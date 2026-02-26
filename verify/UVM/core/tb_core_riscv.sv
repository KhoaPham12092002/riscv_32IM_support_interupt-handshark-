`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"
import riscv_32im_pkg::*; 

// =============================================================================
// 1. INTERFACE (GIỮ NGUYÊN)
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

// =============================================================================
// 2. SEQUENCE ITEM (CẬP NHẬT)
// =============================================================================
class riscv_core_item extends uvm_sequence_item;
    // Mode: 0 = Load Instruction to Memory, 1 = Run CPU
    bit is_load_mode; 
    
    // Dữ liệu nạp vào Memory (Cho giai đoạn Setup)
    logic [31:0] load_addr;
    logic [31:0] load_instr;

    // Delay giả lập (Cho giai đoạn Run)
    rand int imem_delay; 
    rand int dmem_delay;

    constraint c_delay {
        imem_delay inside {[0:2]}; // Random delay ngắn để stress pipeline
        dmem_delay inside {[0:2]};
    }

    `uvm_object_utils_begin(riscv_core_item)
        `uvm_field_int(is_load_mode, UVM_DEFAULT)
        `uvm_field_int(load_addr,    UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(load_instr,   UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(imem_delay,   UVM_DEFAULT | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "riscv_core_item"); super.new(name); endfunction
endclass

// =============================================================================
// 3. DRIVER (THÔNG MINH HƠN)
// =============================================================================
class riscv_core_driver extends uvm_driver #(riscv_core_item);
    `uvm_component_utils(riscv_core_driver)
    virtual riscv_core_if vif;

    logic [31:0] fake_imem [0:4095]; // 16KB Instruction Memory
    logic [31:0] fake_dmem [0:1023]; // 4KB Data Memory

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        int i;
        // Init Memory với NOP
        for(i=0; i<4096; i++) fake_imem[i] = 32'h0000_0013; 
        for(i=0; i<1024; i++) fake_dmem[i] = 32'h0000_0000;
        
        if (!uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "FATAL: Interface Missing")
    endfunction

    task run_phase(uvm_phase phase);
        // 1. Reset Signals
        vif.imem_ready_i <= 0; vif.imem_valid_i <= 0; vif.imem_instr_i <= 0;
        vif.dmem_ready_i <= 0; vif.dmem_valid_i <= 0; vif.dmem_rdata_i <= 0;
        vif.rst_i <= 1; // Giữ Reset ban đầu

        forever begin
            seq_item_port.get_next_item(req);
            
            if (req.is_load_mode) begin
                // --- LOADING PHASE ---
                // Sequence gửi lệnh nào, Driver nạp lệnh đó vào fake_imem
                fake_imem[req.load_addr[13:2]] = req.load_instr;
            end 
            else begin
                // --- EXECUTION PHASE ---
                // Thả Reset nếu chưa thả
                if (vif.rst_i) begin
                    vif.rst_i <= 0;
                end
                
                // Xử lý request từ CPU
                fork 
                    handle_imem(req.imem_delay);
                    handle_dmem(req.dmem_delay);
                join
            end
            
            seq_item_port.item_done();
        end
    endtask

    // --- IMEM RESPONDER ---
    task handle_imem(int delay);
        // Wait CPU Request
        vif.imem_ready_i <= 1'b1;
        do @(posedge vif.clk_i); while (!(vif.imem_valid_o && vif.imem_ready_i));
        vif.imem_ready_i <= 0; 
        
        repeat(delay) @(posedge vif.clk_i);

        // Send Instruction
        vif.imem_valid_i <= 1'b1;
        // Map Address to Array
        if (vif.imem_addr_o[13:2] < 4096)
            vif.imem_instr_i <= fake_imem[vif.imem_addr_o[13:2]];
        else 
            vif.imem_instr_i <= 32'h00000013; // NOP if out of bound

        do @(posedge vif.clk_i); while (!(vif.imem_valid_i && vif.imem_ready_o));
        vif.imem_valid_i <= 0;
    endtask

    // --- DMEM RESPONDER ---
    task handle_dmem(int delay);
        vif.dmem_ready_i <= 1'b1;
        if (vif.dmem_valid_o) begin
            do @(posedge vif.clk_i); while (!(vif.dmem_valid_o && vif.dmem_ready_i));
            vif.dmem_ready_i <= 0;
            
            // WRITE
            if (vif.dmem_we_o) begin
                fake_dmem[vif.dmem_addr_o[11:2]] = vif.dmem_wdata_o;
            end

            repeat(delay) @(posedge vif.clk_i);

            // READ
            if (!vif.dmem_we_o) begin
                vif.dmem_valid_i <= 1'b1;
                vif.dmem_rdata_i <= fake_dmem[vif.dmem_addr_o[11:2]];
                do @(posedge vif.clk_i); while (!(vif.dmem_valid_i && vif.dmem_ready_o));
                vif.dmem_valid_i <= 0;
            end
        end else @(posedge vif.clk_i);
    endtask
endclass

// =============================================================================
// 4. SEQUENCE: HAZARD STRESS GENERATOR (PHẦN QUAN TRỌNG NHẤT)
// =============================================================================
class riscv_hazard_stress_seq extends uvm_sequence #(riscv_core_item);
    `uvm_object_utils(riscv_hazard_stress_seq)
    function new(string name = ""); super.new(name); endfunction

    // --- HELPER FUNCTIONS ĐỂ TẠO MÃ MÁY RISC-V ---
    function logic [31:0] enc_r_type(bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2, bit [2:0] f3, bit [6:0] f7, bit [6:0] op);
        return {f7, rs2, rs1, f3, rd, op};
    endfunction
    function logic [31:0] enc_i_type(bit [4:0] rd, bit [4:0] rs1, bit [11:0] imm, bit [2:0] f3, bit [6:0] op);
        return {imm, rs1, f3, rd, op};
    endfunction
    function logic [31:0] enc_store(bit [4:0] rs1, bit [4:0] rs2, bit [11:0] imm); // SW
        return {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    function logic [31:0] enc_branch(bit [4:0] rs1, bit [4:0] rs2, bit [12:0] imm); // BEQ
        // Imm[12|10:5|4:1|11]
        return {imm[12], imm[10:5], rs2, rs1, 3'b000, imm[4:1], imm[11], 7'b1100011}; 
    endfunction

    task body();
        int i;
        logic [31:0] instr;
        logic [31:0] current_addr = 0;
        
        // Variables for randomization
        bit [4:0] rd, rs1, rs2;
        bit [4:0] last_rd = 0; // Để tạo dependency
        bit [1:0] hazard_type;

        // ---------------------------------------------------------------------
        // PHASE 1: GENERATE PROGRAM & LOAD TO DRIVER
        // ---------------------------------------------------------------------
        `uvm_info("SEQ", "START GENERATING STRESS TEST PROGRAM...", UVM_NONE)

        // 1. INIT REGISTERS (x1-x5) với giá trị ban đầu để tránh x = 0
        for (i=1; i<=5; i++) begin
            instr = enc_i_type(i, 0, i*10, 3'b000, 7'b0010011); // ADDI xi, x0, i*10
            send_load_req(current_addr, instr);
            current_addr += 4;
        end

        // 2. RANDOM LOOP INSTRUCTIONS (Tạo 100 lệnh cực đoan)
        for (i=0; i<100; i++) begin
            // Constraint: Chỉ dùng Register x1 đến x5 để tỉ lệ trùng (collision) cực cao
            // Đây là bí quyết để ép Forwarding Unit hoạt động hết công suất
            rd  = $urandom_range(1, 5);
            
            // Logic tạo Hazard:
            // 60% dùng lại rd của lệnh trước cho rs1/rs2 (RAW Hazard)
            // 40% random rs1/rs2
            if ($urandom_range(0, 100) < 60 && last_rd != 0) begin
                rs1 = last_rd;
                rs2 = $urandom_range(1, 5);
            end else begin
                rs1 = $urandom_range(1, 5);
                rs2 = $urandom_range(1, 5);
            end

            // Random loại lệnh
            // 0: ALU Op (ADD/SUB/OR...) -> Test Forwarding EX-EX, MEM-EX
            // 1: LOAD Op -> Test Load-Use Hazard (Stall)
            // 2: BRANCH -> Test Control Hazard (Flush)
            hazard_type = $urandom_range(0, 5); // Bias về ALU nhiều hơn

            case (hazard_type)
                0, 1, 2: begin // ALU OPS (ADD)
                    instr = enc_r_type(rd, rs1, rs2, 3'b000, 7'b0000000, 7'b0110011); // ADD
                    send_load_req(current_addr, instr);
                    last_rd = rd;
                end
                
                3: begin // LOAD-USE TORTURE
                    // Lệnh 1: LOAD x(rd) từ mem
                    instr = enc_i_type(rd, rs1, 0, 3'b010, 7'b0000011); // LW rd, 0(rs1)
                    send_load_req(current_addr, instr);
                    current_addr += 4;
                    
                    // Lệnh 2: Dùng NGAY x(rd) -> Bắt buộc CPU phải Stall
                    // ADD x(rd), x(rd), x(rs2)
                    instr = enc_r_type(rd, rd, rs2, 3'b000, 7'b0000000, 7'b0110011); 
                    send_load_req(current_addr, instr);
                    
                    last_rd = rd;
                end

                4: begin // BRANCH (Control Hazard)
                    // BEQ x1, x1, +8 (Nhảy qua 1 lệnh NOP) - Always Taken
                    // Offset = 8
                    instr = enc_branch(rs1, rs1, 8); 
                    send_load_req(current_addr, instr);
                    current_addr += 4;
                    
                    // Lệnh này sẽ bị FLUSH nếu Branch Predictor (hoặc Logic nhảy) đúng
                    instr = 32'h00000013; // NOP (bị nhảy qua)
                    send_load_req(current_addr, instr);
                    // Không update last_rd vì branch không ghi reg
                end
                
                5: begin // STORE
                     instr = enc_store(rs1, rs2, 0); // SW rs2, 0(rs1)
                     send_load_req(current_addr, instr);
                end
            endcase
            
            current_addr += 4;
        end

        // 3. END TRAP
        instr = 32'h0000006f; // JAL x0, 0
        send_load_req(current_addr, instr);

        `uvm_info("SEQ", "PROGRAM GENERATION DONE. STARTING CPU...", UVM_NONE)

        // ---------------------------------------------------------------------
        // PHASE 2: RUN SIMULATION
        // ---------------------------------------------------------------------
        // Gửi các dummy transaction để Driver clocking bộ nhớ
        repeat(500) begin
            req = riscv_core_item::type_id::create("req");
            start_item(req);
            req.is_load_mode = 0; // Run mode
            req.imem_delay = $urandom_range(0, 1);
            req.dmem_delay = $urandom_range(0, 1);
            finish_item(req);
        end
    endtask

    // Helper task để gửi lệnh xuống Driver
    task send_load_req(logic [31:0] addr, logic [31:0] val);
        req = riscv_core_item::type_id::create("req");
        start_item(req);
        req.is_load_mode = 1;
        req.load_addr = addr;
        req.load_instr = val;
        finish_item(req);
    endtask
endclass

// =============================================================================
// 5. MONITOR & SCOREBOARD (GIỮ NGUYÊN STRUTURE)
// =============================================================================
// (Monitor và Scoreboard ở đây để trống hoặc implement logic check sau)
class riscv_core_monitor extends uvm_monitor;
    `uvm_component_utils(riscv_core_monitor)
    virtual riscv_core_if vif;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif); endfunction
    task run_phase(uvm_phase phase); endtask 
endclass

class riscv_core_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(riscv_core_scoreboard)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
endclass

// =============================================================================
// 6. AGENT & ENV & TEST
// =============================================================================
class riscv_core_agent extends uvm_agent;
    `uvm_component_utils(riscv_core_agent)
    riscv_core_driver driver; uvm_sequencer #(riscv_core_item) sequencer; riscv_core_monitor monitor;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver = riscv_core_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(riscv_core_item)::type_id::create("sequencer", this);
        monitor = riscv_core_monitor::type_id::create("monitor", this);
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
endclass

class riscv_hazard_test extends uvm_test;
    `uvm_component_utils(riscv_hazard_test)
    riscv_core_env env;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); env = riscv_core_env::type_id::create("env", this); endfunction
    task run_phase(uvm_phase phase);
        riscv_hazard_stress_seq seq;
        seq = riscv_hazard_stress_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 7. TOP MODULE
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
        run_test("riscv_hazard_test"); 
    end
    
    // --- DEBUG MONITOR ---
    // Hiển thị các lệnh được nạp vào
    // Và quan trọng nhất: Hiển thị trạng thái Hazard (Stall/Flush)
    always @(posedge clk) begin
        if (dut.u_hazard_unit.pc_stall_o) 
            $display("[HAZARD-DETECTED] Time: %0t | STALL REQUESTED! (Load-Use)", $time);
            
        if (dut.u_hazard_unit.id_ex_flush_o)
             $display("[HAZARD-DETECTED] Time: %0t | FLUSH REQUESTED! (Branch/Load-Use)", $time);

        if (dut.mem_wb_valid_o && dut.mem_wb_out.ctrl.rf_we && dut.mem_wb_out.rd_addr != 0)
            $display("[WB-RESULT] Time: %0t | x%0d = %0d", $time, dut.mem_wb_out.rd_addr, $signed(dut.wb_final_data));
    end

endmodule