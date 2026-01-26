// =============================================================================
// UVM TESTBENCH FOR LSU (LOAD STORE UNIT)
// =============================================================================

import uvm_pkg::*;
`include "uvm_macros.svh"

// -----------------------------------------------------------------------------
// 1. INTERFACE
// -----------------------------------------------------------------------------
interface lsu_if (input logic clk_i);
    logic        rst_i;
    
    // Core Interface
    logic [31:0] addr_i;
    logic [31:0] wdata_i;
    logic        lsu_we_i;
    logic        lsu_req_i;
    logic [2:0]  funct3_i;
    
    // DMEM Interface
    logic [31:0] dmem_addr_o;
    logic [31:0] dmem_wdata_o;
    logic [3:0]  dmem_be_o;
    logic        dmem_we_o;
    logic [31:0] dmem_rdata_i;
    
    // Writeback Interface
    logic [31:0] lsu_rdata_o;
    logic        lsu_err_o;
endinterface

// -----------------------------------------------------------------------------
// 2. SEQUENCE ITEM
// -----------------------------------------------------------------------------
class lsu_item extends uvm_sequence_item;
    // Input Randomization
    rand bit [31:0] addr_i;
    rand bit [31:0] wdata_i;
    rand bit        lsu_we_i;
    rand bit        lsu_req_i;
    rand bit [2:0]  funct3_i;
    rand bit [31:0] dmem_rdata_i; // Giả lập dữ liệu trả về từ RAM
    rand int        delay;

    // Output Capture (No rand)
    bit [31:0] dmem_addr_o;
    bit [31:0] dmem_wdata_o;
    bit [3:0]  dmem_be_o;
    bit        dmem_we_o;
    bit [31:0] lsu_rdata_o;
    bit        lsu_err_o;

    `uvm_object_utils_begin(lsu_item)
        `uvm_field_int(addr_i, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(funct3_i, UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(lsu_err_o, UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    function new(string name = "lsu_item"); super.new(name); endfunction

    // Constraints để tạo test case có ý nghĩa
    constraint c_req { lsu_req_i dist {1:=90, 0:=10}; } // 90% là có request
    constraint c_funct3 { funct3_i inside {0, 1, 2, 4, 5}; } // Chỉ sinh các op hợp lệ (LB, LH, LW, LBU, LHU)
    // addr_i nên tập trung vào các trường hợp biên (0, 1, 2, 3 offset)
    constraint c_addr_offset { addr_i[1:0] dist {0:=40, 1:=20, 2:=20, 3:=20}; } 
endclass

// -----------------------------------------------------------------------------
// 3. DRIVER
// -----------------------------------------------------------------------------
class lsu_driver extends uvm_driver #(lsu_item);
    `uvm_component_utils(lsu_driver)
    virtual lsu_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual lsu_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "FATAL: Không tìm thấy Interface!")
    endfunction

    task run_phase(uvm_phase phase);
        // Init signals
        vif.lsu_req_i = 0;
        vif.lsu_we_i  = 0;
        
        @(posedge vif.rst_i); // Wait reset release
        
        forever begin
            seq_item_port.get_next_item(req);
            
            @(posedge vif.clk_i); // Drive at posedge
            vif.addr_i       <= req.addr_i;
            vif.wdata_i      <= req.wdata_i;
            vif.lsu_we_i     <= req.lsu_we_i;
            vif.lsu_req_i    <= req.lsu_req_i;
            vif.funct3_i     <= req.funct3_i;
            vif.dmem_rdata_i <= req.dmem_rdata_i;

            repeat(req.delay) @(posedge vif.clk_i);
            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. MONITOR
// -----------------------------------------------------------------------------
class lsu_monitor extends uvm_monitor;
    `uvm_component_utils(lsu_monitor)
    virtual lsu_if vif;
    uvm_analysis_port #(lsu_item) mon_port;

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
        lsu_item item;
        forever begin
            @(negedge vif.clk_i); // Sample output at negedge for stability
            if (vif.rst_i) begin
                item = lsu_item::type_id::create("item");
                
                // Sample Inputs
                item.addr_i       = vif.addr_i;
                item.wdata_i      = vif.wdata_i;
                item.lsu_we_i     = vif.lsu_we_i;
                item.lsu_req_i    = vif.lsu_req_i;
                item.funct3_i     = vif.funct3_i;
                item.dmem_rdata_i = vif.dmem_rdata_i;

                // Sample Outputs
                item.dmem_addr_o  = vif.dmem_addr_o;
                item.dmem_wdata_o = vif.dmem_wdata_o;
                item.dmem_be_o    = vif.dmem_be_o;
                item.dmem_we_o    = vif.dmem_we_o;
                item.lsu_rdata_o  = vif.lsu_rdata_o;
                item.lsu_err_o    = vif.lsu_err_o;

                mon_port.write(item);
            end
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 5. SCOREBOARD (GOLDEN MODEL)
// -----------------------------------------------------------------------------
class lsu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(lsu_scoreboard)
    uvm_analysis_imp #(lsu_item, lsu_scoreboard) scb_export;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        scb_export = new("scb_export", this);
    endfunction

    function void write(lsu_item trans);
        // --- GOLDEN MODEL LOGIC ---
        bit [1:0] offset;
        bit       exp_misaligned;
        bit [3:0] exp_be;
        bit [31:0] exp_wdata;
        bit [31:0] exp_lsu_rdata;
        bit [31:0] shifted_rdata;

        offset = trans.addr_i[1:0];
        exp_misaligned = 0;

        // 1. Check Misalignment
        if (trans.lsu_req_i) begin
            case (trans.funct3_i)
                3'b001, 3'b101: if (offset[0] != 0) exp_misaligned = 1; // Half
                3'b010:         if (offset != 0)    exp_misaligned = 1; // Word
            endcase
        end

        // 2. Compare Error Signal
        if (trans.lsu_err_o !== (exp_misaligned & trans.lsu_req_i)) begin
            `uvm_error("SCB", $sformatf("MISALIGNED MISMATCH! Addr: %h, Funct3: %b, ExpErr: %b, ActErr: %b", 
                trans.addr_i, trans.funct3_i, (exp_misaligned & trans.lsu_req_i), trans.lsu_err_o))
        end

        // 3. Check Store Logic (Only if no error and Write)
        if (trans.lsu_req_i && trans.lsu_we_i && !exp_misaligned) begin
            exp_wdata = trans.wdata_i << (offset * 8);
            
            case (trans.funct3_i)
                3'b000: exp_be = 4'b0001 << offset;
                3'b001: exp_be = 4'b0011 << offset;
                3'b010: exp_be = 4'b1111;
                default: exp_be = 0;
            endcase

            if (trans.dmem_wdata_o !== exp_wdata) 
                `uvm_error("SCB", $sformatf("STORE DATA MISMATCH! Offset: %d, Exp: %h, Act: %h", offset, exp_wdata, trans.dmem_wdata_o))
            if (trans.dmem_be_o !== exp_be) 
                `uvm_error("SCB", $sformatf("BYTE ENABLE MISMATCH! Offset: %d, Exp: %b, Act: %b", offset, exp_be, trans.dmem_be_o))
        end

        // 4. Check Load Logic
        shifted_rdata = trans.dmem_rdata_i >> (offset * 8);
        case (trans.funct3_i)
            3'b000: exp_lsu_rdata = {{24{shifted_rdata[7]}}, shifted_rdata[7:0]};
            3'b100: exp_lsu_rdata = {24'b0, shifted_rdata[7:0]};
            3'b001: exp_lsu_rdata = {{16{shifted_rdata[15]}}, shifted_rdata[15:0]};
            3'b101: exp_lsu_rdata = {16'b0, shifted_rdata[15:0]};
            3'b010: exp_lsu_rdata = shifted_rdata;
            default: exp_lsu_rdata = 0;
        endcase

        if (!exp_misaligned && !trans.lsu_we_i && trans.lsu_req_i && (trans.lsu_rdata_o !== exp_lsu_rdata)) begin
             `uvm_error("SCB", $sformatf("LOAD DATA MISMATCH! Funct3: %b, Raw: %h, Offset: %d, Exp: %h, Act: %h", 
                trans.funct3_i, trans.dmem_rdata_i, offset, exp_lsu_rdata, trans.lsu_rdata_o))
        end

    endfunction
endclass

// -----------------------------------------------------------------------------
// 6. AGENT & ENV
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
// 7. SEQUENCE (MANUAL RANDOMIZATION FOR FREE MODELSIM)
// -----------------------------------------------------------------------------
class lsu_rand_sequence extends uvm_sequence #(lsu_item);
    `uvm_object_utils(lsu_rand_sequence)
    
    function new(string name = ""); super.new(name); endfunction
    
    task body();
        int unsigned rand_idx;
        logic [2:0] valid_funct3 [5] = '{3'b000, 3'b001, 3'b010, 3'b100, 3'b101};

        repeat(5000) begin // Chạy 5000 test case
            req = lsu_item::type_id::create("req");
            start_item(req);

            // --- MANUAL RANDOMIZATION (Thay thế randomize()) ---
            
            // 1. Generate Request (90% chance High)
            req.lsu_req_i = ($urandom_range(0, 99) < 90); 

            // 2. Generate WE (50% Read, 50% Write)
            req.lsu_we_i  = $urandom_range(0, 1);

            // 3. Generate Funct3 (Pick random from valid array)
            rand_idx = $urandom_range(0, 4);
            req.funct3_i = valid_funct3[rand_idx];

            // 4. Generate Addr & Data (Full Random)
            req.addr_i  = $urandom(); 
            req.wdata_i = $urandom();
            
            // 5. Fake Memory Response
            req.dmem_rdata_i = $urandom();

            // 6. Delay
            req.delay = $urandom_range(0, 1);

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
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 9. TOP MODULE
// =============================================================================
module tb_top;
    import uvm_pkg::*;
    bit clk;
    always #5 clk = ~clk; // 100MHz

    lsu_if vif(clk);

    // Instantiate DUT
    lsu dut (
        .clk_i        (clk), // Unused in logic but present
        .rst_i       (vif.rst_i),
        
        .addr_i       (vif.addr_i),
        .wdata_i      (vif.wdata_i),
        .lsu_we_i     (vif.lsu_we_i),
        .lsu_req_i    (vif.lsu_req_i),
        .funct3_i     (vif.funct3_i),
        
        .dmem_addr_o  (vif.dmem_addr_o),
        .dmem_wdata_o (vif.dmem_wdata_o),
        .dmem_be_o    (vif.dmem_be_o),
        .dmem_we_o    (vif.dmem_we_o),
        .dmem_rdata_i (vif.dmem_rdata_i),
        
        .lsu_rdata_o  (vif.lsu_rdata_o),
        .lsu_err_o    (vif.lsu_err_o)
    );

    initial begin
        vif.rst_i = 0;
        uvm_config_db#(virtual lsu_if)::set(null, "*", "vif", vif);
        run_test("lsu_basic_test");
    end

    initial begin
        #20; vif.rst_i = 1;
    end

    // --- CONSOLE TABLE MONITOR ---
    initial begin
        $display("\n=================================================================================================");
        $display(" Time | Req | WE | Funct3 |   Addr (Off)  |     Data In      | BE  | Err |     Data Out     ");
        $display("------+-----+----+--------+---------------+------------------+-----+-----+------------------");
        //       %9t |  %b |  %b |   %b   | %h (%d) | %h | %b |  %b  | %h
        
        $monitor("%4t |  %b  | %b  |   %b  | %h (%1d) | %h | %b |  %b  | %h",
                 $time,
                 vif.lsu_req_i,
                 vif.lsu_we_i,
                 vif.funct3_i,
                 vif.addr_i, vif.addr_i[1:0], // In thêm offset cho dễ debug
                 vif.lsu_we_i ? vif.wdata_i : vif.dmem_rdata_i, // Nếu Store in WData, Load in ReadMem
                 vif.dmem_be_o,
                 vif.lsu_err_o,
                 vif.lsu_rdata_o
        );
    end
endmodule
