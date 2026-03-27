`timescale 1ns/1ps
import riscv_32im_pkg::*;
import riscv_instr::*;

module soc_top #(
    parameter string IMEM_HEX = "program.hex",
    parameter int    IMEM_SZ  = riscv_32im_pkg::IMEM_SIZE_BYTES,
    parameter int    DMEM_SZ  = riscv_32im_pkg::DMEM_SIZE_BYTES
)(
    input  logic clk_i,
    input  logic rst_i,
    
    // Interrupt Interfaces (Từ ngoại vi cấp vào)
    input  logic irq_sw_i,    // Software Interrupt
    input  logic irq_timer_i, // Timer Interrupt
    input  logic irq_ext_i    // External Interrupt
);

    // =======================================================================
    // 1. KHAI BÁO CÁP KẾT NỐI NỘI BỘ (INTERNAL WIRES)
    // =======================================================================

    // --- Cáp Memory (IF & LSU) ---
    logic        if_req_valid, if_req_ready, if_rsp_valid, if_rsp_ready;
    logic [31:0] if_req_addr, if_rsp_instr;
    
    logic        lsu_req_valid, lsu_req_ready, lsu_rsp_valid, lsu_rsp_ready, lsu_we, lsu_err;
    logic [31:0] lsu_addr, lsu_wdata, lsu_rdata;
    logic [2:0]  lsu_funct3;

    // --- Cáp Báo Cáo Datapath -> Control ---
    logic [4:0]  hz_id_rs1_addr, hz_id_rs2_addr;
    logic        id_is_ecall, id_is_mret, id_illegal_instr;
    
    logic [4:0]  hz_ex_rs1_addr, hz_ex_rs2_addr, hz_ex_rd_addr;
    logic        hz_ex_reg_we;
    wb_sel_e     hz_ex_wb_sel;
    logic        branch_taken;
    
    logic [4:0]  hz_mem_rd_addr; logic hz_mem_reg_we;
    logic [4:0]  hz_wb_rd_addr;  logic hz_wb_reg_we;

    // --- Cáp Lệnh Control -> Datapath ---
    logic        ctrl_force_stall_id, ctrl_flush_if_id, ctrl_flush_id_ex;
    logic [1:0]  ctrl_fwd_rs1_sel, ctrl_fwd_rs2_sel, ctrl_pc_sel;

    // --- Cáp Control -> CSR (Trap Control) ---
    logic        ctrl_trap_valid, ctrl_mret_valid;
    logic [3:0]  ctrl_trap_cause;

    // --- Cáp Datapath <-> CSR (Dữ liệu CSR) ---
    csr_req_t    csr_req;
    logic        csr_ready, csr_rsp_valid;
    logic [31:0] csr_rdata, epc_wire, trap_vector_wire, trap_pc_wire, trap_val_wire;


    // =======================================================================
    // 2. INSTANTIATE KHỐI DATAPATH (CƠ BẮP)
    // =======================================================================
    riscv_datapath u_datapath (
        .clk_i                 (clk_i),
        .rst_i                 (rst_i),
        
        // Memory
        .if_req_valid_o        (if_req_valid),      .if_req_addr_o         (if_req_addr),
        .if_req_ready_i        (if_req_ready),      .if_rsp_valid_i        (if_rsp_valid),
        .if_rsp_instr_i        (if_rsp_instr),      .if_rsp_ready_o        (if_rsp_ready),
        .lsu_addr_o            (lsu_addr),          .lsu_wdata_o           (lsu_wdata),
        .lsu_we_o              (lsu_we),            .lsu_funct3_o          (lsu_funct3),
        .lsu_req_valid_o       (lsu_req_valid),     .lsu_req_ready_i       (lsu_req_ready),
        .lsu_rsp_valid_i       (lsu_rsp_valid),     .lsu_rdata_i           (lsu_rdata),
        .lsu_rsp_ready_o       (lsu_rsp_ready),     .lsu_err_i             (lsu_err),

        // Lên Control
        .hz_id_rs1_addr_o      (hz_id_rs1_addr),    .hz_id_rs2_addr_o      (hz_id_rs2_addr),
        .id_is_ecall_o         (id_is_ecall),       .id_is_mret_o          (id_is_mret),
        .id_illegal_instr_o    (id_illegal_instr),
        .hz_ex_rs1_addr_o      (hz_ex_rs1_addr),    .hz_ex_rs2_addr_o      (hz_ex_rs2_addr),
        .hz_ex_rd_addr_o       (hz_ex_rd_addr),     .hz_ex_reg_we_o        (hz_ex_reg_we),
        .hz_ex_wb_sel_o        (hz_ex_wb_sel),      .branch_taken_o        (branch_taken),
        .hz_mem_rd_addr_o      (hz_mem_rd_addr),    .hz_mem_reg_we_o       (hz_mem_reg_we),
        .hz_wb_rd_addr_o       (hz_wb_rd_addr),     .hz_wb_reg_we_o        (hz_wb_reg_we),

        // Từ Control
        .ctrl_force_stall_id_i (ctrl_force_stall_id), 
        .ctrl_flush_if_id_i    (ctrl_flush_if_id),
        .ctrl_flush_id_ex_i    (ctrl_flush_id_ex),
        .ctrl_fwd_rs1_sel_i    (ctrl_fwd_rs1_sel),  .ctrl_fwd_rs2_sel_i    (ctrl_fwd_rs2_sel),
        .ctrl_pc_sel_i         (ctrl_pc_sel),

        // CSR
        .csr_req_o             (csr_req),           .csr_ready_i           (csr_ready),
        .csr_rdata_i           (csr_rdata),         .trap_pc_o             (trap_pc_wire),
        .trap_val_o            (trap_val_wire),     .csr_epc_i             (epc_wire),
        .csr_trap_vector_i     (trap_vector_wire)
    );

    // =======================================================================
    // 3. INSTANTIATE KHỐI CONTROL (NÃO BỘ)
    // =======================================================================
    riscv_control u_control (
        // Input từ Datapath & MEM
        .hz_id_rs1_addr_i      (hz_id_rs1_addr),    .hz_id_rs2_addr_i      (hz_id_rs2_addr),
        .id_is_ecall_i         (id_is_ecall),       .id_is_mret_i          (id_is_mret),
        .id_illegal_instr_i    (id_illegal_instr),  .hz_ex_rs1_addr_i      (hz_ex_rs1_addr),
        .hz_ex_rs2_addr_i      (hz_ex_rs2_addr),    .hz_ex_rd_addr_i       (hz_ex_rd_addr),
        .hz_ex_reg_we_i        (hz_ex_reg_we),      .hz_ex_wb_sel_i        (hz_ex_wb_sel),
        .branch_taken_i        (branch_taken),      .hz_mem_rd_addr_i      (hz_mem_rd_addr),
        .hz_mem_reg_we_i       (hz_mem_reg_we),     .lsu_err_i             (lsu_err),
        .hz_wb_rd_addr_i       (hz_wb_rd_addr),     .hz_wb_reg_we_i        (hz_wb_reg_we),

        // Lệnh xuống Datapath
        .ctrl_force_stall_id_o (ctrl_force_stall_id),
        .ctrl_flush_if_id_o    (ctrl_flush_if_id),  .ctrl_flush_id_ex_o    (ctrl_flush_id_ex),
        .ctrl_fwd_rs1_sel_o    (ctrl_fwd_rs1_sel),  .ctrl_fwd_rs2_sel_o    (ctrl_fwd_rs2_sel),
        .ctrl_pc_sel_o         (ctrl_pc_sel),

        // Tới CSR
        .ctrl_trap_valid_o     (ctrl_trap_valid),   .ctrl_trap_cause_o     (ctrl_trap_cause),
        .ctrl_mret_valid_o     (ctrl_mret_valid)
    );

    // =======================================================================
    // 4. INSTANTIATE KHỐI CSR (HỆ MIỄN DỊCH & TRẠNG THÁI)
    // =======================================================================
    csr u_csr (
        .clk_i                 (clk_i),             .rst_i                 (rst_i),
        
        // Giao tiếp với Core (EX)
        .csr_req_i             (csr_req),           .csr_ready_o           (csr_ready),
        .csr_rdata_o           (csr_rdata),         .csr_rsp_valid_o       (csr_rsp_valid),
        
        // Giao tiếp Trap từ Control & Datapath
        .trap_valid_i          (ctrl_trap_valid),   .trap_cause_i          (ctrl_trap_cause),
        .trap_pc_i             (trap_pc_wire),      .trap_val_i            (trap_val_wire),
        .mret_i                (ctrl_mret_valid),
        
        // Cấp địa chỉ cho PC Mux
        .epc_o                 (epc_wire),          .trap_vector_o         (trap_vector_wire),
        
        // Ngắt từ bên ngoài
        .irq_sw_i              (irq_sw_i),          .irq_timer_i           (irq_timer_i),
        .irq_ext_i             (irq_ext_i)
    );

    // =======================================================================
    // 5. INSTANTIATE KHỐI MEMORY (BỘ NHỚ)
    // =======================================================================
    mem #(
        .IMEM_HEX(IMEM_HEX),
        .IMEM_SZ(IMEM_SZ),
        .DMEM_SZ(DMEM_SZ)
    ) u_mem (
        .clk_i                 (clk_i),             .rst_i                 (rst_i),
        
        // IF
        .if_req_valid_i        (if_req_valid),      .if_req_addr_i         (if_req_addr),
        .if_req_ready_o        (if_req_ready),      .if_rsp_valid_o        (if_rsp_valid),
        .if_rsp_ready_i        (if_rsp_ready),      .if_rsp_instr_o        (if_rsp_instr),
        
        // LSU
        .lsu_addr_i            (lsu_addr),          .lsu_wdata_i           (lsu_wdata),
        .lsu_we_i              (lsu_we),            .lsu_funct3_i          (lsu_funct3),
        .lsu_req_valid_i       (lsu_req_valid),     .lsu_req_ready_o       (lsu_req_ready),
        .lsu_rsp_valid_o       (lsu_rsp_valid),     .lsu_rsp_ready_i       (lsu_rsp_ready),
        .lsu_rdata_o           (lsu_rdata),         .lsu_err_o             (lsu_err)
    );

endmodule