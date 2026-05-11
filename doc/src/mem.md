# Memory Wrapper Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `mem.sv` là một module đóng gói (Wrapper) toàn bộ phân hệ bộ nhớ của hệ thống. Thay vì Core phải cắm hàng chục dây cáp tới từng khối IMEM và DMEM riêng rẽ, module này gom chúng lại. Nó cũng chứa luôn khối LSU (Load/Store Unit) bên trong để xử lý việc dịch địa chỉ truy xuất dữ liệu trước khi gửi xuống DMEM thực sự.

**Tính năng chính:**
- Khởi tạo khối nhớ lệnh `imem.sv` và nạp file hex.
- Khởi tạo khối Load/Store Unit `lsu.sv`.
- Khởi tạo khối nhớ dữ liệu `dmem.sv`.
- Kết nối các luồng dữ liệu (Routing) từ Core -> LSU -> DMEM nội bộ.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `if_req_...`, `if_rsp_...` | In/Out| Mix | Luồng lấy lệnh từ Core cắm thẳng vào `imem` |
| `lsu_addr_i`, `lsu_wdata_i`| Input | 32 | Luồng truy xuất dữ liệu từ Core |
| `lsu_req_...`, `lsu_rsp_...`| In/Out| Mix | Tín hiệu bắt tay truy cập dữ liệu với Core |
| `lsu_rdata_o`, `lsu_err_o` | Output| 32/1| Trả kết quả đọc dữ liệu hoặc báo lỗi (Misaligned) |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Thiết kế Structural thuần túy. 
- Mọi dây cáp (Kênh Request và Kênh Response) nối giữa LSU và DMEM được bọc gọn hoàn toàn bên trong file này, không lộ ra ngoài Core, giúp giảm số lượng cổng kết nối ở Top Module.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
