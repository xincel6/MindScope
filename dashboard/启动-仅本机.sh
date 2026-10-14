#!/usr/bin/env bash
# ==============================================================================
#  MindScope 服务端 · Linux/macOS 一键启动（仅本机 · 安全默认）
#
#  用法：
#      chmod +x 启动-仅本机.sh
#      ./启动-仅本机.sh
#
#  等价于 Windows 下的 启动-仅本机.bat
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/backend"

export KMP_DUPLICATE_LIB_OK=TRUE
# 不设 HOST，沿用 serve_all.py 的默认值 127.0.0.1（只有本机可访问）
export PORT="${PORT:-8000}"

echo "=============================================="
echo "  MindScope - LOCAL ONLY (safe mode)"
echo "  Open http://127.0.0.1:${PORT} on THIS machine"
echo "=============================================="

PY=""
for candidate in venv/bin/python venv/Scripts/python.exe; do
  if [ -x "$candidate" ]; then PY="$candidate"; break; fi
done
if [ -z "$PY" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PY="python3"
    echo "  [WARN] 未找到 venv，回退到系统 python3"
  else
    echo "  [ERROR] 找不到可用的 Python。"
    echo "          请先执行：python3 -m venv venv && venv/bin/pip install -r requirements.txt"
    exit 1
  fi
fi

echo "  Python : $PY"
echo "=============================================="
exec "$PY" serve_all.py
