package riscv_32im_pkg;

// 1. SYSTEM CONSTANTS & CONFIGURATION
    
    localparam int XLEN = 32;
    localparam int IMEM_SIZE_BYTES = 4096;  // 4KB
    localparam int DMEM_SIZE_BYTES = 4096;  // 4KB
    parameter logic [31:0] BOOT_ADDR = 32'h0000_0000; // address boot PC
    parameter type T_DATA = logic [31:0] // Dùng Parameter type của reg pipeline_reg



    // --- Memory Map Constants ---
    // Instruction Memory (0x0000_0000 - 0x0FFF_FFFF)
    localparam logic [31:0] MAP_IMEM_BASE = 32'h0000_0000;
    localparam logic [31:0] MAP_IMEM_MASK = 32'hF000_0000;

    // Data Memory (0x2000_0000 - 0x2FFF_FFFF)
    localparam logic [31:0] MAP_DMEM_BASE = 32'h2000_0000;
    localparam logic [31:0] MAP_DMEM_MASK = 32'hF000_0000; 

    // Peripherals / IO (0x4000_0000 - 0x4FFF_FFFF)
    localparam logic [31:0] MAP_IO_BASE   = 32'h4000_0000;
    localparam logic [31:0] MAP_IO_MASK   = 32'hF000_0000;

    // External SDRAM (0x6000_0000 - 0x6FFF_FFFF)
    localparam logic [31:0] MAP_SDRAM_BASE = 32'h6000_0000;
    localparam logic [31:0] MAP_SDRAM_MASK = 32'hF000_0000;

// 2. ENUMERATIONS (DEFINITIONS)
    
    // --- ALU Operations ---
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
        ALU_B    = 4'b1111  // Pass Operand B (LUI)
    } alu_op_e;

    // --- M-Extension Operations (Mul/Div) ---
    typedef enum logic [2:0] {
        M_MUL    = 3'b000,
        M_MULH   = 3'b001,
        M_MULHSU = 3'b010, 
        M_MULHU  = 3'b011, 
        M_DIV    = 3'b100,
        M_DIVU   = 3'b101,
        M_REM    = 3'b110,
        M_REMU   = 3'b111
    } m_op_e;

    // --- Branch Operations ---
    typedef enum logic [2:0] {
        BR_BEQ  = 3'b000,
        BR_BNE  = 3'b001,
        BR_BLT  = 3'b100,
        BR_BGE  = 3'b101,
        BR_BLTU = 3'b110,
        BR_BGEU = 3'b111
    } br_op_e;

    // --- Memory Operations ---
    typedef enum logic [1:0] {
        MEM_BYTE = 2'b00,
        MEM_HALF = 2'b01,
        MEM_WORD = 2'b10
    } mem_width_e;

    // --- Immediate Types ---
    typedef enum logic [2:0] {
        IMM_I  = 3'b000,    // I-type : ALU Imm, Load, JALR  (12 bit signed)
        IMM_S  = 3'b001,    // S-type : Store (12 bit signed)
        IMM_B  = 3'b010,    // B-type : Branch (13 bit signed, bit 0 = 0)
        IMM_U  = 3'b011,    // U-type : LUI, AUIPC (20 bit upper)   
        IMM_J  = 3'b100,    // J-type : JAL (21 bit signed, bit 0 = 0)
        IMM_Z  = 3'b101     // Zero : R-type    
        } imm_type_e;

    // --- Mux Selects ---
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

    // --- Device Selection ---
    typedef enum logic [1:0] {
        DEV_IMEM  = 2'b00,
        DEV_DMEM  = 2'b01,
        DEV_IO    = 2'b10,
        DEV_SDRAM = 2'b11,
        DEV_NONE  = 2'bxx // Trạng thái lỗi hoặc không chọn gì
    } dev_sel_t;

    // --- Peripheral Addresses (Offsets) ---
    typedef enum logic [15:0] {
        ADDR_GPIO           = 16'h0000,
        ADDR_SEGMENTS       = 16'h0001,
        ADDR_UART           = 16'h0002,
        ADDR_ADC            = 16'h0003,
        ADDR_I2C            = 16'h0004,
        ADDR_TIMER          = 16'h0005,
        
        ADDR_DIF_FIL        = 16'h0008,
        ADDR_STEP_MOT       = 16'h0009,
        ADDR_LCD            = 16'h000A,
        ADDR_NN_ACCEL       = 16'h000B,
        
        ADDR_FIR_FIL        = 16'h000D,
        ADDR_KEY            = 16'h000E,
        ADDR_CRC            = 16'h000F,
        
        ADDR_SPWM           = 16'h0011,
        ADDR_ACCEL          = 16'h0012,
        ADDR_CORDIC         = 16'h0015,
        ADDR_RS485          = 16'h0017,
        ADDR_RGB            = 16'h0020,
        
        ADDR_UNKNOWN        = 16'hxxxx // Cho các trường hợp default
    } periph_addr_t;

// 3. STRUCT DEFINITIONS (DATA PAYLOADS)
 
    
    // --- Instruction Formats (Moved here for global visibility) ---
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

    // --- Execution Requests ---
    
    // ALU Request
    typedef struct packed {
        alu_op_e    op;
        op_a_sel_e  op_a_sel;
        op_b_sel_e  op_b_sel;
    } alu_req_t;

    // M-Unit Request
    typedef struct packed {
        m_op_e      op;
        logic       valid;  // 1 = valid request
    } m_req_t;

    // LSU Request
    typedef struct packed {
        logic       we;           // Write Enable (1 = Store)
        logic       re;           // Read Enable (1 = Load)
        mem_width_e width;        // Byte/Half/Word
        logic       is_unsigned;  // 1 = Load Unsigned (LBU/LHU)
    } lsu_req_t;

    // Branch Request
    typedef struct packed {
        logic       is_branch;    // 1 = Branch (BEQ...)
        logic       is_jump;      // 1 = Jump (JAL/JALR)
        br_op_e     op;           // Comparison type (EQ, NE, LT...)
    } br_req_t;

    // CSR Request
    typedef struct packed {
        logic       valid;
        logic       we; // Write enable to CSR
        logic [11:0] addr;
    } csr_req_t;

    // --- CONTROL BUS (Decoder Output) ---
    typedef struct packed {
        alu_req_t   alu_req;
        lsu_req_t   lsu_req;
        br_req_t    br_req;
        m_req_t     m_req;
        csr_req_t   csr_req;

        // Tín hiệu điều khiển cục bộ (Local Control Signals)
        imm_type_e  imm_type;
        logic       rf_we;
        wb_sel_e    wb_sel;
        // Exception Handling
        logic       illegal_instr;
    } dec_out_t;

// 4. TYPE INPUT FOR MODULE
    typedef struct packed {
        logic [31:0] a;     // Operand A
        logic [31:0] b;     // Operand B
        alu_op_e     op;    // Operation Code
        logic valid_i;       // Input Valid Signal
        logic ready_i;       // Input Ready Signal
    }alu_in_t;

    typedef struct packed {
        logic [31:0]  a_i; //rs1
        logic [31:0]  b_i; //sr2
        m_op_e        op;  // opcode
    } m_in_t; // M-type request
// 5. RESET VALUES
    localparam alu_req_t ALU_REQ_RST = '{op: ALU_ADD, op_a_sel: OP_A_RS1, op_b_sel: OP_B_RS2};
    localparam m_req_t   M_REQ_RST   = '{op: M_MUL, valid: 1'b0};
    localparam lsu_req_t LSU_REQ_RST = '{we: 1'b0, re: 1'b0, width: MEM_BYTE, is_unsigned: 1'b0};
    localparam br_req_t  BR_REQ_RST  = '{is_branch: 1'b0, is_jump: 1'b0, op: BR_BEQ};
    localparam csr_req_t CSR_REQ_RST = '{valid: 1'b0, we: 1'b0, addr: 12'b0};

// 6. HELPER FUNCTIONS

    function automatic dev_sel_t decode_address(input logic [31:0] addr);
        if      ((addr & MAP_IMEM_MASK)  == MAP_IMEM_BASE)  return DEV_IMEM;
        else if ((addr & MAP_DMEM_MASK)  == MAP_DMEM_BASE)  return DEV_DMEM;
        else if ((addr & MAP_IO_MASK)    == MAP_IO_BASE)    return DEV_IO;
        else if ((addr & MAP_SDRAM_MASK) == MAP_SDRAM_BASE) return DEV_SDRAM;
        else                                                return DEV_NONE;
    endfunction

endpackage