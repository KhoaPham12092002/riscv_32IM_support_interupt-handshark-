# Hazard Unit Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `hazard_unit.sv` chịu trách nhiệm giải quyết các Hazard mạnh mà Forwarding không thể xử lý nổi, bắt buộc phải làm "kẹt" (Stall) hoặc "xóa" (Flush/Kill) các lệnh trong đường ống.

**Tính năng chính:**
- **Giải quyết Data Hazard (Load-Use):** Khi lệnh phía trước là lệnh Load đang nằm ở tầng EX, và lệnh sau ngay lập tức dùng kết quả đó tại tầng ID. Bắt buộc phải Stall tầng IF và ID, đồng thời chèn bong bóng (NOP) vào tầng EX bằng flush.
- **Giải quyết Control Hazard (Jump/Branch Trap):** Khi có một lệnh Branch/Jump được xác nhận (có thể tại EX hoặc MEM), tín hiệu `jump_trap_i` = 1, Hazard Unit sẽ ra lệnh dọn dẹp lệnh bị fetch sai đường ở các tầng trước đó (IF, ID).

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `hz_id_rs1_addr_i` | Input | 5 | Địa chỉ nguồn RS1 tầng ID |
| `hz_id_rs2_addr_i` | Input | 5 | Địa chỉ nguồn RS2 tầng ID |
| `hz_ex_rd_addr_i`  | Input | 5 | Địa chỉ đích RD tầng EX |
| `hz_ex_reg_we_i`   | Input | 1 | Lệnh tầng EX có write reg không? |
| `hz_ex_wb_sel_i`   | Input | enum| Nguồn Write-back tầng EX (WB_MEM, WB_ALU...) |
| `jump_trap_i`      | Input | 1 | 1 = Jump/Branch Taken / Trap xảy ra |
| `ctrl_force_stall_id_o` | Output | 1 | Lệnh ép Stall pipeline tại tầng ID |
| `ctrl_flush_if_id_o`    | Output | 1 | Lệnh Flush thanh ghi IF/ID |
| `ctrl_flush_id_ex_o`    | Output | 1 | Lệnh Flush thanh ghi ID/EX |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- **Bắt bệnh Load-Use:**
  Phát hiện qua tín hiệu `hz_ex_wb_sel_i == WB_MEM` (nghĩa là lệnh ở EX là lệnh Load bộ nhớ). Nếu RD của lệnh Load này trùng với RS1 hoặc RS2 của lệnh tại ID, thì `is_load_use = 1`.
- **Phát sinh tín hiệu can thiệp:**
  - Nếu `jump_trap_i` = 1 (Control hazard): Flush cả IF/ID và ID/EX.
  - Nếu `is_load_use` = 1: Bật `ctrl_force_stall_id_o` để bóp nghẹt Valid/Ready tại tầng ID (Handshake sẽ kìm IF lại). Đồng thời Flush `ctrl_flush_id_ex_o` để nhét bong bóng vào EX.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
