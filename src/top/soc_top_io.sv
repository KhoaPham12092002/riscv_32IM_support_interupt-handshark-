`timescale 1ns/1ps
import riscv_32im_pkg::*;
import riscv_instr::*;

// =============================================================================
// Module: address_decoder
// Cấp 2 – decode offset trong vùng IO (bits [19:0]) thành chip-select ngoại vi.
// Mỗi ngoại vi chiếm 4 KB; so sánh bits [19:12] (= page number).
// Mask 20'hFF000 xóa bits [11:0] trước khi cast sang periph_addr_t.
// =============================================================================
module address_decoder
    import riscv_32im_pkg::*;
(
    input  logic        io_req_valid_i, // Đã confirm là IO access
    input  logic [19:0] io_addr_i,      // dmem_addr[19:0]
    output logic        cs_sw_led_o,    // 0x4000_0000
    output logic        cs_hex_o,       // 0x4000_1000
    output logic        cs_key_o,       // 0x4000_2000
    output logic        cs_uart_o,      // 0x4000_3000
    output logic        cs_gpio_o       // 0x4000_4000
);
    always_comb begin
        cs_sw_led_o = 1'b0;
        cs_hex_o    = 1'b0;
        cs_key_o    = 1'b0;
        cs_uart_o   = 1'b0;
        cs_gpio_o   = 1'b0;
        if (io_req_valid_i) begin
            case (periph_addr_t'(io_addr_i & 20'hFF000))
                ADDR_SW_LED: cs_sw_led_o = 1'b1;
                ADDR_HEX:    cs_hex_o    = 1'b1;
                ADDR_KEY:    cs_key_o    = 1'b1;
                ADDR_UART:   cs_uart_o   = 1'b1;
                ADDR_GPIO:   cs_gpio_o   = 1'b1;
                default: ;
            endcase
        end
    end
endmodule

// =============================================================================
// Module: soc_top_io
// Top-level SoC – RISC-V RV32IM + IMEM/DMEM + ngoại vi IO
//
// Memory Map (Cấp 1):
//   0x0000_0000 – 0x0FFF_FFFF : IMEM
//   0x2000_0000 – 0x2FFF_FFFF : DMEM
//   0x4000_0000 – 0x4FFF_FFFF : IO (address_decoder decode tiếp)
//
// Memory Map (Cấp 2 – IO):
//   0x4000_0000 : SW_LED  – Đọc: SW[9:0], Ghi: LED[9:0]
//   0x4000_1000 : HEX     – Ghi raw 7-seg (common-anode) cho 6 màn hình
//                           +0x00=HEX0 .. +0x14=HEX5, bước 4 bytes
//   0x4000_2000 : KEY     – Đọc KEY[3:0] (active-low)
//   0x4000_3000 : UART    – TX(+0) RX(+4) STATUS(+8) CTRL(+C), qua GPIO[1:0]
//   0x4000_4000 : GPIO    – Data(+0) Dir(+4) cho 20-pin GPIO
// =============================================================================
module soc_top_io #(
    parameter string IMEM_HEX = riscv_32im_pkg::IMEM_HEX_FILE,
    parameter int    IMEM_SZ  = riscv_32im_pkg::IMEM_SIZE_BYTES,
    parameter int    DMEM_SZ  = riscv_32im_pkg::DMEM_SIZE_BYTES,
    parameter int    CLK_FREQ  = 50_000_000,
    parameter int    BAUD_RATE = 115200
)(
    input  logic        clk_i,
    input  logic        rst_i,          // Active-high reset

    // SW & LED
    input  logic [9:0]  sw_i,
    output logic [9:0]  led_o,

    // KEY (active-low, DE10-Standard: KEY[0] = global reset trong phần mềm)
    input  logic [3:0]  key_i,

    // UART (kết nối vật lý tới GPIO[1:0] trên board)
    input  logic        uart_rx_i,      // GPIO[0] -> UART RX
    output logic        uart_tx_o,      // GPIO[1] -> UART TX

    // HEX 7-segment (common-anode, active-LOW segments)
    output logic [6:0]  hex0_o,
    output logic [6:0]  hex1_o,
    output logic [6:0]  hex2_o,
    output logic [6:0]  hex3_o,
    output logic [6:0]  hex4_o,
    output logic [6:0]  hex5_o
);

    // =========================================================================
    // Reset polarity
    // =========================================================================
    logic rst_n;
    assign rst_n = ~rst_i;

    // =========================================================================
    // 1. INTERNAL WIRES — CPU Core
    // =========================================================================
    logic        if_req_valid, if_req_ready, if_rsp_valid, if_rsp_ready;
    logic [31:0] if_req_addr, if_rsp_instr;

    logic        dmem_req_valid, dmem_req_ready;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_be;
    logic        dmem_we;
    logic        dmem_rsp_valid, dmem_rsp_ready;
    logic        lsu_err;

    logic [4:0]  hz_id_rs1_addr, hz_id_rs2_addr;
    logic        id_is_ecall, id_is_mret, id_illegal_instr;
    logic [4:0]  hz_ex_rs1_addr, hz_ex_rs2_addr, hz_ex_rd_addr;
    logic        hz_ex_reg_we;
    wb_sel_e     hz_ex_wb_sel;
    logic        branch_taken;
    logic [4:0]  hz_mem_rd_addr; logic hz_mem_reg_we;
    logic [4:0]  hz_wb_rd_addr;  logic hz_wb_reg_we;

    logic        ctrl_force_stall_id, ctrl_flush_if_id, ctrl_flush_id_ex;
    logic [1:0]  ctrl_fwd_rs1_sel, ctrl_fwd_rs2_sel, ctrl_pc_sel;

    logic        ctrl_trap_valid, ctrl_mret_valid;
    logic [3:0]  ctrl_trap_cause;
    csr_req_t    csr_req;
    logic        csr_ready, csr_rsp_valid;
    logic [31:0] csr_rdata, epc_wire, trap_vector_wire, trap_pc_wire, trap_val_wire;

    logic        irq_sw, irq_timer, irq_ext;
    logic        uart_rx_irq;

    // =========================================================================
    // 2. CẤP 1: PHÂN VÙNG ĐỊA CHỈ (IMEM / DMEM / IO)
    // =========================================================================
    logic is_io_access;
    logic is_dmem_access;

    assign is_io_access   = (dmem_addr[31:28] == 4'h4);
    assign is_dmem_access = (dmem_addr[31:28] == 4'h2);

    logic        real_dmem_req_valid, real_dmem_req_ready;
    logic        real_dmem_rsp_valid;
    logic [31:0] real_dmem_rdata;

    assign real_dmem_req_valid = dmem_req_valid & is_dmem_access;

    logic io_req_valid;
    logic io_we;
    assign io_req_valid = dmem_req_valid & is_io_access;
    assign io_we        = dmem_we;

    // =========================================================================
    // 3. CẤP 2: ADDRESS DECODER — sinh chip-select cho từng ngoại vi
    // =========================================================================
    logic cs_sw_led, cs_hex, cs_key, cs_uart, cs_gpio;

    address_decoder u_addr_dec (
        .io_req_valid_i (io_req_valid),
        .io_addr_i      (dmem_addr[19:0]),
        .cs_sw_led_o    (cs_sw_led),
        .cs_hex_o       (cs_hex),
        .cs_key_o       (cs_key),
        .cs_uart_o      (cs_uart),
        .cs_gpio_o      (cs_gpio)
    );

    // =========================================================================
    // 4. SW_LED PERIPHERAL (0x4000_0000)
    //    Đọc: trả về SW[9:0]
    //    Ghi: latch vào led_reg → LED[9:0]
    // =========================================================================

    logic [9:0] led_reg;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) led_reg <= 10'd0;
        else if (cs_sw_led && io_we) led_reg <= dmem_wdata[9:0];
    end

    assign led_o = led_reg;

    // =========================================================================
    // 5. HEX PERIPHERAL (0x4000_1000)
    //    Ghi raw 7-seg code (common-anode, 7-bit) per display.
    //    Địa chỉ: BASE+0=HEX0 .. BASE+0x14=HEX5 (bước 4 bytes).
    //    Phần mềm nạp mã từ lookup table (lbu + sw), không cần phần cứng đổi mã.
    // =========================================================================
    logic [6:0] hex_reg [0:5];

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            foreach (hex_reg[i]) hex_reg[i] <= 7'b1111111; // tắt tất cả
        end else if (cs_hex && io_we) begin
            case (dmem_addr[4:2])
                3'd0: hex_reg[0] <= dmem_wdata[6:0];
                3'd1: hex_reg[1] <= dmem_wdata[6:0];
                3'd2: hex_reg[2] <= dmem_wdata[6:0];
                3'd3: hex_reg[3] <= dmem_wdata[6:0];
                3'd4: hex_reg[4] <= dmem_wdata[6:0];
                3'd5: hex_reg[5] <= dmem_wdata[6:0];
                default: ;
            endcase
        end
    end

    assign hex0_o = hex_reg[0];
    assign hex1_o = hex_reg[1];
    assign hex2_o = hex_reg[2];
    assign hex3_o = hex_reg[3];
    assign hex4_o = hex_reg[4];
    assign hex5_o = hex_reg[5];

    // =========================================================================
    // 6. KEY PERIPHERAL (0x4000_2000)
    //    Read-only: trả về KEY[3:0] active-low từ board
    // =========================================================================
    // (Không cần register – đọc thẳng từ port key_i)

    // =========================================================================
    // 7. UART PERIPHERAL (0x4000_3000) — kết nối vật lý qua GPIO[1:0]
    //    Thanh ghi (uart.sv, dùng addr_i[3:2]):
    //      00 = TX_DATA  (W): ghi byte cần truyền
    //      01 = RX_DATA  (R): đọc byte nhận được (tự clear valid)
    //      10 = STATUS   (R): [0]=tx_busy [1]=rx_valid [2]=rx_overrun [3]=rx_frame_err
    //      11 = CTRL    (RW): [0]=rx_irq_en
    //    => addr_i = dmem_addr[3:0] (không cần offset trừ)
    // =========================================================================
    logic [31:0] uart_rdata;
    logic        uart_ready;

    uart #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart (
        .clk       (clk_i),
        .rst_n     (rst_n),
        .sel_i     (cs_uart),
        .addr_i    (dmem_addr[3:0]),
        .we_i      (io_we),
        .wdata_i   (dmem_wdata),
        .rdata_o   (uart_rdata),
        .ready_o   (uart_ready),
        .rx_i      (uart_rx_i),
        .tx_o      (uart_tx_o),
        .rx_irq_o  (uart_rx_irq)
    );

    // =========================================================================
    // 8. GPIO PERIPHERAL (0x4000_4000) — 20-pin general-purpose IO
    //    +0 (GPIO_DATA): Ghi: set output; Đọc: trả về {gpio_out[19:2], uart_tx, uart_rx}
    //    +4 (GPIO_DIR) : Ghi: set direction (1=output); Đọc: dir register
    //    GPIO[0] = uart_rx_i (always input)
    //    GPIO[1] = uart_tx_o (always output, driven by UART core)
    // =========================================================================
    logic [19:0] gpio_out_reg;
    logic [19:0] gpio_dir_reg;
    logic [31:0] gpio_rdata;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            gpio_out_reg <= 20'd0;
            gpio_dir_reg <= 20'd0;
        end else if (cs_gpio && io_we) begin
            case (dmem_addr[3:2])
                2'b00: gpio_out_reg <= dmem_wdata[19:0];
                2'b01: gpio_dir_reg <= dmem_wdata[19:0];
                default: ;
            endcase
        end
    end

    always_comb begin
        gpio_rdata = 32'd0;
        if (dmem_addr[3:2] == 2'b00) begin
            gpio_rdata[0]    = uart_rx_i;         // GPIO[0] = UART RX pin
            gpio_rdata[1]    = uart_tx_o;         // GPIO[1] = UART TX pin
            gpio_rdata[19:2] = gpio_out_reg[19:2];
        end else begin
            gpio_rdata[19:0] = gpio_dir_reg;
        end
    end

    // =========================================================================
    // 9. READ DATA MUX & IO RESPONSE
    //    io_rdata_comb: MUX tổ hợp từ các cs_* signals.
    //    io_rdata_reg : latch giữ giá trị qua trạng thái WAIT_RSP của LSU
    //                   (LSU hạ dmem_req_valid → cs_* = 0 → cần latch)
    //    io_rsp_valid : fire 1 cycle sau io_req_valid (cả read lẫn write)
    // =========================================================================
    logic [31:0] io_rdata_comb;
    logic [31:0] io_rdata_reg;

    always_comb begin
        io_rdata_comb = 32'd0;
        if      (cs_sw_led) io_rdata_comb = {22'd0, sw_i};
        else if (cs_key)    io_rdata_comb = {28'd0, key_i};
        else if (cs_uart)   io_rdata_comb = uart_rdata;
        else if (cs_gpio)   io_rdata_comb = gpio_rdata;
        // cs_hex: write-only, đọc trả 0
    end

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) io_rdata_reg <= 32'd0;
        else if (io_req_valid && !io_we) io_rdata_reg <= io_rdata_comb;
    end

    logic io_rsp_valid;
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) io_rsp_valid <= 1'b0;
        else       io_rsp_valid <= io_req_valid;
    end

    assign dmem_rdata     = is_io_access ? io_rdata_reg       : real_dmem_rdata;
    assign dmem_req_ready = is_io_access ? 1'b1               : real_dmem_req_ready;
    assign dmem_rsp_valid = is_io_access ? io_rsp_valid       : real_dmem_rsp_valid;

    // =========================================================================
    // 10. INTERRUPT ROUTING
    // =========================================================================
    assign irq_sw    = 1'b0;
    assign irq_timer = 1'b0;
    assign irq_ext   = uart_rx_irq;

    // =========================================================================
    // 11. RISC-V DATAPATH
    // =========================================================================
    riscv_datapath u_datapath (
        .clk_i                 (clk_i),
        .rst_i                 (rst_i),

        .if_req_valid_o        (if_req_valid),     .if_req_addr_o         (if_req_addr),
        .if_req_ready_i        (if_req_ready),     .if_rsp_valid_i        (if_rsp_valid),
        .if_rsp_instr_i        (if_rsp_instr),     .if_rsp_ready_o        (if_rsp_ready),

        .dmem_req_valid_o      (dmem_req_valid),   .dmem_req_ready_i      (dmem_req_ready),
        .dmem_addr_o           (dmem_addr),        .dmem_wdata_o          (dmem_wdata),
        .dmem_be_o             (dmem_be),          .dmem_we_o             (dmem_we),
        .dmem_rsp_valid_i      (dmem_rsp_valid),   .dmem_rsp_ready_o      (dmem_rsp_ready),
        .dmem_rdata_i          (dmem_rdata),       .dmem_err_i            (1'b0),

        .hz_id_rs1_addr_o      (hz_id_rs1_addr),  .hz_id_rs2_addr_o      (hz_id_rs2_addr),
        .id_is_ecall_o         (id_is_ecall),      .id_is_mret_o          (id_is_mret),
        .id_illegal_instr_o    (id_illegal_instr),
        .hz_ex_rs1_addr_o      (hz_ex_rs1_addr),  .hz_ex_rs2_addr_o      (hz_ex_rs2_addr),
        .hz_ex_rd_addr_o       (hz_ex_rd_addr),   .hz_ex_reg_we_o        (hz_ex_reg_we),
        .hz_ex_wb_sel_o        (hz_ex_wb_sel),    .branch_taken_o        (branch_taken),
        .hz_mem_rd_addr_o      (hz_mem_rd_addr),  .hz_mem_reg_we_o       (hz_mem_reg_we),
        .hz_wb_rd_addr_o       (hz_wb_rd_addr),   .hz_wb_reg_we_o        (hz_wb_reg_we),
        .lsu_err_o             (lsu_err),

        .ctrl_force_stall_id_i (ctrl_force_stall_id),
        .ctrl_flush_if_id_i    (ctrl_flush_if_id),
        .ctrl_flush_id_ex_i    (ctrl_flush_id_ex),
        .ctrl_fwd_rs1_sel_i    (ctrl_fwd_rs1_sel), .ctrl_fwd_rs2_sel_i   (ctrl_fwd_rs2_sel),
        .ctrl_pc_sel_i         (ctrl_pc_sel),

        .csr_req_o             (csr_req),          .csr_ready_i           (csr_ready),
        .csr_rdata_i           (csr_rdata),        .trap_pc_o             (trap_pc_wire),
        .trap_val_o            (trap_val_wire),    .csr_epc_i             (epc_wire),
        .csr_trap_vector_i     (trap_vector_wire)
    );

    // =========================================================================
    // 12. CONTROL
    // =========================================================================
    riscv_control u_control (
        .hz_id_rs1_addr_i      (hz_id_rs1_addr),  .hz_id_rs2_addr_i      (hz_id_rs2_addr),
        .id_is_ecall_i         (id_is_ecall),      .id_is_mret_i          (id_is_mret),
        .id_illegal_instr_i    (id_illegal_instr), .hz_ex_rs1_addr_i      (hz_ex_rs1_addr),
        .hz_ex_rs2_addr_i      (hz_ex_rs2_addr),  .hz_ex_rd_addr_i       (hz_ex_rd_addr),
        .hz_ex_reg_we_i        (hz_ex_reg_we),    .hz_ex_wb_sel_i        (hz_ex_wb_sel),
        .branch_taken_i        (branch_taken),    .hz_mem_rd_addr_i      (hz_mem_rd_addr),
        .hz_mem_reg_we_i       (hz_mem_reg_we),   .hz_wb_rd_addr_i       (hz_wb_rd_addr),
        .hz_wb_reg_we_i        (hz_wb_reg_we),    .lsu_err_i             (lsu_err),

        .ctrl_force_stall_id_o (ctrl_force_stall_id),
        .ctrl_flush_if_id_o    (ctrl_flush_if_id), .ctrl_flush_id_ex_o   (ctrl_flush_id_ex),
        .ctrl_fwd_rs1_sel_o    (ctrl_fwd_rs1_sel), .ctrl_fwd_rs2_sel_o   (ctrl_fwd_rs2_sel),
        .ctrl_pc_sel_o         (ctrl_pc_sel),

        .ctrl_trap_valid_o     (ctrl_trap_valid),  .ctrl_trap_cause_o    (ctrl_trap_cause),
        .ctrl_mret_valid_o     (ctrl_mret_valid)
    );

    // =========================================================================
    // 13. CSR
    // =========================================================================
    csr u_csr (
        .clk_i                 (clk_i),            .rst_i                 (rst_i),
        .csr_req_i             (csr_req),          .csr_ready_o           (csr_ready),
        .csr_rdata_o           (csr_rdata),        .csr_rsp_valid_o       (csr_rsp_valid),
        .trap_valid_i          (ctrl_trap_valid),  .trap_cause_i          (ctrl_trap_cause),
        .trap_pc_i             (trap_pc_wire),     .trap_val_i            (trap_val_wire),
        .mret_i                (ctrl_mret_valid),
        .epc_o                 (epc_wire),         .trap_vector_o         (trap_vector_wire),
        .irq_sw_i              (irq_sw),
        .irq_timer_i           (irq_timer),
        .irq_ext_i             (irq_ext)
    );

    // =========================================================================
    // 14. MEMORY: IMEM & DMEM
    // =========================================================================
    imem #(
        .HEX_FILE (IMEM_HEX),
        .MEM_SIZE (IMEM_SZ)
    ) u_imem (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .req_valid_i (if_req_valid),
        .req_addr_i  (if_req_addr),
        .req_ready_o (if_req_ready),
        .rsp_valid_o (if_rsp_valid),
        .rsp_ready_i (if_rsp_ready),
        .rsp_instr_o (if_rsp_instr)
    );

    dmem #(
        .MEM_SIZE (DMEM_SZ)
    ) u_dmem (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .req_valid_i (real_dmem_req_valid),
        .req_ready_o (real_dmem_req_ready),
        .req_addr_i  (dmem_addr),
        .req_wdata_i (dmem_wdata),
        .req_be_i    (dmem_be),
        .req_we_i    (dmem_we),
        .rsp_valid_o (real_dmem_rsp_valid),
        .rsp_ready_i (dmem_rsp_ready),
        .rsp_rdata_o (real_dmem_rdata)
    );

endmodule
