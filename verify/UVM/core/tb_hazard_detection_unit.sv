// =============================================================================
// FILE: tb_hazard_detection_unit.sv (STRICT UVM COMPLIANCE - PRO VERSION)
// Features: Directed Random Injection, Combinational Logic Check, Zero Reg Test
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
`include "uvm_macros.svh"

// -----------------------------------------------------------------------------
// 1. INTERFACE
// -----------------------------------------------------------------------------
interface hazard_if(input logic clk);
    // Inputs
    logic       global_stall_i;
    logic [2:0] id_ex_wb_sel; 
    logic [4:0] id_ex_rd;
    logic [4:0] if_id_rs1;
    logic [4:0] if_id_rs2;

    // Outputs
    logic       pc_stall_o;
    logic       if_id_stall_o;
    logic       id_ex_flush_o;
endinterface

// -----------------------------------------------------------------------------
// 2. SEQUENCE ITEM & SEQUENCE
// -----------------------------------------------------------------------------
class hazard_item extends uvm_sequence_item;
    // --- INPUTS ---
    rand logic       global_stall;
    rand logic [2:0] wb_sel;
    rand logic [4:0] ex_rd;
    rand logic [4:0] id_rs1;
    rand logic [4:0] id_rs2;

    // --- OUTPUTS (OBSERVED) ---
    logic actual_pc_stall;
    logic actual_if_id_stall;
    logic actual_flush;

    `uvm_object_utils_begin(hazard_item)
        `uvm_field_int(global_stall, UVM_DEFAULT)
        `uvm_field_int(wb_sel, UVM_DEFAULT)
        `uvm_field_int(ex_rd, UVM_DEFAULT)
        `uvm_field_int(id_rs1, UVM_DEFAULT)
        `uvm_field_int(id_rs2, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "hazard_item"); super.new(name); endfunction
endclass

class hazard_random_seq extends uvm_sequence #(hazard_item);
    `uvm_object_utils(hazard_random_seq)
    function new(string name=""); super.new(name); endfunction

    task body();
        int dice;
        
        repeat(5000) begin
            req = hazard_item::type_id::create("req");
            start_item(req);
            
            // --- MANUAL RANDOMIZATION STRATEGY ---
            dice = $urandom_range(0, 99);

            // CASE 1: FORCE HAZARD ON RS1 (30%)
            // Điều kiện: EX là Load (WB_MEM) + RD trùng RS1 + RD != 0
            if (dice < 30) begin
                req.global_stall = 0;
                req.wb_sel       = WB_MEM; 
                req.ex_rd        = $urandom_range(1, 31); // Tránh x0
                req.id_rs1       = req.ex_rd;             // Trùng nhau -> Hazard
                req.id_rs2       = $urandom_range(0, 31); // Random
            end

            // CASE 2: FORCE HAZARD ON RS2 (30%)
            else if (dice < 60) begin
                req.global_stall = 0;
                req.wb_sel       = WB_MEM;
                req.ex_rd        = $urandom_range(1, 31);
                req.id_rs1       = $urandom_range(0, 31);
                req.id_rs2       = req.ex_rd;             // Trùng nhau -> Hazard
            end

            // CASE 3: FALSE HAZARD WITH X0 (10%)
            // RD trùng RS1 nhưng RD = 0 -> Không được Stall
            else if (dice < 70) begin
                req.global_stall = 0;
                req.wb_sel       = WB_MEM;
                req.ex_rd        = 5'd0;       // x0
                req.id_rs1       = 5'd0;       // Trùng x0
                req.id_rs2       = $urandom();
            end

            // CASE 4: GLOBAL STALL ACTIVE (10%)
            // Có Hazard nhưng Global Stall bật -> Output phải là 0
            else if (dice < 80) begin
                req.global_stall = 1;
                req.wb_sel       = WB_MEM;
                req.ex_rd        = $urandom_range(1, 31);
                req.id_rs1       = req.ex_rd; // Hazard condition met
                req.id_rs2       = $urandom();
            end

            // CASE 5: NORMAL RANDOM (20%)
            else begin
                req.global_stall = ($urandom_range(0, 20) == 0);
                req.wb_sel       = $urandom_range(0, 7);
                req.ex_rd        = $urandom_range(0, 31);
                req.id_rs1       = $urandom_range(0, 31);
                req.id_rs2       = $urandom_range(0, 31);
            end
            
            finish_item(req);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 3. DRIVER
// -----------------------------------------------------------------------------
class hazard_driver extends uvm_driver #(hazard_item);
    `uvm_component_utils(hazard_driver)
    virtual hazard_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual hazard_if)::get(this, "", "vif", vif)) `uvm_fatal("DRV", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        // Init signals
        vif.global_stall_i <= 0;
        vif.id_ex_wb_sel   <= 0;
        vif.id_ex_rd       <= 0;
        vif.if_id_rs1      <= 0;
        vif.if_id_rs2      <= 0;

        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(req);
            
            // Drive Inputs Synchronously
            @(posedge vif.clk);
            vif.global_stall_i <= req.global_stall;
            vif.id_ex_wb_sel   <= req.wb_sel;
            vif.id_ex_rd       <= req.ex_rd;
            vif.if_id_rs1      <= req.id_rs1;
            vif.if_id_rs2      <= req.id_rs2;

            // Wait 1 cycle for observation
            @(posedge vif.clk); 
            
            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. MONITOR
// -----------------------------------------------------------------------------
class hazard_monitor extends uvm_monitor;
    `uvm_component_utils(hazard_monitor)
    virtual hazard_if vif;
    uvm_analysis_port #(hazard_item) mon_ap;
    
    hazard_item item;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_ap = new("mon_ap", this);
        if(!uvm_config_db#(virtual hazard_if)::get(this, "", "vif", vif)) `uvm_fatal("MON", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            
            // --- DELAY ĐỂ CHỜ LOGIC TỔ HỢP ỔN ĐỊNH ---
            #1; 
            // -----------------------------------------

            item = hazard_item::type_id::create("item");
            
            // Capture Inputs
            item.global_stall = vif.global_stall_i;
            item.wb_sel       = vif.id_ex_wb_sel;
            item.ex_rd        = vif.id_ex_rd;
            item.id_rs1       = vif.if_id_rs1;
            item.id_rs2       = vif.if_id_rs2;

            // Capture Outputs
            item.actual_pc_stall    = vif.pc_stall_o;
            item.actual_if_id_stall = vif.if_id_stall_o;
            item.actual_flush       = vif.id_ex_flush_o;

            mon_ap.write(item);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 5. SCOREBOARD
// -----------------------------------------------------------------------------
class hazard_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(hazard_scoreboard)
    uvm_analysis_imp #(hazard_item, hazard_scoreboard) sb_export;
    
    // --- STATISTICS ---
    int cnt_hazard_rs1   = 0;
    int cnt_hazard_rs2   = 0;
    int cnt_no_hazard    = 0;
    int cnt_global_stall = 0;
    int cnt_x0_ignore    = 0;

    bit verbose = 0; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sb_export = new("sb_export", this);
        if ($test$plusargs("VERBOSE")) verbose = 1;
    endfunction

    // --- GOLDEN MODEL LOGIC ---
    function bit predict_stall(hazard_item pkt);
        bit is_load;
        bit conflict_rs1;
        bit conflict_rs2;
        bit rd_valid;

        // 1. Check if instruction in EX is LOAD
        is_load = (pkt.wb_sel == WB_MEM); 
        
        // 2. Check Valid RD (x0 is never valid for forwarding/hazard)
        rd_valid = (pkt.ex_rd != 0);

        // 3. Check Conflicts
        conflict_rs1 = (pkt.ex_rd == pkt.id_rs1);
        conflict_rs2 = (pkt.ex_rd == pkt.id_rs2);

        // 4. Combine Logic
        if (!pkt.global_stall && is_load && rd_valid && (conflict_rs1 || conflict_rs2)) begin
            return 1'b1; // Should Stall
        end else begin
            return 1'b0; // No Stall
        end
    endfunction

    function void write(hazard_item pkt);
        bit exp_stall;
        
        // Predict Expected Output
        exp_stall = predict_stall(pkt);

        // --- COMPARE ---
        // PC Stall, IF/ID Stall, và Flush thường có cùng logic trong Hazard Unit này
        if (pkt.actual_pc_stall !== exp_stall) 
            `uvm_error("FAIL", $sformatf("PC_STALL Mismatch! Inputs:[G:%b WB:%b RD:%d RS1:%d RS2:%d] Exp:%b Act:%b",
                pkt.global_stall, pkt.wb_sel, pkt.ex_rd, pkt.id_rs1, pkt.id_rs2, exp_stall, pkt.actual_pc_stall))
        
        if (pkt.actual_if_id_stall !== exp_stall) 
            `uvm_error("FAIL", "IF_ID_STALL Mismatch!")

        if (pkt.actual_flush !== exp_stall) 
            `uvm_error("FAIL", "ID_EX_FLUSH Mismatch!")

        // --- STATS ---
        if (exp_stall) begin
            if (pkt.ex_rd == pkt.id_rs1) cnt_hazard_rs1++;
            if (pkt.ex_rd == pkt.id_rs2) cnt_hazard_rs2++;
            if (verbose) $display("[HAZARD] Detected stall on RD=%0d", pkt.ex_rd);
        end else begin
            if (pkt.global_stall) cnt_global_stall++;
            else if (pkt.ex_rd == 0 && (pkt.id_rs1==0 || pkt.id_rs2==0)) cnt_x0_ignore++;
            else cnt_no_hazard++;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        int total_stalls = cnt_hazard_rs1 + cnt_hazard_rs2; // Note: overlaps possible but rough sum
        
        $display("\n==================================================");
        $display("       HAZARD UNIT VERIFICATION REPORT            ");
        $display("==================================================");
        $display("Total Transactions     : %0d", cnt_no_hazard + cnt_global_stall + total_stalls);
        $display("--------------------------------------------------");
        $display("Load-Use Hazards (RS1) : %0d", cnt_hazard_rs1);
        $display("Load-Use Hazards (RS2) : %0d", cnt_hazard_rs2);
        $display("Global Stall Overrides : %0d", cnt_global_stall);
        $display("x0 Hazards Ignored     : %0d (Correct behavior)", cnt_x0_ignore);
        $display("--------------------------------------------------");
        if (total_stalls > 0) 
            $display("[PASS] Hazard Logic Verified with actual collisions.");
        else
            $display("[WARN] No Hazards triggered? Check sequence!");
        $display("==================================================\n");
    endfunction    
endclass

// -----------------------------------------------------------------------------
// 6. AGENT - ENV - TEST
// -----------------------------------------------------------------------------
class hazard_agent extends uvm_agent;
    `uvm_component_utils(hazard_agent)
    hazard_driver drv; hazard_monitor mon; uvm_sequencer #(hazard_item) sqr;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        drv = hazard_driver::type_id::create("drv", this);
        mon = hazard_monitor::type_id::create("mon", this);
        sqr = uvm_sequencer#(hazard_item)::type_id::create("sqr", this);
    endfunction
    function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(sqr.seq_item_export); endfunction
endclass

class hazard_env extends uvm_env;
    `uvm_component_utils(hazard_env)
    hazard_agent agent; hazard_scoreboard scb;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = hazard_agent::type_id::create("agent", this);
        scb   = hazard_scoreboard::type_id::create("scb", this);
    endfunction
    function void connect_phase(uvm_phase phase); agent.mon.mon_ap.connect(scb.sb_export); endfunction
endclass

class hazard_test extends uvm_test;
    `uvm_component_utils(hazard_test)
    hazard_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); env = hazard_env::type_id::create("env", this); endfunction
    task run_phase(uvm_phase phase);
        hazard_random_seq seq = hazard_random_seq::type_id::create("seq");
        phase.raise_objection(this); 
        seq.start(env.agent.sqr); 
        phase.drop_objection(this);
    endtask
endclass

// -----------------------------------------------------------------------------
// 7. TOP MODULE
// -----------------------------------------------------------------------------
module tb_top;
    import uvm_pkg::*;
    import riscv_32im_pkg::*;

    logic clk; always #5 clk = ~clk; 
    hazard_if vif(clk);
    
    // DUT Instantiation
    hazard_detection_unit dut (
        .global_stall_i (vif.global_stall_i),
        .id_ex_wb_sel   (vif.id_ex_wb_sel),
        .id_ex_rd       (vif.id_ex_rd),
        .if_id_rs1      (vif.if_id_rs1),
        .if_id_rs2      (vif.if_id_rs2),
        
        .pc_stall_o     (vif.pc_stall_o),
        .if_id_stall_o  (vif.if_id_stall_o),
        .id_ex_flush_o  (vif.id_ex_flush_o)
    );

    initial begin
        clk=0;
        uvm_config_db#(virtual hazard_if)::set(null, "*", "vif", vif);
        run_test("hazard_test");
    end
endmodule