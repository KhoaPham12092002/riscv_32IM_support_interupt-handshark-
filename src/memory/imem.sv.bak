`timescale 1ns/1ps
import riscv_32im_pkg::*;

// =============================================================================
// Module: imem - Instruction Memory
// Description: ROM-like memory cho Instruction Fetch
//              Load hex file lúc init, chỉ đọc (read-only)
//              Handshake: valid/ready protocol
// =============================================================================
module imem #(
    parameter string HEX_FILE = riscv_32im_pkg::IMEM_HEX_FILE,  // Mặc định từ package
    parameter int    MEM_SIZE = riscv_32im_pkg::IMEM_SIZE_BYTES
) (
    input  logic        clk_i,
    input  logic        rst_i,     // Active high Reset
    
    // --- Handshake Interface ---
    // Request Phase - From PC_GEN
    input   logic            req_valid_i, // Khi PC_GEN có địa chỉ PC mới
    input   logic [31:0]     req_addr_i,  // Giá trị PC
    output  logic            req_ready_o, // IMEM báo đang có ô trống
    
    // Response Phase - To Pipeline
    output  logic           rsp_valid_o,    // Khi IMEM báo lệnh đã được đọc
    input   logic           rsp_ready_i,    // Khi stage sau rảnh
    output  logic [31:0]    rsp_instr_o     // Instruction Data 
);

    localparam int WORD_COUNT = MEM_SIZE / 4;
    localparam int ADDR_W     = $clog2(WORD_COUNT);
    
    logic [31:0] mem_array [0 : WORD_COUNT-1];

    // Word address từ byte address (bỏ 2 bit cuối)
    logic [31:0] word_addr_full;
    assign word_addr_full = req_addr_i >> 2;
    logic [ADDR_W-1:0] word_addr;
    assign word_addr = req_addr_i[ADDR_W+1 : 2];

    // ── Handshake Logic ──
    // IMEM sẵn sàng nhận request khi:
    //   - Không đang giữ response chưa được nhận (rsp_valid_o = 0)
    //   - HOẶC stage sau đã nhận xong (rsp_ready_i = 1)
    assign req_ready_o = ~rsp_valid_o || rsp_ready_i;

    logic read_req;
    assign read_req = req_valid_i && req_ready_o;

    // ── Core Logic (1 cycle latency) ──
    // Dùng 'always' thay vì 'always_ff' để tránh lỗi vopt-7061
    // khi dùng chung với khối 'initial' ở bên dưới.
    always @(posedge clk_i) begin
        if (rst_i) begin
            rsp_valid_o <= 1'b0;
            rsp_instr_o <= 32'h0000_0013; // Reset về NOP (addi x0, x0, 0)
        end 
        else begin
            if (read_req) begin
                rsp_valid_o <= 1'b1;
                if (word_addr_full < WORD_COUNT) begin
                    rsp_instr_o <= mem_array[word_addr_full[ADDR_W-1:0]];
                end 
                else begin 
                    rsp_instr_o <= 32'h0000_0013; // OOB → NOP
                end
            end
            else if (rsp_ready_i) begin
                rsp_valid_o <= 1'b0; // Stage sau đã nhận → xả cờ
            end
        end
    end
           
    // ── Initial Load ──
    initial begin
        for (int i = 0; i < WORD_COUNT; i++) mem_array[i] = 32'h0;
        if (HEX_FILE != "") $readmemh(HEX_FILE, mem_array);
    end

endmodule