`timescale 1ns/1ps

module tb_soc_simple;
    logic clk;
    logic rst;
    wire [31:0] debug_pc;

    // Instance của SoC Top
    soc_top u_soc (
        .clk_i      (clk),
        .rst_i      (rst),
        .debug_pc_o (debug_pc)
    );

    // Clock 100MHz
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        #50 rst = 0;
        
        // Tăng thời gian mô phỏng lên để kịp chạy hết chương trình
        #200000; 
        $display("Done simulation.");
        $stop;
    end

    // --- DEBUG SPY (Đã sửa đường dẫn thành u_soc.u_core) ---
    always @(posedge clk) begin
        // Quan sát tín hiệu Writeback nằm sâu trong u_soc -> u_core
        if (u_soc.u_core.mem_wb_valid_o && u_soc.u_core.mem_wb_ready_i && u_soc.u_core.mem_wb_out.ctrl.rf_we) begin
            if (u_soc.u_core.mem_wb_out.rd_addr != 0) begin
                $display("[SOC-LOG] Time: %0t | PC: %h | Write x%0d = %h (Dec: %0d)", 
                         $time, 
                         u_soc.u_core.mem_wb_out.pc_plus4,
                         u_soc.u_core.mem_wb_out.rd_addr, 
                         u_soc.u_core.wb_final_data,
                         $signed(u_soc.u_core.wb_final_data));
                /*$display("[SOC-LOG] Time: %0t | PC: %h | Write x%0d = %h (Dec: %0d)", 
                $time, 
                u_soc.debug_pc_o, // <--- SỬA THÀNH CÁI NÀY CHO CHẮC
                u_soc.u_core.mem_wb_out.rd_addr, 
                u_soc.u_core.wb_final_data,
                $signed(u_soc.u_core.wb_final_data));*/
            end
        end
    end

endmodule