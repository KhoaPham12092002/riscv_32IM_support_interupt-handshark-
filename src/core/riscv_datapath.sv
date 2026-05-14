import riscv_32im_pkg::*;
import riscv_instr::*;

module riscv_datapath (
    input  logic clk_i,
    input  logic rst_i,

    // ==============================================================
    // 1. INTERFACE MEMORY (IMEM & DMEM) - Khớp với mem module
    // ==============================================================
    // --- IMEM Interface ---
    output logic        if_req_valid_o,
    output logic [31:0] if_req_addr_o,
    input  logic        if_req_ready_i,
    input  logic        if_rsp_valid_i,
    input  logic [31:0] if_rsp_instr_i,
    output logic        if_rsp_ready_o,
    // --- DMEM Interface (Kênh Đôi / Two-Channel) ---
    // 1. Kênh Yêu Cầu (Request Phase)
    output logic        dmem_req_valid_o,
    input  logic        dmem_req_ready_i,
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_be_o,
    output logic        dmem_we_o,
    
    // 2. Kênh Phản Hồi (Response Phase)
    input  logic        dmem_rsp_valid_i,
    output logic        dmem_rsp_ready_o,
    input  logic [31:0] dmem_rdata_i,
    input  logic        dmem_err_i, // 1 = Lỗi truy cập bộ nhớ (ví dụ: misaligned access)
   
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
    output logic        lsu_err_o,         // LSU misaligned trap báo lên Control
    
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
    logic        lsu_err_internal;
    ex_mem_t ex_mem_in, ex_mem_out;
    logic ex_mem_valid, ex_mem_ready;
    id_ex_t id_ex_in, id_ex_out;
    logic id_ex_valid, id_ex_ready;
    mem_wb_t mem_wb_in, mem_wb_out;
    logic mem_wb_valid, mem_wb_ready;
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
    logic if_id_valid, if_id_ready;
    if_id_t if_id_in, if_id_out;  
    
    // [BUG #9 FIXED]: if_pc đã advance khi IMEM response về → cần latch PC lúc request accepted.
    logic [31:0] if_pc_latched;
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            if_pc_latched <= 32'b0;
        else if (if_req_valid_o && if_req_ready_i)
            if_pc_latched <= if_pc;
    end
    
    assign if_req_addr_o  = if_pc;
    assign if_rsp_ready_o = if_id_ready; 
    
    assign if_id_in.pc    = if_pc_latched;  // PC của lệnh đang được fetch, không phải PC tiếp theo
    assign if_id_in.instr = if_rsp_instr_i;
    // [BUG FIX]: IMEM is synchronous, so it acts as an extra pipeline stage.
    // When branch is taken in EX, we must flush ID (in ID/EX) and IF (in IF/ID).
    // BUT IMEM has already accepted a request for the instruction AFTER IF,
    // which will arrive in the NEXT cycle. We must ignore it.
    logic flush_if_id_next;
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) flush_if_id_next <= 1'b0;
        else       flush_if_id_next <= ctrl_flush_if_id_i;
    end
    
    logic real_flush_if_id;
    assign real_flush_if_id = ctrl_flush_if_id_i | flush_if_id_next;

    pipeline_reg #(.WIDTH($bits(if_id_t))) u_reg_if_id (
        .clk_i(clk_i), .rst_i(rst_i),
        .flush_i (real_flush_if_id),  // Xóa rác theo lệnh của Control (hiện tại và chu kỳ sau)
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

    decoder u_decoder (
        .instr_i    (if_id_out.instr),
        .ctrl_o     (id_ctrl),
        .imm_o      (id_imm),
        .rd_addr_o  (id_rd_addr),
        .rs1_addr_o (id_rs1_addr),
        .rs2_addr_o (id_rs2_addr)
    );

    // --- Giải mã thủ công các lệnh đặc biệt cho Control & CSR ---
    assign id_is_ecall_o      = if_id_valid && (if_id_out.instr == 32'h00000073);
    assign id_is_mret_o       = if_id_valid && (if_id_out.instr == 32'h30200073);
    assign id_illegal_instr_o = if_id_valid && id_ctrl.illegal_instr;

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

    assign id_ex_in.pc       = if_id_out.pc;
    assign id_ex_in.ctrl     = id_ctrl;
    assign id_ex_in.rs1_data = rf_rs1_data;
    assign id_ex_in.rs2_data = rf_rs2_data;
    assign id_ex_in.imm      = id_imm;
    assign id_ex_in.rd_addr  = id_rd_addr;
    assign id_ex_in.rs1_addr = id_rs1_addr;
    assign id_ex_in.rs2_addr = id_rs2_addr;

    logic        ex_m_valid_o, ex_m_ready_o;
    logic ex_m_stall;
    assign ex_m_stall = id_ex_valid && id_ex_out.ctrl.m_req.valid && !ex_m_valid_o;

    pipeline_reg #(.WIDTH($bits(id_ex_t))) u_reg_id_ex (
        .clk_i  (clk_i), .rst_i  (rst_i),
        .flush_i (ctrl_flush_id_ex_i),
        .valid_i (if_id_valid),
        .ready_o (id_ex_ready),
        .data_i  (id_ex_in),
        .valid_o (id_ex_valid),
        .ready_i (ex_mem_ready && !ex_m_stall),
        .data_o  (id_ex_out)
    );

// ===========================================================================
// STAGE 3: EXECUTE (EX)
// ===========================================================================
    assign hz_ex_rs1_addr_o = id_ex_out.rs1_addr;
    assign hz_ex_rs2_addr_o = id_ex_out.rs2_addr;
    assign hz_ex_rd_addr_o  = id_ex_out.rd_addr;
    assign hz_ex_reg_we_o   = id_ex_out.ctrl.rf_we && id_ex_valid;
    assign hz_ex_wb_sel_o   = id_ex_out.ctrl.wb_sel;

    // --- Forwarding Mux ---
    logic [31:0] ex_rs1_fwd_data, ex_rs2_fwd_data;

    // Forward declaration để dùng trong mem_fwd_val (LSU thực sự instance dưới MEM stage)
    logic [31:0] lsu_aligned_rdata;

    // MEM-stage forward value: với LOAD phải lấy dữ liệu đọc về (lsu_aligned_rdata),
    // KHÔNG phải alu_result (alu_result của load = địa chỉ).
    logic [31:0] mem_fwd_val;
    assign mem_fwd_val = (ex_mem_out.ctrl.wb_sel == WB_MEM) ? lsu_aligned_rdata
                                                            : ex_mem_out.alu_result;

    // --- Forwarding Latch (Fix for Stall Hazard) ---
    logic [31:0] ex_rs1_latched, ex_rs2_latched;
    logic ex_rs1_fwd_valid, ex_rs2_fwd_valid;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            ex_rs1_latched <= 32'b0;
            ex_rs1_fwd_valid <= 1'b0;
            ex_rs2_latched <= 32'b0;
            ex_rs2_fwd_valid <= 1'b0;
        end else begin
            if ((ex_mem_ready && !ex_m_stall) || ctrl_flush_id_ex_i) begin
                ex_rs1_fwd_valid <= 1'b0;
                ex_rs2_fwd_valid <= 1'b0;
            end else if (id_ex_valid) begin
                if (ctrl_fwd_rs1_sel_i == 2'b01) begin
                    ex_rs1_latched <= mem_fwd_val;
                    ex_rs1_fwd_valid <= 1'b1;
                end else if (ctrl_fwd_rs1_sel_i == 2'b10) begin
                    ex_rs1_latched <= rf_wdata;
                    ex_rs1_fwd_valid <= 1'b1;
                end
                
                if (ctrl_fwd_rs2_sel_i == 2'b01) begin
                    ex_rs2_latched <= mem_fwd_val;
                    ex_rs2_fwd_valid <= 1'b1;
                end else if (ctrl_fwd_rs2_sel_i == 2'b10) begin
                    ex_rs2_latched <= rf_wdata;
                    ex_rs2_fwd_valid <= 1'b1;
                end
            end
        end
    end

    always_comb begin
        if (ctrl_fwd_rs1_sel_i == 2'b01) ex_rs1_fwd_data = mem_fwd_val;
        else if (ctrl_fwd_rs1_sel_i == 2'b10) ex_rs1_fwd_data = rf_wdata;
        else if (ex_rs1_fwd_valid) ex_rs1_fwd_data = ex_rs1_latched;
        else ex_rs1_fwd_data = id_ex_out.rs1_data;
    end

    always_comb begin
        if (ctrl_fwd_rs2_sel_i == 2'b01) ex_rs2_fwd_data = mem_fwd_val;
        else if (ctrl_fwd_rs2_sel_i == 2'b10) ex_rs2_fwd_data = rf_wdata;
        else if (ex_rs2_fwd_valid) ex_rs2_fwd_data = ex_rs2_latched;
        else ex_rs2_fwd_data = id_ex_out.rs2_data;
    end

    // --- ALU & M-UNIT ---
    alu_in_t ex_alu_in;
    logic        ex_alu_zero;
    logic [31:0] ex_alu_result;
    
    assign ex_alu_in.rs1_data = (id_ex_out.ctrl.alu_req.op_a_sel == OP_A_PC)  ? id_ex_out.pc  : ex_rs1_fwd_data;
    assign ex_alu_in.rs2_data = (id_ex_out.ctrl.alu_req.op_b_sel == OP_B_IMM) ? id_ex_out.imm : ex_rs2_fwd_data;
    assign ex_alu_in.op = id_ex_out.ctrl.alu_req.op;
    assign ex_alu_in.valid_i = id_ex_valid;
    assign ex_alu_in.ready_i = ex_mem_ready;

    alu u_alu (.alu_in(ex_alu_in), .Zero(ex_alu_zero), .alu_o(ex_alu_result));

    logic [31:0] ex_m_result;
    m_in_t       ex_m_in;
    assign ex_m_in.rs1_data = ex_rs1_fwd_data; assign ex_m_in.rs2_data = ex_rs2_fwd_data; assign ex_m_in.op  = id_ex_out.ctrl.m_req.op;

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
    // Bắn cờ Branch lên Control (Chỉ khi lệnh hiện tại là lệnh hợp lệ ở EX VÀ thực sự là branch/jump)
    // [BUG #7 FIXED]: BR_REQ_RST.op = BR_BEQ = 0. ADDI với rs1=rs2=x0 → branch_cmp=1 → false branch!
    // Phải guard thêm (is_branch || is_jump) để chỉ branch/jump thực sự mới trigger.
    // [BUG #10 FIXED]: JAL/JALR (is_jump=1) phải nhảy vô điều kiện — không phụ thuộc branch_taken_internal.
    // branch_cmp chỉ tính điều kiện cho BEQ/BNE/...; với JAL/JALR nó cho kết quả bất kỳ (có thể = 0).
    assign branch_taken_o = id_ex_valid
                            && (id_ex_out.ctrl.br_req.is_jump
                                || (id_ex_out.ctrl.br_req.is_branch && branch_taken_internal));
    // [BUG #6 FIXED]: Branch target = PC+IMM (BEQ/BNE/..) hoặc RS1+IMM (JALR).
    // ALU ĐÃ tính đúng vì decoder set op_a_sel=OP_A_PC cho branches, OP_A_RS1 cho JALR.
    // Không cần tính lại — dùng thẳng ex_alu_result.
    assign branch_target_addr = ex_alu_result;

    // --- Thu thập thông tin Trap ---
    // Ghi nhận PC và giá trị lỗi. Ưu tiên LSU lỗi ở MEM, nếu không thì lấy lỗi ở ID/EX.
    assign trap_pc_o  = (lsu_err_internal || dmem_err_i) ? ex_mem_out.pc : if_id_out.pc;
    assign trap_val_o = (lsu_err_internal || dmem_err_i) ? ex_mem_out.alu_result : if_id_out.instr;
  
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
    logic is_mem_access;
    logic lsu_valid_out;
    assign is_mem_access = ex_mem_out.ctrl.lsu_req.we || ex_mem_out.ctrl.lsu_req.re;
    pipeline_reg #(.WIDTH($bits(ex_mem_t))) u_reg_ex_mem (
        .clk_i(clk_i), .rst_i(rst_i),
        .flush_i (1'b0), 
        .valid_i (ex_stage_valid), 
        .ready_o (ex_mem_ready),
        .data_i  (ex_mem_in),
        .valid_o (ex_mem_valid),
        .ready_i (is_mem_access ? (lsu_valid_out && mem_wb_ready) : mem_wb_ready), 
        .data_o  (ex_mem_out)
    );

// ===========================================================================
// STAGE 4: MEMORY (MEM)
// ===========================================================================
    assign hz_mem_rd_addr_o = ex_mem_out.rd_addr;
    assign hz_mem_reg_we_o  = ex_mem_out.ctrl.rf_we && ex_mem_valid;

    logic        lsu_ready_out;

    lsu u_lsu_core (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        
        // Giao tiếp với Pipeline (Nhận lệnh từ Tầng 3)
        .addr_i           (ex_mem_out.alu_result),
        .wdata_i          (ex_mem_out.store_data),
        .lsu_we_i         (ex_mem_out.ctrl.lsu_req.we),
        .funct3_i         ({ex_mem_out.ctrl.lsu_req.is_unsigned, ex_mem_out.ctrl.lsu_req.width}),
        
        .valid_i          (ex_mem_valid && is_mem_access && !dmem_err_i), 
        .ready_o          (lsu_ready_out),
        .valid_o          (lsu_valid_out),
        .ready_i          (mem_wb_ready), 
        
        // Giao tiếp với Pipeline (Trọng tài lỗi và dữ liệu chuẩn)
        .lsu_rdata_o      (lsu_aligned_rdata),
        .lsu_err_o        (lsu_err_internal),

        // Giao tiếp cáp chuẩn ra bên ngoài SoC (DMEM)
        .dmem_req_valid_o (dmem_req_valid_o),
        .dmem_req_ready_i (dmem_req_ready_i),
        .dmem_addr_o      (dmem_addr_o),
        .dmem_wdata_o     (dmem_wdata_o),
        .dmem_be_o        (dmem_be_o),
        .dmem_we_o        (dmem_we_o),
        .dmem_rsp_valid_i (dmem_rsp_valid_i),
        .dmem_rsp_ready_o (dmem_rsp_ready_o),
        .dmem_rdata_i     (dmem_rdata_i)
    );



    assign mem_wb_in.ctrl       = ex_mem_out.ctrl;
    assign mem_wb_in.alu_result = ex_mem_out.alu_result;
    assign mem_wb_in.m_result   = ex_mem_out.m_result;
    assign mem_wb_in.load_data  = lsu_aligned_rdata; 
    assign mem_wb_in.pc_plus4   = ex_mem_out.pc_plus4;
    assign mem_wb_in.rd_addr    = ex_mem_out.rd_addr;
    assign mem_wb_in.csr_data   = ex_mem_out.csr_data;

    assign lsu_err_o = lsu_err_internal;

    logic mem_stage_valid;
    assign mem_stage_valid = ex_mem_valid && (is_mem_access ? lsu_valid_out : 1'b1) && !lsu_err_internal && !dmem_err_i;

    pipeline_reg #(.WIDTH($bits(mem_wb_t))) u_reg_mem_wb (
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
    assign hz_wb_reg_we_o  = mem_wb_out.ctrl.rf_we && mem_wb_valid;

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