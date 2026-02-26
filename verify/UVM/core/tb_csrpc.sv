// =============================================================================
// FILE: tb_csrpc.sv
// DESCRIPTION: All-in-One UVM Testbench for RISC-V Core (Full Fix)
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
import riscv_instr::*;

`include "uvm_macros.svh"

// =============================================================================
// 1. INTERFACE
// =============================================================================
interface riscv_core_if (input logic clk_i, input logic rst_ni);
    // --- Standard IO ---
    logic [31:0] imem_addr;
    logic        imem_valid_req;
    logic        imem_ready_rsp;
    logic [31:0] imem_instr;
    logic        imem_valid_rsp;
    logic        imem_ready_req;

    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [3:0]  dmem_be;
    logic        dmem_we;
    logic        dmem_valid_req;
    logic        dmem_ready_rsp;
    logic [31:0] dmem_rdata;
    logic        dmem_valid_rsp;
    logic        dmem_ready_req;

    logic        irq_sw;
    logic        irq_timer;
    logic        irq_ext;

    // --- White-box Signals ---
    logic        wb_valid_retire; 
    logic        pipeline_stall;
    logic        pipeline_flush; 
    logic        m_unit_busy;
endinterface

// =============================================================================
// 2. TRANSACTION ITEM
// =============================================================================
class riscv_mem_cfg_item extends uvm_sequence_item;
    rand int imem_delay;
    rand int dmem_delay;
    rand bit [31:0] random_instr;

    `uvm_object_utils_begin(riscv_mem_cfg_item)
        `uvm_field_int(imem_delay, UVM_ALL_ON)
        `uvm_field_int(dmem_delay, UVM_ALL_ON)
        `uvm_field_int(random_instr, UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "riscv_mem_cfg_item"); super.new(name); endfunction
endclass

// =============================================================================
// 3. PERFORMANCE MONITOR
// =============================================================================
class riscv_perf_monitor extends uvm_monitor;
    `uvm_component_utils(riscv_perf_monitor)
    virtual riscv_core_if vif;

    real total_cycles  = 0;
    real instr_retired = 0;
    real stall_cycles  = 0;
    real flush_cycles  = 0;
    real m_unit_cycles = 0;

    // Instruction Statistics
    int instr_counts[string];
    real total_decoded = 0;    
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif))
            `uvm_fatal("PERF", "Interface not found!")
    endfunction

    // --- MAIN DECODER FUNCTION (RV32IM) ---
    function string get_mnemonic(logic [31:0] instr);
        logic [6:0] opcode = instr[6:0];
        logic [2:0] funct3 = instr[14:12];
        logic [6:0] funct7 = instr[31:25];

        case (opcode)
            // 1. R-TYPE (Integer Register-Register)
            7'b0110011: begin
                if (funct7 == 7'h01) begin // RV32M Extension
                    case (funct3)
                        3'b000: return "MUL";
                        3'b001: return "MULH";
                        3'b010: return "MULHSU";
                        3'b011: return "MULHU";
                        3'b100: return "DIV";
                        3'b101: return "DIVU";
                        3'b110: return "REM";
                        3'b111: return "REMU";
                        default: return "M-UNKNOWN";
                    endcase
                end else begin // Standard ALU
                    case (funct3)
                        3'b000: return (funct7[5]) ? "SUB" : "ADD";
                        3'b001: return "SLL";
                        3'b010: return "SLT";
                        3'b011: return "SLTU";
                        3'b100: return "XOR";
                        3'b101: return (funct7[5]) ? "SRA" : "SRL";
                        3'b110: return "OR";
                        3'b111: return "AND";
                        default: return "ALU-UNKNOWN";
                    endcase
                end
            end

            // 2. I-TYPE (Integer Register-Immediate)
            7'b0010011: begin
                case (funct3)
                    3'b000: return "ADDI";
                    3'b001: return "SLLI";
                    3'b010: return "SLTI";
                    3'b011: return "SLTIU";
                    3'b100: return "XORI";
                    3'b101: return (funct7[5]) ? "SRAI" : "SRLI";
                    3'b110: return "ORI";
                    3'b111: return "ANDI";
                    default: return "ADDI-UNKNOWN";
                endcase
            end

            // 3. LOAD
            7'b0000011: begin
                case (funct3)
                    3'b000: return "LB";
                    3'b001: return "LH";
                    3'b010: return "LW";
                    3'b100: return "LBU";
                    3'b101: return "LHU";
                    default: return "LOAD-UNKNOWN";
                endcase
            end

            // 4. STORE
            7'b0100011: begin
                case (funct3)
                    3'b000: return "SB";
                    3'b001: return "SH";
                    3'b010: return "SW";
                    default: return "STORE-UNKNOWN";
                endcase
            end

            // 5. BRANCH
            7'b1100011: begin
                case (funct3)
                    3'b000: return "BEQ";
                    3'b001: return "BNE";
                    3'b100: return "BLT";
                    3'b101: return "BGE";
                    3'b110: return "BLTU";
                    3'b111: return "BGEU";
                    default: return "BRANCH-UNKNOWN";
                endcase
            end

            // 6. JUMP & U-TYPE
            7'b1101111: return "JAL";
            7'b1100111: return "JALR";
            7'b0110111: return "LUI";
            7'b0010111: return "AUIPC";

            // 7. SYSTEM / CSR
            7'b1110011: begin
                if (funct3 == 0) return (instr[20]) ? "EBREAK" : "ECALL/MRET";
                case (funct3)
                    3'b001: return "CSRRW";
                    3'b010: return "CSRRS";
                    3'b011: return "CSRRC";
                    3'b101: return "CSRRWI";
                    3'b110: return "CSRRSI";
                    3'b111: return "CSRRCI";
                    default: return "CSR-UNKNOWN";
                endcase
            end
            
            // 8. FENCE
            7'b0001111: return "FENCE";

            default: return "UNKNOWN_OP";
        endcase
    endfunction

    task run_phase(uvm_phase phase);
        string mnem;
        @(posedge vif.rst_ni);
        forever begin
            @(posedge vif.clk_i);
            if (vif.rst_ni) begin
                total_cycles += 1;
                // --- Stats Counters ---
                 if (vif.wb_valid_retire) instr_retired += 1;
                 if (vif.pipeline_stall)  stall_cycles  += 1;
                 if (vif.pipeline_flush)  flush_cycles  += 1; 
                 if (vif.m_unit_busy)     m_unit_cycles += 1;

                // --- Instruction Decoding & Counting ---
                    if (vif.imem_valid_rsp && vif.imem_ready_req) begin
                        mnem = get_mnemonic(vif.imem_instr);
                        
                        if (instr_counts.exists(mnem)) 
                            instr_counts[mnem]++;
                        else 
                            instr_counts[mnem] = 1;
                            
                        total_decoded++;
                    end
            end
        end
    endtask

    function void report_phase(uvm_phase phase);
        real ipc = (total_cycles > 0) ? instr_retired / total_cycles : 0;
        string mnem_idx;
        real pct;
        $display("\n");
        $display("############################################################");
        $display("               RISC-V CORE PERFORMANCE REPORT               ");
        $display("############################################################");
        $display(" [GENERAL STATS]");
        $display("  Total Cycles    : %0d", total_cycles);
        $display("  Instr Retired   : %0d", instr_retired);
        $display("  IPC             : %0.4f", ipc);
        $display("  Stall Cycles    : %0d (%0.2f%%)", stall_cycles, (stall_cycles/total_cycles)*100);
        $display("  Flush Cycles    : %0d (%0.2f%%)", flush_cycles, (flush_cycles/total_cycles)*100);
        $display("  M-Unit Busy     : %0d (%0.2f%%)", m_unit_cycles, (m_unit_cycles/total_cycles)*100);
        $display("------------------------------------------------------------");
        $display(" [INSTRUCTION DISTRIBUTION (Fetched)]");
        $display("  Total Fetched   : %0d", total_decoded);
        $display("------------------------------------------------------------");
        
        // Loop through the associative array and print
        if (total_decoded > 0) begin
            foreach (instr_counts[mnem_idx]) begin
                pct = (real'(instr_counts[mnem_idx]) / total_decoded) * 100.0;
                $display("  %-10s : %6d / %0d (%0.2f %%)", mnem_idx, instr_counts[mnem_idx], total_decoded, pct);
            end
        end else begin
            $display("  No instructions fetched.");
        end
        $display("############################################################\n");
    endfunction
endclass

// =============================================================================
// 4. MEMORY DRIVER
// =============================================================================
class riscv_driver extends uvm_driver #(riscv_mem_cfg_item);
    `uvm_component_utils(riscv_driver)
    virtual riscv_core_if vif;
    
    // Memory Array
    bit [31:0] memory [bit [31:0]]; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Interface not found!")
    endfunction 

    task run_phase(uvm_phase phase);
        vif.imem_valid_rsp <= 0;
        vif.dmem_valid_rsp <= 0;
        vif.imem_ready_rsp <= 0;
        vif.dmem_ready_rsp <= 0;
        vif.irq_sw <= 0; vif.irq_timer <= 0; vif.irq_ext <= 0;

        @(posedge vif.rst_ni);

        fork
            handle_imem();
            handle_dmem();
        join
    endtask

    task handle_imem();
        bit got_item; 
        forever begin
            wait(vif.imem_valid_req);
            
            seq_item_port.try_next_item(req);
            if (req != null) begin
                got_item = 1; 
            end else begin
                got_item = 0;
                req = riscv_mem_cfg_item::type_id::create("default_req");
                req.imem_delay = 0;
                req.random_instr = 32'h00000013; // NOP
            end
            
            vif.imem_ready_rsp <= 0;
            repeat(req.imem_delay) @(posedge vif.clk_i);
            
            vif.imem_ready_rsp <= 1;
            @(posedge vif.clk_i);
            
            vif.imem_valid_rsp <= 1;
            
            if (got_item) begin
                vif.imem_instr <= req.random_instr; 
            end else if (memory.exists(vif.imem_addr)) begin
                vif.imem_instr <= memory[vif.imem_addr];
            end else begin
                vif.imem_instr <= 32'h00000013; // NOP
            end

            wait(vif.imem_ready_req); 
            @(posedge vif.clk_i);
            vif.imem_valid_rsp <= 0;
            
            if (got_item) seq_item_port.item_done();
        end
    endtask

    task handle_dmem();
        forever begin
            wait(vif.dmem_valid_req);
            
            vif.dmem_ready_rsp <= 0;
            repeat($urandom_range(0, 3)) @(posedge vif.clk_i); 
            
            vif.dmem_ready_rsp <= 1;
            @(posedge vif.clk_i);
            
            if (vif.dmem_we) memory[vif.dmem_addr] = vif.dmem_wdata;
            
            vif.dmem_valid_rsp <= 1;
            if (memory.exists(vif.dmem_addr)) vif.dmem_rdata <= memory[vif.dmem_addr];
            else vif.dmem_rdata <= 32'hDEADBEEF;
            
            wait(vif.dmem_ready_req);
            @(posedge vif.clk_i);
            vif.dmem_valid_rsp <= 0;
        end
    endtask
endclass

// =============================================================================
// 5. AGENT & ENV
// =============================================================================
class riscv_agent extends uvm_agent;
    `uvm_component_utils(riscv_agent)
    riscv_driver driver;
    uvm_sequencer #(riscv_mem_cfg_item) sequencer;
    
    function new(string name, uvm_component p); super.new(name, p); endfunction
    
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        driver = riscv_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(riscv_mem_cfg_item)::type_id::create("sequencer", this);
    endfunction
    
    function void connect_phase(uvm_phase phase); 
        driver.seq_item_port.connect(sequencer.seq_item_export); 
    endfunction
endclass

class riscv_env extends uvm_env;
    `uvm_component_utils(riscv_env)
    riscv_agent agent; riscv_perf_monitor perf_mon;
    
    function new(string name, uvm_component p); super.new(name, p); endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = riscv_agent::type_id::create("agent", this);
        perf_mon = riscv_perf_monitor::type_id::create("perf_mon", this);
    endfunction
endclass

// =============================================================================
// 6. SEQUENCE: FULL STRESS (UPGRADED VERSION)
// =============================================================================
class riscv_full_stress_seq extends uvm_sequence #(riscv_mem_cfg_item);
    `uvm_object_utils(riscv_full_stress_seq)
    function new(string name=""); super.new(name); endfunction

    // --- 1. CÁC HÀM BUILDER (Thêm S-Type và J-Type) ---
    
    function bit [31:0] build_r_type(logic [6:0] op, logic [2:0] f3, logic [6:0] f7);
        return {f7, 5'($urandom_range(0,31)), 5'($urandom_range(0,31)), f3, 5'($urandom_range(1,31)), op};
    endfunction

    function bit [31:0] build_u_type(logic [6:0] op);
        // U-Type: imm[31:12] | rd | opcode
        return {20'($urandom), 5'($urandom_range(1,31)), op};
    endfunction
    
    function bit [31:0] build_i_type(logic [6:0] op, logic [2:0] f3);
        return {12'($urandom), 5'($urandom_range(0,31)), f3, 5'($urandom_range(1,31)), op};
    endfunction

    // [NEW] Builder cho Store (S-Type)
    function bit [31:0] build_s_type(logic [6:0] op, logic [2:0] f3);
        bit [11:0] imm = $urandom;
        // Imm[11:5] | rs2 | rs1 | funct3 | Imm[4:0] | opcode
        return {imm[11:5], 5'($urandom_range(0,31)), 5'($urandom_range(0,31)), f3, imm[4:0], op};
    endfunction

    // [NEW] Builder cho Jump (J-Type - JAL)
    function bit [31:0] build_j_type();
        // JAL: Imm[20|10:1|11|19:12] | rd | opcode
        // Lưu ý: Imm của JAL khá lằng nhằng để ghép bit, ta random đơn giản và ép chẵn
        bit [31:0] instr;
        instr = {20'($urandom), 5'($urandom_range(1,31)), 7'b1101111};
        
        // Ép chẵn địa chỉ nhảy (Bit 21-30 chứa Imm, ta can thiệp sau khi ghép xong hơi khó)
        // Cách dễ nhất: Random đè vào vùng Imm một giá trị an toàn
        // Imm = +/- 1MB. 
        // Cấu trúc JAL: instr[31] = sign, [30:21] = imm[10:1], [20] = imm[11], [19:12] = imm[19:12]
        // Để ép chẵn (Imm[0]=0 - mặc định), ta cần ép bit Imm[1] (instr[21]?? Không, JAL encode khác)
        // JAL coding: 
        // 31    | 30:21     | 20      | 19:12     | 11:7 | 6:0
        // imm20 | imm[10:1] | imm[11] | imm[19:12] | rd   | opcode
        
        // Ta ép bit 21 (tương ứng imm[1]) về 0 để đảm bảo offset chẵn 4 byte cho an toàn tuyệt đối
        instr[21] = 1'b0; 
        return instr;
    endfunction

    // --- 2. RANDOM GENERATOR (Cập nhật tỷ lệ) ---
    function bit [31:0] get_rand_instr();
        int dice = $urandom_range(0, 99);
        bit [31:0] instr;
        
        // 0-30: ALU Reg-Reg (High IPC)
        if (dice < 30) begin
            instr = build_r_type(7'b0110011, 3'($urandom_range(0,7)), ($urandom_range(0,1) ? 7'h00 : 7'h20));
        end 
        // 30-40: Load (Cause Stall)
        else if (dice < 40) begin
            instr = build_i_type(7'b0000011, 3'b010); // LW
        end
        // 40-50:  Store (SW)
        else if (dice < 50) begin
            instr = build_s_type(7'b0100011, 3'b010); // SW
        end
        // 50-60: Branch (Cause Flush)
        else if (dice < 60) begin
            instr = {7'($urandom), 5'($urandom), 5'($urandom), 3'b000, 5'($urandom), 7'b1100011};
            instr[8] = 1'b0; // Ép chẵn
        end
        // 60-65:  Jump (JAL)
        else if (dice < 65) begin
            instr = build_j_type();
        end
        
        // 65-70: [NEW] LUI (Thêm phần này vào)
        else if (dice < 70) begin
            instr = build_u_type(7'b0110111); // Opcode LUI
        end

        // 70-85: M-Unit (Multi-cycle)
        else if (dice < 75) begin
            instr = build_r_type(7'b0110011, 3'($urandom_range(0,7)), 7'h01);
        end
        // 85-100: ADDI (Safe)
        else begin
            instr = build_i_type(7'b0010011, 3'b000); 
        end

        return instr;
    endfunction

    task body();
        bit [31:0] directed_code[];
        int k; 
        
        // --- PHASE 1: DIRECTED SCENARIOS ---
        `uvm_info("SEQ", "PHASE 1: Starting Directed Stress Test...", UVM_LOW)
        
        directed_code = new[20];
        // ALU
        directed_code[0] = 32'h00100093; // ADDI x1, x0, 1
        directed_code[1] = 32'h00200113; // ADDI x2, x0, 2
        directed_code[2] = 32'h002081b3; // ADD x3, x1, x2
        
        // [NEW] Store/Load Test
        directed_code[3] = 32'h00302023; // SW x3, 0(x0)  (Store 3 to Addr 0)
        directed_code[4] = 32'h00002203; // LW x4, 0(x0)  (Load back to x4)
        // Lưu ý: Với Mock Memory, lệnh LW sẽ lấy đúng giá trị vừa SW nếu cùng địa chỉ
        
        // M-Unit
        directed_code[5] = 32'h022082b3; // MUL x5, x1, x2
        directed_code[6] = 32'h0220c333; // DIV x6, x1, x2
        
        // Load-Use Hazard
        directed_code[7] = 32'h100003b7; // LUI x7, 0x10000
        directed_code[8] = 32'h0003a403; // LW x8, 0(x7)
        directed_code[9] = 32'h008384b3; // ADD x9, x7, x8 (STALL)
        
        // Branch Flush (Corrected Offset)
        directed_code[10] = 32'h00000663; // BEQ x0, x0, +12
        directed_code[11] = 32'h00100093; // ADDI (FLUSHED)
        directed_code[12] = 32'h00100093; // ADDI (FLUSHED)
        directed_code[13] = 32'h00100093; // ADDI (Target)

        foreach(directed_code[idx]) begin // Đổi tên biến lặp thành idx để tránh trùng
            req = riscv_mem_cfg_item::type_id::create("req");
            start_item(req);
            req.random_instr = directed_code[idx];
            req.imem_delay = 0; 
            req.dmem_delay = 1; 
            finish_item(req);
        end

        // --- PHASE 2: RANDOM 100,000 INSTRUCTIONS ---
        `uvm_info("SEQ", "PHASE 2: Starting Random 10,000 Instructions...", UVM_LOW)
        
        for (int i=0; i<100000; i++) begin
            req = riscv_mem_cfg_item::type_id::create("req");
            start_item(req);
            req.random_instr = get_rand_instr();
            
            if ($urandom_range(0,10) < 8) req.imem_delay = 0; 
            else req.imem_delay = $urandom_range(1, 3);       
            
            finish_item(req);
        end
        `uvm_info("SEQ", "PHASE 2: Completed.", UVM_LOW)
    endtask
endclass
// =============================================================================
// 7. TEST
// =============================================================================
class riscv_stress_test extends uvm_test;
    `uvm_component_utils(riscv_stress_test)
    riscv_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = riscv_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        riscv_full_stress_seq seq = riscv_full_stress_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 8. SVA MODULE (SYSTEMVERILOG ASSERTIONS - PRO)
// =============================================================================
module riscv_sva_checker (
    input logic        clk,
    input logic        rst_n,
    
    // Interface Signals
    input logic        imem_valid_req,
    input logic        imem_ready_rsp,
    input logic        dmem_valid_req,
    input logic        dmem_ready_rsp,
    
    // Architectural State
    input logic [31:0] pc_current,
    input logic        wb_valid,
    input logic [4:0]  wb_rd_addr,
    input logic        pipeline_stall,
    input logic        pipeline_flush 
);

    // --- CHECK 1: PROTOCOL STABILITY ---
    property p_imem_stable;
        @(posedge clk) disable iff (!rst_n)
        (imem_valid_req && !imem_ready_rsp) |=> $stable(imem_valid_req);
    endproperty
    A_IMEM_STABLE: assert property(p_imem_stable) else $error("[SVA] IMEM Req Unstable!");

    property p_dmem_stable;
        @(posedge clk) disable iff (!rst_n)
        (dmem_valid_req && !dmem_ready_rsp) |=> $stable(dmem_valid_req);
    endproperty
    A_DMEM_STABLE: assert property(p_dmem_stable) else $error("[SVA] DMEM Req Unstable!");

    // --- CHECK 2: PC ALIGNMENT (WITH X/Z CHECK) ---
    property p_pc_align;
        @(posedge clk) disable iff (!rst_n)
        (imem_valid_req && !$isunknown(pc_current)) |-> (pc_current[1:0] == 2'b00);
    endproperty
    A_PC_ALIGN: assert property(p_pc_align) else $error("[SVA] PC Misaligned: %h", pc_current);

    // --- CHECK 3: DEADLOCK ---
    property p_deadlock;
        @(posedge clk) disable iff (!rst_n)
        1 |-> ##[1:1000] wb_valid;
    endproperty
    A_DEADLOCK: assert property(p_deadlock) else $fatal(1, "[SVA FATAL] Deadlock detected!");

    // --- PROGRESS REPORT ---
    int total_instr = 0;
    always @(posedge clk) begin
        if (rst_n && wb_valid) begin
            total_instr++;
            if (total_instr % 1000 == 0) 
                $display("[SVA PROBE] Simulation Progress: %0d instructions retired @ %0t", total_instr, $time);
        end
    end
endmodule
// =============================================================================
// 8B. PERFORMANCE SVA (MANUAL REPORTING VERSION)
// =============================================================================
module riscv_perf_sva (
    input logic clk,
    input logic rst_n,
    input logic wb_valid_retire,
    input logic pipeline_stall
);

    // --- 1. KHAI BÁO BIẾN ĐẾM (COUNTERS) ---
    int cnt_burst = 0;
    int cnt_stall_short = 0;
    int cnt_stall_long = 0;
    int cnt_stall_hang = 0; // Stall > 100

    // --- 2. LOGIC ĐẾM (Action Blocks) ---
    
    // Đếm Burst (2 lệnh liên tiếp)
    C_BURST_MODE: cover property (@(posedge clk) wb_valid_retire ##1 wb_valid_retire) begin
        cnt_burst++; 
    end

    // Đếm Stall ngắn (1 cycle)
    C_STALL_SHORT: cover property (@(posedge clk) pipeline_stall ##1 !pipeline_stall) begin
        cnt_stall_short++;
    end

    // Đếm Stall trung bình (> 5 cycles)
    C_STALL_LONG: cover property (@(posedge clk) pipeline_stall [*5]) begin
        cnt_stall_long++;
    end

    // ASSERTION: Check Deadlock (> 150 cycles)
    // Dùng action block để đếm số lần bị tắc nghẽn nặng thay vì báo lỗi đỏ lòm
    property p_hang_stall;
        @(posedge clk) disable iff (!rst_n)
        $rose(pipeline_stall) |-> ##[1:150] !pipeline_stall;
    endproperty
    
    A_HANG_STALL: assert property(p_hang_stall) else begin
        cnt_stall_hang++;
        // Chỉ in cảnh báo, không làm dừng simulation
    //    $warning("[PERF INFO] Heavy Congestion detected (Stall > 150 cycles) at %0t", $time);
    end
    

    // --- 3. TỰ ĐỘNG IN BÁO CÁO KHI KẾT THÚC (FINAL BLOCK) ---
    // Block này tự chạy khi UVM gọi $finish
    final begin
        $display("\n");
        $display("===================================================");
        $display("           SVA PERFORMANCE REPORT (MANUAL)         ");
        $display("===================================================");
        $display(" [+ ] BURST MODE (IPC=1) Hits:      %0d", cnt_burst);
        $display(" [- ] Short Stalls (1 cyc) Hits:    %0d", cnt_stall_short);
        $display(" [--] Long Stalls (>5 cyc) Hits:    %0d", cnt_stall_long);
        $display(" [!!] Heavy Hangs (>150 cyc) Hits:  %0d", cnt_stall_hang);
        $display("===================================================");
        $display("SystemVerilog: Simulation Finished Correctly.");
        $display("\n");
    end

endmodule

// =============================================================================
// 9. TOP MODULE
// =============================================================================
module tb_top;
    logic clk;
    logic rst_n;

    always #5 clk = ~clk; // 100MHz

    riscv_core_if vif(clk, rst_n);

    // DUT
    riscv_core dut (
        .clk_i          (clk),
        .rst_i          (!rst_n),
        .irq_sw_i       (vif.irq_sw),
        .irq_timer_i    (vif.irq_timer),
        .irq_ext_i      (vif.irq_ext),
        .imem_addr_o    (vif.imem_addr),
        .imem_valid_o   (vif.imem_valid_req),
        .imem_ready_i   (vif.imem_ready_rsp),
        .imem_instr_i   (vif.imem_instr),
        .imem_valid_i   (vif.imem_valid_rsp),
        .imem_ready_o   (vif.imem_ready_req),
        .dmem_addr_o    (vif.dmem_addr),
        .dmem_wdata_o   (vif.dmem_wdata),
        .dmem_be_o      (vif.dmem_be),
        .dmem_we_o      (vif.dmem_we),
        .dmem_valid_o   (vif.dmem_valid_req),
        .dmem_ready_i   (vif.dmem_ready_rsp),
        .dmem_rdata_i   (vif.dmem_rdata),
        .dmem_valid_i   (vif.dmem_valid_rsp),
        .dmem_ready_o   (vif.dmem_ready_req)
    );

    // White-box Connections
    assign vif.wb_valid_retire = dut.mem_wb_valid_o;
    
    // [FIXED] Kết nối đúng tên tín hiệu với Interface 
    assign vif.pipeline_stall  = dut.pc_stall | dut.pipeline_stall;
    
    assign vif.pipeline_flush = dut.flush_pipeline | dut.id_ex_flush;
    
    assign vif.m_unit_busy     = dut.u_m_unit.valid_i; 

    // --- SVA BINDING ---
    riscv_sva_checker u_sva (
        .clk            (clk),
        .rst_n          (rst_n),
        
        .imem_valid_req (vif.imem_valid_req),
        .imem_ready_rsp (vif.imem_ready_rsp),
        .dmem_valid_req (vif.dmem_valid_req),
        .dmem_ready_rsp (vif.dmem_ready_rsp),
        
        .pc_current     (dut.imem_addr_o), 
        
        .wb_valid       (vif.wb_valid_retire),
        .wb_rd_addr     (dut.mem_wb_out.rd_addr),
        .pipeline_stall (vif.pipeline_stall),
        .pipeline_flush (vif.pipeline_flush) 
    );
riscv_perf_sva u_perf (
        .clk             (clk),
        .rst_n           (rst_n),
        .wb_valid_retire (vif.wb_valid_retire),
        .pipeline_stall  (vif.pipeline_stall)
    );
    // --- HELPER FUNCTION ---
    function string get_mnemonic(logic [31:0] instr);
        logic [6:0] op; 
        op = instr[6:0]; 
        case (op)
            7'b0110011: return (instr[25]) ? "M-UNIT" : "ALU-R";
            7'b0010011: return "ALU-I";
            7'b0000011: return "LOAD";
            7'b0100011: return "STORE";
            7'b1100011: return "BRANCH";
            7'b1101111: return "JAL";
            7'b0110111: return "LUI";
            default:    return "OTHER";
        endcase
    endfunction

    // --- CONSOLE TRACE ---
    initial begin
        $display("Time | PC | Instr | Type | State | Events");
    end
    always @(negedge clk) begin
        if (rst_n && (dut.imem_valid_o || dut.mem_wb_valid_o)) begin
            automatic string mnem; 
            mnem = get_mnemonic(dut.u_decoder.instr_i);
            
            if (dut.mem_wb_valid_o || dut.pipeline_stall || dut.flush_pipeline) begin
               // Logging (Uncomment to view)
               // $display("%0t | %h | %h | %s | %b | S:%b F:%b", $time, dut.id_ex_out.pc, dut.u_decoder.instr_i, mnem, dut.mem_wb_valid_o, dut.pipeline_stall, dut.pipeline_flush);
            end
            // if (dut.pipeline_stall && dut.u_m_unit.valid_i) $display("[DEBUG] Core is waiting for M-UNIT (Likely DIV/REM instruction)!");
        end
    end

    initial begin
        uvm_config_db#(virtual riscv_core_if)::set(null, "*", "vif", vif);
        run_test("riscv_stress_test");
    end

    initial begin
        clk = 0; rst_n = 0;
        #20 rst_n = 1;
    end
endmodule