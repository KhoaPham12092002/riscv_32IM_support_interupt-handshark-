# ALU Sub-Modules Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `sub_module.sv` là một thư viện chứa các vi mạch (Sub-modules) cấu tạo nên ALU. File này hiện thực hóa các mạch logic số cơ bản ở mức cổng (Gate-level/RTL) để tránh sử dụng các toán tử mức cao, giúp dễ điều khiển kiến trúc khi tổng hợp (Synthesis) lên phần cứng.

**Tính năng chính:**
- `i_adder`: Mạch cộng 32-bit Carry Lookahead Adder (CLA) giúp giảm thiểu trễ lan truyền (Propagation Delay) so với Ripple Carry Adder truyền thống.
- `alu_shift_inst`: Mạch dịch bit thùng (Barrel Shifter) 32-bit, thực hiện dịch mọi vị trí chỉ với 1 chu kỳ tổ hợp bằng các tầng Multiplexer ghép nối.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| **Module `i_adder`** ||| |
| `a`, `b` | Input | 32 | Toán hạng 1 và 2 |
| `carry_in`, `add_sub` | Input | 1 | Bit nhớ và bit điều khiển chế độ (0=Cộng, 1=Trừ) |
| `sum_dif` | Output| 32 | Tổng / Hiệu số |
| `C`, `V` | Output| 1 | Cờ Nhớ ra (Carry) và cờ Tràn (Overflow) |
| **Module `alu_shift_inst`** ||| |
| `a_i` | Input | 32 | Dữ liệu gốc cần dịch |
| `b_i` | Input | 5 | Số lượng bit cần dịch (0-31) |
| `shift_type_i` | Input | 2 | Loại dịch (00=SLL, 01=SRL, 10=SRA) |
| `result_o` | Output| 32 | Kết quả đã dịch |

---

## 3. Kiến trúc bên trong (Micro-architecture)

**1. Khối Cộng CLA 32-bit (`i_adder`):**
- Sử dụng mô hình CLA nhiều cấp. 
- Mức 1: Tạo Generate (`g`) và Propagate (`p`) từ 32 cổng `full_adder_1_bit`.
- Mức 2: Dùng 8 khối `carry_block_4bits` nối với nhau. Các khối này tính trước bit Carry cho các cổng Full Adder bằng biểu thức Boolean để dập tắt đường trễ (Delay Path).
- Logic Overflow (`V`): Được xác định chính xác theo công thức đại số Boolean chuẩn `C_blk[7] ^ cin[31]`.

**2. Khối Dịch Barrel Shifter (`alu_shift_inst`):**
- Được chia làm **5 Tầng Mux (Stages)**, mỗi tầng chịu trách nhiệm dịch một cấp số nhân của 2: `1 -> 2 -> 4 -> 8 -> 16`.
- Bit tương ứng trong lượng dịch `b_i[x]` sẽ là chân Select (Điều khiển) của Mux ở tầng đó.
- Phép SRA (Shift Right Arithmetic) tái tạo lại chính xác bit MSB (Bit dấu) thay vì nhét bit 0 như SRL.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
