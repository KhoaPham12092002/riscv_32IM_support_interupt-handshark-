# CSR (Control and Status Registers) Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** Khối `csr.sv` lưu trữ và quản lý các thanh ghi trạng thái và điều khiển (CSR) dùng cho kiến trúc đặc quyền Machine-Mode (M-mode) của RISC-V. Nó chịu trách nhiệm xử lý các lệnh đọc/ghi CSR từ tập lệnh (CSRRW, CSRRS, CSRRC) và lưu trữ trạng thái khi CPU gặp Ngoại lệ hoặc Ngắt (Exception/Trap/Interrupt).

**Tính năng chính:**
- Hỗ trợ tập thanh ghi thu gọn (Area Optimized) gồm: `mstatus`, `mie`, `mip`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`.
- Có logic tự động sập/mở ngắt toàn cục (MIE/MPIE trong `mstatus`) khi vào Trap hoặc khi gọi lệnh `MRET`.
- Cung cấp địa chỉ Vector ngắt (`mtvec`) cho PC và lưu địa chỉ lỗi (`mepc`) để quay về.
- Hỗ trợ kết nối các ngắt phần cứng (Timer, Software, External).

**Tính năng không hỗ trợ:**
- Không hỗ trợ User-mode (U-mode) hay Supervisor-mode (S-mode).
- Không hỗ trợ thanh ghi bộ đếm hiệu năng (Performance Counters như `mcycle`, `minstret`).

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `csr_req_i` | Input | Struct| Request từ Core: valid, addr, wdata, op |
| `csr_ready_o` | Output| 1 | Báo hiệu khối CSR đang không bận (hoặc không bị Trap chặn) |
| `csr_rdata_o` | Output| 32 | Dữ liệu thanh ghi đọc ra |
| `csr_rsp_valid_o`| Output| 1 | Xác nhận lệnh đọc CSR đã thành công |
| `trap_valid_i`| Input | 1 | Tín hiệu báo có Trap/Interrupt |
| `trap_cause_i`| Input | 4 | Mã nguyên nhân Trap (lưu vào mcause) |
| `trap_pc_i` | Input | 32 | Địa chỉ của lệnh gây Trap (lưu vào mepc) |
| `trap_val_i` | Input | 32 | Thông tin thêm về Trap (lưu vào mtval) |
| `mret_i` | Input | 1 | Tín hiệu báo lệnh MRET |
| `epc_o` / `trap_vector_o` | Output| 32 | Địa chỉ quay về / Địa chỉ ngắt (gửi PC_Gen) |
| `irq_sw_i`, `irq_timer_i`, `irq_ext_i`| Input| 1 | Dây cắm tín hiệu ngắt từ bên ngoài |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Sử dụng mô hình thanh ghi kết hợp logic tổ hợp tạo ra Data: 
  - Phần **Read**: Là tổ hợp (Combinational) sử dụng Multiplexer đa kênh khổng lồ để lấy tín hiệu từ các Flip-Flop gán ra `csr_rdata_o`.
  - Phần **Write**: Đồng bộ sườn lên clock theo cờ Write-Enable (`we_mstatus`, `we_mepc`...).
  - Phần **Update logic**: `mstatus` và `mepc` phức tạp nhất do vừa nhận giá trị Ghi từ Software (bằng lệnh CSR), lại vừa có thể bị phần cứng ép đè (Overwrite) khi có sự kiện Trap hay MRET. Sự ưu tiên: Trap/MRET > Software Write.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** Tín hiệu `csr_rsp_valid_o` hiện tại được nối tổ hợp thẳng từ tín hiệu Handshake đầu vào. Khi ráp với AXI4-Lite (có độ trễ kênh Response), cách đấu nối này có thể làm AXI Controller bị rối loạn.
- **Đề xuất giải quyết:** Cần tách bạch kênh Request và kênh Response bằng thanh ghi hoặc FSM khi thiết kế module AXI Wrapper cho CSR.
