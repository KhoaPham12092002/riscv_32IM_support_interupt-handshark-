`timescale 1ns/1ps

// =============================================================================
// tb_soc_io — HEX Function Test (Mode 00)
//
// Mục đích: Kiểm tra toàn diện chức năng hiển thị N² lên 6 màn HEX 7-đoạn.
//   SW[1:0] = 00  →  Mode 00
//   SW[9:2] = N   →  VALUE (0..255)
//   HEX hiển thị N² theo từng chữ số từ thấp lên cao.
//
// Bảng mã 7-đoạn (common-anode, bits[6:0] = gfedcba):
//   0→40  1→79  2→24  3→30  4→19  5→12  6→02  7→78  8→00  9→10  blank→7F
//
// Test groups:
//   G1  N = 0..3    → N² 1 chữ số  ( 0..  9)
//   G2  N = 4..9    → N² 2 chữ số  (16.. 81)
//   G3  N = 10..31  → N² 3 chữ số  (100..961)
//   G4  N = 32..99  → N² 4 chữ số  (1024..9801)
//   G5  N = 100..255→ N² 5 chữ số  (10000..65025)
// =============================================================================
module tb_soc_io;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int CLK_FREQ_HZ = 50_000_000;
    localparam int BAUD_RATE   = 115_200;
    localparam int CLK_PERIOD  = 20;            // ns (50 MHz)
    localparam int WAIT_CYCLES = 30_000;        // chu kỳ chờ sau khi thay SW

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
    // FUNCTION: digit → 7-seg code (common-anode, bits[6:0])
    //   -1 (hoặc bất kỳ số ngoài 0-9) → 7'h7F (blank, tất cả segment tắt)
    // =========================================================================
    function automatic logic [6:0] seg7(input int d);
        case (d)
            0: return 7'h40;
            1: return 7'h79;
            2: return 7'h24;
            3: return 7'h30;
            4: return 7'h19;
            5: return 7'h12;
            6: return 7'h02;
            7: return 7'h78;
            8: return 7'h00;
            9: return 7'h10;
            default: return 7'h7F; // blank
        endcase
    endfunction

    // =========================================================================
    // TASK: test_n(N)
    //   1. Set SW = {N[7:0], 2'b00}  (Mode 00, VALUE = N)
    //   2. Chờ WAIT_CYCLES chu kỳ để CPU tính N² và ghi HEX registers
    //   3. Tính expected codes cho cả 6 màn (LSB-first, blank nếu hết chữ số)
    //   4. So sánh và in kết quả
    //
    // Thuật toán expected khớp với assembly (programv2.s):
    //   - Luôn ghi ít nhất 1 chữ số (kể cả N²=0 → '0')
    //   - Sau khi thương=0: fill blank cho các màn còn lại
    // =========================================================================
    task automatic test_n(input int N);
        int          nsq, tmp;
        logic [6:0]  exp[0:5];
        logic        all_ok;

        nsq = N * N;
        tmp = nsq;

        // Tính expected (hex0=ones, hex1=tens, …)
        for (int i = 0; i < 6; i++) begin
            if (i == 0 || tmp > 0) begin
                exp[i] = seg7(tmp % 10);
                tmp    = tmp / 10;
            end else begin
                exp[i] = 7'h7F; // blank
            end
        end

        // Drive & wait
        sw_i = {N[7:0], 2'b00};
        repeat (WAIT_CYCLES) @(posedge clk);

        // Compare
        all_ok = (hex0_o === exp[0]) && (hex1_o === exp[1]) &&
                 (hex2_o === exp[2]) && (hex3_o === exp[3]) &&
                 (hex4_o === exp[4]) && (hex5_o === exp[5]);

        if (all_ok) begin
            pass_cnt++;
            $display("  [PASS] N=%3d  N²=%5d  HEX[5:0]=%02h %02h %02h %02h %02h %02h",
                N, nsq,
                hex5_o, hex4_o, hex3_o, hex2_o, hex1_o, hex0_o);
        end else begin
            fail_cnt++;
            $display("  [FAIL] N=%3d  N²=%5d", N, nsq);
            $display("           got HEX[5:0] = %02h %02h %02h %02h %02h %02h",
                hex5_o, hex4_o, hex3_o, hex2_o, hex1_o, hex0_o);
            $display("           exp HEX[5:0] = %02h %02h %02h %02h %02h %02h",
                exp[5], exp[4], exp[3], exp[2], exp[1], exp[0]);
        end
    endtask

    // =========================================================================
    // MONITOR: in log mỗi khi HEX0 thay đổi (passive, không ảnh hưởng test)
    // =========================================================================
    logic [6:0] hex0_prev;
    initial hex0_prev = 7'hXX;
    always @(posedge clk) begin
        if (!rst && hex0_o !== hex0_prev && ^hex0_o !== 1'bX) begin
            $display("  [MON]  t=%8t ns  HEX[5..0]=%02h %02h %02h %02h %02h %02h  SW=%03h",
                $time,
                hex5_o, hex4_o, hex3_o, hex2_o, hex1_o, hex0_o,
                sw_i);
            hex0_prev = hex0_o;
        end
    end

    // =========================================================================
    // IO ACCESS MONITOR — log mọi io_req_valid (HEX, KEY, SW/LED, UART, GPIO)
    // Giúp trả lời: HEX write có thực sự xảy ra không?
    // =========================================================================
    always @(posedge clk) begin
        if (!rst && u_soc.io_req_valid) begin
            $display("  [IO]   t=%8t ns  addr=%08h  we=%b  wdata=%08h  cs={swled=%b hex=%b key=%b uart=%b gpio=%b}",
                $time,
                u_soc.dmem_addr,
                u_soc.io_we,
                u_soc.dmem_wdata,
                u_soc.cs_sw_led, u_soc.cs_hex, u_soc.cs_key, u_soc.cs_uart, u_soc.cs_gpio);
        end
    end

    // Đếm số lần ghi HEX để phát hiện nhanh "không bao giờ ghi"
    int unsigned hex_write_cnt = 0;
    always @(posedge clk) begin
        if (!rst && u_soc.cs_hex && u_soc.io_we) hex_write_cnt++;
    end

    // =========================================================================
    // DEBUG MONITOR 1: LSU DONE state — chỉ cho LOAD (we_q=0)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst && u_soc.u_datapath.u_lsu_core.state == 2'd3 /*DONE*/
                  && !u_soc.u_datapath.u_lsu_core.we_q) begin
            $display("  [LSU-DONE] t=%8t ns  addr_q=%08h  dmem_rdata_q=%08h  lsu_rdata_o=%08h  funct3_q=%b",
                $time,
                u_soc.u_datapath.u_lsu_core.addr_q,
                u_soc.u_datapath.u_lsu_core.dmem_rdata_q,
                u_soc.u_datapath.u_lsu_core.lsu_rdata_o,
                u_soc.u_datapath.u_lsu_core.funct3_q);
        end
    end

    // =========================================================================
    // DEBUG MONITOR 2: mỗi lần x6 được ghi (rf_we cho x6)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst && u_soc.u_datapath.mem_wb_valid
                  && u_soc.u_datapath.mem_wb_out.ctrl.rf_we
                  && u_soc.u_datapath.mem_wb_out.rd_addr == 5'd6) begin
            $display("  [WB-x6]    t=%8t ns  rf_wdata=%08h  wb_sel=%b  load_data=%08h  alu_result=%08h",
                $time,
                u_soc.u_datapath.rf_wdata,
                u_soc.u_datapath.mem_wb_out.ctrl.wb_sel,
                u_soc.u_datapath.mem_wb_out.load_data,
                u_soc.u_datapath.mem_wb_out.alu_result);
        end
    end

    // =========================================================================
    // DEBUG MONITOR 3: Trace EX stage for all instructions
    // =========================================================================
    always @(posedge clk) begin
        if (!rst && u_soc.u_datapath.id_ex_valid) begin
            $display("  [EX-TRACE] t=%8t ns  pc=%08h rs1=%d rs2=%d  fwd_s1=%b fwd_s2=%b  rs1_fwd=%08h rs2_fwd=%08h  alu_result=%08h  ready=%b  lsu=%d",
                $time,
                u_soc.u_datapath.id_ex_out.pc,
                u_soc.u_datapath.id_ex_out.rs1_addr,
                u_soc.u_datapath.id_ex_out.rs2_addr,
                u_soc.u_datapath.ctrl_fwd_rs1_sel_i,
                u_soc.u_datapath.ctrl_fwd_rs2_sel_i,
                u_soc.u_datapath.ex_rs1_fwd_data,
                u_soc.u_datapath.ex_rs2_fwd_data,
                u_soc.u_datapath.ex_alu_result,
                u_soc.u_datapath.ex_mem_ready,
                u_soc.u_datapath.u_lsu_core.state);
        end
    end

    // =========================================================================
    // BUILD MARKER — verify fix compiled in
    // =========================================================================
    initial $display("[BUILD] mem_fwd_val fix compiled in — tb_soc_io debug monitors active");

    // =========================================================================
    // STIMULUS
    // =========================================================================
    initial begin
        // ── Reset ─────────────────────────────────────────────────────────────
        rst       = 1'b1;
        sw_i      = 10'h000;
        key_i     = 4'hF;    // Active-low: 4'hF = không nhấn phím nào
        uart_rx_i = 1'b1;    // UART idle
        repeat (20) @(posedge clk);
        rst = 1'b0;

        $display("=============================================================");
        $display("[TB] Mode 00 — HEX 7-seg N² Function Test");
        $display("     DUT: soc_top_io + programv2.hex");
        $display("     SW[1:0]=00 (Mode 00)  SW[9:2]=N  →  HEX shows N²");
        $display("     7-seg common-anode encoding:");
        $display("       0→40  1→79  2→24  3→30  4→19");
        $display("       5→12  6→02  7→78  8→00  9→10  blank→7F");
        $display("=============================================================");

        // Chờ _init hoàn thành: li + sb × 10 digits + li sp, li x28
        // Ước tính: ~100 instructions × ~4 cycles = ~400 cycles, dùng 500 để chắc chắn
        repeat (500) @(posedge clk);

        // ====================================================================
        // GROUP 1: N² = 1 chữ số  (N = 0..3)
        // ====================================================================
        $display("");
        $display("[G1] N=0..3  →  N²=0..9  (1 chữ số, hex1..5=blank)");
        test_n(0);   //   0²=0
        test_n(1);   //   1²=1
        test_n(2);   //   2²=4
        test_n(3);   //   3²=9

        // ====================================================================
        // GROUP 2: N² = 2 chữ số  (N = 4..9)
        // ====================================================================
        $display("");
        $display("[G2] N=4..9  →  N²=16..81  (2 chữ số, hex2..5=blank)");
        test_n(4);   //   4²=16   hex0='6'(02)  hex1='1'(79)
        test_n(5);   //   5²=25   hex0='5'(12)  hex1='2'(24)
        test_n(6);   //   6²=36   hex0='6'(02)  hex1='3'(30)
        test_n(7);   //   7²=49   hex0='9'(10)  hex1='4'(19)
        test_n(8);   //   8²=64   hex0='4'(19)  hex1='6'(02)
        test_n(9);   //   9²=81   hex0='1'(79)  hex1='8'(00)

        // ====================================================================
        // GROUP 3: N² = 3 chữ số  (N = 10..31)
        // ====================================================================
        $display("");
        $display("[G3] N=10..31  →  N²=100..961  (3 chữ số, hex3..5=blank)");
        test_n(10);  //  10²=100   0,0,1
        test_n(11);  //  11²=121   1,2,1
        test_n(15);  //  15²=225   5,2,2
        test_n(20);  //  20²=400   0,0,4
        test_n(25);  //  25²=625   5,2,6
        test_n(31);  //  31²=961   1,6,9

        // ====================================================================
        // GROUP 4: N² = 4 chữ số  (N = 32..99)
        // ====================================================================
        $display("");
        $display("[G4] N=32..99  →  N²=1024..9801  (4 chữ số, hex4..5=blank)");
        test_n(32);  //  32²=1024   4,2,0,1
        test_n(50);  //  50²=2500   0,0,5,2
        test_n(77);  //  77²=5929   9,2,9,5
        test_n(99);  //  99²=9801   1,0,8,9

        // ====================================================================
        // GROUP 5: N² = 5 chữ số  (N = 100..255)
        // ====================================================================
        $display("");
        $display("[G5] N=100..255  →  N²=10000..65025  (5 chữ số, hex5=blank)");
        test_n(100); // 100²=10000   0,0,0,0,1
        test_n(127); // 127²=16129   9,2,1,6,1
        test_n(200); // 200²=40000   0,0,0,0,4
        test_n(255); // 255²=65025   5,2,0,5,6

        // ====================================================================
        // SUMMARY
        // ====================================================================
        $display("");
        $display("=============================================================");
        $display("[TB] RESULT: PASS=%0d  FAIL=%0d  TOTAL=%0d",
                  pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("[TB] Tổng số lần ghi HEX peripheral (cs_hex && io_we) = %0d", hex_write_cnt);
        if (hex_write_cnt == 0)
            $display("[TB] >>> CẢNH BÁO: KHÔNG có HEX write nào — CPU không reach mode_00 hoặc cs_hex sai!");
        if (fail_cnt == 0)
            $display("[TB] *** ALL HEX TESTS PASSED ***");
        else
            $display("[TB] *** %0d TEST(S) FAILED — xem waveform ***", fail_cnt);
        $display("=============================================================");
        $stop;
    end

endmodule
