// =============================================================================
// FILE: tb_hazard_unit.sv
// DESCRIPTION: UVM Testbench for RISC-V Hazard Unit (Combinational)
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
// Đảm bảo package có wb_sel_e: WB_ALU, WB_MEM, WB_PC_PLUS4, WB_CSR, WB_M_UNIT

`include "uvm_macros.svh"

// =============================================================================
// 1. INTERFACE
// =============================================================================
interface hazard_if (input logic clk);
    // --- Inputs to DUT ---
    logic [4:0]  hz_id_rs1_addr_i;
    logic [4:0]  hz_id_rs2_addr_i;
    logic [4:0]  hz_ex_rd_addr_i;
    logic        hz_ex_reg_we_i;   
    wb_sel_e     hz_ex_wb_sel_i;   
    logic        jump_trap_i;

    // --- Outputs from DUT ---
    logic        ctrl_force_stall_id_o;
    logic        ctrl_flush_if_id_o;
    logic        ctrl_flush_id_ex_o;
    
    // --- TB Signal ---
    logic        tb_item_valid; // Cờ báo hiệu có data mới để SCB lấy mẫu
endinterface

// =============================================================================
// 2. TRANSACTION ITEM
// =============================================================================
class hazard_item extends uvm_sequence_item;
    rand logic [4:0]  rs1;
    rand logic [4:0]  rs2;
    rand logic [4:0]  ex_rd;
    rand logic        ex_we;
    rand wb_sel_e     ex_wb_sel;
    rand logic        jump;

    `uvm_object_utils_begin(hazard_item)
        `uvm_field_int(rs1, UVM_HEX)
        `uvm_field_int(rs2, UVM_HEX)
        `uvm_field_int(ex_rd, UVM_HEX)
        `uvm_field_int(ex_we, UVM_BIN)
        `uvm_field_enum(wb_sel_e, ex_wb_sel, UVM_ALL_ON)
        `uvm_field_int(jump, UVM_BIN)
    `uvm_object_utils_end

    function new(string name = "hazard_item"); super.new(name); endfunction
endclass

// =============================================================================
// 3. DRIVER
// =============================================================================
class hazard_driver extends uvm_driver #(hazard_item);
    `uvm_component_utils(hazard_driver)
    virtual hazard_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual hazard_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Interface not found!")
    endfunction 

    task run_phase(uvm_phase phase);
        vif.hz_id_rs1_addr_i = 0;
        vif.hz_id_rs2_addr_i = 0;
        vif.hz_ex_rd_addr_i  = 0;
        vif.hz_ex_reg_we_i   = 0;
        vif.hz_ex_wb_sel_i   = WB_ALU;
        vif.jump_trap_i      = 0;
        vif.tb_item_valid    = 0;

        forever begin
            seq_item_port.get_next_item(req);
            
            @(posedge vif.clk);
            vif.hz_id_rs1_addr_i <= req.rs1;
            vif.hz_id_rs2_addr_i <= req.rs2;
            vif.hz_ex_rd_addr_i  <= req.ex_rd;
            vif.hz_ex_reg_we_i   <= req.ex_we;
            vif.hz_ex_wb_sel_i   <= req.ex_wb_sel;
            vif.jump_trap_i      <= req.jump;
            vif.tb_item_valid    <= 1; // Bật cờ cho SCB chộp lấy
            
            @(posedge vif.clk);
            vif.tb_item_valid    <= 0;
            
            seq_item_port.item_done();
        end
    endtask
endclass

// =============================================================================
// 4. SEQUENCES
// =============================================================================

// --- 4A. KỊCH BẢN DIRECTED (Phủ 100% logic) ---
class hazard_directed_seq extends uvm_sequence #(hazard_item);
    `uvm_object_utils(hazard_directed_seq)
    function new(string name=""); super.new(name); endfunction

    task send_item(logic [4:0] r1, logic [4:0] r2, logic [4:0] rd, logic we, wb_sel_e wb, logic jmp);
        hazard_item req = hazard_item::type_id::create("req");
        start_item(req);
        req.rs1 = r1; req.rs2 = r2; req.ex_rd = rd; req.ex_we = we; req.ex_wb_sel = wb; req.jump = jmp;
        finish_item(req);
    endtask

    task body();
        `uvm_info("SEQ", "--- STARTING DIRECTED SEQUENCE ---", UVM_LOW)
        
        // 1. Bình thường (Không có hazard)
        send_item(5'd1, 5'd2, 5'd3, 1'b1, WB_ALU, 1'b0);
        
        // 2. Load-Use Hazard trên RS1
        send_item(5'd5, 5'd0, 5'd5, 1'b1, WB_MEM, 1'b0);
        
        // 3. Load-Use Hazard trên RS2
        send_item(5'd0, 5'd7, 5'd7, 1'b1, WB_MEM, 1'b0);
        
        // 4. Fake Load-Use (rd = 0 -> R0 không được tính là hazard)
        send_item(5'd0, 5'd0, 5'd0, 1'b1, WB_MEM, 1'b0);
        
        // 5. Fake Load-Use (Lệnh Load nhưng không ghi Register file - we=0)
        send_item(5'd5, 5'd0, 5'd5, 1'b0, WB_MEM, 1'b0);
        
        // 6. Control Hazard (Có nhảy/trap)
        send_item(5'd1, 5'd2, 5'd3, 1'b1, WB_ALU, 1'b1);
        
        // 7. Xung đột cấp độ: Jump/Trap VÀ Load-Use xảy ra cùng lúc
        // Ưu tiên: Jump/Trap phải thắng (Flush cả 2, không Stall)
        send_item(5'd8, 5'd0, 5'd8, 1'b1, WB_MEM, 1'b1);
        
        `uvm_info("SEQ", "--- DIRECTED SEQUENCE DONE ---", UVM_LOW)
    endtask
endclass

// --- 4B. KỊCH BẢN STRESS (50,000 Lệnh Xí ngầu) ---
class hazard_stress_seq extends uvm_sequence #(hazard_item);
    `uvm_object_utils(hazard_stress_seq)
    function new(string name=""); super.new(name); endfunction

    function hazard_item gen_dice_item();
        hazard_item itm = hazard_item::type_id::create("itm");
        int dice = $urandom_range(0, 99);

        // Tung xí ngầu ngẫu nhiên toàn bộ
        itm.rs1   = $urandom_range(0, 31);
        itm.rs2   = $urandom_range(0, 31);
        itm.ex_rd = $urandom_range(0, 31);
        itm.ex_we = $urandom_range(0, 1);
        
        // 30% tỷ lệ là lệnh Load (WB_MEM)
        if ($urandom_range(0, 100) < 30) itm.ex_wb_sel = WB_MEM;
        else itm.ex_wb_sel = wb_sel_e'($urandom_range(0, 4)); 
        
        // 10% tỷ lệ là lệnh Nhảy/Trap
        itm.jump = ($urandom_range(0, 100) < 10) ? 1'b1 : 1'b0;

        // Ép dính Load-Use Hazard (Xác suất 20% để ép rs1 hoặc rs2 bằng rd)
        if (dice < 20) begin
            itm.ex_wb_sel = WB_MEM;
            itm.ex_we     = 1'b1;
            itm.ex_rd     = $urandom_range(1, 31); // Ép khác 0
            if ($urandom_range(0,1)) itm.rs1 = itm.ex_rd;
            else itm.rs2 = itm.ex_rd;
        end

        return itm;
    endfunction

    task body();
        hazard_item req;
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
class hazard_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(hazard_scoreboard)
    virtual hazard_if vif;

    bit enable_uvm_log    = 0;
    bit enable_debug_dump = 0; 

    int total_tests  = 0;
    int err_count    = 0;

    int cnt_normal   = 0;
    int cnt_load_use = 0;
    int cnt_jump     = 0;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual hazard_if)::get(this, "", "vif", vif))
            `uvm_fatal("SCB", "Interface not found!")
        
        void'($value$plusargs("UVM_LOG_EN=%d", enable_uvm_log));
        void'($value$plusargs("UVM_DEBUG_DUMP=%d", enable_debug_dump));
    endfunction
    
    function void dump_all_pins(string msg);
        $display("\n------------------- [DEBUG PIN DUMP] -------------------");
        $display(" TIME: %0t ns | %s", $time, msg);
        $display(" [INPUT ] RS1:%0d | RS2:%0d | RD:%0d | WE:%b | WBSel:%0d | Jump:%b", 
                  vif.hz_id_rs1_addr_i, vif.hz_id_rs2_addr_i, vif.hz_ex_rd_addr_i, 
                  vif.hz_ex_reg_we_i, vif.hz_ex_wb_sel_i, vif.jump_trap_i);
        $display(" [OUTPUT] Stall_ID:%b | Flush_IF_ID:%b | Flush_ID_EX:%b", 
                  vif.ctrl_force_stall_id_o, vif.ctrl_flush_if_id_o, vif.ctrl_flush_id_ex_o);
        $display("--------------------------------------------------------\n");
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            // Mạch tổ hợp: Chờ sườn XUỐNG của Clock để đảm bảo tín hiệu đã lan truyền xong
            @(negedge vif.clk);
            
            if (vif.tb_item_valid) begin
                logic exp_stall_id;
                logic exp_flush_if;
                logic exp_flush_ex;
                logic is_load_use;

                total_tests++;

                // --- 1. MÔ PHỎNG LẠI LOGIC CHUẨN (REFERENCE MODEL) ---
                is_load_use = (vif.hz_ex_wb_sel_i == WB_MEM) && 
                              (vif.hz_ex_rd_addr_i != 5'd0) && 
                              (vif.hz_ex_reg_we_i == 1'b1) &&
                              ((vif.hz_ex_rd_addr_i == vif.hz_id_rs1_addr_i) || (vif.hz_ex_rd_addr_i == vif.hz_id_rs2_addr_i));

                if (vif.jump_trap_i) begin
                    exp_stall_id = 0; exp_flush_if = 1; exp_flush_ex = 1;
                    cnt_jump++;
                end else if (is_load_use) begin
                    exp_stall_id = 1; exp_flush_if = 0; exp_flush_ex = 1;
                    cnt_load_use++;
                end else begin
                    exp_stall_id = 0; exp_flush_if = 0; exp_flush_ex = 0;
                    cnt_normal++;
                end

                // --- 2. SO SÁNH VỚI DUT ---
                if ((vif.ctrl_force_stall_id_o !== exp_stall_id) ||
                    (vif.ctrl_flush_if_id_o    !== exp_flush_if) ||
                    (vif.ctrl_flush_id_ex_o    !== exp_flush_ex)) begin
                    
                    err_count++;
                    
                    if (enable_uvm_log) begin
                        `uvm_error("SCB_FAIL", "Hazard logic output mismatch!")
                    end else begin
                        $display("[%0t ns] [SCB_FAIL] Expected: Stall=%b, FlushIF=%b, FlushEX=%b | Got: Stall=%b, FlushIF=%b, FlushEX=%b", 
                            $time, exp_stall_id, exp_flush_if, exp_flush_ex, 
                            vif.ctrl_force_stall_id_o, vif.ctrl_flush_if_id_o, vif.ctrl_flush_id_ex_o);
                    end
                    
                    if (enable_debug_dump) dump_all_pins("Hazard Output Mismatch!");
                end
            end
        end
    endtask

    function void report_phase(uvm_phase phase);
        $display("\n==========================================================");
        $display("               HAZARD SCOREBOARD REPORT                   ");
        $display("==========================================================");
        $display(" Total Cases Tested    : %0d", total_tests);
        $display("   - Normal Operations : %0d", cnt_normal);
        $display("   - Load-Use Hazards  : %0d", cnt_load_use);
        $display("   - Jump/Trap Hazards : %0d", cnt_jump);
        $display("----------------------------------------------------------");
        if (err_count == 0)
            $display(" RESULT: PASSED (0 Errors found)");
        else
            $display(" RESULT: FAILED (%0d Errors found)", err_count);
        $display("==========================================================\n");
    endfunction
endclass

// =============================================================================
// 6. AGENT, ENV, TEST
// =============================================================================
class hazard_agent extends uvm_agent;
    `uvm_component_utils(hazard_agent)
    hazard_driver driver;
    uvm_sequencer #(hazard_item) sequencer;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        driver = hazard_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(hazard_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase); 
        driver.seq_item_port.connect(sequencer.seq_item_export); 
    endfunction
endclass

class hazard_env extends uvm_env;
    `uvm_component_utils(hazard_env)
    hazard_agent agent;
    hazard_scoreboard scoreboard;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = hazard_agent::type_id::create("agent", this);
        scoreboard = hazard_scoreboard::type_id::create("scoreboard", this);
    endfunction
endclass

class hazard_test extends uvm_test;
    `uvm_component_utils(hazard_test)
    hazard_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = hazard_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        hazard_directed_seq dir_seq = hazard_directed_seq::type_id::create("dir_seq");
        hazard_stress_seq   str_seq = hazard_stress_seq::type_id::create("str_seq");
        
        phase.raise_objection(this);
        // Chạy tuần tự: Quét kỹ trước -> Stress Test sau
        dir_seq.start(env.agent.sequencer);
        str_seq.start(env.agent.sequencer);
        #10ns; 
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 7. SVA (SYSTEMVERILOG ASSERTIONS)
// =============================================================================
module hazard_sva_checker (
    input logic clk,
    input logic jump_trap_i,
    input logic ctrl_force_stall_id_o,
    input logic ctrl_flush_if_id_o,
    input logic ctrl_flush_id_ex_o
);
    // Tính chất 1: Cứ có Jump/Trap là IF và EX phải bị Flush
    property p_jump_flush;
        @(negedge clk) 
        jump_trap_i |-> (ctrl_flush_if_id_o && ctrl_flush_id_ex_o);
    endproperty
    A_JUMP_FLUSH: assert property(p_jump_flush) 
        else $error("[SVA] Jump/Trap asserted but Flushes are missing!");

    // Tính chất 2: Jump/Trap ưu tiên Tuyệt đối (Không bao giờ Stall khi Jump)
    property p_jump_no_stall;
        @(negedge clk) 
        jump_trap_i |-> (!ctrl_force_stall_id_o);
    endproperty
    A_JUMP_NO_STALL: assert property(p_jump_no_stall) 
        else $error("[SVA] System stalled during Jump/Trap (Violates Priority!)");
endmodule

// =============================================================================
// 8. TOP MODULE
// =============================================================================
module tb_top;
    logic clk;

    // Clock generator
    always #5 clk = ~clk;

    hazard_if vif(clk);

    // DUT
    hazard_unit dut (
        .hz_id_rs1_addr_i      (vif.hz_id_rs1_addr_i),
        .hz_id_rs2_addr_i      (vif.hz_id_rs2_addr_i),
        .hz_ex_rd_addr_i       (vif.hz_ex_rd_addr_i),
        .hz_ex_reg_we_i        (vif.hz_ex_reg_we_i),
        .hz_ex_wb_sel_i        (vif.hz_ex_wb_sel_i),
        .jump_trap_i           (vif.jump_trap_i),
        .ctrl_force_stall_id_o (vif.ctrl_force_stall_id_o),
        .ctrl_flush_if_id_o    (vif.ctrl_flush_if_id_o),
        .ctrl_flush_id_ex_o    (vif.ctrl_flush_id_ex_o)
    );

    // SVA BINDING
    hazard_sva_checker u_sva (
        .clk                   (clk),
        .jump_trap_i           (vif.jump_trap_i),
        .ctrl_force_stall_id_o (vif.ctrl_force_stall_id_o),
        .ctrl_flush_if_id_o    (vif.ctrl_flush_if_id_o),
        .ctrl_flush_id_ex_o    (vif.ctrl_flush_id_ex_o)
    );

    // Console Tracing
    bit enable_log = 0;
    
    initial begin
        void'($value$plusargs("CONSOLE_LOG=%d", enable_log));
        if (enable_log)
            $display("Time | RS1 | RS2 | RD | WE | WBSel | Jump | STALL | F_IF | F_EX");
    end

    always @(negedge clk) begin
        if (enable_log && vif.tb_item_valid) begin
            $display("%0t | %2d  | %2d  | %2d | %b  |   %0d   |  %b   |   %b   |  %b   |  %b", 
                $time, vif.hz_id_rs1_addr_i, vif.hz_id_rs2_addr_i, vif.hz_ex_rd_addr_i, 
                vif.hz_ex_reg_we_i, vif.hz_ex_wb_sel_i, vif.jump_trap_i, 
                vif.ctrl_force_stall_id_o, vif.ctrl_flush_if_id_o, vif.ctrl_flush_id_ex_o);
        end
    end

    initial begin
        uvm_config_db#(virtual hazard_if)::set(null, "*", "vif", vif);
        run_test("hazard_test");
    end

    initial begin
        clk = 0; 
    end
endmodule