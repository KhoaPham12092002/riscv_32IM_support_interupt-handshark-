`timescale 1ns/1ps
import riscv_32im_pkg::*;
import riscv_instr::*;

// =============================================================================
// Module: soc_top_io
// Description: Top-level SoC cho DE10-Standard FPGA
//              Tích hợp RISC-V RV32IM Core + Memory + UART + GPIO + LCD
//              Có hỗ trợ Interrupt (UART RX → External IRQ)
//
// Memory Map:
//   0x0000_0000 - 0x0FFF_FFFF : IMEM (Instruction Memory)
//   0x2000_0000 - 0x2FFF_FFFF : DMEM (Data Memory)
//   0x4000_0000 - 0x4FFF_FFFF : IO Peripherals
//     +0x00 : GPIO_DATA  (R/W) - [9:0]=SW input, [17:10]=LED output
//     +0x04 : GPIO_DIR   (R/W) - Direction (reserved)
//     +0x08 : UART_TX    (W)   - TX data [7:0]
//     +0x0C : UART_RX    (R)   - RX data [7:0]
//     +0x10 : UART_STATUS(R)   - [0]=tx_busy [1]=rx_valid [2]=overrun [3]=frame_err
//     +0x14 : UART_CTRL  (RW)  - [0]=rx_irq_en
//     +0x28 : LCD_CMD    (W)   - LCD command byte
//     +0x2C : LCD_DATA   (W)   - LCD data byte
//     +0x30 : LCD_STATUS (R)   - [0]=busy
// =============================================================================
module soc_top_io #(
    parameter string IMEM_HEX = riscv_32im_pkg::IMEM_HEX_FILE,
    parameter int    IMEM_SZ  = riscv_32im_pkg::IMEM_SIZE_BYTES,
    parameter int    DMEM_SZ  = riscv_32im_pkg::DMEM_SIZE_BYTES,
    parameter int    CLK_FREQ  = 50_000_000,
    parameter int    BAUD_RATE = 115200
)(
    input  logic        clk_i,
    input  logic        rst_i,         // Active-high reset (SoC convention)

    // ── Physical IO Pins ────────────────────────────────────────────
    // GPIO
    input  logic [9:0]  sw_i,          // 10 switches (active high)
    output logic [9:0]  led_o,         // 10 LEDs

    // UART
    input  logic        uart_rx_i,     // UART RX từ PC (qua USB-UART)
    output logic        uart_tx_o,     // UART TX ra PC

    // LCD (HD44780 interface trên DE10-Standard)
    output logic [7:0]  lcd_data_o,    // LCD data bus
    output logic        lcd_en_o,      // LCD enable strobe
    output logic        lcd_rs_o,      // LCD register select (0=cmd, 1=data)
    output logic        lcd_rw_o,      // LCD R/W (luôn = 0 cho write)
    output logic        lcd_on_o       // LCD backlight ON
);

    // =====================================================================
    // RESET: Convert active-high → active-low cho UART
    // =====================================================================
    logic rst_n;
    assign rst_n = ~rst_i;

    // =====================================================================
    // 1. INTERNAL WIRES - CPU Core
    // =====================================================================

    // --- IMEM Interface ---
    logic        if_req_valid, if_req_ready, if_rsp_valid, if_rsp_ready;
    logic [31:0] if_req_addr, if_rsp_instr;

    // --- DMEM Bus (từ datapath) ---
    logic        dmem_req_valid, dmem_req_ready;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_be;
    logic        dmem_we;
    logic        dmem_rsp_valid, dmem_rsp_ready;
    logic        lsu_err;

    // --- Control Wires ---
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

    // --- CSR & Trap Wires ---
    logic        ctrl_trap_valid, ctrl_mret_valid;
    logic [3:0]  ctrl_trap_cause;
    csr_req_t    csr_req;
    logic        csr_ready, csr_rsp_valid;
    logic [31:0] csr_rdata, epc_wire, trap_vector_wire, trap_pc_wire, trap_val_wire;

    // --- Interrupt Wires ---
    logic        irq_sw, irq_timer, irq_ext;
    logic        uart_rx_irq;  // UART RX interrupt

    // =====================================================================
    // 2. ADDRESS DECODER & BUS MUX
    //    Phân biệt DMEM vs IO dựa trên địa chỉ bit [31:28]
    // =====================================================================
    logic is_io_access;
    logic is_dmem_access;

    assign is_io_access   = (dmem_addr[31:28] == 4'h4);  // 0x4xxx_xxxx
    assign is_dmem_access = (dmem_addr[31:28] == 4'h2);  // 0x2xxx_xxxx

    // --- DMEM signals (chỉ khi truy cập DMEM) ---
    logic        real_dmem_req_valid, real_dmem_req_ready;
    logic        real_dmem_rsp_valid;
    logic [31:0] real_dmem_rdata;

    assign real_dmem_req_valid = dmem_req_valid & is_dmem_access;

    // --- IO Peripheral signals ---
    logic        io_req_valid;
    logic [31:0] io_addr_offset;     // Offset trong vùng IO
    logic        io_we;

    assign io_req_valid   = dmem_req_valid & is_io_access;
    assign io_addr_offset = {20'd0, dmem_addr[11:0]};  // 12-bit offset
    assign io_we          = dmem_we;

    // --- Peripheral Select (dựa trên byte offset trong vùng IO) ---
    // GPIO:  offset 0x00-0x04
    // UART:  offset 0x08-0x14 (TX=0x08, RX=0x0C, STATUS=0x10, CTRL=0x14)
    // LCD:   offset 0x28-0x30 (CMD=0x28, DATA=0x2C, STATUS=0x30)
    logic [7:0] io_byte_offset;
    assign io_byte_offset = dmem_addr[7:0];

    logic sel_gpio_real, sel_uart_real, sel_lcd_real;
    assign sel_gpio_real = io_req_valid & (io_byte_offset <= 8'h04);
    assign sel_uart_real = io_req_valid & (io_byte_offset >= 8'h08) & (io_byte_offset <= 8'h14);
    assign sel_lcd_real  = io_req_valid & (io_byte_offset >= 8'h28) & (io_byte_offset <= 8'h30);

    // =====================================================================
    // 3. GPIO MODULE (Simple Register-Based)
    // =====================================================================
    logic [31:0] gpio_data_reg;
    logic [31:0] gpio_rdata;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            gpio_data_reg <= 32'd0;
        end else begin
            // Cập nhật SW input vào bit thấp (read-only)
            gpio_data_reg[9:0]  <= sw_i;
            // CPU ghi LED output vào bit cao
            if (sel_gpio_real && io_we) begin
                gpio_data_reg[31:10] <= dmem_wdata[31:10];
            end
        end
    end

    assign gpio_rdata = gpio_data_reg;
    assign led_o      = gpio_data_reg[19:10]; // LED[9:0] = GPIO[19:10]

    // =====================================================================
    // 4. UART MODULE INSTANTIATION
    //    UART base = 0x08. Internal regs: TX=+0, RX=+4, STATUS=+8, CTRL=+C
    //    → addr_i = (bus_offset - 0x08), sử dụng bit [3:2] sau khi trừ
    //    Bus 0x08 → addr_i[3:2]=00 (TX)
    //    Bus 0x0C → addr_i[3:2]=01 (RX)
    //    Bus 0x10 → addr_i[3:2]=10 (STATUS)
    //    Bus 0x14 → addr_i[3:2]=11 (CTRL)
    // =====================================================================
    logic [31:0] uart_rdata;
    logic        uart_ready;
    logic [3:0]  uart_addr_local;
    assign uart_addr_local = dmem_addr[4:2] - 3'b010;  // subtract 0x08/4=2

    uart #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart (
        .clk       (clk_i),
        .rst_n     (rst_n),

        // CPU interface
        .sel_i     (sel_uart_real),
        .addr_i    ({uart_addr_local[1:0], 2'b00}),  // Mapped: 0→TX, 1→RX, 2→STATUS, 3→CTRL
        .we_i      (io_we),
        .wdata_i   (dmem_wdata),
        .rdata_o   (uart_rdata),
        .ready_o   (uart_ready),

        // Physical pins
        .rx_i      (uart_rx_i),
        .tx_o      (uart_tx_o),

        // Interrupt
        .rx_irq_o  (uart_rx_irq)
    );

    // =====================================================================
    // 5. LCD MODULE (Simple Strobe-Based, HD44780)
    // =====================================================================
    logic [7:0]  lcd_data_latch;
    logic        lcd_rs_latch;
    logic        lcd_busy;
    logic [15:0] lcd_timer;       // Delay counter cho EN strobe
    logic [31:0] lcd_rdata;

    typedef enum logic [1:0] {
        LCD_IDLE,
        LCD_SETUP,
        LCD_STROBE,
        LCD_HOLD
    } lcd_state_t;
    lcd_state_t lcd_state;

    localparam LCD_SETUP_CYCLES  = 16'd100;   // ~2us @ 50MHz
    localparam LCD_STROBE_CYCLES = 16'd500;   // ~10us
    localparam LCD_HOLD_CYCLES   = 16'd2000;  // ~40us (tE cycle time)

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            lcd_state      <= LCD_IDLE;
            lcd_data_latch <= 8'd0;
            lcd_rs_latch   <= 1'b0;
            lcd_timer      <= 16'd0;
            lcd_busy       <= 1'b0;
        end else begin
            case (lcd_state)
                LCD_IDLE: begin
                    lcd_busy <= 1'b0;
                    if (sel_lcd_real && io_we) begin
                        lcd_data_latch <= dmem_wdata[7:0];
                        // RS = 0 cho CMD (offset 0x28), RS = 1 cho DATA (offset 0x2C)
                        lcd_rs_latch <= dmem_addr[2];
                        lcd_busy  <= 1'b1;
                        lcd_timer <= LCD_SETUP_CYCLES;
                        lcd_state <= LCD_SETUP;
                    end
                end
                LCD_SETUP: begin
                    if (lcd_timer == 0) begin
                        lcd_timer <= LCD_STROBE_CYCLES;
                        lcd_state <= LCD_STROBE;
                    end else
                        lcd_timer <= lcd_timer - 1;
                end
                LCD_STROBE: begin
                    if (lcd_timer == 0) begin
                        lcd_timer <= LCD_HOLD_CYCLES;
                        lcd_state <= LCD_HOLD;
                    end else
                        lcd_timer <= lcd_timer - 1;
                end
                LCD_HOLD: begin
                    if (lcd_timer == 0) begin
                        lcd_state <= LCD_IDLE;
                    end else
                        lcd_timer <= lcd_timer - 1;
                end
            endcase
        end
    end

    assign lcd_data_o = lcd_data_latch;
    assign lcd_rs_o   = lcd_rs_latch;
    assign lcd_rw_o   = 1'b0;         // Luôn write
    assign lcd_en_o   = (lcd_state == LCD_STROBE);
    assign lcd_on_o   = 1'b1;         // Backlight always ON
    assign lcd_rdata  = {31'd0, lcd_busy};

    // =====================================================================
    // 6. READ DATA MUX & IO RESPONSE (1-Cycle Latency for LSU)
    // =====================================================================
    logic [31:0] io_rdata;

    always_comb begin
        io_rdata = 32'd0;
        if (sel_gpio_real)     io_rdata = gpio_rdata;
        else if (sel_uart_real) io_rdata = uart_rdata;
        else if (sel_lcd_real)  io_rdata = lcd_rdata;
    end

    // LSU expects dmem_rsp_valid to arrive in WAIT_RSP state (1 cycle after SEND_REQ).
    // Delay io_req_valid by 1 cycle for response valid.
    logic io_rsp_valid;
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) io_rsp_valid <= 1'b0;
        else       io_rsp_valid <= io_req_valid && !io_we; // Chỉ read mới cần response (lsu fire-and-forget for store)
    end

    // Bus response mux: DMEM vs IO
    assign dmem_rdata     = is_io_access ? io_rdata : real_dmem_rdata;
    assign dmem_req_ready = is_io_access ? 1'b1     : real_dmem_req_ready;
    assign dmem_rsp_valid = is_io_access ? io_rsp_valid
                                         : real_dmem_rsp_valid;

    // =====================================================================
    // 7. INTERRUPT ROUTING
    //    UART RX IRQ → External Interrupt (irq_ext)
    //    Software & Timer: tied low (không dùng hiện tại)
    // =====================================================================
    assign irq_sw    = 1'b0;
    assign irq_timer = 1'b0;
    assign irq_ext   = uart_rx_irq;   // UART RX → External IRQ

    // =====================================================================
    // 8. INSTANTIATE RISC-V CORE (Datapath + Control + CSR)
    // =====================================================================
    riscv_datapath u_datapath (
        .clk_i                 (clk_i),
        .rst_i                 (rst_i),

        // IMEM
        .if_req_valid_o        (if_req_valid),       .if_req_addr_o         (if_req_addr),
        .if_req_ready_i        (if_req_ready),       .if_rsp_valid_i        (if_rsp_valid),
        .if_rsp_instr_i        (if_rsp_instr),       .if_rsp_ready_o        (if_rsp_ready),

        // DMEM (qua bus mux ở trên)
        .dmem_req_valid_o      (dmem_req_valid),     .dmem_req_ready_i      (dmem_req_ready),
        .dmem_addr_o           (dmem_addr),          .dmem_wdata_o          (dmem_wdata),
        .dmem_be_o             (dmem_be),            .dmem_we_o             (dmem_we),
        .dmem_rsp_valid_i      (dmem_rsp_valid),     .dmem_rsp_ready_o      (dmem_rsp_ready),
        .dmem_rdata_i          (dmem_rdata),         .dmem_err_i            (1'b0),

        // Lên Control
        .hz_id_rs1_addr_o      (hz_id_rs1_addr),    .hz_id_rs2_addr_o      (hz_id_rs2_addr),
        .id_is_ecall_o         (id_is_ecall),        .id_is_mret_o          (id_is_mret),
        .id_illegal_instr_o    (id_illegal_instr),
        .hz_ex_rs1_addr_o      (hz_ex_rs1_addr),    .hz_ex_rs2_addr_o      (hz_ex_rs2_addr),
        .hz_ex_rd_addr_o       (hz_ex_rd_addr),     .hz_ex_reg_we_o        (hz_ex_reg_we),
        .hz_ex_wb_sel_o        (hz_ex_wb_sel),       .branch_taken_o        (branch_taken),
        .hz_mem_rd_addr_o      (hz_mem_rd_addr),    .hz_mem_reg_we_o       (hz_mem_reg_we),
        .hz_wb_rd_addr_o       (hz_wb_rd_addr),     .hz_wb_reg_we_o        (hz_wb_reg_we),
        .lsu_err_o             (lsu_err),

        // Từ Control
        .ctrl_force_stall_id_i (ctrl_force_stall_id),
        .ctrl_flush_if_id_i    (ctrl_flush_if_id),
        .ctrl_flush_id_ex_i    (ctrl_flush_id_ex),
        .ctrl_fwd_rs1_sel_i    (ctrl_fwd_rs1_sel),  .ctrl_fwd_rs2_sel_i    (ctrl_fwd_rs2_sel),
        .ctrl_pc_sel_i         (ctrl_pc_sel),

        // CSR
        .csr_req_o             (csr_req),            .csr_ready_i           (csr_ready),
        .csr_rdata_i           (csr_rdata),          .trap_pc_o             (trap_pc_wire),
        .trap_val_o            (trap_val_wire),      .csr_epc_i             (epc_wire),
        .csr_trap_vector_i     (trap_vector_wire)
    );

    // =====================================================================
    // 9. INSTANTIATE CONTROL (NÃO BỘ)
    // =====================================================================
    riscv_control u_control (
        .hz_id_rs1_addr_i      (hz_id_rs1_addr),    .hz_id_rs2_addr_i      (hz_id_rs2_addr),
        .id_is_ecall_i         (id_is_ecall),        .id_is_mret_i          (id_is_mret),
        .id_illegal_instr_i    (id_illegal_instr),   .hz_ex_rs1_addr_i      (hz_ex_rs1_addr),
        .hz_ex_rs2_addr_i      (hz_ex_rs2_addr),     .hz_ex_rd_addr_i       (hz_ex_rd_addr),
        .hz_ex_reg_we_i        (hz_ex_reg_we),       .hz_ex_wb_sel_i        (hz_ex_wb_sel),
        .branch_taken_i        (branch_taken),       .hz_mem_rd_addr_i      (hz_mem_rd_addr),
        .hz_mem_reg_we_i       (hz_mem_reg_we),      .lsu_err_i             (lsu_err),
        .hz_wb_rd_addr_i       (hz_wb_rd_addr),     .hz_wb_reg_we_i        (hz_wb_reg_we),

        .ctrl_force_stall_id_o (ctrl_force_stall_id),
        .ctrl_flush_if_id_o    (ctrl_flush_if_id),   .ctrl_flush_id_ex_o    (ctrl_flush_id_ex),
        .ctrl_fwd_rs1_sel_o    (ctrl_fwd_rs1_sel),   .ctrl_fwd_rs2_sel_o    (ctrl_fwd_rs2_sel),
        .ctrl_pc_sel_o         (ctrl_pc_sel),

        .ctrl_trap_valid_o     (ctrl_trap_valid),    .ctrl_trap_cause_o     (ctrl_trap_cause),
        .ctrl_mret_valid_o     (ctrl_mret_valid)
    );

    // =====================================================================
    // 10. INSTANTIATE CSR (HỆ MIỄN DỊCH & TRẠNG THÁI)
    // =====================================================================
    csr u_csr (
        .clk_i                 (clk_i),             .rst_i                 (rst_i),

        .csr_req_i             (csr_req),            .csr_ready_o           (csr_ready),
        .csr_rdata_o           (csr_rdata),          .csr_rsp_valid_o       (csr_rsp_valid),

        .trap_valid_i          (ctrl_trap_valid),    .trap_cause_i          (ctrl_trap_cause),
        .trap_pc_i             (trap_pc_wire),       .trap_val_i            (trap_val_wire),
        .mret_i                (ctrl_mret_valid),

        .epc_o                 (epc_wire),           .trap_vector_o         (trap_vector_wire),

        // Interrupt inputs
        .irq_sw_i              (irq_sw),
        .irq_timer_i           (irq_timer),
        .irq_ext_i             (irq_ext)
    );

    // =====================================================================
    // 11. INSTANTIATE MEMORY: IMEM & DMEM
    // =====================================================================
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
