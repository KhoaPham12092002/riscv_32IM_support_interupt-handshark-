`timescale 1ns/1ps
//import riscv_32im_pkg::*;
module pc_gen (
    input  logic        clk_i,
    input  logic        rst_i,

    // --- Handshake Interface (Back-pressure) ---
    // ready_i = 1: Hệ thống (IMEM + Pipeline) sẵn sàng nhận lệnh mới.
    // ready_i = 0: Pipeline bị Stall (Tắc), PC phải đứng im.
    input  logic        ready_i,    
    output logic        valid_o,    // Luôn = 1 (PC Gen luôn muốn lấy lệnh)

    // --- Branch Interface (From EX Stage) ---
    input  logic        branch_taken_i,       // 1 = Lệnh nhảy thực thi thành công
    input  logic [31:0] branch_target_addr_i, // Địa chỉ đích của lệnh nhảy

    // --- Trap/Interrupt Interface (Placeholder for Future) ---
    // Mở comment phần này khi làm xong CSR/Controller
    /*
    input  logic        trap_taken_i,         // 1 = Có ngắt hoặc ngoại lệ (Trap/Interrupt)
    input  logic [31:0] trap_target_addr_i,   // Địa chỉ vector ngắt (mtvec)
    */

    // --- Output PC ---
    output logic [31:0] pc_o
);

    // Internal Signals
    logic [31:0] pc_q;
    logic [31:0] pc_next;

    // ========================================================================
    // 1. NEXT PC LOGIC (Priority Encoder)
    // ========================================================================
    // Xác định địa chỉ tiếp theo dựa trên độ ưu tiên:
    // Trap > Branch > Sequential (PC+4)
    
    always_comb begin
        // --- LEVEL 1: TRAP/INTERRUPT (Highest Priority) ---
        // Khi có ngắt, ta phải nhảy ngay lập tức, bất chấp lệnh Branch.
        /* if (trap_taken_i) begin
            pc_next = trap_target_addr_i;
        end 
        else 
        */
        
        // --- LEVEL 2: BRANCH/JUMP (From Execute Stage) ---
        // Nếu không có ngắt, kiểm tra xem lệnh hiện tại có phải Branch lấy hay không
        if (branch_taken_i) begin
            pc_next = branch_target_addr_i;
        end 
        
        // --- LEVEL 3: SEQUENTIAL (Default) ---
        // Tăng PC lên 4 byte để lấy lệnh tiếp theo
        else begin
            pc_next = pc_q + 32'd4;
        end
    end

    // ========================================================================
    // 2. PC REGISTER UPDATE (Sequential Logic)
    // ========================================================================
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            pc_q <= 32'h0000_0000; // Hoặc BOOT_ADDR
        end else begin
            // ƯU TIÊN TUYỆT ĐỐI: Nếu có lệnh nhảy (branch_taken), 
            // bắt buộc cập nhật PC ngay lập tức, bỏ qua mọi lý do trì hoãn (ready_i).
            // Nếu không nhảy, thì mới tuân thủ luật Handshake (ready_i).
            if (ready_i) begin 
                pc_q <= pc_next;
            end
        end
    end

    // ========================================================================
    // 3. OUTPUT ASSIGNMENT
    // ========================================================================
    assign pc_o    = pc_q;
    assign valid_o = 1'b1; // PC Gen luôn available trừ khi Reset

endmodule