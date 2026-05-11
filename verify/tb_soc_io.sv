`timescale 1ns/1ps

// =============================================================================
// Module : tb_soc_io
// Target : soc_top_io (RISC-V RV32IM SoC + GPIO/UART/LCD)
//
// Test plan:
//   TEST 1  Mode 00 (SW[1:0]=00): LCD display "THESIS BK 2026"
//             - Verify lcd_on_o=1, lcd_rw_o=0
//             - Monitor CMD/DATA strobes on rising edge of lcd_en_o
//   TEST 2  Mode 01 (SW[1:0]=01): LED = (SW[9:2])^2
//             - 2a: N=5  → LED=25
//             - 2b: N=15 → LED=225
//             - 2c: N=0  → LED=0
//             - 2d: N=10 → LED=100
//   TEST 3  Mode 02 (SW[1:0]=10): UART TX decimal string + CRLF
//             - 3a: N=42  → "42\r\n"
//             - 3b: N=100 → "100\r\n"
//
// SW encoding:
//   sw_i[1:0]  = mode (00/01/10)
//   sw_i[9:2]  = N value (8-bit, 0-255)
//
// Timing:
//   Clock : 50 MHz (20 ns period)
//   UART  : 115200 baud → 1 bit ≈ 8680 ns
// =============================================================================

module tb_soc_io;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int  CLK_FREQ_HZ  = 50_000_000;
    localparam int  BAUD_RATE    = 115_200;
    localparam int  CLK_PERIOD   = 20;               // ns

    // Bit period at BAUD_RATE over CLK_FREQ clock
    localparam int  BIT_CLKS     = CLK_FREQ_HZ / BAUD_RATE;  // ~434 clock cycles/bit
    localparam int  BIT_NS       = BIT_CLKS * CLK_PERIOD;    // ~8680 ns/bit

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic [9:0]  sw_i;
    logic [9:0]  led_o;
    logic        uart_rx_i;
    logic        uart_tx_o;
    logic [7:0]  lcd_data_o;
    logic        lcd_en_o;
    logic        lcd_rs_o;
    logic        lcd_rw_o;
    logic        lcd_on_o;

    // =========================================================================
    // DUT
    // =========================================================================
    soc_top_io #(
        .IMEM_HEX  ("../src/memory/program_io.hex"),
        .IMEM_SZ   (4096),
        .DMEM_SZ   (4096),
        .CLK_FREQ  (CLK_FREQ_HZ),
        .BAUD_RATE (BAUD_RATE)
    ) u_soc (
        .clk_i      (clk),
        .rst_i      (rst),
        .sw_i       (sw_i),
        .led_o      (led_o),
        .uart_rx_i  (uart_rx_i),
        .uart_tx_o  (uart_tx_o),
        .lcd_data_o (lcd_data_o),
        .lcd_en_o   (lcd_en_o),
        .lcd_rs_o   (lcd_rs_o),
        .lcd_rw_o   (lcd_rw_o),
        .lcd_on_o   (lcd_on_o)
    );

    // =========================================================================
    // Clock & UART idle
    // =========================================================================
    initial clk     = 1'b0;
    always  #(CLK_PERIOD/2) clk = ~clk;

    assign uart_rx_i = 1'b1;   // UART RX idle (no incoming data)

    // =========================================================================
    // HELPER: capture 1 UART byte from uart_tx_o
    //   Returns captured data; sets timeout_o=1 if start bit not seen within
    //   TIMEOUT_CLKS clock cycles.
    // =========================================================================
    localparam int UART_TIMEOUT_CLKS = 200_000;

    task automatic uart_capture_byte(
        output logic [7:0] data,
        output logic       timed_out
    );
        int wait_cnt;

        // Wait for falling edge (start bit), counting clock cycles
        timed_out = 1'b0;
        wait_cnt  = 0;
        while (uart_tx_o === 1'b1) begin
            @(posedge clk);
            wait_cnt++;
            if (wait_cnt >= UART_TIMEOUT_CLKS) begin
                timed_out = 1'b1;
                data      = 8'hXX;
                return;
            end
        end

        // Sample at center of each data bit
        // Start bit just detected (uart_tx_o went low); delay 1.5 bit periods
        #(BIT_NS + BIT_NS/2);
        data = 8'h00;
        for (int i = 0; i < 8; i++) begin
            data[i] = uart_tx_o;
            if (i < 7) #BIT_NS;
        end
        // Consume rest of stop bit
        #BIT_NS;
    endtask

    // =========================================================================
    // SCORECARD
    // =========================================================================
    int unsigned pass_cnt = 0;
    int unsigned fail_cnt = 0;

    task check(input string msg, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", msg);
            pass_cnt++;
        end else begin
            $display("  [FAIL] %s", msg);
            fail_cnt++;
        end
    endtask

    // =========================================================================
    // MONITORS (passive, always active after reset)
    // =========================================================================

    // --- LCD strobe: print on rising edge of lcd_en_o ---
    logic prev_lcd_en;
    always_ff @(posedge clk) prev_lcd_en <= lcd_en_o;

    always @(posedge clk) begin
        if (lcd_en_o && !prev_lcd_en && !rst) begin
            if (lcd_rs_o == 1'b0)
                $display("  [LCD-CMD]  t=%0t  CMD =0x%02X", $time, lcd_data_o);
            else
                $display("  [LCD-DATA] t=%0t  DATA=0x%02X ('%c')", $time, lcd_data_o,
                         (lcd_data_o >= 8'h20 && lcd_data_o <= 8'h7E) ? lcd_data_o : 8'h2E);
        end
    end

    // --- LED change monitor ---
    logic [9:0] led_prev_mon;
    initial led_prev_mon = 10'h3FF;
    always @(posedge clk) begin
        if (!rst && led_o !== led_prev_mon && ^led_o !== 1'bX) begin
            $display("  [LED]      t=%0t  LED=0x%03X (%0d)", $time, led_o, led_o);
            led_prev_mon = led_o;
        end
    end

    // --- Register-writeback debug (sparse — only non-x0 writes) ---
    always @(posedge clk) begin
        if (!rst &&
            u_soc.u_datapath.mem_wb_valid &&
            u_soc.u_datapath.mem_wb_out.ctrl.rf_we &&
            u_soc.u_datapath.mem_wb_out.rd_addr != 5'd0)
        begin
            $display("  [WB]       t=%0t  PC=0x%08X  x%0d <= 0x%08X",
                     $time,
                     u_soc.u_datapath.mem_wb_out.pc_plus4 - 32'd4,
                     u_soc.u_datapath.mem_wb_out.rd_addr,
                     u_soc.u_datapath.rf_wdata);
        end
    end

    // =========================================================================
    // STIMULUS + CHECKING
    // =========================================================================
    logic [7:0] rx_byte;
    logic       rx_to;
    logic [9:0] led_snap;

    initial begin
        // ── Reset ──────────────────────────────────────────────────────────
        rst  = 1'b1;
        sw_i = 10'h000;
        repeat (10) @(posedge clk);
        @(posedge clk);
        rst  = 1'b0;
        $display("=============================================================");
        $display("[TB] SoC reset released  t=%0t", $time);
        $display("=============================================================");

        // ──────────────────────────────────────────────────────────────────
        // TEST 1: Mode 00 — LCD display "THESIS BK 2026"
        // ──────────────────────────────────────────────────────────────────
        $display("");
        $display("[TEST 1] Mode 00 - LCD Display 'THESIS BK 2026'");
        $display("  (monitor LCD_CMD/DATA strobes for 120K cycles)");
        sw_i = 10'h000;                // mode=00, N=0
        // LCD sequence: init cmds 0x38/0x0C/0x01, delay, cursor, 14 data bytes
        // Each LCD op ≈ 2600 clk cycles (setup+strobe+hold)
        // 3 init + clear-delay(4096) + 1 cursor + 14 data ≈ 18 ops * 2600 + 4096 ≈ 51K clks
        repeat (120_000) @(posedge clk);

        check("LCD backlight always ON (lcd_on_o=1)", lcd_on_o === 1'b1);
        check("LCD R/W always WRITE (lcd_rw_o=0)",   lcd_rw_o === 1'b0);

        // ──────────────────────────────────────────────────────────────────
        // TEST 2: Mode 01 — LED perfect square
        //   sw_i = { SW[9:2]=N[7:0], SW[1:0]=2'b01 }
        //   Expected: led_o = (N*N) & 10'h3FF
        // ──────────────────────────────────────────────────────────────────
        $display("");
        $display("[TEST 2] Mode 01 - LED Perfect Square");

        // 2a: N=5 → 5^2=25
        sw_i = {8'd5, 2'b01};          // sw_i = 10'b00_0001_0101
        repeat (5_000) @(posedge clk);
        led_snap = led_o;
        $display("  N=5  : LED=%0d (expect 25)", led_snap);
        check("LED=25 when N=5",  led_snap === 10'd25);

        // 2b: N=15 → 15^2=225
        sw_i = {8'd15, 2'b01};         // sw_i = 10'b00_0011_1101
        repeat (5_000) @(posedge clk);
        led_snap = led_o;
        $display("  N=15 : LED=%0d (expect 225)", led_snap);
        check("LED=225 when N=15", led_snap === 10'd225);

        // 2c: N=0 → 0^2=0
        sw_i = {8'd0, 2'b01};          // sw_i = 10'b00_0000_0001
        repeat (5_000) @(posedge clk);
        led_snap = led_o;
        $display("  N=0  : LED=%0d (expect 0)", led_snap);
        check("LED=0 when N=0",   led_snap === 10'd0);

        // 2d: N=10 → 10^2=100
        sw_i = {8'd10, 2'b01};         // sw_i = 10'b00_0010_1001
        repeat (5_000) @(posedge clk);
        led_snap = led_o;
        $display("  N=10 : LED=%0d (expect 100)", led_snap);
        check("LED=100 when N=10", led_snap === 10'd100);

        // ──────────────────────────────────────────────────────────────────
        // TEST 3: Mode 02 — UART TX decimal string
        //   sw_i = { SW[9:2]=N[7:0], SW[1:0]=2'b10 }
        //
        //   CPU algorithm:
        //     hundreds (if != 0): ASCII digit
        //     tens digit  : ASCII digit
        //     units digit : ASCII digit
        //     CR (0x0D)
        //     LF (0x0A)
        //   Example N=42 → skips hundreds → sends '4','2',CR,LF
        // ──────────────────────────────────────────────────────────────────
        $display("");
        $display("[TEST 3a] Mode 02 - UART TX  N=42 → expect '42\\r\\n'");
        sw_i = {8'd42, 2'b10};         // sw_i = 10'b00_1010_1010

        uart_capture_byte(rx_byte, rx_to);
        $display("  Byte 1: 0x%02X '%c' %s", rx_byte,
                 (rx_byte >= 8'h20) ? rx_byte : 8'h2E,
                 rx_to ? "(TIMEOUT)" : "");
        check("UART N=42 byte1='4' (0x34)", !rx_to && rx_byte === 8'h34);

        uart_capture_byte(rx_byte, rx_to);
        $display("  Byte 2: 0x%02X '%c' %s", rx_byte,
                 (rx_byte >= 8'h20) ? rx_byte : 8'h2E,
                 rx_to ? "(TIMEOUT)" : "");
        check("UART N=42 byte2='2' (0x32)", !rx_to && rx_byte === 8'h32);

        uart_capture_byte(rx_byte, rx_to);
        $display("  Byte 3: 0x%02X %s", rx_byte, rx_to ? "(TIMEOUT)" : "");
        check("UART N=42 byte3=CR (0x0D)", !rx_to && rx_byte === 8'h0D);

        uart_capture_byte(rx_byte, rx_to);
        $display("  Byte 4: 0x%02X %s", rx_byte, rx_to ? "(TIMEOUT)" : "");
        check("UART N=42 byte4=LF (0x0A)", !rx_to && rx_byte === 8'h0A);

        // Wait through UART delay loop before next test
        // UART delay = ~32768 cycles (lui x28, 8; loop)
        repeat (80_000) @(posedge clk);

        $display("");
        $display("[TEST 3b] Mode 02 - UART TX  N=100 → expect '100\\r\\n'");
        // N=100=0b01100100, SW[9:2]=100, SW[1:0]=10
        sw_i = {8'd100, 2'b10};        // sw_i = 10'b01_1001_0010

        // N=100: hundreds=1→'1', tens=0→'0', units=0→'0', CR, LF
        uart_capture_byte(rx_byte, rx_to);
        $display("  Byte 1: 0x%02X '%c' %s", rx_byte,
                 (rx_byte >= 8'h20) ? rx_byte : 8'h2E,
                 rx_to ? "(TIMEOUT)" : "");
        check("UART N=100 byte1='1' (0x31)", !rx_to && rx_byte === 8'h31);

        uart_capture_byte(rx_byte, rx_to);
        $display("  Byte 2: 0x%02X '%c' %s", rx_byte,
                 (rx_byte >= 8'h20) ? rx_byte : 8'h2E,
                 rx_to ? "(TIMEOUT)" : "");
        check("UART N=100 byte2='0' (0x30)", !rx_to && rx_byte === 8'h30);

        uart_capture_byte(rx_byte, rx_to);
        $display("  Byte 3: 0x%02X '%c' %s", rx_byte,
                 (rx_byte >= 8'h20) ? rx_byte : 8'h2E,
                 rx_to ? "(TIMEOUT)" : "");
        check("UART N=100 byte3='0' (0x30)", !rx_to && rx_byte === 8'h30);

        uart_capture_byte(rx_byte, rx_to);
        $display("  Byte 4: 0x%02X %s", rx_byte, rx_to ? "(TIMEOUT)" : "");
        check("UART N=100 byte4=CR (0x0D)", !rx_to && rx_byte === 8'h0D);

        uart_capture_byte(rx_byte, rx_to);
        $display("  Byte 5: 0x%02X %s", rx_byte, rx_to ? "(TIMEOUT)" : "");
        check("UART N=100 byte5=LF (0x0A)", !rx_to && rx_byte === 8'h0A);

        // ──────────────────────────────────────────────────────────────────
        // RESULTS
        // ──────────────────────────────────────────────────────────────────
        $display("");
        $display("=============================================================");
        $display("[TB] RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("[TB] *** ALL TESTS PASSED ***");
        else
            $display("[TB] *** %0d TEST(S) FAILED — see waveform ***", fail_cnt);
        $display("=============================================================");
        $stop;
    end

endmodule
