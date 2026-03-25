`timescale 1ns/1ps
import riscv_32im_pkg::*;

module imem #(
    parameter string HEX_FILE = "new_code.hex",
    parameter int    MEM_SIZE = riscv_32im_pkg::IMEM_SIZE_BYTES
) (
    input  logic        clk_i,
    input  logic        rst_i,     // Active high Reset
    // --- hand shark Interface ---
    
    // Request Phase - From PC_GEN
    input   logic            req_valid_i, // Khi PC_GEN có địa chỉ PC mới
    input   logic [31:0]     req_addr_i,  // giá trị PC
    output  logic            req_ready_o, // IMEM báo đang có ô trống
    
    // Response Phase - To Decoder/ Pipeline
    output  logic           rsp_valid_o,    // Khi IMEM báo lệnh đã được đọc
    input   logic           rsp_ready_i,    // Khi decoder rảnh
    output  logic [31:0]    rsp_instr_o   // Instruction Data 
);

    localparam int WORD_COUNT = MEM_SIZE / 4;
    localparam int ADDR_W     = $clog2(WORD_COUNT);
    
    logic [31:0] mem_array [0 : WORD_COUNT-1];

    logic [31:0] word_addr_full;
    assign word_addr_full = req_addr_i >> 2;
    logic [ADDR_W-1:0] word_addr;

    // Mapping Address
    assign word_addr = req_addr_i[ADDR_W+1 : 2];

    // 2. HANDSHAKE LOGIC (Tránh sập Timing)
    // IMEM chỉ nhận địa chỉ khi L
    // không giữ lệnh nào rsp_valid_o = 0 Hoặc stage sau đã nhận lệnh (rsp_ready_i =1)
    
        assign req_ready_o = ~rsp_valid_o || rsp_ready_i;
    // chỉ đọc RAM khi req handshark

    logic read_req ;
    assign read_req = req_valid_i && req_ready_o ;
    
    
// --- Core Logic (delay 1 clk ) ---
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rsp_valid_o <= 1'b0;
            rsp_instr_o <= 32'h0000_0013; // Reset về NOP
        end 
        else begin
            if (read_req) begin
                rsp_valid_o <= 1'b1;
                if (word_addr_full < WORD_COUNT) begin
                    rsp_instr_o <= mem_array[word_addr_full[ADDR_W-1:0]];
                end 
                else begin 
                    rsp_instr_o <= 32'h0000_0013; // OOB trả về NOP
                   //display("[IMEM] WARNING: PC OOB: %h", req_addr_i);
                end
            end // <--- CẬU THIẾU CÁI END NÀY
            else if (rsp_ready_i) begin
                rsp_valid_o <= 1'b0; // Xả cờ khi stage sau đã nhận lệnh
            end
        end
    end
           
    // --- Initial Load ---
    initial begin
        for (int i = 0; i < WORD_COUNT; i++) mem_array[i] = 32'h0;
       if (HEX_FILE != "") $readmemh(HEX_FILE, mem_array);
    end
    endmodule