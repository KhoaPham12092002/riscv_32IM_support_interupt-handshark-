`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"
import riscv_32im_pkg::*; 

// =============================================================================
// 1. INTERFACE & ITEM (GIỮ NGUYÊN)
// =============================================================================
interface riscv_core_if (input logic clk_i);
    logic        rst_i;
    // IMEM
    logic [31:0] imem_addr_o;
    logic        imem_valid_o;
    logic        imem_ready_i;
    logic [31:0] imem_instr_i;
    logic        imem_valid_i;
    logic        imem_ready_o;
    // DMEM
    logic [31:0] dmem_addr_o;
    logic [31:0] dmem_wdata_o;
    logic [3:0]  dmem_be_o;
    logic        dmem_we_o;
    logic        dmem_valid_o;
    logic        dmem_ready_i;
    logic [31:0] dmem_rdata_i;
    logic        dmem_valid_i;
    logic        dmem_ready_o;
endinterface

class riscv_core_item extends uvm_sequence_item;
    rand int imem_delay; 
    rand int dmem_delay;
    constraint c_delay { imem_delay inside {[0:1]}; dmem_delay inside {[0:1]}; }
    `uvm_object_utils_begin(riscv_core_item)
        `uvm_field_int(imem_delay, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(dmem_delay, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end
    function new(string name = "riscv_core_item"); super.new(name); endfunction
endclass

// =============================================================================
// 2. DRIVER - CHỨA CHƯƠNG TRÌNH TEST FORWARDING (ĐÃ SỬA ĐỔI)
// =============================================================================
class riscv_core_driver extends uvm_driver #(riscv_core_item);
    `uvm_component_utils(riscv_core_driver)
    virtual riscv_core_if vif;
    logic [31:0] fake_imem [0:1023]; 
    logic [31:0] fake_dmem [0:255]; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        int i;
        // Init NOP
        for(i=0; i<1024; i++) fake_imem[i] = 32'h0000_0013;
        
        if (!uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "FATAL: Interface missing")

        // =====================================================================
        // CHƯƠNG TRÌNH "TRA TẤN" FORWARDING UNIT
        // =====================================================================
        
        // 1. Khởi tạo: x1 = 10, x2 = 20
        fake_imem[0] = 32'h00a00093; // ADDI x1, x0, 10
        fake_imem[1] = 32'h01400113; // ADDI x2, x0, 20

        // 2. TEST CASE A: EX-to-EX Forwarding (Hazard khoảng cách 1)
        // Lệnh 2 tính x3, Lệnh 3 dùng NGAY x3.
        // x3 = x1 + x2 = 10 + 20 = 30
        fake_imem[2] = 32'h002081b3; // ADD x3, x1, x2  (Write x3)
        
        // x4 = x3 + x1 = 30 + 10 = 40
        // (x3 nằm ở EX/MEM, Forwarding Unit phải lấy về cho x4 ở ID/EX)
        fake_imem[3] = 32'h00118233; // ADD x4, x3, x1  (Read x3 immediatly)

        // 3. TEST CASE B: MEM-to-EX Forwarding + EX-to-EX Mixed
        // Lệnh 3 ghi x4. Lệnh 2 ghi x3.
        // Lệnh 4 dùng cả x4 (Vừa tính xong - EX Hazard) và x3 (Cách 1 nhịp - MEM Hazard)
        // x5 = x4 + x3 = 40 + 30 = 70
        fake_imem[4] = 32'h003202b3; // ADD x5, x4, x3 

        // 4. TEST CASE C: SUB Forwarding
        // x6 = x5 - x4 = 70 - 40 = 30
        fake_imem[5] = 32'h40428333; // SUB x6, x5, x4

        // 5. Check Result: Store x5 (70) ra Memory để Monitor bắt được
        fake_imem[6] = 32'h00502023; // SW x5, 0(x0)

        // 6. Stop
        fake_imem[7] = 32'h0000006f; // JAL x0, 0
    endfunction

    task run_phase(uvm_phase phase);
        vif.imem_ready_i <= 0; vif.imem_valid_i <= 0; vif.imem_instr_i <= 0;
        vif.dmem_ready_i <= 0; vif.dmem_valid_i <= 0; vif.dmem_rdata_i <= 0;
        @(negedge vif.rst_i);
        forever begin
            seq_item_port.get_next_item(req);
            fork
                handle_imem(req.imem_delay);
                handle_dmem(req.dmem_delay);
            join
            seq_item_port.item_done();
        end
    endtask

    task handle_imem(int delay);
        vif.imem_ready_i <= 1;
        do @(posedge vif.clk_i); while (!(vif.imem_valid_o && vif.imem_ready_i));
        vif.imem_ready_i <= 0;
        repeat(delay) @(posedge vif.clk_i);
        vif.imem_valid_i <= 1;
        if (vif.imem_addr_o[11:2] < 1024) vif.imem_instr_i <= fake_imem[vif.imem_addr_o[11:2]];
        else vif.imem_instr_i <= 32'h00000013; 
        do @(posedge vif.clk_i); while (!(vif.imem_valid_i && vif.imem_ready_o));
        vif.imem_valid_i <= 0;
    endtask

    task handle_dmem(int delay);
        vif.dmem_ready_i <= 1;
        if (vif.dmem_valid_o) begin
            do @(posedge vif.clk_i); while (!(vif.dmem_valid_o && vif.dmem_ready_i));
            vif.dmem_ready_i <= 0;
            if (vif.dmem_we_o) fake_dmem[vif.dmem_addr_o[9:2]] = vif.dmem_wdata_o;
            repeat(delay) @(posedge vif.clk_i);
            if (!vif.dmem_we_o) begin
                vif.dmem_valid_i <= 1;
                vif.dmem_rdata_i <= fake_dmem[vif.dmem_addr_o[9:2]];
                do @(posedge vif.clk_i); while (!(vif.dmem_valid_i && vif.dmem_ready_o));
                vif.dmem_valid_i <= 0;
            end
        end else @(posedge vif.clk_i);
    endtask
endclass

// =============================================================================
// 3. MONITOR & SCOREBOARD & AGENT & ENV (GIỮ NGUYÊN STRUTCTURE)
// =============================================================================
class riscv_core_monitor extends uvm_monitor;
    `uvm_component_utils(riscv_core_monitor)
    virtual riscv_core_if vif;
    uvm_analysis_port #(riscv_core_item) mon_port;
    function new(string name, uvm_component parent); super.new(name, parent); mon_port = new("mon_port", this); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif); endfunction
    task run_phase(uvm_phase phase); endtask // Passive
endclass

class riscv_core_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(riscv_core_scoreboard)
    uvm_analysis_imp #(riscv_core_item, riscv_core_scoreboard) scb_export;
    function new(string name, uvm_component parent); super.new(name, parent); scb_export = new("scb_export", this); endfunction
    function void write(riscv_core_item trans); endfunction
endclass

class riscv_core_agent extends uvm_agent;
    `uvm_component_utils(riscv_core_agent)
    riscv_core_driver driver; riscv_core_monitor monitor; uvm_sequencer #(riscv_core_item) sequencer;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver = riscv_core_driver::type_id::create("driver", this);
        monitor = riscv_core_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer#(riscv_core_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase); driver.seq_item_port.connect(sequencer.seq_item_export); endfunction
endclass

class riscv_core_env extends uvm_env;
    `uvm_component_utils(riscv_core_env)
    riscv_core_agent agent; riscv_core_scoreboard scb;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = riscv_core_agent::type_id::create("agent", this);
        scb = riscv_core_scoreboard::type_id::create("scb", this);
    endfunction
    function void connect_phase(uvm_phase phase); agent.monitor.mon_port.connect(scb.scb_export); endfunction
endclass

class riscv_core_rand_sequence extends uvm_sequence #(riscv_core_item);
    `uvm_object_utils(riscv_core_rand_sequence)
    function new(string name = ""); super.new(name); endfunction
    task body();
        repeat(50) begin // Chạy ngắn thôi vì chương trình test ngắn
            req = riscv_core_item::type_id::create("req");
            start_item(req);
            req.imem_delay = 0; // Stress test: No delay để Pipeline chạy nhanh nhất
            req.dmem_delay = 0;
            finish_item(req);
        end
    endtask
endclass

class riscv_core_test extends uvm_test;
    `uvm_component_utils(riscv_core_test)
    riscv_core_env env;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); env = riscv_core_env::type_id::create("env", this); endfunction
    task run_phase(uvm_phase phase);
        riscv_core_rand_sequence seq;
        seq = riscv_core_rand_sequence::type_id::create("seq");
        phase.raise_objection(this);
        #100ns; seq.start(env.agent.sequencer); #500ns; // Đợi đủ lâu để kết quả ra
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 4. TOP MODULE (ĐÃ BẬT HIỂN THỊ LOG)
// =============================================================================
module tb_top;
    import uvm_pkg::*;
    bit clk; always #5 clk = ~clk; 
    riscv_core_if vif(clk);

    riscv_core dut (
        .clk_i(clk), .rst_i(vif.rst_i),
        .imem_addr_o(vif.imem_addr_o), .imem_valid_o(vif.imem_valid_o), .imem_ready_i(vif.imem_ready_i),
        .imem_instr_i(vif.imem_instr_i), .imem_valid_i(vif.imem_valid_i), .imem_ready_o(vif.imem_ready_o),
        .dmem_addr_o(vif.dmem_addr_o), .dmem_wdata_o(vif.dmem_wdata_o), .dmem_be_o(vif.dmem_be_o),
        .dmem_we_o(vif.dmem_we_o), .dmem_valid_o(vif.dmem_valid_o), .dmem_ready_i(vif.dmem_ready_i),
        .dmem_rdata_i(vif.dmem_rdata_i), .dmem_valid_i(vif.dmem_valid_i), .dmem_ready_o(vif.dmem_ready_o)
    );

    initial begin
        uvm_config_db#(virtual riscv_core_if)::set(null, "*", "vif", vif);
        run_test("riscv_core_test"); 
    end
    initial begin vif.rst_i = 1; #50; vif.rst_i = 0; end

    // -------------------------------------------------------------------------
    // SNOOPING MONITOR - SOI KẾT QUẢ GHI THANH GHI
    // -------------------------------------------------------------------------
    initial begin
        $display("\n===================== FORWARDING TEST START =====================");
    end

    always @(posedge clk) begin
        // Soi tín hiệu WB trong Core
        if (dut.mem_wb_valid_o && dut.mem_wb_ready_i && dut.mem_wb_out.ctrl.rf_we) begin
            if (dut.mem_wb_out.rd_addr != 0) begin
                $display("[WB-SNOOP] Time: %0t | Reg: x%0d | Val: %0d (0x%h)", 
                         $time, dut.mem_wb_out.rd_addr, $signed(dut.wb_final_data), dut.wb_final_data);
                
                // --- CHECK KẾT QUẢ TỰ ĐỘNG ---
                if (dut.mem_wb_out.rd_addr == 3 && dut.wb_final_data == 30) 
                    $display("    -> x3 = 10 + 20 = 30 [OK]");
                
                if (dut.mem_wb_out.rd_addr == 4 && dut.wb_final_data == 40) 
                    $display("    -> x4 = x3(30) + x1(10) = 40 [FORWARDING OK - EX HAZARD]");
                
                if (dut.mem_wb_out.rd_addr == 5 && dut.wb_final_data == 70) 
                    $display("    -> x5 = x4(40) + x3(30) = 70 [FORWARDING OK - MIXED HAZARD]");
                
                if (dut.mem_wb_out.rd_addr == 6 && dut.wb_final_data == 30) 
                    $display("    -> x6 = x5(70) - x4(40) = 30 [FORWARDING OK - SUB]");
            end
        end
    end
endmodule