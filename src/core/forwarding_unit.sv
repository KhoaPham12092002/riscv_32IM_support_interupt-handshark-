`timescale 1ns/1ps

module forwarding_unit (
    // --- Inputs từ tầng Execute (Lệnh hiện tại đang cần data) ---
    input  logic [4:0] rs1_addr_ex,
    input  logic [4:0] rs2_addr_ex,

    // --- Inputs từ tầng Memory (Lệnh trước đó 1 chu kỳ - EX/MEM) ---
    input  logic [4:0] rd_addr_mem,
    input  logic       rf_we_mem,

    // --- Inputs từ tầng Writeback (Lệnh trước đó 2 chu kỳ - MEM/WB) ---
    input  logic [4:0] rd_addr_wb,
    input  logic       rf_we_wb,

    // --- Outputs điều khiển Mux chọn dữ liệu cho ALU ---
    // 00: Lấy từ Register File (No Forwarding)
    // 10: Forward từ tầng MEM (Ưu tiên cao nhất - EX Hazard)
    // 01: Forward từ tầng WB (Ưu tiên thấp hơn - MEM Hazard)
    output logic [1:0] forward_a_o,
    output logic [1:0] forward_b_o
);

    // =========================================================================
    // FORWARDING LOGIC CHO SOURCE 1 (RS1)
    // =========================================================================
    always_comb begin
        // Trường hợp 1: EX Hazard (Lệnh liền trước ghi vào RS1)
        if (rf_we_mem && (rd_addr_mem != 5'd0) && (rd_addr_mem == rs1_addr_ex)) begin
            forward_a_o = 2'b10;
        end
        // Trường hợp 2: MEM Hazard (Lệnh cách 1 nhịp ghi vào RS1)
        // Lưu ý: Chỉ forward nếu KHÔNG bị EX Hazard che khuất (Priority logic)
        else if (rf_we_wb && (rd_addr_wb != 5'd0) && (rd_addr_wb == rs1_addr_ex)) begin
            forward_a_o = 2'b01;
        end
        // Trường hợp 3: Không có Hazard
        else begin
            forward_a_o = 2'b00;
        end
    end

    // =========================================================================
    // FORWARDING LOGIC CHO SOURCE 2 (RS2)
    // =========================================================================
    always_comb begin
        // Trường hợp 1: EX Hazard (Lệnh liền trước ghi vào RS2)
        if (rf_we_mem && (rd_addr_mem != 5'd0) && (rd_addr_mem == rs2_addr_ex)) begin
            forward_b_o = 2'b10;
        end
        // Trường hợp 2: MEM Hazard (Lệnh cách 1 nhịp ghi vào RS2)
        else if (rf_we_wb && (rd_addr_wb != 5'd0) && (rd_addr_wb == rs2_addr_ex)) begin
            forward_b_o = 2'b01;
        end
        // Trường hợp 3: Không có Hazard
        else begin
            forward_b_o = 2'b00;
        end
    end

endmodule
