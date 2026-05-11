# UART (32-bit Custom) Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `uart.sv` (nằm ở thư mục gốc src) là một biến thể UART tùy chỉnh (Custom) được thiết kế đặc biệt để truyền/nhận gói dữ liệu khổng lồ **32-bit** thay vì 8-bit tiêu chuẩn.

**Tính năng chính:**
- Truyền/Nhận liên tục 32 bit dữ liệu chỉ với 1 Start bit và 1 Stop bit. 
- Tiết kiệm Start/Stop overhead khi gửi các Word 32-bit liên tiếp.

**Tính năng không hỗ trợ:**
- Khối này hoàn toàn phá vỡ tiêu chuẩn giao thức UART công nghiệp (8-N-1). Các Terminal máy tính (như TeraTerm, PuTTY) sẽ KHÔNG THỂ giao tiếp trực tiếp với khối này. Nó chỉ dùng để giao tiếp chip-to-chip hoặc phục vụ Testbench.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk`, `rst_n` | Input | 1 | Clock và Reset Active Low |
| `tx_data`, `rx_data`| In/Out| 32 | Dữ liệu truyền nhận 32-bit |
| `tx_valid`, `tx_ready`| In/Out| 1 | Handshake TX |
| `tx_out`, `rx_in` | Out/In| 1 | Dây nối tiếp TX/RX |
| `rx_valid` | Output| 1 | Cờ báo RX hoàn tất 32-bit |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Sử dụng FSM 4 trạng thái như UART thường.
- Biến đếm `tx_bit_idx` và `rx_bit_idx` được mở rộng lên 5-bit (đếm từ 0 đến 31).
- Shift Register được mở rộng thành 32-bit.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** Khối RX không có tín hiệu `rx_ready_i` để nhận back-pressure từ Core. Cờ `rx_valid` chỉ nháy đúng 1 nhịp clock rồi tắt, nếu hệ thống không đọc kịp nhịp đó thì dữ liệu bị rớt (Data drop).
- **Warning:** Mất mát gói tin khi CPU bận hoặc pipeline bị stall.
- **Đề xuất giải quyết:** Thêm tín hiệu `rx_ready_i` vào khối UART 32-bit. Giữ `rx_valid = 1` cho tới khi `rx_ready_i = 1` mới được thả cờ xuống.
