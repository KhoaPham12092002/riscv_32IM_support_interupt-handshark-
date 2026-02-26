import riscv_32im_pkg::*; 
import riscv_instr::*;

module csr (
    input  logic        clk_i,
    input  logic        rst_i,

    // --- Core Access Interface (Từ EX Stage) ---
    // Dữ liệu wdata trong csr_req_i đã được chọn (RS1 hoặc Imm) ở ngoài
    input  csr_req_t    csr_req_i, 
    output logic [31:0] csr_rdata_o, 

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

// 1. KHAI BÁO CÁC THANH GHI CSR (Machine Mode Standard)
    
    // mstatus: Trạng thái hệ thống
    // [12:11] MPP (Machine Previous Privilege) - Hardwire 11 (Machine)
    // [7] MPIE (Previous Interrupt Enable)
    // [3] MIE (Global Interrupt Enable)
    logic [31:0] mstatus; 

    // mie: Cho phép ngắt cụ thể
    // [11] MEIE (External), [7] MTIE (Timer), [3] MSIE (Software)
    logic [31:0] mie;     

    // mtvec: Địa chỉ cơ sở của hàm xử lý ngắt
    logic [31:0] mtvec;   

    // mepc: Lưu PC khi xảy ra lỗi
    logic [31:0] mepc;    

    // mcause: Nguyên nhân lỗi
    logic [31:0] mcause;  

    // mtval: Giá trị lỗi (VD: Địa chỉ truy cập sai)
    logic [31:0] mtval;   

    // mscratch: Thanh ghi nháp (thường để lưu con trỏ Stack kernel)
    logic [31:0] mscratch;

    // mip: Báo hiệu ngắt đang chờ (Pending)
    logic [31:0] mip;     
// 2. LOGIC ĐỌC CSR (Read Logic - Combinational)
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
            CSR_MHARTID:  csr_rdata_o = 32'b0; // Core 0
            default:      csr_rdata_o = 32'b0; // Đọc địa chỉ lạ trả về 0
        endcase
    end

// 3. LOGIC TÍNH TOÁN DỮ LIỆU GHI (Write Data Calculation)
    logic [31:0] wdata_final;
    
    always_comb begin
        // Dựa vào giá trị hiện tại (csr_rdata_o) và dữ liệu mới (csr_req_i.wdata)
        case (csr_req_i.op)
            CSR_RW: wdata_final = csr_req_i.wdata;                   // Ghi đè
            CSR_RS: wdata_final = csr_rdata_o | csr_req_i.wdata;     // Bật bit (Set)
            CSR_RC: wdata_final = csr_rdata_o & ~csr_req_i.wdata;    // Tắt bit (Clear)
            default: wdata_final = csr_rdata_o;                      // Giữ nguyên
        endcase
    end

// 4. LOGIC CẬP NHẬT THANH GHI (Sequential Logic)
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            // Reset Values
            mstatus  <= 32'h0000_1800; // MPP=11 (Machine Mode)
            mie      <= 32'b0;
            mtvec    <= 32'b0;
            mepc     <= 32'b0;
            mcause   <= 32'b0;
            mtval    <= 32'b0;
            mscratch <= 32'b0;
            mip      <= 32'b0;
        end else begin
            // --- A. Cập nhật MIP (Ngắt Pending) ---
            // MIP phản ánh trực tiếp tín hiệu ngắt bên ngoài
            mip[11] <= irq_ext_i;   // MEIP
            mip[7]  <= irq_timer_i; // MTIP
            mip[3]  <= irq_sw_i;    // MSIP
            
            // --- B. Xử lý Trap (Ưu tiên cao nhất) ---
            if (trap_valid_i) begin
                mepc    <= trap_pc_i;             // Lưu PC lỗi
                mcause  <= {28'b0, trap_cause_i}; // Lưu mã lỗi (Cần xử lý bit 31 cho Interrupt sau)
                mtval   <= trap_val_i;            // Lưu giá trị lỗi
                
                // Cập nhật mstatus (Save context)
                mstatus[7] <= mstatus[3];     // MPIE = MIE (Lưu trạng thái ngắt cũ)
                mstatus[3] <= 1'b0;           // MIE = 0 (Tắt ngắt toàn cục để xử lý lỗi)
                mstatus[12:11] <= 2'b11;      // MPP = Machine Mode
            end 
            
            // --- C. Xử lý MRET (Quay về từ Trap) ---
            else if (mret_i) begin
                // Khôi phục mstatus (Restore context)
                mstatus[3] <= mstatus[7];     // MIE = MPIE (Khôi phục trạng thái ngắt)
                mstatus[7] <= 1'b1;           // MPIE = 1 (Mặc định bật lại ngắt dự phòng)
                mstatus[12:11] <= 2'b00;      // MPP = User (Hoặc giữ 11 nếu chỉ hỗ trợ M-mode)
            end
            
            // --- D. Xử lý Ghi CSR thông thường (Từ lệnh phần mềm) ---
            else if (csr_req_i.valid) begin
                case (csr_req_i.addr)
                    CSR_MSTATUS: begin
                        // Chỉ cho phép ghi các bit MIE, MPIE
                        mstatus[3] <= wdata_final[3];
                        mstatus[7] <= wdata_final[7];
                    end
                    CSR_MIE: begin
                        // Chỉ cho phép ghi các bit MEIE, MTIE, MSIE
                        mie[11] <= wdata_final[11];
                        mie[7]  <= wdata_final[7];
                        mie[3]  <= wdata_final[3];
                    end
                    CSR_MTVEC:    mtvec    <= wdata_final;
                    CSR_MEPC:     mepc     <= wdata_final;
                    CSR_MCAUSE:   mcause   <= wdata_final;
                    CSR_MTVAL:    mtval    <= wdata_final;
                    CSR_MSCRATCH: mscratch <= wdata_final;
                    // MIP thường là Read-Only đối với Software (trừ Software Interrupt)
                endcase
            end
        end
    end

// --- Output Mapping ---
    assign epc_o = mepc;         // Địa chỉ để MRET nhảy về
    assign trap_vector_o = mtvec;// Địa chỉ để Trap nhảy đến

endmodule