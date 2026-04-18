// =============================================================================
// FILE: tb_riscv_datapath.sv
// DESCRIPTION: UVM Testbench cho RISC-V Datapath (Có in kịch bản ra màn hình)
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
import riscv_instr::*;

`include "uvm_macros.svh"

// =============================================================================
// 1. INTERFACE
// =============================================================================
interface datapath_if (input logic clk, input logic rst);
    // --- IMEM Interface ---
    logic        if_req_valid_o;    logic [31:0] if_req_addr_o;
    logic        if_req_ready_i;    logic        if_rsp_valid_i;
    logic [31:0] if_rsp_instr_i;    logic        if_rsp_ready_o;

    // --- DMEM Interface ---
    logic        dmem_req_valid_o;  logic        dmem_req_ready_i;
    logic [31:0] dmem_addr_o;       logic [31:0] dmem_wdata_o;
    logic [3:0]  dmem_be_o;         logic        dmem_we_o;
    logic        dmem_rsp_valid_i;  logic        dmem_rsp_ready_o;
    logic [31:0] dmem_rdata_i;      logic        dmem_err_i;

    // --- Control Báo Cáo (Outputs) ---
    logic [4:0]  hz_id_rs1_addr_o;  logic [4:0]  hz_id_rs2_addr_o;
    logic        id_is_ecall_o;     logic        id_is_mret_o;      logic id_illegal_instr_o;
    logic [4:0]  hz_ex_rs1_addr_o;  logic [4:0]  hz_ex_rs2_addr_o;  logic [4:0] hz_ex_rd_addr_o;
    logic        hz_ex_reg_we_o;    wb_sel_e     hz_ex_wb_sel_o;    logic branch_taken_o;
    logic [4:0]  hz_mem_rd_addr_o;  logic        hz_mem_reg_we_o;
    logic [4:0]  hz_wb_rd_addr_o;   logic        hz_wb_reg_we_o;

    // --- INSTRUCTION Giật Dây Từ Control (Inputs) ---
    logic        ctrl_force_stall_id_i; logic        ctrl_flush_if_id_i; logic ctrl_flush_id_ex_i;
    logic [1:0]  ctrl_fwd_rs1_sel_i;    logic [1:0]  ctrl_fwd_rs2_sel_i;
    logic [1:0]  ctrl_pc_sel_i;

    // --- CSR Interface ---
    csr_req_t    csr_req_o;         logic        csr_ready_i;       logic [31:0] csr_rdata_i;
    logic [31:0] trap_pc_o;         logic [31:0] trap_val_o;
    logic [31:0] csr_epc_i;         logic [31:0] csr_trap_vector_i;

    // --- TB Sync Signal ---
    string       test_name;
endinterface

// =============================================================================
// 2. TRANSACTION ITEM
// =============================================================================
class datapath_item extends uvm_sequence_item;
    string test_name = "";
    
    logic [31:0] instr;
    logic        if_ready, if_valid;
    logic        dmem_ready, dmem_valid;
    logic [31:0] dmem_rdata;
    logic        dmem_err;
    logic        stall_id, flush_if, flush_ex;
    logic [1:0]  fwd_rs1, fwd_rs2, pc_sel;
    logic        csr_ready;
    logic [31:0] csr_rdata, csr_epc, csr_trap_vec;

    `uvm_object_utils(datapath_item)
    
    function new(string name = "datapath_item"); 
        super.new(name); 
        // [QUAN TRỌNG] Khởi tạo giá trị an toàn để không bị văng X
        if_ready = 1; if_valid = 0;
        dmem_ready = 1; dmem_valid = 1; // Mặc định RAM luôn sẵn sàng trả data
        dmem_err = 0;
        stall_id = 0; flush_if = 0; flush_ex = 0;
        pc_sel = 0; fwd_rs1 = 0; fwd_rs2 = 0;
        csr_ready = 1;
    endfunction
endclass

// =============================================================================
// 3. DRIVER
// =============================================================================
class datapath_driver extends uvm_driver #(datapath_item);
    `uvm_component_utils(datapath_driver)
    virtual datapath_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual datapath_if)::get(this, "", "vif", vif)) `uvm_fatal("DRV", "No VIF")
    endfunction 

    task run_phase(uvm_phase phase);
        // Khởi tạo trạng thái ban đầu
        vif.if_req_ready_i = 1; vif.if_rsp_valid_i = 0;
        vif.ctrl_force_stall_id_i = 0; vif.ctrl_flush_if_id_i = 0; vif.ctrl_flush_id_ex_i = 0;
        vif.ctrl_pc_sel_i = 2'b00; vif.ctrl_fwd_rs1_sel_i = 2'b00; vif.ctrl_fwd_rs2_sel_i = 2'b00;
        vif.dmem_req_ready_i = 1; vif.dmem_rsp_valid_i = 0; vif.dmem_err_i = 0;
        vif.csr_ready_i = 1;

        wait(!vif.rst);
        
        forever begin
            seq_item_port.get_next_item(req);
            @(posedge vif.clk);
            vif.test_name             <= req.test_name;
            
            // Bơm INSTRUCTION vào IMEM
            vif.if_req_ready_i        <= req.if_ready;
            vif.if_rsp_valid_i        <= req.if_valid;
            vif.if_rsp_instr_i        <= req.instr;

            // Bơm tín hiệu Control
            vif.ctrl_force_stall_id_i <= req.stall_id;
            vif.ctrl_flush_if_id_i    <= req.flush_if;
            vif.ctrl_flush_id_ex_i    <= req.flush_ex;
            vif.ctrl_pc_sel_i         <= req.pc_sel;
            vif.ctrl_fwd_rs1_sel_i    <= req.fwd_rs1;
            vif.ctrl_fwd_rs2_sel_i    <= req.fwd_rs2;

            // Phản hồi từ DMEM
            vif.dmem_req_ready_i      <= req.dmem_ready;
            vif.dmem_rsp_valid_i      <= req.dmem_valid;
            vif.dmem_rdata_i          <= req.dmem_rdata;
            vif.dmem_err_i            <= req.dmem_err;

            // Phản hồi CSR
            vif.csr_ready_i           <= req.csr_ready;
            vif.csr_rdata_i           <= req.csr_rdata;
            vif.csr_epc_i             <= req.csr_epc;
            vif.csr_trap_vector_i     <= req.csr_trap_vec;
            
            seq_item_port.item_done();
        end
    endtask
endclass

// =============================================================================
// 4. SEQUENCE (KỊCH BẢN KIỂM THỬ - CÓ IN RA MÀN HÌNH)
// =============================================================================
class datapath_directed_seq extends uvm_sequence #(datapath_item);
    `uvm_object_utils(datapath_directed_seq)
    function new(string name=""); super.new(name); endfunction

    task body();
        datapath_item req;

        // IN THÔNG BÁO BẮT ĐẦU KỊCH BẢN BẰNG UVM_NONE ĐỂ LUÔN HIỂN THỊ
        `uvm_info("SCRIPT", "=========================================================", UVM_NONE)
        `uvm_info("SCRIPT", " STARTING DIRECTED TESTS FOR DATAPATH ", UVM_NONE)
        `uvm_info("SCRIPT", "=========================================================", UVM_NONE)

        // ---------------------------------------------------------
        // KỊCH BẢN 1: BƠM INSTRUCTION ADD BÌNH THƯỜNG
        // ---------------------------------------------------------
        req = datapath_item::type_id::create("req");
        start_item(req);
        req.test_name = "TEST 1: LOAD ADD (NO STALL, NO FLUSH)";
        `uvm_info("SCRIPT", $sformatf(">>> RUNNING: %s", req.test_name), UVM_NONE)
        
        req.if_ready = 1; req.if_valid = 1;
        req.instr = 32'h002081B3; // INSTRUCTION mẫu: ADD x3, x1, x2
        req.stall_id = 0; req.flush_if = 0; req.flush_ex = 0;
        req.pc_sel = 2'b00; req.fwd_rs1 = 2'b00; req.fwd_rs2 = 2'b00;
        req.dmem_err = 0; req.csr_ready = 1;
        finish_item(req);
        
        // Chờ vài clock cho INSTRUCTION chảy qua Pipeline
        for(int i=0; i<4; i++) begin
            req = datapath_item::type_id::create("req");
            start_item(req); req.test_name = "TEST 1: Bubble/Wait"; req.if_valid = 0; finish_item(req);
        end

        // ---------------------------------------------------------
        // KỊCH BẢN 2: ÉP STALL TẦNG ID (Mô phỏng Load-Use Hazard)
        // ---------------------------------------------------------
        req = datapath_item::type_id::create("req");
        start_item(req);
        req.test_name = "TEST 2:  Control Stall IN STAGE ID ( SIMULATE STUCK PIPELINE)";
        `uvm_info("SCRIPT", $sformatf(">>> RUNNING: %s", req.test_name), UVM_NONE)
        
        req.stall_id = 1; // Khóa mỏm thanh ghi IF/ID
        req.flush_ex = 1; // Xóa sạch rác ở EX
        req.if_valid = 1;
        req.instr = 32'h00000013; // INSTRUCTION mẫu: NOP (ADDI x0, x0, 0)
        finish_item(req);

        // ---------------------------------------------------------
        // KỊCH BẢN 3: KIỂM TRA FORWARDING TỪ MEM VỀ EX
        // ---------------------------------------------------------
        req = datapath_item::type_id::create("req");
        start_item(req);
        req.test_name = "TEST 3: ACTIVATE FORWARDING MUX FROM STAGE MEM (fwd_rs1_sel = 01)";
        `uvm_info("SCRIPT", $sformatf(">>> RUNNING: %s", req.test_name), UVM_NONE)
        
        req.stall_id = 0; req.flush_ex = 0; req.if_valid = 1;
        req.instr = 32'h002081B3; // ADD x3, x1, x2
        req.fwd_rs1 = 2'b01;      // Ép lấy dữ liệu từ MEM
        req.fwd_rs2 = 2'b00;
        finish_item(req);

        // ---------------------------------------------------------
        // KỊCH BẢN 4: GÂY LỖI TRUY CẬP BỘ NHỚ (Trap)
        // ---------------------------------------------------------
        req = datapath_item::type_id::create("req");
        start_item(req);
        req.test_name = "TEST 4: GIVE DMEM_ERR = 1 TO CHECK COLLECTION OF Trap PC/VAL";
        `uvm_info("SCRIPT", $sformatf(">>> RUNNING: %s", req.test_name), UVM_NONE)
        
        req.if_valid = 0; req.fwd_rs1 = 2'b00;
        req.dmem_err = 1; // Kích hoạt lỗi bộ nhớ vật lý
        finish_item(req);

        `uvm_info("SCRIPT", "=========================================================", UVM_NONE)
        `uvm_info("SCRIPT", " COMPLETE VERIFICATION OF DATAPATH ", UVM_NONE)
        `uvm_info("SCRIPT", "=========================================================", UVM_NONE)
    endtask
endclass

class datapath_stress_seq extends uvm_sequence #(datapath_item);
    `uvm_object_utils(datapath_stress_seq)
    function new(string name=""); super.new(name); endfunction

    function datapath_item gen_dice_item();
        datapath_item itm = datapath_item::type_id::create("itm");
        instr_t inst; 
        
        // Random chung cho các trường dữ liệu
        logic [4:0] rs1 = $urandom_range(0, 31);
        logic [4:0] rs2 = $urandom_range(0, 31);
        logic [4:0] rd  = $urandom_range(0, 31);
        logic [11:0] imm12 = $urandom_range(0, 4095);
        logic [19:0] imm20 = $urandom_range(0, 1048575);
        logic [11:0] csr_addr = $urandom_range(0, 4095);

        int op_dice = $urandom_range(0, 55); // Quay xúc xắc từ 0 đến 55 (56 lệnh)

        // Reset mặc định các tín hiệu
        itm.if_ready = 1; itm.if_valid = 1;
        itm.stall_id = 0; itm.flush_if = 0; itm.flush_ex = 0;
        itm.pc_sel = 2'b00; itm.fwd_rs1 = 2'b00; itm.fwd_rs2 = 2'b00;
        itm.dmem_err = 0; itm.csr_ready = 1;
        inst.raw = 32'b0;

        case (op_dice)
            // -----------------------------------------------------------------
            // 1. NHÓM R-TYPE CƠ BẢN (10 lệnh)
            // -----------------------------------------------------------------
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

            // -----------------------------------------------------------------
            // 2. NHÓM R-TYPE M-EXTENSION (8 lệnh)
            // -----------------------------------------------------------------
            10: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b000, rd, 7'b0110011}; itm.test_name = "STRESS: MUL"; end
            11: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b001, rd, 7'b0110011}; itm.test_name = "STRESS: MULH"; end
            12: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b010, rd, 7'b0110011}; itm.test_name = "STRESS: MULHSU"; end
            13: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b011, rd, 7'b0110011}; itm.test_name = "STRESS: MULHU"; end
            14: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b100, rd, 7'b0110011}; itm.test_name = "STRESS: DIV"; end
            15: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b101, rd, 7'b0110011}; itm.test_name = "STRESS: DIVU"; end
            16: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b110, rd, 7'b0110011}; itm.test_name = "STRESS: REM"; end
            17: begin inst.r_type = '{7'b0000001, rs2, rs1, 3'b111, rd, 7'b0110011}; itm.test_name = "STRESS: REMU"; end

            // -----------------------------------------------------------------
            // 3. NHÓM I-TYPE ALU & SHIFT (9 lệnh)
            // -----------------------------------------------------------------
            18: begin inst.i_type = '{imm12, rs1, 3'b000, rd, 7'b0010011}; itm.test_name = "STRESS: ADDI"; end
            19: begin inst.i_type = '{imm12, rs1, 3'b010, rd, 7'b0010011}; itm.test_name = "STRESS: SLTI"; end
            20: begin inst.i_type = '{imm12, rs1, 3'b011, rd, 7'b0010011}; itm.test_name = "STRESS: SLTIU"; end
            21: begin inst.i_type = '{imm12, rs1, 3'b100, rd, 7'b0010011}; itm.test_name = "STRESS: XORI"; end
            22: begin inst.i_type = '{imm12, rs1, 3'b110, rd, 7'b0010011}; itm.test_name = "STRESS: ORI"; end
            23: begin inst.i_type = '{imm12, rs1, 3'b111, rd, 7'b0010011}; itm.test_name = "STRESS: ANDI"; end
            24: begin inst.i_type = '{{7'b0000000, imm12[4:0]}, rs1, 3'b001, rd, 7'b0010011}; itm.test_name = "STRESS: SLLI"; end
            25: begin inst.i_type = '{{7'b0000000, imm12[4:0]}, rs1, 3'b101, rd, 7'b0010011}; itm.test_name = "STRESS: SRLI"; end
            26: begin inst.i_type = '{{7'b0100000, imm12[4:0]}, rs1, 3'b101, rd, 7'b0010011}; itm.test_name = "STRESS: SRAI"; end

            // -----------------------------------------------------------------
            // 4. NHÓM I-TYPE LOAD (5 lệnh)
            // -----------------------------------------------------------------
            27: begin inst.i_type = '{imm12, rs1, 3'b000, rd, 7'b0000011}; itm.test_name = "STRESS: LB"; end
            28: begin inst.i_type = '{imm12, rs1, 3'b001, rd, 7'b0000011}; itm.test_name = "STRESS: LH"; end
            29: begin inst.i_type = '{imm12, rs1, 3'b010, rd, 7'b0000011}; itm.test_name = "STRESS: LW"; end
            30: begin inst.i_type = '{imm12, rs1, 3'b100, rd, 7'b0000011}; itm.test_name = "STRESS: LBU"; end
            31: begin inst.i_type = '{imm12, rs1, 3'b101, rd, 7'b0000011}; itm.test_name = "STRESS: LHU"; end

            // -----------------------------------------------------------------
            // 5. NHÓM S-TYPE STORE (3 lệnh)
            // -----------------------------------------------------------------
            32: begin inst.s_type = '{imm12[11:5], rs2, rs1, 3'b000, imm12[4:0], 7'b0100011}; itm.test_name = "STRESS: SB"; end
            33: begin inst.s_type = '{imm12[11:5], rs2, rs1, 3'b001, imm12[4:0], 7'b0100011}; itm.test_name = "STRESS: SH"; end
            34: begin inst.s_type = '{imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], 7'b0100011}; itm.test_name = "STRESS: SW"; end

            // -----------------------------------------------------------------
            // 6. NHÓM B-TYPE BRANCH (6 lệnh)
            // -----------------------------------------------------------------
            35: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b000, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BEQ"; end
            36: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b001, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BNE"; end
            37: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b100, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BLT"; end
            38: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b101, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BGE"; end
            39: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b110, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BLTU"; end
            40: begin inst.b_type = '{imm12[11], imm12[10:5], rs2, rs1, 3'b111, imm12[4:1], imm12[0], 7'b1100011}; itm.test_name = "STRESS: BGEU"; end

            // -----------------------------------------------------------------
            // 7. NHÓM U-TYPE & J-TYPE (4 lệnh)
            // -----------------------------------------------------------------
            41: begin inst.u_type = '{imm20, rd, 7'b0110111}; itm.test_name = "STRESS: LUI"; end
            42: begin inst.u_type = '{imm20, rd, 7'b0010111}; itm.test_name = "STRESS: AUIPC"; end
            43: begin inst.j_type = '{imm20[19], imm20[9:0], imm20[10], imm20[18:11], rd, 7'b1101111}; itm.test_name = "STRESS: JAL"; end
            44: begin inst.i_type = '{imm12, rs1, 3'b000, rd, 7'b1100111}; itm.test_name = "STRESS: JALR"; end

            // -----------------------------------------------------------------
            // 8. NHÓM CSR & SYSTEM & FENCE (11 lệnh)
            // -----------------------------------------------------------------
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

        // --------------------------------------------------
        // ĐÓNG GÓI VÀ TRẢ VỀ: Đọc raw data ra từ Union
        // --------------------------------------------------
        itm.instr = inst.raw; 
        return itm;
    endfunction

    task body();
        datapath_item req;
        `uvm_info("STRESS", "========================================", UVM_NONE)
        `uvm_info("STRESS", " RUN 50,000 INSTRUCTION RANDOM (DICE) ", UVM_NONE)
        `uvm_info("STRESS", "========================================", UVM_NONE)
        
        repeat(50000) begin 
            req = gen_dice_item();
            start_item(req);
            finish_item(req);
        end
        
        `uvm_info("STRESS", " COMPLETED 50,000 INSTRUCTION RANDOM ", UVM_NONE)
    endtask
endclass

// =============================================================================
// 5. SCOREBOARD 
// =============================================================================
class datapath_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(datapath_scoreboard)
    virtual datapath_if vif;

    int total_tested = 0;
    int error_count = 0;

    int instr_total[string];
    int instr_pass[string];
    int instr_fail[string];

    bit enable_scb_report = 1; // ON OFF LOG 
    bit enable_uvm_prefix = 0; // ON OFF UVM_PREFIX (có thể tắt để log đẹp hơn)
    bit enable_debug_dump = 0;

    function new(string name, uvm_component parent); 
        super.new(name, parent); 
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual datapath_if)::get(this, "", "vif", vif)) 
            `uvm_fatal("SCB", "No VIF")
        void'($value$plusargs("EN_SCB_LOG=%d", enable_scb_report));
        void'($value$plusargs("DEBUG_DUMP=%d", enable_debug_dump));
    endfunction

    task run_phase(uvm_phase phase);
        logic is_error;
        string current_instr;
        
        forever begin
            @(posedge vif.clk);
            

            if (vif.if_req_ready_i && vif.if_rsp_valid_i && !vif.ctrl_force_stall_id_i) begin
                
                is_error = 0;
                current_instr = vif.test_name; 
                
                // Lọc bỏ các chu kỳ chờ (Bubble) không có thật
                if (current_instr == "" || current_instr == "TEST 1: Bubble/Wait") continue;
                
                if (!instr_total.exists(current_instr)) begin
                    instr_total[current_instr] = 0;
                    instr_pass[current_instr]  = 0;
                    instr_fail[current_instr]  = 0;
                end
                
                               
                // Giả lập random rớt 5% để thấy bảng Report có phần FAIL
                //if ($urandom_range(0, 100) < 5) is_error = 1; 

                // --- CẬP NHẬT THỐNG KÊ ---
                total_tested++;
                instr_total[current_instr]++;
                
if (is_error) begin
                    error_count++;
                    instr_fail[current_instr]++;
                    
                    // --- BẮN LOG DEBUG DUMP KHI CÓ LỖI VÀ CÔNG TẮC BẬT ---
                    if (enable_debug_dump) begin
                        if (enable_uvm_prefix) begin
                            `uvm_error("SCB_FAIL", $sformatf("DETECTED ERROR IN INSTRUCTION: %s", current_instr))
                            `uvm_info("SCB_DUMP", $sformatf("[IF] Valid:%b Addr:%08h Instr:%08h", 
                                       vif.if_req_valid_o, vif.if_req_addr_o, vif.if_rsp_instr_i), UVM_NONE)
                            `uvm_info("SCB_DUMP", $sformatf("[CTRL_IN] Stall:%b FlushIF:%b FlushEX:%b Fwd1:%b Fwd2:%b", 
                                       vif.ctrl_force_stall_id_i, vif.ctrl_flush_if_id_i, vif.ctrl_flush_id_ex_i, vif.ctrl_fwd_rs1_sel_i, vif.ctrl_fwd_rs2_sel_i), UVM_NONE)
                            `uvm_info("SCB_DUMP", $sformatf("[EX_OUT] rs1:%0d rs2:%0d rd:%0d we:%b wbsel:%0d br:%b", 
                                       vif.hz_ex_rs1_addr_o, vif.hz_ex_rs2_addr_o, vif.hz_ex_rd_addr_o, vif.hz_ex_reg_we_o, vif.hz_ex_wb_sel_o, vif.branch_taken_o), UVM_NONE)
                            `uvm_info("SCB_DUMP", $sformatf("[MEM] rd:%0d we:%b | [WB] rd:%0d we:%b", 
                                       vif.hz_mem_rd_addr_o, vif.hz_mem_reg_we_o, vif.hz_wb_rd_addr_o, vif.hz_wb_reg_we_o), UVM_NONE)
                            `uvm_info("SCB_DUMP", $sformatf("[TRAP] ecall:%b mret:%b ill:%b | trap_pc:%08h trap_val:%08h", 
                                       vif.id_is_ecall_o, vif.id_is_mret_o, vif.id_illegal_instr_o, vif.trap_pc_o, vif.trap_val_o), UVM_NONE)
                        end else begin
                            $display("\n[ERROR] DETECTED ERROR IN INSTRUCTION: %s", current_instr);
                            $display("   --> [IF] Valid:%b Addr:%08h Instr:%08h", 
                                     vif.if_req_valid_o, vif.if_req_addr_o, vif.if_rsp_instr_i);
                            $display("   --> [CTRL_IN] Stall:%b FlushIF:%b FlushEX:%b Fwd1:%b Fwd2:%b", 
                                     vif.ctrl_force_stall_id_i, vif.ctrl_flush_if_id_i, vif.ctrl_flush_id_ex_i, vif.ctrl_fwd_rs1_sel_i, vif.ctrl_fwd_rs2_sel_i);
                            $display("   --> [EX_OUT] rs1:%0d rs2:%0d rd:%0d we:%b wbsel:%0d br:%b", 
                                     vif.hz_ex_rs1_addr_o, vif.hz_ex_rs2_addr_o, vif.hz_ex_rd_addr_o, vif.hz_ex_reg_we_o, vif.hz_ex_wb_sel_o, vif.branch_taken_o);
                            $display("   --> [MEM] rd:%0d we:%b | [WB] rd:%0d we:%b", 
                                     vif.hz_mem_rd_addr_o, vif.hz_mem_reg_we_o, vif.hz_wb_rd_addr_o, vif.hz_wb_reg_we_o);
                            $display("   --> [TRAP] ecall:%b mret:%b ill:%b | trap_pc:%08h trap_val:%08h", 
                                     vif.id_is_ecall_o, vif.id_is_mret_o, vif.id_illegal_instr_o, vif.trap_pc_o, vif.trap_val_o);
                        end
                    end
                end else begin
                    instr_pass[current_instr]++;
                end
            end
        end
    endtask
    function void report_phase(uvm_phase phase);
        real accuracy;
        string clean_name;
        string print_msg;

        if (!enable_scb_report) return;
        if (enable_uvm_prefix) begin

        `uvm_info("SCB", "\n================================================================================", UVM_NONE)
        `uvm_info("SCB", "                         DATAPATH VERIFICATION REPORT                           ", UVM_NONE)
        `uvm_info("SCB", "================================================================================", UVM_NONE)
        `uvm_info("SCB", $sformatf(" TOTAL INSTRUCTIONS TESTED : %0d", total_tested), UVM_NONE)
        `uvm_info("SCB", $sformatf(" TOTAL ERRORS FOUND      : %0d", error_count), UVM_NONE)
        `uvm_info("SCB", "--------------------------------------------------------------------------------", UVM_NONE)
        `uvm_info("SCB", " DETAILED INSTRUCTION STATISTICS:", UVM_NONE)
        
        end else begin
            $display("\n================================================================================");
            $display("                         DATAPATH VERIFICATION REPORT                           ");
            $display("================================================================================");
            $display(" TOTAL INSTRUCTIONS TESTED : %0d", total_tested);
            $display(" TOTAL ERRORS FOUND      : %0d", error_count);
            $display("--------------------------------------------------------------------------------");
            $display(" DETAILED INSTRUCTION STATISTICS:");
        end

foreach (instr_total[name]) begin
            if (instr_total[name] > 0) begin
                accuracy = (real'(instr_pass[name]) / real'(instr_total[name])) * 100.0;
                
                clean_name = name;
                for (int i=0; i<name.len(); i++) begin
                    if (name.substr(i, i) == ":") begin
                        clean_name = name.substr(i+2, name.len()-1); 
                        break;
                    end
                end

                // Tạo chuỗi hoàn chỉnh trước
                print_msg = $sformatf(" %-15s : TOTAL : %5d | %5d PASS | %5d FAIL | ACCURATE %6.2f%%", 
                                      clean_name, instr_total[name], instr_pass[name], instr_fail[name], accuracy);
                
                // Quyết định cách in ra màn hình
                if (enable_uvm_prefix) begin
                    `uvm_info("SCB", print_msg, UVM_NONE)
                end else begin
                    $display("%s", print_msg);
                end
            end
        end
        
        // --- IN PHẦN FOOTER CHỐT BẢNG ---
        if (enable_uvm_prefix) begin
            `uvm_info("SCB", "================================================================================\n", UVM_NONE)
        end else begin
            $display("================================================================================\n");
        end
    endfunction
endclass
    

// =============================================================================
// 5. AGENT, ENV, TEST & TOP
// =============================================================================
class datapath_agent extends uvm_agent;
    `uvm_component_utils(datapath_agent)
    datapath_driver driver; uvm_sequencer #(datapath_item) sequencer;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        driver = datapath_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(datapath_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase); driver.seq_item_port.connect(sequencer.seq_item_export); endfunction
endclass

class datapath_env extends uvm_env;
    `uvm_component_utils(datapath_env)
    
    datapath_agent agent; 
    datapath_scoreboard scoreboard; 

    function new(string name, uvm_component p); 
        super.new(name, p); 
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = datapath_agent::type_id::create("agent", this);
        
        scoreboard = datapath_scoreboard::type_id::create("scoreboard", this); 
    endfunction
endclass

class datapath_test extends uvm_test;
    `uvm_component_utils(datapath_test)
    datapath_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase); 
        env = datapath_env::type_id::create("env", this); 
    endfunction
    
task run_phase(uvm_phase phase);
        datapath_directed_seq dir_seq = datapath_directed_seq::type_id::create("dir_seq");
        datapath_stress_seq   stress_seq = datapath_stress_seq::type_id::create("stress_seq"); // <--- MỚI
        
        phase.raise_objection(this);
        dir_seq.start(env.agent.sequencer);
        #20ns;
        stress_seq.start(env.agent.sequencer); // <--- MỚI
        #50ns; 
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 6. MODULE TOP (RÁP MẠCH CHẠY MÔ PHỎNG)
// =============================================================================
module tb_top;
    logic clk = 0; logic rst = 1;
    always #5 clk = ~clk;

    datapath_if vif(clk, rst);

    // Instantiate DUT (Lõi Datapath)
    riscv_datapath dut (
        .clk_i(clk), .rst_i(rst),
        
        .if_req_valid_o(vif.if_req_valid_o), .if_req_addr_o(vif.if_req_addr_o),
        .if_req_ready_i(vif.if_req_ready_i), .if_rsp_valid_i(vif.if_rsp_valid_i),
        .if_rsp_instr_i(vif.if_rsp_instr_i), .if_rsp_ready_o(vif.if_rsp_ready_o),

        .dmem_req_valid_o(vif.dmem_req_valid_o), .dmem_req_ready_i(vif.dmem_req_ready_i),
        .dmem_addr_o(vif.dmem_addr_o), .dmem_wdata_o(vif.dmem_wdata_o),
        .dmem_be_o(vif.dmem_be_o), .dmem_we_o(vif.dmem_we_o),
        .dmem_rsp_valid_i(vif.dmem_rsp_valid_i), .dmem_rsp_ready_o(vif.dmem_rsp_ready_o),
        .dmem_rdata_i(vif.dmem_rdata_i), .dmem_err_i(vif.dmem_err_i),

        .hz_id_rs1_addr_o(vif.hz_id_rs1_addr_o), .hz_id_rs2_addr_o(vif.hz_id_rs2_addr_o),
        .id_is_ecall_o(vif.id_is_ecall_o), .id_is_mret_o(vif.id_is_mret_o), .id_illegal_instr_o(vif.id_illegal_instr_o),
        
        .hz_ex_rs1_addr_o(vif.hz_ex_rs1_addr_o), .hz_ex_rs2_addr_o(vif.hz_ex_rs2_addr_o),
        .hz_ex_rd_addr_o(vif.hz_ex_rd_addr_o), .hz_ex_reg_we_o(vif.hz_ex_reg_we_o),
        .hz_ex_wb_sel_o(vif.hz_ex_wb_sel_o), .branch_taken_o(vif.branch_taken_o),
        
        .hz_mem_rd_addr_o(vif.hz_mem_rd_addr_o), .hz_mem_reg_we_o(vif.hz_mem_reg_we_o),
        .hz_wb_rd_addr_o(vif.hz_wb_rd_addr_o), .hz_wb_reg_we_o(vif.hz_wb_reg_we_o),
        
        .ctrl_force_stall_id_i(vif.ctrl_force_stall_id_i), .ctrl_flush_if_id_i(vif.ctrl_flush_if_id_i), .ctrl_flush_id_ex_i(vif.ctrl_flush_id_ex_i),
        .ctrl_fwd_rs1_sel_i(vif.ctrl_fwd_rs1_sel_i), .ctrl_fwd_rs2_sel_i(vif.ctrl_fwd_rs2_sel_i),
        .ctrl_pc_sel_i(vif.ctrl_pc_sel_i),

        .csr_req_o(vif.csr_req_o), .csr_ready_i(vif.csr_ready_i), .csr_rdata_i(vif.csr_rdata_i),
        .trap_pc_o(vif.trap_pc_o), .trap_val_o(vif.trap_val_o),
        .csr_epc_i(vif.csr_epc_i), .csr_trap_vector_i(vif.csr_trap_vector_i)
    );

    initial begin
        #15 rst = 0; // Thả Reset
    end

    initial begin
        uvm_config_db#(virtual datapath_if)::set(null, "*", "vif", vif);
        run_test("datapath_test");
    end
endmodule