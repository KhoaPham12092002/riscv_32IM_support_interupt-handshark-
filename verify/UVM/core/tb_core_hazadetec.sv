`timescale 1ns/1ps

// =============================================================================
// PACKAGE IMPORT & MACROS
// =============================================================================
import uvm_pkg::*;
`include "uvm_macros.svh"
import riscv_32im_pkg::*; 

// =============================================================================
// 1. INTERFACE
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
// 2. SEQUENCE ITEM
// =============================================================================
class riscv_core_item extends uvm_sequence_item;
    // Control bit: 1 = Nạp code vào Memory ảo, 0 = Chạy mô phỏng
    bit is_load_mode; 
    logic [31:0] load_addr;
    logic [31:0] load_instr;

    // Stress Params: Random delay trả về của Memory
    rand int imem_delay; 
    rand int dmem_delay;

    constraint c_delay { 
        imem_delay inside {[0:2]}; // Ép Pipeline phải chờ đợi (Elastic)
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
// 3. DRIVER (MEMORY SIMULATOR)
// =============================================================================
class riscv_core_driver extends uvm_driver #(riscv_core_item);
    `uvm_component_utils(riscv_core_driver)
    virtual riscv_core_if vif;

    logic [31:0] fake_imem [0:8191]; // 32KB Instruction Memory
    logic [31:0] fake_dmem [0:1023]; // 4KB Data Memory

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        // Init Memory = NOP
        for(int i=0; i<8192; i++) fake_imem[i] = 32'h0000_0013; 
        for(int i=0; i<1024; i++) fake_dmem[i] = 32'h0000_0000;

        if (!uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "FATAL: Interface Missing")
    endfunction

    task run_phase(uvm_phase phase);
        vif.imem_ready_i <= 0; vif.imem_valid_i <= 0; vif.imem_instr_i <= 0;
        vif.dmem_ready_i <= 0; vif.dmem_valid_i <= 0; vif.dmem_rdata_i <= 0;
        vif.rst_i <= 1;

        forever begin
            seq_item_port.get_next_item(req);
            
            if (req.is_load_mode) begin
                // Mode 1: Backdoor Load
                fake_imem[req.load_addr[14:2]] = req.load_instr;
            end 
            else begin
                // Mode 0: Run CPU
                if (vif.rst_i) vif.rst_i <= 0; // Thả Reset
                fork 
                    handle_imem(req.imem_delay);
                    handle_dmem(req.dmem_delay);
                join
            end
            seq_item_port.item_done();
        end
    endtask

    task handle_imem(int delay);
        vif.imem_ready_i <= 1;
        do @(posedge vif.clk_i); while (!(vif.imem_valid_o && vif.imem_ready_i));
        vif.imem_ready_i <= 0;
        
        repeat(delay) @(posedge vif.clk_i);

        vif.imem_valid_i <= 1;
        // Trả về lệnh từ fake_imem
        vif.imem_instr_i <= (vif.imem_addr_o[14:2] < 8192) ? fake_imem[vif.imem_addr_o[14:2]] : 32'h00000013;
        
        do @(posedge vif.clk_i); while (!(vif.imem_valid_i && vif.imem_ready_o));
        vif.imem_valid_i <= 0;
    endtask

    task handle_dmem(int delay);
        vif.dmem_ready_i <= 1;
        if (vif.dmem_valid_o) begin
            do @(posedge vif.clk_i); while (!(vif.dmem_valid_o && vif.dmem_ready_i));
            vif.dmem_ready_i <= 0;
            
            // Write Logic
            if (vif.dmem_we_o) fake_dmem[vif.dmem_addr_o[11:2]] = vif.dmem_wdata_o;

            repeat(delay) @(posedge vif.clk_i);

            // Read Logic
            if (!vif.dmem_we_o) begin
                vif.dmem_valid_i <= 1;
                vif.dmem_rdata_i <= fake_dmem[vif.dmem_addr_o[11:2]];
                do @(posedge vif.clk_i); while (!(vif.dmem_valid_i && vif.dmem_ready_o));
                vif.dmem_valid_i <= 0;
            end
        end else @(posedge vif.clk_i);
    endtask
endclass

// =============================================================================
// 4. SEQUENCE: SELF-CHECKING HAZARD STRESS
// =============================================================================
class riscv_hazard_stress_seq extends uvm_sequence #(riscv_core_item);
    `uvm_object_utils(riscv_hazard_stress_seq)
    function new(string name = ""); super.new(name); endfunction

    // --- Helper Functions: RISC-V Encoding ---
    function logic [31:0] enc_i(bit [4:0] rd, rs1, bit [11:0] imm, bit [2:0] f3, bit [6:0] op);
        return {imm, rs1, f3, rd, op}; 
    endfunction
    function logic [31:0] enc_r(bit [4:0] rd, rs1, rs2, bit [2:0] f3, bit [6:0] f7);
        return {f7, rs2, rs1, f3, rd, 7'b0110011};
    endfunction
    function logic [31:0] enc_s(bit [4:0] rs1, rs2, bit [11:0] imm);
        return {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011}; 
    endfunction
    function logic [31:0] enc_b(bit [4:0] rs1, rs2, bit [12:0] imm, bit [2:0] f3);
        return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
    endfunction

    // Variables
    logic [31:0] cur_pc = 0;
    logic [31:0] ERROR_PC = 32'h0000_2000;

    // --- Task: Gửi lệnh nạp vào Memory ---
    task send_instr(logic [31:0] instr);
        req = riscv_core_item::type_id::create("req");
        start_item(req);
        req.is_load_mode = 1; req.load_addr = cur_pc; req.load_instr = instr;
        finish_item(req);
        cur_pc += 4;
    endtask

    // --- Task: Tạo bẫy kiểm tra (Check Trap) ---
    task check_result(bit [4:0] reg_idx, bit [31:0] expected_val);
        // 1. Nạp giá trị mong đợi vào x31 (thanh ghi tạm)
        send_instr(enc_i(31, 0, expected_val, 0, 7'b0010011)); // ADDI x31, x0, expected
        
        // 2. So sánh: BEQ reg_idx, x31, +12 (Nếu đúng thì nhảy qua trap)
        send_instr(enc_b(reg_idx, 31, 12, 3'b000)); 
        
        // 3. TRAP: Nếu xuống đây nghĩa là SAI -> Ghi vào địa chỉ 0
        send_instr(enc_s(0, 0, 0)); // SW x0, 0(x0)
        
        // 4. Safe Zone (Nhảy tới đây nếu đúng)
        // (Không cần lệnh gì, chỉ là PC tiếp theo)
    endtask

    task body();
        // --- 1. DECLARATIONS ---
        int i;
        bit [4:0] r1, r2, r_dst;
        bit [31:0] val1, val2;
        int scenario;
        logic [31:0] saved_pc;

        `uvm_info("SEQ", "Generating HAZARD STRESS Program...", UVM_LOW)

        // --- 2. GENERATION LOOP (1000 iterations) ---
        for(i=0; i<1000; i++) begin
            // Randomize params
            r1 = $urandom_range(1, 5); // Dùng ít thanh ghi để dễ trùng (Hazard)
            r2 = $urandom_range(1, 5);
            r_dst = $urandom_range(6, 10);
            val1 = $urandom_range(1, 50);
            val2 = $urandom_range(1, 50);
            scenario = $urandom_range(0, 1);

            case(scenario)
                0: begin // === TEST FORWARDING (EX-EX) ===
                    // Lệnh 1: ADDI r1, x0, val1
                    send_instr(enc_i(r1, 0, val1, 0, 7'b0010011));
                    
                    // Lệnh 2: ADDI r_dst, r1, val2 (Dùng ngay r1 -> Hazard)
                    send_instr(enc_i(r_dst, r1, val2, 0, 7'b0010011));
                    
                    // Kiểm tra
                    check_result(r_dst, val1 + val2);
                end

                1: begin // === TEST LOAD-USE STALL ===
                    // Setup: Ghi val1 vào RAM tại địa chỉ 100
                    send_instr(enc_i(15, 0, val1, 0, 7'b0010011)); // li x15, val1
                    send_instr(enc_s(0, 15, 100));                // sw x15, 100(x0)
                    
                    // Lệnh 1: Load lại vào r1
                    send_instr(enc_i(r1, 0, 100, 3'b010, 7'b0000011)); // lw r1, 100(x0)
                    
                    // Lệnh 2: Dùng ngay r1 (Bắt buộc phải Stall)
                    send_instr(enc_r(r_dst, r1, r1, 0, 7'b0000000)); // add r_dst, r1, r1
                    
                    // Kiểm tra (r_dst = val1 + val1)
                    check_result(r_dst, val1 + val1);
                end
            endcase
        end

        // Finish
        send_instr(32'h0000006f); // JAL x0, 0

        // --- 3. RUN SIMULATION ---
        repeat(10000) begin
            req = riscv_core_item::type_id::create("req");
            start_item(req);
            req.is_load_mode = 0;
            req.imem_delay = $urandom_range(0, 2);
            req.dmem_delay = $urandom_range(0, 2);
            finish_item(req);
        end
    endtask
endclass

// =============================================================================
// 5. MONITOR & SCOREBOARD (REQUIRED BY UVM)
// =============================================================================
class riscv_core_monitor extends uvm_monitor;
    `uvm_component_utils(riscv_core_monitor)
    virtual riscv_core_if vif;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif); endfunction
    task run_phase(uvm_phase phase); endtask // Passive
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
// 7. TOP MODULE (SNOOPING FOR ERROR TRAP)
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

    // --- FATAL ERROR DETECTION (TRAP MONITOR) ---
    always @(posedge clk) begin
        // Nếu CPU ghi vào địa chỉ 0x00000000 -> Có nghĩa là Branch Check bị SAI -> Hazard Lỗi!
        if (vif.dmem_valid_o && vif.dmem_we_o && vif.dmem_addr_o == 0) begin
            $display("\n[!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!]");
            $display("[FATAL] CPU CALCULATION ERROR DETECTED at Time %0t", $time);
            $display("[FATAL] A Hazard (Forwarding/Stall) was MISSED.");
            $display("[!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!]\n");
            $stop;
        end
        
        // Debug: Báo Stall
        if (dut.u_hazard_unit.pc_stall_o)
            $display("[INFO] %0t: Stall Active (Load-Use Detected) at PC=%h", $time, dut.imem_addr_o);
    end
endmodule