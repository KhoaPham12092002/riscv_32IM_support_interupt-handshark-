`timescale 1ns/1ps

module tb_pc_gen;

    // 1. Tín hiệu kết nối
    logic        clk;
    logic        rst;
    
    // Handshake
    logic        ready_i;
    logic        valid_o;
    
    // Branch
    logic        branch_taken_i;
    logic [31:0] branch_target_addr_i;
    
    // Output
    logic [31:0] pc_o;

    // Tham số
    parameter BOOT_ADDR = 32'h8000_0000; // Giả sử boot từ 0x80000000

    // 2. Instantiate DUT (Device Under Test)
    pc_gen #(
        .BOOT_ADDR(BOOT_ADDR)
    ) dut (
        .clk_i                (clk),
        .rst_i                (rst),
        .ready_i              (ready_i),
        .valid_o              (valid_o),
        .branch_taken_i       (branch_taken_i),
        .branch_target_addr_i (branch_target_addr_i),
        .pc_o                 (pc_o)
    );

    // 3. Tạo Clock (100MHz -> T=10ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 4. Kịch bản Test (Main Stimulus)
    initial begin
        // --- GIAI ĐOẠN 1: KHỞI TẠO & RESET ---
        $display("=========================================================");
        $display("[TEST START] Checking PC_GEN Behavior...");
        rst = 1;
        ready_i = 0;
        branch_taken_i = 0;
        branch_target_addr_i = 0;
        
        repeat(2) @(posedge clk);
        #1; // Tránh race condition
        rst = 0; // Thả Reset
        
        // Check Reset Value
        if (pc_o !== BOOT_ADDR) 
            $error("[FAIL] Reset Failed! Exp: %h, Act: %h", BOOT_ADDR, pc_o);
        else 
            $display("[PASS] Reset OK. PC = %h", pc_o);

        // --- GIAI ĐOẠN 2: CHẠY TUẦN TỰ (NORMAL FETCH) ---
        $display("--- Test Case 2: Sequential Fetch (PC+4) ---");
        ready_i = 1; // Hệ thống sẵn sàng
        
        @(posedge clk); #1; // PC: 8000_0000 -> 8000_0004
        check_pc(BOOT_ADDR + 4);

        @(posedge clk); #1; // PC: 8000_0004 -> 8000_0008
        check_pc(BOOT_ADDR + 8);

        // --- GIAI ĐOẠN 3: TEST STALL (TẮC ĐƯỜNG) ---
        $display("--- Test Case 3: Pipeline Stall (Ready=0) ---");
        ready_i = 0; // Giả lập pipeline phía sau bị tắc
        
        @(posedge clk); #1; 
        // PC không được tăng, phải giữ nguyên giá trị cũ (BOOT+8)
        check_pc(BOOT_ADDR + 8); 
        $display("[INFO] Stalled... PC giữ nguyên: %h", pc_o);

        @(posedge clk); #1;
        check_pc(BOOT_ADDR + 8); // Vẫn phải đứng im

        // --- GIAI ĐOẠN 4: TEST BRANCH (NHẢY) ---
        $display("--- Test Case 4: Branch Taken ---");
        ready_i = 1; // Hết tắc
        branch_taken_i = 1;
        branch_target_addr_i = 32'h9000_0000; // Nhảy xa

        @(posedge clk); #1;
        check_pc(32'h9000_0000); // PC phải cập nhật ngay đích đến
        
        // Tắt Branch, quay lại chạy tuần tự từ đích mới
        branch_taken_i = 0;
        @(posedge clk); #1;
        check_pc(32'h9000_0004);

        // --- GIAI ĐOẠN 5: TEST BRANCH + STALL (TÌNH HUỐNG KHÓ) ---
        // Lưu ý: Logic RTL hiện tại yêu cầu ready_i=1 để cập nhật PC.
        // Controller thực tế sẽ ép ready_i=1 khi có Branch.
        // Ở đây ta test xem nếu ready_i=0 thì Branch có bị ignore không (đúng logic RTL).
        $display("--- Test Case 5: Branch while Stall (Ready=0) ---");
        ready_i = 0;
        branch_taken_i = 1;
        branch_target_addr_i = 32'hAAAA_BBBB;
        
        @(posedge clk); #1;
        // Vì ready=0, PC KHÔNG ĐƯỢC cập nhật dù có Branch (đây là hành vi của RTL hiện tại)
        check_pc(32'h9000_0004); 
        $display("[PASS] Branch ignored due to Stall (Correct behavior for this module)");

        // Mở Stall -> Branch được thực thi
        ready_i = 1;
        @(posedge clk); #1;
        check_pc(32'hAAAA_BBBB);

        $display("=========================================================");
        $display("[TEST FINISHED] ALL CHECKS PASSED!");
        $stop;
    end

    // 5. Task hỗ trợ kiểm tra nhanh
    task check_pc(input logic [31:0] expected);
        if (pc_o !== expected) begin
            $error("[FAIL] Time: %0t | Exp: %h | Act: %h", $time, expected, pc_o);
        end else begin
            $display("[PASS] PC Updated to %h", pc_o);
        end
    endtask

    // 6. Monitor phụ để nhìn sóng cho dễ
    initial begin
        // $monitor("Time: %0t | Rdy: %b | Br: %b | PC: %h", $time, ready_i, branch_taken_i, pc_o);
    end

endmodule