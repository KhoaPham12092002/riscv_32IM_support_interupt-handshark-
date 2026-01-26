`include "uvm_macros.svh"
import uvm_pkg::*;
import imem_pkg::*;
import memory_pkg::*;

// ---------------------------------------------------------
// Interface (Active High Reset)
// ---------------------------------------------------------
interface imem_if (input logic clk_i);
    logic        rst_i;   // Active High Reset
    logic        req_i;   
    logic [31:0] addr_i;  
    logic [31:0] instr_o; 
endinterface

module tb_top;
    logic clk;
    
    // Clock Gen
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Interface Instance
    imem_if vif(clk);

    // DUT Instance
    imem #(
        .HEX_FILE("program.hex"),
        .MEM_SIZE(4096)
    ) dut (
        .clk_i   (clk),
        .rst_i   (vif.rst_i), // <--- SỬA LẠI DÒNG NÀY (rst_ni -> rst_i)
        .req_i   (vif.req_i), 
        .addr_i  (vif.addr_i),
        .instr_o (vif.instr_o)
    );

    // --- Reset Logic (Active High: 1 là Reset, 0 là Chạy) ---
    initial begin
        // 1. Khởi tạo
        vif.rst_i  = 0; 
        vif.req_i  = 0;
        vif.addr_i = 0;

        // 2. Kích hoạt Reset (Bật lên 1)
        #10;
        vif.rst_i  = 1; // RESET ON
        #20;
        vif.rst_i  = 0; // RESET OFF (Chạy)
    end

    // UVM Start
    initial begin
        uvm_config_db#(virtual imem_if)::set(null, "*", "vif", vif);
        run_test("imem_basic_test");
    end

    // Debug Monitor
    initial begin
        $display("Time  | Rst_i | Req | Address    | Instruction");
        $display("------+-------+-----+------------+------------");
        $monitor("%4t  |   %b   |  %b  | %h   | %h", 
                 $time, vif.rst_i, vif.req_i, vif.addr_i, vif.instr_o);
    end

endmodule