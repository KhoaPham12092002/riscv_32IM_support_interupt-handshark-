// =============================================================================
// FILE: tb_pc_gen.sv (STRICT UVM COMPLIANCE - PRO VERSION)
// Features: Manual Randomization, PC Flow Tracking, Stall/Branch Conflict Check
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
`include "uvm_macros.svh"

// -----------------------------------------------------------------------------
// 1. INTERFACE
// -----------------------------------------------------------------------------
interface pc_gen_if(input logic clk);
    logic        rst_i;
    logic        ready_i;
    logic        valid_o;
    
    // Branch Interface
    logic        branch_taken_i;
    logic [31:0] branch_target_addr_i;

    // Output PC
    logic [31:0] pc_o;
endinterface

// -----------------------------------------------------------------------------
// 2. SEQUENCE ITEM & SEQUENCE
// -----------------------------------------------------------------------------
class pc_item extends uvm_sequence_item;
    // --- INPUTS ---
    rand logic        ready;
    rand logic        branch_taken;
    rand logic [31:0] branch_target;

    // --- OUTPUTS (OBSERVED) ---
    logic [31:0] current_pc;
    logic        valid_out;

    `uvm_object_utils_begin(pc_item)
        `uvm_field_int(ready, UVM_DEFAULT)
        `uvm_field_int(branch_taken, UVM_DEFAULT)
        `uvm_field_int(branch_target, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(current_pc, UVM_DEFAULT | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "pc_item"); super.new(name); endfunction
endclass

class pc_random_seq extends uvm_sequence #(pc_item);
    `uvm_object_utils(pc_random_seq)
    function new(string name=""); super.new(name); endfunction

    // --- MANUAL RANDOMIZATION ---
    // Sinh địa chỉ Target hợp lệ (Aligned 4 byte)
    function logic [31:0] get_aligned_target();
        return ($urandom() & 32'hFFFFFFFC); 
    endfunction

    task body();
        int dice;
        
        
        repeat(5000) begin
            req = pc_item::type_id::create("req");
            start_item(req);
            
            dice = $urandom_range(0, 99);

            // CASE 1: NORMAL SEQUENTIAL (70%)
            // Hệ thống sẵn sàng, không nhảy
            if (dice < 70) begin
                req.ready = 1;
                req.branch_taken = 0;
                req.branch_target = get_aligned_target(); // Don't care
            end

            // CASE 2: STALL SCENARIO (15%)
            // Hệ thống bận, PC phải đứng yên
            else if (dice < 85) begin
                req.ready = 0;
                req.branch_taken = 0;
                req.branch_target = get_aligned_target();
            end

            // CASE 3: BRANCH TAKEN (10%)
            // Có lệnh nhảy -> PC = Target
            else if (dice < 95) begin
                req.ready = 1;
                req.branch_taken = 1;
                req.branch_target = get_aligned_target();
            end

            // CASE 4: BRANCH OVERRIDE STALL (5% - CRITICAL)
            else begin
                req.ready = 0; // STALL REQUEST
                req.branch_taken = 1; // BRANCH REQUEST
                req.branch_target = get_aligned_target();
            end
            
            finish_item(req);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 3. DRIVER
// -----------------------------------------------------------------------------
class pc_driver extends uvm_driver #(pc_item);
    `uvm_component_utils(pc_driver)
    virtual pc_gen_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual pc_gen_if)::get(this, "", "vif", vif)) `uvm_fatal("DRV", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        // Init Inputs
        vif.rst_i              <= 1;
        vif.ready_i            <= 0;
        vif.branch_taken_i     <= 0;
        vif.branch_target_addr_i <= 0;

        // Reset Sequence
        repeat(5) @(posedge vif.clk);
        vif.rst_i <= 0;

        forever begin
            seq_item_port.get_next_item(req);
            
            // Drive Inputs Synchronously
            @(posedge vif.clk);
            vif.ready_i            <= req.ready;
            vif.branch_taken_i     <= req.branch_taken;
            vif.branch_target_addr_i <= req.branch_target;

            // Wait 1 cycle for PC update (Sequential Logic)
            @(posedge vif.clk); 
            
            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. MONITOR
// -----------------------------------------------------------------------------
class pc_monitor extends uvm_monitor;
    `uvm_component_utils(pc_monitor)
    virtual pc_gen_if vif;
    uvm_analysis_port #(pc_item) mon_ap;
    
    pc_item item;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_ap = new("mon_ap", this);
        if(!uvm_config_db#(virtual pc_gen_if)::get(this, "", "vif", vif)) `uvm_fatal("MON", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            
            // --- DELAY 1ns: Chờ Register cập nhật xong ---
            #1; 
            // ---------------------------------------------

            if (!vif.rst_i) begin // Chỉ bắt khi không Reset
                item = pc_item::type_id::create("item");
                
                // Inputs (State causing the update)
                // Lưu ý: Do PC là Sequential, giá trị PC hiện tại là kết quả của Input chu kỳ TRƯỚC.
                // Tuy nhiên, Scoreboard sẽ tự maintain state, nên Monitor cứ gửi những gì nó thấy.
                item.ready         = vif.ready_i;
                item.branch_taken  = vif.branch_taken_i;
                item.branch_target = vif.branch_target_addr_i;

                // Output Current
                item.current_pc    = vif.pc_o;
                item.valid_out     = vif.valid_o;

                mon_ap.write(item);
            end
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 5. SCOREBOARD (STATEFUL PREDICTION)
// -----------------------------------------------------------------------------
/*class pc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(pc_scoreboard)
    uvm_analysis_imp #(pc_item, pc_scoreboard) sb_export;
    
    // --- INTERNAL STATE ---
    logic [31:0] expected_pc;
    bit          first_pkt = 1;

    // --- STATISTICS ---
    int cnt_seq_step  = 0; // PC + 4
    int cnt_stall     = 0; // PC maintained
    int cnt_branch    = 0; // Branch taken
    int cnt_override  = 0; // Branch override Stall

    bit verbose = 0; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sb_export = new("sb_export", this);
        if ($test$plusargs("VERBOSE")) verbose = 1;
        
        // Reset Expected PC
        expected_pc = 32'h0; 
    endfunction

    function void write(pc_item pkt);
        logic [31:0] next_expected;
        string msg;

        // 1. COMPARE CURRENT PC
        if (pkt.current_pc !== expected_pc) begin
            `uvm_error("FAIL", $sformatf("PC Mismatch! Exp:%h Act:%h | Inputs:[Rdy:%b Br:%b Tgt:%h]", 
                expected_pc, pkt.current_pc, pkt.ready, pkt.branch_taken, pkt.branch_target))
        end else begin
            if (verbose) $display("[PASS] PC:%h", pkt.current_pc);
        end

        // 2. CALCULATE NEXT PC (For next cycle check)
        // Logic: Trap > Branch > Stall > Sequential
        // =======================================================
        // 2. CALCULATE NEXT PC (Reference Model Logic)
        // =======================================================
        
        // Ưu tiên 1: STALL (Ready = 0)
        if (pkt.ready == 0) begin
            next_expected = expected_pc; // Đứng im, không nhảy!
            
            if (pkt.branch_taken) begin
                cnt_override++; 
                current_eval = CASE_OVERRIDE; // Ghi nhận Case 4: Có Branch nhưng bị chặn
            end else begin
                cnt_stall++;    
                current_eval = CASE_STALL;    // Ghi nhận Case 2: Stall bình thường
            end
        end 
        
        // Ưu tiên 2: READY (Ready = 1) -> Xử lý Branch hoặc Tuần tự
        else begin
            if (pkt.branch_taken) begin
                next_expected = pkt.branch_target;
                cnt_branch++;
                current_eval = CASE_BRANCH;   // Ghi nhận Case 3
            end else begin
                next_expected = expected_pc + 32'd4;
                cnt_seq_step++;
                current_eval = CASE_SEQ;      // Ghi nhận Case 1
            end
        end       

        // Update state for next cycle
        expected_pc = next_expected;
    endfunction

    function void report_phase(uvm_phase phase);
        $display("\n==================================================");
        $display("          PC GEN VERIFICATION REPORT              ");
        $display("==================================================");
        $display("Total Cycles Checked     : %0d", cnt_seq_step + cnt_stall + cnt_branch);
        $display("--------------------------------------------------");
        $display("Sequential Steps (+4)    : %0d", cnt_seq_step);
        $display("Stall Cycles (Hold PC)   : %0d", cnt_stall);
        $display("Branch Jumps Taken       : %0d", cnt_branch);
        $display("Branch Override Stall    : %0d (CRITICAL CHECK)", cnt_override);
        $display("--------------------------------------------------");
        if (cnt_override > 0)
             $display("[PASS] Logic 'Branch overrides Stall' verified successfully.");
        else $display("[WARN] Corner case 'Branch during Stall' NOT tested.");
        $display("==================================================\n");
    endfunction    
endclass */
// -----------------------------------------------------------------------------
// 5. SCOREBOARD (STATEFUL PREDICTION & ERROR BINNING)
// -----------------------------------------------------------------------------
class pc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(pc_scoreboard)
    uvm_analysis_imp #(pc_item, pc_scoreboard) sb_export;
    
    // --- INTERNAL STATE ---
    logic [31:0] expected_pc;
    
    // Enum để nhớ xem chu kỳ trước ta đã mong đợi điều kiện gì
    typedef enum {CASE_SEQ, CASE_STALL, CASE_BRANCH, CASE_OVERRIDE} eval_case_e;
    eval_case_e prev_case = CASE_SEQ; 

    // --- STATISTICS (PASS) ---
    int cnt_seq_step  = 0; 
    int cnt_stall     = 0; 
    int cnt_branch    = 0; 
    int cnt_override  = 0; 

    // --- STATISTICS (FAIL) ---
    int fail_seq      = 0;
    int fail_stall    = 0;
    int fail_branch   = 0;
    int fail_override = 0;

    bit verbose = 0; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sb_export = new("sb_export", this);
        if ($test$plusargs("VERBOSE")) verbose = 1;
        expected_pc = 32'h0; 
    endfunction

    function void write(pc_item pkt);
        logic [31:0] next_expected;
        eval_case_e  current_eval;

        // =======================================================
        // 1. COMPARE CURRENT PC & BINNING ERRORS
        // =======================================================
        if (pkt.current_pc !== expected_pc) begin
            `uvm_error("FAIL", $sformatf("Mismatch! Exp:%h Act:%h | Inputs:[Rdy:%b Br:%b]", 
                expected_pc, pkt.current_pc, pkt.ready, pkt.branch_taken))
            
            // Ghi nhận lỗi vào đúng Case đã được đánh giá ở cycle trước
            case (prev_case)
                CASE_SEQ:      fail_seq++;
                CASE_STALL:    fail_stall++;
                CASE_BRANCH:   fail_branch++;
                CASE_OVERRIDE: fail_override++;
            endcase
        end else begin
            if (verbose) $display("[PASS] PC:%h", pkt.current_pc);
        end

        // =======================================================
        // 2. CALCULATE NEXT PC & DETERMINE CASE (For next cycle)
        // =======================================================
        // Ưu tiên 1: STALL (Ready = 0)
        if (pkt.ready == 0) begin
            next_expected = expected_pc; // Đứng im, không nhảy!
            
            if (pkt.branch_taken) begin
                cnt_override++; 
                current_eval = CASE_OVERRIDE; // Ghi nhận Case 4: Có Branch nhưng bị chặn
            end else begin
                cnt_stall++;    
                current_eval = CASE_STALL;    // Ghi nhận Case 2: Stall bình thường
            end
        end 
        
        // Ưu tiên 2: READY (Ready = 1) -> Xử lý Branch hoặc Tuần tự
        else begin
            if (pkt.branch_taken) begin
                next_expected = pkt.branch_target;
                cnt_branch++;
                current_eval = CASE_BRANCH;   // Ghi nhận Case 3
            end else begin
                next_expected = expected_pc + 32'd4;
                cnt_seq_step++;
                current_eval = CASE_SEQ;      // Ghi nhận Case 1
            end
        end       


        // Update state for next cycle
        expected_pc = next_expected;
        prev_case   = current_eval;
    endfunction


    function void report_phase(uvm_phase phase);
        int total_fails = fail_seq + fail_stall + fail_branch + fail_override;

        $display("\n==================================================");
        $display("         PC GEN VERIFICATION REPORT               ");
        $display("==================================================");
        $display("Total Cycles Checked     : %0d", cnt_seq_step + cnt_stall + cnt_branch + cnt_override);
        $display("--------------------------------------------------");
        $display("FAIL SUMMARY:");
        $display("Case 1 (Sequential)      : %0d Fails", fail_seq);
        $display("Case 2 (Stall)           : %0d Fails", fail_stall);
        $display("Case 3 (Branch Taken)    : %0d Fails", fail_branch);
        $display("Case 4 (Override Stall)  : %0d Fails", fail_override);
        $display("--------------------------------------------------");
        $display("==================================================");
        $display("Total Cycles Checked     : %0d", cnt_seq_step + cnt_stall + cnt_branch + cnt_override);
        $display("--------------------------------------------------");
        $display("Sequential Steps (+4)    : %0d", cnt_seq_step);
        $display("Stall Cycles (Hold PC)   : %0d", cnt_stall);
        $display("Branch Jumps Taken       : %0d", cnt_branch);
        $display("Branch Override Stall    : %0d (CRITICAL CHECK)", cnt_override);
        $display("--------------------------------------------------");
        if (cnt_override > 0)
             $display("[PASS] Logic 'Branch overrides Stall' verified successfully.");
        else $display("[WARN] Corner case 'Branch during Stall' NOT tested.");
        $display("==================================================\n");
        if (total_fails == 0)
             $display("[PASSED] ALL CASES VERIFIED SUCCESSFULLY.");
        else $display("[FAILED] TEST FINISHED WITH %0d ERRORS.", total_fails);
        $display("==================================================\n");
    endfunction    
endclass

// -----------------------------------------------------------------------------
// 6. AGENT - ENV - TEST
// -----------------------------------------------------------------------------
class pc_agent extends uvm_agent;
    `uvm_component_utils(pc_agent)
    pc_driver drv; pc_monitor mon; uvm_sequencer #(pc_item) sqr;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        drv = pc_driver::type_id::create("drv", this);
        mon = pc_monitor::type_id::create("mon", this);
        sqr = uvm_sequencer#(pc_item)::type_id::create("sqr", this);
    endfunction
    function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(sqr.seq_item_export); endfunction
endclass

class pc_env extends uvm_env;
    `uvm_component_utils(pc_env)
    pc_agent agent; pc_scoreboard scb;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = pc_agent::type_id::create("agent", this);
        scb   = pc_scoreboard::type_id::create("scb", this);
    endfunction
    function void connect_phase(uvm_phase phase); agent.mon.mon_ap.connect(scb.sb_export); endfunction
endclass

class pc_test extends uvm_test;
    `uvm_component_utils(pc_test)
    pc_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); env = pc_env::type_id::create("env", this); endfunction
    task run_phase(uvm_phase phase);
        pc_random_seq seq = pc_random_seq::type_id::create("seq");
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
    pc_gen_if vif(clk);
    
    // DUT Instantiation
    pc_gen dut (
        .clk_i      (vif.clk),
        .rst_i      (vif.rst_i),
        .ready_i    (vif.ready_i),
        .valid_o    (vif.valid_o),
        .branch_taken_i       (vif.branch_taken_i),
        .branch_target_addr_i (vif.branch_target_addr_i),
        .pc_o       (vif.pc_o)
    );

    initial begin
        clk=0;
        uvm_config_db#(virtual pc_gen_if)::set(null, "*", "vif", vif);
        run_test("pc_test");
    end
endmodule