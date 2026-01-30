import riscv_32im_pkg::*;
module lsu (
    input  logic        clk_i,
    input  logic        rst_i,

    // Interface with Core
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic        lsu_we_i,    // 1 = Store
    input  logic [2:0]  funct3_i,    // Data type (LB, SB, etc.)
    // Interface handshark
    input  logic        valid_i,
    output logic        ready_o,
    output logic        valid_o,
    input  logic        ready_i ,
    // Interface with DMEM
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_be_o,
    output logic        dmem_we_o,
    input  logic [31:0] dmem_rdata_i,

    // Writeback to Core (Load Data)
    output logic [31:0] lsu_rdata_o,
    
   // Output for trap 
    output logic lsu_err_o  

);
    //FSM
    typedef enum logic [1:0]{
        IDLE,       // PHASE WAIT SIGNAL FORM EX
        WAIT_MEM,   // WAIT MEMORY RESPONSE 1 CYCLE LATENCY
        DONE       // OUT PUT
    } state_t;
    state_t state;
    
    // register save information Request
    logic [31:0] addr_q;
    logic [2:0]  funct3_q;
    logic        we_q;
    logic        misaligned_trap_q; // Lưu trạng thái lỗi

    // Combinational
    logic [1:0] addr_offset;
    assign addr_offset = addr_i[1:0]; //(00, 01, 10, 11)
    logic misaligned;	// để check số lẽ 
    
//  STORE PATH (CPU -> MEM)
    // check lỗi miss aligned 
        always_comb begin
            misaligned = 1'b0; // Mặc định là OK
            case (funct3_i)
                3'b001, 3'b101: begin // SH, LH, LHU (16-bit)
                    // Yêu cầu: Địa chỉ phải chẵn (bit cuối = 0)
                    if (addr_i[0] != 1'b0) misaligned = 1'b1;
                end
            
                3'b010: begin // SW, LW (32-bit)
                    // Yêu cầu: Địa chỉ chia hết cho 4 (2 bit cuối = 00)
                    if (addr_i[1:0] != 2'b00) misaligned = 1'b1;
                end
            
                default: misaligned = 1'b0; // Byte (LB, SB) luôn luôn đúng
            endcase
        end

    // Xuất tín hiệu lỗi ra ngoài
// MAIN FSM (CONTROLLER)
    always_ff @(posedge clk_i or posedge rst_i) begin 
        if (rst_i) begin
            state <= IDLE;
            addr_q <= 32'b0;
            funct3_q <= 1'b0;
            we_q <= 1'b0;
            misaligned_trap_q <= 1'b0;
        end else begin 
            case (state)
                IDLE : begin
                    if (valid_i) begin
                        addr_q      <= addr_i;
                        funct3_q    <= funct3_i;
                        we_q        <= lsu_we_i;
                        // check error
                        if (misaligned) begin
                            misaligned_trap_q <= 1'b1;
                            state <= DONE ;
                        end else begin
                            misaligned_trap_q <= 1'b0;
                            state <=    WAIT_MEM;
                        end
                    end
                end
                WAIT_MEM : begin
                    state <= DONE ;
                end
                DONE : begin
                    if (ready_i) begin
                    state <= IDLE;
                    end
                end
            endcase
        end
    end
    // DMEM INTERFACE DRIVING (OUTPUT LOGIC)
        // INPUT DMEM address : IDLE: addr_i, WAIT: addr_q 
        logic [31:0] effective_addr;
        assign effective_addr = (state == IDLE) ? addr_i : addr_q;
        logic [1:0]  effective_offset;
        assign effective_offset = effective_addr[1:0];

        assign dmem_addr_o = {effective_addr[31:2], 2'b00}; // Word Aligned
    // Chỉ bật Write Enable khi đang ở IDLE và có Valid Request (và không lỗi)
    logic trigger_access;
    assign trigger_access = (state == IDLE) && valid_i && !misaligned;
    
    // DMEM Write Enable:
    assign dmem_we_o = trigger_access & lsu_we_i;
    
    // DMEM Write Data: Dịch dữ liệu đến đúng ngăn
    assign dmem_wdata_o = wdata_i << (effective_offset * 8);
    
    // DMEM Byte Enable
    always_comb begin
        dmem_be_o = 4'b0000;
        if (trigger_access && lsu_we_i )  begin
            case (funct3_i)
                3'b000: begin // SB (Store Byte)
                   dmem_be_o = 4'b0001 << effective_offset; 
                end

                3'b001: begin // SH (Store Half)
                   dmem_be_o = 4'b0011 << effective_offset; 
                end

                3'b010: begin // SW (Store Word)
                    dmem_be_o = 4'b1111;
                end
                
                default: dmem_be_o = 4'b0000;
            endcase
        end
    end

// 2. LOAD PATH (MEM -> CPU)
    
    logic [31:0] raw_rdata;
    logic [31:0] shifted_raw_data;

    assign raw_rdata =dmem_rdata_i;
    assign shifted_raw_data = raw_rdata >> (addr_q[1:0]*8);

    always_comb begin
        lsu_rdata_o = 32'b0;
        if (state == DONE && !misaligned_trap_q && !we_q) begin
	    case (funct3_q)
                 3'b000: begin // LB (Store Byte)
                 lsu_rdata_o = { {24{shifted_raw_data[7]}}, shifted_raw_data[7:0] };
                 end
		  3'b100: begin // LB (Store Byte)
                  lsu_rdata_o = { 24'b0, shifted_raw_data[7:0] };
                 end

                 3'b001: begin // LH (Store Half)
		 lsu_rdata_o = { {16{shifted_raw_data[15]}}, shifted_raw_data[15:0] };
                 end
		 3'b101: begin // LH (Store Half)
		 lsu_rdata_o = { 16'b0, shifted_raw_data[15:0] };
                 end

                 3'b010: begin // LW (Store Word)
                  lsu_rdata_o = dmem_rdata_i ;
                 end

                 default: lsu_rdata_o = 32'b0;
        endcase
        end
    end
// OUTPUT HANDSHAKE LOGIC
    assign valid_o = (state == DONE);
    assign ready_o = (state == IDLE);
    assign lsu_err_o = (state == DONE) ? misaligned_trap_q : 1'b0;

endmodule    
