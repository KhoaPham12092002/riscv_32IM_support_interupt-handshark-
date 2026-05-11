# AI Framework — Manager/Worker Protocol

## Kiến trúc 2 tầng

```
┌─────────────────────────────────────────────┐
│          CLAUDE CODE  (Manager)             │
│   Suy luận sâu · Quyết định · Kiến trúc    │
└──────────────┬──────────────────────────────┘
               │ delegate qua shell script
               ▼
┌─────────────────────────────────────────────┐
│          GEMINI CLI  (Worker)               │
│   Viết code · Edit file · Tác vụ thứ cấp   │
└─────────────────────────────────────────────┘
```

## Scripts có sẵn

| Script | Mode | Dùng khi |
|--------|------|----------|
| `~/ai-framework/bin/delegate.sh` | flexible | Tác vụ tổng quát |
| `~/ai-framework/bin/gemini-edit.sh` | auto_edit | Chỉ cần edit file |
| `~/ai-framework/bin/gemini-run.sh` | yolo | Cần chạy lệnh shell |

## Phân công nhiệm vụ

### Claude Code tự xử lý (KHÔNG delegate):
- Phân tích yêu cầu, lập kế hoạch thực thi
- Quyết định kiến trúc hệ thống
- Debug logic phức tạp, truy vết bug khó
- Review security, xác định lỗ hổng
- Đọc và hiểu codebase lớn
- Ra quyết định trade-off quan trọng
- Bất kỳ task nào cần **lý luận nhiều bước sâu**

### Delegate cho Gemini (tiết kiệm Claude limit):
- Viết boilerplate code theo spec đã định sẵn
- Edit/refactor file theo instruction rõ ràng
- Tạo test cases cho module đã biết
- Viết documentation
- Format, lint, type-hint tự động
- Tạo nhiều file theo template
- Tác vụ lặp đi lặp lại trên nhiều file
- Search và thay thế pattern trên codebase

## Cách delegate từ Claude Code

### Cú pháp cơ bản trong Bash tool:
```bash
# Edit file
~/ai-framework/bin/delegate.sh "Thêm docstring cho tất cả function" src/utils.py

# Nhiều file
~/ai-framework/bin/delegate.sh "Convert sang TypeScript" src/api.js src/db.js

# Trong thư mục cụ thể
~/ai-framework/bin/delegate.sh -d ~/project "Tạo README.md chi tiết"

# Cần chạy lệnh (yolo)
~/ai-framework/bin/delegate.sh -y "Cài deps và chạy tests, fix errors nếu có"

# Chỉ review, không edit
~/ai-framework/bin/delegate.sh -r "Review code và liệt kê potential issues" src/auth.py
```

### Workflow điển hình:
1. **Claude** phân tích yêu cầu → quyết định spec
2. **Claude** dùng Bash tool gọi `delegate.sh` với instruction rõ ràng
3. **Gemini** tự động edit/tạo file
4. **Claude** review kết quả, điều chỉnh nếu cần

## Giới hạn quan trọng

**Gemini chỉ đọc/ghi file trong `/home/key`** (workspace trust).
- File phải nằm trong `/home/key` hoặc subdirectory
- Không thể edit file trong `/tmp`, `/etc`, hoặc ngoài home
- Khi delegate, luôn dùng absolute path bắt đầu bằng `/home/key/` hoặc `~/`

## Quy tắc vàng

- Viết instruction cho Gemini **càng cụ thể càng tốt** — không mơ hồ
- Luôn chỉ định file/directory rõ ràng
- Dùng `--edit` khi chỉ cần sửa file (an toàn hơn `--yolo`)
- Dùng `--yolo` khi cần cài package hoặc chạy build
- Sau khi Gemini chỉnh file, **Claude review** trước khi báo user xong
