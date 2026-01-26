`include "uvm_macros.svh"
import uvm_pkg::*;
import imem_pkg::*; // Import gói UVM ta vừa viết

// Định nghĩa Interface
interface imem_if (input logic clk);
    logic        rst_n;
    logic [31:0] addr;
    logic [31:0] instr;
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
        .HEX_FILE("program.hex")
    ) dut (
        .clk_i   (clk),
        .rst_ni  (vif.rst_n),
        .addr_i  (vif.addr),
        .instr_o (vif.instr)
    );

    // Block khởi chạy UVM
    initial begin
        vif.rst_n = 0;
        #20 vif.rst_n = 1;

        // Đăng ký Interface vào Config DB để Driver/Monitor tìm thấy
        uvm_config_db#(virtual imem_if)::set(null, "*", "vif", vif);

        // Chạy Test
        run_test("imem_basic_test");
    end

endmodule