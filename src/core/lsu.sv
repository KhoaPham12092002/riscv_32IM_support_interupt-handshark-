import riscv_32im_pkg::*;

module lsu (
    input  logic        clk_i,
    input  logic        rst_i,

    // --- Interface with Core (ALU/Decoder) ---
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic        lsu_we_i,    // 1 = Store, 0 = Load
    input  logic [2:0]  funct3_i,    // Data type (LB, SB, etc.)
    
    // Core Handshake
    input  logic        valid_i,
    output logic        ready_o,
    output logic        valid_o,
    input  logic        ready_i,

    // --- Interface with DMEM (Kênh Đôi / Two-Channel) ---
    // 1. Kênh Yêu Cầu (Request Phase)
    output logic        dmem_req_valid_o,
    input  logic        dmem_req_ready_i,
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_be_o,
    output logic        dmem_we_o,
    
    // 2. Kênh Phản Hồi (Response Phase)
    input  logic        dmem_rsp_valid_i,
    output logic        dmem_rsp_ready_o,
    input  logic [31:0] dmem_rdata_i,

    // --- Writeback to Core (Load Data & Trap) ---
    output logic [31:0] lsu_rdata_o,
    output logic        lsu_err_o   
);

    // ==========================================
    // 1. FSM & REGISTERS
    // ==========================================
    typedef enum logic [1:0]{
        IDLE,       // Chờ tín hiệu từ Core
        SEND_REQ,   // Gửi Request sang DMEM
        WAIT_RSP,   // Chờ Response từ DMEM
        DONE        // Trả kết quả về Core
    } state_t;
    state_t state;
    
    // Registers to latch inputs
    logic [31:0] addr_q;
    logic [31:0] dmem_rdata_q;
    logic [31:0] wdata_q;
    logic [2:0]  funct3_q;
    logic        we_q;
    logic        misaligned_trap_q;

    logic misaligned; 
    
    always_comb begin
        misaligned = 1'b0; 
        case (funct3_i)
            3'b001, 3'b101: if (addr_i[0] != 1'b0) misaligned = 1'b1;     
            3'b010:         if (addr_i[1:0] != 2'b00) misaligned = 1'b1;  
            default:        misaligned = 1'b0;                            
        endcase
    end

    always_ff @(posedge clk_i or posedge rst_i) begin 
        if (rst_i) begin
            state <= IDLE;
            addr_q <= 32'b0;
            wdata_q <= 32'b0;
            funct3_q <= 3'b0;
            we_q <= 1'b0;
            misaligned_trap_q <= 1'b0;
            dmem_rdata_q <= 32'b0;
        end else begin 
            case (state)
                IDLE : begin
                    if (valid_i) begin
                        addr_q   <= addr_i;
                        wdata_q  <= wdata_i;
                        funct3_q <= funct3_i;
                        we_q     <= lsu_we_i;
                        
                        if (misaligned) begin
                            misaligned_trap_q <= 1'b1;
                            state <= DONE ;
                        end else begin
                            misaligned_trap_q <= 1'b0;
                            state <= SEND_REQ;
                        end
                    end
                end
                SEND_REQ : begin
                    // [BUG #2 FIXED]: STORE không cần Response Phase (fire-and-forget).
                    // Chỉ LOAD mới cần chờ dmem_rsp_valid_i.
                    if (dmem_req_ready_i) state <= we_q ? DONE : WAIT_RSP;
                end
                WAIT_RSP : begin
                    if (dmem_rsp_valid_i) begin
                        state <= DONE;
                        dmem_rdata_q <= dmem_rdata_i;
                    end
                end
                DONE : begin
                    if (ready_i) state <= IDLE;
                end       
            endcase
        end
    end

    // ==========================================
    // 2. DMEM INTERFACE DRIVING (OUTPUT LOGIC)
    // ==========================================
    logic [1:0] effective_offset;
    assign effective_offset = addr_q[1:0];

    assign dmem_addr_o = {addr_q[31:2], 2'b00}; 
    assign dmem_we_o = (state == SEND_REQ) & we_q;

    always_comb begin
        dmem_wdata_o = 32'b0;
        case (effective_offset)
            2'b00: dmem_wdata_o = wdata_q;
            2'b01: dmem_wdata_o = {wdata_q[23:0], 8'b0};
            2'b10: dmem_wdata_o = {wdata_q[15:0], 16'b0};
            2'b11: dmem_wdata_o = {wdata_q[7:0], 24'b0};
        endcase
    end

    always_comb begin
        dmem_be_o = 4'b0000;
        if ((state == SEND_REQ) && we_q) begin
            case (funct3_q)
                3'b000:  dmem_be_o = 4'b0001 << effective_offset; // SB
                3'b001:  dmem_be_o = 4'b0011 << effective_offset; // SH
                3'b010:  dmem_be_o = 4'b1111;                     // SW
                default: dmem_be_o = 4'b0000;
            endcase
        end
    end

    // [BUG #1 FIXED]: Đảm bảo dmem_req_valid_o được kéo lên 1 cho CẢ lệnh Đọc lẫn Ghi
    assign dmem_req_valid_o = (state == SEND_REQ);
    assign dmem_rsp_ready_o = (state == WAIT_RSP);

    // ==========================================
    // 3. CORE INTERFACE DRIVING (LOAD PATH)
    // ==========================================
    logic [7:0] ext_byte;
    always_comb begin
        case (addr_q[1:0])
            2'b00: ext_byte = dmem_rdata_q[7:0];
            2'b01: ext_byte = dmem_rdata_q[15:8];
            2'b10: ext_byte = dmem_rdata_q[23:16];
            2'b11: ext_byte = dmem_rdata_q[31:24];
        endcase
    end

    logic [15:0] ext_half;
    always_comb begin
        case (addr_q[1]) 
            1'b0: ext_half = dmem_rdata_q[15:0];
            1'b1: ext_half = dmem_rdata_q[31:16];
        endcase
    end

    always_comb begin
        lsu_rdata_o = 32'b0;
        if ((state == DONE) && !misaligned_trap_q && !we_q) begin
            case (funct3_q)
                3'b000: lsu_rdata_o = {{24{ext_byte[7]}}, ext_byte};        // LB  
                3'b100: lsu_rdata_o = {24'b0, ext_byte};                    // LBU 
                3'b001: lsu_rdata_o = {{16{ext_half[15]}}, ext_half};       // LH  
                3'b101: lsu_rdata_o = {16'b0, ext_half};                    // LHU 
                3'b010: lsu_rdata_o = dmem_rdata_q;                         // LW  
                default: lsu_rdata_o = 32'b0;
            endcase
        end
    end

    assign valid_o   = (state == DONE);
    assign ready_o   = (state == IDLE);
    assign lsu_err_o = (state == DONE) ? misaligned_trap_q : 1'b0;

endmodule