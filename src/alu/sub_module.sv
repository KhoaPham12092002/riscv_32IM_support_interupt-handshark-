// ============================================================================
// MODULES CON (i_adder...) - GIỮ NGUYÊN NHƯ CŨ
// ============================================================================

module full_adder_1_bit (
    input  logic a, b, cin, add_sub,
    output logic sum_dif, p, g
);
    logic b_inv;
    assign b_inv = b ^ add_sub; 
    assign g = a & b_inv;
    assign p = a ^ b_inv;
    assign sum_dif = p ^ cin;
endmodule

module carry_block_4bits (
    input  logic        carry_in,
    input  logic [3:0] p, g,
    output logic [3:0] cin_out,
    output logic        cout, P_out, G_out
);
    assign cin_out[0] = carry_in;
    assign cin_out[1] = g[0] | (p[0] & cin_out[0]);
    assign cin_out[2] = g[1] | (p[1] & g[0]) | (p[1] & p[0] & cin_out[0]);
    assign cin_out[3] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & cin_out[0]);
    
    assign G_out = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);
    assign P_out = &p; 
    assign cout  = G_out | (P_out & carry_in);
endmodule

module i_adder (
    input  logic [31:0] a, b,
    input  logic        carry_in, add_sub,
    output logic [31:0] sum_dif,
    output logic        C, V 
); 
    logic [31:0] p, g, cin;
    logic [7:0]  P_blk, G_blk, C_blk;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_fa
            full_adder_1_bit fa_inst (
                .a(a[i]), .b(b[i]), .cin(cin[i]), .add_sub(add_sub),
                .sum_dif(sum_dif[i]), .p(p[i]), .g(g[i])
            );
        end
    endgenerate

    genvar j;
    generate
        for (j = 0; j < 8; j = j + 1) begin : gen_cla
            carry_block_4bits cla_inst (
                .carry_in( (j == 0) ? carry_in : C_blk[j-1] ),
                .p(p[j*4+3 : j*4]), 
                .g(g[j*4+3 : j*4]),
                .cin_out(cin[j*4+3 : j*4]),
                .cout(C_blk[j]),
                .P_out(P_blk[j]),
                .G_out(G_blk[j])
            );
        end
    endgenerate

    assign C = C_blk[7];
    assign V = C_blk[7] ^ cin[31]; 

endmodule

module  alu_shift_inst (
       input logic [31:0] a_i, //data in 1
       input logic [31:0] b_i, //data in 2
       input logic [1:0]   shift_type_i, //00 SLL, 01 SRL, 10 SRA
       output logic [31:0] result_o
    );
// ====================================================
    localparam [1:0] TYPE_SLL = 2'b00;
    localparam [1:0] TYPE_SRL = 2'b01;
    localparam [1:0] TYPE_SRA = 2'b10;
// ====================================================
    logic [31:0] stage_1, stage_2, stage_3, stage_4; // only 4 stage because final stage is output
    logic [4:0] shift_amount;
    assign shift_amount = b_i[4:0]; // only need lower 5 bits   
    // Stage 1: shift by 1
    always_comb begin
        // Stage 1: shift by 1
        case (shift_type_i)
            TYPE_SLL: stage_1 = (shift_amount[0]) ? {a_i[30:0], 1'b0} : a_i; // SLL
            TYPE_SRL: stage_1 = (shift_amount[0]) ? {1'b0, a_i[31:1]} : a_i; // SRL
            TYPE_SRA: stage_1 = (shift_amount[0]) ? {a_i[31], a_i[31:1]} : a_i; // SRA
            default: stage_1 = a_i;
        endcase
        // Stage 2: shift by 2
        case (shift_type_i)
            TYPE_SLL: stage_2 = (shift_amount[1]) ? {stage_1[29:0], 2'b00} : stage_1; // SLL
            TYPE_SRL: stage_2 = (shift_amount[1]) ? {2'b00, stage_1[31:2]} : stage_1; // SRL
            TYPE_SRA: stage_2 = (shift_amount[1]) ? { {2{stage_1[31]}}, stage_1[31:2]} : stage_1; // SRA
            default: stage_2 = stage_1; 
        endcase
        // Stage 3: shift by 4      
        case (shift_type_i)
            TYPE_SLL: stage_3 = (shift_amount[2]) ? {stage_2[27:0], 4'b0000} : stage_2; // SLL
            TYPE_SRL: stage_3 = (shift_amount[2]) ? {4'b0000, stage_2[31:4]} : stage_2; // SRL
            TYPE_SRA: stage_3 = (shift_amount[2]) ? { {4{stage_2[31]}}, stage_2[31:4]} : stage_2; // SRA
            default: stage_3 = stage_2; 
        endcase
        // Stage 4: shift by 8
        case (shift_type_i)
            TYPE_SLL: stage_4 = (shift_amount[3]) ? {stage_3[23:0], 8'b00000000} : stage_3; // SLL
            TYPE_SRL: stage_4 = (shift_amount[3]) ? {8'b00000000, stage_3[31:8]} : stage_3; // SRL
            TYPE_SRA: stage_4 = (shift_amount[3]) ? { {8{stage_3[31]}}, stage_3[31:8]} : stage_3; // SRA
            default: stage_4 = stage_3;
        endcase
        // Final Stage: shift by 16
        case (shift_type_i)
            TYPE_SLL: result_o = (shift_amount[4]) ? {stage_4[15:0], 16'b0000000000000000} : stage_4; // SLL
            TYPE_SRL: result_o = (shift_amount[4]) ? {16'b0000000000000000, stage_4[31:16]} : stage_4; // SRL
            TYPE_SRA: result_o = (shift_amount[4]) ? { {16{stage_4[31]}}, stage_4[31:16]} : stage_4; // SRA
            default: result_o = stage_4;       
        endcase     
    end

  endmodule
  