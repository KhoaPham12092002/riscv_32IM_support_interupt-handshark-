module tb_pc_gen;

    // 1. Signals
    logic        clk_i;
    logic        rst_i;
    logic        stall_i;
    logic        branch_taken_i;
    logic [31:0] branch_target_i;
    logic [31:0] pc_o;

    // 2. Instantiate DUT (Device Under Test)
    pc_gen #(
        .BOOT_ADDR(32'h0000_1000) // Test boot address khác 0
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i),
        .branch_taken_i(branch_taken_i),
        .branch_target_addr_i(branch_target_i),
        .pc_o(pc_o)
    );

    // 3. Clock Generation (50MHz -> T=20ns)
    initial begin
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // 4. Test Scenario
    initial begin
        // Setup Monitor
        $monitor("Time: %0t | PC: %h | Stall: %b | Br_Taken: %b | Target: %h", 
                 $time, pc_o, stall_i, branch_taken_i, branch_target_i);

        // --- TEST CASE 1: RESET ---
        $display("--- TC1: Reset Check ---");
        rst_i = 1; // Active High Reset
        stall_i = 0; branch_taken_i = 0; branch_target_i = 0;
        #30; 
        rst_i = 0; // Release Reset
        #10;
        // Expect: PC = 1000

        // --- TEST CASE 2: NORMAL OPERATION ---
        $display("--- TC2: Normal Increment (PC+4) ---");
        #20; // Chạy vài cycle: 1000 -> 1004 -> 1008

        // --- TEST CASE 3: BRANCHING ---
        $display("--- TC3: Branch to 0x5000 ---");
        branch_target_i = 32'h0000_5000;
        branch_taken_i = 1;
        #20; // PC should be 5000
        branch_taken_i = 0; // Release branch
        #20; // PC should be 5004

        // --- TEST CASE 4: STALL ---
        $display("--- TC4: Stall at %h ---", pc_o);
        stall_i = 1;
        #60; // PC must hold value for 3 cycles
        stall_i = 0;
        #20; // PC continues

        // --- TEST CASE 5: PRIORITY CHECK (STALL vs BRANCH) ---
        $display("--- TC5: Stall vs Branch (Stall must win) ---");
        stall_i = 1;
        branch_taken_i = 1;
        branch_target_i = 32'hDEAD_BEEF; // Địa chỉ bẫy
        #40; 
        // Nếu PC = DEAD_BEEF -> CODE SAI. PC phải giữ giá trị cũ.
        
        $display("--- TEST FINISHED ---");
        $finish;
    end

endmodule
