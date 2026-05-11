# PC Generator Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `pc_gen.sv` là khối tạo địa chỉ bộ đếm chương trình (Program Counter). Nhiệm vụ của nó là cung cấp địa chỉ PC (thường là để cấp cho Instruction Memory/Fetch) ở mỗi chu kỳ xung nhịp để CPU biết lệnh tiếp theo nằm ở đâu.

**Tính năng chính:**
- Hỗ trợ thực thi tuần tự (Sequential Fetch): Tăng PC lên 4 byte (RV32I).
- Hỗ trợ thực thi rẽ nhánh (Branch/Jump): Nhận tín hiệu và địa chỉ đích từ khối Execute.
- Hỗ trợ xử lý ngoại lệ/ngắt (Trap/Interrupt): Nhảy đến các địa chỉ Vector ngắt (mtvec) khi có lệnh từ bộ xử lý Trap/CSR.

**Tính năng không hỗ trợ (Non-features):**
- Khối này không tự cộng PC khi rẽ nhánh, địa chỉ đích (Target Address) phải được ALU hoặc Branch adder tính toán và đưa vào dưới dạng ngõ vào.
- Không hỗ trợ tập lệnh nén 16-bit (C-Extension), vì PC chỉ nhảy bước 4.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk_i` / `rst_i` | Input | 1 | Clock và Reset đồng bộ |
| `ready_i` | Input | 1 | (Từ Pipeline) Báo hiệu Pipeline/IMEM sẵn sàng nhận PC mới |
| `valid_o` | Output| 1 | Báo hiệu ngõ ra PC là hợp lệ (Luôn = 1) |
| `branch_taken_i` | Input | 1 | Cờ báo Branch/Jump đã nhảy (Từ EX) |
| `branch_target_addr_i`| Input| 32| Địa chỉ đích của Branch/Jump |
| `trap_taken_i` | Input | 1 | Cờ báo Trap/Interrupt (Từ CSR/Hazard) |
| `trap_target_addr_i` | Input | 32| Địa chỉ Vector xử lý ngắt |
| `pc_o` | Output| 32 | Giá trị PC xuất ra ngoài |

**Giao thức:** Handshake Valid/Ready đơn giản, với đặc thù Valid luôn kéo mức Cao.

---

## 3. Sơ đồ khối & Kiến trúc bên trong (Micro-architecture)

**Priority Encoder (Xác định PC tiếp theo):**
- **Ưu tiên 1 (Cao nhất): Trap.** Nếu `trap_taken_i = 1`, Next PC = Trap Address.
- **Ưu tiên 2: Branch.** Nếu `branch_taken_i = 1`, Next PC = Branch Address.
- **Ưu tiên 3 (Thấp nhất): Tuần tự.** Next PC = PC hiện tại + 4.

**Thanh ghi PC:**
- Cập nhật đồng bộ theo sườn lên của clock.
- Reset đồng bộ trả về `0x0000_0000`.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
