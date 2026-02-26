// =============================================================================
// RISC-V M-UNIT UVM TESTBENCH (PRO VERSION)
// Features: Corner Cases, Verbose Mode, Detailed Report, No-License Random
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
`include "uvm_macros.svh"

// -----------------------------------------------------------------------------
// 1. INTERFACE
// -----------------------------------------------------------------------------
interface m_unit_if (input logic clk_i);
    logic        rst_ni;
    // Upstream
    logic        valid_i;
    logic        ready_o;
    m_op_e       op;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    // Downstream
    logic        valid_o;
    logic        ready_i;
    logic [31:0] result_o;
endinterface

// -----------------------------------------------------------------------------
// 2. SEQUENCE ITEM
// -----------------------------------------------------------------------------
class m_unit_item extends uvm_sequence_item;
    rand m_op_e       op;
    rand logic [31:0] operand_a;
    rand logic [31:0] operand_b;
    rand int          delay_cycles; // Delay trước khi gửi lệnh tiếp theo

    logic [31:0]      actual_result;
    logic [31:0]      expected_result;

    `uvm_object_utils(m_unit_item) // Dùng macro đơn giản
    function new(string name = "m_unit_item"); super.new(name); endfunction
endclass

// -----------------------------------------------------------------------------
// 3. SEQUENCE (MANUAL RANDOMIZATION - NO LICENSE REQUIRED)
// -----------------------------------------------------------------------------
class m_unit_rand_sequence extends uvm_sequence #(m_unit_item);
    `uvm_object_utils(m_unit_rand_sequence)
    function new(string name = ""); super.new(name); endfunction
    
    // --- HÀM TẠO DỮ LIỆU BIÊN (CORNER CASES) ---
    function logic [31:0] get_biased_data();
        int dice = $urandom_range(0, 99);
        if (dice < 5)       return 32'h00000000; // 0
        else if (dice < 10) return 32'hFFFFFFFF; // -1
        else if (dice < 15) return 32'h7FFFFFFF; // Max Pos
        else if (dice < 20) return 32'h80000000; // Min Neg
        else                return $urandom();   // Random
    endfunction

    task body();
        // Mảng chứa toàn bộ 8 lệnh của M-Extension
        m_op_e ops[] ;
        int dice;
        ops = '{M_MUL, M_MULH, M_MULHSU, M_MULHU, M_DIV, M_DIVU, M_REM, M_REMU};
        repeat(50000) begin 
            req = m_unit_item::type_id::create("req");
            start_item(req);
            dice = $urandom_range(0, 99);
        // --- (FORCE CORNER CASES) ---
            
            // CASE 1: SIGNED OVERFLOW (2%)   
            //  Opcode là DIV/REM + A là Min Int + B -1
            if (dice < 2) begin
                req.op = ($urandom_range(0, 1) == 0) ? M_DIV : M_REM;
                req.operand_a = 32'h80000000; // -2^31
                req.operand_b = 32'hFFFFFFFF; // -1
            end
            
            // CASE 2: DIVIDE BY ZERO (5%)
            // Random Opcode chia + B bằng 0
            else if (dice < 7) begin
                req.op = ops[$urandom_range(4, 7)]; // DIV, DIVU, REM, REMU
                req.operand_a = get_biased_data();
                req.operand_b = 32'h00000000;
            end
            else begin
            // 1. Random Opcode (Chọn 1 trong 8 lệnh)
            req.op = ops[$urandom_range(0, 7)]; 
            
            // 2. Random Operands (Có Corner Cases)
            req.operand_a = get_biased_data();
            
            // 3. Random Operands (Có Corner Cases)
            req.operand_b = get_biased_data();            
            
            // Avoid too many divide by zero cases
            if (req.operand_b == 0) req.operand_b = 1;
            end
            req.delay_cycles = $urandom_range(0, 2);
            
            finish_item(req);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. DRIVER
// -----------------------------------------------------------------------------
class m_unit_driver extends uvm_driver #(m_unit_item);
    `uvm_component_utils(m_unit_driver)
    virtual m_unit_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual m_unit_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "FATAL: Interface not found!")
    endfunction

    task run_phase(uvm_phase phase);
        int timeout;
        
        // Init signal
        vif.valid_i   <= 0;
        vif.op        <= M_MUL;
        vif.rs1_data  <= 0;
        vif.rs2_data  <= 0;
        
        @(posedge vif.rst_ni); 
        
        forever begin
            seq_item_port.get_next_item(req);
            
            // Random delay giữa các transaction
            repeat(req.delay_cycles) @(posedge vif.clk_i);

            // Drive Input
            vif.valid_i      <= 1'b1;
            vif.op           <= req.op;
            vif.rs1_data     <= req.operand_a;
            vif.rs2_data     <= req.operand_b;

            // Wait for Ready (Handshake)
            timeout = 0;
            do begin
                @(posedge vif.clk_i);
                timeout++;
                if (timeout > 100) `uvm_fatal("DRV", "Timeout waiting for ready_o!")
            end while (vif.ready_o !== 1'b1);

            vif.valid_i <= 1'b0; // Clear valid sau khi handshake xong
            
            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 5. MONITOR
// -----------------------------------------------------------------------------
class m_unit_monitor extends uvm_monitor;
    `uvm_component_utils(m_unit_monitor)
    virtual m_unit_if vif;
    uvm_analysis_port #(m_unit_item) mon_port;
    
    // Queue lưu các lệnh đang xử lý (Pipeline support)
    m_unit_item  pending_tx_q[$]; 

    function new(string name, uvm_component parent);
        super.new(name, parent);
        mon_port = new("mon_port", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual m_unit_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "FATAL: Interface not found")
    endfunction

    // --- GOLDEN PREDICTOR ---
    function logic [31:0] predict_result(m_op_e op, logic [31:0] a, logic [31:0] b);
        logic [63:0] full_mul;
        logic signed [63:0] a_64_s;
        logic signed [63:0] b_64_s;        
        case (op)
            M_MUL:    return a * b;
            M_MULH:   begin full_mul = $signed(a) * $signed(b); return full_mul[63:32]; end
            M_MULHSU: begin 
                        a_64_s = $signed({a[31], a});
                        b_64_s = $unsigned({1'b0, b});
                        full_mul = a_64_s * b_64_s;
                        return full_mul[63:32]; 
            end
            M_MULHU:  begin full_mul = $unsigned(a) * $unsigned(b); return full_mul[63:32]; end
            
            M_DIV:    begin
                        if (b == 0) return -1; 
                        if (a == 32'h80000000 && b == 32'hFFFFFFFF) return 32'h80000000;
                        return $signed(a) / $signed(b);
                      end
            M_DIVU:   begin
                        if (b == 0) return 32'hFFFFFFFF; // Max value
                        return $unsigned(a) / $unsigned(b);
                      end
            
            M_REM:    begin
                        if (b == 0) return a;
                        if (a == 32'h80000000 && b == 32'hFFFFFFFF) return 0;
                        return $signed(a) % $signed(b); 
                      end
            M_REMU:   begin
                        if (b == 0) return a;
                        return $unsigned(a) % $unsigned(b);
                      end
            default:  return 0;
        endcase
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_input();
            monitor_output();
        join
    endtask

    // Bắt đầu vào (Request)
    task monitor_input();
        forever begin
            @(posedge vif.clk_i);
            if (vif.valid_i && vif.ready_o) begin
                m_unit_item item = m_unit_item::type_id::create("item_in");
                item.op = vif.op;
                item.operand_a = vif.rs1_data;
                item.operand_b = vif.rs2_data;
                item.expected_result = predict_result(item.op, item.operand_a, item.operand_b);
                pending_tx_q.push_back(item);
            end
        end
    endtask

    // Bắt đầu ra (Response)
    task monitor_output();
        forever begin
            @(posedge vif.clk_i);
            if (vif.valid_o && vif.ready_i) begin
                m_unit_item item;
                if (pending_tx_q.size() > 0) begin
                    item = pending_tx_q.pop_front();
                    item.actual_result = vif.result_o;
                    mon_port.write(item);
                end else begin
                    `uvm_error("MON", "Unexpected output valid (No pending request)!")
                end
            end
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 6. SCOREBOARD (PRO REPORTING)
// -----------------------------------------------------------------------------
class m_unit_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(m_unit_scoreboard)
    uvm_analysis_imp #(m_unit_item, m_unit_scoreboard) scb_export;

    // --- Statistics ---
    int op_count[m_op_e];
    int cnt_div_zero = 0;
    int cnt_overflow = 0;
    
    bit verbose = 0;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        scb_export = new("scb_export", this);
        if ($test$plusargs("VERBOSE")) verbose = 1;
    endfunction

    function void write(m_unit_item trans);
        string msg;

        // 1. Check Result
        if (trans.actual_result === trans.expected_result) begin
            if (verbose) begin
                msg = $sformatf("[PASS] Op:%-8s A:%h B:%h | Res:%h", 
                                 trans.op.name(), trans.operand_a, trans.operand_b, trans.actual_result);
                $display(msg);
            end
        end else begin
            msg = $sformatf("[FAIL] Op:%-8s A:%h B:%h | Exp:%h Act:%h", 
                      trans.op.name(), trans.operand_a, trans.operand_b, trans.expected_result, trans.actual_result);
            `uvm_error("COMPARE", msg)
        end

        // 2. Statistics Gathering
        if (op_count.exists(trans.op)) op_count[trans.op]++; else op_count[trans.op] = 1;
        
        // Count Div/Rem by Zero
        if ((trans.op inside {M_DIV, M_DIVU, M_REM, M_REMU}) && (trans.operand_b == 0)) 
            cnt_div_zero++;
            
        // Count Overflow (Only for signed DIV/REM)
        if ((trans.op inside {M_DIV, M_REM}) && (trans.operand_a == 32'h80000000 && trans.operand_b == 32'hFFFFFFFF))
            cnt_overflow++;
    endfunction
    
    function void report_phase(uvm_phase phase);
        string name_str;
        $display("\n==================================================");
        $display("          M-UNIT VERIFICATION REPORT              ");
        $display("==================================================");
        
        $display("\n--- 1. OPCODE COVERAGE ---");
        foreach (op_count[i]) begin
             name_str = i.name();
             if (name_str == "") name_str = $sformatf("UNKNOWN(%0d)", i);
             $display("Opcode %-12s : Tested %0d times", name_str, op_count[i]);
        end

        $display("\n--- 2. ROBUSTNESS METRICS ---");
        $display("Divide by Zero Cases  : %0d times", cnt_div_zero);
        $display("Signed Overflow Cases : %0d times", cnt_overflow);
        
        $display("\n==================================================\n");
    endfunction
endclass

// -----------------------------------------------------------------------------
// 7. AGENT - ENV - TEST
// -----------------------------------------------------------------------------
class m_unit_agent extends uvm_agent;
    `uvm_component_utils(m_unit_agent)
    m_unit_driver    driver;
    m_unit_monitor   monitor;
    uvm_sequencer #(m_unit_item) sequencer;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver    = m_unit_driver::type_id::create("driver", this);
        monitor   = m_unit_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer#(m_unit_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

class m_unit_env extends uvm_env;
    `uvm_component_utils(m_unit_env)
    m_unit_agent    agent;
    m_unit_scoreboard scb;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = m_unit_agent::type_id::create("agent", this);
        scb   = m_unit_scoreboard::type_id::create("scb", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        agent.monitor.mon_port.connect(scb.scb_export);
    endfunction
endclass

class m_unit_test extends uvm_test;
    `uvm_component_utils(m_unit_test)
    m_unit_env env;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = m_unit_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        m_unit_rand_sequence seq;
        seq = m_unit_rand_sequence::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        #1000; // Chờ cho pipeline clear hết lệnh cuối
        phase.drop_objection(this);
    endtask
endclass

// -----------------------------------------------------------------------------
// 8. TOP MODULE
// -----------------------------------------------------------------------------
module tb_top;
    import uvm_pkg::*;
    import riscv_32im_pkg::*;

    bit clk; always #5 clk = ~clk; // 100MHz

    m_unit_if vif(clk);

    // Map Interface -> Struct Input cho DUT
    m_in_t dut_input_struct;
    assign dut_input_struct.op  = vif.op;
    assign dut_input_struct.a_i = vif.rs1_data;
    assign dut_input_struct.b_i = vif.rs2_data;

    // Instantiate DUT
    riscv_m_unit dut (
        .clk        (clk),
        .rst        (~vif.rst_ni),
        .valid_i    (vif.valid_i),
        .ready_o    (vif.ready_o),
        .m_in       (dut_input_struct),
        .valid_o    (vif.valid_o),
        .ready_i    (vif.ready_i),
        .result_o   (vif.result_o)
    );

    // Back-pressure Simulation: Random ready_i để test khả năng stall của M-Unit
    initial begin
        vif.ready_i = 1;
        forever begin
            @(negedge clk);
            // 80% thời gian sẵn sàng, 20% stall
            vif.ready_i = ($urandom_range(0, 9) < 8); 
        end
    end

    initial begin
        vif.rst_ni = 0; 
        uvm_config_db#(virtual m_unit_if)::set(null, "*", "vif", vif);
        run_test("m_unit_test"); 
    end

    initial begin
        #20 vif.rst_ni = 1; 
    end
endmodule