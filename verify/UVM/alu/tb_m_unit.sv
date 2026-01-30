// =============================================================================
// RISC-V M-UNIT UVM TESTBENCH (FIXED SIGNED MATH)
// =============================================================================

import uvm_pkg::*;
`include "uvm_macros.svh"
import riscv_32im_pkg::*; 

// -----------------------------------------------------------------------------
// 1. INTERFACE
// -----------------------------------------------------------------------------
interface m_unit_if (input logic clk_i);
    logic        rst_ni;
    
    // Upstream
    logic        valid_i;
    logic        ready_o;
    
    // Explicit Signals mapped from Driver
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
    rand int          delay_cycles;

    logic [31:0]      actual_result;
    logic [31:0]      expected_result;

    `uvm_object_utils_begin(m_unit_item)
        `uvm_field_enum(m_op_e, op, UVM_DEFAULT)
        `uvm_field_int(operand_a, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(operand_b, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(actual_result, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(expected_result, UVM_DEFAULT | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "m_unit_item"); super.new(name); endfunction
endclass

// -----------------------------------------------------------------------------
// 3. DRIVER
// -----------------------------------------------------------------------------
class m_unit_driver extends uvm_driver #(m_unit_item);
    `uvm_component_utils(m_unit_driver)
    virtual m_unit_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual m_unit_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "FATAL: Interface not found!")
    endfunction

    task run_phase(uvm_phase phase);
        vif.valid_i   <= 0;
        vif.op        <= M_MUL;
        vif.rs1_data  <= 0;
        vif.rs2_data  <= 0;
        
        @(posedge vif.rst_ni); 
        
        forever begin
            seq_item_port.get_next_item(req);
            
            repeat(req.delay_cycles) @(posedge vif.clk_i);

            vif.valid_i      <= 1'b1;
            vif.op           <= req.op;
            vif.rs1_data     <= req.operand_a;
            vif.rs2_data     <= req.operand_b;

            do begin
                @(posedge vif.clk_i);
            end while (vif.ready_o !== 1'b1);

            vif.valid_i <= 1'b0;
            
            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. MONITOR (THE FIX IS HERE)
// -----------------------------------------------------------------------------
class m_unit_monitor extends uvm_monitor;
    `uvm_component_utils(m_unit_monitor)
    virtual m_unit_if vif;
    uvm_analysis_port #(m_unit_item) mon_port;
    
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

    // --- GOLDEN PREDICTOR (STRICTLY TYPED) ---
    function logic [31:0] predict_result(m_op_e op, logic [31:0] a, logic [31:0] b);
        logic [63:0] full_mul;
        
        // Ép kiểu tường minh (Explicit Casting)
        // SystemVerilog $signed() coi bit cao nhất là bit dấu
        
        case (op)
            // --- MULTIPLICATION ---
            M_MUL:    return a * b; // Lower 32 bits same for signed/unsigned
            M_MULH:   begin 
                        full_mul = $signed(a) * $signed(b); 
                        return full_mul[63:32]; 
                      end
            M_MULHSU: begin 
                        full_mul = $signed(a) * $unsigned(b); 
                        return full_mul[63:32]; 
                      end
            M_MULHU:  begin 
                        full_mul = $unsigned(a) * $unsigned(b); 
                        return full_mul[63:32]; 
                      end
            
            // --- DIVISION ---
            M_DIV:    begin
                        if (b == 0) return -1; // Div by 0
                        if (a == 32'h80000000 && b == 32'hFFFFFFFF) return 32'h80000000; // Overflow
                        return $signed(a) / $signed(b);
                      end
            M_DIVU:   begin
                        if (b == 0) return -1; // Div by 0 -> All 1s
                        return $unsigned(a) / $unsigned(b);
                      end
            
            // --- REMAINDER ---
            M_REM:    begin
                        if (b == 0) return a; // Rem by 0 -> Dividend
                        if (a == 32'h80000000 && b == 32'hFFFFFFFF) return 0; // Overflow case
                        // Toán tử % trong SV trả về dấu giống số bị chia (Dividend)
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

    task monitor_input();
        forever begin
            @(posedge vif.clk_i);
            if (vif.valid_i && vif.ready_o) begin
                m_unit_item item = m_unit_item::type_id::create("item_in");
                item.op = vif.op;
                item.operand_a = vif.rs1_data;
                item.operand_b = vif.rs2_data;
                
                // Gọi hàm dự đoán đã sửa
                item.expected_result = predict_result(item.op, item.operand_a, item.operand_b);
                
                pending_tx_q.push_back(item);
            end
        end
    endtask

    task monitor_output();
        forever begin
            @(posedge vif.clk_i);
            if (vif.valid_o && vif.ready_i) begin
                m_unit_item item;
                if (pending_tx_q.size() > 0) begin
                    item = pending_tx_q.pop_front();
                    item.actual_result = vif.result_o;
                    mon_port.write(item);
                end
            end
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 5. SCOREBOARD
// -----------------------------------------------------------------------------
class m_unit_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(m_unit_scoreboard)
    uvm_analysis_imp #(m_unit_item, m_unit_scoreboard) scb_export;

    int match_count = 0;
    int mismatch_count = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        scb_export = new("scb_export", this);
    endfunction

function void write(m_unit_item trans);
        if (trans.actual_result === trans.expected_result) begin
            // IN RA MÀN HÌNH KHI PASS
            $display("[SCB-PASS] Op=%-6s A=%h B=%h | Exp=%h Act=%h", 
                      trans.op.name(), trans.operand_a, trans.operand_b, trans.expected_result, trans.actual_result);
            match_count++;
        end else begin
            `uvm_error("SCB", $sformatf("FAIL: Op=%s A=%h B=%h | Exp=%h Act=%h", 
                      trans.op.name(), trans.operand_a, trans.operand_b, trans.expected_result, trans.actual_result))
            mismatch_count++;
        end
    endfunction
    
    function void report_phase(uvm_phase phase);
        $display("\n========================================");
        $display("SCOREBOARD REPORT");
        $display("Matches:    %0d", match_count);
        $display("Mismatches: %0d", mismatch_count);
        $display("========================================\n");
    endfunction
endclass

// -----------------------------------------------------------------------------
// 6. AGENT, ENV, TEST (Standard)
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

class m_unit_rand_sequence extends uvm_sequence #(m_unit_item);
    `uvm_object_utils(m_unit_rand_sequence)
    function new(string name = ""); super.new(name); endfunction
    
    task body();
        m_op_e ops[] = {M_MUL, M_MULH, M_DIV, M_REM}; 
        repeat(55000) begin // Tăng số lượng test lên 500 để cover hết case
            req = m_unit_item::type_id::create("req");
            start_item(req);
            req.op = ops[$urandom_range(0, 3)]; 
            req.operand_a = $urandom();
            req.operand_b = $urandom();
            if ($urandom_range(0, 50) == 0) req.operand_b = 0; // Test chia 0
            req.delay_cycles = $urandom_range(0, 2);
            finish_item(req);
        end
    endtask
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
        #500; 
        phase.drop_objection(this);
    endtask
endclass

// -----------------------------------------------------------------------------
// 7. TOP MODULE (BRIDGE)
// -----------------------------------------------------------------------------
module tb_top;
    import uvm_pkg::*;
    import riscv_32im_pkg::*;

    bit clk;
    always #5 clk = ~clk;

    m_unit_if vif(clk);

    // --- CẦU NỐI STRUCT ---
    m_in_t dut_input_struct;
    assign dut_input_struct.op  = vif.op;
    assign dut_input_struct.a_i = vif.rs1_data;
    assign dut_input_struct.b_i = vif.rs2_data;

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

    // Back-pressure Simulation
    initial begin
        vif.ready_i = 1;
        forever begin
            @(negedge clk);
            vif.ready_i = ($urandom_range(0, 9) < 8); 
        end
    end

    // --- UVM STARTUP & RESET ---
    initial begin
        vif.rst_ni = 0; 
        uvm_config_db#(virtual m_unit_if)::set(null, "*", "vif", vif);
        run_test("m_unit_test"); 
    end

    initial begin
        vif.rst_ni = 0;
        #20;
        vif.rst_ni = 1; 
    end

initial begin
        $display("\n=========================================================================");
        $display(" Time      | V_in R_out |   Op   |     A    |     B    | V_out R_in |   Res  ");
        $display("-----------+------------+--------+----------+----------+------------+--------");
        
        // $monitor tự động in mỗi khi tín hiệu thay đổi
        $monitor("%9t |  %b    %b   | %6s | %h | %h |  %b    %b   | %h",
                 $time, 
                 vif.valid_i, vif.ready_o,
                 get_op_name(vif.op), 
                 vif.rs1_data, vif.rs2_data,
                 vif.valid_o, vif.ready_i,
                 vif.result_o
        );
    end

    // Helper function để in tên Opcode cho đẹp
    function string get_op_name(m_op_e op);
        case(op)
            M_MUL: return "MUL"; M_MULH: return "MULH"; 
            M_MULHSU: return "MULHSU"; M_MULHU: return "MULHU";
            M_DIV: return "DIV"; M_DIVU: return "DIVU";
            M_REM: return "REM"; M_REMU: return "REMU";
            default: return "OTHER";
        endcase
    endfunction
endmodule