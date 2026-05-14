`timescale 1ns/1ps
import riscv_32im_pkg::*;

// =============================================================================
// Module: imem - Instruction Memory
// Description: ROM-like memory cho Instruction Fetch
//              Load hex file lúc init, chỉ đọc (read-only)
//              Handshake: valid/ready protocol
// =============================================================================
module imem #(
    parameter  HEX_FILE = riscv_32im_pkg::IMEM_HEX_FILE,  // Mặc định từ package
    parameter bit    LOAD_HEX = 1,
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

    // Byte array — $readmemh với objcopy -O verilog (default) sinh byte-per-element.
    // Reconstruct 32-bit words theo little-endian: byte[4k+0]=LSB, byte[4k+3]=MSB.
    logic [7:0] mem_array [0 : MEM_SIZE-1];

    // Word address từ byte address (bỏ 2 bit cuối)
    logic [31:0] word_addr_full;
    assign word_addr_full = req_addr_i >> 2;

    // Little-endian word assembly: byte[4k]=LSB .. byte[4k+3]=MSB
    // Dùng concat để tránh lỗi 'automatic' trong always_comb
    logic [ADDR_W-1:0] word_addr;
    assign word_addr = word_addr_full[ADDR_W-1:0];

    logic [31:0] instr_fetched;
    always_comb begin
        if (word_addr_full < WORD_COUNT)
            instr_fetched = {mem_array[{word_addr, 2'b11}],
                             mem_array[{word_addr, 2'b10}],
                             mem_array[{word_addr, 2'b01}],
                             mem_array[{word_addr, 2'b00}]};
        else
            instr_fetched = 32'h0000_0013; // OOB → NOP
    end

    // ── Handshake Logic ──
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
                rsp_instr_o <= instr_fetched;
            end
            else if (rsp_ready_i) begin
                rsp_valid_o <= 1'b0;
            end
        end
    end

    // ── Initial Load ──
    initial begin
        for (int i = 0; i < MEM_SIZE; i++) mem_array[i] = 8'h0;
        if (LOAD_HEX) $readmemh(HEX_FILE, mem_array);
    end
endmodule