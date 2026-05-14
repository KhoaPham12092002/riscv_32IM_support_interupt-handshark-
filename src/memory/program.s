# ==============================================================================
# RISC-V RV32IM Assembly Program cho DE10-Standard FPGA
# Tác giả: LVTN - THESIS BK 2026
# ==============================================================================

# --- ĐỊNH NGHĨA ĐỊA CHỈ CƠ SỞ ---
.equ SW_LED_BASE, 0x40000000
.equ KEY_BASE,    0x40002000
.equ UART_BASE,   0x40003000
.equ HEX_BASE,    0x40004000

# --- VÙNG NHỚ DỮ LIỆU ---
.section .data
# Bảng mã 7-segment (Common Anode) từ 0-9
hex_map: 
    .byte 0xC0, 0xF9, 0xA4, 0xB0, 0x99, 0x92, 0x82, 0xF8, 0x80, 0x90

# --- VÙNG NHỚ MÃ LỆNH ---
.section .text
.globl _start

_start:
    # 1. Khởi tạo Stack Pointer (Top of 4KB DMEM)
    li x2, 0x20000FFC       # x2 (sp)

    # 2. Khởi tạo biến nhớ tạm cho Mode 01 (Chống Spam UART)
    li x28, -1              # x28 (t3) = prev_sw_val, gán -1 để đảm bảo lần đầu tiên luôn in

main_loop:
    # -----------------------------------------------------------
    # [A] XỬ LÝ KEY[0] - GLOBAL RESET
    # -----------------------------------------------------------
    li x5, KEY_BASE         # x5 (t0) = Address KEY
    lw x6, 0(x5)            # x6 (t1) = Giá trị KEY đọc được
    andi x6, x6, 1          # Lọc lấy KEY[0]
    beqz x6, _start         # DE10-Standard nút nhấn Active-Low. Nếu = 0 -> Nhấn -> Reset.

    # -----------------------------------------------------------
    # [B] XỬ LÝ SW & LED THỂ HIỆN TRẠNG THÁI
    # -----------------------------------------------------------
    li x5, SW_LED_BASE      
    lw x6, 0(x5)            # Đọc SW input vào x6 (t1)
    sw x6, 0(x5)            # Xuất trực tiếp ra LED output (Cùng base address)

    # -----------------------------------------------------------
    # [C] TÁCH DỮ LIỆU (MODE & VALUE)
    # -----------------------------------------------------------
    andi x8, x6, 0x03       # x8 (s0) = SW[1:0] (Mode Select)
    srli x9, x6, 2          # Dịch phải 2 bit
    andi x9, x9, 0xFF       # x9 (s1) = SW[9:2] (Value input)

    # -----------------------------------------------------------
    # [D] BỘ CHỌN CHẾ ĐỘ (MODE MULTIPLEXER)
    # -----------------------------------------------------------
    li x7, 0
    beq x8, x7, mode_00     # Nếu x8 == 0 -> Mode 00
    li x7, 1
    beq x8, x7, mode_01     # Nếu x8 == 1 -> Mode 01
    li x7, 2
    beq x8, x7, mode_10     # Nếu x8 == 2 -> Mode 10
    
    j main_loop             # Mode 11 (Không định nghĩa) -> Quay lại loop

# ==============================================================================
# MODE 00: In số chính phương lên 6 LED 7-Đoạn (HEX)
# ==============================================================================
mode_00:
    mul x10, x9, x9         # x10 (a0) = s1 * s1 (Bình phương giá trị SW[9:2])
    li x11, HEX_BASE        # x11 (a1) = Địa chỉ HEX hiện tại
    li x12, 6               # x12 (a2) = Bộ đếm số lượng HEX (6 cái)
    li x29, 10              # x29 (t4) = Số chia (10)
    la x30, hex_map         # x30 (t5) = Địa chỉ Base của Lookup Table

hex_extract_loop:
    beqz x12, mode_00_done  # Đã in đủ 6 HEX thì thoát
    
    rem x6, x10, x29        # x6 (t1) = a0 % 10 (Lấy chữ số hàng đơn vị)
    div x10, x10, x29       # a0 = a0 / 10 (Loại bỏ chữ số vừa lấy)

    add x7, x30, x6         # x7 (t2) = Địa chỉ mã 7-seg tương ứng chữ số
    lb x7, 0(x7)            # Load mã 7-seg (byte)
    sw x7, 0(x11)           # Ghi ra phần cứng HEX hiện tại

    addi x11, x11, 4        # Trỏ tới HEX tiếp theo (Offset 4 bytes)
    addi x12, x12, -1       # Giảm bộ đếm HEX

    # Tối ưu: Nếu a0 == 0 (Đã in xong số), tắt toàn bộ các HEX còn lại (Blanking)
    beqz x10, fill_blank    
    j hex_extract_loop

fill_blank:
    li x7, 0xFF             # Mã 0xFF làm tắt hoàn toàn (Common Anode)
blank_loop:
    beqz x12, mode_00_done  # Đã tắt đủ các HEX dư thì thoát
    sw x7, 0(x11)           
    addi x11, x11, 4
    addi x12, x12, -1
    j blank_loop

mode_00_done:
    j main_loop

# ==============================================================================
# MODE 01: Gửi giá trị SW[9:2] dạng mã Hex (ASCII) qua UART TX (Putty)
# ==============================================================================
mode_01:
    # Tối ưu UART TX: Chỉ truyền khi giá trị SW thay đổi
    beq x9, x28, mode_01_done # Nếu giá trị hiện tại == giá trị cũ, bỏ qua
    mv x28, x9              # Cập nhật giá trị cũ x28 (t3) = x9 (s1)

    # In Nibble cao (4 bit đầu)
    srli x6, x9, 4          
    jal x1, tx_hex_char

    # In Nibble thấp (4 bit cuối)
    andi x6, x9, 0x0F       
    jal x1, tx_hex_char

    # Gửi ký tự xuống dòng (\r \n)
    li x6, 13               # '\r'
    jal x1, tx_char
    li x6, 10               # '\n'
    jal x1, tx_char

mode_01_done:
    j main_loop

# --- Hàm con (Subroutine) cho Mode 01 ---
tx_hex_char:
    # Đầu vào: x6 chứa 1 số Hex từ 0-15. Nhiệm vụ: Đổi sang ASCII tương ứng.
    li x7, 10
    blt x6, x7, tx_is_digit
    addi x6, x6, 55         # Nếu >= 10: Chuyển thành 'A'-'F' (x6 + 55)
    j tx_char
tx_is_digit:
    addi x6, x6, 48         # Nếu < 10: Chuyển thành '0'-'9' (x6 + 48)

tx_char:
    # Gửi 1 ký tự ASCII trong x6 qua UART
    li x5, UART_BASE
tx_wait:
    lw x7, 8(x5)            # Đọc thanh ghi STATUS (Offset 8)
    andi x7, x7, 1          # Kiểm tra bit 0 (TX_READY)
    beqz x7, tx_wait        # Nếu bận, chờ đến khi rảnh
    sw x6, 0(x5)            # Ghi Data vào TX_REG (Offset 0)
    jalr x0, 0(x1)          # Return (ret)

# ==============================================================================
# MODE 10: Đọc từ UART RX và hồi đáp (Echo) ra UART TX
# ==============================================================================
mode_10:
    li x5, UART_BASE
    
    # 1. Kiểm tra có dữ liệu tới (RX_VALID) không
    lw x6, 8(x5)            # Đọc STATUS
    andi x7, x6, 2          # Kiểm tra bit 1 (RX_VALID)
    beqz x7, mode_10_done   # Không có dữ liệu, về main loop (Tránh treo CPU)

    # 2. Đọc dữ liệu
    lw x10, 4(x5)           # Đọc byte từ RX_REG (Offset 4) vào x10 (a0)
    andi x10, x10, 0xFF     # Lọc bỏ nhiễu, giữ đúng 8-bit Data

    # 3. Echo dữ liệu đó lên TX
echo_wait:
    lw x6, 8(x5)            
    andi x7, x6, 1          # Chờ TX_READY (Bit 0)
    beqz x7, echo_wait
    sw x10, 0(x5)           # Gửi lại byte đó ra Putty

mode_10_done:
    j main_loop