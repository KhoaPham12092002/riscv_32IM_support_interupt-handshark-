`include "uvm_macros.svh"
import uvm_pkg::*;
import imem_pkg::*; // Import gói UVM ta vừa viết
import riscv_32im_pkg::*;

// Định nghĩa Interface
interface imem_if (input logic clk);
    logic rst_i;
// ==========================================
    // 1. KÊNH REQUEST (Yêu cầu đọc lệnh từ PC_Gen)
    // ==========================================
    logic        req_valid_i;  // Master (PC) báo có địa chỉ hợp lệ
    logic        req_ready_o;  // Slave (IMEM) báo sẵn sàng nhận địa chỉ
    logic [31:0] req_addr_i;   // Giá trị địa chỉ PC (32-bit)

    // ==========================================
    // 2. KÊNH RESPONSE (Trả lệnh về cho Decoder)
    // ==========================================
    logic        rsp_valid_o;  // Slave (IMEM) báo đã lấy được lệnh ra khỏi RAM
    logic        rsp_ready_i;  // Master (Decoder) báo sẵn sàng nhận lệnh
    logic [31:0] rsp_instr_o;  // Dữ liệu
    endinterface

module tb_top;
    logic clk;
    
    // Tạo Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Instance Interface
    imem_if vif(clk);

    // Instance DUT (Device Under Test)
    imem #(
        .HEX_FILE("new_code.hex"),
        .MEM_SIZE(riscv_32im_pkg::IMEM_SIZE_BYTES)
    ) dut (
        .clk_i   (clk),
        .rst_i  (vif.rst_i),
        // --- Kênh Request ---
        .req_valid_i (vif.req_valid_i),
        .req_ready_o (vif.req_ready_o),
        .req_addr_i  (vif.req_addr_i),
        
        // --- Kênh Response ---
        .rsp_valid_o (vif.rsp_valid_o),
        .rsp_ready_i (vif.rsp_ready_i),
        .rsp_instr_o (vif.rsp_instr_o)
    );

    // Block khởi chạy UVM
    initial begin
        vif.rst_i = 1'b1;
        #20; 
        vif.rst_i = 1'b0;
    end

    initial begin
        // Đăng ký Interface vào Config DB để Driver/Monitor tìm thấy
        uvm_config_db#(virtual imem_if)::set(null, "*", "vif", vif);

        // Chạy Test
        run_test("imem_basic_test");
    end

endmodule