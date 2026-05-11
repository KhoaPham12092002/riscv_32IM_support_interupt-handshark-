# Instruction Memory Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `imem.sv` là khối nhớ đóng vai trò bộ nhớ chương trình (ROM/RAM). Nó chứa các mã máy (Instruction) của chương trình và cung cấp chúng cho lõi xử lý (Core) tại tầng Fetch.

**Tính năng chính:**
- Hỗ trợ tham số hóa kích thước bộ nhớ (`MEM_SIZE`) và file khởi tạo (`HEX_FILE`).
- Ánh xạ địa chỉ (Address Mapping): Chuyển đổi địa chỉ Byte (từ PC) sang địa chỉ Word để truy xuất mảng nhớ tĩnh.
- Trả về lệnh NOP (`32'h0000_0013`) khi địa chỉ PC vượt ra ngoài giới hạn bộ nhớ, giúp hệ thống không bị crash.

**Tính năng không hỗ trợ:**
- Khối này là Read-Only đối với hệ thống đường ống (Pipeline), không hỗ trợ ghi.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `req_valid_i` | Input | 1 | Cờ báo Core muốn đọc lệnh mới tại `req_addr_i` |
| `req_addr_i` | Input | 32 | Địa chỉ Byte từ PC |
| `req_ready_o` | Output| 1 | IMEM báo sẵn sàng xử lý yêu cầu đọc |
| `rsp_valid_o` | Output| 1 | Lệnh tại ngõ ra đã sẵn sàng để lấy |
| `rsp_ready_i` | Input | 1 | Tầng Decoder/IF-ID pipeline báo đã lấy lệnh |
| `rsp_instr_o` | Output| 32 | Mã lệnh đọc ra |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Mô hình lưu trữ: Mảng `logic [31:0] mem_array`.
- Khối Handshake (Tránh sập Timing): `assign req_ready_o = ~rsp_valid_o || rsp_ready_i;`
- **Synchronous Read:** Quá trình đọc diễn ra đồng bộ theo xung Clock. Mất 1 nhịp clock để dữ liệu từ địa chỉ được xuất ra ngõ `rsp_instr_o` kèm theo cờ `rsp_valid_o = 1`.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
