# Interrupt Controller Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `interrupt_control.sv` là một bộ điều khiển ngắt cơ bản (tương tự một bản thu gọn của CLINT/PLIC). Nó gom tất cả các đường ngắt rời rạc từ ngoại vi (Software, Timer, External), phân giải mức độ ưu tiên, và báo cáo lên khối CSR/Core.

**Tính năng chính:**
- Hỗ trợ 9 ngõ vào ngắt chia làm 3 nhóm chính chuẩn RISC-V: Software, Timer, External.
- Gộp cụm (OR Gate) để bật cờ tổng (vd: `irq_ext_o`).
- Bộ mã hóa độ ưu tiên (Priority Encoder) xác định Interrupt ID.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `irq_sw_x_i` | Input | 3 | Các tín hiệu ngắt phần mềm (A, B, C) |
| `irq_tmr_x_i`| Input | 3 | Các tín hiệu ngắt định thời (A, B, C) |
| `irq_ext_x_i`| Input | 3 | Các tín hiệu ngắt ngoại vi phần cứng (A, B, C) |
| `irq_sw_o` | Output| 1 | Cờ ngắt phần mềm báo lên CSR |
| `irq_timer_o`| Output| 1 | Cờ ngắt định thời báo lên CSR |
| `irq_ext_o` | Output| 1 | Cờ ngắt phần cứng báo lên CSR |
| `irq_id_o` | Output| 4 | Mã ID ngắt gửi lên Trap Handler/mcause |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- **Tầng 1 (Cờ tổng):** Các tín hiệu ngắt được gộp OR với nhau theo nhóm.
- **Tầng 2 (Bộ mã hóa ưu tiên):** Dùng chuỗi tổ hợp `if - else if` liên tiếp. 
  - Ưu tiên nhóm: External > Software > Timer.
  - Ưu tiên trong nhóm: Nguồn A > Nguồn B > Nguồn C.
  - Các ID (11, 12, 13, 3, 4, 7...) được hard-code theo một tiêu chuẩn do người thiết kế định nghĩa (Một phần giống bảng Cause của M-Mode RISC-V: M-External là 11, M-Timer là 7, M-Software là 3).

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
