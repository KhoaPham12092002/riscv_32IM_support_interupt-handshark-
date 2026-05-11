`timescale 1ns/1ps
import riscv_32im_pkg::*;
import riscv_instr::*;

module riscv_core (
    input  logic        clk_i,
    input  logic        rst_i,
    // IMEM
    output logic [31:0] imem_addr_o,
    output logic        imem_valid_o,
    input  logic        imem_ready_i,
    input  logic [31:0] imem_instr_i,
    input  logic        imem_valid_i,
    output logic        imem_ready_o,
    // DMEM
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_be_o,
    output logic        dmem_we_o,
    output logic        dmem_valid_o,
    input  logic        dmem_ready_i,
    input  logic [31:0] dmem_rdata_i,
    input  logic        dmem_valid_i,
    output logic        dmem_ready_o,
    // Debug outputs for TB monitoring (avoids hierarchical refs that Questa vopt makes X)
    output logic        dbg_wb_we_o,
    output logic [4:0]  dbg_wb_rd_o
);

    // --- Datapath → Control ---
    logic [4:0]  hz_id_rs1_addr, hz_id_rs2_addr;
    logic        id_is_ecall, id_is_mret, id_illegal_instr;
    logic [4:0]  hz_ex_rs1_addr, hz_ex_rs2_addr, hz_ex_rd_addr;
    logic        hz_ex_reg_we;
    wb_sel_e     hz_ex_wb_sel;
    logic        branch_taken;
    logic [4:0]  hz_mem_rd_addr;
    logic        hz_mem_reg_we;
    logic [4:0]  hz_wb_rd_addr;
    logic        hz_wb_reg_we;
    logic        lsu_err;     // LSU misaligned trap: datapath → control
    logic [31:0] trap_pc, trap_val;

    // --- Control → Datapath ---
    logic        ctrl_force_stall_id;
    logic        ctrl_flush_if_id;
    logic        ctrl_flush_id_ex;
    logic [1:0]  ctrl_fwd_rs1_sel;
    logic [1:0]  ctrl_fwd_rs2_sel;
    logic [1:0]  ctrl_pc_sel;

    // --- Datapath/Control ↔ CSR ---
    csr_req_t    csr_req;
    logic        trap_valid;
    logic [3:0]  trap_cause;
    logic        mret_valid;
    logic        csr_ready;
    logic [31:0] csr_rdata;
    logic [31:0] csr_epc;
    logic [31:0] csr_trap_vector;

    riscv_datapath u_datapath (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .if_req_valid_o       (imem_valid_o),
        .if_req_addr_o        (imem_addr_o),
        .if_req_ready_i       (imem_ready_i),
        .if_rsp_valid_i       (imem_valid_i),
        .if_rsp_instr_i       (imem_instr_i),
        .if_rsp_ready_o       (imem_ready_o),
        .dmem_req_valid_o     (dmem_valid_o),
        .dmem_req_ready_i     (dmem_ready_i),
        .dmem_addr_o          (dmem_addr_o),
        .dmem_wdata_o         (dmem_wdata_o),
        .dmem_be_o            (dmem_be_o),
        .dmem_we_o            (dmem_we_o),
        .dmem_rsp_valid_i     (dmem_valid_i),
        .dmem_rsp_ready_o     (dmem_ready_o),
        .dmem_rdata_i         (dmem_rdata_i),
        .dmem_err_i           (lsu_err),   // dùng lsu_err nội bộ làm dmem_err
        .hz_id_rs1_addr_o     (hz_id_rs1_addr),
        .hz_id_rs2_addr_o     (hz_id_rs2_addr),
        .id_is_ecall_o        (id_is_ecall),
        .id_is_mret_o         (id_is_mret),
        .id_illegal_instr_o   (id_illegal_instr),
        .hz_ex_rs1_addr_o     (hz_ex_rs1_addr),
        .hz_ex_rs2_addr_o     (hz_ex_rs2_addr),
        .hz_ex_rd_addr_o      (hz_ex_rd_addr),
        .hz_ex_reg_we_o       (hz_ex_reg_we),
        .hz_ex_wb_sel_o       (hz_ex_wb_sel),
        .branch_taken_o       (branch_taken),
        .hz_mem_rd_addr_o     (hz_mem_rd_addr),
        .hz_mem_reg_we_o      (hz_mem_reg_we),
        .hz_wb_rd_addr_o      (hz_wb_rd_addr),
        .hz_wb_reg_we_o       (hz_wb_reg_we),
        .lsu_err_o            (lsu_err),
        .ctrl_force_stall_id_i(ctrl_force_stall_id),
        .ctrl_flush_if_id_i   (ctrl_flush_if_id),
        .ctrl_flush_id_ex_i   (ctrl_flush_id_ex),
        .ctrl_fwd_rs1_sel_i   (ctrl_fwd_rs1_sel),
        .ctrl_fwd_rs2_sel_i   (ctrl_fwd_rs2_sel),
        .ctrl_pc_sel_i        (ctrl_pc_sel),
        .csr_req_o            (csr_req),
        .csr_ready_i          (csr_ready),
        .csr_rdata_i          (csr_rdata),
        .trap_pc_o            (trap_pc),
        .trap_val_o           (trap_val),
        .csr_epc_i            (csr_epc),
        .csr_trap_vector_i    (csr_trap_vector)
    );

    riscv_control u_control (
        .hz_id_rs1_addr_i     (hz_id_rs1_addr),
        .hz_id_rs2_addr_i     (hz_id_rs2_addr),
        .id_is_ecall_i        (id_is_ecall),
        .id_is_mret_i         (id_is_mret),
        .id_illegal_instr_i   (id_illegal_instr),
        .hz_ex_rs1_addr_i     (hz_ex_rs1_addr),
        .hz_ex_rs2_addr_i     (hz_ex_rs2_addr),
        .hz_ex_rd_addr_i      (hz_ex_rd_addr),
        .hz_ex_reg_we_i       (hz_ex_reg_we),
        .hz_ex_wb_sel_i       (hz_ex_wb_sel),
        .branch_taken_i       (branch_taken),
        .hz_mem_rd_addr_i     (hz_mem_rd_addr),
        .hz_mem_reg_we_i      (hz_mem_reg_we),
        .lsu_err_i            (lsu_err),
        .hz_wb_rd_addr_i      (hz_wb_rd_addr),
        .hz_wb_reg_we_i       (hz_wb_reg_we),
        .ctrl_force_stall_id_o(ctrl_force_stall_id),
        .ctrl_flush_if_id_o   (ctrl_flush_if_id),
        .ctrl_flush_id_ex_o   (ctrl_flush_id_ex),
        .ctrl_fwd_rs1_sel_o   (ctrl_fwd_rs1_sel),
        .ctrl_fwd_rs2_sel_o   (ctrl_fwd_rs2_sel),
        .ctrl_pc_sel_o        (ctrl_pc_sel),
        .ctrl_trap_valid_o    (trap_valid),
        .ctrl_trap_cause_o    (trap_cause),
        .ctrl_mret_valid_o    (mret_valid)
    );

    csr u_csr (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .csr_req_i       (csr_req),
        .csr_ready_o     (csr_ready),
        .csr_rdata_o     (csr_rdata),
        .csr_rsp_valid_o (),
        .trap_valid_i    (trap_valid),
        .trap_cause_i    (trap_cause),
        .trap_pc_i       (trap_pc),
        .trap_val_i      (trap_val),
        .mret_i          (mret_valid),
        .epc_o           (csr_epc),
        .trap_vector_o   (csr_trap_vector),
        .irq_sw_i        (1'b0),
        .irq_timer_i     (1'b0),
        .irq_ext_i       (1'b0)
    );

    assign dbg_wb_we_o = hz_wb_reg_we;
    assign dbg_wb_rd_o = hz_wb_rd_addr;

endmodule
