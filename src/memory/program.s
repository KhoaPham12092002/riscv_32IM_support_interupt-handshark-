# ==============================================================================
# RISC-V RV32IM Assembly Program cho DE10-Standard FPGA
# Tác giả: LVTN - THESIS BK 2026
#
# CHỨC NĂNG:
#   SW[1:0] = Mode Select
#   Mode 00: In "THESIS BK 2026" lên LCD 16x2 (HD44780)
#   Mode 01: In số chính phương (perfect square) của SW[9:2] lên LED
#   Mode 10: UART TX giá trị SW[9:2] ra PC qua Putty (115200 baud)
#
# MEMORY MAP (chưa thiết lập mem IO - comment line mapping):
#   0x4000_0000  GPIO_DATA   - [9:0] = SW input, [17:10] = LED output (R/W)
#   0x4000_0004  GPIO_DIR    - Direction register (không dùng, mặc định input)
#   0x4000_0008  UART_TX     - Ghi byte [7:0] để truyền
#   0x4000_000C  UART_RX     - Đọc byte [7:0] đã nhận
#   0x4000_0010  UART_STATUS - [0]=tx_busy, [1]=rx_valid
#   0x4000_0014  UART_CTRL   - [0]=rx_irq_en
#   0x4000_0028  LCD_CMD     - Ghi lệnh HD44780 [7:0]
#   0x4000_002C  LCD_DATA    - Ghi ký tự [7:0] lên LCD
#   0x4000_0030  LCD_STATUS  - [0]=busy
#
# REGISTER CONVENTION:
#   x1  (ra)  = return address
#   x2  (sp)  = stack pointer (init 0x2000_0FFC, top of 4KB DMEM)
#   x5  (t0)  = temp / IO base address
#   x6  (t1)  = temp
#   x7  (t2)  = temp
#   x8  (s0)  = mode value [1:0]
#   x9  (s1)  = SW[9:2] input value
#   x10 (a0)  = function argument / return value
#   x11 (a1)  = function argument
#   x12 (a2)  = function argument
#   x28 (t3)  = temp
#   x29 (t4)  = temp
#   x30 (t5)  = temp
# ==============================================================================

.equ IO_BASE,      0x40000000     # Base address cho IO peripherals
.equ GPIO_DATA,    0x00           # offset GPIO data register
.equ UART_TX,      0x08           # offset UART TX data
.equ UART_RX,      0x0C           # offset UART RX data
.equ UART_STATUS,  0x10           # offset UART status
.equ UART_CTRL,    0x14           # offset UART control
.equ LCD_CMD,      0x28           # offset LCD command
.equ LCD_DATA,     0x2C           # offset LCD data
.equ LCD_STATUS,   0x30           # offset LCD status

.equ DMEM_BASE,    0x20000000     # Data memory base
.equ STACK_TOP,    0x20000FFC     # Top of 4KB DMEM stack

# ──────────────────────────────────────────────────────────────────────
# BOOT / RESET VECTOR (Address 0x0000_0000)
# ──────────────────────────────────────────────────────────────────────
.section .text
.globl _start
_start:
    # ── Khởi tạo Stack Pointer ──
    lui   x2, 0x20001             # x2 = 0x20001000
    addi  x2, x2, -4             # x2 = 0x20000FFC (stack top)

    # ── Khởi tạo IO Base Address vào x5 ──
    lui   x5, 0x40000             # x5 = 0x40000000 (IO_BASE)

# ──────────────────────────────────────────────────────────────────────
# MAIN LOOP: Đọc SW, phân loại mode, gọi hàm tương ứng
# ──────────────────────────────────────────────────────────────────────
main_loop:
    # ── Đọc GPIO (SW[9:0]) ──
    lw    x6, 0(x5)               # x6 = GPIO_DATA = SW[9:0]
    nop                           # pipeline delay
    nop

    # ── Tách mode = SW[1:0] ──
    andi  x8, x6, 0x03            # x8 = mode = x6 & 0x03

    # ── Tách input = SW[9:2] >> 2 ──
    srli  x9, x6, 2               # x9 = SW[9:2] (giá trị 0-255)
    andi  x9, x9, 0xFF            # mask 8 bit

    # ── Phân nhánh theo mode ──
    addi  x6, x0, 0               # x6 = 0 (MODE_00)
    beq   x8, x6, mode_00_lcd     # if mode==00 → LCD

    addi  x6, x0, 1               # x6 = 1 (MODE_01)
    beq   x8, x6, mode_01_led     # if mode==01 → LED perfect square

    addi  x6, x0, 2               # x6 = 2 (MODE_10)
    beq   x8, x6, mode_02_uart    # if mode==10 → UART

    # Mode 11: không dùng, quay lại main loop
    jal   x0, main_loop

# ======================================================================
# MODE 00: In "THESIS BK 2026" lên LCD 16x2 (HD44780 interface)
# ======================================================================
mode_00_lcd:
    # ── Khởi tạo LCD (Function Set: 8-bit, 2 lines, 5x8 font) ──
    addi  a0, x0, 0x38            # CMD = 0x38
    jal   ra, lcd_send_cmd
    # ── Display ON, Cursor OFF, Blink OFF ──
    addi  a0, x0, 0x0C            # CMD = 0x0C
    jal   ra, lcd_send_cmd
    # ── Clear Display ──
    addi  a0, x0, 0x01            # CMD = 0x01 (Clear)
    jal   ra, lcd_send_cmd
    # ── Delay sau Clear (cần ~2ms, dùng vòng lặp đơn giản) ──
    lui   x28, 1                  # delay counter = 4096
lcd_clear_delay:
    addi  x28, x28, -1
    bne   x28, x0, lcd_clear_delay
    # ── Set cursor dòng 1, vị trí 0 ──
    addi  a0, x0, 0x80            # CMD = 0x80 (DDRAM addr = 0x00)
    jal   ra, lcd_send_cmd

    # ── In chuỗi "THESIS BK 2026" (14 ký tự) ──
    # T=0x54, H=0x48, E=0x45, S=0x53, I=0x49, S=0x53
    # ' '=0x20, B=0x42, K=0x4B
    # ' '=0x20, 2=0x32, 0=0x30, 2=0x32, 6=0x36
    addi  a0, x0, 0x54            # 'T'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x48            # 'H'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x45            # 'E'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x53            # 'S'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x49            # 'I'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x53            # 'S'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x20            # ' '
    jal   ra, lcd_send_data
    addi  a0, x0, 0x42            # 'B'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x4B            # 'K'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x20            # ' '
    jal   ra, lcd_send_data
    addi  a0, x0, 0x32            # '2'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x30            # '0'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x32            # '2'
    jal   ra, lcd_send_data
    addi  a0, x0, 0x36            # '6'
    jal   ra, lcd_send_data

    # ── Quay lại main loop ──
    jal   x0, main_loop

# ======================================================================
# MODE 01: In số chính phương (Perfect Square) của SW[9:2] lên LED
#   Input: x9 = N = SW[9:2] (0-255)
#   Output: LED = N*N (viết vào GPIO_DATA[17:10])
#   Dùng phép MUL (M-extension)
# ======================================================================
mode_01_led:
    # ── Tính N * N ──
    mul   x10, x9, x9             # x10 = N^2 (M-extension MUL)
    nop                           # wait for M-unit (2 cycles)
    nop

    # ── Shift left 10 bit để ghi vào LED[17:10] ──
    slli  x10, x10, 10            # x10 = N^2 << 10

    # ── Giữ lại SW[9:0] ở bit thấp (đọc lại GPIO) ──
    lw    x6, 0(x5)               # x6 = GPIO_DATA hiện tại
    nop
    nop
    andi  x6, x6, 0x3FF           # giữ SW[9:0]
    or    x10, x10, x6            # ghép LED + SW

    # ── Ghi ra GPIO ──
    sw    x10, 0(x5)              # GPIO_DATA = LED[17:10] | SW[9:0]

    # ── Quay lại main loop ──
    jal   x0, main_loop

# ======================================================================
# MODE 10: UART TX giá trị SW[9:2] lên PC (qua Putty @ 115200 baud)
#   Truyền giá trị dưới dạng ASCII decimal + newline
#   VD: SW=42 → truyền "42\r\n"
# ======================================================================
mode_02_uart:
    # ── Chuyển x9 (0-255) thành chuỗi ASCII decimal ──
    # Chia cho 100 → hàng trăm
    # Chia cho 10  → hàng chục
    # Phần dư      → hàng đơn vị

    add   a0, x9, x0              # a0 = N (copy)

    # ── Hàng trăm ──
    addi  x28, x0, 100            # x28 = 100
    divu  x29, a0, x28            # x29 = N / 100 (hàng trăm)
    nop                           # wait for DIV (35 cycles in M-unit)
    remu  a0, a0, x28             # a0 = N % 100 (phần dư)
    nop

    # Chỉ in hàng trăm nếu != 0
    beq   x29, x0, skip_hundreds
    addi  x30, x29, 0x30          # x30 = ASCII digit
    add   a0, a0, x0              # save a0 (không mất)
    # Ghi vào backup trước khi gọi uart_tx
    add   x7, a0, x0              # x7 = backup remainder
    add   a0, x30, x0             # a0 = char to send
    jal   ra, uart_send_byte
    add   a0, x7, x0              # restore a0
skip_hundreds:

    # ── Hàng chục ──
    addi  x28, x0, 10             # x28 = 10
    divu  x29, a0, x28            # x29 = remainder / 10
    nop
    remu  a0, a0, x28             # a0 = remainder % 10
    nop

    # In hàng chục (luôn in, kể cả khi = 0 nếu có hàng trăm)
    addi  x30, x29, 0x30          # ASCII digit
    add   x7, a0, x0              # backup
    add   a0, x30, x0
    jal   ra, uart_send_byte
    add   a0, x7, x0              # restore

    # ── Hàng đơn vị ──
    addi  a0, a0, 0x30            # ASCII digit
    jal   ra, uart_send_byte

    # ── Gửi CR + LF ("\r\n") ──
    addi  a0, x0, 0x0D            # '\r'
    jal   ra, uart_send_byte
    addi  a0, x0, 0x0A            # '\n'
    jal   ra, uart_send_byte

    # ── Delay trước khi đọc lại SW (tránh spam) ──
    lui   x28, 8                  # delay ~ 32K cycles
uart_delay:
    addi  x28, x28, -1
    bne   x28, x0, uart_delay

    # ── Quay lại main loop ──
    jal   x0, main_loop

# ======================================================================
# SUBROUTINE: lcd_send_cmd - Gửi lệnh tới LCD
#   Input: a0 = command byte [7:0]
#   Clobbers: x28
# ======================================================================
lcd_send_cmd:
    # Chờ LCD không busy
lcd_cmd_wait:
    lw    x28, 0x30(x5)           # x28 = LCD_STATUS
    nop
    nop
    andi  x28, x28, 1             # check busy bit
    bne   x28, x0, lcd_cmd_wait   # loop nếu busy

    # Ghi lệnh
    sw    a0, 0x28(x5)            # LCD_CMD = a0
    jalr  x0, ra, 0               # return

# ======================================================================
# SUBROUTINE: lcd_send_data - Gửi ký tự tới LCD
#   Input: a0 = data byte [7:0]
#   Clobbers: x28
# ======================================================================
lcd_send_data:
    # Chờ LCD không busy
lcd_data_wait:
    lw    x28, 0x30(x5)           # x28 = LCD_STATUS
    nop
    nop
    andi  x28, x28, 1
    bne   x28, x0, lcd_data_wait

    # Ghi data
    sw    a0, 0x2C(x5)            # LCD_DATA = a0
    jalr  x0, ra, 0               # return

# ======================================================================
# SUBROUTINE: uart_send_byte - Gửi 1 byte qua UART TX
#   Input: a0 = byte to send [7:0]
#   Clobbers: x28
# ======================================================================
uart_send_byte:
    # Chờ TX không busy (poll STATUS[0])
uart_tx_wait:
    lw    x28, 0x10(x5)           # x28 = UART_STATUS
    nop
    nop
    andi  x28, x28, 1             # check tx_busy bit
    bne   x28, x0, uart_tx_wait   # loop nếu busy

    # Ghi byte vào TX register
    sw    a0, 0x08(x5)            # UART_TX = a0[7:0]
    jalr  x0, ra, 0               # return

# ======================================================================
# TRAP HANDLER (mtvec trỏ vào đây)
# Xử lý interrupt cơ bản: đọc mcause, nếu là UART RX thì đọc data
# HIỆN TẠI: placeholder — chỉ MRET quay về
# ======================================================================
.align 4
trap_handler:
    # Save context (tối thiểu)
    addi  x2, x2, -16            # allocate stack frame
    sw    x1, 0(x2)              # save ra
    sw    x28, 4(x2)             # save t3
    sw    x29, 8(x2)             # save t4
    sw    x10, 12(x2)            # save a0

    # Đọc mcause để xác định nguồn ngắt
    csrr  x28, 0x342             # x28 = mcause
    nop
    nop

    # Kiểm tra nếu là external interrupt (mcause[31]=1, code=11)
    # Hiện tại: đơn giản MRET
    # TODO: Xử lý UART RX interrupt khi cần

    # Restore context
    lw    x1, 0(x2)
    lw    x28, 4(x2)
    lw    x29, 8(x2)
    lw    x10, 12(x2)
    addi  x2, x2, 16

    mret                          # Return from trap
