import riscv_32im_pkg::*; 
import riscv_instr::*;

module csr (
    input  logic        clk_i,
    input  logic        rst_i,

    // --- Core Access Interface (Từ EX Stage) ---
    input  csr_req_t    csr_req_i,    // valid, addr, wdata, op
    output logic        csr_ready_o,  //  1 = ready, 0 = stuck
    output logic [31:0] csr_rdata_o,  // 
    output logic        csr_rsp_valid_o, // To EX: "Data rdata_o valid" (Cho AXI R-Channel)

    // --- Exception/Trap Interface (Từ Hazard/Commit Logic) ---
    input  logic        trap_valid_i,  // 1 = Có lỗi/ngắt xảy ra
    input  logic [3:0]  trap_cause_i,  // Mã lỗi (mcause)
    input  logic [31:0] trap_pc_i,     // PC bị lỗi (mepc)
    input  logic [31:0] trap_val_i,    // Giá trị phụ (mtval)
    input  logic        mret_i,        // 1 = Lệnh MRET (Return)

    // --- Output tới PC Generator ---
    output logic [31:0] epc_o,         // Địa chỉ quay về (PC = mepc)
    output logic [31:0] trap_vector_o, // Địa chỉ xử lý lỗi (PC = mtvec)
    
    // --- Interrupt Inputs (Từ bên ngoài) ---
    input  logic        irq_sw_i,      // Software Interrupt
    input  logic        irq_timer_i,   // Timer Interrupt
    input  logic        irq_ext_i      // External Interrupt
);

// ===========================================================================
// 1. KHAI BÁO CÁC THANH GHI CSR  - AREA OPTIMIZED
// ===========================================================================
    
    // --- mstatus: Chỉ dùng 2 DFF cho MIE và MPIE ---
    
    logic mstatus_mpie;
    logic mstatus_mie;
    logic [31:0] mstatus; 
    assign mstatus = {19'b0, 2'b11, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
    
    logic mie_meie, mie_mtie, mie_msie; 
    logic [31:0] mie;
    assign mie = {20'b0, mie_meie, 3'b0, mie_mtie, 3'b0, mie_msie, 3'b0};

    logic [31:0] mip; 
    assign mip = {20'b0, irq_ext_i, 3'b0, irq_timer_i, 3'b0, irq_sw_i, 3'b0};

    logic [31:0] mtvec, mepc, mcause, mtval, mscratch;

// 2. LOGIC HANDSHAKE & READ COMBINATIONAL
    // Nếu có Trap, kéo Ready = 0 
    assign csr_ready_o = ~trap_valid_i; 

    // confirm handshark
    logic handshake_ok;
    assign handshake_ok = csr_req_i.valid && csr_ready_o;

    //(RSP VALID) 
    // Tín hiệu này sau này nối thẳng vào cờ RVALID của AXI-Lite.
    assign csr_rsp_valid_o = handshake_ok;

    always_comb begin
        case (csr_req_i.addr)
            CSR_MSTATUS:  csr_rdata_o = mstatus;
            CSR_MIE:      csr_rdata_o = mie;
            CSR_MTVEC:    csr_rdata_o = mtvec;
            CSR_MSCRATCH: csr_rdata_o = mscratch;
            CSR_MEPC:     csr_rdata_o = mepc;
            CSR_MCAUSE:   csr_rdata_o = mcause;
            CSR_MTVAL:    csr_rdata_o = mtval;
            CSR_MIP:      csr_rdata_o = mip;
            CSR_MHARTID:  csr_rdata_o = 32'b0; 
            default:      csr_rdata_o = 32'b0; 
        endcase
    end
// 3. LOGIC XỬ LÝ DỮ LIỆU GHI & WRITE ENABLE (COMBINATIONAL)

    logic [31:0] wdata_final;
    logic        is_write_op;
    
    always_comb begin
        case (csr_req_i.op)
            CSR_RW:  wdata_final = csr_req_i.wdata;
            CSR_RS:  wdata_final = csr_rdata_o | csr_req_i.wdata;
            CSR_RC:  wdata_final = csr_rdata_o & ~csr_req_i.wdata;
            default: wdata_final = csr_rdata_o;
        endcase

        is_write_op = (csr_req_i.op == CSR_RW) || 
                      ((csr_req_i.op == CSR_RS || csr_req_i.op == CSR_RC) && (csr_req_i.wdata != 32'b0));
    end

    // Tín hiệu Write Enable (we) BẮT BUỘC phải handshake_ok
    logic we_mstatus, we_mie, we_mtvec, we_mepc, we_mcause, we_mtval, we_mscratch;
    
    assign we_mstatus  = handshake_ok && is_write_op && (csr_req_i.addr == CSR_MSTATUS);
    assign we_mie      = handshake_ok && is_write_op && (csr_req_i.addr == CSR_MIE);
    assign we_mtvec    = handshake_ok && is_write_op && (csr_req_i.addr == CSR_MTVEC);
    assign we_mepc     = handshake_ok && is_write_op && (csr_req_i.addr == CSR_MEPC);
    assign we_mcause   = handshake_ok && is_write_op && (csr_req_i.addr == CSR_MCAUSE);
    assign we_mtval    = handshake_ok && is_write_op && (csr_req_i.addr == CSR_MTVAL);
    assign we_mscratch = handshake_ok && is_write_op && (csr_req_i.addr == CSR_MSCRATCH);

// 4. LOGIC CẬP NHẬT THANH GHI 


    // --- A. Khối mstatus (Chịu ảnh hưởng bởi Trap, MRET và Software) ---
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
        end else if (trap_valid_i) begin
            mstatus_mpie <= mstatus_mie; // Lưu hiện trường cầu dao
            mstatus_mie  <= 1'b0;        // Sập cầu dao tổng
        end else if (mret_i) begin
            mstatus_mie  <= mstatus_mpie;// Khôi phục cầu dao
            mstatus_mpie <= 1'b1;        // Mặc định bật lại ngắt dự phòng
        end else if (we_mstatus) begin
            mstatus_mie  <= wdata_final[3];
            mstatus_mpie <= wdata_final[7];
        end
    end

    // --- B. Khối mepc, mcause, mtval (Chịu ảnh hưởng bởi Trap và Software) ---
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            mepc   <= 32'b0;
            mcause <= 32'b0;
            mtval  <= 32'b0;
        end else if (trap_valid_i) begin
            mepc   <= trap_pc_i;
            mcause <= {28'b0, trap_cause_i}; // Có thể ghép bit 31 (Interrupt flag) từ bộ Hazard vào đây sau
            mtval  <= trap_val_i;
        end else begin
            if (we_mepc)   mepc   <= wdata_final;
            if (we_mcause) mcause <= wdata_final;
            if (we_mtval)  mtval  <= wdata_final;
        end
    end

    // --- C. Khối mie, mtvec, mscratch (CHỈ chịu ảnh hưởng bởi Software) ---
    // Hoàn toàn không bị Trap đè (No Priority Masking)
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            mie_meie <= 1'b0;
            mie_mtie <= 1'b0;
            mie_msie <= 1'b0;
            mtvec    <= 32'b0;
            mscratch <= 32'b0;
        end else begin
            if (we_mie) begin
                mie_meie <= wdata_final[11];
                mie_mtie <= wdata_final[7];
                mie_msie <= wdata_final[3];
            end
            if (we_mtvec)    mtvec    <= wdata_final;
            if (we_mscratch) mscratch <= wdata_final;
        end
    end

// 5. OUTPUT MAPPING
    assign epc_o         = mepc;  
    assign trap_vector_o = mtvec; 

endmodule