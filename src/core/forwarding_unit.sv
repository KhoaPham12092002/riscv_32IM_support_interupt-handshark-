`timescale 1ns/1ps
import riscv_32im_pkg::*;

module forwarding_unit (
    // =======================================================================
    // 1. NGƯỜI CẦN CỨU TRỢ (Tầng EX)
    // =======================================================================
    input  logic [4:0]  hz_ex_rs1_addr_i,
    input  logic [4:0]  hz_ex_rs2_addr_i,

    // =======================================================================
    // 2. NGUỒN CỨU TRỢ 1 (Tầng MEM - Trễ 1 nhịp)
    // =======================================================================
    input  logic [4:0]  hz_mem_rd_addr_i,
    input  logic        hz_mem_reg_we_i,

    // =======================================================================
    // 3. NGUỒN CỨU TRỢ 2 (Tầng WB - Trễ 2 nhịp)
    // =======================================================================
    input  logic [4:0]  hz_wb_rd_addr_i,
    input  logic        hz_wb_reg_we_i,

    // =======================================================================
    // 4. LỆNH BẺ GHI (Outputs)
    // =======================================================================
    output logic [1:0]  ctrl_fwd_rs1_sel_o,
    output logic [1:0]  ctrl_fwd_rs2_sel_o
);

    always_comb begin
        // Mặc định: Không Forward, dùng giá trị gốc đọc từ Register File (00)
        ctrl_fwd_rs1_sel_o = 2'b00;
        ctrl_fwd_rs2_sel_o = 2'b00;

        // -------------------------------------------------------------------
        // FORWARD CHO RS1
        // -------------------------------------------------------------------
        // Ưu tiên 1: Lấy từ MEM (Kết quả vừa tính xong nóng hổi nhất)
        if (hz_mem_reg_we_i && (hz_mem_rd_addr_i != 5'd0) && (hz_mem_rd_addr_i == hz_ex_rs1_addr_i)) begin
            ctrl_fwd_rs1_sel_o = 2'b01; 
        end
        // Ưu tiên 2: Lấy từ WB (Kết quả cũ hơn 1 nhịp, chuẩn bị ghi vào túi)
        else if (hz_wb_reg_we_i && (hz_wb_rd_addr_i != 5'd0) && (hz_wb_rd_addr_i == hz_ex_rs1_addr_i)) begin
            ctrl_fwd_rs1_sel_o = 2'b10;
        end

        // -------------------------------------------------------------------
        // FORWARD CHO RS2
        // -------------------------------------------------------------------
        if (hz_mem_reg_we_i && (hz_mem_rd_addr_i != 5'd0) && (hz_mem_rd_addr_i == hz_ex_rs2_addr_i)) begin
            ctrl_fwd_rs2_sel_o = 2'b01;
        end
        else if (hz_wb_reg_we_i && (hz_wb_rd_addr_i != 5'd0) && (hz_wb_rd_addr_i == hz_ex_rs2_addr_i)) begin
            ctrl_fwd_rs2_sel_o = 2'b10;
        end
    end

endmodule