# Data Memory Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `dmem.sv` đóng vai trò là bộ nhớ dữ liệu (RAM) cục bộ của hệ thống. Khối LSU giao tiếp với nó để ghi và đọc dữ liệu cho các lệnh như `LW, SW, SB, LBU...`.

**Tính năng chính:**
- Đọc/Ghi đồng bộ (Synchronous Read/Write) mất 1 nhịp clock.
- Hỗ trợ Ghi theo từng Byte (Byte Enable masking), rất thiết yếu cho lệnh SB và SH.
- Trả về cờ hợp lệ (`rsp_valid_o`) ngay cả đối với lệnh Ghi (Store) để báo cho LSU biết giao dịch đã hoàn tất.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `req_valid_i` | Input | 1 | Request có giá trị |
| `req_ready_o` | Output| 1 | Bộ nhớ rảnh để nhận request |
| `req_addr_i` | Input | 32 | Địa chỉ thao tác (đã Word-aligned) |
| `req_wdata_i` | Input | 32 | Dữ liệu để Ghi |
| `req_be_i` | Input | 4 | Byte Enable (Từng bit bật cho phép ghi từng byte) |
| `req_we_i` | Input | 1 | Lệnh 1 = Ghi, 0 = Đọc |
| `rsp_valid_o` | Output| 1 | Báo quá trình đọc/ghi đã thành công |
| `rsp_ready_i` | Input | 1 | LSU báo đã nhận phản hồi |
| `rsp_rdata_o` | Output| 32 | Dữ liệu xuất ra (với lệnh đọc) |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Dùng `always @(posedge clk_i)` thay vì `always_ff` để tối ưu cảnh báo mô phỏng của vài tool biên dịch về việc trộn lẫn logic reset và initial block.
- Khối Handshake giống hệt `imem.sv`.
- Block Ghi phân mảnh: Tách `wdata` 32-bit thành 4 cụm 8-bit, ghi vào `mem_array` tùy thuộc bit tương ứng trong `req_be_i` có bằng 1 hay không.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
