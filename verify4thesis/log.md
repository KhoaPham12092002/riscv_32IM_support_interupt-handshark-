# verify4thesis — Log tiến độ

> File này tự động cập nhật sau MỖI action (modify/create/delete file, chạy lệnh, quyết định).
> Mở file này đầu session để pickup ngay không cần đọc lại lịch sử.

---

## 1. Mục tiêu tổng

Viết lại 6 testbench UVM cho thesis RV32IM (Section 5.2.4 → 5.5):
1. `tb_lsu_thesis` — Section 5.2.4 → Hình 5.4
2. `tb_fwd_thesis` — Section 5.3.1 → Hình 5.5
3. `tb_hazadetec_thesis` — Section 5.3.2 → Hình 5.6
4. `tb_control_thesis` — Section 5.3.3 → Hình 5.7
5. `tb_csr_thesis` — Section 5.3.4 → Hình 5.8
6. `tb_core_riscv_thesis` — Section 5.4 → Bảng 1

**Tiêu chí cho mỗi tb:**
- Coverage 100% functional (mỗi tb in `[COV] <module>: n/total = pct%`)
- Scoreboard độc lập + golden model SV (2 component khác nhau, scoreboard so sánh kết quả golden vs DUT)
- SVA bắt lỗi cục bộ (handshake, no-X, FSM legality)
- Dice random `$urandom % 100` + bảng phần trăm (thay cho `randomize()` bị khoá license)
- Stress hardcore: 10 seed × 100 instr/run (đúng Bảng 1 thesis)
- Log format chuẩn grep được (banner / TEST block / SUMMARY)
- Wave .do có 5 group + marker `tb_test_id`/`tb_check_pass` + `wave zoom range` cho Killer test
- 1-2 ảnh PNG killer test mỗi module → tb/<module>/killer_*.png

---

## 2. Quyết định kiến trúc đã chốt

| # | Quyết định | Ngày | Lý do |
|---|---|---|---|
| 1 | Tạo tb mới song song (`*_thesis.sv`), giữ tb cũ làm regression | 2026-05-07 | Không phá pipeline cũ |
| 2 | Foundation chung trong `logs/common/` (pkg + checker + sva + dice) | 2026-05-07 | DRY cho 6 tb |
| 3 | Dice = `$urandom % 100` + bảng pct (không dùng `randomize()`) | 2026-05-07 | License khoá |
| 4 | Stress 10 seed × 100 instr/run | 2026-05-07 | Match Bảng 1 thesis |
| 5 | Thứ tự build: foundation → lsu → fwd → hazadetec → control → csr → core | 2026-05-07 | User duyệt từng tb |

---

## 3. Cấu trúc file

```
verify4thesis/
├── log.md                              ← FILE NÀY
├── logs/                               ← DIR 1: tb UVM + log terminal
│   ├── common/
│   │   ├── tb_thesis_pkg.sv            [x] Macro log + dice (gộp dice vào đây)
│   │   ├── tb_thesis_checker.sv        [x] Scoreboard base (TLM 2-fifo, độc lập golden)
│   │   └── tb_thesis_sva.svh           [x] SVA library (NO_X/HANDSHAKE/ONEHOT/IMPL/STABLE/RST)
│   ├── tb_lsu_thesis.sv                [x] done — 2 minor issues
│   ├── tb_fwd_thesis.sv                [x] done — 2 bugs to fix
│   ├── tb_hazadetec_thesis.sv          [x] done
│   ├── tb_control_thesis.sv            [ ]
│   ├── tb_csr_thesis.sv                [ ]
│   ├── tb_core_riscv_thesis.sv         [x] done — 1 bug + 2 design issues
│   ├── scripts/
│   │   ├── run_lsu_thesis.do           [x]
│   │   ├── run_fwd_thesis.do           [x]
│   │   ├── run_core_thesis.do          [x]
│   │   ├── run_hazadetec_thesis.do     [x]
│   │   ├── run_*_thesis.do (×2 còn lại)[ ]
│   │   ├── run_regression.sh           [ ] Multi-seed
│   │   ├── merge_coverage.do           [ ]
│   │   ├── cov_report.do               [ ]
│   │   └── grep_results.sh             [ ]
│   └── output/                         ← log + .ucdb sau khi chạy
└── tb/                                 ← DIR 2: wave + ảnh killer
    ├── lsu/        wave_lsu_thesis.do [x]   + 2 PNG [ ]
    ├── fwd/        wave_fwd_thesis.do [x]   + 2 PNG [ ]
    ├── hazadetec/  wave_hazadetec_thesis.do [x]  + 2 PNG [ ]
    ├── control/    wave_control_thesis.do    [ ]
    ├── csr/        wave_csr_thesis.do        [ ]
    └── core/       wave_core_thesis.do [x]  + 2 PNG [ ]
```

---

## 4. Tiến độ

### 4.1. Done
- [x] 2026-05-07 | Tạo cấu trúc thư mục `verify4thesis/` (logs/, tb/, common/, scripts/, output/, 6 module subdir)
- [x] 2026-05-07 | Tạo log.md skeleton
- [x] 2026-05-07 | `tb_thesis_pkg.sv` — package `tb_thesis_pkg` + 9 macro (HEADER/TEST_BEGIN/STIM/EXPECT/CHECK/MARKER/COV/SUMMARY + INFO/WARN/ERR) + class `dice_pct` (replace `randomize()`) + counter pass/fail
- [x] 2026-05-07 | `tb_thesis_checker.sv` — package `tb_thesis_checker_pkg` + class `thesis_txn` (uvm_sequence_item) + class `thesis_scoreboard_base #(T)` với 2 TLM fifo (DUT/golden độc lập)
- [x] 2026-05-07 | `tb_thesis_sva.svh` — 8 macro SVA: NO_X / HANDSHAKE / ONEHOT / ONEHOT0 / IMPL_NEXT / IMPL_SAME / STABLE_UNTIL / RESET_VAL
- [x] 2026-05-07 | User duyệt foundation, OK chạy tiếp
- [x] 2026-05-07 | `tb_lsu_thesis.sv` — package `lsu_thesis_pkg` với 11 directed test (5 load + 3 store + 3 misalign), driver/monitor có mailbox `inflight` để truyền id+label, golden độc lập (uvm_subscriber), scoreboard 2-fifo, covergroup 4 coverpoint + 1 cross, SVA bind 5 assertion, wave hook drive `tb_test_id`/`tb_check_pass` từ package counter
- [x] 2026-05-07 | `wave_lsu_thesis.do` — 5 group (Clock_Reset / Inputs / DUT_internal / Outputs_Core+DMEM / Checker)
- [x] 2026-05-07 | `run_lsu_thesis.do` — vlog package + UVM + DUT + tb, vsim với coverage `+cover=bcefsx`, save `cov_lsu.ucdb` cho regression merge

- [x] 2026-05-07 | Compile clean + run thành công: **11/11 PASS, COV 100% (20/20 bins), 0 UVM_ERROR**
- [x] 2026-05-07 | `tb_fwd_thesis.sv` — 7 directed + 93 random, golden độc lập, manual_cov 9 bins, SVA NO_X + ONEHOT0
- [x] 2026-05-07 | `wave_fwd_thesis.do` + `run_fwd_thesis.do`
- [x] 2026-05-07 | `tb_core_riscv_thesis.sv` — stress 5 init + 100 hazard instr, golden prediction → scoreboard, obs_* counter driven by always@negedge, coverage 11 bins, SVA on stall/flush/fwd, hard timeout 2ms
- [x] 2026-05-07 | `wave_core_thesis.do` + `run_core_thesis.do`
- [x] 2026-05-07 | Code review 3 file (lsu + fwd + core) — **xem Section 5 bug #6–#8**

### 4.2. In progress
- [x] 2026-05-07 | Sửa Bug 6+7 trong tb_fwd_thesis.sv (thêm 2 directed we=0 cases, xóa duplicate coverage trong fwd_scoreboard)
- [x] 2026-05-07 | Sửa Bug 8+9 trong tb_core_riscv_thesis.sv (range check ok_stall/ok_store, fix pred_alu_raw rs2)
- [x] 2026-05-07 | `tb_hazadetec_thesis.sv` — 10 directed + 90 random, golden độc lập, 9 bins coverage, 3 SVA NO_X
- [x] 2026-05-07 | `wave_hazadetec_thesis.do` + `run_hazadetec_thesis.do`
- [x] 2026-05-08 | Xác định Bug #10: thiếu monitor block trong tb_top → obs_* counters luôn=0 → 3/3 FAIL
- [x] 2026-05-08 | Xác định Bug #11: `core_coverage.final_sample()` rỗng → 0/11 coverage bins
- [x] 2026-05-08 | Xác định Bug #12: IMEM DEADLOCK sau khi thêm monitor block (xem Bug table)

### 4.3. TODO (theo thứ tự)
1. [ ] **[URGENT]** Fix Bug #12: sửa `handle_imem` (tb_core_riscv_thesis.sv line 107) — xem Bug table
2. [ ] Fix Bug #10: thêm monitor `always @(negedge clk)` trong `tb_top` module
3. [ ] Fix Bug #11: điền `core_coverage.final_sample()` gọi `mc.hit_bin()`
4. [ ] Chạy sim core → kỳ vọng 3/3 PASS, COV 11/11 bins
5. [ ] Chạy sim fwd + hazadetec để confirm pass
6. [ ] tb_control_thesis.sv + wave + run script
7. [ ] tb_csr_thesis.sv + wave + run script
8. [ ] `run_regression.sh` (multi-seed) + `merge_coverage.do` + `cov_report.do` + `grep_results.sh`
9. [ ] Chụp 12 ảnh PNG killer test → tb/&lt;module&gt;/killer_*.png

---

## 5. Lỗi & fix

| # | Triệu chứng | Nguyên nhân | Fix | File |
|---|---|---|---|---|
| 1 | `vlog-13069 near "(": syntax error` ở `\`THESIS_SUMMARY()` | Macro với `begin/end` + `\`uvm_fatal` không an toàn parse trong function | Đổi tất cả macro log thành function trong `tb_thesis_pkg`, gọi `tb_thesis_pkg::header()` etc. Chỉ giữ `THESIS_WAVE_HOOK` là macro vì cần ở module scope | tb_thesis_pkg.sv, tb_lsu_thesis.sv |
| 2 | `Concurrent assertions not allowed in report_phase / tasks` | SVA macro label `a_thesis_no_x_``SIG` expand thành `a_..._vif.lsu_rdata_o` — invalid identifier có dấu `.` | Thêm tham số `LBL` riêng cho mỗi SVA macro. User phải truyền identifier hợp lệ | tb_thesis_sva.svh, tb_lsu_thesis.sv |
| 3 | `Failure to checkout svverification license — required for covergroup` | License giống `randomize()` cũng chặn `covergroup` | Tạo class `manual_cov` trong `tb_thesis_pkg`: associative array `hits[string]`, `add_bin()`/`hit_bin()`/`report()`. Coverage tính tay | tb_thesis_pkg.sv, tb_lsu_thesis.sv |
| 4 | Coverage 18/20 (90%) — `dly_med`, `dly_slow` không hit | (a) Monitor không copy `dmem_delay` từ inflight meta; (b) `$urandom_range(1,5)` quá hay rơi vào 1 | (a) Thêm `pending.dmem_delay = meta.dmem_delay`; (b) Hardcode delay đa dạng 1/2/3/4/5 trong send_case | tb_lsu_thesis.sv |
| 5 | `SVA_HS: req rose but grant did not within 16 cyc` (false positive) | `$rose(REQ) \|-> ##[1:N] GNT` không match handshake same-cycle do NBA race giữa `wait()` driver và DUT | Đổi sang `REQ \|-> ##[0:N] GNT` (không cần $rose, cho phép ##0) | tb_thesis_sva.svh |
| 6 | **[FWD] rf_we=0 chưa bao giờ test** | Line 117-123 directed + tất cả random (138,145,152,159,166,169,176) đều hardcode `we_mem=1'b1, we_wb=1'b1`. Corner case "không forward khi write-enable=0" bị bỏ sót hoàn toàn | Trong `fwd_stress_seq::body()`: thêm 2 directed case cuối `send_case(..., 5'd3, 1'b0, 5'd8, 1'b1)` (we_mem=0) và `send_case(..., 5'd4, 1'b1, 5'd4, 1'b0)` (we_wb=0); thêm bucket `"WE_DIS"` 5% vào dice + xử lý: pick rs1=rd_mem nhưng we_mem=0 → expected fwd=2'b00 | tb_fwd_thesis.sv |
| 7 | **[FWD] Coverage đếm đôi** | `fwd_scoreboard` (line 373: `mc` field; line 380-387: `build_phase add_bins`; line 423-448: `coverage_sample`; line 452: `mc.report()`) trùng y hệt `fwd_coverage`. Cả hai connect `ap_dut` → cả hai sample cùng data → `[COV] fwd:` in 2 lần | Xóa khỏi `fwd_scoreboard`: field `mc` (line 373), toàn bộ `build_phase` add_bin (380-387), function `coverage_sample` (423-448), dòng `mc.report()` (452). Giữ nguyên `fwd_coverage` | tb_fwd_thesis.sv |
| 8 | **[CORE] Scoreboard check quá lỏng** | Header comment line 12-14 nói "exact, deterministic" nhưng line 352: `ok_stall = (obs_stalls >= p.load_use_cnt)` và line 360: `ok_store = (obs_stores >= p.store_cnt)` chỉ check lower bound. DUT stall thừa / store thừa vẫn pass | Đổi line 352: `ok_stall = (obs_stalls >= p.load_use_cnt) && (obs_stalls <= p.load_use_cnt + 10)`; đổi line 360: `ok_store = (obs_stores >= p.store_cnt) && (obs_stores <= p.store_cnt + 5)`; cập nhật string s_stall/s_store cho đúng | tb_core_riscv_thesis.sv |
| 9 | **[CORE] pred_alu_raw undercount** (design weakness, non-critical) | Line 239: `if (rs1 == last_rd && last_rd != 0) pred_alu_raw++` chỉ track rs1. Nếu chỉ rs2 match last_rd thì không count → Bảng 1 ALU-RAW thấp hơn thực tế | Đổi thành `if ((rs1 == last_rd \|\| rs2 == last_rd) && last_rd != 0) pred_alu_raw++` | tb_core_riscv_thesis.sv |
| 10 | **[CORE] obs_* counters luôn=0** → STALLS=0, FLUSHES=0 → 3/3 FAIL | Không có code nào increment `obs_stalls`, `obs_flushes` v.v. Thiếu monitor block trong `tb_top`. Vopt không cần quan sát nội tại DUT nên tối ưu hóa tất cả hazard signals → DUT chạy "như không có stall" | Trong `tb_top` (sau line 388 — port connection của `dut`), thêm `always @(negedge clk)` block: `if (dut.ctrl_force_stall_id) obs_stalls++; if (dut.ctrl_flush_if_id \|\| dut.ctrl_flush_id_ex) obs_flushes++; if (vif.dmem_valid_o && vif.dmem_ready_i && !vif.dmem_we_o) obs_loads++; if (vif.dmem_valid_o && vif.dmem_ready_i && vif.dmem_we_o) obs_stores++; if (vif.dbg_wb_we) obs_wb++; if (dut.ctrl_fwd_rs1_sel==2'b01 \|\| dut.ctrl_fwd_rs2_sel==2'b01) obs_fwd_ex++; if (dut.ctrl_fwd_rs1_sel==2'b10 \|\| dut.ctrl_fwd_rs2_sel==2'b10) obs_fwd_mem++;` | tb_core_riscv_thesis.sv (tb_top module) |
| 11 | **[CORE] Coverage 0/11** mặc dù sim chạy | `core_coverage.final_sample()` (line 297-299) có nội dung là comment dummy `// Dummy check to silence unused warning`. Không có dòng `mc.hit_bin()` nào được gọi | Thay body của `final_sample()` thành: `if (p.alu_raw_cnt>0) mc.hit_bin("hz_alu_raw"); if (p.load_use_cnt>0) mc.hit_bin("hz_load_use"); if (p.branch_cnt>0) mc.hit_bin("hz_branch"); if (p.store_cnt>0) mc.hit_bin("hz_store"); if (obs_stalls>0) mc.hit_bin("ev_stall"); if (obs_flushes>0) mc.hit_bin("ev_flush"); if (obs_loads>0) mc.hit_bin("ev_load"); if (obs_stores>0) mc.hit_bin("ev_store_actual"); if (obs_wb>0) mc.hit_bin("ev_wb"); if (obs_fwd_ex>0) mc.hit_bin("ev_fwd_ex"); if (obs_fwd_mem>0) mc.hit_bin("ev_fwd_mem");` | tb_core_riscv_thesis.sv (line 297) |
| 12 | **[CORE] IMEM DEADLOCK** sau khi thêm monitor block Bug #10. `imem_hang` tăng 82827 cycles liên tục. Log: `IMEM: Req(1) Rdy(0) Addr(0000002a) \| Rsp(1) Ack(0) Inst(00408133)` | **Root cause chuỗi**: (1) Bug #10 monitor bắt buộc Questa evaluate đầy đủ hazard unit → `ctrl_force_stall_id` có giá trị thực (không bị tối ưu hóa = 0 nữa). (2) Khi load-use hazard xảy ra, `ctrl_force_stall_id=1` → pipeline stall → `imem_ready_o=0`. (3) Nhưng `handle_imem` đã drop `imem_ready_i=0` (line 102) TRƯỚC khi deliver response. (4) `pc_gen.sv line 69`: `if (ready_i)` — PC chỉ advance khi `imem_ready_i=1`. (5) `imem_ready_o` của pipeline có thể phụ thuộc vào `imem_ready_i`  (pipeline cần biết có thể nhận instr mới không). (6) Kết quả: TB chờ `imem_ready_o=1`, core chờ `imem_ready_i=1` → DEADLOCK. **Tại sao trước đây không deadlock**: Vopt tối ưu hazard unit → `ctrl_force_stall_id=0` mọi lúc → không có stall → `imem_ready_o=1` ngay → `handle_imem` hoàn thành bình thường. | **Fix `handle_imem` task** (line 94-114 trong tb_core_riscv_thesis.sv): Sau dòng set `vif.imem_valid_i <= 1'b1` (line ~107), THÊM `vif.imem_ready_i <= 1'b1;`. Cuối task sau `vif.imem_valid_i <= 0;`, THÊM `vif.imem_ready_i <= 0;`. Sequence đầy đủ: capture addr → drop ready → delay → set instr+valid+ready → wait ack → drop valid+ready. | tb_core_riscv_thesis.sv (handle_imem task, line 107 + line 113) |
---

## 6. Lưu ý & gotcha

- **License lock**: Không dùng `randomize()` / `rand` / `randc`. Dùng dice class `dice_pct(table)` trong `tb_thesis_pkg.sv`.
- **Tb cũ regression**: Sau khi xong tb mới, phải verify `vsim -do run_lsu.do` (tb cũ) vẫn pass.
- **Wave marker**: Mỗi `THESIS_CHECK` phải pulse `tb_check_pass` + tăng `tb_test_id` để wave nhìn được test boundary.
- **Path**: TB mới ở `verify4thesis/logs/`, KHÔNG ở `verify/UVM/core/` để không lẫn tb cũ.

---

## 7. Lệnh chạy nhanh

```bash
# Single tb (sau khi viết xong)
cd ~/workspace/project2_axi/sim
vsim -do ../verify4thesis/logs/scripts/run_lsu_thesis.do

# Regression toàn bộ
bash ~/workspace/project2_axi/verify4thesis/logs/scripts/run_regression.sh

# Merge coverage + report
vsim -c -do ~/workspace/project2_axi/verify4thesis/logs/scripts/merge_coverage.do
cat ~/workspace/project2_axi/verify4thesis/logs/output/cov_summary.txt
```

---

## 8. Reference

- DUT package: `~/workspace/project2_axi/src/package/riscv_32im_pkg.sv`
- DUT modules: `~/workspace/project2_axi/src/core/{lsu,forwarding_unit,hazard_unit,riscv_control,csr}.sv`, `src/soc_top.sv`
- TB cũ (reuse env/agent/golden): `~/workspace/project2_axi/verify/UVM/core/tb_*.sv`
- Thesis docx: `~/workspace/project2_axi/doc/Thesis/thesis_khoa_update.docx`

---

## 9. Handoff — next chat pickup từ đây

> Đọc section này ĐẦU TIÊN. Đủ context để tiếp tục ngay không cần đọc lại file cũ.

### 9.1 State kết thúc session 2026-05-08 (session 3)

Session này đã xác định:
- Bug #10: thiếu monitor `always @(negedge clk)` trong `tb_top` → `obs_*` counters luôn=0
- Bug #11: `core_coverage.final_sample()` rỗng → 0/11 bins
- Bug #12: IMEM DEADLOCK — root cause là `handle_imem` drop `imem_ready_i=0` trước khi deliver response, kết hợp với monitor Bug #10 bắt Questa evaluate đầy đủ hazard unit → pipeline stall thực sự → `imem_ready_o` không bao giờ=1

**Chưa sửa code nào** — user sửa tay theo hướng dẫn trong Bug table.

### 9.2 Ba fix cần làm trong tb_core_riscv_thesis.sv (theo thứ tự)

**File**: `~/workspace/project2_axi/verify4thesis/logs/tb_core_riscv_thesis.sv`

---

**FIX A — Bug #12 (DEADLOCK): sửa `handle_imem` task**

Vị trí: task `handle_imem` trong `core_driver`, khoảng line 94-114.

Tìm đoạn:
```systemverilog
    // 2. Trả lệnh về cho Core
    vif.imem_valid_i <= 1'b1;
    vif.imem_instr_i <= (captured_addr[13:2] < 4096) ? fake_imem[captured_addr[13:2]] : 32'h0000_0013;
    
    // 3. Kiên nhẫn chờ Core xác nhận (Tuyệt đối không dùng Timeout ở đây)
    do @(posedge vif.clk_i); while (!(vif.imem_valid_i && vif.imem_ready_o));
    
    vif.imem_valid_i <= 0;
```

Sửa thành:
```systemverilog
    // 2. Trả lệnh về cho Core
    vif.imem_valid_i <= 1'b1;
    vif.imem_instr_i <= (captured_addr[13:2] < 4096) ? fake_imem[captured_addr[13:2]] : 32'h0000_0013;
    vif.imem_ready_i <= 1'b1;   // re-assert: unlock pipeline stall, allow PC advance on ack

    // 3. Kiên nhẫn chờ Core xác nhận (Tuyệt đối không dùng Timeout ở đây)
    do @(posedge vif.clk_i); while (!(vif.imem_valid_i && vif.imem_ready_o));
    
    vif.imem_valid_i <= 0;
    vif.imem_ready_i <= 0;      // drop cả hai sau khi ack
```

---

**FIX B — Bug #10: thêm monitor block vào `tb_top`**

Vị trí: module `tb_top`, SAU dấu `);` kết thúc port connections của `dut` instance (khoảng line 388), TRƯỚC comment `// =========================================================================`.

Thêm block mới:
```systemverilog
  // Monitor: sample DUT internal control signals at negedge → drive obs_* counters
  always @(negedge clk) begin
    if (!vif.rst_i) begin
      if (dut.ctrl_force_stall_id)                                      core_thesis_pkg::obs_stalls++;
      if (dut.ctrl_flush_if_id || dut.ctrl_flush_id_ex)                core_thesis_pkg::obs_flushes++;
      if (vif.dmem_valid_o && vif.dmem_ready_i && !vif.dmem_we_o)      core_thesis_pkg::obs_loads++;
      if (vif.dmem_valid_o && vif.dmem_ready_i &&  vif.dmem_we_o)      core_thesis_pkg::obs_stores++;
      if (vif.dbg_wb_we)                                                core_thesis_pkg::obs_wb++;
      if (dut.ctrl_fwd_rs1_sel == 2'b01 || dut.ctrl_fwd_rs2_sel == 2'b01)
          core_thesis_pkg::obs_fwd_ex++;
      if (dut.ctrl_fwd_rs1_sel == 2'b10 || dut.ctrl_fwd_rs2_sel == 2'b10)
          core_thesis_pkg::obs_fwd_mem++;
    end
  end
```

Lưu ý: `dut.ctrl_force_stall_id`, `dut.ctrl_flush_if_id`, `dut.ctrl_flush_id_ex`, `dut.ctrl_fwd_rs1_sel`, `dut.ctrl_fwd_rs2_sel` là internal wire của `riscv_core`. Các tên này xác nhận tại `src/core/riscv_core.sv` line 44-48. Hierarchical access hợp lệ vì vsim dùng `-voptargs="+acc=all"`.

---

**FIX C — Bug #11: điền `core_coverage.final_sample()`**

Vị trí: class `core_coverage`, function `final_sample`, khoảng line 297-299.

Tìm:
```systemverilog
    function void final_sample(core_prediction p);
      // Dummy check to silence unused warning
    endfunction
```

Sửa thành:
```systemverilog
    function void final_sample(core_prediction p);
      if (p.alu_raw_cnt  > 0) mc.hit_bin("hz_alu_raw");
      if (p.load_use_cnt > 0) mc.hit_bin("hz_load_use");
      if (p.branch_cnt   > 0) mc.hit_bin("hz_branch");
      if (p.store_cnt    > 0) mc.hit_bin("hz_store");
      if (obs_stalls     > 0) mc.hit_bin("ev_stall");
      if (obs_flushes    > 0) mc.hit_bin("ev_flush");
      if (obs_loads      > 0) mc.hit_bin("ev_load");
      if (obs_stores     > 0) mc.hit_bin("ev_store_actual");
      if (obs_wb         > 0) mc.hit_bin("ev_wb");
      if (obs_fwd_ex     > 0) mc.hit_bin("ev_fwd_ex");
      if (obs_fwd_mem    > 0) mc.hit_bin("ev_fwd_mem");
    endfunction
```

---

### 9.3 Sau khi sửa xong — chạy sim core

```bash
cd ~/workspace/project2_axi/sim
vsim -do ../verify4thesis/logs/scripts/run_core_thesis.do
```

Kỳ vọng khi pass:
```
[BANG1] instr=91 ALU_RAW=42 LOAD_USE=21 BRANCH=12 STORE=16 STALLS=21 FLUSHES=24 ...
SUMMARY: 3/3 PASS
[COV] core: 11/11 = 100.00%
```

Nếu vẫn deadlock: kiểm tra lại FIX A có đúng vị trí không. Nếu STALLS vẫn=0: kiểm tra FIX B có đúng signal names không (so với src/core/riscv_core.sv).

---

### 9.4 Sau khi core pass — chạy fwd + hazadetec

```bash
vsim -do ../verify4thesis/logs/scripts/run_fwd_thesis.do
vsim -do ../verify4thesis/logs/scripts/run_hazadetec_thesis.do
```

Kỳ vọng: fwd 100/100 PASS COV 9/9, hazadetec 100/100 PASS COV 9/9.

---

### 9.5 Tiếp theo sau khi 3 module pass — tb_control_thesis

DUT: `riscv_control` trong `src/core/riscv_control.sv`.
Pattern giống `tb_hazadetec_thesis.sv`: interface + package + 10 directed + 90 random + golden + manual_cov + scoreboard.
Trước khi viết, đọc port list: `grep -n "input\|output" ~/workspace/project2_axi/src/core/riscv_control.sv | head -40`

---

### 9.6 Lưu ý kiến trúc đã học (KHÔNG thay đổi giữa sessions)

- **License lock**: KHÔNG dùng `randomize()` / `rand` / `randc` / `covergroup`. Dùng `tb_thesis_pkg::manual_cov` + `dice_pct`.
- **Mailbox inflight pattern**: driver put(req) trước `@posedge`, monitor get() sau `@negedge+#1`. Pattern đã verified ở lsu.
- **Package-level global obs_***: Pattern chỉ đúng cho single-sim tb_core. Không copy sang tb khác.
- **SVA**: dùng `wire rst_n = !vif.rst_i` nếu cần enable. Macro NO_X/ONEHOT0/HANDSHAKE đã tested.
- **fwd_scoreboard clean**: scoreboard KHÔNG có manual_cov — chỉ compare_txn + super.report_phase.
- **IMEM protocol (tb_core)**: `imem_ready_i` vừa là "TB accept request" vừa là "pipeline can advance" (pc_gen.sv line 69). Khi deliver response, phải re-assert `imem_ready_i=1` để pipeline có thể drain stalls.
- **Decoder path**: dùng `src/decoder/decoder.sv`, KHÔNG phải `src/core/decoder.sv`.
- **Package path**: `~/workspace/project2_axi/package/riscv_32im_pkg.sv` (KHÔNG phải src/package/).
- **Tb cũ regression**: Sau khi xong tb mới, phải verify `vsim -do run_lsu.do` (tb cũ) vẫn pass.
