# RISC-V Core Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `riscv_core.sv` là Top-module của toàn bộ lõi xử lý RISC-V RV32IM. Nó đóng gói Datapath, Control Unit và CSR thành một thực thể duy nhất, đồng thời "chuyển hóa" các giao tiếp tín hiệu nội bộ thành chuẩn giao tiếp chung (như tín hiệu Valid/Ready cho Instruction và Data) để tương tác với thế giới bên ngoài (Bộ nhớ, AXI Wrapper, SoC Top).

**Tính năng chính:**
- Che giấu hoàn toàn độ phức tạp của Pipeline, Hazard, Forwarding vào bên trong.
- Bộc lộ cổng gỡ lỗi (Debug ports) để Testbench có thể soi vào trạng thái thanh ghi nội bộ mà không cần trỏ đường dẫn phân cấp (hierarchical paths), giúp tránh lỗi `X` khi chạy mô phỏng có tối ưu hóa (vd: Questa `vopt`).
- Hỗ trợ giao tiếp nhớ theo chuẩn Request/Response (Valid/Ready kênh đôi).

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `clk_i`, `rst_i` | Input | 1 | Clock / Reset hệ thống |
| **Giao tiếp Instruction Memory (IMEM)** ||| |
| `imem_addr_o`, `imem_valid_o` | Output| 32/1 | Địa chỉ lệnh và cờ Request |
| `imem_ready_i` | Input | 1 | IMEM sẵn sàng nhận Request |
| `imem_instr_i`, `imem_valid_i`| Input | 32/1 | Data lệnh và cờ Response |
| `imem_ready_o` | Output| 1 | Core báo đã lấy lệnh thành công |
| **Giao tiếp Data Memory (DMEM)** ||| |
| `dmem_addr_o`, `dmem_wdata_o` | Output| 32 | Địa chỉ và Dữ liệu ghi |
| `dmem_be_o`, `dmem_we_o` | Output| 4/1 | Kênh byte enable và write enable |
| `dmem_valid_o`, `dmem_ready_i`| Out/In| 1 | Handshake kênh Request |
| `dmem_rdata_i`, `dmem_valid_i`| Input | 32/1| Dữ liệu đọc trả về và cờ hợp lệ |
| `dmem_ready_o` | Output| 1 | Handshake kênh Response (Core đã nhận) |
| **Giao tiếp Debug** ||| |
| `dbg_wb_we_o`, `dbg_wb_rd_o` | Output| 1/5 | Dùng để dò xem lệnh nào vừa ghi Write-Back |

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Chỉ chứa các lệnh Instantiate của `riscv_datapath`, `riscv_control`, và `csr`.
- Dùng các dây `logic` nội bộ để nối tín hiệu Datapath <-> Control và Datapath <-> CSR.
- Chặn lỗi ổ cứng (hard-coded): Ngõ `dmem_err_i` của Datapath đang bị cắm xuống `1'b0` (không bắt lỗi Bus fault từ AXI/Memory bên ngoài), có thể mở rộng sau.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** 0
- **Warning:** 0
- **Đề xuất giải quyết:** 0
