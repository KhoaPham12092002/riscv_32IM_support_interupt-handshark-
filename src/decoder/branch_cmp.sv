`timescale 1ns/1ps
import riscv_32im_pkg::*;

module branch_cmp (
    input logic [31:0] rs1_i, rs2_i,
    input br_op_e br_op_i, 
    output logic branch_taken_o
    );
    logic is_equal;
    assign is_equal = (rs1_i == rs2_i);

    logic is_less_u;
    assign is_less_u = (rs1_i < rs2_i);
    
    logic is_less_s;
    logic sign1;
    logic sign2;
    assign sign1 = rs1_i[31];
    assign sign2 = rs2_i[31];
    assign is_less_s = (sign1 != sign2) ? sign1 : is_less_u;

    always_comb begin
        branch_taken_o = 1'b0;
        case (br_op_i)
            BR_BEQ: branch_taken_o = is_equal;
            BR_BNE: branch_taken_o = ~is_equal;

            BR_BLT: branch_taken_o = is_less_s;
            BR_BGE: branch_taken_o = ~is_less_s;

            BR_BLTU: branch_taken_o = is_less_u;
            BR_BGEU: branch_taken_o = ~is_less_u;
            default : branch_taken_o = 1'b0;
        endcase
    end
    endmodule