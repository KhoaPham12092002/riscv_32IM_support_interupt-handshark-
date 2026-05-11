# Tổng hợp Báo cáo Lỗi & Cảnh báo (Synthetic Report)

## File: `uart.md`
- **Issue:** Khối RX không có tín hiệu `rx_ready_i` để nhận back-pressure từ Core. Cờ `rx_valid` chỉ nháy đúng 1 nhịp clock rồi tắt, nếu hệ thống không đọc kịp nhịp đó thì dữ liệu bị rớt (Data drop).
- **Warning:** Mất mát gói tin khi CPU bận hoặc pipeline bị stall.
- **Đề xuất giải quyết:** Thêm tín hiệu `rx_ready_i` vào khối UART 32-bit. Giữ `rx_valid = 1` cho tới khi `rx_ready_i = 1` mới được thả cờ xuống.

## File: `csr.md`
- **Warning:** Tín hiệu `csr_rsp_valid_o` hiện tại được nối tổ hợp thẳng từ tín hiệu Handshake đầu vào. Khi ráp với AXI4-Lite (có độ trễ kênh Response), cách đấu nối này có thể làm AXI Controller bị rối loạn.
- **Đề xuất giải quyết:** Cần tách bạch kênh Request và kênh Response bằng thanh ghi hoặc FSM khi thiết kế module AXI Wrapper cho CSR.

## File: `lsu.md`
- **Issue:** LSU đọc trực tiếp `dmem_rdata_i` tại state `DONE` trong khi data chỉ được đảm bảo hợp lệ ở chu kỳ `WAIT_RSP` (vì `dmem_rsp_valid_i` có thể chỉ nảy 1 chu kỳ).
- **Warning:** Có thể dẫn đến việc đọc dữ liệu rác nếu Data Memory không giữ tín hiệu sau khi Handshake kết thúc.
- **Đề xuất giải quyết:** Thêm một thanh ghi để chốt (Latch) dữ liệu `dmem_rdata_i` lại ngay tại chu kỳ `WAIT_RSP` khi `dmem_rsp_valid_i` bật lên.

## File: `riscv_datapath.md`
- **Issue:** Thanh ghi đường ống `u_reg_ex_mem` gán `ready_i = (is_mem_access ? lsu_valid_out : mem_wb_ready)`. Nếu là lệnh Load/Store, nó phớt lờ `mem_wb_ready` của tầng kế tiếp. Nếu tầng sau bị kẹt (Stall), kết quả sẽ bị xóa đè và mất (Data Loss).
- **Warning:** Gây mất dữ liệu nghiêm trọng làm CPU chạy sai logic lệnh.
- **Đề xuất giải quyết:** Sửa logic gán ready_i thành: `(is_mem_access ? (lsu_valid_out && mem_wb_ready) : mem_wb_ready)`

