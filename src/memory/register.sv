`timescale 1ns/1ps

module register (
    input  logic        clk_i,
    input  logic        rst_i,         
    
    // (Write Port) - From Write Back (WB)
    input  logic        w_ena_i,       
    input  logic [4:0]  w_addr_i,   
    input  logic [31:0] w_data_i_i,      

    // (Read Ports) - Output data immediately to Execute (EX)
    input  logic [4:0]  r1_addr_i,  
    output logic [31:0] r1_data_o,     
    
    input  logic [4:0]  r2_addr_i,  
    output logic [31:0] r2_data_o      
);

    // --- (32 register 32-bit) ---
    logic [31:0] rf [31:0];
    //x0 always = 0.
    logic w_ena_prot;
    assign w_ena_prot = (w_addr_i == 5'd0) ? 1'b0 : w_ena_i;

    // (Synchronous Write) ghi dữ liệu (xung clock cạnh lên)
    always_ff @(posedge clk_i ) begin
        if (rst_i) begin
            // reset
            for (int i = 0; i < 32; i++) begin
                rf[i] <= 32'h0;
            end
        end else if (w_ena_prot) begin
            rf[w_addr_i] <= w_data_i;
        end
    end

    // (Asynchronous Read) đọc dữ liệu
    // đọc không đợi clock.
    assign r1_data_o = (r1_addr_i == 5'd0) ? 32'h0 : rf[r1_addr_i];
    assign r2_data_o = (r2_addr_i == 5'd0) ? 32'h0 : rf[r2_addr_i];
 // hoạt động như một bộ nhớ 3 cổng (1W/2R
endmodule
