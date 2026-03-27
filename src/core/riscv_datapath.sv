import riscv_32im_pkg::*;
import riscv_instr::*;

module riscv_datapath (
    input  logic clk_i,
    input  logic rst_i,

    // ==============================================================
    // 1. INTERFACE MEMORY (IMEM & LSU) - Khớp với mem module
    // ==============================================================
    output logic        if_req_valid_o,
    output logic [31:0] if_req_addr_o,
    input  logic        if_req_ready_i,
    input  logic        if_rsp_valid_i,
    input  logic [31:0] if_rsp_instr_i,
    output logic        if_rsp_ready_o,

    output logic [31:0] lsu_addr_o,
    output logic [31:0] lsu_wdata_o,
    output logic        lsu_we_o,
    output logic [2:0]  lsu_funct3_o, 
    output logic        lsu_req_valid_o,
    input  logic        lsu_req_ready_i,
    input  logic        lsu_rsp_valid_i,
    input  logic [31:0] lsu_rdata_i,
    output logic        lsu_rsp_ready_o,
    input  logic        lsu_err_i,         // Nhận lỗi từ MEM

    // ==============================================================
    // 2. INTERFACE ĐIỀU KHIỂN (CONTROL LOGIC) - Khớp riscv_control
    // ==============================================================
    // ---> Báo cáo trạng thái LÊN Não bộ
    output logic [4:0]  hz_id_rs1_addr_o,
    output logic [4:0]  hz_id_rs2_addr_o,
    output logic        id_is_ecall_o,     
    output logic        id_is_mret_o,      
    output logic        id_illegal_instr_o,
    
    output logic [4:0]  hz_ex_rs1_addr_o, 
    output logic [4:0]  hz_ex_rs2_addr_o, 
    output logic [4:0]  hz_ex_rd_addr_o,
    output logic        hz_ex_reg_we_o,    
    output wb_sel_e     hz_ex_wb_sel_o,
    output logic        branch_taken_o,    // Báo lệnh nhảy thành công
    
    output logic [4:0]  hz_mem_rd_addr_o,
    output logic        hz_mem_reg_we_o,
    
    output logic [4:0]  hz_wb_rd_addr_o,
    output logic        hz_wb_reg_we_o,
    
    // ---> Nhận lệnh giật dây TỪ Não bộ
    input  logic        ctrl_force_stall_id_i,   
    input  logic        ctrl_flush_if_id_i,
    input  logic        ctrl_flush_id_ex_i,
    
    input  logic [1:0]  ctrl_fwd_rs1_sel_i, 
    input  logic [1:0]  ctrl_fwd_rs2_sel_i,
    input  logic [1:0]  ctrl_pc_sel_i,     // 00: PC+4, 01: Branch, 10: Trap, 11: MRET

    // ==============================================================
    // 3. INTERFACE CSR - Khớp với csr module
    // ==============================================================
    output csr_req_t    csr_req_o,         
    input  logic        csr_ready_i,       // 1 = Sẵn sàng, 0 = Đang bận xử lý Trap
    input  logic [31:0] csr_rdata_i,       
    
    output logic [31:0] trap_pc_o,         // Nạp vào trap_pc_i của CSR (mepc)
    output logic [31:0] trap_val_o,        // Nạp vào trap_val_i của CSR (mtval)
    input  logic [31:0] csr_epc_i,         // Đọc từ epc_o của CSR
    input  logic [31:0] csr_trap_vector_i  // Đọc từ trap_vector_o của CSR
);

// ===========================================================================
// [DÂY CÁP NỘI BỘ CHO REGISTER FILE]
// ===========================================================================
    logic [4:0]  rf_rs1_addr, rf_rs2_addr, rf_waddr;
    logic [31:0] rf_rs1_data, rf_rs2_data, rf_wdata;
    logic        rf_we;

// ===========================================================================
// STAGE 1: INSTRUCTION FETCH (IF)
// ===========================================================================
    logic [31:0] if_pc;
    logic [31:0] branch_target_addr; 
    
    // --- Giải mã lệnh điều khiển PC từ Control ---
    logic pc_branch, pc_trap;
    logic [31:0] pc_trap_target;
    
    assign pc_branch      = (ctrl_pc_sel_i == 2'b01);
    assign pc_trap        = (ctrl_pc_sel_i == 2'b10) || (ctrl_pc_sel_i == 2'b11);
    assign pc_trap_target = (ctrl_pc_sel_i == 2'b10) ? csr_trap_vector_i : csr_epc_i;

    pc_gen u_pc_gen (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .ready_i              (if_req_ready_i && !ctrl_force_stall_id_i), // Không cho IF chạy nếu ID bị kẹt
        .valid_o              (if_req_valid_o),
        .branch_taken_i       (pc_branch),
        .branch_target_addr_i (branch_target_addr),
        .trap_taken_i         (pc_trap),
        .trap_target_addr_i   (pc_trap_target),
        .pc_o                 (if_pc)
    );

    assign if_req_addr_o  = if_pc;
    assign if_rsp_ready_o = if_id_ready; 

    if_id_t if_id_in, if_id_out;
    logic if_id_valid, if_id_ready;
    assign if_id_in.pc    = if_pc;
    assign if_id_in.instr = if_rsp_instr_i;

    pipeline_reg #(if_id_t) u_reg_if_id (
        .clk_i(clk_i), .rst_i(rst_i),
        .flush_i (ctrl_flush_if_id_i),  // Xóa rác theo lệnh của Control
        .valid_i (if_rsp_valid_i), 
        .ready_o (if_id_ready),
        .data_i  (if_id_in),
        .valid_o (if_id_valid),
        .ready_i (id_ex_ready && !ctrl_force_stall_id_i), // Bóp cổ tầng ID -> IF tự động kẹt lại
        .data_o  (if_id_out)
    );

// ===========================================================================
// STAGE 2: INSTRUCTION DECODE (ID)
// ===========================================================================
    dec_out_t    id_ctrl;
    logic [31:0] id_imm;
    logic [4:0]  id_rd_addr, id_rs1_addr, id_rs2_addr;
    logic        id_decoder_valid_o;

    decoder u_decoder (
        .instr_i    (if_id_out.instr),
        .ctrl_o     (id_ctrl),
        .imm_o      (id_imm),
        .rd_addr_o  (id_rd_addr),
        .rs1_addr_o (id_rs1_addr),
        .rs2_addr_o (id_rs2_addr),
        .valid_i    (if_id_valid),
        .ready_o    (), 
        .valid_o    (id_decoder_valid_o),
        .ready_i    (id_ex_ready)
    );

    // --- Giải mã thủ công các lệnh đặc biệt cho Control & CSR ---
    assign id_is_ecall_o      = if_id_valid && (if_id_out.instr == 32'h00000073);
    assign id_is_mret_o       = if_id_valid && (if_id_out.instr == 32'h30200073);
    assign id_illegal_instr_o = if_id_valid && !id_decoder_valid_o;

    // --- Cấp địa chỉ cho Register File và Control ---
    assign rf_rs1_addr = id_rs1_addr;
    assign rf_rs2_addr = id_rs2_addr;
    assign hz_id_rs1_addr_o = id_rs1_addr;
    assign hz_id_rs2_addr_o = id_rs2_addr;

    register u_register_file (
        .clk_i     (clk_i), .rst_i     (rst_i),
        .w_ena_i   (rf_we),       .w_addr_i  (rf_waddr),    .w_data_i  (rf_wdata),
        .r1_addr_i (rf_rs1_addr), .r1_data_o (rf_rs1_data),
        .r2_addr_i (rf_rs2_addr), .r2_data_o (rf_rs2_data)  
    );

    /* =======================================================================
       [THESIS COMPARE] VERSION 2: EARLY BRANCH RESOLUTION (STAGE ID)
       Để test tổng hợp (Synthesis), hãy mở comment block này và comment block Branch ở Tầng EX.
       ======================================================================= */
    /*
    logic [31:0] id_rs1_fwd_data, id_rs2_fwd_data;
    
    // 1. Mux Forwarding riêng cho Tầng ID (Cần khai báo thêm tín hiệu từ Control)
    always_comb begin
        case(ctrl_id_fwd_rs1_sel_i)
            2'b01: id_rs1_fwd_data = ex_mem_in.alu_result; 
            2'b10: id_rs1_fwd_data = mem_wb_in.alu_result; 
            default: id_rs1_fwd_data = rf_rs1_data; 
        endcase
    end
    always_comb begin
        case(ctrl_id_fwd_rs2_sel_i)
            2'b01: id_rs2_fwd_data = ex_mem_in.alu_result;
            2'b10: id_rs2_fwd_data = mem_wb_in.alu_result;
            default: id_rs2_fwd_data = rf_rs2_data;
        endcase
    end

    // 2. Khối so sánh đặt ngay sau Decoder
    logic id_branch_taken_internal;
    branch_cmp u_early_branch_cmp (
        .rs1_i          (id_rs1_fwd_data), 
        .rs2_i          (id_rs2_fwd_data),
        .br_op_i        (id_ctrl.br_req.op), 
        .branch_taken_o (id_branch_taken_internal) 
    );
    
    // 3. Báo cáo cờ nhảy lên Control (Nhớ đổi assign ở dưới cùng Tầng EX thành comment)
    assign branch_taken_o = if_id_valid && id_branch_taken_internal;
    
    // 4. Tính địa chỉ đích
    assign branch_target_addr = (id_ctrl.br_req.is_jump) ? (if_id_out.pc + id_imm) : 
                                                           (id_rs1_fwd_data + id_imm);
    */
    // =======================================================================

    id_ex_t id_ex_in, id_ex_out;
    logic id_ex_valid, id_ex_ready;

// ===========================================================================
// STAGE 3: EXECUTE (EX)
// ===========================================================================
    assign hz_ex_rs1_addr_o = id_ex_out.rs1_addr;
    assign hz_ex_rs2_addr_o = id_ex_out.rs2_addr;
    assign hz_ex_rd_addr_o  = id_ex_out.rd_addr;
    assign hz_ex_reg_we_o   = id_ex_out.ctrl.rf_we;
    assign hz_ex_wb_sel_o   = id_ex_out.ctrl.wb_sel;

    // --- Forwarding Mux ---
    logic [31:0] ex_rs1_fwd_data, ex_rs2_fwd_data;
    
    always_comb begin
        case(ctrl_fwd_rs1_sel_i)
            2'b01: ex_rs1_fwd_data = mem_wb_in.alu_result; 
            2'b10: ex_rs1_fwd_data = rf_wdata;            
            default: ex_rs1_fwd_data = id_ex_out.rs1_data; 
        endcase
    end
    always_comb begin
        case(ctrl_fwd_rs2_sel_i)
            2'b01: ex_rs2_fwd_data = mem_wb_in.alu_result;
            2'b10: ex_rs2_fwd_data = rf_wdata;
            default: ex_rs2_fwd_data = id_ex_out.rs2_data;
        endcase
    end

    // --- ALU & M-UNIT ---
    alu_in_t ex_alu_in;
    logic        ex_alu_zero;
    logic [31:0] ex_alu_result;
    
    assign ex_alu_in.a = (id_ex_out.ctrl.alu_req.op_a_sel == OP_A_PC)  ? id_ex_out.pc  : ex_rs1_fwd_data;
    assign ex_alu_in.b = (id_ex_out.ctrl.alu_req.op_b_sel == OP_B_IMM) ? id_ex_out.imm : ex_rs2_fwd_data;
    assign ex_alu_in.op = id_ex_out.ctrl.alu_req.op;
    assign ex_alu_in.valid_i = id_ex_valid;
    assign ex_alu_in.ready_i = ex_mem_ready;

    alu u_alu (.alu_in(ex_alu_in), .Zero(ex_alu_zero), .alu_o(ex_alu_result), .vaild_o(), .ready_o());

    logic [31:0] ex_m_result;
    logic        ex_m_valid_o, ex_m_ready_o;
    m_in_t       ex_m_in; 
    assign ex_m_in.a_i = ex_rs1_fwd_data; assign ex_m_in.b_i = ex_rs2_fwd_data; assign ex_m_in.op  = id_ex_out.ctrl.m_req.op;

    riscv_m_unit u_m_unit (
        .clk(clk_i), .rst(rst_i),
        .valid_i (id_ex_valid && id_ex_out.ctrl.m_req.valid), 
        .ready_o (ex_m_ready_o), .m_in (ex_m_in), .valid_o (ex_m_valid_o),
        .ready_i (ex_mem_ready), .result_o(ex_m_result)
    );

    // --- CSR & Branch ---
    assign csr_req_o.valid  = id_ex_valid && id_ex_out.ctrl.csr_req.valid && csr_ready_i;
    assign csr_req_o.op     = id_ex_out.ctrl.csr_req.op;
    assign csr_req_o.addr   = id_ex_out.ctrl.csr_req.addr;
    assign csr_req_o.is_imm = id_ex_out.ctrl.csr_req.is_imm;
    assign csr_req_o.wdata  = (id_ex_out.ctrl.csr_req.is_imm) ? id_ex_out.ctrl.csr_req.wdata : ex_rs1_fwd_data;

    logic branch_taken_internal;
    branch_cmp u_branch_cmp (
        .rs1_i          (ex_rs1_fwd_data), .rs2_i          (ex_rs2_fwd_data),
        .br_op_i        (id_ex_out.ctrl.br_req.op), 
        .branch_taken_o (branch_taken_internal) 
    );
    // Bắn cờ Branch lên Control (Chỉ khi lệnh hiện tại là lệnh hợp lệ ở EX)
    assign branch_taken_o = id_ex_valid && branch_taken_internal;
    assign branch_target_addr = (id_ex_out.ctrl.br_req.is_jump) ? (id_ex_out.pc + id_ex_out.imm) : (ex_rs1_fwd_data + id_ex_out.imm);

    // --- Thu thập thông tin Trap ---
    // Ghi nhận PC và giá trị lỗi. Ưu tiên LSU lỗi ở MEM, nếu không thì lấy lỗi ở ID/EX.
    assign trap_pc_o  = lsu_err_i ? ex_mem_out.pc : if_id_out.pc;
    assign trap_val_o = lsu_err_i ? ex_mem_out.alu_result : if_id_out.instr;

    ex_mem_t ex_mem_in, ex_mem_out;
    logic ex_mem_valid, ex_mem_ready;

    assign ex_mem_in.pc         = id_ex_out.pc; // Chuyển PC xuống để dò lỗi LSU
    assign ex_mem_in.ctrl       = id_ex_out.ctrl;
    assign ex_mem_in.alu_result = ex_alu_result;
    assign ex_mem_in.m_result   = ex_m_result;
    assign ex_mem_in.csr_data   = csr_rdata_i; 
    assign ex_mem_in.store_data = ex_rs2_fwd_data;
    assign ex_mem_in.pc_plus4   = id_ex_out.pc + 32'd4;
    assign ex_mem_in.rd_addr    = id_ex_out.rd_addr;

    logic ex_stage_valid;
    // Chờ M-Unit (nếu đang tính toán) và CSR (nếu đang xử lý ngắt/ghi chép)
    assign ex_stage_valid = id_ex_valid && (id_ex_out.ctrl.m_req.valid ? ex_m_valid_o : 1'b1) && csr_ready_i;

    pipeline_reg #(ex_mem_t) u_reg_ex_mem (
        .clk_i(clk_i), .rst_i(rst_i),
        .flush_i (1'b0), 
        .valid_i (ex_stage_valid), 
        .ready_o (ex_mem_ready),
        .data_i  (ex_mem_in),
        .valid_o (ex_mem_valid),
        .ready_i (mem_wb_ready), 
        .data_o  (ex_mem_out)
    );

// ===========================================================================
// STAGE 4: MEMORY (MEM)
// ===========================================================================
    assign hz_mem_rd_addr_o = ex_mem_out.rd_addr;
    assign hz_mem_reg_we_o  = ex_mem_out.ctrl.rf_we;

    assign lsu_addr_o      = ex_mem_out.alu_result;
    assign lsu_wdata_o     = ex_mem_out.store_data;
    assign lsu_we_o        = ex_mem_out.ctrl.lsu_req.we;
    assign lsu_funct3_o    = ex_mem_out.ctrl.lsu_req.funct3;
    
    logic is_mem_access;
    assign is_mem_access   = ex_mem_out.ctrl.lsu_req.we || ex_mem_out.ctrl.lsu_req.re;
    assign lsu_req_valid_o = ex_mem_valid && is_mem_access && !lsu_err_i; // Kẹt lại nếu có lỗi
    assign lsu_rsp_ready_o = mem_wb_ready;

    mem_wb_t mem_wb_in, mem_wb_out;
    logic mem_wb_valid, mem_wb_ready;

    assign mem_wb_in.ctrl       = ex_mem_out.ctrl;
    assign mem_wb_in.alu_result = ex_mem_out.alu_result;
    assign mem_wb_in.m_result   = ex_mem_out.m_result;
    assign mem_wb_in.load_data  = lsu_rdata_i; 
    assign mem_wb_in.pc_plus4   = ex_mem_out.pc_plus4;
    assign mem_wb_in.rd_addr    = ex_mem_out.rd_addr;
    assign mem_wb_in.csr_data   = ex_mem_out.csr_data;

    logic mem_stage_valid;
    assign mem_stage_valid = ex_mem_valid && (is_mem_access ? lsu_rsp_valid_i : 1'b1) && !lsu_err_i;

    pipeline_reg #(mem_wb_t) u_reg_mem_wb (
        .clk_i(clk_i), .rst_i(rst_i),
        .flush_i (1'b0),
        .valid_i (mem_stage_valid),
        .ready_o (mem_wb_ready),
        .data_i  (mem_wb_in),
        .valid_o (mem_wb_valid),
        .ready_i (1'b1), 
        .data_o  (mem_wb_out)
    );

// ===========================================================================
// STAGE 5: WRITEBACK (WB)
// ===========================================================================
    assign hz_wb_rd_addr_o = mem_wb_out.rd_addr;
    assign hz_wb_reg_we_o  = mem_wb_out.ctrl.rf_we;

    assign rf_we    = mem_wb_out.ctrl.rf_we && mem_wb_valid;
    assign rf_waddr = mem_wb_out.rd_addr;
    
    always_comb begin
        case (mem_wb_out.ctrl.wb_sel)
            WB_ALU:      rf_wdata = mem_wb_out.alu_result;
            WB_MEM:      rf_wdata = mem_wb_out.load_data;
            WB_PC_PLUS4: rf_wdata = mem_wb_out.pc_plus4;
            WB_CSR:      rf_wdata = mem_wb_out.csr_data;
            WB_M_UNIT:   rf_wdata = mem_wb_out.m_result;
            default:     rf_wdata = mem_wb_out.alu_result; 
        endcase
    end

endmodule