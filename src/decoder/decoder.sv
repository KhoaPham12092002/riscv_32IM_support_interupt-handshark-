module decoder 
import decoder_pkg::*;
(
    input logic [31:0]        instr_i,
    output dec_out_t          ctrl_o,   
    output logic [31:0]        imm_o,
    output logic [4:0]       rd_addr_o,
    output logic [4:0]       rs1_addr_o,
    output logic [4:0]       rs2_addr_o
);
// 1. INSTRUCTION SLICING (Internal Data Types)
    // R-Type: Register-Register (ADD, SUB, SLL...)
    typedef struct packed {
        logic [6:0] funct7;
        logic [4:0] rs2;
        logic [4:0] rs1;
        logic [2:0] funct3;
        logic [4:0] rd;
        logic [6:0] opcode;
    } r_type_t;

    // I-Type: Immediate (ADDI, SLTI, ANDI...)
    typedef struct packed {
        logic [11:0]    imm;
        logic [4:0]     rs1;    
        logic [2:0]     funct3;
        logic [4:0]     rd;
        logic [6:0]     opcode;
    } i_type_t;

    // S-Type: Store (SW, SH, SB)
    typedef struct packed {
        logic [6:0]     imm_11_5;
        logic [4:0]     rs2;
        logic [4:0]     rs1;
        logic [2:0]     funct3;
        logic [4:0]     imm_4_0;
        logic [6:0]     opcode;
    } s_type_t;

    // B-Type: Branch (BEQ, BNE, BLT...)
    typedef struct packed {
        logic           imm_12;
        logic [5:0]     imm_10_5;
        logic [4:0]     rs2;
        logic [4:0]     rs1;
        logic [2:0]     funct3;
        logic [3:0]     imm_4_1;
        logic           imm_11;
        logic [6:0]     opcode;
    } b_type_t;

    // U-Type: LUI, AUIPC
    typedef struct packed {
        logic [19:0]    imm_31_12;
        logic [4:0]     rd;
        logic [6:0]     opcode;
    } u_type_t;

    // J-Type: JAL
    typedef struct packed {
        logic           imm_20;
        logic [9:0]     imm_10_1;
        logic           imm_11;
        logic [7:0]     imm_19_12;
        logic [4:0]     rd;
        logic [6:0]     opcode;
    } j_type_t;
    // UNION of all instruction types
    typedef union packed {
        r_type_t    r_type;
        i_type_t    i_type;
        s_type_t    s_type;
        b_type_t    b_type;
        u_type_t    u_type;
        j_type_t    j_type;
        logic [31:0] raw;
    } instr_t;

    instr_t instr; 
    assign instr.raw = instr_i;
    
    // assign input to BUS
    assign rd_addr_o   = instr.r_type.rd;
    assign rs1_addr_o  = instr.r_type.rs1;
    assign rs2_addr_o  = instr.r_type.rs2;  

// 2.MAIN CONTROL DECODER 
    always_comb begin
	// Default Assignments 
        ctrl_o.illegal_instr = 1'b0;
        ctrl_o.imm_type      = IMM_I;
        ctrl_o.rf_we        = 1'b0;
        ctrl_o.wb_sel       = WB_ALU;
	// Reset sub-packets to 0
	ctrl_o.alu_req = ALU_REQ_RST;
	ctrl_o.m_req   = M_REQ_RST;
	ctrl_o.lsu_req = LSU_REQ_RST;
	ctrl_o.br_req  = BR_REQ_RST;
    // Instruction Decoding
    casez (instr.raw)
        // GROUP 1: UPPER IMMEDIATE (U-Type)
            LUI: begin
                ctrl_o.imm_type = IMM_U;    
                ctrl_o.rf_we    = 1'b1; // Ghi vào Rd
                ctrl_o.wb_sel   = WB_ALU; 

                //  Logic: ALU Result = 0 + Immediate (Pass B)
                ctrl_o.alu_req.op        = ALU_B;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1; // RS1 = 0
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM; // B = IMM
            end
            // AUIPC: Add Upper Imm to PC (Rd = PC + (Imm << 12))
            AUIPC: begin
                ctrl_o.imm_type = IMM_U;    
                ctrl_o.rf_we    = 1'b1; // Ghi vào Rd
                ctrl_o.wb_sel   = WB_ALU; 

                // Logic: ALU Result = PC + Immediate (Pass A and B)
                ctrl_o.alu_req.op        = ALU_ADD;
                ctrl_o.alu_req.op_a_sel  = OP_A_PC;    // A = PC
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;   // B = IMM
            end
        // GROUP 2: ARITHMETIC & LOGIC (I-Type)
            // ALU IMMEDIATE INSTRUCTIONS    
            // ADDI : Add Immediate (Rd = Rs1 + Imm)
            ADDI: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 + Immediate
                ctrl_o.alu_req.op        = ALU_ADD;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
            // SLTI: Set Less Than Immediate (Signed)
            SLTI: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = (Rs1 < Immediate) ? 1 : 0
                ctrl_o.alu_req.op        = ALU_SLT;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
            // SLTIU: Set Less Than Immediate (Unsigned)
            SLTIU: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = (Rs1 < Immediate) ? 1 : 0
                ctrl_o.alu_req.op        = ALU_SLTU;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
            // ANDI : AND Immediate
            ANDI: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 & Immediate
                ctrl_o.alu_req.op        = ALU_AND;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
            // ORI : OR Immediate
            ORI: begin  
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 | Immediate
                ctrl_o.alu_req.op        = ALU_OR;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
            // XORI : XOR Immediate
            XORI: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 ^ Immediate
                ctrl_o.alu_req.op        = ALU_XOR;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
            // SLLI : Shift Left Logical Immediate
            SLLI: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 << shamt
                ctrl_o.alu_req.op        = ALU_SLL;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
            // SRLI : Shift Right Logical Immediate
            SRLI: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 >> shamt (logical)
                ctrl_o.alu_req.op        = ALU_SRL;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
            // SRAI : Shift Right Arithmetic Immediate
            SRAI: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 >> shamt (arithmetic)
                ctrl_o.alu_req.op        = ALU_SRA;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
            // LOAD INSTRUCTIONS
            // LB : Load Byte (sign-extended)
            LB: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_MEM;
                // Address Rs1 + Imm_11_0
                ctrl_o.alu_req.op        = ALU_ADD;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
                // Logic: Load Byte from Memory
                ctrl_o.lsu_req.width = MEM_BYTE;
                ctrl_o.lsu_req.is_unsigned = 1'b0;
                ctrl_o.lsu_req.re   = 1'b1;
            end
            // LBU : Load Byte Unsigned
            LBU: begin
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_MEM;
                // Address Rs1 + Imm_11_0
                ctrl_o.alu_req.op        = ALU_ADD;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
                // Logic: Load Byte from Memory
                ctrl_o.lsu_req.width = MEM_BYTE;
                ctrl_o.lsu_req.is_unsigned = 1'b1;
                ctrl_o.lsu_req.re   = 1'b1;
            end
            // LH : Load Halfword (sign-extended)
            LH: begin 
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_MEM;
                // Address Rs1 + Imm_11_0
                ctrl_o.alu_req.op        = ALU_ADD;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
                // Logic: Load Halfword from Memory
                ctrl_o.lsu_req.width = MEM_HALF;
                ctrl_o.lsu_req.is_unsigned = 1'b0;
                ctrl_o.lsu_req.re   = 1'b1;
            end
            // LHU : Load Halfword Unsigned
            LHU: begin  
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_MEM;
                // Address Rs1 + Imm_11_0
                ctrl_o.alu_req.op        = ALU_ADD;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
                // Logic: Load Halfword from Memory
                ctrl_o.lsu_req.width = MEM_HALF;
                ctrl_o.lsu_req.is_unsigned = 1'b1;
                ctrl_o.lsu_req.re   = 1'b1;
            end 
            //LW : Load Word
            LW: begin   
                ctrl_o.imm_type = IMM_I;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_MEM;
                // Address Rs1 + Imm_11_0
                ctrl_o.alu_req.op        = ALU_ADD;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
                // Logic: Load Word from Memory
                ctrl_o.lsu_req.width = MEM_WORD;
                ctrl_o.lsu_req.is_unsigned = 1'b1;
                ctrl_o.lsu_req.re   = 1'b1;
            end
            // JALR : Jump and Link Register -> PC = Rs1 + Imm, Rd = PC + 4
            JALR: begin
            ctrl_o.imm_type = IMM_I;
            ctrl_o.br_req.is_jump       = 1'b1;
            ctrl_o.br_req.is_branch     = 1'b0;
            ctrl_o.rf_we    = 1'b1; // Ghi PC + 4 vào Rd
            ctrl_o.wb_sel   = WB_PC_PLUS4;
            // Logic: ALU Result = Rs1 + Immediate (for target address)
            ctrl_o.alu_req.op        = ALU_ADD;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            end
        // GROUP 3: ARITHMETIC & LOGIC (R-Type)
            // ADD : Add  (Rd = Rs1 + Rs2)
            ADD: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 + Rs2
                ctrl_o.alu_req.op        = ALU_ADD;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
            // SUB : Subtract (Rd = Rs1 - Rs2)
            SUB: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 - Rs2
                ctrl_o.alu_req.op        = ALU_SUB;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
            // SLT: Set Less Than  (Signed)
            SLT: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = (Rs1 < Rs2) ? 1 : 0
                ctrl_o.alu_req.op        = ALU_SLT;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
            // SLTU: Set Less Than  (Unsigned)
            SLTU: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = (Rs1 < Rs2) ? 1 : 0
                ctrl_o.alu_req.op        = ALU_SLTU;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
            // AND : AND 
            AND: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 & Rs2
                ctrl_o.alu_req.op        = ALU_AND;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
            // OR : OR 
            OR: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 | Rs2
                ctrl_o.alu_req.op        = ALU_OR;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
            // XOR : XOR Immediate
            XOR: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 ^ Rs2
                ctrl_o.alu_req.op        = ALU_XOR;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
            // SLL : Shift Left Logical Immediate
            SLL: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 << shamt
                ctrl_o.alu_req.op        = ALU_SLL;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
            // SRL : Shift Right Logical Immediate
            SRL: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 >> shamt (logical)
                ctrl_o.alu_req.op        = ALU_SRL;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
            // SRA : Shift Right Arithmetic Immediate
            SRA: begin
                ctrl_o.imm_type = IMM_Z;
                ctrl_o.rf_we    = 1'b1;
                ctrl_o.wb_sel   = WB_ALU;

                // Logic: ALU Result = Rs1 >> shamt (arithmetic)
                ctrl_o.alu_req.op        = ALU_SRA;
                ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
                ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
        // GROUP 4: BRANCH INSTRUCTIONS (B-Type)
        // BEQ : Branch if Equal
        BEQ: begin
            ctrl_o.imm_type = IMM_B;
            ctrl_o.br_req.op = BR_BEQ;
            ctrl_o.rf_we    = 1'b0; // Không ghi vào Rd
            ctrl_o.br_req.is_branch     = 1'b1; 
            ctrl_o.br_req.is_jump       = 1'b0;
            // Logic: ALU Result = Rs1 - Rs2 (for comparison)
            ctrl_o.alu_req.op        = ALU_SUB;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
        // BNE : Branch if Not Equal
        BNE: begin
            ctrl_o.imm_type = IMM_B;
            ctrl_o.br_req.op = BR_BNE;
            ctrl_o.rf_we    = 1'b0; // Không ghi vào Rd
            ctrl_o.br_req.is_branch     = 1'b1;
            ctrl_o.br_req.is_jump       = 1'b0;
            // Logic: ALU Result = Rs1 - Rs2 (for comparison)
            ctrl_o.alu_req.op        = ALU_SUB;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
        // BLT : Branch if Less Than (Signed)
        BLT: begin
            ctrl_o.imm_type = IMM_B;
            ctrl_o.br_req.op = BR_BLT;
            ctrl_o.rf_we    = 1'b0; // Không ghi vào Rd
            ctrl_o.br_req.is_branch     = 1'b1;
            ctrl_o.br_req.is_jump       = 1'b0;
            // Logic: ALU Result = Rs1 - Rs2 (for comparison)
            ctrl_o.alu_req.op        = ALU_SLT;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
        // BLTU : Branch if Less Than (Unsigned)
        BLTU: begin
            ctrl_o.imm_type = IMM_B;
            ctrl_o.br_req.op = BR_BLTU;
            ctrl_o.rf_we    = 1'b0; // Không ghi vào Rd
            ctrl_o.br_req.is_branch     = 1'b1;
            ctrl_o.br_req.is_jump       = 1'b0;
            // Logic: ALU Result = Rs1 - Rs2 (for comparison)
            ctrl_o.alu_req.op        = ALU_SLTU;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
        // BGE : Branch if Greater Than or Equal (Signed)
        BGE: begin
            ctrl_o.imm_type = IMM_B;
            ctrl_o.br_req.op = BR_BGE;
            ctrl_o.rf_we    = 1'b0; // Không ghi vào Rd
            ctrl_o.br_req.is_branch     = 1'b1;
            ctrl_o.br_req.is_jump       = 1'b0;
            // Logic: ALU Result = Rs1 - Rs2 (for comparison)
            ctrl_o.alu_req.op        = ALU_SLT;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
        // BGEU : Branch if Greater Than or Equal (Unsigned)
        BGEU: begin
            ctrl_o.imm_type = IMM_B;
            ctrl_o.br_req.op = BR_BGEU;
            ctrl_o.rf_we    = 1'b0; // Không ghi vào Rd
            ctrl_o.br_req.is_branch     = 1'b1;
            ctrl_o.br_req.is_jump       = 1'b0;
            // Logic: ALU Result = Rs1 - Rs2 (for comparison)
            ctrl_o.alu_req.op        = ALU_SLTU;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_RS2;
            end
        // GROUP 5: JUMP INSTRUCTIONS (J-Type & I-Type)
        // JAL : Jump and Link -> PC = PC+ Imm, Rd = PC + 4
        JAL: begin
            ctrl_o.imm_type = IMM_J;
            ctrl_o.br_req.is_jump       = 1'b1;
            ctrl_o.br_req.is_branch     = 1'b0;
            ctrl_o.rf_we                = 1'b1; // Ghi PC + 4 vào Rd
            ctrl_o.wb_sel               = WB_PC_PLUS4;
            ctrl_o.br_req.is_jump       = 1'b1;
            // Logic: ALU Result = PC + Immediate (for target address)
            ctrl_o.alu_req.op        = ALU_ADD;
            ctrl_o.alu_req.op_a_sel  = OP_A_PC;
            ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
        end
        // GROUP 6: STORE INSTRUCTIONS (S-Type)
        // SB : Store Byte
        SB: begin
            ctrl_o.imm_type = IMM_S;
            ctrl_o.rf_we    = 1'b0; // Không ghi vào Rd
            // Address Rs1 + Imm_11_0
            ctrl_o.alu_req.op        = ALU_ADD;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            // Logic: Store Byte to Memory
            ctrl_o.lsu_req.width = MEM_BYTE;
            ctrl_o.lsu_req.we   = 1'b1;
        end
        // SH : Store Halfword
        SH: begin
            ctrl_o.imm_type = IMM_S;
            ctrl_o.rf_we    = 1'b0; // Không ghi vào Rd
            // Address Rs1 + Imm_11_0
            ctrl_o.alu_req.op        = ALU_ADD;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            // Logic: Store Halfword to Memory
            ctrl_o.lsu_req.width = MEM_HALF;
            ctrl_o.lsu_req.we   = 1'b1;
        end
        // SW : Store Word
        SW: begin
            ctrl_o.imm_type = IMM_S;
            ctrl_o.rf_we    = 1'b0; // Không ghi vào Rd
            // Address Rs1 + Imm_11_0
            ctrl_o.alu_req.op        = ALU_ADD;
            ctrl_o.alu_req.op_a_sel  = OP_A_RS1;
            ctrl_o.alu_req.op_b_sel  = OP_B_IMM;
            // Logic: Store Word to Memory
            ctrl_o.lsu_req.width = MEM_WORD;
            ctrl_o.lsu_req.we   = 1'b1;
        end
        // GROUP 7: MULTIPLY & DIVIDE (R-Type)
        // MUL : Multiply (Rd = Rs1 * Rs2)
        MUL: begin
            ctrl_o.imm_type = IMM_Z;
            ctrl_o.rf_we    = 1'b1;
            ctrl_o.wb_sel   = WB_M_UNIT;

            // Logic: MULDIV Result = Rs1 * Rs2
            ctrl_o.m_req.op        = M_MUL;
            ctrl_o.m_req.valid     = 1'b1;
        end
        // MULH : Multiply High (Signed)
        MULH: begin
            ctrl_o.imm_type = IMM_Z;
            ctrl_o.rf_we    = 1'b1;
            ctrl_o.wb_sel   = WB_M_UNIT;

            // Logic: MULDIV Result = high 32 bits of (Rs1 * Rs2)
            ctrl_o.m_req.op        = M_MULH;
            ctrl_o.m_req.valid     = 1'b1;
        end
        // MULHU : Multiply High Unsigned
        MULHU: begin
            ctrl_o.imm_type = IMM_Z;
            ctrl_o.rf_we    = 1'b1;
            ctrl_o.wb_sel   = WB_M_UNIT;

            // Logic: MULDIV Result = high 32 bits of (Rs1 * Rs2)
            ctrl_o.m_req.op        = M_MULHU;
            ctrl_o.m_req.valid     = 1'b1;
        end 
        // MULHSU : Multiply High Signed-Unsigned
        MULHSU: begin
            ctrl_o.imm_type = IMM_Z;
            ctrl_o.rf_we    = 1'b1;
            ctrl_o.wb_sel   = WB_M_UNIT;

            // Logic: MULDIV Result = high 32 bits of (Rs1 * Rs2)
            ctrl_o.m_req.op        = M_MULHSU;
            ctrl_o.m_req.valid     = 1'b1;
        end
        // DIV : Divide (Rd = Rs1 / Rs2)
        DIV: begin
            ctrl_o.imm_type = IMM_Z;
            ctrl_o.rf_we    = 1'b1;
            ctrl_o.wb_sel   = WB_M_UNIT;

            // Logic: MULDIV Result = Rs1 / Rs2
            ctrl_o.m_req.op        = M_DIV;
            ctrl_o.m_req.valid     = 1'b1;
        end
        // DIVU : Divide Unsigned (Rd = Rs1 / Rs2)
        DIVU: begin
            ctrl_o.imm_type = IMM_Z;
            ctrl_o.rf_we    = 1'b1;
            ctrl_o.wb_sel   = WB_M_UNIT;

            // Logic: MULDIV Result = Rs1 / Rs2
            ctrl_o.m_req.op        = M_DIVU;
            ctrl_o.m_req.valid     = 1'b1;
        end
        // REM : Remainder (Rd = Rs1 % Rs2)
        REM: begin
            ctrl_o.imm_type = IMM_Z;
            ctrl_o.rf_we    = 1'b1;
            ctrl_o.wb_sel   = WB_M_UNIT;

            // Logic: MULDIV Result = Rs1 % Rs2
            ctrl_o.m_req.op        = M_REM;
            ctrl_o.m_req.valid     = 1'b1;
        end
        // REMU : Remainder Unsigned (Rd = Rs1 % Rs2)
        REMU: begin 
            ctrl_o.imm_type = IMM_Z;
            ctrl_o.rf_we    = 1'b1;
            ctrl_o.wb_sel   = WB_M_UNIT;

            // Logic: MULDIV Result = Rs1 % Rs2
            ctrl_o.m_req.op        = M_REMU;
            ctrl_o.m_req.valid     = 1'b1;
        end 
        default: begin
            ctrl_o.illegal_instr = 1'b1; // Báo lệnh không hợp lệ (Trap)
        end
    endcase
    end
// 3. IMMEDIATE GENERATION
    always_comb begin
        unique case (ctrl_o.imm_type)
            IMM_I: imm_o = {{20{instr.i_type.imm[11]}}, instr.i_type.imm};
            IMM_S: imm_o = {{20{instr.s_type.imm_11_5[6]}}, instr.s_type.imm_11_5, instr.s_type.imm_4_0};
            IMM_B: imm_o = {{19{instr.b_type.imm_12}}, instr.b_type.imm_12, instr.b_type.imm_11, instr.b_type.imm_10_5, instr.b_type.imm_4_1, 1'b0};
            IMM_U: imm_o = {instr.u_type.imm_31_12, 12'b0};
            IMM_J: imm_o = {{11{instr.j_type.imm_20}}, instr.j_type.imm_20, instr.j_type.imm_19_12, instr.j_type.imm_11, instr.j_type.imm_10_1, 1'b0};
            IMM_Z: imm_o = 32'b0;
            default: imm_o = 32'b0;
        endcase
    end        
endmodule
