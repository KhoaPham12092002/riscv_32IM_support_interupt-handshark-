# ALU (Arithmetic Logic Unit) Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `alu.sv` là trái tim toán học của bộ xử lý RISC-V. Khối này thực hiện các phép tính số học (Cộng, Trừ), logic (AND, OR, XOR), dịch bit (SLL, SRL, SRA) và các phép so sánh (SLT, SLTU) dựa trên lệnh của người dùng.

**Tính năng chính:**
- Hỗ trợ đầy đủ các phép toán của tập lệnh RV32I cơ bản (Cộng/Trừ, Logic, Dịch bit, So sánh).
- Được thiết kế cấu trúc (Structural Design) bằng cách gọi các module con chuyên dụng (`i_adder` và `alu_shift_inst`) thay vì dùng phép toán `+`, `-`, `<<` của Verilog, giúp dễ dàng kiểm soát phần cứng tổng hợp (Synthesis).

**Tính năng không hỗ trợ:**
- Khối này không thực hiện phép Nhân/Chia (nhường cho `riscv_m_unit`).
- Là mạch tổ hợp 100%, không lưu trạng thái.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `alu_in` | Input | Struct| Gói tín hiệu chứa `rs1_data`, `rs2_data` và `op` (ALU_ADD, ALU_SUB...) |
| `Zero` | Output| 1 | Cờ báo kết quả bằng 0 (Thường dùng cho Branch nhưng ở đây có `branch_cmp` riêng nên ít dùng) |
| `alu_o` | Output| 32 | Kết quả tính toán của ALU |

**Giao thức & Clock/Reset:** Mạch tổ hợp thuần túy (Combinational). Dữ liệu ngõ ra lập tức thay đổi theo ngõ vào. Không có Clock, Reset hay Handshake.

---

## 3. Sơ đồ khối & Kiến trúc bên trong (Micro-architecture)
- **Datapath Tích hợp:**
  - Tín hiệu `alu_in.rs1_data` và `alu_in.rs2_data` được đưa song song vào cả bộ Adder và bộ Shifter.
  - `is_sub`: Cờ xác định phép trừ (dùng cho lệnh SUB và cả lệnh so sánh SLT/SLTU). Nó điều khiển cờ `carry_in` của bộ cộng để thực hiện phép bù 2 (Trừ = Cộng đảo bit + 1).
  - Bộ Mux khổng lồ (`always_comb case`) ở cuối sẽ chọn 1 trong các kết quả từ Adder, Shifter hoặc cổng Logic để xuất ra ngõ `alu_o`.
- **So sánh có dấu/không dấu:**
  - `SLT` (Có dấu): Sử dụng công thức `adder_o[31] ^ v_flag` (Kiểm tra bit dấu của kết quả trừ XOR với cờ Overflow). Đây là thuật toán chuẩn xác 100% trong kiến trúc máy tính.
  - `SLTU` (Không dấu): Dựa vào `~cout` (Ngược lại của Carry out sau phép trừ).

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
