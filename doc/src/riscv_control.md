# RISC-V Control Unit Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `riscv_control.sv` là khối "Não bộ" (Control Unit) đóng vai trò điều phối tập trung mọi hoạt động xử lý rủi ro (Hazard), chuyển hướng dữ liệu (Forwarding) và xử lý ngoại lệ/ngắt (Trap) của toàn bộ Core.

**Tính năng chính:**
- Tập hợp các module con như Hazard Unit và Forwarding Unit.
- Thu thập lỗi/ngoại lệ từ toàn bộ đường ống (Ecall, Illegal instruction từ ID; Load access fault từ MEM).
- Sinh mã lỗi (Trap cause) theo chuẩn RISC-V M-mode và gửi cho khối CSR.
- Sinh tín hiệu chọn PC (Branch, Trap, MRET, Sequential).

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| **Báo cáo từ Datapath** ||| |
| `hz_...` | Input | - | Hàng loạt tín hiệu địa chỉ `rs1`, `rs2`, `rd`, `we` từ các tầng. |
| `id_is_ecall_i`, `id_illegal_instr_i` | Input | 1 | Các cờ báo lỗi từ tầng ID. |
| `lsu_err_i` | Input | 1 | Cờ báo lỗi truy xuất Data Memory từ tầng MEM. |
| `branch_taken_i`| Input | 1 | Báo lệnh nhảy ở EX đã kích hoạt. |
| **Điều khiển xuất ra** ||| |
| `ctrl_force_stall_id_o`, `flush_...` | Output| 1 | Lệnh ép Stall hoặc Flush pipeline. |
| `ctrl_fwd_...` | Output| 2 | Lệnh chọn kênh Forwarding. |
| `ctrl_pc_sel_o` | Output| 2 | 00: PC+4, 01: Branch, 10: Trap, 11: MRET |
| **Giao tiếp CSR** ||| |
| `ctrl_trap_valid_o` | Output| 1 | Báo CSR lưu trạng thái đứt gãy (Trap). |
| `ctrl_trap_cause_o` | Output| 4 | Mã nguyên nhân Trap (VD: 11, 2, 5). |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Là một khối thuần tổ hợp (Combinational Logic Wrapper).
- Logic sinh Trap: Gộp bằng cổng OR (`is_trap = id_is_ecall_i | id_illegal_instr_i | lsu_err_i`).
- Mạch sinh tín hiệu Flush cho IF/ID và ID/EX: Gộp giữa nhánh Jump (Branch/MRET) và Trap (`jump_trap_comb`).

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
