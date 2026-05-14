`timescale 1ns/1ps

// =============================================================================
// Module: wrapper
// Description: Top-level FPGA wrapper cho DE10-Standard board.
//              Mapping trực tiếp theo QSF pin assignment.
// =============================================================================
module wrapper (
    input  logic       CLOCK_50,        // 50 MHz system clock (Mặc định cần có)

    // Push-buttons (active-low)
    input  logic [3:0] KEY,

    // Slide switches
    input  logic [9:0] SW,

    // Red LEDs
    output logic [9:0] LEDR,

    // 7-segment displays (common-anode, active-low)
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5,

    // UART TO USB (HPS)
    input  logic       HPS_UART_RX,     // UART RX (từ PC)
    output logic       HPS_UART_TX,     // UART TX (tới PC)
    output logic       HPS_CONV_USB_N,  // Enable USB-UART converter (Active-low)

    // 128x64 DOTS LCD (HPS - SPI Interface)
    output logic       HPS_LCM_D_C,
    output logic       HPS_LCM_RST_N,
    output logic       HPS_LCM_SPIM_CLK,
    output logic       HPS_LCM_SPIM_MOSI,
    output logic       HPS_LCM_SPIM_SS
);

    // =========================================================================
    // Reset và Cấu hình ngoại vi
    // =========================================================================
    
    // KEY[0] là active-low → chuyển thành active-high reset cho SoC
    logic rst;
    assign rst = ~KEY[0];

    // Kích hoạt IC chuyển đổi UART-USB trên board DE10-Standard (Active Low)
    assign HPS_CONV_USB_N = 1'b0;

    // =========================================================================
    // Xử lý xung đột chuẩn giao tiếp LCD
    // SoC dùng chuẩn Parallel (HD44780) - Board dùng chuẩn SPI
    // =========================================================================
    
    // Gán mức logic an toàn cho các chân SPI của màn hình trên board
    assign HPS_LCM_D_C       = 1'b0;
    assign HPS_LCM_RST_N     = 1'b1; // Reset active-low, kéo lên 1 để nhả reset
    assign HPS_LCM_SPIM_CLK  = 1'b0;
    assign HPS_LCM_SPIM_MOSI = 1'b0;
    assign HPS_LCM_SPIM_SS   = 1'b1; // Chip select active-low, kéo lên 1 để vô hiệu hóa

    // Tạo các dây tín hiệu ảo để hứng output từ soc_top_io tránh warning
    logic [7:0] lcd_data_dummy;
    logic       lcd_en_dummy;
    logic       lcd_rs_dummy;
    logic       lcd_rw_dummy;
    logic       lcd_on_dummy;

    // =========================================================================
    // Khởi tạo SoC
    // =========================================================================
    soc_top_io #(
        .IMEM_HEX  ("../src/memory/programV2_io.hex"),
        .IMEM_SZ   (4096),
        .DMEM_SZ   (4096),
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (115200)
    ) u_soc (
        .clk_i      (CLOCK_50),
        .rst_i      (rst),

        .sw_i       (SW),
        .led_o      (LEDR),

        // Map UART theo QSF mới
        .uart_rx_i  (HPS_UART_RX),
        .uart_tx_o  (HPS_UART_TX),

        // Đấu vào các dây dummy (Do không tương thích chuẩn Parallel <-> SPI)
        .lcd_data_o (lcd_data_dummy),
        .lcd_en_o   (lcd_en_dummy),
        .lcd_rs_o   (lcd_rs_dummy),
        .lcd_rw_o   (lcd_rw_dummy),
        .lcd_on_o   (lcd_on_dummy),

        .hex0_o     (HEX0),
        .hex1_o     (HEX1),
        .hex2_o     (HEX2),
        .hex3_o     (HEX3),
        .hex4_o     (HEX4),
        .hex5_o     (HEX5)
    );

endmodule