`timescale 1ns/1ps
import riscv_32im_pkg::*;

module riscv_control (
    // =======================================================================
    // 1. DÂY BÁO CÁO TỪ DATAPATH BẮN LÊN (Inputs)
    // =======================================================================
    // --- Tầng ID ---
    input  logic [4:0]  hz_id_rs1_addr_i,
    input  logic [4:0]  hz_id_rs2_addr_i,
    input  logic        id_is_ecall_i,        // Lệnh gọi hệ thống
    input  logic        id_is_mret_i,         // Lệnh quay về từ ngắt
    input  logic        id_illegal_instr_i,   // Lệnh rác/không hợp lệ
    
    // --- Tầng EX ---
    input  logic [4:0]  hz_ex_rs1_addr_i,
    input  logic [4:0]  hz_ex_rs2_addr_i,
    input  logic [4:0]  hz_ex_rd_addr_i,
    input  logic        hz_ex_reg_we_i,   
    input  wb_sel_e     hz_ex_wb_sel_i,   
    input  logic        branch_taken_i,       // Lệnh nhảy (JAL/Branch) thực thi thành công
    
    // --- Tầng MEM ---
    input  logic [4:0]  hz_mem_rd_addr_i,
    input  logic        hz_mem_reg_we_i,
    input  logic        lsu_err_i,            // Lỗi truy cập RAM
    
    // --- Tầng WB ---
    input  logic [4:0]  hz_wb_rd_addr_i,
    input  logic        hz_wb_reg_we_i,

    // =======================================================================
    // 2. LỆNH ĐIỀU KHIỂN BẮN XUỐNG DATAPATH & PC (Outputs)
    // =======================================================================
    // --- Can thiệp Pipeline (Handshake Override) ---
    output logic        ctrl_force_stall_id_o, 
    output logic        ctrl_flush_if_id_o,    
    output logic        ctrl_flush_id_ex_o,    
    
    // --- Bẻ ghi Dữ liệu (Forwarding) ---
    output logic [1:0]  ctrl_fwd_rs1_sel_o,
    output logic [1:0]  ctrl_fwd_rs2_sel_o,

    // --- Điều khiển PC ---
    output logic [1:0]  ctrl_pc_sel_o,         // 00: PC+4 | 01: Branch | 10: Trap | 11: MRET

    // =======================================================================
    // 3. GIAO TIẾP VỚI KHỐI CSR (Exception/Trap Interface)
    // =======================================================================
    output logic        ctrl_trap_valid_o,     // Cắm vào trap_valid_i của CSR
    output logic [3:0]  ctrl_trap_cause_o,     // Cắm vào trap_cause_i của CSR
    output logic        ctrl_mret_valid_o      // Cắm vào mret_i của CSR
);

    // -----------------------------------------------------------------------
    // A. TỔNG HỢP LOGIC NGẮT & ĐIỀU HƯỚNG (Control Hazard Logic)
    // -----------------------------------------------------------------------
    logic is_trap;
    logic jump_trap_comb;

    always_comb begin
        // 1. Nhận diện có ngắt/lỗi xảy ra không
        is_trap = id_is_ecall_i | id_illegal_instr_i | lsu_err_i;
        
        // 2. Tín hiệu tổng hợp báo cho Hazard Unit biết PC đang đi sai đường
        jump_trap_comb = is_trap | id_is_mret_i | branch_taken_i;

        // 3. Đóng gói gửi sang CSR
        ctrl_trap_valid_o = is_trap;
        ctrl_mret_valid_o = id_is_mret_i;

        // Mã lỗi đơn giản (Chuẩn RISC-V Privileged)
        if (id_is_ecall_i)           ctrl_trap_cause_o = 4'd11; // Environment call from M-mode
        else if (id_illegal_instr_i) ctrl_trap_cause_o = 4'd2;  // Illegal instruction
        else if (lsu_err_i)          ctrl_trap_cause_o = 4'd5;  // Load access fault (Mặc định)
        else                         ctrl_trap_cause_o = 4'd0;

        // 4. Lái vô lăng bộ PC Gen
        if (is_trap)                 ctrl_pc_sel_o = 2'b10; // Nhảy vào mtvec
        else if (id_is_mret_i)       ctrl_pc_sel_o = 2'b11; // Quay về mepc
        else if (branch_taken_i)     ctrl_pc_sel_o = 2'b01; // Nhảy theo ALU
        else                         ctrl_pc_sel_o = 2'b00; // Tăng tuần tự PC + 4
    end

    // -----------------------------------------------------------------------
    // B. INSTANTIATE BỘ PHANH KHẨN CẤP (Hazard Unit)
    // -----------------------------------------------------------------------
    hazard_unit u_hazard (
        .hz_id_rs1_addr_i      (hz_id_rs1_addr_i),
        .hz_id_rs2_addr_i      (hz_id_rs2_addr_i),
        .hz_ex_rd_addr_i       (hz_ex_rd_addr_i),
        .hz_ex_reg_we_i        (hz_ex_reg_we_i),
        .hz_ex_wb_sel_i        (hz_ex_wb_sel_i),
        
        .jump_trap_i           (jump_trap_comb), // Bơm tín hiệu dọn rác tổng hợp vào
        
        .ctrl_force_stall_id_o (ctrl_force_stall_id_o),
        .ctrl_flush_if_id_o    (ctrl_flush_if_id_o),
        .ctrl_flush_id_ex_o    (ctrl_flush_id_ex_o)
    );

    // -----------------------------------------------------------------------
    // C. INSTANTIATE BỘ BẺ GHI DỮ LIỆU (Forwarding Unit)
    // -----------------------------------------------------------------------
    forwarding_unit u_forwarding (
        .hz_ex_rs1_addr_i   (hz_ex_rs1_addr_i),
        .hz_ex_rs2_addr_i   (hz_ex_rs2_addr_i),
        .hz_mem_rd_addr_i   (hz_mem_rd_addr_i),
        .hz_mem_reg_we_i    (hz_mem_reg_we_i),
        .hz_wb_rd_addr_i    (hz_wb_rd_addr_i),
        .hz_wb_reg_we_i     (hz_wb_reg_we_i),
        
        .ctrl_fwd_rs1_sel_o (ctrl_fwd_rs1_sel_o),
        .ctrl_fwd_rs2_sel_o (ctrl_fwd_rs2_sel_o)
    );

endmodule