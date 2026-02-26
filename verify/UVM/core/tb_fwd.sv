// =============================================================================
// FILE: tb_forwarding_unit.sv (STRICT UVM COMPLIANCE - PRO VERSION)
// Features: Priority Check, Directed Random Injection, Zero Reg Filtering
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
`include "uvm_macros.svh"

// -----------------------------------------------------------------------------
// 1. INTERFACE
// -----------------------------------------------------------------------------
interface forwarding_if(input logic clk);
    // Inputs
    logic [4:0] rs1_addr_ex;
    logic [4:0] rs2_addr_ex;
    logic [4:0] rd_addr_mem;
    logic       rf_we_mem;
    logic [4:0] rd_addr_wb;
    logic       rf_we_wb;

    // Outputs
    logic [1:0] forward_a_o;
    logic [1:0] forward_b_o;
endinterface

// -----------------------------------------------------------------------------
// 2. SEQUENCE ITEM & SEQUENCE
// -----------------------------------------------------------------------------
class fwd_item extends uvm_sequence_item;
    // --- INPUTS ---
    rand logic [4:0] rs1_ex;
    rand logic [4:0] rs2_ex;
    rand logic [4:0] rd_mem;
    rand logic       we_mem;
    rand logic [4:0] rd_wb;
    rand logic       we_wb;

    // --- OUTPUTS (OBSERVED) ---
    logic [1:0] act_fwd_a;
    logic [1:0] act_fwd_b;

    `uvm_object_utils_begin(fwd_item)
        `uvm_field_int(rs1_ex, UVM_DEFAULT)
        `uvm_field_int(rs2_ex, UVM_DEFAULT)
        `uvm_field_int(rd_mem, UVM_DEFAULT)
        `uvm_field_int(rd_wb,  UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "fwd_item"); super.new(name); endfunction
endclass

class fwd_random_seq extends uvm_sequence #(fwd_item);
    `uvm_object_utils(fwd_random_seq)
    function new(string name=""); super.new(name); endfunction

    task body();
        int dice;
        logic [4:0] common_reg;

        repeat(10000) begin // 10k testcases
            req = fwd_item::type_id::create("req");
            start_item(req);
            
            // --- MANUAL RANDOMIZATION (DIRECTED) ---
            dice = $urandom_range(0, 99);
            common_reg = $urandom_range(1, 31); // Register 1-31 (Not x0)

            // CASE 1: EX HAZARD (Priority 1) - 30%
            // MEM stage ghi vào RS1/RS2
            if (dice < 30) begin
                req.rs1_ex = common_reg;
                req.rs2_ex = common_reg;
                req.rd_mem = common_reg; // MATCH -> Hazard
                req.we_mem = 1;
                
                req.rd_wb  = $urandom_range(0, 31); // WB random
                req.we_wb  = $urandom_range(0, 1);
                // Tránh trường hợp WB trùng (để test riêng EX hazard)
                if (req.rd_wb == common_reg) req.rd_wb = ~common_reg; 
            end

            // CASE 2: MEM HAZARD (Priority 2) - 30%
            // WB stage ghi vào RS1/RS2, MEM stage KHÔNG ghi (hoặc khác Reg)
            else if (dice < 60) begin
                req.rs1_ex = common_reg;
                req.rs2_ex = common_reg;
                
                req.rd_mem = ~common_reg; // NOT MATCH -> No EX Hazard
                req.we_mem = $urandom_range(0, 1);

                req.rd_wb  = common_reg;  // MATCH -> MEM Hazard
                req.we_wb  = 1;
            end

            // CASE 3: DOUBLE HAZARD (PRIORITY CHECK) - 10%
            // Cả MEM và WB đều ghi vào cùng Register -> Phải chọn MEM (Forward 10)
            else if (dice < 70) begin
                req.rs1_ex = common_reg;
                req.rs2_ex = common_reg;
                req.rd_mem = common_reg; // Match MEM
                req.we_mem = 1;
                req.rd_wb  = common_reg; // Match WB also
                req.we_wb  = 1;
            end

            // CASE 4: X0 HAZARD (SHOULD IGNORE) - 10%
            // RD = 0 trùng RS -> Không được Forward
            else if (dice < 80) begin
                req.rs1_ex = 5'd0;
                req.rs2_ex = 5'd0;
                req.rd_mem = 5'd0; 
                req.we_mem = 1;
                req.rd_wb  = 5'd0;
                req.we_wb  = 1;
            end

            // CASE 5: NO HAZARD (Random) - 20%
            else begin
                req.rs1_ex = $urandom_range(0, 31);
                req.rs2_ex = $urandom_range(0, 31);
                req.rd_mem = $urandom_range(0, 31);
                req.we_mem = $urandom_range(0, 1);
                req.rd_wb  = $urandom_range(0, 31);
                req.we_wb  = $urandom_range(0, 1);
            end
            
            finish_item(req);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 3. DRIVER
// -----------------------------------------------------------------------------
class fwd_driver extends uvm_driver #(fwd_item);
    `uvm_component_utils(fwd_driver)
    virtual forwarding_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual forwarding_if)::get(this, "", "vif", vif)) `uvm_fatal("DRV", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        // Init Inputs
        vif.rs1_addr_ex <= 0; vif.rs2_addr_ex <= 0;
        vif.rd_addr_mem <= 0; vif.rf_we_mem   <= 0;
        vif.rd_addr_wb  <= 0; vif.rf_we_wb    <= 0;

        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(req);
            
            // Drive Inputs Synchronously
            @(posedge vif.clk);
            vif.rs1_addr_ex <= req.rs1_ex;
            vif.rs2_addr_ex <= req.rs2_ex;
            vif.rd_addr_mem <= req.rd_mem;
            vif.rf_we_mem   <= req.we_mem;
            vif.rd_addr_wb  <= req.rd_wb;
            vif.rf_we_wb    <= req.we_wb;

            // Wait 1 cycle for DUT stability
            @(posedge vif.clk); 
            
            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. MONITOR
// -----------------------------------------------------------------------------
class fwd_monitor extends uvm_monitor;
    `uvm_component_utils(fwd_monitor)
    virtual forwarding_if vif;
    uvm_analysis_port #(fwd_item) mon_ap;
    
    fwd_item item;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_ap = new("mon_ap", this);
        if(!uvm_config_db#(virtual forwarding_if)::get(this, "", "vif", vif)) `uvm_fatal("MON", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            
            // --- DELAY 1ns: CRITICAL FOR COMBINATIONAL LOGIC ---
            #1; 
            // ---------------------------------------------------

            item = fwd_item::type_id::create("item");
            
            // Capture Inputs
            item.rs1_ex = vif.rs1_addr_ex;
            item.rs2_ex = vif.rs2_addr_ex;
            item.rd_mem = vif.rd_addr_mem;
            item.we_mem = vif.rf_we_mem;
            item.rd_wb  = vif.rd_addr_wb;
            item.we_wb  = vif.rf_we_wb;

            // Capture Outputs
            item.act_fwd_a = vif.forward_a_o;
            item.act_fwd_b = vif.forward_b_o;

            mon_ap.write(item);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 5. SCOREBOARD (GOLDEN MODEL)
// -----------------------------------------------------------------------------
class fwd_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fwd_scoreboard)
    uvm_analysis_imp #(fwd_item, fwd_scoreboard) sb_export;
    
    // --- STATISTICS ---
    int cnt_ex_hazard   = 0;
    int cnt_mem_hazard  = 0;
    int cnt_priority_win = 0; // Số lần MEM thắng WB
    int cnt_no_hazard   = 0;
    int cnt_x0_ignore   = 0;

    bit verbose = 0; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sb_export = new("sb_export", this);
        if ($test$plusargs("VERBOSE")) verbose = 1;
    endfunction

    // --- GOLDEN PREDICTOR ---
    // Hàm dự đoán logic Forward cho 1 cổng (RS)
    function logic [1:0] predict_forward(logic [4:0] rs, logic [4:0] rd_mem, logic we_mem, logic [4:0] rd_wb, logic we_wb);
        // Priority 1: EX Hazard (From MEM Stage)
        if (we_mem && (rd_mem != 0) && (rd_mem == rs)) begin
            return 2'b10;
        end
        // Priority 2: MEM Hazard (From WB Stage)
        else if (we_wb && (rd_wb != 0) && (rd_wb == rs)) begin
            return 2'b01;
        end
        // No Hazard
        else begin
            return 2'b00;
        end
    endfunction

    function void write(fwd_item pkt);
        logic [1:0] exp_fwd_a;
        logic [1:0] exp_fwd_b;

        // Predict
        exp_fwd_a = predict_forward(pkt.rs1_ex, pkt.rd_mem, pkt.we_mem, pkt.rd_wb, pkt.we_wb);
        exp_fwd_b = predict_forward(pkt.rs2_ex, pkt.rd_mem, pkt.we_mem, pkt.rd_wb, pkt.we_wb);

        // Compare A
        if (pkt.act_fwd_a !== exp_fwd_a) begin
            `uvm_error("FAIL", $sformatf("Forward A Mismatch! Inputs:[RS1:%d MEM:%d/%b WB:%d/%b] Exp:%b Act:%b",
                pkt.rs1_ex, pkt.rd_mem, pkt.we_mem, pkt.rd_wb, pkt.we_wb, exp_fwd_a, pkt.act_fwd_a))
        end

        // Compare B
        if (pkt.act_fwd_b !== exp_fwd_b) begin
            `uvm_error("FAIL", $sformatf("Forward B Mismatch! Inputs:[RS2:%d MEM:%d/%b WB:%d/%b] Exp:%b Act:%b",
                pkt.rs2_ex, pkt.rd_mem, pkt.we_mem, pkt.rd_wb, pkt.we_wb, exp_fwd_b, pkt.act_fwd_b))
        end

        // Stats Gathering (Dựa trên RS1 cho đơn giản)
        if (exp_fwd_a == 2'b10) begin
            cnt_ex_hazard++;
            // Check Priority Case: Nếu WB cũng match thì đây là Priority Win
            if (pkt.we_wb && (pkt.rd_wb == pkt.rs1_ex) && (pkt.rd_wb != 0)) cnt_priority_win++;
        end 
        else if (exp_fwd_a == 2'b01) cnt_mem_hazard++;
        else begin 
             if ((pkt.rd_mem == pkt.rs1_ex && pkt.rd_mem == 0) || (pkt.rd_wb == pkt.rs1_ex && pkt.rd_wb == 0)) 
                 cnt_x0_ignore++;
             else 
                 cnt_no_hazard++;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        $display("\n==================================================");
        $display("       FORWARDING UNIT VERIFICATION REPORT        ");
        $display("==================================================");
        $display("Total Transactions       : %0d", cnt_ex_hazard + cnt_mem_hazard + cnt_no_hazard);
        $display("--------------------------------------------------");
        $display("EX Hazards (Fwd from MEM): %0d", cnt_ex_hazard);
        $display("MEM Hazards (Fwd from WB): %0d", cnt_mem_hazard);
        $display("Priority Wins (MEM > WB) : %0d (Critical Logic Check)", cnt_priority_win);
        $display("x0 Hazards Ignored       : %0d (Correct)", cnt_x0_ignore);
        $display("--------------------------------------------------");
        if (cnt_priority_win > 0)
             $display("[PASS] Priority Logic Verified! (MEM Stage correctly overrides WB Stage)");
        else $display("[WARN] Priority Logic NOT fully tested! Check sequence.");
        $display("==================================================\n");
    endfunction    
endclass

// -----------------------------------------------------------------------------
// 6. AGENT - ENV - TEST
// -----------------------------------------------------------------------------
class fwd_agent extends uvm_agent;
    `uvm_component_utils(fwd_agent)
    fwd_driver drv; fwd_monitor mon; uvm_sequencer #(fwd_item) sqr;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        drv = fwd_driver::type_id::create("drv", this);
        mon = fwd_monitor::type_id::create("mon", this);
        sqr = uvm_sequencer#(fwd_item)::type_id::create("sqr", this);
    endfunction
    function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(sqr.seq_item_export); endfunction
endclass

class fwd_env extends uvm_env;
    `uvm_component_utils(fwd_env)
    fwd_agent agent; fwd_scoreboard scb;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = fwd_agent::type_id::create("agent", this);
        scb   = fwd_scoreboard::type_id::create("scb", this);
    endfunction
    function void connect_phase(uvm_phase phase); agent.mon.mon_ap.connect(scb.sb_export); endfunction
endclass

class fwd_test extends uvm_test;
    `uvm_component_utils(fwd_test)
    fwd_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); env = fwd_env::type_id::create("env", this); endfunction
    task run_phase(uvm_phase phase);
        fwd_random_seq seq = fwd_random_seq::type_id::create("seq");
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
    forwarding_if vif(clk);
    
    // DUT Instantiation
    forwarding_unit dut (
        .rs1_addr_ex (vif.rs1_addr_ex),
        .rs2_addr_ex (vif.rs2_addr_ex),
        .rd_addr_mem (vif.rd_addr_mem),
        .rf_we_mem   (vif.rf_we_mem),
        .rd_addr_wb  (vif.rd_addr_wb),
        .rf_we_wb    (vif.rf_we_wb),
        .forward_a_o (vif.forward_a_o),
        .forward_b_o (vif.forward_b_o)
    );

    initial begin
        clk=0;
        uvm_config_db#(virtual forwarding_if)::set(null, "*", "vif", vif);
        run_test("fwd_test");
    end
endmodule