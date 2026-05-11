# SoC Without Memory Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `soc_without_mem.sv` đóng vai trò là lõi hệ thống đóng gói (System-on-Chip Wrapper). Nó thực hiện việc Instantiate các cấu phần xử lý trung tâm gồm: `riscv_datapath`, `riscv_control` và `csr`. 
(Lưu ý: Module này có tính năng giống hệt `riscv_core.sv` nhưng bộc lộ nhiều dây tín hiệu rõ ràng hơn thay vì bọc giấu. Thiết kế này thường dùng để dễ dàng nối với AXI Interconnect khi muốn cắm Memory bên ngoài).

**Tính năng chính:**
- Ghép nối các tín hiệu nội bộ rời rạc (`hz_...`, `ctrl_...`) giữa Datapath, Control và CSR.
- Trích xuất toàn bộ giao tiếp IMEM và DMEM ra ngoài làm Interface chính.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk_i`, `rst_i` | Input | 1 | Clock hệ thống |
| `irq_sw_i`, `irq_timer_i`, `irq_ext_i`| Input| 1 | Các chân ngắt (Interrupts) từ ngoài |
| `if_req_...`, `if_rsp_...` | In/Out| Mix | Bus lấy lệnh IMEM |
| `dmem_req_...`, `dmem_rsp_...` | In/Out| Mix | Bus dữ liệu DMEM |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Hoàn toàn là đấu nối Structural tĩnh (Wire routing). Không chứa logic cổng hay thanh ghi nào.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
