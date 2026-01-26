package alu_types_pkg;

    // 1. ALU Operation Codes (Giữ nguyên logic của bạn, rất tốt)
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
    } alu_op_e;

    // 2. Struct dữ liệu (Bỏ signed để linh hoạt)
    typedef struct packed {
        logic [31:0] a;     // Operand A
        logic [31:0] b;     // Operand B
        alu_op_e     op;    // Operation Code
    } alu_req_t;

    // 3. MUX SELECT DEFINITIONS (Chuẩn Pipeline Datapath)
    
    // Nguồn cho Operand A của ALU
    typedef enum logic {
        OP_A_REG = 1'b0,    // Lấy từ Register File (rs1)
        OP_A_PC  = 1'b1     // Lấy từ PC (Cho lệnh AUIPC, JAL, Branch)
    } op_a_sel_e;

    // Nguồn cho Operand B của ALU
    typedef enum logic {
        OP_B_REG = 1'b0,    // Lấy từ Register File (rs2) - R-type
        OP_B_IMM = 1'b1     // Lấy từ Immediate Gen - I-type, S-type, U-type
    } op_b_sel_e;

    // 4. Writeback Mux (Ghi gì vào thanh ghi rd?)
    typedef enum logic [1:0] {
        WB_ALU  = 2'b00,    // Kết quả tính toán ALU
        WB_MEM  = 2'b01,    // Dữ liệu đọc từ RAM (Load)
        WB_PC4  = 2'b10     // PC + 4 (Cho lệnh JAL/JALR để lưu địa chỉ trả về)
    } wb_sel_e;

endpackage