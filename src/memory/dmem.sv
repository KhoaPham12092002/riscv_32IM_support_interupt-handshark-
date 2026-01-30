import riscv_32im_pkg::*;

module dmem #(
    parameter int MEM_SIZE = riscv_32im_pkg::DMEM_SIZE_BYTES
) (
    input  logic        clk_i,
    input  logic        rst_i,      // Active High Reset (1 = Reset)
    // hand shark interface
    input  logic valid_i,
    output logic ready_o,
    input  logic ready_i,
    output logic valid_o,
    // --- Native Interface ---
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
    logic req_i;
    logic valid_q;
    //HAND SHARK LOGIC
    assign ready_o = ready_i;
    assign req_i = valid_i && ready_i;

    // Mapping Address: Chuyển đổi địa chỉ Byte sang Word Index
    // (Addr - Base) / 4
    localparam logic [31:0] LOCAL_BASE = riscv_32im_pkg::MAP_DMEM_BASE;
    assign word_addr = (addr_i -LOCAL_BASE ) >> 2;
   
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rdata_o <= 32'h0;
            end else begin
            // SYNCHRONOUS WRITE (Ghi đồng bộ)
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
                end else begin
                    $display ("[DMEM] ERROR: Write Address Out of Bound: Addr=%h (Idx=%0d)", addr_i, word_addr);
            end
            end
               
    //  READ LOGIC
        if (req_i && !we_i) begin
            if (word_addr < WORD_COUNT)
                rdata_o <= mem_array[word_addr];
            else
                rdata_o <= 32'h0; // Out of bound
        end else begin
            rdata_o <= 32'h0;
        end
    end
    end
// LATENCY MANAGERMENT - DMEM có độ trễ 1 chu kỳ.
    always_ff @(posedge clk_i ) begin
        if (rst_i) begin
            valid_q <= 1'b0;
        end else begin 
            if (ready_i) begin
            valid_q <= valid_i;
            end
        end
    end
    assign valid_o = valid_q;

    // --- Initial Load ---
    initial begin
        for (int i = 0; i < WORD_COUNT; i++) mem_array[i] = 32'h0;
        if (HEX_FILE != "") $readmemh(HEX_FILE, mem_array);
    end
  
endmodule
