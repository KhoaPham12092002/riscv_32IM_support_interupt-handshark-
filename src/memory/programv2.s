# ==============================================================================
# RISC-V RV32IM Assembly — programv2.s
# DE10-Standard FPGA | Harvard SoC (IMEM fetch-only, DMEM load/store)
#
# Memory Map (Cấp 2 - IO):
#   SW_LED_BASE = 0x4000_0000  R: SW[9:0]  W: LED[9:0]
#   HEX_BASE    = 0x4000_1000  W: HEX[0..5] tại +0,+4,...+0x14 (raw 7-seg code)
#   KEY_BASE    = 0x4000_2000  R: KEY[3:0] active-low
#   UART_BASE   = 0x4000_3000  UART TX/RX qua GPIO[1:0]
#                   +0x00 TX_DATA (W) | +0x04 RX_DATA (R)
#                   +0x08 STATUS  (R) : [0]=tx_busy  [1]=rx_valid
#                   +0x0C CTRL   (RW) : [0]=rx_irq_en
#   GPIO_BASE   = 0x4000_4000  20-pin GPIO (Data +0, Dir +4)
#
# DMEM Layout (Harvard: LOAD/STORE chỉ tới DMEM 0x2000_xxxx):
#   0x2000_0000 .. 0x2000_0009 = hex_map[0..9]  (10 bytes, init by _init)
#   0x2000_000A .. 0x2000_0FFC = stack (grows downward từ 0x2000_0FFC)
#
# *** QUAN TRỌNG - Harvard Architecture ***
#   LOAD/STORE từ IMEM (0x0000_xxxx) → BUS HANG (LSU không route).
#   Bảng hex_map PHẢI ở DMEM. _init khởi tạo bằng SB trước khi vào main_loop.
#
# Chế độ hoạt động (SW[1:0]):
#   00 : In N² (N=SW[9:2]) lên 6 màn HEX 7-đoạn
#   01 : Gửi SW[9:2] dạng 2 ký tự Hex ASCII qua UART TX
#   10 : Echo UART RX → TX
#   11 : Không định nghĩa, vòng lại main_loop
#
# Quy ước thanh ghi:
#   x2  (sp)  = Stack Pointer
#   x28 (t3)  = prev_sw_val (anti-spam Mode 01)
#   x30 (t5)  = hex_map DMEM base (0x2000_0000, set once in _init)
#   x31 (t6)  = SW_LED_BASE   (0x4000_0000, set once in _init)
# ==============================================================================

.equ SW_LED_BASE,  0x40000000
.equ HEX_BASE,     0x40001000
.equ KEY_BASE,     0x40002000
.equ UART_BASE,    0x40003000
.equ GPIO_BASE,    0x40004000
.equ HEX_MAP_BASE, 0x20000000   # DMEM address nơi lưu bảng mã 7-seg

.section .text
.globl _start

# ==============================================================================
# ENTRY POINT & STARTUP INITIALIZATION
# ==============================================================================
_start:
_init:
    # ── Stack Pointer ─────────────────────────────────────────────────────────
    li   x2,  0x20000FFC         # sp = đỉnh DMEM (4 KB - 4)

    # ── Khởi tạo bảng mã 7-đoạn (Common Anode) vào DMEM ─────────────────────
    # Lý do: LSU chỉ route LOAD sang DMEM (0x2000_xxxx).
    # Tra cứu từ IMEM sẽ làm treo CPU → phải đặt bảng tại DMEM.
    # Encoding: bit[7]=DP(off=1), bit[6:0]=gfedcba (0=segment ON)
    li   x30, HEX_MAP_BASE       # x30 = hex_map DMEM base (giữ cố định)
    # digit 0 → 0xC0 → bits[6:0]=0x40
    li   x6,  0xC0
    sb   x6,  0(x30)
    # digit 1 → 0xF9 → bits[6:0]=0x79
    li   x6,  0xF9
    sb   x6,  1(x30)
    # digit 2 → 0xA4 → bits[6:0]=0x24
    li   x6,  0xA4
    sb   x6,  2(x30)
    # digit 3 → 0xB0 → bits[6:0]=0x30
    li   x6,  0xB0
    sb   x6,  3(x30)
    # digit 4 → 0x99 → bits[6:0]=0x19
    li   x6,  0x99
    sb   x6,  4(x30)
    # digit 5 → 0x92 → bits[6:0]=0x12
    li   x6,  0x92
    sb   x6,  5(x30)
    # digit 6 → 0x82 → bits[6:0]=0x02
    li   x6,  0x82
    sb   x6,  6(x30)
    # digit 7 → 0xF8 → bits[6:0]=0x78
    li   x6,  0xF8
    sb   x6,  7(x30)
    # digit 8 → 0x80 → bits[6:0]=0x00
    li   x6,  0x80
    sb   x6,  8(x30)
    # digit 9 → 0x90 → bits[6:0]=0x10
    li   x6,  0x90
    sb   x6,  9(x30)

    # ── SW_LED_BASE cố định (tránh forwarding gap khi x5 bị overwrite bởi KEY_BASE) ──
    li   x31, SW_LED_BASE        # x31 = SW_LED_BASE (giữ cố định, không tái dùng)

    # ── Giá trị prev_sw (anti-spam Mode 01) ──────────────────────────────────
    li   x28, -1                 # x28 = 0xFFFFFFFF, lần đầu luôn gửi UART

# ==============================================================================
# MAIN LOOP
# ==============================================================================
main_loop:

    # ------------------------------------------------------------------
    # [A] KEY[0] — GLOBAL RESET (active-low, DE10-Standard)
    #     KEY nhấn = 0 → beqz đúng → nhảy về _init
    # ------------------------------------------------------------------
    li   x5,  KEY_BASE
    lw   x6,  0(x5)
    andi x6,  x6,  1
    beqz x6,  _init

    # ------------------------------------------------------------------
    # [B] SW → LED (mirror trạng thái switch)
    #     Dùng x31 (SW_LED_BASE cố định) thay vì li x5 để tránh
    #     forwarding gap khi x5 còn giữ KEY_BASE từ section [A].
    # ------------------------------------------------------------------
    lw   x6,  0(x31)            # x6 = SW[9:0]
    sw   x6,  0(x31)            # LED = SW

    # ------------------------------------------------------------------
    # [C] TÁCH DỮ LIỆU: SW[1:0]=MODE, SW[9:2]=VALUE
    # ------------------------------------------------------------------
    andi x8,  x6,  0x03         # x8 (s0) = MODE
    srli x9,  x6,  2
    andi x9,  x9,  0xFF         # x9 (s1) = VALUE (8-bit)

    # ------------------------------------------------------------------
    # [D] MODE MULTIPLEXER
    # ------------------------------------------------------------------
    li   x7,  0
    beq  x8,  x7,  mode_00
    li   x7,  1
    beq  x8,  x7,  mode_01
    li   x7,  2
    beq  x8,  x7,  mode_10
    j    main_loop              # Mode 11: không định nghĩa

# ==============================================================================
# MODE 00: In N² lên 6 màn HEX (N = SW[9:2])
#   Thuật toán: chia dư liên tiếp cho 10, lấy từng chữ số từ thấp lên cao.
#   Tra mã 7-seg từ hex_map (DMEM). Ghi thẳng raw code vào HEX peripheral.
#   Sau khi N=0: tắt trắng (0x7F = all-OFF) các màn còn lại.
# ==============================================================================
mode_00:
    mul  x10, x9,  x9           # x10 = N²
    li   x11, HEX_BASE          # x11 = địa chỉ HEX hiện tại
    li   x12, 6                 # x12 = bộ đếm màn (6 displays)
    li   x29, 10                # x29 = ước số

hex_loop:
    beqz x12, mode_00_done
    rem  x6,  x10, x29          # x6  = chữ số hàng đơn vị (x10 % 10)
    div  x10, x10, x29          # x10 = phần còn lại (x10 / 10)
    add  x7,  x30, x6           # x7  = &hex_map[chữ số]  (DMEM address)
    lbu  x7,  0(x7)             # x7  = mã 7-seg (lbu: zero-extend, bits[6:0] đúng)
    sw   x7,  0(x11)            # Ghi ra HEX peripheral
    addi x11, x11, 4            # Sang display tiếp
    addi x12, x12, -1
    beqz x10, fill_blank        # Số đã cạn → tắt trắng phần còn lại
    j    hex_loop

fill_blank:
    li   x7,  0x7F              # 0b111_1111 = tất cả đoạn tắt (common-anode)
blank_loop:
    beqz x12, mode_00_done
    sw   x7,  0(x11)
    addi x11, x11, 4
    addi x12, x12, -1
    j    blank_loop

mode_00_done:
    j    main_loop

# ==============================================================================
# MODE 01: Gửi VALUE (SW[9:2]) dạng 2 ký tự Hex ASCII qua UART TX
#   Ví dụ: VALUE=0x5A → gửi '5'(0x35) 'A'(0x41) '\r'(0x0D) '\n'(0x0A)
#   Anti-spam: chỉ gửi khi VALUE thay đổi so với lần trước (x28 = prev_val).
# ==============================================================================
mode_01:
    beq  x9,  x28, mode_01_done  # VALUE không đổi → bỏ qua
    mv   x28, x9                  # cập nhật prev_val

    srli x6,  x9,  4              # nibble cao [7:4]
    jal  x1,  tx_hex_char

    andi x6,  x9,  0x0F           # nibble thấp [3:0]
    jal  x1,  tx_hex_char

    li   x6,  13                  # CR
    jal  x1,  tx_char
    li   x6,  10                  # LF
    jal  x1,  tx_char

mode_01_done:
    j    main_loop

# --- Hàm con: nibble (0–15) → ASCII → gửi UART ---
# Vào : x6 = nibble value
# Dùng: x5, x7  |  Trả về: x1
tx_hex_char:
    li   x7,  10
    blt  x6,  x7,  tx_is_digit
    addi x6,  x6,  55            # 10+55=65='A' → 'A'..'F'
    j    tx_char
tx_is_digit:
    addi x6,  x6,  48            # 0+48=48='0' → '0'..'9'
    # fall-through

# --- Hàm con: gửi 1 byte ASCII (x6) qua UART TX ---
# Đợi tx_busy=0 (STATUS[0]) trước khi ghi TX_DATA
tx_char:
    li   x5,  UART_BASE
tx_wait:
    lw   x7,  8(x5)              # STATUS (offset +8)
    andi x7,  x7,  1             # [0] = tx_busy
    bnez x7,  tx_wait            # chờ khi UART đang truyền
    sw   x6,  0(x5)              # ghi byte vào TX_DATA (offset +0)
    jalr x0,  0(x1)              # return

# ==============================================================================
# MODE 10: Echo UART RX → TX
#   Poll rx_valid (STATUS[1]). Nếu có byte: đọc RX_DATA rồi gửi lại TX.
#   Không block nếu không có dữ liệu (tránh treo CPU trong vòng lặp chính).
# ==============================================================================
mode_10:
    li   x5,  UART_BASE

    lw   x6,  8(x5)              # STATUS
    andi x7,  x6,  2             # [1] = rx_valid
    beqz x7,  mode_10_done       # không có dữ liệu → về main

    lw   x10, 4(x5)              # RX_DATA (offset +4, tự clear rx_valid)
    andi x10, x10, 0xFF

echo_wait:
    lw   x6,  8(x5)
    andi x7,  x6,  1             # tx_busy
    bnez x7,  echo_wait
    sw   x10, 0(x5)              # echo byte ra TX

mode_10_done:
    j    main_loop

