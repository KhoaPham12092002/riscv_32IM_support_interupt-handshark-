# UART (Core) Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `core/uart.sv` là ngoại vi giao tiếp nối tiếp bất đồng bộ (Universal Asynchronous Receiver-Transmitter). Nó cho phép hệ thống truyền và nhận dữ liệu 8-bit qua 2 dây TX và RX.

**Tính năng chính:**
- Hoạt động Song công (Full-duplex): Có 2 FSM độc lập cho TX và RX.
- Tham số hóa linh hoạt: `CLK_FREQ` và `BAUD_RATE` cho phép tự tính toán chu kỳ lấy mẫu `CLKS_PER_BIT`.
- Tích hợp mạch đồng bộ hóa 2-tầng (Double-flop synchronizer) tại ngõ vào `rx_i` để chống Meta-stability.
- Lấy mẫu RX tại giữa chu kỳ bit (Middle of bit-period) giúp tăng khả năng chống nhiễu.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk_i`, `rst_ni` | Input | 1 | Clock và Reset (Active Low) |
| **TX Interface** ||| |
| `tx_data_i` | Input | 8 | Byte dữ liệu cần truyền |
| `tx_valid_i` | Input | 1 | Core báo có data hợp lệ cần truyền |
| `tx_ready_o` | Output| 1 | UART báo sẵn sàng (TX_IDLE) |
| `tx_o` | Output| 1 | Dây truyền tín hiệu nối tiếp ra ngoài |
| **RX Interface** ||| |
| `rx_data_o` | Output| 8 | Byte dữ liệu nhận được |
| `rx_valid_o` | Output| 1 | UART báo đã nhận xong 1 byte |
| `rx_ready_i` | Input | 1 | Core báo đã lấy byte dữ liệu đi |
| `rx_i` | Input | 1 | Dây nhận tín hiệu nối tiếp từ ngoài |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- **TX FSM:** 4 trạng thái (`IDLE`, `START`, `DATA`, `STOP`). Truyền LSB trước. Cờ `tx_ready_o` chỉ lên 1 ở `IDLE`.
- **RX FSM:** Tương tự 4 trạng thái. Chờ sườn xuống của Start bit, đợi nửa chu kỳ (`CLKS_PER_BIT / 2`) để check lại Start bit (False start detection). Sau đó lấy mẫu dữ liệu mỗi chu kỳ baud.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
