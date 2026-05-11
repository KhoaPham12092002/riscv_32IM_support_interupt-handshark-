#!/bin/bash
# ============================================================
#  gemini-run.sh — Gemini thực thi task phức tạp (yolo mode)
#  Dùng khi task cần chạy shell command + edit file
# ============================================================
#
#  CÁCH DÙNG:
#    gemini-run.sh "task" [dir]
#
#  VÍ DỤ:
#    gemini-run.sh "Tạo project React mới tên my-app" ~/projects
#    gemini-run.sh "Chạy test và fix các lỗi thất bại" ~/myproject
#    gemini-run.sh "Cài dependencies còn thiếu và update requirements.txt"
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: gemini-run.sh \"task\" [working_dir]" >&2
    exit 1
fi

TASK="$1"
DIR="${2:-$(pwd)}"

exec "$SCRIPT_DIR/delegate.sh" --yolo --dir "$DIR" "$TASK"
