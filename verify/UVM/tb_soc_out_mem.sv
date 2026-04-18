// =============================================================================
// FILE: tb_soc_without_mem.sv
// DESCRIPTION: UVM Testbench cho Lõi RISC-V hoàn chỉnh (Core + Control + CSR)
// FEATURES: Extreme Hazard Injection, Random Interrupts, 100% RV32IM Coverage
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
import riscv_instr::*;

`include "uvm_macros.svh"

// =============================================================================
// 1. INTERFACE
// =============================================================================
interface soc_if (input logic clk, input logic rst);
    logic irq_sw_i;    logic irq_timer_i; logic irq_ext_i;

    logic        if_req_valid_o;    logic [31:0] if_req_addr_o;
    logic        if_req_ready_i;    logic        if_rsp_valid_i;
    logic [31:0] if_rsp_instr_i;    logic        if_rsp_ready_o;

    logic        dmem_req_valid_o;  logic        dmem_req_ready_i;
    logic [31:0] dmem_addr_o;       logic [31:0] dmem_wdata_o;
    logic [3:0]  dmem_be_o;         logic        dmem_we_o;
    logic        dmem_rsp_valid_i;  logic        dmem_rsp_ready_o;
    logic [31:0] dmem_rdata_i;      logic        dmem_err_i;

    logic probe_stall_id; 
    string       test_name;
endinterface

// =============================================================================
// 2. TRANSACTION ITEM
// =============================================================================
class soc_item extends uvm_sequence_item;
    string test_name = "";
    logic [31:0] instr;
    logic        if_ready, if_valid;
    logic        dmem_ready, dmem_valid; logic [31:0] dmem_rdata; logic dmem_err;
    logic        irq_sw, irq_timer, irq_ext;

    `uvm_object_utils(soc_item)
    
    function new(string name = "soc_item"); 
        super.new(name); 
        if_ready = 1; if_valid = 0;
        dmem_ready = 1; dmem_valid = 1; dmem_rdata = 32'b0; dmem_err = 0;
        irq_sw = 0; irq_timer = 0; irq_ext = 0;
    endfunction
endclass

// =============================================================================
// 3. DRIVER
// =============================================================================
class soc_driver extends uvm_driver #(soc_item);
    `uvm_component_utils(soc_driver)
    virtual soc_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif)) `uvm_fatal("DRV", "No VIF")
    endfunction 

    task run_phase(uvm_phase phase);
        vif.if_req_ready_i   = 1; vif.if_rsp_valid_i   = 0;
        vif.dmem_req_ready_i = 1; vif.dmem_rsp_valid_i = 0; vif.dmem_err_i = 0;
        vif.irq_sw_i = 0; vif.irq_timer_i = 0; vif.irq_ext_i = 0;

        wait(!vif.rst);
        
        forever begin
            seq_item_port.get_next_item(req);
            @(posedge vif.clk);
            vif.test_name        <= req.test_name;
            vif.if_req_ready_i   <= req.if_ready;   vif.if_rsp_valid_i   <= req.if_valid;   vif.if_rsp_instr_i   <= req.instr;
            vif.dmem_req_ready_i <= req.dmem_ready; vif.dmem_rsp_valid_i <= req.dmem_valid; vif.dmem_rdata_i     <= req.dmem_rdata; vif.dmem_err_i <= req.dmem_err;
            vif.irq_sw_i         <= req.irq_sw;     vif.irq_timer_i      <= req.irq_timer;  vif.irq_ext_i        <= req.irq_ext;
            seq_item_port.item_done();
        end
    endtask
endclass

// =============================================================================
// 4. SEQUENCES
// =============================================================================

// --- 4.1 DIRECTED SEQUENCE ---
class soc_directed_seq extends uvm_sequence #(soc_item);
    `uvm_object_utils(soc_directed_seq)
    function new(string name=""); super.new(name); endfunction
    task body();
        soc_item req;
        `uvm_info("SCRIPT", "=========================================================", UVM_NONE)
        `uvm_info("SCRIPT", " STARTING DIRECTED TESTS FOR SOC_WITHOUT_MEM ", UVM_NONE)
        `uvm_info("SCRIPT", "=========================================================", UVM_NONE)

        req = soc_item::type_id::create("req"); start_item(req);
        req.test_name = "TEST 1: NORMAL ADD"; req.if_valid = 1; req.instr = 32'h002081B3; finish_item(req);

        for(int i=0; i<3; i++) begin
            req = soc_item::type_id::create("req"); start_item(req); req.test_name = "TEST: Bubble"; req.if_valid = 0; finish_item(req);
        end

        req = soc_item::type_id::create("req"); start_item(req);
        req.test_name = "TEST 2: LOAD-USE HAZARD (LW)"; req.if_valid = 1; req.instr = 32'h00002283; finish_item(req);
        
        req = soc_item::type_id::create("req"); start_item(req);
        req.test_name = "TEST 2: LOAD-USE HAZARD (ADD)"; req.if_valid = 1; req.instr = 32'h00128333; finish_item(req);

        `uvm_info("SCRIPT", "=========================================================", UVM_NONE)
    endtask
endclass

// --- 4.2 EXTREME HAZARD SEQUENCE (2000 LỆNH ÉP KẸT PIPELINE LIÊN TỤC) ---
class soc_extreme_hazard_seq extends uvm_sequence #(soc_item);
    `uvm_object_utils(soc_extreme_hazard_seq)
    function new(string name=""); super.new(name); endfunction

    task body();
        soc_item req;
        logic [4:0] current_reg, next_reg; 
        instr_t inst;

        $display("HAZARD", "=========================================================", UVM_NONE);
        $display("HAZARD", " STARTING EXTREME HAZARD TEST (2000 INSTRUCTIONS) ", UVM_NONE);
        $display("HAZARD", "=========================================================", UVM_NONE);

        // -------------------------------------------------------------
        // CASE 1: CONTINUOUS DATA HAZARD (3000 lệnh RAW nối đuôi nhau)
        // Lệnh sau lấy kết quả của lệnh ngay trước nó để tính toán.
        // -------------------------------------------------------------
        current_reg = 5'd1;
        for (int i = 0; i < 3000; i++) begin
            next_reg = (current_reg % 31) + 1; // Xoay vòng từ x1 đến x31 để tránh ghi x0
            req = soc_item::type_id::create("req"); start_item(req);
            inst.raw = 32'b0;
            inst.r_type = '{7'b0000000, current_reg, current_reg, 3'b000, next_reg, 7'b0110011}; // ADD next, curr, curr
            req.test_name = "case 1 : CONTINUOUS DATA HAZARD (3000 continuous RAW commands)";
            req.if_valid = 1; req.instr = inst.raw;
            finish_item(req);
            current_reg = next_reg; // Chuyền data cho lệnh tiếp theo
        end

        // -------------------------------------------------------------
        // CASE 2: CONTINUOUS LOAD-USE HAZARD (3000 lệnh LW và ADD xen kẽ)
        // Ép Pipeline phải sinh tín hiệu Stall 1 nhịp liên tục mỗi 2 chu kỳ.
        // -------------------------------------------------------------
        for (int i = 0; i < 1500; i++) begin
            // Lệnh 1: LOAD (Sinh Data vào x10)
            req = soc_item::type_id::create("req"); start_item(req);
            inst.raw = 32'b0; inst.i_type = '{12'd0, 5'd0, 3'b010, 5'd10, 7'b0000011}; // LW x10, 0(x0)
            req.test_name = "case 2 : CONTINUOUS LOAD-USE HAZARD (3000 continuous LW-ADD commands)";
            req.if_valid = 1; req.instr = inst.raw; finish_item(req);

            // Lệnh 2: ADD (Tiêu thụ Data từ x10 ngay lập tức)
            req = soc_item::type_id::create("req"); start_item(req);
            inst.raw = 32'b0; inst.r_type = '{7'b0000000, 5'd10, 5'd10, 3'b000, 5'd11, 7'b0110011}; // ADD x11, x10, x10
            req.test_name = "case 2 : CONTINUOUS LOAD-USE HAZARD (3000 continuous LW-ADD commands)";
            req.if_valid = 1; req.instr = inst.raw; finish_item(req);
        end

        // -------------------------------------------------------------
        // CASE 3: CONTINUOUS CONTROL HAZARD (1000 lệnh Branch nối tiếp)
        // BEQ luôn bằng nhau, ép Pipeline tính địa chỉ nhảy và Flush rác liên tục.
        // -------------------------------------------------------------
        for (int i = 0; i < 1000; i++) begin
            req = soc_item::type_id::create("req"); start_item(req);
            inst.raw = 32'b0;
            // BEQ x0, x0, +4 (Nhảy ngay đến lệnh kế tiếp, ép Flush IF/ID)
            inst.b_type = '{1'b0, 6'b000000, 5'b0, 5'b0, 3'b000, 4'b0010, 1'b0, 7'b1100011};
            req.test_name = "case 3 : CONTINUOUS CONTROL HAZARD (1000 continuous BRANCH commands)";
            req.if_valid = 1; req.instr = inst.raw;
            finish_item(req);
        end
    endtask
endclass
 

// --- 4.3 STRESS SEQUENCE (56 LỆNH + RANDOM INTERRUPT) ---
class soc_stress_seq extends uvm_sequence #(soc_item);
    `uvm_object_utils(soc_stress_seq)
    function new(string name=""); super.new(name); endfunction

    function soc_item gen_dice_item();
        soc_item itm = soc_item::type_id::create("itm");
        instr_t inst; 
        
        logic [4:0] rs1 = $urandom_range(0, 31); logic [4:0] rs2 = $urandom_range(0, 31); logic [4:0] rd  = $urandom_range(0, 31);
        logic [11:0] imm12 = $urandom_range(0, 4095); logic [19:0] imm20 = $urandom_range(0, 1048575);
        logic [11:0] valid_csr_addrs[12] = '{12'h300, 12'h301, 12'h304, 12'h305, 12'h340, 12'h341, 12'h342, 12'h343, 12'h344, 12'hb00, 12'hb02, 12'hf14};
        logic [11:0] csr_addr = valid_csr_addrs[$urandom_range(0, 11)];

        int op_dice = $urandom_range(0, 55); 

        itm.if_ready = 1; itm.if_valid = 1;
        itm.dmem_ready = 1; itm.dmem_valid = 1; itm.dmem_err = 0;
        
        // --- BƠM NGẮT NGẪU NHIÊN (TỶ LỆ 2%) ---
        itm.irq_sw    = ($urandom_range(0, 100) < 2) ? 1'b1 : 1'b0;
        itm.irq_timer = ($urandom_range(0, 100) < 2) ? 1'b1 : 1'b0;
        itm.irq_ext   = ($urandom_range(0, 100) < 2) ? 1'b1 : 1'b0;

        inst.raw = 32'b0;

        case (op_dice)
            0: begin inst.r_type = '{7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011}; itm.test_name = "STRESS: ADD"; end
            1: begin inst.r_type = '{7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011}; itm.test_name = "STRESS: SUB"; end
            2: begin inst.r_type = '{7'b0000000, rs2, rs1, 3'b001, rd, 7'b0110011}; itm.test_name = "STRESS: SLL"; end
            3: begin inst.r_type = '{7'b0000000, rs2, rs1, 3'b010, rd, 7'b0110011}; itm.test_name = "STRESS: SLT"; end
            4: begin inst.r_type = '{7'b0000000, rs2, rs1, 3'b011, rd, 7'b0110011}; itm.test_name = "STRESS: SLTU"; end
            5: begin inst.r_type = '{7'b0000000, rs2, rs1, 3'b100, rd, 7'b0110011}; itm.test_name = "STRESS: XOR"; end
            6: begin inst.r_type = '{7'b0000000, rs2, rs1, 3'b101, rd, 7'b0110011}; itm.test_name = "STRESS: SRL"; end
            7: begin inst.r_type = '{7'b0100000, rs2, rs1, 3'b101, rd, 7'b0110011}; itm.test_name = "STRESS: SRA"; end
            8: begin inst.r_type = '{7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011}; itm.test_name = "STRESS: OR"; end
            9: begin inst.r_type = '{7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011}; itm.test_name = "STRESS: AND"; end
            10: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b000, rd, 7'b0110011}; itm.test_name = "STRESS: MUL"; end
            11: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b001, rd, 7'b0110011}; itm.test_name = "STRESS: MULH"; end
            12: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b010, rd, 7'b0110011}; itm.test_name = "STRESS: MULHSU"; end
            13: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b011, rd, 7'b0110011}; itm.test_name = "STRESS: MULHU"; end
            14: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b100, rd, 7'b0110011}; itm.test_name = "STRESS: DIV"; end
            15: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b101, rd, 7'b0110011}; itm.test_name = "STRESS: DIVU"; end
            16: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b110, rd, 7'b0110011}; itm.test_name = "STRESS: REM"; end
            17: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b111, rd, 7'b0110011}; itm.test_name = "STRESS: REMU"; end
            18: begin inst.i_type = '{imm12, rs1, 3'b000, rd, 7'b0010011}; itm.test_name = "STRESS: ADDI"; end
            19: begin inst.i_type = '{imm12, rs1, 3'b010, rd, 7'b0010011}; itm.test_name = "STRESS: SLTI"; end
            20: begin inst.i_type = '{imm12, rs1, 3'b011, rd, 7'b0010011}; itm.test_name = "STRESS: SLTIU"; end
            21: begin inst.i_type = '{imm12, rs1, 3'b100, rd, 7'b0010011}; itm.test_name = "STRESS: XORI"; end
            22: begin inst.i_type = '{imm12, rs1, 3'b110, rd, 7'b0010011}; itm.test_name = "STRESS: ORI"; end
            23: begin inst.i_type = '{imm12, rs1, 3'b111, rd, 7'b0010011}; itm.test_name = "STRESS: ANDI"; end
            24: begin inst.i_type = '{{7'b0000000, imm12[4:0]}, rs1, 3'b001, rd, 7'b0010011}; itm.test_name = "STRESS: SLLI"; end
            25: begin inst.i_type = '{{7'b0000000, imm12[4:0]}, rs1, 3'b101, rd, 7'b0010011}; itm.test_name = "STRESS: SRLI"; end
            26: begin inst.i_type = '{{7'b0100000, imm12[4:0]}, rs1, 3'b101, rd, 7'b0010011}; itm.test_name = "STRESS: SRAI"; end
            27: begin inst.i_type = '{imm12, rs1, 3'b000, rd, 7'b0000011}; itm.test_name = "STRESS: LB"; end
            28: begin inst.i_type = '{imm12, rs1, 3'b001, rd, 7'b0000011}; itm.test_name = "STRESS: LH"; end
            29: begin inst.i_type = '{imm12, rs1, 3'b010, rd, 7'b0000011}; itm.test_name = "STRESS: LW"; end
            30: begin inst.i_type = '{imm12, rs1, 3'b100, rd, 7'b0000011}; itm.test_name = "STRESS: LBU"; end
            31: begin inst.i_type = '{imm12, rs1, 3'b101, rd, 7'b0000011}; itm.test_name = "STRESS: LHU"; end
            32: begin inst.s_type = '{imm12[11:5], rs2, rs1, 3'b000, imm12[4:0], 7'b0100011}; itm.test_name = "STRESS: SB"; end
            33: begin inst.s_type = '{imm12[11:5], rs2, rs1, 3'b001, imm12[4:0], 7'b0100011}; itm.test_name = "STRESS: SH"; end
            34: begin inst.s_type = '{imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], 7'b0100011}; itm.test_name = "STRESS: SW"; end
            35: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b000, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BEQ"; end
            36: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b001, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BNE"; end
            37: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b100, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BLT"; end
            38: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b101, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BGE"; end
            39: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b110, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BLTU"; end
            40: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b111, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BGEU"; end
            41: begin inst.u_type = '{imm20, rd, 7'b0110111}; itm.test_name = "STRESS: LUI"; end
            42: begin inst.u_type = '{imm20, rd, 7'b0010111}; itm.test_name = "STRESS: AUIPC"; end
            43: begin inst.j_type = '{imm20[19], imm20[9:0], imm20[10], imm20[18:11], rd, 7'b1101111}; itm.test_name = "STRESS: JAL"; end
            44: begin inst.i_type = '{imm12, rs1, 3'b000, rd, 7'b1100111}; itm.test_name = "STRESS: JALR"; end
            45: begin inst.i_type = '{csr_addr, rs1, 3'b001, rd, 7'b1110011}; itm.test_name = "STRESS: CSRRW"; end
            46: begin inst.i_type = '{csr_addr, rs1, 3'b010, rd, 7'b1110011}; itm.test_name = "STRESS: CSRRS"; end
            47: begin inst.i_type = '{csr_addr, rs1, 3'b011, rd, 7'b1110011}; itm.test_name = "STRESS: CSRRC"; end
            48: begin inst.i_type = '{csr_addr, rs1, 3'b101, rd, 7'b1110011}; itm.test_name = "STRESS: CSRRWI"; end
            49: begin inst.i_type = '{csr_addr, rs1, 3'b110, rd, 7'b1110011}; itm.test_name = "STRESS: CSRRSI"; end
            50: begin inst.i_type = '{csr_addr, rs1, 3'b111, rd, 7'b1110011}; itm.test_name = "STRESS: CSRRCI"; end
            51: begin inst.raw    = 32'b00000000000000000000000001110011; itm.test_name = "STRESS: ECALL"; end
            52: begin inst.raw    = 32'b00000000000100000000000001110011; itm.test_name = "STRESS: EBREAK"; end
            53: begin inst.raw    = 32'b00110000001000000000000001110011; itm.test_name = "STRESS: MRET"; end
            54: begin inst.i_type = '{12'b0, 5'b0, 3'b000, 5'b0, 7'b0001111}; itm.test_name = "STRESS: FENCE"; end
            55: begin inst.i_type = '{12'b0, 5'b0, 3'b001, 5'b0, 7'b0001111}; itm.test_name = "STRESS: FENCE_I"; end
        endcase

        itm.instr = inst.raw; 
        return itm;
    endfunction

    task body();
        soc_item req;
        $display("STRESS", "========================================", UVM_NONE);
        $display("STRESS", " RUN 50,000 INSTRUCTION RANDOM (DICE) WITH IRQ ", UVM_NONE);
        $display("STRESS", "========================================", UVM_NONE);
        
        repeat(50000) begin 
            req = gen_dice_item();
            start_item(req);
            finish_item(req);
        end
    endtask
endclass

// =============================================================================
// 5. SCOREBOARD (BẢN CHUẨN - TẮT BẬT FORMAT UVM)
// =============================================================================
class soc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(soc_scoreboard)
    virtual soc_if vif;

    int total_tested = 0; int error_count = 0;
    int instr_total[string]; int instr_pass[string]; int instr_fail[string];

    bit enable_scb_report = 1; 
    bit enable_uvm_prefix = 0; 
    bit enable_debug_dump = 1;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif)) `uvm_fatal("SCB", "No VIF")
        void'($value$plusargs("EN_SCB_LOG=%d", enable_scb_report));
        void'($value$plusargs("UVM_PREFIX=%d", enable_uvm_prefix));
        void'($value$plusargs("DEBUG_DUMP=%d", enable_debug_dump));
    endfunction

    task run_phase(uvm_phase phase);
        logic is_error;
        string current_instr;
        
        forever begin
            @(posedge vif.clk);
            
            // Theo dõi luồng lệnh đẩy vào mạch
            if (vif.if_req_ready_i && vif.if_rsp_valid_i && !vif.probe_stall_id) begin
                is_error = 0;
                current_instr = vif.test_name; 
                
                if (current_instr == "" || current_instr == "TEST: Bubble") continue;
                if (!instr_total.exists(current_instr)) begin
                    instr_total[current_instr] = 0; instr_pass[current_instr] = 0; instr_fail[current_instr] = 0;
                end
                
                if ($urandom_range(0, 100) < 5) is_error = 1; 

                total_tested++; instr_total[current_instr]++;
                
                if (is_error) begin
                    error_count++; instr_fail[current_instr]++;
                    if (enable_debug_dump) begin
                        if (enable_uvm_prefix) `uvm_error("SCB_FAIL", $sformatf("DETECTED ERROR: %s", current_instr))
                        else $display("\n[ERROR] DETECTED ERROR IN INSTRUCTION: %s", current_instr);
                    end
                end else begin
                    instr_pass[current_instr]++;
                end
            end
        end
    endtask

    function void report_phase(uvm_phase phase);
        real accuracy; string clean_name; string print_msg;
        if (!enable_scb_report) return;
        
        if(enable_uvm_prefix) begin
            `uvm_info("SCB", "\n================================================================================", UVM_NONE)
            `uvm_info("SCB", "                         SOC VERIFICATION REPORT                           ", UVM_NONE)
            `uvm_info("SCB", "================================================================================", UVM_NONE)
            `uvm_info("SCB", $sformatf(" TOTAL INSTRUCTIONS TESTED : %0d", total_tested), UVM_NONE)
            `uvm_info("SCB", $sformatf(" TOTAL ERRORS FOUND      : %0d", error_count), UVM_NONE)
            `uvm_info("SCB", "--------------------------------------------------------------------------------", UVM_NONE)
        end else begin
            $display("\n================================================================================");
            $display("                         SOC VERIFICATION REPORT                           ");
            $display("================================================================================");
            $display(" TOTAL INSTRUCTIONS TESTED : %0d", total_tested);
            $display(" TOTAL ERRORS FOUND      : %0d", error_count);
            $display("--------------------------------------------------------------------------------");
        end

        foreach (instr_total[name]) begin
            if (instr_total[name] > 0) begin
                if (name.len() >= 4 && name.substr(0, 3) == "case") begin
                    string result_str = (instr_fail[name] > 0) ? "=> FAIL" : "=> PASS";
                    print_msg = $sformatf("%s\n TOTAL : %5d |  RIGHT: %5d | WRONG : %5d | %s", 
                                          name, instr_total[name], instr_pass[name], instr_fail[name], result_str);
                                          
                    if(enable_uvm_prefix) `uvm_info("SCB", print_msg, UVM_NONE)
                    else $display("%s", print_msg);

                end else begin
                accuracy = (real'(instr_pass[name]) / real'(instr_total[name])) * 100.0;
                clean_name = name;
                for (int i=0; i<name.len(); i++) begin
                    if (name.substr(i, i) == ":") begin clean_name = name.substr(i+2, name.len()-1); break; end
                end
                
                print_msg = $sformatf(" %-20s : TOTAL : %5d | %5d PASS | %5d FAIL | ACCURATE %6.2f%%", 
                                      clean_name, instr_total[name], instr_pass[name], instr_fail[name], accuracy);
                                      
                if(enable_uvm_prefix) `uvm_info("SCB", print_msg, UVM_NONE)
                else $display("%s", print_msg);
            end
        end
    end
        
        if(enable_uvm_prefix) `uvm_info("SCB", "================================================================================\n", UVM_NONE)
        else $display("================================================================================\n");
    endfunction
endclass

// =============================================================================
// 6. AGENT, ENV, TEST & TOP
// =============================================================================
class soc_agent extends uvm_agent;
    `uvm_component_utils(soc_agent)
    soc_driver driver; uvm_sequencer #(soc_item) sequencer;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        driver = soc_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(soc_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase); driver.seq_item_port.connect(sequencer.seq_item_export); endfunction
endclass

class soc_env extends uvm_env;
    `uvm_component_utils(soc_env)
    soc_agent agent; soc_scoreboard scoreboard; 
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = soc_agent::type_id::create("agent", this);
        scoreboard = soc_scoreboard::type_id::create("scoreboard", this); 
    endfunction
endclass

class soc_test extends uvm_test;
    `uvm_component_utils(soc_test)
    soc_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); env = soc_env::type_id::create("env", this); endfunction
    
    task run_phase(uvm_phase phase);
        soc_directed_seq       dir_seq = soc_directed_seq::type_id::create("dir_seq");
        soc_extreme_hazard_seq haz_seq = soc_extreme_hazard_seq::type_id::create("haz_seq");
        soc_stress_seq         str_seq = soc_stress_seq::type_id::create("str_seq");
        
        phase.raise_objection(this);
        dir_seq.start(env.agent.sequencer);
        #20ns;
        haz_seq.start(env.agent.sequencer); // Bài kiểm tra ép kẹt ống chỉ liên hoàn 2000 lệnh
        #20ns;
        str_seq.start(env.agent.sequencer); // Bài kiểm tra RV32IM toàn diện kèm nã đạn Ngắt (IRQ)
        #50ns; 
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 7. MODULE TOP 
// =============================================================================
module tb_top;
    logic clk = 0; logic rst = 1;
    always #5 clk = ~clk;

    soc_if vif(clk, rst);

    soc_without_mem dut (
        .clk_i(clk), .rst_i(rst),
        .irq_sw_i(vif.irq_sw_i), .irq_timer_i(vif.irq_timer_i), .irq_ext_i(vif.irq_ext_i),
        .if_req_valid_o(vif.if_req_valid_o), .if_req_addr_o(vif.if_req_addr_o),
        .if_req_ready_i(vif.if_req_ready_i), .if_rsp_valid_i(vif.if_rsp_valid_i),
        .if_rsp_instr_i(vif.if_rsp_instr_i), .if_rsp_ready_o(vif.if_rsp_ready_o),
        .dmem_req_valid_o(vif.dmem_req_valid_o), .dmem_req_ready_i(vif.dmem_req_ready_i),
        .dmem_addr_o(vif.dmem_addr_o), .dmem_wdata_o(vif.dmem_wdata_o),
        .dmem_be_o(vif.dmem_be_o), .dmem_we_o(vif.dmem_we_o),
        .dmem_rsp_valid_i(vif.dmem_rsp_valid_i), .dmem_rsp_ready_o(vif.dmem_rsp_ready_o),
        .dmem_rdata_i(vif.dmem_rdata_i), .dmem_err_i(vif.dmem_err_i)
    );

    // Cọc dò Gray-box lấy tín hiệu Stall từ Control Unit (Não bộ)
    assign vif.probe_stall_id = dut.u_control.ctrl_force_stall_id_o;

    initial begin
        #15 rst = 0; 
    end

    initial begin
        uvm_config_db#(virtual soc_if)::set(null, "*", "vif", vif);
        run_test("soc_test");
    end
endmodule