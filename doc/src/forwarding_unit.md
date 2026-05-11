# Forwarding Unit Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** Giải quyết Data Hazard khi thực hiện Pipeline bằng kỹ thuật Data Forwarding (Bắt cầu dữ liệu). Thay vì Stall (dừng) đường ống khi có lệnh phụ thuộc dữ liệu, `forwarding_unit.sv` sẽ lấy kết quả phép tính từ các tầng phía sau (MEM, WB) "bơm" thẳng ngược lên tầng Execute (EX) cho lệnh hiện tại dùng.

**Tính năng chính:**
- Bypass dữ liệu từ tầng MEM về ngõ vào RS1/RS2 của EX (Trễ 1 nhịp - EX-to-EX hazard).
- Bypass dữ liệu từ tầng WB về ngõ vào RS1/RS2 của EX (Trễ 2 nhịp - MEM-to-EX hazard).
- Hỗ trợ logic ưu tiên (Priority): Nếu cả MEM và WB đều cùng cập nhật một thanh ghi, ưu tiên lấy dữ liệu mới nhất (từ MEM).

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `hz_ex_rs1_addr_i` | Input | 5 | Địa chỉ nguồn RS1 của lệnh đang ở tầng EX |
| `hz_ex_rs2_addr_i` | Input | 5 | Địa chỉ nguồn RS2 của lệnh đang ở tầng EX |
| `hz_mem_rd_addr_i` | Input | 5 | Địa chỉ đích RD của lệnh đang ở tầng MEM |
| `hz_mem_reg_we_i`  | Input | 1 | Lệnh ở MEM có ghi vào thanh ghi không? |
| `hz_wb_rd_addr_i`  | Input | 5 | Địa chỉ đích RD của lệnh đang ở tầng WB |
| `hz_wb_reg_we_i`   | Input | 1 | Lệnh ở WB có ghi vào thanh ghi không? |
| `ctrl_fwd_rs1_sel_o`| Output| 2 | Lệnh chọn ngõ Mux cho RS1 (00: No Fwd, 01: Fwd MEM, 10: Fwd WB) |
| `ctrl_fwd_rs2_sel_o`| Output| 2 | Lệnh chọn ngõ Mux cho RS2 |

**Giao thức:** Tổ hợp thuần túy (Combinational Logic). Không có valid/ready.

---

## 3. Kiến trúc bên trong (Micro-architecture)
- **Điều kiện Forward cơ bản:** Địa chỉ đích `rd` từ MEM/WB phải bằng địa chỉ nguồn `rs` tại EX, cờ `reg_we` phải bằng 1, và quan trọng nhất: địa chỉ phải **khác 0** (`!= 5'd0`). Trong RISC-V, thanh ghi x0 luôn bằng 0 và không bao giờ được forward.
- **Priority Logic:** Mạch dùng `if - else if` đảm bảo thứ tự ưu tiên: Ưu tiên MEM lên trên (kiểm tra trước). Nếu MEM thỏa mãn, bỏ qua WB.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
