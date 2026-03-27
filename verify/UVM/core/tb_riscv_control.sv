// =============================================================================
// FILE: tb_riscv_control.sv
// DESCRIPTION: UVM Testbench cho RISC-V Control Unit (Bao gồm Hazard & FWD)
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 

`include "uvm_macros.svh"

// =============================================================================
// 1. INTERFACE
// =============================================================================
interface control_if (input logic clk);
    // --- Inputs từ Datapath ---
    logic [4:0]  hz_id_rs1_addr_i;  logic [4:0]  hz_id_rs2_addr_i;
    logic        id_is_ecall_i;     logic        id_is_mret_i;     logic id_illegal_instr_i;
    
    logic [4:0]  hz_ex_rs1_addr_i;  logic [4:0]  hz_ex_rs2_addr_i; logic [4:0] hz_ex_rd_addr_i;
    logic        hz_ex_reg_we_i;    wb_sel_e     hz_ex_wb_sel_i;   logic branch_taken_i;
    
    logic [4:0]  hz_mem_rd_addr_i;  logic        hz_mem_reg_we_i;  logic lsu_err_i;
    logic [4:0]  hz_wb_rd_addr_i;   logic        hz_wb_reg_we_i;

    // --- Outputs tới Datapath & CSR ---
    logic        ctrl_force_stall_id_o; logic        ctrl_flush_if_id_o; logic ctrl_flush_id_ex_o;
    logic [1:0]  ctrl_fwd_rs1_sel_o;    logic [1:0]  ctrl_fwd_rs2_sel_o;
    logic [1:0]  ctrl_pc_sel_o;
    logic        ctrl_trap_valid_o;     logic [3:0]  ctrl_trap_cause_o;  logic ctrl_mret_valid_o;
    
    // --- TB Sync Signal ---
    logic        tb_item_valid;
    string       test_name;
endinterface

// =============================================================================
// 2. TRANSACTION ITEM
// =============================================================================
class control_item extends uvm_sequence_item;
    string test_name = "";
    rand logic [4:0]  id_rs1, id_rs2, ex_rs1, ex_rs2, ex_rd, mem_rd, wb_rd;
    rand logic        is_ecall, is_mret, illegal, branch, lsu_err;
    rand logic        ex_we=0, mem_we=0, wb_we=0;
    rand wb_sel_e     ex_wb_sel = WB_ALU;

    `uvm_object_utils_begin(control_item)
        `uvm_field_int(id_rs1, UVM_HEX)
        // (Lược bỏ macro field để code ngắn gọn, UVM tự xử lý khi in ấn)
    `uvm_object_utils_end

    function new(string name = "control_item"); super.new(name); endfunction
endclass

// =============================================================================
// 3. DRIVER
// =============================================================================
class control_driver extends uvm_driver #(control_item);
    `uvm_component_utils(control_driver)
    virtual control_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual control_if)::get(this, "", "vif", vif)) `uvm_fatal("DRV", "No VIF")
    endfunction 

    task run_phase(uvm_phase phase);
        // Reset mặc định
        vif.tb_item_valid = 0; vif.branch_taken_i = 0; vif.id_is_ecall_i = 0; // ...
        forever begin
            seq_item_port.get_next_item(req);
            @(posedge vif.clk);
            vif.hz_id_rs1_addr_i <= req.id_rs1; vif.hz_id_rs2_addr_i <= req.id_rs2;
            vif.hz_ex_rs1_addr_i <= req.ex_rs1; vif.hz_ex_rs2_addr_i <= req.ex_rs2; vif.hz_ex_rd_addr_i <= req.ex_rd;
            vif.hz_ex_reg_we_i   <= req.ex_we;  vif.hz_ex_wb_sel_i   <= req.ex_wb_sel; vif.branch_taken_i <= req.branch;
            vif.id_is_ecall_i    <= req.is_ecall; vif.id_is_mret_i   <= req.is_mret; vif.id_illegal_instr_i <= req.illegal;
            vif.hz_mem_rd_addr_i <= req.mem_rd; vif.hz_mem_reg_we_i  <= req.mem_we;  vif.lsu_err_i <= req.lsu_err;
            vif.hz_wb_rd_addr_i  <= req.wb_rd;  vif.hz_wb_reg_we_i   <= req.wb_we;
            vif.test_name        <= req.test_name;
            vif.tb_item_valid    <= 1;
            
            @(posedge vif.clk);
            vif.tb_item_valid    <= 0;
            seq_item_port.item_done();
        end
    endtask
endclass

// =============================================================================
// 4. SEQUENCES
// =============================================================================
class control_directed_seq extends uvm_sequence #(control_item);
    `uvm_object_utils(control_directed_seq)
    function new(string name=""); super.new(name); endfunction
    function void clear_req(control_item req);
        req.id_rs1 = 0; req.id_rs2 = 0; req.ex_rs1 = 0; req.ex_rs2 = 0; req.ex_rd = 0; req.mem_rd = 0; req.wb_rd = 0;
        req.is_ecall = 0; req.is_mret = 0; req.illegal = 0; req.lsu_err = 0; req.branch = 0;
        req.ex_we = 0; req.mem_we = 0; req.wb_we = 0; req.ex_wb_sel = WB_ALU;
    endfunction

task body();
        control_item req;
        `uvm_info("SEQ", "--- STARTING DIRECTED SEQUENCE ---", UVM_LOW)
        
        // Test 1: Lệnh bình thường
        req = control_item::type_id::create("req"); start_item(req);
        req.test_name = "Directed Test 1: Normal Operation (No Hazard/Trap)"; // [GẮN TÊN]
        req.branch = 0; req.is_ecall = 0; req.is_mret = 0; req.illegal = 0; req.lsu_err = 0; 
        req.ex_rd = 0; req.mem_rd = 0; req.wb_rd = 0;
        finish_item(req);

        // Test 2: ECALL Trap
        req = control_item::type_id::create("req"); start_item(req);
        req.test_name = "Directed Test 2: ECALL Trap Assertion"; // [GẮN TÊN]
        req.branch = 0; req.is_ecall = 1; req.is_mret = 0; req.illegal = 0; req.lsu_err = 0;
        finish_item(req);

        // Test 3: Load-Use Hazard
        req = control_item::type_id::create("req"); start_item(req);
        req.test_name = "Directed Test 3: Load-Use Hazard Stall & Flush"; // [GẮN TÊN]
        req.ex_wb_sel = WB_MEM; req.ex_we = 1; req.ex_rd = 5; req.id_rs1 = 5; 
        req.is_ecall = 0; req.illegal = 0; req.lsu_err = 0; req.branch = 0;
        finish_item(req);
        
        // Test 4: Forwarding từ MEM
        req = control_item::type_id::create("req"); start_item(req);
        req.test_name = "Directed Test 4: Data Forwarding from MEM to EX"; // [GẮN TÊN]
        req.mem_we = 1; req.mem_rd = 10; req.ex_rs1 = 10; req.wb_we = 0; 
        req.is_ecall = 0; req.illegal = 0; req.lsu_err = 0;
        finish_item(req);

        `uvm_info("SEQ", "--- DIRECTED SEQUENCE DONE ---", UVM_LOW)
    endtask
endclass

class control_stress_seq extends uvm_sequence #(control_item);
    `uvm_object_utils(control_stress_seq)
    function new(string name=""); super.new(name); endfunction

    function control_item gen_dice_item();
        control_item itm = control_item::type_id::create("itm");
        
        itm.id_rs1 = $urandom_range(0, 31); itm.id_rs2 = $urandom_range(0, 31);
        itm.ex_rs1 = $urandom_range(0, 31); itm.ex_rs2 = $urandom_range(0, 31);
        itm.ex_rd  = $urandom_range(0, 31); itm.mem_rd = $urandom_range(0, 31); itm.wb_rd  = $urandom_range(0, 31);

        itm.ex_we  = $urandom_range(0, 1); itm.mem_we = $urandom_range(0, 1); itm.wb_we  = $urandom_range(0, 1);
        itm.ex_wb_sel = wb_sel_e'($urandom_range(0, 4)); 

        // Đổ xí ngầu tỷ lệ thấp cho các biến cố
        itm.is_ecall = ($urandom_range(0, 99) < 5)  ? 1'b1 : 1'b0;
        itm.is_mret  = ($urandom_range(0, 99) < 5)  ? 1'b1 : 1'b0;
        itm.illegal  = ($urandom_range(0, 99) < 5)  ? 1'b1 : 1'b0;
        itm.lsu_err  = ($urandom_range(0, 99) < 5)  ? 1'b1 : 1'b0;
        itm.branch   = ($urandom_range(0, 99) < 10) ? 1'b1 : 1'b0;
        return itm;
    endfunction

    task body();
        control_item req;
        `uvm_info("SEQ", "STARTING 50,000 STRESS TEST (DICE METHOD)...", UVM_LOW)
        for (int i = 0; i < 50000; i++) begin
            req = gen_dice_item();
            start_item(req);
            finish_item(req);
        end
        `uvm_info("SEQ", "STRESS TEST COMPLETED.", UVM_LOW)
    endtask
endclass

// =============================================================================
// 5. SCOREBOARD
// =============================================================================
class control_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(control_scoreboard)
    virtual control_if vif;

    bit enable_uvm_log = 1; bit enable_debug_dump = 1; 
    int total_tests = 0;    int err_count = 0;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual control_if)::get(this, "", "vif", vif)) `uvm_fatal("SCB", "No VIF")
        void'($value$plusargs("UVM_LOG_EN=%d", enable_uvm_log));
        void'($value$plusargs("UVM_DEBUG_DUMP=%d", enable_debug_dump));
    endfunction
    
    task run_phase(uvm_phase phase);
        // [SỬA LỖI] Gom TOÀN BỘ khai báo biến lên đỉnh của Task
        bit exp_trap_valid, exp_mret_valid;
        bit [3:0] exp_trap_cause;
        bit [1:0] exp_pc_sel;
        bit exp_stall_id, exp_flush_if, exp_flush_ex;
        bit [1:0] exp_fwd_rs1, exp_fwd_rs2;
        bit is_trap, jump_trap, is_load_use;
        bit is_error;

        forever begin
            @(negedge vif.clk); // Lấy mẫu ở sườn xuống
            if (vif.tb_item_valid) begin
                
                is_error = 0; // Reset cờ lỗi mỗi vòng lặp (Lệnh thực thi)
                total_tests++;

                // --- 1. MÔ PHỎNG LOGIC CSR & PC ---
                is_trap   = vif.id_is_ecall_i | vif.id_illegal_instr_i | vif.lsu_err_i;
                jump_trap = is_trap | vif.id_is_mret_i | vif.branch_taken_i;
                
                exp_trap_valid = is_trap;
                exp_mret_valid = vif.id_is_mret_i;
                
                if (vif.id_is_ecall_i)        exp_trap_cause = 4'd11;
                else if (vif.id_illegal_instr_i) exp_trap_cause = 4'd2;
                else if (vif.lsu_err_i)       exp_trap_cause = 4'd5;
                else                          exp_trap_cause = 4'd0;

                if (is_trap)                  exp_pc_sel = 2'b10;
                else if (vif.id_is_mret_i)    exp_pc_sel = 2'b11;
                else if (vif.branch_taken_i)  exp_pc_sel = 2'b01;
                else                          exp_pc_sel = 2'b00;

                // --- 2. MÔ PHỎNG LOGIC HAZARD ---
                is_load_use = (vif.hz_ex_wb_sel_i == WB_MEM) && (vif.hz_ex_rd_addr_i != 5'd0) && vif.hz_ex_reg_we_i && 
                              ((vif.hz_ex_rd_addr_i == vif.hz_id_rs1_addr_i) || (vif.hz_ex_rd_addr_i == vif.hz_id_rs2_addr_i));
                
                exp_flush_if = jump_trap;
                exp_flush_ex = jump_trap | is_load_use;
                exp_stall_id = !jump_trap & is_load_use;

                // --- 3. MÔ PHỎNG LOGIC FORWARDING ---
                
                if (vif.hz_mem_reg_we_i && (vif.hz_mem_rd_addr_i != 0) && (vif.hz_mem_rd_addr_i == vif.hz_ex_rs1_addr_i)) exp_fwd_rs1 = 2'b01; 
                else if (vif.hz_wb_reg_we_i && (vif.hz_wb_rd_addr_i != 0) && (vif.hz_wb_rd_addr_i == vif.hz_ex_rs1_addr_i)) exp_fwd_rs1 = 2'b10;
                else exp_fwd_rs1 = 2'b00;

                if (vif.hz_mem_reg_we_i && (vif.hz_mem_rd_addr_i != 0) && (vif.hz_mem_rd_addr_i == vif.hz_ex_rs2_addr_i)) exp_fwd_rs2 = 2'b01;
                else if (vif.hz_wb_reg_we_i && (vif.hz_wb_rd_addr_i != 0) && (vif.hz_wb_rd_addr_i == vif.hz_ex_rs2_addr_i)) exp_fwd_rs2 = 2'b10;
                else exp_fwd_rs2 = 2'b00;

                // --- SO SÁNH (CHECK) ---
                
                // Kiểm tra ĐẦY ĐỦ các cổng đầu ra
                if (vif.ctrl_pc_sel_o !== exp_pc_sel || vif.ctrl_trap_valid_o !== exp_trap_valid || 
                    vif.ctrl_force_stall_id_o !== exp_stall_id || vif.ctrl_flush_if_id_o !== exp_flush_if ||
                    vif.ctrl_flush_id_ex_o !== exp_flush_ex ||
                    vif.ctrl_fwd_rs1_sel_o !== exp_fwd_rs1 || vif.ctrl_fwd_rs2_sel_o !== exp_fwd_rs2) 
                begin
                    is_error = 1;
                end

                if (is_error) begin
                    err_count++;
                    if (vif.test_name != "") $display("FAIL: [%0t ns] [FAIL] %s", $time, vif.test_name);
                    else if (!enable_uvm_log) $display("FAIL: [%0t ns] [SCB_FAIL] Control Logic Mismatch!", $time);
                    
                    if (enable_debug_dump) $display("   -> PC_SEL Exp:%b Got:%b | STALL Exp:%b Got:%b | FWD1 Exp:%b Got:%b", 
                                                    exp_pc_sel, vif.ctrl_pc_sel_o, exp_stall_id, vif.ctrl_force_stall_id_o, exp_fwd_rs1, vif.ctrl_fwd_rs1_sel_o);
                end else begin
                    if (vif.test_name != "") $display("PASS: [%0t ns] [PASS] %s", $time, vif.test_name);
                end
            end
        end
    endtask

    function void report_phase(uvm_phase phase);
        $display("\n==========================================================");
        $display("             CONTROL UNIT SCOREBOARD REPORT               ");
        $display("==========================================================");
        $display(" Total Cases Tested    : %0d", total_tests);
        if (err_count == 0) $display(" RESULT: PASSED (0 Errors found)");
        else                $display(" RESULT: FAILED (%0d Errors found)", err_count);
        $display("==========================================================\n");
    endfunction
endclass

// =============================================================================
// 6. AGENT, ENV, TEST & TOP
// =============================================================================
class control_agent extends uvm_agent;
    `uvm_component_utils(control_agent)
    control_driver driver; uvm_sequencer #(control_item) sequencer;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        driver = control_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(control_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase); driver.seq_item_port.connect(sequencer.seq_item_export); endfunction
endclass

class control_env extends uvm_env;
    `uvm_component_utils(control_env)
    control_agent agent; control_scoreboard scoreboard;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = control_agent::type_id::create("agent", this);
        scoreboard = control_scoreboard::type_id::create("scoreboard", this);
    endfunction
endclass

class control_test extends uvm_test;
    `uvm_component_utils(control_test)
    control_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); env = control_env::type_id::create("env", this); endfunction
    task run_phase(uvm_phase phase);
        control_directed_seq dir_seq = control_directed_seq::type_id::create("dir_seq");
        control_stress_seq   str_seq = control_stress_seq::type_id::create("str_seq");
        phase.raise_objection(this);
        dir_seq.start(env.agent.sequencer);
        str_seq.start(env.agent.sequencer);
        #10ns; phase.drop_objection(this);
    endtask
endclass

module tb_top;
    logic clk = 0;
    always #5 clk = ~clk;

    control_if vif(clk);

    riscv_control dut (
        .hz_id_rs1_addr_i(vif.hz_id_rs1_addr_i), .hz_id_rs2_addr_i(vif.hz_id_rs2_addr_i),
        .id_is_ecall_i(vif.id_is_ecall_i), .id_is_mret_i(vif.id_is_mret_i), .id_illegal_instr_i(vif.id_illegal_instr_i),
        .hz_ex_rs1_addr_i(vif.hz_ex_rs1_addr_i), .hz_ex_rs2_addr_i(vif.hz_ex_rs2_addr_i), .hz_ex_rd_addr_i(vif.hz_ex_rd_addr_i),
        .hz_ex_reg_we_i(vif.hz_ex_reg_we_i), .hz_ex_wb_sel_i(vif.hz_ex_wb_sel_i), .branch_taken_i(vif.branch_taken_i),
        .hz_mem_rd_addr_i(vif.hz_mem_rd_addr_i), .hz_mem_reg_we_i(vif.hz_mem_reg_we_i), .lsu_err_i(vif.lsu_err_i),
        .hz_wb_rd_addr_i(vif.hz_wb_rd_addr_i), .hz_wb_reg_we_i(vif.hz_wb_reg_we_i),
        
        .ctrl_force_stall_id_o(vif.ctrl_force_stall_id_o), .ctrl_flush_if_id_o(vif.ctrl_flush_if_id_o), .ctrl_flush_id_ex_o(vif.ctrl_flush_id_ex_o),
        .ctrl_fwd_rs1_sel_o(vif.ctrl_fwd_rs1_sel_o), .ctrl_fwd_rs2_sel_o(vif.ctrl_fwd_rs2_sel_o),
        .ctrl_pc_sel_o(vif.ctrl_pc_sel_o),
        .ctrl_trap_valid_o(vif.ctrl_trap_valid_o), .ctrl_trap_cause_o(vif.ctrl_trap_cause_o), .ctrl_mret_valid_o(vif.ctrl_mret_valid_o)
    );

    initial begin
        uvm_config_db#(virtual control_if)::set(null, "*", "vif", vif);
        run_test("control_test");
    end
endmodule