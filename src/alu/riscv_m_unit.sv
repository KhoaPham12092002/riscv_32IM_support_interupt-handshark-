`timescale 1ns/1ps
import riscv_32im_pkg::*; 

module riscv_m_unit (
    input  logic         clk,
    input  logic         rst,

    // --- Upstream Interface ---
    input  logic         valid_i,
    output logic         ready_o,
    input  m_in_t        m_in,

    // --- Downstream Interface ---
    output logic         valid_o,
    input  logic         ready_i,
    output logic [31:0]  result_o
);

    // ========================================================================
    // 1. SIGNALS & REGISTERS
    // ========================================================================
    typedef enum logic [2:0] { IDLE, PREPARE, DIV_LOOP, FIX_SIGN, DONE } state_t;
    state_t state;

    // Registers
    m_op_e       op_q;
    logic [63:0] result_reg;
    logic [31:0] divisor_reg;
    logic [5:0]  count;
    logic        sign_q, sign_r;
    logic        div_by_zero_q; 

    // Helper Signals
    logic is_div_op, a_is_signed, b_is_signed;
    logic [32:0] mul_op_a, mul_op_b;
    logic [65:0] mul_res_full;

    // Khai báo tín hiệu tổ hợp cho phép chia (Sửa lỗi BLKSEQ)
    logic [63:0] shifted_reg;
    logic [32:0] diff_val;
    logic [63:0] next_result_div;

    // ========================================================================
    // 2. COMBINATIONAL LOGIC
    // ========================================================================
    assign is_div_op   = (m_in.op inside {M_DIV, M_DIVU, M_REM, M_REMU});
    assign a_is_signed = (m_in.op inside {M_MUL, M_MULH, M_MULHSU, M_DIV, M_REM});
    assign b_is_signed = (m_in.op inside {M_MUL, M_MULH, M_DIV, M_REM});

    assign mul_op_a = a_is_signed ? {m_in.rs1_data[31], m_in.rs1_data} : {1'b0, m_in.rs1_data};
    assign mul_op_b = b_is_signed ? {m_in.rs2_data[31], m_in.rs2_data} : {1'b0, m_in.rs2_data};
    assign mul_res_full = $signed(mul_op_a) * $signed(mul_op_b);

    // Mạch toán học tổ hợp cho phép chia Restoring
    assign shifted_reg = {result_reg[62:0], 1'b0};
    assign diff_val    = {1'b0, shifted_reg[63:32]} - {1'b0, divisor_reg};

    always_comb begin
        next_result_div = shifted_reg;
        if (diff_val[32] == 0) begin // Nếu kết quả phép trừ không âm
            next_result_div[63:32] = diff_val[31:0];
            next_result_div[0]     = 1'b1;
        end
    end

    // ========================================================================
    // 3. MAIN FSM
    // ========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            result_reg <= '0; divisor_reg <= '0; count <= '0;
            op_q <= M_MUL; sign_q <= 0; sign_r <= 0;
            div_by_zero_q <= 0;
        end else begin
            case (state)
                IDLE: begin
                    div_by_zero_q <= 0;
                    if (valid_i) begin
                        op_q <= m_in.op;
                        if (is_div_op) begin
                            state <= PREPARE;
                            sign_q <= (a_is_signed && m_in.rs1_data[31]) ^ (b_is_signed && m_in.rs2_data[31]);
                            sign_r <= (a_is_signed && m_in.rs1_data[31]);
                            result_reg  <= {32'd0, (a_is_signed && m_in.rs1_data[31]) ? -m_in.rs1_data : m_in.rs1_data};
                            divisor_reg <= (b_is_signed && m_in.rs2_data[31]) ? -m_in.rs2_data : m_in.rs2_data;
                        end else begin
                            result_reg <= mul_res_full[63:0];
                            state      <= DONE;
                        end
                    end
                end

                PREPARE: begin
                    if (divisor_reg == 0) begin
                        result_reg    <= {result_reg[31:0], 32'hFFFFFFFF};
                        div_by_zero_q <= 1'b1;
                        state         <= FIX_SIGN; 
                    end else begin
                        count <= 32;
                        state <= DIV_LOOP;
                    end
                end

                DIV_LOOP: begin
                    // Sử dụng tín hiệu tổ hợp đã tính sẵn ở bên ngoài (Sửa lỗi BLKSEQ)
                    result_reg <= next_result_div;
                    
                    if (count == 1) state <= FIX_SIGN;
                    else            count <= count - 1;
                end

                FIX_SIGN: begin
                    logic [31:0] q_final, r_final;
                    q_final = result_reg[31:0];
                    r_final = result_reg[63:32];

                    if (sign_q && !div_by_zero_q) q_final = -q_final;
                    if (sign_r) r_final = -r_final;

                    result_reg <= {r_final, q_final};
                    state      <= DONE;
                end

                DONE: begin
                    if (ready_i) state <= IDLE;
                end

                // Bắt buộc phải có default cho FSM phần cứng (Sửa lỗi CASEINCOMPLETE)
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    // ========================================================================
    // 4. OUTPUT LOGIC
    // ========================================================================
    assign valid_o = (state == DONE);
    assign ready_o = (state == IDLE);

    always_comb begin
        result_o = '0;
        if (state == DONE) begin
            case (op_q)
                M_MUL:    result_o = result_reg[31:0];
                M_MULH, M_MULHSU, M_MULHU: result_o = result_reg[63:32];
                M_DIV, M_DIVU: result_o = result_reg[31:0];
                M_REM, M_REMU: result_o = result_reg[63:32];
                default:  result_o = '0;
            endcase
        end
    end

endmodule