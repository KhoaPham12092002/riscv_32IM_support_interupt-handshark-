import memory_pkg::*;

module dmem #(
    parameter int MEM_SIZE = memory_pkg::DMEM_SIZE_BYTES
) (
    input  logic        clk_i,
    input  logic        rst_i,      // Active High Reset (1 = Reset)
    
    // --- Native Interface ---
    input  logic        req_i,      // Chip Select (1 = Select DMEM)
    input  logic        we_i,       // Write Enable (1 = Write, 0 = Read)
    input  logic [3:0]  be_i,       // Byte Enable (Mask cho SB, SH, SW)
    input  logic [31:0] addr_i,     // Address
    input  logic [31:0] wdata_i,    // Write Data
    output logic [31:0] rdata_o     // Read Data
);

    localparam int WORD_COUNT = MEM_SIZE / 4;
    
    // Mảng nhớ chính
    logic [31:0] mem_array [0 : WORD_COUNT-1];
    logic [31:0] word_addr;

    // Mapping Address: Chuyển đổi địa chỉ Byte sang Word Index
    // (Addr - Base) / 4
    localparam logic [31:0] LOCAL_BASE = memory_pkg::MAP_DMEM_BASE;
    assign word_addr = (addr_i -LOCAL_BASE ) >> 2;
    
    // ========================================================================
    // 1. ASYNCHRONOUS READ (Đọc tổ hợp)
    // ========================================================================
    // Giúp Pipeline đơn giản hóa tầng MEM, không bị trễ 1 nhịp.
    always_comb begin
        // Chỉ đọc khi có Request VÀ KHÔNG Ghi (Write Priority hoặc Read Independent tùy thiết kế)
        // Ở đây ưu tiên: Nếu đang chọn DMEM và không ghi -> Trả dữ liệu
        if (req_i && !we_i) begin
            if (word_addr < WORD_COUNT)
                rdata_o = mem_array[word_addr];
            else
                rdata_o = 32'h0; // Out of bound
        end else begin
            rdata_o = 32'h0;
        end
    end

    // ========================================================================
    // 2. SYNCHRONOUS WRITE (Ghi đồng bộ)
    // ========================================================================
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            // Reset: Xóa trắng bộ nhớ (Tùy chọn, mô phỏng thì nên có)
            for (int i = 0; i < WORD_COUNT; i++) begin
                mem_array[i] <= 32'h0;
            end
        end else begin
            // Logic Ghi: Phải có Req + Write Enable
            if (req_i && we_i) begin
		    $display("[RTL_READ]  Time:%0t | Addr=%h (Idx=%0d) | RDATA_INTERNAL=%h", 
                     $time, addr_i, word_addr, mem_array[word_addr]);
		    if (word_addr < WORD_COUNT) begin
                    // Hỗ trợ Byte Enable (Cho các lệnh store: sb, sh, sw)
                    if (be_i[0]) mem_array[word_addr][7:0]   <= wdata_i[7:0];
                    if (be_i[1]) mem_array[word_addr][15:8]  <= wdata_i[15:8];
                    if (be_i[2]) mem_array[word_addr][23:16] <= wdata_i[23:16];
                    if (be_i[3]) mem_array[word_addr][31:24] <= wdata_i[31:24];
                end
            end
        end
    end
endmodule
