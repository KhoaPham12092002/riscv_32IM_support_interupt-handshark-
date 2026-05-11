# CLAUDE.md — project2_axi (LVTN RISC-V RV32IM)

## Context tự động
File này được Claude load khi mở thư mục project. Không cần nhắc Claude đọc rule thủ công.
**CRITICAL RULE:** Do anything by English but when in conversation then use Vietnamese.


---

## Dự án
LVTN: RTL SystemVerilog + UVM Verification cho RISC-V RV32IM 5-stage pipeline.
- Source: `src/`
- Sim: `sim/`  
- Thesis figures: `doc/Thesis/`
- Rule chi tiết: `~/ai-framework/CLAUDE.md`


### Cấu trúc
- TẤT CẢ mxCell phải có `parent="1"` — KHÔNG nested, KHÔNG group cell
- ID đơn giản: "2", "3", "4", ... (không dùng chuỗi hash)
- Bọc trong `<mxfile>` → `<diagram>` → `<mxGraphModel>` → `<root>`

### Text trong value=""
```
# ĐÚNG — escape trong XML attribute:
value="dòng 1&lt;br&gt;dòng 2"
value="&lt;b&gt;tiêu đề&lt;/b&gt;"

# SAI — gây lỗi XML parser:
value="dòng 1<br>dòng 2"       ← unescaped <
value="dòng 1&#xa;dòng 2"      ← không hoạt động với html=1
```

### Style cho cell có multiline / HTML tag
```
style="rounded=1;whiteSpace=wrap;html=1;..."
```
Thiếu `html=1` → `<b>`, `<br>` hiển thị literal. Thiếu `whiteSpace=wrap` → text không xuống hàng.

### Edge rules
- Luôn có `source=` và `target=` — KHÔNG dùng sourcePoint/targetPoint thay thế
- Waypoints đặt trong `<Array as="points"><mxPoint .../></Array>`
- Hai edge song song: dùng waypoint x lệch nhau ≥10px để tránh overlap

---

## Trạng thái thesis figures (cập nhật 06/05/2026)

| File | Trạng thái |
|------|-----------|
| hinh2_7_trap_handling.drawio | ✅ Fixed |
| hinh2_8_uvm_hierarchy.drawio | ✅ Cần rewrite flat (prompt đã có) |
| hinh3_1_tong_quat_he_thong.drawio | ✅ Rewrite hoàn chỉnh (thêm VIF box, fix duplicate cells, fix edges) |
| hinh3_2_datapath.drawio | ✅ OK |
| hinh3_3_munit_fsm.drawio | ✅ OK |
| hinh3_4_forwarding_logic.drawio | ✅ OK |
| hinh4_1_uvm_environment.drawio | ✅ Fixed |
| hinh4_2_transaction_class.drawio | ✅ OK |
| hinh2_2, 2_3, 2_4, 2_5, 2_6 | ✅ OK (minor notes trong se_chinh.txt) |
| hinh5_1 → 5_8 | ❌ Cần chụp từ QuestaSim sim |

Tham khảo đầy đủ: `doc/Thesis/se_chinh.txt`

---

## Trạng thái thesis_khoa_update.docx (cập nhật 06/05/2026)

**Formatting đã chuẩn hóa** theo `DD_Huong dan viet TM_DATN_2026May05.pdf`:
- Lề: 40mm left / 25mm right / 40mm top / 25mm bottom
- Font: Times New Roman 13pt, giãn dòng 1.3
- Heading 1 (chương): TNR 14pt, bold, in hoa, canh giữa, xuống trang mới
- Heading 2/3 (mục): TNR 13pt, bold, canh trái
- Footer: số trang canh giữa
- Backup: `doc/Thesis/thesis_khoa_update_backup.docx`

**Việc còn lại trước khi nộp:**
- [ ] Chụp waveform QuestaSim → chèn vào Hình 5.1–5.8
- [ ] Viết nội dung Lời cảm ơn
- [ ] Dán phiếu nhiệm vụ có chữ ký sống (in riêng)

**Ghi chú nội dung:**
- Section numbering Ch.4 dùng "1./2./3.x" thay vì "4.1/4.2/4.3" — chưa đồng bộ
- Log chi tiết session: `~/ai-framework/logs/session_2026-05-06_thesis-reformat.md`

---

## RTL Pitfalls quan trọng
- Forwarding: MEM→EX trước WB→EX (priority order)
- CSR trap: clear MIE cùng cycle với trap, không phải cycle sau
- Decoder: dùng `src/decoder/decoder.sv`, KHÔNG phải `src/core/decoder.sv`
- Branch penalty: 2 cycles (Late Branch Resolution tại EX stage)
- Divide-by-zero: không raise exception (theo RISC-V M-ext spec)
- M-Unit: MUL=2 cycles, DIV=35 cycles (restoring division)

## Lệnh thường dùng
```bash
make lint          # lint toàn bộ
make lint_quiet    # chỉ hiện error
cd sim && vsim -do run_<module>.do   # chạy sim
```
