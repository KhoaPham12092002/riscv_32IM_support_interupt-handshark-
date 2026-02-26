// =============================================================================
// FILE: tb_alu.sv (STRICT UVM COMPLIANCE)
// =============================================================================
`timescale 1ns/1ps

// Import gói toàn cục
import uvm_pkg::*;
import riscv_32im_pkg::*; 
`include "uvm_macros.svh"

// -----------------------------------------------------------------------------
// 1. INTERFACE
// -----------------------------------------------------------------------------
interface alu_if(input logic clk);
    logic [3:0]  op; 
    logic [31:0] a;
    logic [31:0] b;
    logic [31:0] result;
    logic        zero;
endinterface

// -----------------------------------------------------------------------------
// 2. SEQUENCE ITEM & SEQUENCE
// -----------------------------------------------------------------------------
class alu_item extends uvm_sequence_item;
    rand logic [3:0]  op; 
    rand logic [31:0] a;
    rand logic [31:0] b;
    logic [31:0] actual_result;
    logic        actual_zero;

    `uvm_object_utils_begin(alu_item)
        `uvm_field_int(op, UVM_DEFAULT)
        `uvm_field_int(a,  UVM_DEFAULT)
        `uvm_field_int(b,  UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "alu_item"); super.new(name); endfunction
endclass

class alu_random_seq extends uvm_sequence #(alu_item);
    `uvm_object_utils(alu_random_seq)
    function new(string name=""); super.new(name); endfunction

    // --- SUPPORT FUNCTION: SIMULATION "CONSTRAINT DIST" --- BEACAU I'M POOR DON'T HAVE LICENSE
    function logic [31:0] get_biased_data();
        int dice;
        dice = $urandom_range(0, 99); // Gieo xúc xắc từ 0 đến 99 (100 số)

        if (dice < 5)       return 32'h00000000; // 0-4 (5%): Số 0
        else if (dice < 10) return 32'hFFFFFFFF; // 5-9 (5%): Số -1 (All 1s)
        else if (dice < 15) return 32'h7FFFFFFF; // 10-14 (5%): Max Dương
        else if (dice < 20) return 32'h80000000; // 15-19 (5%): Min Âm (Max Neg)
        else                return $urandom();   // 20-99 (80%): Số ngẫu nhiên thường
    endfunction
    task body();
        alu_op_e valid_ops[] = '{
            ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
            ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND, 
            ALU_B // Giá trị 15
        };
        int rand_idx;
        repeat(50000) begin
            req = alu_item::type_id::create("req");
            start_item(req);
            req.a = get_biased_data();
            req.b = get_biased_data();
            rand_idx = $urandom_range(0, valid_ops.size() - 1);
            req.op = valid_ops[rand_idx];
            finish_item(req);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 3. DRIVER
// -----------------------------------------------------------------------------
class alu_driver extends uvm_driver #(alu_item);
    `uvm_component_utils(alu_driver)
    virtual alu_if vif;

    // [FIX] Constructor chuẩn: (string name, uvm_component parent)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // [FIX] Phase chuẩn: (uvm_phase phase) - KHÔNG ĐƯỢC DÙNG 'p'
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual alu_if)::get(this, "", "vif", vif)) `uvm_fatal("DRV", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            vif.a  <= req.a; vif.b  <= req.b; vif.op <= req.op;
            @(posedge vif.clk);
            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. MONITOR
// -----------------------------------------------------------------------------
class alu_monitor extends uvm_monitor;
    `uvm_component_utils(alu_monitor)
    virtual alu_if vif;
    uvm_analysis_port #(alu_item) mon_ap;
    alu_item req; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_ap = new("mon_ap", this);
        if(!uvm_config_db#(virtual alu_if)::get(this, "", "vif", vif)) `uvm_fatal("MON", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk); #1;
            req = alu_item::type_id::create("pkt");
            req.a = vif.a; req.b = vif.b; req.op = vif.op;
            req.actual_result = vif.result; req.actual_zero = vif.zero;
            mon_ap.write(req);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 5. SCOREBOARD
// -----------------------------------------------------------------------------
class alu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(alu_scoreboard)
    uvm_analysis_imp #(alu_item, alu_scoreboard) sb_export;
    
    int op_count[alu_op_e]; 
    string       msg;
    int cnt_a_zero = 0;
    int cnt_b_zero = 0;
    int cnt_a_max  = 0; // Toàn 1
    int cnt_b_max  = 0;
    int cnt_a_neg  = 0; // Số âm
    int cnt_b_neg  = 0;
    int cnt_zero_flag = 0; // Kết quả = 0


    // --- BIẾN ĐIỀU KHIỂN LOG ---
    bit verbose = 0; // Mặc định = 0 (Tắt in chi tiết từng lệnh)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sb_export = new("sb_export", this);
        // --- KIỂM TRA THAM SỐ TỪ COMMAND LINE ---
        if ($test$plusargs("VERBOSE")) begin
            verbose = 1;
            `uvm_info("SCB", "DEBUG MODE: ENABLED (Printing per-instruction checks)", UVM_LOW)
        end
    endfunction

    function void write(alu_item pkt);
        logic [31:0] expected_result;
        alu_op_e     op_enum;
        
        op_enum = alu_op_e'(pkt.op);

        case (op_enum)
            ALU_ADD:  expected_result = pkt.a + pkt.b;
            ALU_SUB:  expected_result = pkt.a - pkt.b;
            ALU_SLL:  expected_result = pkt.a << pkt.b[4:0];
            ALU_SRL:  expected_result = pkt.a >> pkt.b[4:0];
            ALU_SRA:  expected_result = $signed(pkt.a) >>> pkt.b[4:0];
            ALU_SLT:  expected_result = ($signed(pkt.a) < $signed(pkt.b)) ? 32'd1 : 32'd0;
            ALU_SLTU: expected_result = (pkt.a < pkt.b) ? 32'd1 : 32'd0;
            ALU_XOR:  expected_result = pkt.a ^ pkt.b;
            ALU_OR:   expected_result = pkt.a | pkt.b;
            ALU_AND:  expected_result = pkt.a & pkt.b;
            ALU_B:    expected_result = pkt.b;
            default:  expected_result = 32'd0;
        endcase

        if (pkt.actual_result !== expected_result) begin
            `uvm_error("FAIL", $sformatf("Op:%s A:%h B:%h Exp:%h Act:%h", 
                op_enum.name(), pkt.a, pkt.b, expected_result, pkt.actual_result))
        end
        else begin
            // --- TRƯỜNG HỢP PASS (CHỈ IN NẾU VERBOSE = 1) ---
            if (verbose) begin
                msg = $sformatf("[PASS] Op:%-10s | A:%h | B:%h | Res:%h", 
                                 op_enum.name(), pkt.a, pkt.b, expected_result);
                $display(msg); // Dùng $display cho gọn, không rác log
            end
        end

        if (op_count.exists(op_enum)) op_count[op_enum]++; else op_count[op_enum] = 1;
        if (pkt.a == 0) cnt_a_zero++;
        if (pkt.b == 0) cnt_b_zero++;
        if (pkt.a == 32'hFFFFFFFF) cnt_a_max++; 
        if (pkt.b == 32'hFFFFFFFF) cnt_b_max++;
        if (pkt.a[31] == 1) cnt_a_neg++; // Bit dấu = 1
        if (pkt.b[31] == 1) cnt_b_neg++;
        if (expected_result == 0) cnt_zero_flag++;        
            
    endfunction

    /*
    function void report_phase(uvm_phase phase);
       /* 
        `uvm_info("COV", "--------------------------------------------------", UVM_LOW)
        `uvm_info("COV", "          MANUAL COVERAGE REPORT                  ", UVM_LOW)
        `uvm_info("COV", "--------------------------------------------------", UVM_LOW)
        foreach (op_count[i]) begin
             `uvm_info("COV", $sformatf("Opcode %-8s : Tested %0d times", i.name(), op_count[i]), UVM_LOW)
        end
        `uvm_info("COV", "--------------------------------------------------", UVM_LOW)
    
        $display(""); // Xuống dòng cho thoáng
        $display("--------------------------------------------------");
        $display("          MANUAL COVERAGE REPORT                  ");
        $display("--------------------------------------------------");
        
        foreach (op_count[i]) begin
             // %-10s: Căn lề trái 10 ký tự cho tên Opcode thẳng hàng
             $display("Opcode %-10s : Tested %0d times", i.name(), op_count[i]);
        end
        
        $display("--------------------------------------------------");
        $display("");
        endfunction
    */
    
        function void report_phase(uvm_phase phase);
        string name_str; // Biến tạm để xử lý lỗi tên rỗng

        $display("\n==================================================");
        $display("          ALU VERIFICATION REPORT           ");
        $display("==================================================");
        
        $display("\n--- 1. OPCODE COVERAGE ---");
        foreach (op_count[i]) begin
             // Fix lỗi hiển thị: Nếu name() rỗng thì in Unknown
             name_str = i.name();
             if (name_str == "") name_str = $sformatf("UNKNOWN(%0d)", i);
             
             $display("Opcode %-12s : Tested %0d times", name_str, op_count[i]);
        end
        $display("(Note: MUL/DIV are in M-Unit, not tested here)");

        $display("\n--- 2. DATA CORNER CASES (QUALITY CHECK) ---");
        $display("Operand A = 0        : %0d times", cnt_a_zero);
        $display("Operand B = 0        : %0d times", cnt_b_zero);
        $display("Operand A = -1 (All 1): %0d times", cnt_a_max);
        $display("Operand B = -1 (All 1): %0d times", cnt_b_max);
        $display("Operand A is Negative : %0d times", cnt_a_neg);
        $display("Result is ZERO        : %0d times", cnt_zero_flag);
        
        $display("\n==================================================\n");
    endfunction    
endclass

// -----------------------------------------------------------------------------
// 6. AGENT & ENV (PHASE NAME FIXED)
// -----------------------------------------------------------------------------
class alu_agent extends uvm_agent;
    `uvm_component_utils(alu_agent)
    alu_driver drv; alu_monitor mon; uvm_sequencer #(alu_item) sqr;
    
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        drv = alu_driver::type_id::create("drv", this);
        mon = alu_monitor::type_id::create("mon", this);
        sqr = uvm_sequencer#(alu_item)::type_id::create("sqr", this);
    endfunction
    
    function void connect_phase(uvm_phase phase); 
        drv.seq_item_port.connect(sqr.seq_item_export); 
    endfunction
endclass

class alu_env extends uvm_env;
    `uvm_component_utils(alu_env)
    alu_agent agent; 
    alu_scoreboard scb;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = alu_agent::type_id::create("agent", this);
        scb   = alu_scoreboard::type_id::create("scb", this);
    endfunction
    
    function void connect_phase(uvm_phase phase); 
        agent.mon.mon_ap.connect(scb.sb_export); 
    endfunction
endclass

class alu_test extends uvm_test;
    `uvm_component_utils(alu_test)
    alu_env env;
    
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase); 
        env = alu_env::type_id::create("env", this); 
    endfunction
    
    task run_phase(uvm_phase phase);
        alu_random_seq seq = alu_random_seq::type_id::create("seq");
        phase.raise_objection(this); 
        seq.start(env.agent.sqr); 
        phase.drop_objection(this);
    endtask
endclass

// -----------------------------------------------------------------------------
// 7. TOP (ĐÃ THÊM IMPORT)
// -----------------------------------------------------------------------------
module tb_alu_top;
    // [FIX] Import UVM pkg trong Module scope để fix lỗi 'Undefined uvm_config_db'
    import uvm_pkg::*;
    import riscv_32im_pkg::*; // Để hiểu alu_op_e

    logic clk; always #5 clk = ~clk; 
    alu_if vif(clk);
    
    alu_in_t dut_in;
    assign dut_in.op = alu_op_e'(vif.op);
    assign dut_in.a  = vif.a;
    assign dut_in.b  = vif.b;

    alu dut (
        .alu_in  (dut_in),
        .Zero    (vif.zero),
        .alu_o   (vif.result),
        .vaild_o (), .ready_o ()
    );

    initial begin
        clk=0;
        uvm_config_db#(virtual alu_if)::set(null, "*", "vif", vif);
        run_test("alu_test");
    end
endmodule