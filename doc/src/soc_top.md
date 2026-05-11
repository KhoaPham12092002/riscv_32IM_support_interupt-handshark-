# SoC Top Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `soc_top.sv` là đỉnh chóp của toàn bộ cấu trúc phần cứng (Top-level Module). Đây là thực thể sẽ được đưa đi tổng hợp (Synthesis) lên FPGA hoặc dùng làm khối DUT (Device Under Test) cuối cùng trong Testbench.

**Tính năng chính:**
- Bao bọc toàn bộ hệ thống từ Não bộ (Control), Cơ bắp (Datapath), Hệ miễn dịch (CSR) đến Kho lưu trữ (Memory - IMEM, DMEM).
- Khép kín các đường Bus Memory bên trong, hệ thống bây giờ có thể tự chạy code được nạp sẵn mà không cần giao tiếp nhớ bên ngoài.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk_i` | Input | 1 | Nguồn Clock tổng |
| `rst_i` | Input | 1 | Nút Reset tổng |
| `irq_sw_i`, `irq_timer_i`, `irq_ext_i` | Input | 1 | Nút bấm hoặc nguồn ngắt từ bên ngoài |

**Giao thức:** Hệ thống khép kín, giao tiếp với môi trường ngoài chỉ còn phụ thuộc vào Clock, Reset và Interrupt.

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Instantiate 4 khối trụ cột:
  1. `riscv_datapath`
  2. `riscv_control`
  3. `csr`
  4. `mem`
- Cáp kết nối bộ nhớ giữa Core (Datapath) và `mem` được bọc bên trong file này.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
