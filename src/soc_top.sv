import riscv_32im_pkg::*;
import riscv_instr::*;
`timescale 1ns/1ps
module soc_top (
    input  logic        clk_i,
    input  logic        rst_i,
    output logic [31:0] debug_pc_o // Để soi PC trên Waveform
);

    // =========================================================================
    // 1. INTERNAL SIGNALS (Dây nối)
    // =========================================================================
    
    // --- IMEM SIGNALS ---
    logic [31:0] imem_addr;
    logic        imem_req_valid; // Core -> Mem
    logic        imem_req_ready; // Mem -> Core (Chấp nhận địa chỉ)
    logic [31:0] imem_rdata;
    logic        imem_resp_valid;// Mem -> Core (Có dữ liệu trả về)
    logic        imem_resp_ready;// Core -> Mem (Sẵn sàng nhận dữ liệu)

    // --- DMEM SIGNALS ---
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic        dmem_we;
    logic [3:0]  dmem_be;
    logic        dmem_req_valid;
    logic        dmem_req_ready;
    logic [31:0] dmem_rdata;
    logic        dmem_resp_valid;
    logic        dmem_resp_ready;

    assign debug_pc_o = imem_addr;

    // =========================================================================
    // 2. INSTANTIATE RISC-V CORE
    // =========================================================================
    riscv_core u_core (
        .clk_i          (clk_i),
        .rst_i          (rst_i),

        // --- Instruction Memory Interface ---
        .imem_addr_o    (imem_addr),
        .imem_valid_o   (imem_req_valid), // Core yêu cầu lấy lệnh
        .imem_ready_i   (imem_req_ready), // Memory bảo "Ok, đưa địa chỉ đây"
        
        .imem_instr_i   (imem_rdata),     // Lệnh trả về từ Memory
        .imem_valid_i   (imem_resp_valid),// Memory bảo "Có hàng rồi nè"
        .imem_ready_o   (imem_resp_ready),// Core bảo "Ok, đang chờ hàng"

        // --- Data Memory Interface ---
        .dmem_addr_o    (dmem_addr),
        .dmem_wdata_o   (dmem_wdata),
        .dmem_be_o      (dmem_be),
        .dmem_we_o      (dmem_we),
        .dmem_valid_o   (dmem_req_valid),
        .dmem_ready_i   (dmem_req_ready),

        .dmem_rdata_i   (dmem_rdata),
        .dmem_valid_i   (dmem_resp_valid),
        .dmem_ready_o   (dmem_resp_ready)
    );

    // =========================================================================
    // 3. INSTANTIATE IMEM (Instruction Memory)
    // =========================================================================
    imem #(
        .HEX_FILE ("new_code.hex") // File chứa mã máy
    ) u_imem (
        .clk_i    (clk_i),
        .rst_i    (rst_i),
        
        // Handshake
        .valid_i  (imem_req_valid),  // Input request từ Core
        .ready_o  (imem_req_ready),  // Output ready báo về Core
        
        .valid_o  (imem_resp_valid), // Output valid trả dữ liệu về Core
        .ready_i  (imem_resp_ready), // Input ready từ Core (Core có rảnh nhận không?)

        // Native
        .addr_i   (imem_addr),
        .instr_o  (imem_rdata)
    );

    // =========================================================================
    // 4. INSTANTIATE DMEM (Data Memory)
    // =========================================================================
    dmem #(
        // Không load file hex, để trống ban đầu
    ) u_dmem (
        .clk_i    (clk_i),
        .rst_i    (rst_i),

        // Handshake
        .valid_i  (dmem_req_valid),
        .ready_o  (dmem_req_ready),

        .valid_o  (dmem_resp_valid),
        .ready_i  (dmem_resp_ready),

        // Native
        .we_i     (dmem_we),
        .be_i     (dmem_be),
        .addr_i   (dmem_addr),
        .wdata_i  (dmem_wdata),
        .rdata_o  (dmem_rdata)
    );

endmodule