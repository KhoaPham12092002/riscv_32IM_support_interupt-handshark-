# Branch Comparator Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `branch_cmp.sv` là khối so sánh phân nhánh nằm tại tầng Execute (EX) hoặc Decode (tùy kiến trúc). Nó thực hiện việc so sánh toán học giữa 2 thanh ghi nguồn (RS1 và RS2) để quyết định xem lệnh Branch có nhảy (Taken) hay không nhảy (Not Taken).

**Tính năng chính:**
- Hỗ trợ đầy đủ 6 phép so sánh rẽ nhánh của RISC-V: Equal (BEQ), Not Equal (BNE), Less Than Signed/Unsigned (BLT, BLTU), Greater or Equal Signed/Unsigned (BGE, BGEU).

**Tính năng không hỗ trợ (Non-features):**
- Khối này chỉ ra quyết định đúng/sai. Nó KHÔNG tính toán địa chỉ đích (Target Address). Địa chỉ đích được tính bởi một bộ Adder (thường mượn ALU hoặc adder riêng).

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `rs1_i` | Input | 32 | Toán hạng 1 (từ thanh ghi hoặc forwarding) |
| `rs2_i` | Input | 32 | Toán hạng 2 |
| `br_op_i` | Input | Enum | Loại toán tử so sánh (BEQ, BLT...) |
| `branch_taken_o`| Output| 1 | `1` = Nhảy (Taken), `0` = Không nhảy |

**Giao thức & Clock/Reset:**
- Mạch tổ hợp thuần túy, không có clock/reset và không có handshake valid/ready.

---

## 3. Sơ đồ khối & Kiến trúc bên trong (Micro-architecture)
- Sử dụng các toán tử tổng hợp (Synthetic operators) như `==` và `<`.
- Khéo léo tối ưu số lượng bộ so sánh: Chỉ dùng một bộ so sánh bằng (`==`) và một bộ so sánh nhỏ hơn không dấu (`<`).
- Để so sánh nhỏ hơn có dấu (`is_less_s`), thay vì tốn thêm một bộ so sánh phần cứng, module dùng logic tự kiểm tra bit MSB (bit dấu):
  - Nếu khác dấu (sign1 != sign2): Dấu của `rs1` chính là kết quả (nếu `rs1` âm -> rs1 < rs2 luôn đúng).
  - Nếu cùng dấu: Chuyển về kết quả của bộ so sánh không dấu `is_less_u`.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
