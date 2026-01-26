`timescale 1ns/1ps

module register (
    input  logic        clk_i,
    input  logic        rst_i,         
    
    // (Write Port) - From Write Back (WB)
    input  logic        w_ena_i,       
    input  logic [4:0]  w_address_i,   
    input  logic [31:0] w_data,      

    // (Read Ports) - Output data immediately to Execute (EX)
    input  logic [4:0]  r1_address_i,  
    output logic [31:0] r1_data_o,     
    
    input  logic [4:0]  r2_address_i,  
    output logic [31:0] r2_data_o      
);

    // --- (32 register 32-bit) ---
    logic [31:0] rf [31:0];
    //x0 always = 0.
    logic w_ena_prot;
    assign w_ena_prot = (w_address_i == 5'd0) ? 1'b0 : w_ena_i;

    // (Synchronous Write) ghi dữ liệu (xung clock cạnh lên)
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            // reset
            for (int i = 0; i < 32; i++) begin
                rf[i] <= 32'h0;
            end
        end else if (w_ena_prot) begin
            rf[w_address_i] <= w_data;
        end
    end

    // (Asynchronous Read) đọc dữ liệu
    // đọc không đợi clock.
    assign r1_data_o = (r1_address_i == 5'd0) ? 32'h0 : rf[r1_address_i];
    assign r2_data_o = (r2_address_i == 5'd0) ? 32'h0 : rf[r2_address_i];
 // hoạt động như một bộ nhớ 3 cổng (1W/2R
endmodule
