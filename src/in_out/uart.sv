`timescale 1ns/1ps
// =============================================================================
// Module: uart
// Description: Memory-mapped UART controller cho RISC-V SoC
//              Dựa trên reference design verilog-uart (Alex Forencich)
//              Tích hợp thêm register-based interface cho CPU access via Store/Load
//              + Interrupt support (rx_irq_o khi có byte mới)
//
// Memory Map (offset từ UART base address 0x4000_0008):
//   0x00 - TX_DATA  (W):  Ghi byte cần truyền vào [7:0]
//   0x04 - RX_DATA  (R):  Đọc byte đã nhận [7:0], tự clear rx_valid
//   0x08 - STATUS   (R):  [0]=tx_busy, [1]=rx_valid, [2]=rx_overrun, [3]=rx_frame_err
//   0x0C - CTRL     (RW): [0]=rx_irq_en (cho phép ngắt khi nhận byte)
// =============================================================================
module uart #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  logic        clk,
    input  logic        rst_n,       // Active-low reset (match design convention)

    // ── CPU Memory-Mapped Interface ─────────────────────────────────
    input  logic        sel_i,       // Chip select (address decoder chọn UART)
    input  logic [3:0]  addr_i,      // Register offset (word-aligned, [3:2] dùng)
    input  logic        we_i,        // Write enable
    input  logic [31:0] wdata_i,     // Write data
    output logic [31:0] rdata_o,     // Read data
    output logic        ready_o,     // Luôn ready (single-cycle access)

    // ── Physical UART Pins ──────────────────────────────────────────
    input  logic        rx_i,        // UART RX pin (từ bên ngoài / PC)
    output logic        tx_o,        // UART TX pin (ra ngoài / PC)

    // ── Interrupt Output ────────────────────────────────────────────
    output logic        rx_irq_o     // Interrupt request khi có byte mới nhận
);

    // =========================================================================
    // 1. PRESCALE CALCULATION
    //    Reference design dùng prescale = CLK_FREQ / (BAUD * 8)
    //    Mỗi bit được oversample 8 lần
    // =========================================================================
    localparam [15:0] PRESCALE = CLK_FREQ / (BAUD_RATE * 8);

    // =========================================================================
    // 2. INTERNAL SIGNALS
    // =========================================================================
    // TX path (CPU → UART TX pin)
    logic [7:0]  tx_axis_tdata;
    logic        tx_axis_tvalid;
    logic        tx_axis_tready;
    logic        tx_busy;

    // RX path (UART RX pin → CPU)
    logic [7:0]  rx_axis_tdata;
    logic        rx_axis_tvalid;
    logic        rx_axis_tready;
    logic        rx_busy;
    logic        rx_overrun_error;
    logic        rx_frame_error;

    // Internal registers
    logic [7:0]  rx_data_reg;       // Latch byte nhận được
    logic        rx_data_valid;     // Cờ báo có data mới
    logic        rx_overrun_latch;  // Latch overrun error
    logic        rx_frame_err_latch;// Latch frame error
    logic        rx_irq_en;        // Enable interrupt khi nhận byte

    // =========================================================================
    // 3. UART TX CORE (Dựa trên reference verilog-uart/rtl/uart_tx.v)
    // =========================================================================
    logic        tx_tready_reg;
    logic        tx_txd_reg;
    logic        tx_busy_reg;
    logic [8:0]  tx_data_reg;      // DATA_WIDTH(8) + 1 bit stop
    logic [18:0] tx_prescale_reg;
    logic [3:0]  tx_bit_cnt;

    assign tx_axis_tready = tx_tready_reg;
    assign tx_o           = tx_txd_reg;
    assign tx_busy        = tx_busy_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_tready_reg   <= 1'b0;
            tx_txd_reg      <= 1'b1;      // UART idle = HIGH
            tx_prescale_reg <= 19'd0;
            tx_bit_cnt      <= 4'd0;
            tx_busy_reg     <= 1'b0;
            tx_data_reg     <= 9'd0;
        end else begin
            if (tx_prescale_reg > 0) begin
                tx_tready_reg   <= 1'b0;
                tx_prescale_reg <= tx_prescale_reg - 1;
            end else if (tx_bit_cnt == 0) begin
                tx_tready_reg <= 1'b1;
                tx_busy_reg   <= 1'b0;
                if (tx_axis_tvalid) begin
                    tx_tready_reg   <= ~tx_tready_reg;
                    tx_prescale_reg <= ({3'b0, PRESCALE} << 3) - 1;
                    tx_bit_cnt      <= 4'd9;           // 8 data + 1 stop
                    tx_data_reg     <= {1'b1, tx_axis_tdata}; // stop bit + data
                    tx_txd_reg      <= 1'b0;           // start bit
                    tx_busy_reg     <= 1'b1;
                end
            end else begin
                if (tx_bit_cnt > 1) begin
                    tx_bit_cnt      <= tx_bit_cnt - 1;
                    tx_prescale_reg <= ({3'b0, PRESCALE} << 3) - 1;
                    {tx_data_reg, tx_txd_reg} <= {1'b0, tx_data_reg};
                end else if (tx_bit_cnt == 1) begin
                    tx_bit_cnt      <= tx_bit_cnt - 1;
                    tx_prescale_reg <= {3'b0, PRESCALE} << 3;
                    tx_txd_reg      <= 1'b1;           // stop bit
                end
            end
        end
    end

    // =========================================================================
    // 4. UART RX CORE (Dựa trên reference verilog-uart/rtl/uart_rx.v)
    // =========================================================================
    logic [7:0]  rx_tdata_reg;
    logic        rx_tvalid_reg;
    logic        rx_rxd_reg;
    logic        rx_busy_reg;
    logic        rx_overrun_reg;
    logic        rx_frame_reg;
    logic [7:0]  rx_shift_reg;
    logic [18:0] rx_prescale_reg;
    logic [3:0]  rx_bit_cnt;

    assign rx_axis_tdata    = rx_tdata_reg;
    assign rx_axis_tvalid   = rx_tvalid_reg;
    assign rx_busy          = rx_busy_reg;
    assign rx_overrun_error = rx_overrun_reg;
    assign rx_frame_error   = rx_frame_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_tdata_reg    <= 8'd0;
            rx_tvalid_reg   <= 1'b0;
            rx_rxd_reg      <= 1'b1;
            rx_prescale_reg <= 19'd0;
            rx_bit_cnt      <= 4'd0;
            rx_busy_reg     <= 1'b0;
            rx_overrun_reg  <= 1'b0;
            rx_frame_reg    <= 1'b0;
            rx_shift_reg    <= 8'd0;
        end else begin
            rx_rxd_reg     <= rx_i;       // Synchronizer stage 1
            rx_overrun_reg <= 1'b0;       // Pulse, tự clear
            rx_frame_reg   <= 1'b0;       // Pulse, tự clear

            if (rx_axis_tvalid && rx_axis_tready) begin
                rx_tvalid_reg <= 1'b0;
            end

            if (rx_prescale_reg > 0) begin
                rx_prescale_reg <= rx_prescale_reg - 1;
            end else if (rx_bit_cnt > 0) begin
                if (rx_bit_cnt > 9) begin
                    // Start bit validation (sample giữa bit)
                    if (!rx_rxd_reg) begin
                        rx_bit_cnt      <= rx_bit_cnt - 1;
                        rx_prescale_reg <= ({3'b0, PRESCALE} << 3) - 1;
                    end else begin
                        rx_bit_cnt      <= 4'd0;  // False start → hủy
                        rx_prescale_reg <= 19'd0;
                    end
                end else if (rx_bit_cnt > 1) begin
                    // Data bits (LSB first)
                    rx_bit_cnt      <= rx_bit_cnt - 1;
                    rx_prescale_reg <= ({3'b0, PRESCALE} << 3) - 1;
                    rx_shift_reg    <= {rx_rxd_reg, rx_shift_reg[7:1]};
                end else if (rx_bit_cnt == 1) begin
                    // Stop bit
                    rx_bit_cnt <= rx_bit_cnt - 1;
                    if (rx_rxd_reg) begin
                        // Valid stop bit → output data
                        rx_tdata_reg   <= rx_shift_reg;
                        rx_tvalid_reg  <= 1'b1;
                        rx_overrun_reg <= rx_tvalid_reg; // Overrun nếu data cũ chưa đọc
                    end else begin
                        rx_frame_reg <= 1'b1;  // Frame error: stop bit != 1
                    end
                end
            end else begin
                rx_busy_reg <= 1'b0;
                if (!rx_rxd_reg) begin
                    // Falling edge → start bit detected
                    rx_prescale_reg <= ({3'b0, PRESCALE} << 2) - 2;  // Sample giữa start bit
                    rx_bit_cnt      <= 4'd10;  // 1 start + 8 data + 1 stop
                    rx_shift_reg    <= 8'd0;
                    rx_busy_reg     <= 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // 5. REGISTER FILE & CPU ACCESS LOGIC
    // =========================================================================
    // RX FIFO handshake: CPU đọc RX_DATA → clear valid
    assign rx_axis_tready = (sel_i && !we_i && addr_i[3:2] == 2'b01); // Read from RX_DATA

    // CPU Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_axis_tvalid   <= 1'b0;
            tx_axis_tdata    <= 8'd0;
            rx_data_reg      <= 8'd0;
            rx_data_valid    <= 1'b0;
            rx_overrun_latch <= 1'b0;
            rx_frame_err_latch <= 1'b0;
            rx_irq_en        <= 1'b0;
        end else begin
            // Auto-clear TX valid sau 1 cycle (fire-and-forget)
            if (tx_axis_tvalid && tx_axis_tready)
                tx_axis_tvalid <= 1'b0;

            // Latch RX data khi UART core báo valid
            if (rx_axis_tvalid && !rx_data_valid) begin
                rx_data_reg   <= rx_axis_tdata;
                rx_data_valid <= 1'b1;
            end
            // Latch error flags
            if (rx_overrun_error) rx_overrun_latch <= 1'b1;
            if (rx_frame_error)   rx_frame_err_latch <= 1'b1;

            // CPU Access
            if (sel_i) begin
                if (we_i) begin
                    case (addr_i[3:2])
                        2'b00: begin // TX_DATA: ghi byte vào TX
                            tx_axis_tdata  <= wdata_i[7:0];
                            tx_axis_tvalid <= 1'b1;
                        end
                        2'b11: begin // CTRL: điều khiển
                            rx_irq_en <= wdata_i[0];
                        end
                        default: ;
                    endcase
                end else begin
                    case (addr_i[3:2])
                        2'b01: begin // RX_DATA: đọc xong clear valid + error
                            rx_data_valid      <= 1'b0;
                            rx_overrun_latch   <= 1'b0;
                            rx_frame_err_latch <= 1'b0;
                        end
                        default: ;
                    endcase
                end
            end
        end
    end

    // CPU Read mux
    always_comb begin
        rdata_o = 32'd0;
        if (sel_i && !we_i) begin
            case (addr_i[3:2])
                2'b00: rdata_o = {24'd0, tx_axis_tdata};        // TX_DATA echo
                2'b01: rdata_o = {24'd0, rx_data_reg};          // RX_DATA
                2'b10: rdata_o = {28'd0, rx_frame_err_latch,    // STATUS
                                         rx_overrun_latch,
                                         rx_data_valid,
                                         tx_busy};
                2'b11: rdata_o = {31'd0, rx_irq_en};            // CTRL
                default: rdata_o = 32'd0;
            endcase
        end
    end

    // Luôn sẵn sàng (single-cycle register access)
    assign ready_o = 1'b1;

    // =========================================================================
    // 6. INTERRUPT GENERATION
    //    Khi có byte mới nhận VÀ interrupt được enable → kéo IRQ lên
    // =========================================================================
    assign rx_irq_o = rx_data_valid & rx_irq_en;

endmodule
