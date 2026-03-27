`timescale 1ns/1ps
import riscv_32im_pkg::*;

module hazard_unit (
    // =======================================================================
    // 1. DÂY BÁO CÁO TỪ DATAPATH (Inputs)
    // =======================================================================
    // --- Tầng ID (Lệnh đang giải mã) ---
    input  logic [4:0]  hz_id_rs1_addr_i,
    input  logic [4:0]  hz_id_rs2_addr_i,
    
    // --- Tầng EX (Lệnh đang thực thi) ---
    input  logic [4:0]  hz_ex_rd_addr_i,
    input  logic        hz_ex_reg_we_i,   
    input  wb_sel_e     hz_ex_wb_sel_i,   
    
    // --- Báo cáo Lỗi Điều hướng (Control Status) ---
    input  logic        jump_trap_i,      // 1 = Có lệnh JUMP / BRANCH / TRAP / MRET

    // =======================================================================
    // 2. LỆNH ĐIỀU KHIỂN BẮN XUỐNG DATAPATH (Outputs)
    // =======================================================================
    // (Đã gộp chung stall_if và stall_id thành 1 lệnh ép kẹt duy nhất nhờ Handshake)
    output logic        ctrl_force_stall_id_o, // Bóp cổ Ready ở ID -> IF sẽ tự kẹt theo
    output logic        ctrl_flush_if_id_o,    // Xóa lệnh rác ở thanh ghi IF/ID
    output logic        ctrl_flush_id_ex_o     // Xóa lệnh rác ở thanh ghi ID/EX
);

    logic is_load_use;

    always_comb begin
        // -------------------------------------------------------------------
        // [A] BẮT BỆNH LOAD-USE HAZARD
        // -------------------------------------------------------------------
        is_load_use = 1'b0;
        if ((hz_ex_wb_sel_i == WB_MEM) && (hz_ex_rd_addr_i != 5'd0) && hz_ex_reg_we_i) begin
            if ((hz_ex_rd_addr_i == hz_id_rs1_addr_i) || (hz_ex_rd_addr_i == hz_id_rs2_addr_i)) begin
                is_load_use = 1'b1;
            end
        end

        // -------------------------------------------------------------------
        // [B] BỘ MÃ HÓA ƯU TIÊN (Priority Encoder)
        // -------------------------------------------------------------------
        // Mặc định: Không can thiệp, để Handshake tự làm việc của nó
        ctrl_force_stall_id_o = 1'b0;
        ctrl_flush_if_id_o    = 1'b0;
        ctrl_flush_id_ex_o    = 1'b0;

        // ƯU TIÊN 1: CONTROL HAZARD (Nhảy / Ngắt đi sai đường)
        // Hành động: Xóa sạch các lệnh đang nối đuôi nhau đi sai đường. 
        if (jump_trap_i) begin
            ctrl_flush_if_id_o = 1'b1;
            ctrl_flush_id_ex_o = 1'b1;
        end 
        
        // ƯU TIÊN 2: DATA HAZARD (Load-Use)
        // Hành động: Phát lệnh "bóp cổ" Handshake ở tầng ID. Chèn NOP vào tầng EX.
        else if (is_load_use) begin
            ctrl_force_stall_id_o = 1'b1;
            ctrl_flush_id_ex_o    = 1'b1; 
        end 
    end
     
endmodule

