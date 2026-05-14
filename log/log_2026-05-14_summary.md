# Session Summary — 2026-05-14 (debug session 2)

## 1. Triệu chứng

`do run_soc_io.do` → **PASS=0 / FAIL=24**. Mọi test: `got HEX[5:0] = 7f 7f 7f 7f 7f 7f` (giá trị reset).

Sau khi thêm `[IO]` monitor vào testbench (log mọi `io_req_valid`), transcript chỉ thấy:

```
[IO]  t=...  addr=40002000  we=0  wdata=00000000  cs={swled=0 hex=0 key=1 uart=0 gpio=0}
[IO]  t=...  addr=40002000  we=0  wdata=00000000  cs={swled=0 hex=0 key=1 uart=0 gpio=0}
...
[TB] Tổng số lần ghi HEX peripheral (cs_hex && io_we) = 0
```

→ CPU chỉ access KEY (0x40002000), **không bao giờ tới `lw SW_LED`** ở dòng kế tiếp.

## 2. Trace assembly

```asm
main_loop:
    li   x5,  KEY_BASE       # 0x40002000
    lw   x6,  0(x5)          # đọc KEY → kỳ vọng x6 = 0xF (key_i=4'hF)
    andi x6,  x6,  1         # mask bit[0] → kỳ vọng = 1
    beqz x6,  _init          # nếu = 0 → reset
    
    li   x5,  SW_LED_BASE    # ← KHÔNG BAO GIỜ TỚI ĐÂY
    ...
```

→ Để CPU loop mãi KEY: `beqz x6, _init` luôn taken → `x6` (sau `andi`) luôn = 0 → giá trị `x6` đọc về từ `lw` đang sai (KHÔNG phải 0xF).

## 3. LSU & pipeline đã verify

Từ waveform snapshot user gửi:

| State | addr_q | we_q | dmem_rsp_valid_i | dmem_addr_o |
|-------|--------|------|------------------|-------------|
| IDLE | 0x20000007 | 1 | 0 | 0x20000004 |
| SEND_REQ | — | 1 | 0 | 0x20000004 |
| WAIT_RSP | 0x40002000 | 0 | **1** | 0x40002000 |
| DONE | — | 1 | 0 | 0x20000004 |

→ LSU đi đủ 4 stage `IDLE→SEND_REQ→WAIT_RSP→DONE`. Peripheral KEY trả response (`dmem_rsp_valid_i=1`). **CPU không treo, LSU không stuck.**

→ Vấn đề KHÔNG ở routing IO, KHÔNG ở LSU FSM, KHÔNG ở address decoder.

## 4. Bug đã xác định và sửa (chưa giải quyết)

### Bug: EX-stage forwarding mux sai field khi nguồn là LOAD

**File:** `src/core/riscv_datapath.sv` dòng ~270.

**Code gốc:**
```sv
case(ctrl_fwd_rs1_sel_i)
    2'b01: ex_rs1_fwd_data = mem_wb_in.alu_result;  // BUG: với LOAD thì alu_result = địa chỉ
    2'b10: ex_rs1_fwd_data = rf_wdata;
    default: ex_rs1_fwd_data = id_ex_out.rs1_data;
endcase
```

**Sequence gây bug** với LSU 4-cycle:
- `lw x6, 0(x5)` vào MEM, LSU bắt đầu 4 cycle. Pipeline kẹt `andi` trong EX.
- Forwarding unit thấy `lw` ở MEM với `rd=x6` → match `rs1` của `andi` → chọn `2'b01`.
- `mem_wb_in.alu_result = ex_mem_out.alu_result` = **địa chỉ 0x40002000** (alu_result của LW).
- `andi`: `0x40002000 & 1 = 0` → `x6 = 0` → `beqz` taken → loop _init.

**Fix đã apply:**
```sv
logic [31:0] lsu_aligned_rdata;  // forward declaration

logic [31:0] mem_fwd_val;
assign mem_fwd_val = (ex_mem_out.ctrl.wb_sel == WB_MEM) ? lsu_aligned_rdata
                                                        : ex_mem_out.alu_result;

case(ctrl_fwd_rs1_sel_i)
    2'b01: ex_rs1_fwd_data = mem_fwd_val;
    ...
```

**Kết quả sau fix:** VẪN PASS=0 FAIL=24, vẫn chỉ thấy KEY access trong `[IO]`.

→ Fix lý thuyết đúng nhưng chưa đủ. Còn bug khác / hoặc fix chưa kick in đúng cách.

## 5. Các giả thuyết còn lại

### H1. `lsu_aligned_rdata = 0` ở cycle EX/MEM advance (RACE)

LSU `lsu_rdata_o` chỉ hợp lệ ở state DONE:
```sv
if ((state == DONE) && !misaligned_trap_q && !we_q) ...
else lsu_rdata_o = 32'b0;
```

Khi LSU sang DONE: cùng cycle đó, `lsu_valid_out=1` → `ex_mem_ready=1` → ex_mem latch andi. ALU dùng `lsu_aligned_rdata` (combinational). Về lý thuyết đồng bộ.

**Nhưng:** nếu có 1 chu kỳ delta race (LSU state→IDLE cùng lúc latch), `lsu_aligned_rdata` có thể = 0.

### H2. Latch `dmem_rdata_q` trễ 1 cycle

LSU latch `dmem_rdata_q <= dmem_rdata_i` tại WAIT_RSP→DONE transition. Cycle DONE đầu tiên, `dmem_rdata_q` mới đã có giá trị. `lsu_aligned_rdata` (comb từ `dmem_rdata_q`) cũng đã đúng.

→ Có khả năng cao OK.

### H3. `io_rdata_reg` latch sai cycle

`io_rdata_reg` latch ở cycle SEND_REQ (khi `io_req_valid=1, cs_key=1`). 1 cycle sau (WAIT_RSP) `io_rsp_valid=1`, LSU đọc `dmem_rdata_i = io_rdata_reg`. Timing này 1-cycle delayed phù hợp.

### H4. Branch resolve trong EX nhưng forward sai cho branch_cmp

`branch_cmp` đặt ở EX (dòng 325) và dùng `ex_rs1_fwd_data`. Cùng tín hiệu với ALU → cùng fix. OK.

### H5. Hazard detect không stall đủ khi M-unit + LSU đan xen

Không liên quan ở đây vì chưa tới mode_00 (mul/rem/div chưa execute).

### H6. ID-stage forwarding cũng có cùng bug

`id_rs1_fwd_data` (dòng 197-211 — đang COMMENT OUT, early branch không dùng). Loại.

### H7. **Wb_sel của LW chưa đúng** ← cần verify

Decoder dòng 184/198/212/226/240 set `wb_sel = WB_MEM` cho LB/LH/LW/LBU/LHU. Pkg dòng 108: `WB_MEM = 3'b001`. Hợp lý.

### H8. **Hazard unit chỉ stall 1 cycle, không đủ cho LSU 4-cycle**

Hazard unit detect khi load ở EX. Sau 1 cycle stall, load advance sang MEM, hazard release. Andi vào EX. Pipeline backpressure (ex_mem_ready=0) giữ andi ở EX. ALU continuously compute. Khi LSU xong, latch.

**Nhưng:** trong các cycle waiting, `ex_alu_result` được compute liên tục với rs1=0 (do `lsu_aligned_rdata=0` khi không DONE). Nếu vì lý do gì ex_mem advance SỚM (trước DONE), latch giá trị sai.

Cần kiểm tra `ex_mem_ready` exact timing.

## 6. Phương án debug tiếp — CHỈ DÙNG TRANSCRIPT

Không add wave. Thêm `$display` trong testbench bind vào hierarchy nội bộ của DUT để log đúng các signal nghi vấn, **mỗi cycle relevant**.

### Bước 1 — Log mỗi cycle LSU DONE state

Thêm vào `tb_soc_io.sv` (sau `[IO]` monitor):

```sv
// Snapshot mỗi cycle LSU DONE — chỉ cho LOAD (we_q=0)
always @(posedge clk) begin
    if (!rst && u_soc.u_datapath.u_lsu_core.state == 2'd3 /*DONE*/
              && !u_soc.u_datapath.u_lsu_core.we_q) begin
        $display("  [LSU-DONE] t=%8t ns  addr_q=%08h  dmem_rdata_q=%08h  lsu_rdata_o=%08h  funct3_q=%b",
            $time,
            u_soc.u_datapath.u_lsu_core.addr_q,
            u_soc.u_datapath.u_lsu_core.dmem_rdata_q,
            u_soc.u_datapath.u_lsu_core.lsu_rdata_o,
            u_soc.u_datapath.u_lsu_core.funct3_q);
    end
end
```

**Đọc transcript:**
- `dmem_rdata_q = 0000000F` → KEY peripheral OK
- `lsu_rdata_o = 0000000F` → LSU LOAD alignment OK
- Nếu cả 2 đều đúng → bug nằm SAU LSU, trong forwarding hoặc register write.

### Bước 2 — Log mỗi lần x6 được ghi (rf_we cho x6)

```sv
always @(posedge clk) begin
    if (!rst && u_soc.u_datapath.mem_wb_valid
              && u_soc.u_datapath.mem_wb_out.ctrl.rf_we
              && u_soc.u_datapath.mem_wb_out.rd_addr == 5'd6) begin
        $display("  [WB-x6]    t=%8t ns  rf_wdata=%08h  wb_sel=%b  load_data=%08h  alu_result=%08h",
            $time,
            u_soc.u_datapath.rf_wdata,
            u_soc.u_datapath.mem_wb_out.ctrl.wb_sel,
            u_soc.u_datapath.mem_wb_out.load_data,
            u_soc.u_datapath.mem_wb_out.alu_result);
    end
end
```

**Đọc transcript:**
- Nếu `wb_sel=001` và `load_data=0xF` và `rf_wdata=0xF` → x6 được ghi đúng → bug ở chỗ KHÁC (vd: andi đọc trước khi x6 settle).
- Nếu `rf_wdata=0` hoặc `load_data ≠ 0xF` → bug trong path WB.

### Bước 3 — Log mỗi cycle `andi` ở EX (instr=0x0017f713)

`andi x6, x6, 1` opcode: `0x0017f713` (imm=1, rs1=x6, funct3=111 ANDI, rd=x6, opcode=0010011).

```sv
always @(posedge clk) begin
    if (!rst && u_soc.u_datapath.id_ex_valid
              && u_soc.u_datapath.id_ex_out.rd_addr == 5'd6
              && u_soc.u_datapath.id_ex_out.rs1_addr == 5'd6) begin
        $display("  [ANDI-EX] t=%8t ns  fwd_sel=%b  rs1_fwd=%08h  mem_fwd_val=%08h  alu_result=%08h  ex_mem_ready=%b  lsu_state=%d",
            $time,
            u_soc.u_datapath.ctrl_fwd_rs1_sel_i,
            u_soc.u_datapath.ex_rs1_fwd_data,
            u_soc.u_datapath.mem_fwd_val,
            u_soc.u_datapath.ex_alu_result,
            u_soc.u_datapath.ex_mem_ready,
            u_soc.u_datapath.u_lsu_core.state);
    end
end
```

**Đọc transcript:**
- Quan sát từng cycle `andi` ở EX khi LSU đang chạy.
- Nếu thấy 1 cycle có `lsu_state=3 (DONE)` và `mem_fwd_val=0xF` và `alu_result=1` và `ex_mem_ready=1` → fix đã hoạt động → bug khác.
- Nếu mọi cycle `mem_fwd_val=0` → fix KHÔNG kick in → `wb_sel` ở MEM không phải `WB_MEM`, hoặc `ex_mem_out.ctrl.wb_sel` reset về `WB_ALU` khi bubble.

### Bước 4 — Verify recompile thực sự xảy ra

Thêm `$display` ngay đầu DUT khi `mem_fwd_val` tồn tại:

```sv
// Trong soc_top_io.sv hoặc datapath, thêm 1 dòng marker:
initial $display("[BUILD] mem_fwd_val fix compiled in");
```

Nếu không thấy dòng này trong transcript → file chưa được vlog → cần `vdel -lib work -all; vlib work; do run_soc_io.do`.

## 7. Kế hoạch fix (ưu tiên cao → thấp)

1. **Add 3 `$display` monitors** ở section 6 vào `tb_soc_io.sv`. Chạy. Đọc transcript.
2. Từ output:
   - **Nếu `dmem_rdata_q = 0xF` nhưng `mem_fwd_val = 0`** → `wb_sel` issue. Kiểm tra `ex_mem_out.ctrl.wb_sel` enum khớp `WB_MEM = 3'b001`. Có thể cần so sánh dạng `wb_sel == 3'b001` thay vì enum literal.
   - **Nếu `mem_fwd_val = 0xF` nhưng `alu_result = 0`** → ALU operand thực không phải mem_fwd_val. Kiểm tra `ex_alu_in.rs1_data` mux ở dòng 289 (`op_a_sel == OP_A_PC` có nhầm không).
   - **Nếu `alu_result = 1` nhưng `rf x6` = 0** → ex_mem latch không xảy ra ở cycle đó (ex_mem_ready=0). Cần sửa pipeline backpressure.
   - **Nếu `rf x6 = 1` nhưng `beqz` vẫn taken** → branch_cmp đọc stale x6, không qua forwarding đúng.
3. Sau khi xác định chính xác signal nào sai → fix targeted (1-2 dòng).

## 8. Trạng thái file hiện tại

| File | Trạng thái |
|------|-----------|
| `src/core/riscv_datapath.sv` | Đã thêm `mem_fwd_val` mux (fix forwarding LOAD). KHÔNG đủ. |
| `verify/tb_soc_io.sv` | Đã thêm `[IO]` monitor + `hex_write_cnt`. |
| `sim/run_soc_io.do` | Đã xóa toàn bộ debug waves, về dạng nguyên thủy. |
| `log/log_2026-05-14_summary.md` | File này — tổng hợp. |

## 9. Bước kế tiếp cho session mới

1. Apply 3 `$display` monitors trong section 6 vào `tb_soc_io.sv`.
2. `quit -sim; do run_soc_io.do`.
3. Paste transcript `[LSU-DONE]`, `[WB-x6]`, `[ANDI-EX]` đầu tiên (10-20 dòng).
4. Theo flowchart ở section 7.2 → identify root cause → fix.
