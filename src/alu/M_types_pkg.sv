package M_types_pkg;
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

    typedef struct packed {
        logic [31:0]  a_i; //rs1
        logic [31:0]  b_i; //sr2
        m_op_e        op;  // opcode
    } M_req_t; // M-type request
endpackage