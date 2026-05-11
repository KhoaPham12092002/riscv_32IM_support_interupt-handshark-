# Pipeline Register Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `pipeline_reg.sv` là một module tham số hóa (Parameterized module) mô tả cấu trúc của một thanh ghi đường ống (Pipeline Register). Nó dùng để chèn vào giữa các công đoạn xử lý (IF, ID, EX, MEM, WB) để lưu trữ gói dữ liệu và ngắt chuỗi trễ logic (Critical path).

**Tính năng chính:**
- Hoạt động như một chốt dữ liệu D-Flip-Flop với Handshake Valid/Ready đầy đủ.
- Có khả năng triệt tiêu dữ liệu ngay lập tức (Flush/Kill) khi có lệnh nhảy sai đường hoặc Trap (thông qua tín hiệu `flush_i` đồng bộ).
- Không tự xóa dữ liệu (No data wipe-out) khi flush, mà chỉ hạ cờ Valid xuống 0, giúp tiết kiệm cổng logic.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk_i`, `rst_i` | Input | 1 | Clock / Reset |
| `flush_i` | Input | 1 | Đồng bộ xóa Pipeline, chèn NOP |
| `valid_i` | Input | 1 | Ngõ vào: Dữ liệu đằng trước đã sẵn sàng |
| `ready_o` | Output| 1 | Ngõ ra: Bản thân thanh ghi có chỗ trống (hoặc xả kịp) |
| `data_i` | Input | `T_DATA`| Gói dữ liệu đầu vào (cấu hình qua Parameter) |
| `valid_o` | Output| 1 | Ngõ ra: Dữ liệu chứa trong thanh ghi là hợp lệ |
| `ready_i` | Input | 1 | Ngõ vào: Tầng phía sau đã sẵn sàng nhận |
| `data_o` | Output| `T_DATA`| Gói dữ liệu xuất ra tầng sau |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Mô hình **Skid Buffer / 1-Stage FIFO** rút gọn: Dùng một thanh ghi duy nhất để lưu trạng thái "Có dữ liệu" (`full_q`).
- **Data Path:** `data_o <= data_i` nếu thỏa mãn điều kiện `valid_i` và `ready_o`.
- **Control Path (Handshake):**
  - Tầng này sẵn sàng nhận dữ liệu (`ready_o = 1`) khi nó Đang Rỗng (`~full_q`), HOẶC là nó đang Đầy nhưng tầng sau sẽ lấy dữ liệu ngay trong chu kỳ này (`ready_i = 1`), tạo khoảng trống cho data mới chèn vào ngay lập tức.
  - Tầng này báo xuất valid (`valid_o = full_q`).

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
