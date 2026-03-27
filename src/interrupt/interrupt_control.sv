`timescale 1ns/1ps

module interrupt_controller (
    input  logic clk_i,
    input  logic rst_i,

    // =======================================================================
    // 1. CÁC NGUỒN NGẮT ĐẦU VÀO TỪ NGOẠI VI (Nút nhấn, Timer, UART...)
    // =======================================================================
    // Software Interrupts (VD: IPC từ Core khác)
    input  logic irq_sw_a_i,   // Ưu tiên cao nhất trong SW
    input  logic irq_sw_b_i,
    input  logic irq_sw_c_i,   // Ưu tiên thấp nhất trong SW

    // Timer Interrupts (VD: Timer 0, Timer 1, Timer 2)
    input  logic irq_tmr_a_i,  // Ưu tiên cao nhất trong TMR
    input  logic irq_tmr_b_i,
    input  logic irq_tmr_c_i,

    // External Interrupts (VD: UART, SPI, GPIO)
    input  logic irq_ext_a_i,  // Ưu tiên cao nhất trong EXT
    input  logic irq_ext_b_i,
    input  logic irq_ext_c_i,

    // =======================================================================
    // 2. GIAO TIẾP VỚI KHỐI CSR (Ghim thẳng vào csr.sv)
    // =======================================================================
    output logic       irq_sw_o,      // Gắn vào irq_sw_i của CSR
    output logic       irq_timer_o,   // Gắn vào irq_timer_i của CSR
    output logic       irq_ext_o,     // Gắn vào irq_ext_i của CSR

    // =======================================================================
    // 3. BÁO CÁO ID THIẾT BỊ CHO KHỐI TRAP / CSR
    // =======================================================================
    output logic [3:0] irq_id_o       // Mã ID của thiết bị đang ngắt (Dùng để CPU biết ai đang kêu)
);

    // -----------------------------------------------------------------------
    // BƯỚC 1: GỘP TÍN HIỆU (OR GATES) - Báo cáo tổng lên CSR
    // -----------------------------------------------------------------------
    // Bất cứ thiết bị con nào kích hoạt, cờ tổng sẽ dựng lên 1
    assign irq_sw_o    = irq_sw_a_i  | irq_sw_b_i  | irq_sw_c_i;
    assign irq_timer_o = irq_tmr_a_i | irq_tmr_b_i | irq_tmr_c_i;
    assign irq_ext_o   = irq_ext_a_i | irq_ext_b_i | irq_ext_c_i;

    // -----------------------------------------------------------------------
    // BƯỚC 2: PRIORITY ENCODER (Bộ mã hóa độ ưu tiên A > B > C)
    // -----------------------------------------------------------------------
    // Theo chuẩn RISC-V, ưu tiên toàn cục thường là: EXTERNAL > SOFTWARE > TIMER
    // Mã ID tự định nghĩa (Hardware Interrupt Vector)
    
    always_comb begin
        // Mặc định không có ngắt (ID = 0)
        irq_id_o = 4'd0; 

        // 1. XÉT EXTERNAL INTERRUPT TRƯỚC (Ưu tiên cao nhất toàn hệ thống)
        if (irq_ext_o) begin
            if      (irq_ext_a_i) irq_id_o = 4'd11; // ID 11: Lỗi EXT A (VD: UART)
            else if (irq_ext_b_i) irq_id_o = 4'd12; // ID 12: Lỗi EXT B (VD: SPI)
            else if (irq_ext_c_i) irq_id_o = 4'd13; // ID 13: Lỗi EXT C (VD: GPIO)
        end
        
        // 2. XÉT SOFTWARE INTERRUPT (Ưu tiên thứ hai)
        else if (irq_sw_o) begin
            if      (irq_sw_a_i)  irq_id_o = 4'd3;  // ID 3: SW A
            else if (irq_sw_b_i)  irq_id_o = 4'd4;  // ID 4: SW B
            else if (irq_sw_c_i)  irq_id_o = 4'd5;  // ID 5: SW C
        end
        
        // 3. XÉT TIMER INTERRUPT (Ưu tiên thấp nhất)
        else if (irq_timer_o) begin
            if      (irq_tmr_a_i) irq_id_o = 4'd7;  // ID 7: TMR A
            else if (irq_tmr_b_i) irq_id_o = 4'd8;  // ID 8: TMR B
            else if (irq_tmr_c_i) irq_id_o = 4'd9;  // ID 9: TMR C
        end
    end

endmodule