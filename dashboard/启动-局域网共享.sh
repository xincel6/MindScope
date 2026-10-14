#!/usr/bin/env bash
# ==============================================================================
#  MindScope 服务端 · Linux/macOS 一键启动
#
#  用法：
#      chmod +x 启动-局域网共享.sh        # 只需执行一次
#      ./启动-局域网共享.sh               # 开放局域网（手机 / 其它电脑可访问）
#      ./启动-仅本机.sh                   # 仅本机可访问（安全默认）
#
#  等价于 Windows 下的两个 .bat 脚本。
# ==============================================================================
set -euo pipefail

# 切到脚本所在目录，再进 backend —— 等价于 .bat 里的 cd /d "%~dp0backend"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/backend"

# Linux 上 Intel OpenMP 冲突不会像 Windows 那样报错，设上更保险
export KMP_DUPLICATE_LIB_OK=TRUE

# ★ 关键：默认 127.0.0.1 只有本机能访问，手机连不上，必须 0.0.0.0
export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-8000}"

echo "=================================================="
echo "  MindScope - LAN SHARING"
echo "  Local  : http://127.0.0.1:${PORT}"
if command -v hostname >/dev/null 2>&1; then
  IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -n "${IP:-}" ] && echo "  LAN    : http://${IP}:${PORT}"
fi
echo "  Stop   : Ctrl+C"
echo "=================================================="

# 优先用项目自带 venv，找不到再回退到系统 python3
PY=""
for candidate in venv/bin/python venv/Scripts/python.exe; do
  if [ -x "$candidate" ]; then PY="$candidate"; break; fi
done
if [ -z "$PY" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PY="python3"
    echo "  [WARN] 未找到 venv，回退到系统 python3：$(command -v python3)"
    echo "         建议先建虚拟环境：python3 -m venv venv && venv/bin/pip install -r requirements.txt"
  else
    echo "  [ERROR] 找不到可用的 Python。"
    echo "          请先执行：python3 -m venv venv && venv/bin/pip install -r requirements.txt"
    exit 1
  fi
fi

echo "  Python : $PY"
echo "=================================================="
exec "$PY" serve_all.py
