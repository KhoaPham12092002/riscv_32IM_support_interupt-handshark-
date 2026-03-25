`timescale 1ns/1ps
import riscv_32im_pkg::*;

module mem #(
    parameter string IMEM_HEX = "program.hex",
    parameter int    IMEM_SZ  = riscv_32im_pkg::IMEM_SIZE_BYTES,
    parameter int    DMEM_SZ  = riscv_32im_pkg::DMEM_SIZE_BYTES
) (
    input  logic        clk_i,
    input  logic        rst_i,

    // ==============================================================
    // VÒI 1: GIAO TIẾP CORE <-> IMEM (Instruction Fetch)
    // ==============================================================
    input   logic        if_req_valid_i, 
    input   logic [31:0] if_req_addr_i,  
    output  logic        if_req_ready_o, 
    
    output  logic        if_rsp_valid_o,   
    input   logic        if_rsp_ready_i,   
    output  logic [31:0] if_rsp_instr_o,

    // ==============================================================
    // VÒI 2: GIAO TIẾP CORE <-> LSU (Data Load/Store)
    // ==============================================================
    input  logic [31:0] lsu_addr_i,
    input  logic [31:0] lsu_wdata_i,
    input  logic        lsu_we_i,    
    input  logic [2:0]  lsu_funct3_i,    
    
    input  logic        lsu_req_valid_i,
    output logic        lsu_req_ready_o,
    output logic        lsu_rsp_valid_o,
    input  logic        lsu_rsp_ready_i,
    
    output logic [31:0] lsu_rdata_o,
    output logic        lsu_err_o   
);

    // ==============================================================
    // CÁP NỘI BỘ: Nối giữa LSU (Master) và DMEM (Slave)
    // ==============================================================
    // 1. Kênh Request
    logic        int_dmem_req_valid;
    logic        int_dmem_req_ready;
    logic [31:0] int_dmem_req_addr;
    logic [31:0] int_dmem_req_wdata;
    logic [3:0]  int_dmem_req_be;
    logic        int_dmem_req_we;

    // 2. Kênh Response
    logic        int_dmem_rsp_valid;
    logic        int_dmem_rsp_ready;
    logic [31:0] int_dmem_rsp_rdata;


    // ==============================================================
    // INSTANTIATION: Khởi tạo các khối con
    // ==============================================================

    // 1. INSTRUCTION MEMORY (Độc lập, chỉ phục vụ lấy lệnh)
    imem #(
        .HEX_FILE (IMEM_HEX),
        .MEM_SIZE (IMEM_SZ)
    ) u_imem (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .req_valid_i (if_req_valid_i),
        .req_addr_i  (if_req_addr_i),
        .req_ready_o (if_req_ready_o),
        .rsp_valid_o (if_rsp_valid_o),
        .rsp_ready_i (if_rsp_ready_i),
        .rsp_instr_o (if_rsp_instr_o)
    );

    // 2. LOAD/STORE UNIT (Trung gian giải mã địa chỉ, data type)
    lsu u_lsu (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        
        // Nối ra ngoài Core
        .addr_i           (lsu_addr_i),
        .wdata_i          (lsu_wdata_i),
        .lsu_we_i         (lsu_we_i),
        .funct3_i         (lsu_funct3_i),
        .valid_i          (lsu_req_valid_i),
        .ready_o          (lsu_req_ready_o),
        .valid_o          (lsu_rsp_valid_o),
        .ready_i          (lsu_rsp_ready_i),
        .lsu_rdata_o      (lsu_rdata_o),
        .lsu_err_o        (lsu_err_o),

        // Nối cáp nội bộ sang DMEM
        .dmem_req_valid_o (int_dmem_req_valid),
        .dmem_req_ready_i (int_dmem_req_ready),
        .dmem_addr_o      (int_dmem_req_addr),
        .dmem_wdata_o     (int_dmem_req_wdata),
        .dmem_be_o        (int_dmem_req_be),
        .dmem_we_o        (int_dmem_req_we),
        .dmem_rsp_valid_i (int_dmem_rsp_valid),
        .dmem_rsp_ready_o (int_dmem_rsp_ready),
        .dmem_rdata_i     (int_dmem_rsp_rdata)
    );

    // 3. DATA MEMORY (Nơi chứa dữ liệu thực sự)
    dmem #(
        .MEM_SIZE (DMEM_SZ)
    ) u_dmem (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        
        // Nhận cáp nội bộ từ LSU
        .req_valid_i  (int_dmem_req_valid),
        .req_ready_o  (int_dmem_req_ready),
        .req_addr_i   (int_dmem_req_addr),
        .req_wdata_i  (int_dmem_req_wdata),
        .req_be_i     (int_dmem_req_be),
        .req_we_i     (int_dmem_req_we),
        .rsp_valid_o  (int_dmem_rsp_valid),
        .rsp_ready_i  (int_dmem_rsp_ready),
        .rsp_rdata_o  (int_dmem_rsp_rdata)
    );

endmodule