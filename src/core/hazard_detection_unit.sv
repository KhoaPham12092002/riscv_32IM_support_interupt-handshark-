`timescale 1ns/1ps
import riscv_32im_pkg::*;

module hazard_detection_unit (
    // Kiểm tra lệnh ở tầng EX có phải là lệnh LOAD không
    input  logic [2:0] id_ex_wb_sel, 
    input  logic [4:0] id_ex_rd,

    // Kiểm tra địa chỉ RS của lệnh đang ở tầng DECODE
    input  logic [4:0] if_id_rs1,
    input  logic [4:0] if_id_rs2,

    // Output điều khiển
    output logic       pc_stall_o,
    output logic       if_id_stall_o,
    output logic       id_ex_flush_o
);

    always_comb begin
        // Mặc định: Không stall, không flush
        pc_stall_o    = 1'b0;
        if_id_stall_o = 1'b0;
        id_ex_flush_o = 1'b0;

        // ĐIỀU KIỆN LOAD-USE HAZARD:
        // 1. Lệnh ở tầng EX đang đọc Memory (WB_MEM)
        // 2. VÀ Thanh ghi đích (RD) của lệnh Load trùng với RS1 hoặc RS2 của lệnh đang Decode
        if ((id_ex_wb_sel == WB_MEM) && (id_ex_rd != 5'd0) && 
           ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2))) begin
            
            pc_stall_o    = 1'b1; // Dừng PC
            if_id_stall_o = 1'b1; // Giữ nguyên lệnh cũ trong IF/ID
            id_ex_flush_o = 1'b1; // Chèn NOP vào tầng EX (tạo bong bóng - bubble)
        end
    end
     
endmodule
