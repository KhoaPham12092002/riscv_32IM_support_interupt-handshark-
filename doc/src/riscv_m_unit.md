# RISC-V M-Unit (Multiplier/Divider) Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `riscv_m_unit.sv` là bộ đồng xử lý toán học thực thi tập lệnh mở rộng M (M-Extension) của RISC-V. Nó chịu trách nhiệm giải quyết các phép Nhân và phép Chia số nguyên.

**Tính năng chính:**
- Phép Nhân (MUL, MULH, MULHSU, MULHU): Thực hiện trong **1 chu kỳ máy** bằng thuật toán tổ hợp.
- Phép Chia/Lấy dư (DIV, DIVU, REM, REMU): Thực hiện qua nhiều chu kỳ máy (multi-cycle) bằng thuật toán chia khôi phục (Restoring Division).
- Hỗ trợ đầy đủ các tổ hợp dấu (Có dấu/Không dấu) giữa toán hạng A và B.
- Xử lý mượt mà ngoại lệ Chia cho 0 (Divide-by-zero) theo đúng chuẩn RISC-V (Trả về All-1s cho DIV và trả về tử số cho REM).

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk`, `rst` | Input | 1 | Clock và Reset đồng bộ |
| `valid_i` | Input | 1 | Lệnh từ Core là hợp lệ và bắt đầu tính toán |
| `ready_o` | Output| 1 | M-Unit rảnh (Đang ở IDLE) |
| `m_in` | Input | Struct| Gói toán hạng (`rs1_data`, `rs2_data`) và mã lệnh (`op`) |
| `valid_o` | Output| 1 | Báo hiệu tính toán đã xong, kết quả khả dụng |
| `ready_i` | Input | 1 | Pipeline (Tầng MEM) báo đã nhận kết quả |
| `result_o` | Output| 32 | Kết quả 32-bit của phép Nhân/Chia |

**Giao thức:** Sử dụng Handshake Valid/Ready cơ bản.

---

## 3. Kiến trúc bên trong (Micro-architecture) & FSM
**Kiến trúc:**
- Khối Nhân: Là mạch tổ hợp dùng toán tử `$signed * $signed` để tổng hợp ra Multiplier cứng của FPGA. Kết quả 64-bit được lấy tùy thuộc vào MUL hay MULH.
- Khối Chia: Là một cỗ máy trạng thái tuần tự. Dùng một thanh ghi dịch 64-bit (`result_reg`) đóng vai trò vừa là bộ lưu Số dư (Remainder), vừa là bộ lưu Thương số (Quotient).

**FSM (Máy trạng thái):**
- `IDLE`: Chờ `valid_i`. Nếu là lệnh Nhân, gán kết quả và nhảy thẳng tới `DONE` (Tốn 1 cycle). Nếu là lệnh Chia, đưa toán hạng về dạng không dấu dương và nhảy tới `PREPARE`.
- `PREPARE`: Check chia cho 0. Nạp bộ đếm `count = 32`. Nhảy tới `DIV_LOOP`.
- `DIV_LOOP`: Thuật toán Restoring Division. Lặp lại 32 lần (Mất 32 cycle). Ở mỗi lần lặp, dịch trái 1 bit, trừ thử tử số cho mẫu số.
- `FIX_SIGN`: Trả lại dấu (- hay +) cho kết quả thương số/số dư dựa trên tổ hợp dấu đầu vào.
- `DONE`: Xuất `valid_o = 1`. Chờ `ready_i = 1` để về `IDLE`.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
