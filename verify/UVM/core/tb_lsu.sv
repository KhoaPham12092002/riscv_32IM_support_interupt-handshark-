// =============================================================================
// UVM TESTBENCH FOR HANDSHAKE LSU
// =============================================================================

import uvm_pkg::*;
`include "uvm_macros.svh"
import riscv_32im_pkg::*; // Import package để dùng enum nếu cần

// -----------------------------------------------------------------------------
// 1. INTERFACE (Updated for Handshake)
// -----------------------------------------------------------------------------
interface lsu_if (input logic clk_i);
    logic        rst_i; // Active High Reset
    
    // --- Core Interface (Upstream) ---
    logic        valid_i;
    logic        ready_o;
    
    logic [31:0] addr_i;
    logic [31:0] wdata_i;
    logic        lsu_we_i;
    logic [2:0]  funct3_i;
    
    // --- Writeback Interface (Downstream) ---
    logic        valid_o;
    logic        ready_i;
    logic [31:0] lsu_rdata_o;
    logic        lsu_err_o;

    // --- DMEM Interface ---
    logic [31:0] dmem_addr_o;
    logic [31:0] dmem_wdata_o;
    logic [3:0]  dmem_be_o;
    logic        dmem_we_o;
    logic [31:0] dmem_rdata_i;
endinterface

// -----------------------------------------------------------------------------
// 2. SEQUENCE ITEM
// -----------------------------------------------------------------------------
class lsu_item extends uvm_sequence_item;
    // Input Stimulus
    rand bit [31:0] addr_i;
    rand bit [31:0] wdata_i;
    rand bit        lsu_we_i;   // 1=Store, 0=Load
    rand bit [2:0]  funct3_i;   // LB, LH, LW...
    rand bit [31:0] dmem_rdata_i; // Giả lập dữ liệu trả về từ RAM (cho lệnh Load)
    rand int        delay_cycles;
    rand bit valid_i;
    // Output Capture
    bit [31:0] dmem_addr_o;
    bit [31:0] dmem_wdata_o;
    bit [3:0]  dmem_be_o;
    bit        dmem_we_o;
    bit [31:0] lsu_rdata_o;
    bit        lsu_err_o;

    `uvm_object_utils_begin(lsu_item)
        `uvm_field_int(addr_i, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(lsu_we_i, UVM_DEFAULT)
        `uvm_field_int(funct3_i, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(valid_i , UVM_DEFAULT)
        `uvm_field_int(lsu_rdata_o, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(lsu_err_o, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "lsu_item"); super.new(name); endfunction

    // Constraints
    constraint c_valid { valid_i dist {1:=90, 0:=10}; }
    constraint c_funct3 { funct3_i inside {0, 1, 2, 4, 5}; } // Valid funct3
    // Tập trung test Misaligned address (0, 1, 2, 3)
    constraint c_addr_offset { addr_i[1:0] dist {0:=50, 1:=15, 2:=20, 3:=15}; } 
endclass

// -----------------------------------------------------------------------------
// 3. DRIVER (Implements Handshake Protocol)
// -----------------------------------------------------------------------------
class lsu_driver extends uvm_driver #(lsu_item);
    `uvm_component_utils(lsu_driver)
    virtual lsu_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual lsu_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "FATAL: Interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        // Init signals
        vif.valid_i   <= 0;
        vif.addr_i    <= 0;
        vif.wdata_i   <= 0;
        vif.lsu_we_i  <= 0;
        vif.funct3_i  <= 0;
        
        // Trong unit test đơn giản, ta lái luôn cổng dmem_rdata_i từ driver
        // để giả lập RAM luôn có dữ liệu sẵn sàng.
        vif.dmem_rdata_i <= 0; 
        
        @(negedge vif.rst_i); // Wait for Reset Release (Active High)
        @(posedge vif.clk_i);

        forever begin
            seq_item_port.get_next_item(req);
            
            // Random delay (Bubbles)
            repeat(req.delay_cycles) @(posedge vif.clk_i);

            // --- 1. ASSERT REQUEST ---
            vif.valid_i      <= req.valid_i;
            vif.addr_i       <= req.addr_i;
            vif.wdata_i      <= req.wdata_i;
            vif.lsu_we_i     <= req.lsu_we_i;
            vif.funct3_i     <= req.funct3_i;
            
            // Giả lập RAM trả data về (cho trường hợp Load)
            vif.dmem_rdata_i <= req.dmem_rdata_i; 

            // --- 2. WAIT FOR GRANT (Ready) ---
            do begin
                @(posedge vif.clk_i);
            end while (vif.ready_o !== 1'b1);

            // --- 3. DEASSERT REQUEST ---

            if (req.valid_i) begin 
                do begin @(posedge vif.clk_i); end while (vif.ready_o !== 1'b1);
                vif.valid_i <= 1'b0;
                end          
        seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. MONITOR (Input/Output Queueing)
// -----------------------------------------------------------------------------
class lsu_monitor extends uvm_monitor;
    `uvm_component_utils(lsu_monitor)
    virtual lsu_if vif;
    uvm_analysis_port #(lsu_item) mon_port;

    // Queue để lưu Input chờ Output tương ứng (xử lý Pipeline Latency)
    lsu_item pending_q[$]; 

    function new(string name, uvm_component parent);
        super.new(name, parent);
        mon_port = new("mon_port", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual lsu_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "FATAL: Interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_input();
            monitor_output();
        join
    endtask

    // Process 1: Capture Valid Input Handshake
    task monitor_input();
        forever begin
            @(negedge vif.clk_i);
            if (vif.valid_i && vif.ready_o) begin
                lsu_item item = lsu_item::type_id::create("item_in");
                item.addr_i       = vif.addr_i;
                item.wdata_i      = vif.wdata_i;
                item.lsu_we_i     = vif.lsu_we_i;
                item.funct3_i     = vif.funct3_i;
                item.dmem_rdata_i = vif.dmem_rdata_i;
                
                // Capture immediate DMEM control signals (Combinational at IDLE)
                item.dmem_addr_o  = vif.dmem_addr_o;
                item.dmem_wdata_o = vif.dmem_wdata_o;
                item.dmem_be_o    = vif.dmem_be_o;
                item.dmem_we_o    = vif.dmem_we_o;

                pending_q.push_back(item);
            end
        end
    endtask

    // Process 2: Capture Valid Output Handshake
    task monitor_output();
        forever begin
            @(negedge vif.clk_i);
            if (vif.valid_o && vif.ready_i) begin
                lsu_item item;
                if (pending_q.size() > 0) begin
                    item = pending_q.pop_front();
                    
                    // Capture Results
                    item.lsu_rdata_o = vif.lsu_rdata_o;
                    item.lsu_err_o   = vif.lsu_err_o;

                    mon_port.write(item);
                end else begin
                    `uvm_error("MON", "Spurious Output detected (No matching Input)!")
                end
            end
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 5. SCOREBOARD (Golden Model Logic)
// -----------------------------------------------------------------------------
class lsu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(lsu_scoreboard)
    uvm_analysis_imp #(lsu_item, lsu_scoreboard) scb_export;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        scb_export = new("scb_export", this);
    endfunction

    function void write(lsu_item trans);
        bit [1:0]  offset;
        bit        exp_misaligned;
        bit [3:0]  exp_be;
        bit [31:0] exp_dmem_wdata;
        bit [31:0] exp_lsu_rdata;
        bit [31:0] shifted_rdata;

        offset = trans.addr_i[1:0];
        exp_misaligned = 0;

        // --- 1. Check Misalignment ---
        case (trans.funct3_i[1:0])
            2'b01: if (offset[0] != 0) exp_misaligned = 1; // Half
            2'b10: if (offset != 0)    exp_misaligned = 1; // Word
        endcase

        // Verify Trap Signal
        if (trans.lsu_err_o !== exp_misaligned) begin
            `uvm_error("SCB", $sformatf("TRAP MISMATCH! Addr=%h, Funct3=%b | ExpErr=%b ActErr=%b", 
                       trans.addr_i, trans.funct3_i, exp_misaligned, trans.lsu_err_o))
        end

        // --- 2. Check Store Logic (Memory Interface) ---
        // Lưu ý: Logic này xảy ra ngay tại cycle IDLE
        if (trans.lsu_we_i && !exp_misaligned && trans.valid_i) begin
            exp_dmem_wdata = trans.wdata_i << (offset * 8);
            
            case (trans.funct3_i[1:0])
                2'b00: exp_be = 4'b0001 << offset; // SB
                2'b01: exp_be = 4'b0011 << offset; // SH
                2'b10: exp_be = 4'b1111;           // SW
                default: exp_be = 0;
            endcase

            if (trans.dmem_we_o !== 1'b1) 
                 `uvm_error("SCB", "DMEM_WE should be HIGH for valid store!")
            if (trans.dmem_wdata_o !== exp_dmem_wdata)
                 `uvm_error("SCB", $sformatf("WDATA MISMATCH! Exp=%h Act=%h", exp_dmem_wdata, trans.dmem_wdata_o))
            if (trans.dmem_be_o !== exp_be)
                 `uvm_error("SCB", $sformatf("BE MISMATCH! Exp=%b Act=%b", exp_be, trans.dmem_be_o))
        end else begin
            // Nếu là Load hoặc Lỗi, không được ghi RAM
            if (trans.dmem_we_o !== 1'b0)
                 `uvm_error("SCB", "DMEM_WE should be LOW for Load or Error!")
        end

        // --- 3. Check Load Logic (Result to Core) ---
        if (!trans.lsu_we_i && !exp_misaligned) begin
            shifted_rdata = trans.dmem_rdata_i >> (offset * 8);
            
            case (trans.funct3_i)
                3'b000: exp_lsu_rdata = {{24{shifted_rdata[7]}}, shifted_rdata[7:0]};   // LB
                3'b100: exp_lsu_rdata = {24'b0, shifted_rdata[7:0]};                   // LBU
                3'b001: exp_lsu_rdata = {{16{shifted_rdata[15]}}, shifted_rdata[15:0]}; // LH
                3'b101: exp_lsu_rdata = {16'b0, shifted_rdata[15:0]};                  // LHU
                3'b010: exp_lsu_rdata = shifted_rdata;                                 // LW
                default: exp_lsu_rdata = 0;
            endcase

            if (trans.lsu_rdata_o !== exp_lsu_rdata) begin
                 `uvm_error("SCB", $sformatf("LOAD DATA MISMATCH! Funct3=%b Raw=%h Off=%d | Exp=%h Act=%h", 
                            trans.funct3_i, trans.dmem_rdata_i, offset, exp_lsu_rdata, trans.lsu_rdata_o))
            end
        end

    endfunction
endclass

// -----------------------------------------------------------------------------
// 6. AGENT & ENV (Standard Boilerplate)
// -----------------------------------------------------------------------------
class lsu_agent extends uvm_agent;
    `uvm_component_utils(lsu_agent)
    lsu_driver    driver;
    lsu_monitor   monitor;
    uvm_sequencer #(lsu_item) sequencer;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver    = lsu_driver::type_id::create("driver", this);
        monitor   = lsu_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer#(lsu_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

class lsu_env extends uvm_env;
    `uvm_component_utils(lsu_env)
    lsu_agent      agent;
    lsu_scoreboard scb;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = lsu_agent::type_id::create("agent", this);
        scb   = lsu_scoreboard::type_id::create("scb", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        agent.monitor.mon_port.connect(scb.scb_export);
    endfunction
endclass

// -----------------------------------------------------------------------------
// 7. SEQUENCE
// -----------------------------------------------------------------------------
class lsu_rand_sequence extends uvm_sequence #(lsu_item);
    `uvm_object_utils(lsu_rand_sequence)
    function new(string name = ""); super.new(name); endfunction
    
    task body();
        int unsigned rand_idx;
        logic [2:0] valid_funct3 [5] = '{3'b000, 3'b001, 3'b010, 3'b100, 3'b101};

        repeat(100000) begin
            req = lsu_item::type_id::create("req");
            start_item(req);

            // Manual Randomization
            req.lsu_we_i = $urandom_range(0, 1);
            rand_idx = $urandom_range(0, 4);
            req.funct3_i = valid_funct3[rand_idx];
            req.addr_i   = $urandom(); 
            req.wdata_i  = $urandom();
            req.dmem_rdata_i = $urandom(); // Giả lập RAM
            req.delay_cycles = $urandom_range(0, 2);

            finish_item(req);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 8. TEST
// -----------------------------------------------------------------------------
class lsu_basic_test extends uvm_test;
    `uvm_component_utils(lsu_basic_test)
    lsu_env env;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = lsu_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        lsu_rand_sequence seq;
        seq = lsu_rand_sequence::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        #100; // Wait for pipeline to drain
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 9. TOP MODULE
// =============================================================================
module tb_top;
    import uvm_pkg::*;
    bit clk;
    always #5 clk = ~clk;

    lsu_if vif(clk);

    // Instantiate Handshake LSU
    lsu dut (
        .clk_i        (clk),
        .rst_i        (vif.rst_i), // Active High

        // Core
        .valid_i      (vif.valid_i),
        .ready_o      (vif.ready_o),
        .addr_i       (vif.addr_i),
        .wdata_i      (vif.wdata_i),
        .lsu_we_i     (vif.lsu_we_i),
        .funct3_i     (vif.funct3_i),

        // Writeback
        .valid_o      (vif.valid_o),
        .ready_i      (vif.ready_i),
        .lsu_rdata_o  (vif.lsu_rdata_o),
        .lsu_err_o    (vif.lsu_err_o),

        // DMEM
        .dmem_addr_o  (vif.dmem_addr_o),
        .dmem_wdata_o (vif.dmem_wdata_o),
        .dmem_be_o    (vif.dmem_be_o),
        .dmem_we_o    (vif.dmem_we_o),
        .dmem_rdata_i (vif.dmem_rdata_i)
    );

    // --- SETUP & RESET ---
    initial begin
        vif.rst_i = 1; // Assert Reset (Active High)
        uvm_config_db#(virtual lsu_if)::set(null, "*", "vif", vif);
        run_test("lsu_basic_test");
    end

    initial begin
        #20; vif.rst_i = 0; // Deassert Reset
    end

    // --- DOWNSTREAM BACK-PRESSURE SIMULATION ---
    // Giả lập Writeback Stage đôi khi bận
    initial begin
        vif.ready_i = 1;
        forever begin
            @(negedge clk);
            // 70% chance ready, 30% stall
            vif.ready_i = ($urandom_range(0, 9) < 7);
        end
    end

    // --- CONSOLE MONITOR ---
    initial begin
        $display("\n======================================================================================");
        $display(" Time | ValI RdyO | WE Fn3 |   Addr   |   Data In   | ValO RdyI | Err |   Data Out  ");
        $display("------+-----------+--------+----------+-------------+-----------+-----+-------------");
        
        $monitor("%4t |  %b    %b  | %b %3b | %h | %h |  %b    %b  |  %b  | %h",
                 $time,
                 vif.valid_i, vif.ready_o,
                 vif.lsu_we_i, vif.funct3_i,
                 vif.addr_i, 
                 (vif.lsu_we_i ? vif.wdata_i : vif.dmem_rdata_i),
                 vif.valid_o, vif.ready_i,
                 vif.lsu_err_o,
                 vif.lsu_rdata_o
        );
    end
endmodule