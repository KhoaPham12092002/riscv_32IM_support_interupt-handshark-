package decoder_pkg;

    // =================================================================
    // 1. Intruction data
    // =================================================================
    // --- ENUM CHO WRITEBACK MUX  ---
    typedef enum logic [2:0] {
        WB_ALU  = 3'b000, // ALU Result
        WB_IMM  = 3'b001, // LUI
        WB_PC4  = 3'b011, // JAL/JALR
        WB_MEM  = 3'b100, // Load Memory
        WB_CSR  = 3'b101  // CSR Read
    } wb_mux_t;
    // Record for instruction decoding
    typedef struct packed {
        logic [6:0]  opcode;  // [6:0]
        logic [2:0]  funct3;  // [14:12]
        logic [6:0]  funct7;  // [31:25]
        logic [11:0] funct12; // [31:20]
    } opcodes_t;

    // Record for memory controller
    typedef struct packed {
        logic        read;       // Memory read signal
        logic        write;      // Memory write signal
        logic        signal_ext; // Signal extension
        logic        bus_lag;    // Active when another cycle is needed
        logic [1:0]  word_size;  // "00": word, "01": half word, "11": byte
    } mem_ctrl_t;

    // Record for control flow instructions
    typedef struct packed {
        logic        inc;        // PC increment
        logic        load;       // PC load
        logic [1:0]  load_from;  // "00": pc + j_imm
    } jumps_ctrl_t;

    // Record for cpu state
    typedef struct packed {
        logic        halted;     // CPU is halted (ebreak)
        logic        error;      // Error state
    } cpu_state_t;

    // =================================================================
    // Define Opcodes 
    // =================================================================

    // Arithmetic Type R
    localparam logic [6:0] TYPE_R         = 7'b0110011;
    localparam logic [2:0] TYPE_ADD_SUB   = 3'b000;
    localparam logic [6:0] TYPE_ADD       = 7'b0000000;
    localparam logic [6:0] TYPE_SUB       = 7'b0100000;
    localparam logic [2:0] TYPE_SLL       = 3'b001;
    localparam logic [2:0] TYPE_SLT       = 3'b010;
    localparam logic [2:0] TYPE_SLU       = 3'b011; // SLTU
    localparam logic [2:0] TYPE_XOR       = 3'b100;
    localparam logic [2:0] TYPE_OR        = 3'b110;
    localparam logic [2:0] TYPE_AND       = 3'b111;

    // M Extension (Multiplication/Division)
    localparam logic [6:0] TYPE_MULDIV    = 7'b0000001;
    localparam logic [2:0] TYPE_MUL       = 3'b000;
    localparam logic [2:0] TYPE_MULH      = 3'b001;
    localparam logic [2:0] TYPE_MULHU     = 3'b010;
    localparam logic [2:0] TYPE_MULHSU    = 3'b011;
    localparam logic [2:0] TYPE_DIV       = 3'b100;
    localparam logic [2:0] TYPE_DIVU      = 3'b101;
    localparam logic [2:0] TYPE_REM       = 3'b110;
    localparam logic [2:0] TYPE_REMU      = 3'b111;

    // Arithmetic Type I
    localparam logic [6:0] TYPE_I         = 7'b0010011;
    localparam logic [2:0] TYPE_ADDI      = 3'b000;
    localparam logic [2:0] TYPE_SLTI      = 3'b010;
    localparam logic [2:0] TYPE_SLTIU     = 3'b011;
    localparam logic [2:0] TYPE_XORI      = 3'b100;
    localparam logic [2:0] TYPE_ORI       = 3'b110;
    localparam logic [2:0] TYPE_ANDI      = 3'b111;
    localparam logic [2:0] TYPE_SLLI      = 3'b001;
    localparam logic [2:0] TYPE_SR        = 3'b101; // Logic for SRLI/SRAI
    localparam logic [6:0] TYPE_SRLI      = 7'b0000000;
    localparam logic [6:0] TYPE_SRAI      = 7'b0100000;

    // Branch Type B
    localparam logic [6:0] TYPE_BRANCH    = 7'b1100011;
    localparam logic [2:0] TYPE_BEQ       = 3'b000;
    localparam logic [2:0] TYPE_BNE       = 3'b001;
    localparam logic [2:0] TYPE_BLT       = 3'b100;
    localparam logic [2:0] TYPE_BGE       = 3'b101;
    localparam logic [2:0] TYPE_BLTU      = 3'b110;
    localparam logic [2:0] TYPE_BGEU      = 3'b111;

    // Memory Type S (Store)
    localparam logic [6:0] TYPE_S          = 7'b0100011;
    localparam logic [2:0] TYPE_SB         = 3'b000;
    localparam logic [2:0] TYPE_SH         = 3'b001;
    localparam logic [2:0] TYPE_SW         = 3'b010;

    // Memory Type L (Load)
    localparam logic [6:0] TYPE_L          = 7'b0000011;
    localparam logic [2:0] TYPE_LB         = 3'b000;
    localparam logic [2:0] TYPE_LH         = 3'b001;
    localparam logic [2:0] TYPE_LW         = 3'b010;
    localparam logic [2:0] TYPE_LBU        = 3'b100;
    localparam logic [2:0] TYPE_LHU        = 3'b101;

    // Jumps
    localparam logic [6:0] TYPE_JAL        = 7'b1101111;
    localparam logic [6:0] TYPE_JALR       = 7'b1100111;

    // Special Type U
    localparam logic [6:0] TYPE_LUI        = 7'b0110111;
    localparam logic [6:0] TYPE_AUIPC      = 7'b0010111;

    // System / CSR
    localparam logic [6:0] TYPE_ENV_BREAK_CSR = 7'b1110011;
    localparam logic [2:0] TYPE_EBREAK_ECALL  = 3'b000;
    localparam logic [2:0] TYPE_CSRRW         = 3'b001;
    localparam logic [2:0] TYPE_CSRRS         = 3'b010;
    localparam logic [2:0] TYPE_CSRRC         = 3'b011;
    localparam logic [2:0] TYPE_CSRRWI        = 3'b101;
    localparam logic [2:0] TYPE_CSRRSI        = 3'b110;
    localparam logic [2:0] TYPE_CSRRCI        = 3'b111;
    
    localparam logic [6:0]  TYPE_EBREAK       = 7'b0000001;
    localparam logic [11:0] TYPE_MRET         = 12'b001100000010;

endpackage