// =============================================================================
// UVM TESTBENCH TEMPLATE (QUESTA FREE COMPATIBLE)
// =============================================================================

import uvm_pkg::*;
`include "uvm_macros.svh"

// 1. INTERFACE
interface [TÊN_MODULE]_if (input logic clk_i);
    logic rst_ni;
    // [KHAI BÁO TÍN HIỆU TẠI ĐÂY]
    // logic [31:0] data_i;
    // logic [31:0] data_o;
endinterface

// 2. SEQUENCE ITEM
class [TÊN_MODULE]_item extends uvm_sequence_item;
    rand int delay;
    // [KHAI BÁO BIẾN RANDOM]
    
    `uvm_object_utils_begin([TÊN_MODULE]_item)
        `uvm_field_int(delay, UVM_ALL_ON | UVM_DEC)
        // `uvm_field_int(data_i, UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "[TÊN_MODULE]_item"); super.new(name); endfunction
endclass

// 3. DRIVER
class [TÊN_MODULE]_driver extends uvm_driver #([TÊN_MODULE]_item);
    `uvm_component_utils([TÊN_MODULE]_driver)
    virtual [TÊN_MODULE]_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual [TÊN_MODULE]_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "FATAL: Không tìm thấy Interface!")
    endfunction

    task run_phase(uvm_phase phase);
        // vif.signal <= 0; // Init signals
        @(posedge vif.rst_ni); 
        forever begin
            seq_item_port.get_next_item(req);
            @(posedge vif.clk_i);
            // [DRIVE LOGIC HERE]
            // vif.data_i <= req.data_i;
            repeat(req.delay) @(posedge vif.clk_i);
            seq_item_port.item_done();
        end
    endtask
endclass

// 4. MONITOR
class [TÊN_MODULE]_monitor extends uvm_monitor;
    `uvm_component_utils([TÊN_MODULE]_monitor)
    virtual [TÊN_MODULE]_if vif;
    uvm_analysis_port #([TÊN_MODULE]_item) mon_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        mon_port = new("mon_port", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual [TÊN_MODULE]_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "FATAL: Interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        [TÊN_MODULE]_item item;
        forever begin
            @(negedge vif.clk_i); // Sample at negedge
            item = [TÊN_MODULE]_item::type_id::create("item");
            // [SAMPLE LOGIC]
            // item.data_i = vif.data_i;
            mon_port.write(item);
        end
    endtask
endclass

// 5. SCOREBOARD
class [TÊN_MODULE]_scoreboard extends uvm_scoreboard;
    `uvm_component_utils([TÊN_MODULE]_scoreboard)
    uvm_analysis_imp #([TÊN_MODULE]_item, [TÊN_MODULE]_scoreboard) scb_export;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        scb_export = new("scb_export", this);
    endfunction

    function void write([TÊN_MODULE]_item trans);
        // [COMPARE LOGIC HERE]
    endfunction
endclass

// 6. AGENT & ENV (Standard)
class [TÊN_MODULE]_agent extends uvm_agent;
    `uvm_component_utils([TÊN_MODULE]_agent)
    [TÊN_MODULE]_driver    driver;
    [TÊN_MODULE]_monitor   monitor;
    uvm_sequencer #([TÊN_MODULE]_item) sequencer;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver    = [TÊN_MODULE]_driver::type_id::create("driver", this);
        monitor   = [TÊN_MODULE]_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer#([TÊN_MODULE]_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

class [TÊN_MODULE]_env extends uvm_env;
    `uvm_component_utils([TÊN_MODULE]_env)
    [TÊN_MODULE]_agent      agent;
    [TÊN_MODULE]_scoreboard scb;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = [TÊN_MODULE]_agent::type_id::create("agent", this);
        scb   = [TÊN_MODULE]_scoreboard::type_id::create("scb", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        agent.monitor.mon_port.connect(scb.scb_export);
    endfunction
endclass

// 7. SEQUENCE (Random Manual for Questa Free)
class [TÊN_MODULE]_rand_sequence extends uvm_sequence #([TÊN_MODULE]_item);
    `uvm_object_utils([TÊN_MODULE]_rand_sequence)
    function new(string name = ""); super.new(name); endfunction
    task body();
        repeat(100) begin
            req = [TÊN_MODULE]_item::type_id::create("req");
            start_item(req);
            // req.data_i = $urandom();
            req.delay = $urandom_range(0, 3);
            finish_item(req);
        end
    endtask
endclass

// 8. TEST
class [TÊN_MODULE]_basic_test extends uvm_test;
    `uvm_component_utils([TÊN_MODULE]_basic_test)
    [TÊN_MODULE]_env env;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = [TÊN_MODULE]_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        [TÊN_MODULE]_rand_sequence seq;
        seq = [TÊN_MODULE]_rand_sequence::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 9. TOP MODULE W/ CONSOLE MONITOR
// =============================================================================
module tb_top;
    import uvm_pkg::*;
    bit clk;
    always #5 clk = ~clk;

    [TÊN_MODULE]_if vif(clk);

    [TÊN_MODULE] dut (
        .clk_i    (clk),
        .rst_ni   (vif.rst_ni)
        // Connect signals...
    );

    initial begin
        vif.rst_ni = 0;
        uvm_config_db#(virtual [TÊN_MODULE]_if)::set(null, "*", "vif", vif);
        run_test(); 
    end

    initial begin
        #20; vif.rst_ni = 1;
    end

    // --- CONSOLE TABLE MONITOR (USER FAVORITE) ---
    initial begin
        // Tùy chỉnh Header cho từng module (Ví dụ dưới đây là mẫu, cần sửa lại tên cột)
        $display("\n==================================================================");
        $display(" Time      | Rst |  Signal_1  |  Signal_2  |  Output    | Status ");
        $display("-----------+-----+------------+------------+------------+--------");
        
        // Tùy chỉnh Format $monitor (%h=Hex, %b=Bin, %d=Dec)
        $monitor("%9t |  %b  | 0x%h | 0x%h | 0x%h | %s",
                 $time, 
                 vif.rst_ni,
                 // --- THAY TÊN TÍN HIỆU VÀO ĐÂY ---
                 // vif.signal_1, 
                 // vif.signal_2,
                 // vif.output_signal,
                 // ----------------------------------
                 0, 0, 0, // Placeholder values (Xóa dòng này khi điền tín hiệu thật)
                 (vif.rst_ni) ? "RUN " : "RST " // Simple Status logic
        );
    end
endmodule
