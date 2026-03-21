`timescale 1ns/1ps
import riscv_32im_pkg::*; // Đảm bảo package này đã được compile trước

module tb_branch_cmp;

    // --- Khai báo tín hiệu ---
    logic [31:0] rs1_i;
    logic [31:0] rs2_i;
    br_op_e      br_op_i;
    logic        branch_taken_o;

    int error_count = 0;

    // --- Khởi tạo DUT (Device Under Test) ---
    branch_cmp dut (
        .rs1_i(rs1_i),
        .rs2_i(rs2_i),
        .br_op_i(br_op_i),
        .branch_taken_o(branch_taken_o)
    );

    // --- Task kiểm tra tự động ---
    task check_branch(
        input string       test_name,
        input logic [31:0] r1,
        input logic [31:0] r2,
        input br_op_e      op,
        input logic        expected
    );
        rs1_i   = r1;
        rs2_i   = r2;
        br_op_i = op;
        #1; // Đợi 1ns cho logic tổ hợp lan truyền

        if (branch_taken_o !== expected) begin
            $display("[FAIL] %-25s | Rs1: %0h, Rs2: %0h | Exp: %b, Act: %b", 
                     test_name, r1, r2, expected, branch_taken_o);
            error_count++;
        end else begin
            $display("[PASS] %-25s | Rs1: %0h, Rs2: %0h -> OK", test_name, r1, r2);
        end
    endtask

    // --- Kịch bản Test (Stimulus) ---
    initial begin
        $display("==================================================");
        $display("       STARTING BRANCH COMPARATOR TEST            ");
        $display("==================================================");

        // -----------------------------------------------------------
        // 1. Test Bằng Nhau (Equal / Not Equal)
        // -----------------------------------------------------------
        $display("\n--- 1. EQUALITY TESTS ---");
        check_branch("BEQ (10 == 10)",  32'd10, 32'd10, BR_BEQ, 1'b1);
        check_branch("BNE (10 != 10)",  32'd10, 32'd10, BR_BNE, 1'b0);
        check_branch("BEQ (-5 == -5)", -32'd5, -32'd5,  BR_BEQ, 1'b1);
        check_branch("BNE (-5 != 10)", -32'd5,  32'd10, BR_BNE, 1'b1);

        // -----------------------------------------------------------
        // 2. Test Cùng Dấu (Same Sign)
        // -----------------------------------------------------------
        $display("\n--- 2. SAME SIGN TESTS ---");
        check_branch("BLT  (5 < 10)",   32'd5,  32'd10, BR_BLT,  1'b1);
        check_branch("BGE  (5 >= 10)",  32'd5,  32'd10, BR_BGE,  1'b0);
        // Số âm: -10 < -5
        check_branch("BLT  (-10 < -5)", -32'd10, -32'd5, BR_BLT, 1'b1);
        check_branch("BGE  (-10 >= -5)",-32'd10, -32'd5, BR_BGE, 1'b0);

        // -----------------------------------------------------------
        // 3. Test Khác Dấu (TỬ HUYỆT: Signed vs Unsigned)
        // -----------------------------------------------------------
        $display("\n--- 3. MIXED SIGN TESTS (THE KILLER CASES) ---");
        // Rs1 = 5 (Dương), Rs2 = -2 (Âm. Unsigned là 0xFFFFFFFE)
        // Signed: 5 lớn hơn -2 -> BLT = 0, BGE = 1
        check_branch("BLT  (5 < -2)",   32'd5, -32'd2, BR_BLT,  1'b0);
        check_branch("BGE  (5 >= -2)",  32'd5, -32'd2, BR_BGE,  1'b1);
        // Unsigned: 5 nhỏ hơn 0xFFFFFFFE -> BLTU = 1, BGEU = 0
        check_branch("BLTU (5 < -2_U)", 32'd5, -32'd2, BR_BLTU, 1'b1);
        check_branch("BGEU (5 >= -2_U)",32'd5, -32'd2, BR_BGEU, 1'b0);

        // Rs1 = -2 (Âm), Rs2 = 5 (Dương)
        // Signed: -2 nhỏ hơn 5 -> BLT = 1, BGE = 0
        check_branch("BLT  (-2 < 5)",   -32'd2, 32'd5, BR_BLT,  1'b1);
        check_branch("BGE  (-2 >= 5)",  -32'd2, 32'd5, BR_BGE,  1'b0);
        // Unsigned: 0xFFFFFFFE lớn hơn 5 -> BLTU = 0, BGEU = 1
        check_branch("BLTU (-2_U < 5)", -32'd2, 32'd5, BR_BLTU, 1'b0);
        check_branch("BGEU (-2_U >= 5)",-32'd2, 32'd5, BR_BGEU, 1'b1);

        // -----------------------------------------------------------
        // KẾT LUẬN
        // -----------------------------------------------------------
        $display("\n==================================================");
        if (error_count == 0)
            $display(">>> PERFECT! ALL TESTS PASSED! <<<");
        else
            $display(">>> FAILED! FOUND %0d ERRORS! <<<", error_count);
        $display("==================================================\n");
        
        $finish;
    end

endmodule