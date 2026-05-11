#!/bin/bash
# ============================================================
#  delegate.sh — Giao việc cho Gemini CLI worker
#  Dùng bởi Claude Code (manager) để ủy thác tác vụ thứ cấp
# ============================================================
#
#  CÁCH DÙNG:
#    delegate.sh [OPTIONS] "mô tả task" [file1 file2 ...]
#
#  OPTIONS:
#    -y, --yolo       Auto-approve TẤT CẢ hành động (kể cả chạy lệnh shell)
#    -e, --edit       Auto-approve CHỈ file edits (mặc định)
#    -r, --readonly   Chỉ đọc, không ghi file (plan mode)
#    -d, --dir DIR    Thư mục làm việc (mặc định: thư mục hiện tại)
#    -j, --json       Output dạng JSON
#    -m, --model MOD  Chỉ định model Gemini (vd: gemini-2.5-pro)
#    -l, --log        Ghi log ra ~/ai-framework/logs/tasks.log
#
#  VÍ DỤ:
#    delegate.sh "Thêm error handling cho file này" src/api.py
#    delegate.sh -y "Tạo test suite cho module auth, chạy luôn" src/auth.py
#    delegate.sh -r "Review code này và liệt kê các vấn đề" src/main.py
#    delegate.sh -d ~/project "Refactor tất cả import thành absolute"
# ============================================================

set -euo pipefail

APPROVAL_MODE="auto_edit"
WORK_DIR="$(pwd)"
OUTPUT_FORMAT="text"
MODEL=""
DO_LOG=false
LOG_FILE="$HOME/ai-framework/logs/tasks.log"

# Parse options
while [[ $# -gt 0 && "$1" == -* ]]; do
    case "$1" in
        -y|--yolo)       APPROVAL_MODE="yolo" ;;
        -e|--edit)       APPROVAL_MODE="auto_edit" ;;
        -r|--readonly)   APPROVAL_MODE="plan" ;;
        -d|--dir)        WORK_DIR="$2"; shift ;;
        -j|--json)       OUTPUT_FORMAT="json" ;;
        -m|--model)      MODEL="$2"; shift ;;
        -l|--log)        DO_LOG=true ;;
        --) shift; break ;;
        *) echo "[delegate] Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

if [[ $# -eq 0 ]]; then
    echo "Usage: delegate.sh [OPTIONS] \"task prompt\" [file1 file2 ...]" >&2
    exit 1
fi

TASK_PROMPT="$1"
shift
FILES=("$@")

# Xây dựng prompt đầy đủ với context về files
FULL_PROMPT="$TASK_PROMPT"

if [[ ${#FILES[@]} -gt 0 ]]; then
    FULL_PROMPT="$FULL_PROMPT

Files cần làm việc:"
    for f in "${FILES[@]}"; do
        if [[ -e "$f" ]]; then
            FULL_PROMPT="$FULL_PROMPT
- $(realpath "$f")"
        else
            echo "[delegate] Warning: file không tồn tại: $f" >&2
        fi
    done
fi

# Build gemini command
GEMINI_ARGS=(
    "--prompt" "$FULL_PROMPT"
    "--approval-mode" "$APPROVAL_MODE"
    "--output-format" "$OUTPUT_FORMAT"
)

[[ -n "$MODEL" ]] && GEMINI_ARGS+=("--model" "$MODEL")

# Log task nếu cần
if $DO_LOG; then
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | mode=$APPROVAL_MODE | dir=$WORK_DIR" >> "$LOG_FILE"
    echo "  TASK: $TASK_PROMPT" >> "$LOG_FILE"
    [[ ${#FILES[@]} -gt 0 ]] && echo "  FILES: ${FILES[*]}" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
fi

# Chạy Gemini trong working directory
cd "$WORK_DIR"
exec gemini "${GEMINI_ARGS[@]}"
