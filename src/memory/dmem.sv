`timescale 1ns/1ps
import riscv_32im_pkg::*;

module dmem #(
    parameter int MEM_SIZE = riscv_32im_pkg::DMEM_SIZE_BYTES
) (
    input  logic        clk_i,
    input  logic        rst_i,      
    
    // --- Interface with LSU ---
    input  logic        req_valid_i,  
    output logic        req_ready_o,  
    input  logic [31:0] req_addr_i,   
    input  logic [31:0] req_wdata_i,  
    input  logic [3:0]  req_be_i,     // Byte Enable
    input  logic        req_we_i,     // 1 = Write, 0 = Read

    output logic        rsp_valid_o,  
    input  logic        rsp_ready_i,  
    output logic [31:0] rsp_rdata_o   
);

    localparam int WORD_COUNT = MEM_SIZE / 4;
    localparam int ADDR_W     = $clog2(WORD_COUNT);

    // Mảng bộ nhớ chính
    logic [31:0] mem_array [0 : WORD_COUNT-1];

    // Cắt địa chỉ để lấy Index (bỏ qua 2 bit cuối vì Word-aligned)
    logic [ADDR_W-1:0] word_addr;
    assign word_addr = req_addr_i[ADDR_W+1 : 2];

    // Handshake Logic
    assign req_ready_o = ~rsp_valid_o || rsp_ready_i;
    logic req_fire;
    assign req_fire = req_valid_i && req_ready_o;

    // ===================================================================
    // LƯU Ý: Dùng 'always' thay vì 'always_ff' để tránh lỗi vopt-7061
    // khi dùng chung với khối 'initial' ở bên dưới.
    // ===================================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            rsp_valid_o <= 1'b0;
            rsp_rdata_o <= 32'h0;
        end else begin
            if (req_fire) begin
                rsp_valid_o <= 1'b1;
                
                if (req_we_i) begin
                    // LỆNH GHI (Phân mảnh theo Byte Enable)
                    if (word_addr < WORD_COUNT) begin
                        if (req_be_i[0]) mem_array[word_addr][7:0]   <= req_wdata_i[7:0];
                        if (req_be_i[1]) mem_array[word_addr][15:8]  <= req_wdata_i[15:8];
                        if (req_be_i[2]) mem_array[word_addr][23:16] <= req_wdata_i[23:16];
                        if (req_be_i[3]) mem_array[word_addr][31:24] <= req_wdata_i[31:24];
                    end
                    rsp_rdata_o <= 32'h0; // Ghi thì không cần Data trả về
                end 
                else begin
                    // LỆNH ĐỌC
                    if (word_addr < WORD_COUNT) begin
                        rsp_rdata_o <= mem_array[word_addr];
                    end else begin
                        rsp_rdata_o <= 32'h0; // Trả về 0 nếu Out-of-bounds
                    end
                end
            end 
            else if (rsp_ready_i) begin
                rsp_valid_o <= 1'b0; // Stage sau đã nhận lệnh -> Xả cờ
            end
        end
    end

    // Khởi tạo RAM rỗng (0x0)
    initial begin
        for (int i = 0; i < WORD_COUNT; i++) mem_array[i] = 32'h0;
    end

endmodule