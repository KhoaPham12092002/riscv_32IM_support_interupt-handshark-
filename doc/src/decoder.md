# Decoder Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** Khối `decoder.sv` chịu trách nhiệm giải mã tập lệnh RV32IM. Nó nhận vào mã máy 32-bit (Instruction) và xuất ra các tín hiệu điều khiển (Control signals) tương ứng cho các khối Datapath, ALU, LSU, Branch Unit, và CSR. Đồng thời, nó cũng tạo ra giá trị Immediate (Immediate Generation).

**Tính năng chính:**
- Giải mã tất cả các lệnh thuộc tập lệnh chuẩn RV32I và phần mở rộng M (Nhân/Chia).
- Hỗ trợ giải mã các lệnh liên quan đến CSR và Trap (MRET, ECALL, EBREAK).
- Trích xuất địa chỉ thanh ghi (rd, rs1, rs2) từ lệnh.
- Sinh ra giá trị Immediate 32-bit đã được mở rộng dấu (Sign-extended) tùy theo định dạng lệnh (I-Type, S-Type, B-Type, U-Type, J-Type).
- Chặn lệnh không hợp lệ bằng tín hiệu `illegal_instr`.

**Tính năng không hỗ trợ (Non-features):**
- Không có bất kỳ bộ lưu trữ tuần tự (Flip-flops) nào bên trong. Nó là khối logic tổ hợp (Combinational Logic).
- Không hỗ trợ giải mã lệnh Nén (C-extension) hay Float (F/D-extension).

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

### Bảng Port List:
| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `instr_i` | Input | 32 | Mã lệnh 32-bit từ khối Fetch/IF |
| `ctrl_o` | Output | Struct | Gói tín hiệu điều khiển (`dec_out_t`) |
| `imm_o` | Output | 32 | Giá trị Immediate đã mở rộng |
| `rd_addr_o` | Output | 5 | Địa chỉ thanh ghi đích |
| `rs1_addr_o`| Output | 5 | Địa chỉ thanh ghi nguồn 1 |
| `rs2_addr_o`| Output | 5 | Địa chỉ thanh ghi nguồn 2 |
| `valid_i` | Input | 1 | Lệnh nhận vào là hợp lệ |
| `ready_o` | Output | 1 | Sẵn sàng nhận lệnh mới từ IF |
| `valid_o` | Output | 1 | Gói tín hiệu giải mã đã sẵn sàng |
| `ready_i` | Input | 1 | Tầng EX đã sẵn sàng nhận lệnh |

**Giao thức (Protocols):**
- Sử dụng Handshake Valid/Ready. Khối decoder đóng vai trò như một bộ "kết nối xuyên thấu" (pass-through) với handshake: `valid_o = valid_i` và `ready_o = ready_i`.

**Clock & Reset:**
- Không sử dụng Clock và Reset do là khối mạch tổ hợp.

---

## 3. Sơ đồ khối & Kiến trúc bên trong (Block Diagram & Micro-architecture)

**Datapath & Control path:**
- **Instruction Slicing:** Cắt các trường bit cố định (rd, rs1, rs2) đưa thẳng ra ngoài.
- **Main Control Decoder:** Sử dụng khối `always_comb` với cấu trúc `casez(instr_i)`. Đầu tiên gán tất cả tín hiệu control về giá trị mặc định (Nop-like) để tránh hiện tượng mạch chốt (Latch). Sau đó, tùy thuộc vào `opcode/funct3/funct7`, các cờ điều khiển cụ thể như `alu_req`, `lsu_req`, `m_req`, `br_req`, `csr_req` sẽ được set lên.
- **Immediate Generation:** Dùng một `always_comb` case phụ thuộc vào trường `imm_type` (được sinh ra từ Main Control) để chọn và mở rộng dấu chính xác.

---

## 4. Máy trạng thái (FSM - Finite State Machine)
- Không có FSM.

---

## 5. Giản đồ thời gian (Timing Diagrams & Waveforms)
- **Normal Flow:** Ngay khi `instr_i` và `valid_i` có giá trị, các tín hiệu control và `imm_o` sẽ ngay lập tức được xuất ra. Trễ lan truyền chỉ phụ thuộc vào logic gates.
- Nếu `valid_i` = 0, toàn bộ ngõ ra control bị trả về Default Assignments (không write, không thực hiện gì).

---

## 6. Bản đồ Thanh ghi (Register Map)
- Không có thanh ghi.

---

## 7. Tham số hóa (Parameters & Configurations)
- Dùng thư viện package `riscv_instr` và `riscv_32im_pkg` để import các cấu trúc struct và hằng số opcode.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
