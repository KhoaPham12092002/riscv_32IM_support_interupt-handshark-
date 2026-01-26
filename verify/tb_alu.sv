
`timescale 1ns/1ps
import alu_types_pkg::*;

module tb_alu;

    // --- 1. DUT SIGNALS ---
    alu_req_t    req;
    logic        zero;
    logic [31:0] result;

    // --- 2. INSTANTIATE DUT ---
    alu dut (
        .alu_req (req),
        .Zero    (zero),
        .alu_o   (result)
    );

    // Biến đếm lỗi
    int error_count = 0;
    int test_count = 0;

    // Mảng chứa các Opcode hợp lệ để Random (Bao gồm cả ALU_B = 15)
    alu_op_e valid_ops[] = '{
        ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
        ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND, ALU_B
    };

    // --- 3. MAIN TESTING PROCESS ---
    initial begin
        $display("==========================================================");
        $display("   STARTING ROBUST RISC-V ALU VERIFICATION");
        $display("==========================================================");

        // ------------------------------------------------------------
        // PHẦN 1: DIRECTED TESTS (CÁC TRƯỜNG HỢP HIỂM HÓC)
        // ------------------------------------------------------------
        $display("\n--- [PART 1] CORNER CASES (Truong hop khac khe) ---");

        // Case 1.1: Zero Flag Check
        verify_alu(ALU_SUB, 32'd10, 32'd10, "SUB sets Zero Flag");

        // Case 1.2: Shift 0 bit
        verify_alu(ALU_SLL, 32'hDEADBEEF, 32'd0, "Shift Left by 0");

        // Case 1.3: Shift tối đa (31 bit)
        verify_alu(ALU_SLL, 32'd1, 32'd31, "Shift Left Max (31)");

        // Case 1.4: Shift quá giới hạn (33 bit -> lấy 1 bit)
        verify_alu(ALU_SRL, 32'hFFFFFFFF, 32'd33, "Shift Right Overlimit (33->1)");

        // Case 1.5: SRA với số Âm
        verify_alu(ALU_SRA, 32'hFFFFFF00, 32'd4, "SRA on Negative Number");

        // Case 1.6: Signed Comparison (SLT)
        verify_alu(ALU_SLT, -32'd1, 32'd10, "SLT: Negative < Positive");

        // Case 1.7: Unsigned Comparison (SLTU) - Số âm là số dương cực lớn
        verify_alu(ALU_SLTU, -32'd1, 32'd10, "SLTU: Max Uint > Small Uint");

        // Case 1.8: BUG TRAP (Test case sát thủ phát hiện lỗi cộng/trừ)
        // 20 < 10 là SAI -> Kết quả phải là 0.
        // Nếu mạch làm phép CỘNG (20+10=30), kết quả sẽ khác logic so sánh.
        verify_alu(ALU_SLTU, 32'd20, 32'd10, "SLTU Logic Trap: 20 < 10 (Must be 0)");

        // Case 1.9: Test ALU_B (Pass through)
        verify_alu(ALU_B, 32'h12345678, 32'hAABBCCDD, "ALU_B Pass Through");

        // ------------------------------------------------------------
        // PHẦN 2: RANDOMIZED TESTS
        // ------------------------------------------------------------
        $display("\n--- [PART 2] RANDOM REGRESSION (Chay 1000 lenh ngau nhien) ---");

repeat (100000) begin
            // 1. Khai báo biến tĩnh (Giữ nguyên vỏ hộp)
            static logic [31:0] rand_a;
            static logic [31:0] rand_b;
            static int rand_idx;
            static alu_op_e rand_op;
            
            // 2. Gán giá trị mới (Thực hiện mỗi vòng lặp)
            rand_a   = $urandom();
            rand_b   = $urandom();
            rand_idx = $urandom_range(0, $size(valid_ops)-1);
            rand_op  = valid_ops[rand_idx];

            verify_alu(rand_op, rand_a, rand_b, "Random Case");
        end
        // --- FINAL REPORT ---
        $display("\n==========================================================");
        if (error_count == 0) begin
            $display("   VICTORY! ALL %0d TESTS PASSED.", test_count);
            $display("   Your ALU is Solid Rock!");
        end else begin
            $display("   FAILURE! FOUND %0d ERRORS.", error_count);
        end
        $display("==========================================================");

        if (error_count > 0) $stop; else $finish;
    end

    // =================================================================
    // TASK: GOLDEN MODEL & CHECKER
    // =================================================================
    task verify_alu(input alu_op_e op_in, input [31:0] a_in, input [31:0] b_in, input string msg);
        logic [31:0] expected_res;
        logic        expected_zero;

        // 1. Setup Input
        req.op = op_in;
        req.a  = a_in;
        req.b  = b_in;

        // 2. Golden Model Logic
        case (op_in)
            ALU_ADD:  expected_res = a_in + b_in;
            ALU_SUB:  expected_res = a_in - b_in;
            ALU_SLL:  expected_res = a_in << b_in[4:0];
            ALU_SRL:  expected_res = a_in >> b_in[4:0];
            ALU_SRA:  expected_res = $signed(a_in) >>> b_in[4:0];
            ALU_SLT:  expected_res = ($signed(a_in) < $signed(b_in)) ? 32'd1 : 32'd0;
            ALU_SLTU: expected_res = (a_in < b_in) ? 32'd1 : 32'd0;
            ALU_XOR:  expected_res = a_in ^ b_in;
            ALU_OR:   expected_res = a_in | b_in;
            ALU_AND:  expected_res = a_in & b_in;
            ALU_B:    expected_res = b_in; // Pass through B
            default:  expected_res = 32'b0;
        endcase

        expected_zero = (expected_res == 0);

        // 3. Wait & Check
        #5;
        test_count++;

        if (result !== expected_res || zero !== expected_zero) begin
            $error("[FAIL] %s", msg);
            $display("   OP: %s | A: %h | B: %h", op_in.name(), a_in, b_in);
            $display("   Expect: %h (Z=%b)", expected_res, expected_zero);
            $display("   Got   : %h (Z=%b)", result, zero);
            error_count++;
        end else begin
            // Chỉ in PASS cho các corner cases (Part 1) để đỡ rối mắt
            if (test_count <= 20)
                $display("[PASS] %s - Result: %h", msg, result);
        end
    endtask

endmodule
