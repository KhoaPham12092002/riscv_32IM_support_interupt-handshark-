import riscv_32im_pkg::*;

module imem #(
    parameter string HEX_FILE = "program.hex",
    parameter int    MEM_SIZE = riscv_32im_pkg::IMEM_SIZE_BYTES
) (
    input  logic        clk_i,
    input  logic        rst_i,     // Active high Reset
    // --- hand shark Interface ---
    input   logic valid_i,
    output  logic valid_o,
    input   logic ready_i,
    output  logic ready_o,
    // --- Native Interface ---
    input   logic [31:0] addr_i,     // Address
    output  logic [31:0] instr_o     // Instruction Data
);

    localparam int WORD_COUNT = MEM_SIZE / 4;
    logic valid_q;
    logic [31:0] mem_array [0 : WORD_COUNT-1];
    logic [31:0] word_addr;
    logic req_i;
    assign req_i = valid_i && ready_i;
    
    // Mapping Address
    assign word_addr = (addr_i - riscv_32im_pkg::MAP_IMEM_BASE) >> 2;

    // --- Core Logic (Synchronous Read - Block RAM friendly) ---
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            instr_o <= 32'h0000_0000; // NOP
        end else begin
            // Chỉ đọc khi có yêu cầu (req_i = 1)
            if (req_i) begin
                if (word_addr < WORD_COUNT) 
                    instr_o <= mem_array[word_addr];
                else 
                    instr_o <= 32'h0000_0000;
            end
            // Nếu req_i = 0, giữ nguyên instr_o cũ (Stable output)
        end
    end

    // --- Initial Load ---
    initial begin
        for (int i = 0; i < WORD_COUNT; i++) mem_array[i] = 32'h0;
        if (HEX_FILE != "") $readmemh(HEX_FILE, mem_array);
    end
    // --- Handshark Interface Logic ---
    // IMEM chỉ sẵn sàng nhận địa chỉ mới khi tầng sau (Pipeline) không bị tắc.
    // Nếu ready_i = 0 (Tắc), ta cũng phải báo ready_o = 0 để PC Gen dừng lại.
    assign ready_o = ready_i;
    // LATENCY MANAGERMENT - IMEM có độ trễ 1 chu kỳ.
    always_ff @(posedge clk_i ) begin
        if (rst_i) begin
            valid_q <= 1'b0;
        end else begin 
            if (ready_i) begin
            valid_q <= valid_i;
            end
        end
    end
    assign valid_o = valid_q;
endmodule