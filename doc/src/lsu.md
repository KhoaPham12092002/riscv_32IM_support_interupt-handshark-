# LSU (Load Store Unit) Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `lsu.sv` là khối Load/Store Unit đóng vai trò cầu nối giao tiếp giữa Core (cụ thể là đường ống thực thi) và Data Memory (DMEM). Khối này xử lý các lệnh truy xuất bộ nhớ như Load (LB, LH, LW, LBU, LHU) và Store (SB, SH, SW).

**Tính năng chính:**
- Hỗ trợ các độ dài truy xuất: Byte (8-bit), Half-word (16-bit), Word (32-bit).
- Hỗ trợ việc mở rộng dấu (Sign-extension) hoặc không mở rộng dấu (Zero-extension) cho lệnh Load.
- Phát hiện lỗi truy xuất bộ nhớ không thẳng hàng (Misaligned memory access) và sinh tín hiệu Trap (`lsu_err_o`).
- Tách biệt kênh Request và Response (giao tiếp kênh đôi) với Data Memory.

**Tính năng không hỗ trợ (Non-features):**
- Không có bộ đệm Cache bên trong.
- Không hỗ trợ các truy xuất atomic (A-extension) hoặc floating point.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

### Bảng Port List:
| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk_i` | Input | 1 | Clock hệ thống |
| `rst_i` | Input | 1 | Reset hệ thống (Active-high) |
| **Giao tiếp với Core** | | | |
| `addr_i` | Input | 32 | Địa chỉ truy xuất từ Core |
| `wdata_i` | Input | 32 | Dữ liệu cần ghi (dùng cho Store) |
| `lsu_we_i` | Input | 1 | 1 = Store (Ghi), 0 = Load (Đọc) |
| `funct3_i` | Input | 3 | Xác định Data type (000=B, 001=H, 010=W, 100=BU, 101=HU) |
| `valid_i` | Input | 1 | Core báo có request hợp lệ |
| `ready_o` | Output | 1 | LSU báo sẵn sàng nhận request mới |
| `valid_o` | Output | 1 | LSU báo dữ liệu Load hoặc quá trình Store đã xong |
| `ready_i` | Input | 1 | Core báo đã sẵn sàng nhận kết quả trả về từ LSU |
| `lsu_rdata_o` | Output | 32 | Dữ liệu Load trả về cho Core |
| `lsu_err_o` | Output | 1 | Báo lỗi Misaligned Trap |
| **Giao tiếp với DMEM** | | | |
| `dmem_req_valid_o` | Output | 1 | LSU báo yêu cầu truy xuất mem hợp lệ |
| `dmem_req_ready_i` | Input | 1 | DMEM báo sẵn sàng nhận yêu cầu |
| `dmem_addr_o` | Output | 32 | Địa chỉ gửi tới DMEM (Word-aligned) |
| `dmem_wdata_o` | Output | 32 | Dữ liệu gửi tới DMEM (đã shift byte tùy offset) |
| `dmem_be_o` | Output | 4 | Byte Enable tương ứng với vùng nhớ cần ghi |
| `dmem_we_o` | Output | 1 | 1 = Ghi, 0 = Đọc |
| `dmem_rsp_valid_i` | Input | 1 | DMEM báo đã có dữ liệu trả về hợp lệ |
| `dmem_rsp_ready_o` | Output | 1 | LSU sẵn sàng nhận dữ liệu trả về |
| `dmem_rdata_i` | Input | 32 | Dữ liệu đọc từ DMEM |

**Giao thức (Protocols):**
- Sử dụng Valid/Ready handshake tiêu chuẩn cả ở ngõ Core và ngõ DMEM. Kênh DMEM được chia làm 2 phase độc lập: Request (gửi lệnh, địa chỉ) và Response (trả data).
  
**Clock & Reset:**
- Chạy chung một clock domain `clk_i`.
- Reset đồng bộ, tích cực mức cao `rst_i`.

---

## 3. Sơ đồ khối & Kiến trúc bên trong (Block Diagram & Micro-architecture)

**Datapath:**
- **Store Path:** Dữ liệu (`wdata_i`) và Byte Enable (`dmem_be_o`) được dịch tương ứng với 2 bit offset của `addr_i`. (VD: Offset = 2'b01 -> dịch trái 8 bit).
- **Load Path:** Dữ liệu trả về `dmem_rdata_i` đi qua các bộ MUX (8-bit hoặc 16-bit) chọn byte/half-word tùy vào offset, sau đó qua một tầng kết hợp để Sign-extend hoặc Zero-extend để ra được giá trị 32-bit cuối cùng.

**Control Path:**
- Dùng một máy trạng thái FSM (4 trạng thái) để quản lý tiến trình gửi Request và đợi Response.
- Bộ logic tổ hợp liên tục kiểm tra 2 bit cuối của `addr_i` kết hợp với `funct3_i` để phát hiện truy cập Misaligned (VD: Word access không chia hết cho 4). Nếu bị Misaligned, FSM sẽ bỏ qua gửi request xuống bộ nhớ mà rẽ ngay nhánh báo lỗi Trap.

---

## 4. Máy trạng thái (FSM - Finite State Machine)

- **IDLE:** Đứng chờ. Khi `valid_i = 1`, lưu các tín hiệu input vào Flip-flop. 
  - Nếu `misaligned = 1`, nhảy tới `DONE` (chuẩn bị báo lỗi Trap).
  - Nếu `misaligned = 0`, nhảy tới `SEND_REQ`.
- **SEND_REQ:** Kéo cờ `dmem_req_valid_o = 1` cùng các tín hiệu địa chỉ, write data. 
  - Đợi `dmem_req_ready_i = 1` thì chuyển sang `WAIT_RSP`.
- **WAIT_RSP:** Kéo cờ `dmem_rsp_ready_o = 1`. 
  - Đợi `dmem_rsp_valid_i = 1` thì chuyển sang `DONE`.
- **DONE:** Request hoàn tất (có thể thành công hoặc do Misaligned trap). 
  - Kéo cờ `valid_o = 1`. Đợi `ready_i = 1` từ Core thì quay lại `IDLE`.

---

## 5. Giản đồ thời gian (Timing Diagrams & Waveforms)

**Normal Handshake (VD: Load Word thành công):**
1. Core đưa `valid_i=1`. Cycle sau, LSU vào trạng thái `SEND_REQ`.
2. LSU đưa `dmem_req_valid_o=1`. DMEM đáp ứng bằng `dmem_req_ready_i=1`.
3. Cycle sau, LSU vào `WAIT_RSP` và đưa `dmem_rsp_ready_o=1`.
4. DMEM đưa dữ liệu và bật `dmem_rsp_valid_i=1`.
5. Cycle sau, LSU vào `DONE` và bật `valid_o=1` đưa kết quả về Core.

**Back-pressure / Stall:**
- Nếu Core gửi request mới nhưng `ready_o = 0` (LSU đang ở trạng thái không phải IDLE), request đó sẽ phải giữ nguyên tới khi LSU về IDLE.
- Nếu ở `SEND_REQ` mà DMEM chưa đưa `dmem_req_ready_i = 1`, FSM sẽ stall ở trạng thái này vô thời hạn.

---

## 6. Bản đồ Thanh ghi (Register Map)
- Đây là một module Datapath/Control nội bộ (trong Core), không giao tiếp qua bus System (như AXI/APB) với vai trò Peripheral có thanh ghi cấu hình. Vì vậy không có Memory-Mapped Registers.

---

## 7. Tham số hóa (Parameters & Configurations)
- Module không sử dụng tham số (Parameters) nội bộ, các kích thước data/address đều bị hard-code là 32-bit theo chuẩn RV32I.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** LSU đọc trực tiếp `dmem_rdata_i` tại state `DONE` trong khi data chỉ được đảm bảo hợp lệ ở chu kỳ `WAIT_RSP` (vì `dmem_rsp_valid_i` có thể chỉ nảy 1 chu kỳ).
- **Warning:** Có thể dẫn đến việc đọc dữ liệu rác nếu Data Memory không giữ tín hiệu sau khi Handshake kết thúc.
- **Đề xuất giải quyết:** Thêm một thanh ghi để chốt (Latch) dữ liệu `dmem_rdata_i` lại ngay tại chu kỳ `WAIT_RSP` khi `dmem_rsp_valid_i` bật lên.
