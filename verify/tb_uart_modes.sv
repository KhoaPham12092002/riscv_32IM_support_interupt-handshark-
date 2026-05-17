`timescale 1ns/1ps
// =============================================================================
// tb_uart_modes — UART Mode 01 & Mode 10 Verification
//
// Mode 01: SW[1:0]=01, SW[9:2]=VALUE → CPU TX "HH\r\n" (2 hex ASCII chars)
//          Anti-spam: chỉ gửi khi VALUE thay đổi so với lần trước
// Mode 10: SW[1:0]=10 → CPU echo UART RX → TX (byte-for-byte)
//
// UART: 50 MHz CLK, 115200 baud, 8N1
//   PRESCALE  = 50_000_000 / (115_200 * 8) = 54
//   BIT_CYCLES = 54 * 8 = 432 clock cycles per bit
//   FRAME_CYCLES = 10 * 432 = 4320 cycles per byte (1 start + 8 data + 1 stop)
// =============================================================================
module tb_uart_modes;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int CLK_FREQ_HZ  = 50_000_000;
    localparam int BAUD_RATE    = 115_200;
    localparam int CLK_PERIOD   = 20;                            // ns
    localparam int PRESCALE     = CLK_FREQ_HZ / (BAUD_RATE * 8); // = 54
    localparam int BIT_CYCLES   = PRESCALE * 8;                  // = 432
    localparam int BYTE_TIMEOUT = 300_000;                       // cycles trước khi timeout

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic [9:0]  sw_i;
    logic [9:0]  led_o;
    logic [3:0]  key_i;
    logic        uart_rx_i;
    logic        uart_tx_o;
    logic [6:0]  hex0_o, hex1_o, hex2_o, hex3_o, hex4_o, hex5_o;

    // =========================================================================
    // DUT
    // =========================================================================
    soc_top_io #(
        .IMEM_HEX  ("../src/memory/programv2.hex"),
        .IMEM_SZ   (4096),
        .DMEM_SZ   (4096),
        .CLK_FREQ  (CLK_FREQ_HZ),
        .BAUD_RATE (BAUD_RATE)
    ) u_soc (
        .clk_i     (clk),
        .rst_i     (rst),
        .sw_i      (sw_i),
        .led_o     (led_o),
        .key_i     (key_i),
        .uart_rx_i (uart_rx_i),
        .uart_tx_o (uart_tx_o),
        .hex0_o    (hex0_o),
        .hex1_o    (hex1_o),
        .hex2_o    (hex2_o),
        .hex3_o    (hex3_o),
        .hex4_o    (hex4_o),
        .hex5_o    (hex5_o)
    );

    // =========================================================================
    // Clock
    // =========================================================================
    initial clk = 1'b0;
    always  #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // Scorecard
    // =========================================================================
    int unsigned pass_cnt = 0;
    int unsigned fail_cnt = 0;

    // =========================================================================
    // FUNCTION: nibble → ASCII (khớp với assembly tx_hex_char)
    //   < 10  → '0'..'9'  (nib + 0x30)
    //   >= 10 → 'A'..'F'  (nib + 0x37)
    // =========================================================================
    function automatic logic [7:0] nibble_to_ascii(input logic [3:0] nib);
        return (nib < 4'd10) ? (8'h30 + {4'h0, nib})
                             : (8'h37 + {4'h0, nib});
    endfunction

    // =========================================================================
    // TASK: uart_recv
    //   Nhận 1 byte từ uart_tx_o (bit sampling tại giữa mỗi bit period).
    //   ok=1  : nhận thành công (stop bit = 1)
    //   ok=0  : timeout (không có start bit) hoặc frame error
    // =========================================================================
    task automatic uart_recv(output logic [7:0] data, output logic ok);
        int cnt;
        ok   = 1'b0;
        data = 8'hXX;
        cnt  = BYTE_TIMEOUT;

        // Chờ falling edge (start bit)
        while (uart_tx_o !== 1'b0 && cnt > 0) begin
            @(posedge clk);
            cnt--;
        end
        if (cnt == 0) begin
            $display("  [UART] TIMEOUT: không nhận được start bit sau %0d cycles", BYTE_TIMEOUT);
            return;
        end

        // Vào giữa start bit
        repeat (BIT_CYCLES / 2) @(posedge clk);

        // Sample 8 data bits (LSB first), mỗi bit cách nhau BIT_CYCLES
        for (int i = 0; i < 8; i++) begin
            repeat (BIT_CYCLES) @(posedge clk);
            data[i] = uart_tx_o;
        end

        // Stop bit: chờ BIT_CYCLES, kiểm tra = 1
        repeat (BIT_CYCLES) @(posedge clk);
        ok = (uart_tx_o === 1'b1);
        if (!ok)
            $display("  [UART] Frame error: stop bit = %b", uart_tx_o);
    endtask

    // =========================================================================
    // TASK: uart_send
    //   Gửi 1 byte qua uart_rx_i (mô phỏng external UART sender).
    //   Định dạng 8N1, LSB-first.
    // =========================================================================
    task automatic uart_send(input logic [7:0] data);
        uart_rx_i = 1'b0;                    // start bit
        repeat (BIT_CYCLES) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            uart_rx_i = data[i];             // data bits (LSB first)
            repeat (BIT_CYCLES) @(posedge clk);
        end
        uart_rx_i = 1'b1;                    // stop bit
        repeat (BIT_CYCLES) @(posedge clk);
    endtask

    // =========================================================================
    // TASK: test_mode01
    //   Set SW → Mode 01, VALUE. Nhận 4 bytes (hi, lo, CR, LF) và so sánh.
    //   Gọi khi đảm bảo VALUE != x28 (anti-spam không chặn).
    // =========================================================================
    task automatic test_mode01(input logic [7:0] value);
        logic [7:0] exp[0:3];
        logic [7:0] got;
        logic       ok;
        logic       all_ok;
        string      repr;

        exp[0] = nibble_to_ascii(value[7:4]);  // nibble cao
        exp[1] = nibble_to_ascii(value[3:0]);  // nibble thấp
        exp[2] = 8'h0D;                         // CR
        exp[3] = 8'h0A;                         // LF

        sw_i   = {value, 2'b01};               // MODE=01, VALUE=value

        all_ok = 1'b1;
        for (int i = 0; i < 4; i++) begin
            uart_recv(got, ok);
            if (!ok || got !== exp[i]) begin
                all_ok = 1'b0;
                $display("  [FAIL] Mode01 VALUE=%02Xh byte[%0d] got=%02Xh exp=%02Xh  ok=%b",
                         value, i, got, exp[i], ok);
            end
        end

        if (all_ok) begin
            pass_cnt++;
            $display("  [PASS] Mode01 VALUE=%02Xh → '%c%c\\r\\n'",
                     value, exp[0], exp[1]);
        end else begin
            fail_cnt++;
        end
    endtask

    // =========================================================================
    // TASK: test_mode10
    //   Gửi byte qua uart_rx_i, đợi CPU echo lại trên uart_tx_o.
    // =========================================================================
    task automatic test_mode10(input logic [7:0] send_byte);
        logic [7:0] got;
        logic       ok;

        sw_i = {8'h00, 2'b10};               // MODE=10
        repeat (300) @(posedge clk);         // chờ CPU vào mode_10

        uart_send(send_byte);                 // gửi byte (~4320 cycles)

        uart_recv(got, ok);                   // nhận echo

        if (ok && got === send_byte) begin
            pass_cnt++;
            $display("  [PASS] Mode10 send=%02Xh  echo=%02Xh", send_byte, got);
        end else begin
            fail_cnt++;
            $display("  [FAIL] Mode10 send=%02Xh  echo=%02Xh  ok=%b", send_byte, got, ok);
        end
    endtask

    // =========================================================================
    // STIMULUS
    // =========================================================================
    initial begin
        // ── Reset ─────────────────────────────────────────────────────────────
        rst       = 1'b1;
        sw_i      = 10'h000;
        key_i     = 4'hF;     // active-low, không nhấn
        uart_rx_i = 1'b1;     // UART idle
        repeat (20) @(posedge clk);
        rst = 1'b0;

        // Chờ _init hoàn thành (~100 instr × 4 cycles + margin)
        repeat (500) @(posedge clk);

        $display("=================================================================");
        $display("[TB] UART Mode Test  |  50MHz CLK  |  115200 baud");
        $display("     BIT_CYCLES=%0d  FRAME_CYCLES=%0d", BIT_CYCLES, BIT_CYCLES*10);
        $display("=================================================================");

        // ==================================================================
        // MODE 01 — TX hex ASCII (nibble_high nibble_low CR LF)
        //   x28 khởi tạo = -1 (0xFFFF_FFFF) nên lần đầu luôn gửi.
        //   Mỗi test dùng VALUE khác nhau để anti-spam không chặn.
        // ==================================================================
        $display("");
        $display("[M01] Mode 01 — VALUE → UART TX ('HH\\r\\n')");

        test_mode01(8'h00);  // '0','0',CR,LF
        test_mode01(8'h09);  // '0','9',CR,LF  — chữ số đơn
        test_mode01(8'h0A);  // '0','A',CR,LF  — ranh giới digit/letter
        test_mode01(8'h5A);  // '5','A',CR,LF  — mixed
        test_mode01(8'hAB);  // 'A','B',CR,LF  — full letter
        test_mode01(8'hFF);  // 'F','F',CR,LF  — max

        // ── Anti-spam: cùng VALUE=0xFF gửi lại → CPU KHÔNG gửi ─────────────
        $display("[M01] Anti-spam: VALUE=FFh lặp lại (không nên có TX)");
        begin
            automatic bit tx_seen = 0;
            sw_i = {8'hFF, 2'b01}; // same value as last test
            fork : antispam_fork
                begin
                    repeat (15_000) @(posedge clk); // ~15000 cycles chờ
                end
                begin
                    @(negedge uart_tx_o);            // bất kỳ start bit nào
                    tx_seen = 1;
                end
            join_any
            disable antispam_fork;

            if (!tx_seen) begin
                pass_cnt++;
                $display("  [PASS] Anti-spam: không có TX khi VALUE không đổi (FFh)");
            end else begin
                fail_cnt++;
                $display("  [FAIL] Anti-spam: phát hiện TX bất ngờ khi VALUE=FFh lặp lại");
            end
        end

        // ==================================================================
        // MODE 10 — RX echo
        //   CPU poll rx_valid, nếu có byte: đọc RX_DATA, echo qua TX.
        // ==================================================================
        $display("");
        $display("[M10] Mode 10 — UART RX echo");

        test_mode10(8'h41);  // 'A'
        test_mode10(8'h55);  // 'U'
        test_mode10(8'h00);  // null byte
        test_mode10(8'hAA);  // alternating bits
        test_mode10(8'hFF);  // all ones

        // ==================================================================
        // SUMMARY
        // ==================================================================
        $display("");
        $display("=================================================================");
        $display("[TB] RESULT: PASS=%0d  FAIL=%0d  TOTAL=%0d",
                  pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display("[TB] *** ALL UART TESTS PASSED ***");
        else
            $display("[TB] *** %0d TEST(S) FAILED ***", fail_cnt);
        $display("=================================================================");
        $stop;
    end

endmodule
