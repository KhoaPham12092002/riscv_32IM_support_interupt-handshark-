# RISC-V Datapath Specification

## 1. Tổng quan & Chức năng (Overview & Features)
**Mục đích:** `riscv_datapath.sv` là trung tâm (Heart) của bộ xử lý, kết nối 5 tầng Pipeline (IF, ID, EX, MEM, WB) bằng các thanh ghi đường ống (`pipeline_reg`). Nó định tuyến dữ liệu giữa các thành phần ALU, LSU, M-Unit, Decoder, và Register File.

**Tính năng chính:**
- Kết nối logic toàn bộ 5 stage.
- Xử lý cơ chế Back-pressure (Handshake stall) do lệnh chậm (Nhân/Chia, Load/Store) gây ra.
- Thực hiện Forwarding data qua các Mux ở tầng EX.
- Giải mã và trích xuất thông tin lỗi/ngoại lệ để gửi lên Control Unit.

---

## 2. Danh sách Giao tiếp & Tín hiệu (Port List & Interfaces)

| Tên tín hiệu | Chiều | Width | Mô tả chức năng |
| :--- | :--- | :--- | :--- |
| `if_req_...`, `if_rsp_...` | In/Out| Mix | Giao tiếp lấy lệnh (Instruction Fetch) |
| `dmem_req_...`, `dmem_rsp_...`| In/Out| Mix | Giao tiếp truy xuất bộ nhớ (Data Memory) |
| `hz_...` | Output| Mix | Gửi thông tin (rs, rd) lên Control để xét Hazard |
| `ctrl_...` | Input | Mix | Nhận lệnh Flush, Stall, Forward, PC_Sel từ Control |
| `csr_req_...` | Output| Mix | Gửi request đọc/ghi thanh ghi hệ thống cho CSR |

**Giao thức:**
- Pipeline dùng giao thức Valid/Ready ở mọi điểm nối (Inter-stage Handshake).

---

## 3. Kiến trúc bên trong (Micro-architecture)
- Đường ống 5 tầng truyền thống:
  - **Tầng IF:** Có bộ PC_Gen, gửi tín hiệu ra ngoài tới IMEM.
  - **Tầng ID:** Lệnh đi qua `decoder`. Data lấy từ `register`.
  - **Tầng EX:** Gồm Mux chọn Forwarding, `alu`, `branch_cmp`, và `riscv_m_unit`.
  - **Tầng MEM:** Đi qua khối `lsu`.
  - **Tầng WB:** Mux 5-to-1 (`WB_ALU`, `WB_MEM`, `WB_PC_PLUS4`...) ghi kết quả vào Register File.
- Sử dụng mô-đun `pipeline_reg` để dập xung và cô lập từng vùng.

---

## REVIEW BUG TIỀM ẨN CỰC KỲ QUAN TRỌNG

- **Issue:** Thanh ghi đường ống `u_reg_ex_mem` gán `ready_i = (is_mem_access ? lsu_valid_out : mem_wb_ready)`. Nếu là lệnh Load/Store, nó phớt lờ `mem_wb_ready` của tầng kế tiếp. Nếu tầng sau bị kẹt (Stall), kết quả sẽ bị xóa đè và mất (Data Loss).
- **Warning:** Gây mất dữ liệu nghiêm trọng làm CPU chạy sai logic lệnh.
- **Đề xuất giải quyết:** Sửa logic gán ready_i thành: `(is_mem_access ? (lsu_valid_out && mem_wb_ready) : mem_wb_ready)`
