#!/bin/bash
# ============================================================
#  gemini-edit.sh — Gemini chỉnh sửa file theo yêu cầu
#  Shortcut chuyên dụng cho tác vụ edit file
# ============================================================
#
#  CÁCH DÙNG:
#    gemini-edit.sh "instruction" file1 [file2 ...]
#
#  VÍ DỤ:
#    gemini-edit.sh "Thêm type hints cho tất cả function" src/utils.py
#    gemini-edit.sh "Convert sang async/await" src/api.py src/db.py
#    gemini-edit.sh "Fix tất cả lỗi lint" src/
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 ]]; then
    echo "Usage: gemini-edit.sh \"instruction\" file1 [file2 ...]" >&2
    exit 1
fi

exec "$SCRIPT_DIR/delegate.sh" --edit "$@"
