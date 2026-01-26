`timescale 1ns/1ps
import M_types_pkg::*; 

module riscv_m_unit (
    input  logic         clk,
    input  logic         rst,
    input  logic         valid,
    input  M_req_t       m_req,
    output logic [31:0]  result,
    output logic         ready,
    output logic         busy    
);

    // ========================================================================
    // 1. DECODE & SIGN LOGIC
    // ========================================================================
    logic is_div_op, is_rem_op;
    logic a_is_signed, b_is_signed;

    assign is_div_op   = (m_req.op inside {M_DIV, M_DIVU, M_REM, M_REMU});
    assign is_rem_op   = (m_req.op inside {M_REM, M_REMU});
    assign a_is_signed = (m_req.op inside {M_MUL, M_MULH, M_MULHSU, M_DIV, M_REM});
    assign b_is_signed = (m_req.op inside {M_MUL, M_MULH, M_DIV, M_REM});

    typedef enum logic [2:0] { IDLE, PREPARE, DIV_LOOP, FIX_SIGN, DONE } state_t;
    state_t state;

    // ========================================================================
    // 2. MULTIPLIER WITH D-FF (Handshaking & Safety)
    // ========================================================================
    logic [63:0] mul_res_reg;
    logic        mul_ready_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mul_res_reg <= '0;
            mul_ready_q <= 1'b0;
        end else begin
            // Chỉ bắt đầu nhân khi đang ở IDLE và chưa bận phép nhân cũ
            if (valid && !is_div_op && state == IDLE && !mul_ready_q) begin
                // Phép nhân được thực hiện và chốt vào D-FF tại cạnh lên clock
                mul_res_reg <= $signed(a_is_signed ? {m_req.a_i[31], m_req.a_i} : {1'b0, m_req.a_i}) * $signed(b_is_signed ? {m_req.b_i[31], m_req.b_i} : {1'b0, m_req.b_i});
                mul_ready_q <= 1'b1;
            end 
            // Cơ chế bắt tay: Hạ ready khi Master hạ valid
            else if (!valid) begin
                mul_ready_q <= 1'b0;
            end
        end
    end

    // ========================================================================
    // 3. DIVIDER FSM
    // ========================================================================
    logic [5:0]  count;
    logic [63:0] rem_quot_reg;
    logic [31:0] divisor_reg;
    logic        sign_q, sign_r;

    logic [31:0] adder_out;
    logic        adder_cout;
    
    // Shared Subtractor logic
    i_adder shared_adder (
        .a({rem_quot_reg[62:32], rem_quot_reg[31]}), 
        .b(divisor_reg), .carry_in(1'b1), .add_sub(1'b1), 
        .sum_dif(adder_out), .C(adder_cout)
    );

    

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; rem_quot_reg <= '0; divisor_reg <= '0;
            count <= '0; sign_q <= '0; sign_r <= '0;
        end else begin
            case (state)
                IDLE: begin
                    // Đợi valid và đảm bảo không vướng phép nhân vừa xong
                    if (valid && is_div_op && !mul_ready_q) begin
                        state  <= PREPARE;
                        sign_q <= (a_is_signed && m_req.a_i[31]) ^ (b_is_signed && m_req.b_i[31]);
                        sign_r <= (a_is_signed && m_req.a_i[31]);
                    end
                end

                PREPARE: begin
                    if (m_req.b_i == 0) begin // Corner Case: Div by Zero
                        rem_quot_reg <= {m_req.a_i, 32'hFFFFFFFF};
                        state <= DONE;
                    end else if (m_req.a_i == 32'h80000000 && m_req.b_i == 32'hFFFFFFFF && a_is_signed) begin
                        rem_quot_reg <= {32'd0, 32'h80000000};
                        state <= DONE;
                    end else begin
                        rem_quot_reg <= {32'd0, (a_is_signed && m_req.a_i[31]) ? -m_req.a_i : m_req.a_i};
                        divisor_reg  <= (b_is_signed && m_req.b_i[31]) ? -m_req.b_i : m_req.b_i;
                        count <= 32; state <= DIV_LOOP;
                    end
                end

                DIV_LOOP: begin
                    if (count > 0) begin
                        if (adder_cout) rem_quot_reg <= {adder_out, rem_quot_reg[30:0], 1'b1};
                        else            rem_quot_reg <= {rem_quot_reg[62:0], 1'b0};
                        count <= count - 1;
                    end else state <= FIX_SIGN;
                end

                FIX_SIGN: begin
                    rem_quot_reg <= { (sign_r ? -rem_quot_reg[63:32] : rem_quot_reg[63:32]),
                                      (sign_q ? -rem_quot_reg[31:0]  : rem_quot_reg[31:0]) };
                    state <= DONE;
                end

                DONE: if (!valid) state <= IDLE;
            endcase
        end
    end

    // Busy bao gồm trạng thái FSM đang chạy hoặc phép nhân đang giữ Ready
    assign busy = (state != IDLE) || mul_ready_q;

    // ========================================================================
    // 4. FINAL OUTPUT MUX
    // ========================================================================
    always_comb begin
        if (is_div_op) begin
            ready  = (state == DONE);
            result = is_rem_op ? rem_quot_reg[63:32] : rem_quot_reg[31:0];
        end else begin
            ready  = mul_ready_q;
            result = (m_req.op == M_MUL) ? mul_res_reg[31:0] : mul_res_reg[63:32];
        end
    end
endmodule