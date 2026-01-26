module lsu (
    input  logic        clk_i,
    input  logic        rst_i,

    // Interface with Core
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic        lsu_we_i,    // 1 = Store
    input  logic        lsu_req_i,   // 1 = Valid Request
    input  logic [2:0]  funct3_i,    // Data type (LB, SB, etc.)

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

    logic [1:0] addr_offset;
    assign addr_offset = addr_i[1:0]; //(00, 01, 10, 11)
    logic misaligned;	// để check kiiux half số lẽ 
    // ---------------------------------------------------------
    // 1. STORE PATH (CPU -> MEM)
    // ---------------------------------------------------------
    
    // DMEM Address: Luôn aligned 4-byte
    assign dmem_addr_o = {addr_i[31:2], 2'b00};
    
    // DMEM Write Enable:
    assign dmem_we_o   = lsu_req_i & lsu_we_i;

    // DMEM Write Data: Dịch dữ liệu đến đúng ngăn
  
    assign dmem_wdata_o = wdata_i << (addr_offset * 8);
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
    assign lsu_err_o = misaligned & lsu_req_i;

    // --- 2. Logic tạo Byte Enable (Đã cập nhật Fail-Safe) ---
    // DMEM Byte Enable
    always_comb begin
        dmem_be_o = 4'b0000;
        if (lsu_req_i && lsu_we_i && !misaligned )  begin
            case (funct3_i)
                3'b000: begin // SB (Store Byte)
                   dmem_be_o = 4'b0001 << addr_offset; 
                end

                3'b001: begin // SH (Store Half)
                   dmem_be_o = 4'b0011 << addr_offset; 
                end

                3'b010: begin // SW (Store Word)
                    dmem_be_o = 4'b1111;
                end
                
                default: dmem_be_o = 4'b0000;
            endcase
        end
    end

    // ---------------------------------------------------------
    // 2. LOAD PATH (MEM -> CPU)
    // ---------------------------------------------------------
    // Phần này ta sẽ làm sau khi xong Store.
    logic [31:0] data_shifted;
    assign data_shifted = dmem_rdata_i >> (addr_offset*8);

    always_comb begin
	    case (funct3_i)
                 3'b000: begin // LB (Store Byte)
                 lsu_rdata_o = { {24{data_shifted[7]}}, data_shifted[7:0] };
                 end
		  3'b100: begin // LB (Store Byte)
                  lsu_rdata_o = { 24'b0, data_shifted[7:0] };
                 end

                 3'b001: begin // LH (Store Half)
		 lsu_rdata_o = { {16{data_shifted[15]}}, data_shifted[15:0] };
                 end
		 3'b101: begin // LH (Store Half)
		 lsu_rdata_o = { 16'b0, data_shifted[15:0] };
                 end

                 3'b010: begin // LW (Store Word)
                  lsu_rdata_o = dmem_rdata_i ;
                 end

                 default: lsu_rdata_o = 32'b0;
             endcase
         end



endmodule    
