package decoder_pkg;

    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b0001,
        ALU_SLL  = 4'b0010,
        ALU_SLT  = 4'b0011, // Set Less Than (Signed)
        ALU_SLTU = 4'b0100, // Set Less Than Unsigned
        ALU_XOR  = 4'b0101,
        ALU_SRL  = 4'b0110,
        ALU_SRA  = 4'b0111,
        ALU_OR   = 4'b1000,
        ALU_AND  = 4'b1001,
        ALU_B    = 4'b1111  // Pass operand B (cho lệnh LUI, copy B ra output)
    } alu_op_e;     // ALU operation
    typedef enum logic [2:0] {
        M_MUL    = 3'b000,
        M_MULH   = 3'b001,
        M_MULHSU = 3'b010, 
        M_MULHU  = 3'b011, 
        M_DIV    = 3'b100,
        M_DIVU   = 3'b101,
        M_REM    = 3'b110,
        M_REMU   = 3'b111
    } m_op_e;       // M-type operation
    typedef enum logic [2:0] {
        BR_BEQ  = 3'b000,
        BR_BGE  = 3'b101,
        BR_BGEU = 3'b111,
        BR_BLT  = 3'b100,
        BR_BLTU = 3'b110,
        BR_BNE  = 3'b001
    }br_op_e;       // branch operation
    typedef enum logic [1:0] {
        MEM_BYTE = 2'b00,
        MEM_HALF = 2'b01,
        MEM_WORD = 2'b10
    } mem_width_e;  // memory width
    typedef enum logic [2:0] {
        IMM_I  = 3'b000,    // I-type : ALU Imm, Load, JALR  (12 bit signed)
        IMM_S  = 3'b001,    // S-type : Store (12 bit signed)
        IMM_B  = 3'b010,    // B-type : Branch (13 bit signed, bit 0 = 0)
        IMM_U  = 3'b011,    // U-type : LUI, AUIPC (20 bit upper)   
        IMM_J  = 3'b100,    // J-type : JAL (21 bit signed, bit 0 = 0)
        IMM_Z  = 3'b101     // Zero : R-type
    } imm_type_e;   // immediate type
    typedef enum logic  {
        OP_A_RS1 = 1'b0,
        OP_A_PC  = 1'b1
    } op_a_sel_e;   // select operand A
    typedef enum logic  {
        OP_B_RS2 = 1'b0,
        OP_B_IMM = 1'b1
    } op_b_sel_e;   // select operand B
    typedef enum logic [2:0] {
        WB_ALU      = 3'b000,      // ALU (ADD, SUB, AND...)
        WB_MEM      = 3'b001,      // Memory (LW, LH, LB...)
        WB_PC_PLUS4 = 3'b010, // (PC + 4) ( JAL, JALR)
        WB_CSR      = 3'b011,       // CSR 
        WB_M_UNIT   = 3'b100       // M-Unit (MUL, DIV...)
    } wb_sel_e;     // select source write to register 
    // =================================================================
    // 2. STRUCT DEFINITIONS (REQUEST PACKETS)
    // =================================================================     
    typedef struct packed {
        alu_op_e    op;         //  (ADD, SUB, XOR...)
        op_a_sel_e  op_a_sel;   // (RS1 or PC?)
        op_b_sel_e  op_b_sel;   // (RS2 or IMM?)
    } alu_req_t;
    typedef struct packed {
        m_op_e  op;     // (MUL, DIV, REM...)
        logic       valid;  // 1 = valid request
    } m_req_t;
    typedef struct packed {
        logic       we;           // Write Enable (1 = Store)
        logic       re;           // Read Enable (1 = Load)
        mem_width_e width;        // Byte/Half/Word
        logic       is_unsigned;  // 1 = Load Unsigned (LBU/LHU)
    } lsu_req_t;
    typedef struct packed {
        logic       is_branch;    // 1 = Branch (BEQ...)
        logic       is_jump;      // 1 = Jump (JAL/JALR)
        br_op_e     op;           // Comparison type (EQ, NE, LT...)
    } br_req_t;

    // CSR Request Packet (Placeholder - Added to fix compile error)
    typedef struct packed {
        logic       valid;
        // logic [1:0] op; // Will expand later
    } csr_req_t;
    typedef struct packed {
        // Gói tin con (Sub-packets)
        alu_req_t   alu_req;
        lsu_req_t   lsu_req;
        br_req_t    br_req;
        m_req_t     m_req;
        csr_req_t   csr_req; // (Optional: Có thể bỏ nếu chưa làm CSR)

        // Tín hiệu điều khiển cục bộ (Local Control Signals)
        imm_type_e  imm_type;      // Loại Immediate để sinh (I/S/B/U/J)
        logic       rf_we;         // Register File Write Enable (Ghi vào Rd?)
        wb_sel_e    wb_sel;        // Chọn nguồn dữ liệu ghi về Rd (Writeback)
        
        // Exception Handling
        logic       illegal_instr; // Báo lệnh không hợp lệ (Trap)
    } dec_out_t;
    typedef struct packed {
        logic [6:0]  opcode;       // Instruction Opcode
        logic [2:0]  funct3;       // Instruction funct3    
        logic [6:0]  funct7;       // Instruction funct7
        logic [11:0] funct12;      // Instruction funct12 for CSR or IMM
    } dec_in_t;
	// =================================================================
    	// 3. RESET VALUES (To avoid ENUMVALUE errors in Verilator)
    	// =================================================================
    localparam alu_req_t ALU_REQ_RST = '{
        op: ALU_ADD, 
        op_a_sel: OP_A_RS1, 
        op_b_sel: OP_B_RS2
    };

    localparam m_req_t M_REQ_RST = '{
        op: M_MUL, 
        valid: 1'b0
    };

    localparam lsu_req_t LSU_REQ_RST = '{
        we: 1'b0, 
        re: 1'b0, 
        width: MEM_BYTE, 
        is_unsigned: 1'b0
    };

    localparam br_req_t BR_REQ_RST = '{
        is_branch: 1'b0, 
        is_jump: 1'b0, 
        op: BR_BEQ
    };

    localparam csr_req_t CSR_REQ_RST = '{
        valid: 1'b0
    };
endpackage
