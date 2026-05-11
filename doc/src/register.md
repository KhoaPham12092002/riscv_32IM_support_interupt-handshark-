# Register File Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `register.sv` là tập thanh ghi trung tâm (Register File) của kiến trúc RISC-V 32-bit. Đây là nơi chứa 32 thanh ghi đa dụng (General Purpose Registers - GPRs) từ x0 đến x31.

**Tính năng chính:**
- **3 Cổng (3-Port RAM):** Có 2 cổng đọc dữ liệu (Read ports) và 1 cổng ghi dữ liệu (Write port).
- Xử lý đặc biệt cho thanh ghi zero (`x0` / `zero`), luôn trả về giá trị 0 và không cho phép ghi đè lên nó.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk_i`, `rst_i` | Input | 1 | Clock và Reset đồng bộ |
| `w_ena_i` | Input | 1 | Tín hiệu Write Enable (từ WB stage) |
| `w_addr_i` | Input | 5 | Địa chỉ thanh ghi đích để ghi |
| `w_data_i` | Input | 32 | Dữ liệu cần ghi |
| `r1_addr_i` | Input | 5 | Địa chỉ nguồn RS1 cần đọc (từ ID) |
| `r1_data_o` | Output| 32 | Dữ liệu đọc ra cổng 1 |
| `r2_addr_i` | Input | 5 | Địa chỉ nguồn RS2 cần đọc (từ ID) |
| `r2_data_o` | Output| 32 | Dữ liệu đọc ra cổng 2 |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- **Cấu trúc lưu trữ:** Dùng một mảng 31 phần tử 32-bit `logic [31:0] rf [31:1];` (không có phần tử 0).
- **Asynchronous Read:** Hai ngõ ra `r1_data_o` và `r2_data_o` là thuần tổ hợp. Thay đổi địa chỉ `rX_addr_i` sẽ lập tức thay đổi `rX_data_o` mà không cần đợi sườn clock. Nếu địa chỉ là 0, lập tức ép kết quả trả về `32'h0`.
- **Synchronous Write:** Ghi dữ liệu đồng bộ theo sườn lên của clock nếu có tín hiệu `w_ena_prot`.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
