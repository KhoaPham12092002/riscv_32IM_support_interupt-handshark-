import riscv_32im_pkg::*;

module alu (
    input  alu_in_t         alu_in,
    output logic Zero,
    output logic  [31:0]      alu_o,
    output logic        vaild_o,
    output logic        ready_o
    );
// INTERNAL SIGNALS
    // (Adder/Subtractor)
    logic        is_sub;        // signal sub
    logic [31:0] adder_o ;     
    logic        cout, v_flag;  // Carry , Overflow 

    //  (Shifters)
    logic [31:0] shift_o;       
    logic [1:0] shift_type;
    always_comb begin
        case (alu_in.op)
            ALU_SLL: shift_type = 2'b00; // SLL
            ALU_SRL: shift_type = 2'b01; // SRL
            ALU_SRA: shift_type = 2'b10; // SRA
            default: shift_type = 2'b00; // Mặc định
        endcase
    end      
   
    assign is_sub = (alu_in.op == ALU_SUB) ||
                    (alu_in.op == ALU_SLT) ||
                    (alu_in.op == ALU_SLTU);
// POSITIONAL MAPPING MODULE
    i_adder adder_inst (
        alu_in.a,   //  a
        alu_in.b,   // b
        is_sub,       // carry_in (Sub = 1, Add = 0)
        is_sub,       // add_sub  (Mode control)
        adder_o,    // Output result
        cout,         // Carry Out
        v_flag        // Overflow
    );

    alu_shift_inst shift_inst (
        alu_in.a,            // data in 1
        alu_in.b[4:0],      // shift amount from lower 5 bits of operand B
        shift_type,             // shift type: 00 SLL
        shift_o              // result
    );
    always_comb begin
        case (alu_in.op)
            // Math
            ALU_ADD:  alu_o = adder_o;
            ALU_SUB:  alu_o = adder_o;

            // Shift bit
            ALU_SLL:  alu_o = shift_o;
            ALU_SRL:  alu_o = shift_o;
            //  SRA: Shift Right Arithmetic
            ALU_SRA:  alu_o = shift_o;

            // Set Less Than
            ALU_SLT:  alu_o = {31'd0, (adder_o[31] ^ v_flag)};
            ALU_SLTU: alu_o = {31'd0, (~cout)};
            // Logic
            ALU_XOR:  alu_o = alu_in.a ^ alu_in.b;
            ALU_OR:   alu_o = alu_in.a | alu_in.b;
            ALU_AND:  alu_o = alu_in.a & alu_in.b;
            // Pass through B (LUI instruction support if needed)
            ALU_B:    alu_o = alu_in.b;
            default:  alu_o = 32'b0;
        endcase
    end
    assign Zero = (alu_o == 32'b0);
// Cờ Carry và Overflow (dư ra, chưa dùng tới trong ALU này nhưng cần thì sài)

endmodule
