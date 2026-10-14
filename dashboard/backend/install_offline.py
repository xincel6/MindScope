# -*- coding: utf-8 -*-
"""
纯离线安装 wheelhouse 里的全部 wheel。

为什么需要它：pip 不接受"目录"或通配符作为包参数，手工敲几十个文件名极易出错。
本脚本自动枚举 wheelhouse 里的 wheel 并交给 pip 安装，全程不联网。

用法（在 backend 目录下，且已激活 venv）:
    python install_offline.py
"""
import subprocess
import sys
from pathlib import Path

WH = Path(__file__).resolve().parent / "wheelhouse"


def main():
    if not WH.is_dir():
        print(f"[错误] 找不到依赖目录: {WH}")
        print("       请先运行:  python fetch_wheels.py")
        return 1

    wheels = sorted(WH.glob("*.whl"))
    if not wheels:
        print(f"[错误] {WH} 里没有 wheel 文件")
        print("       请先运行:  python fetch_wheels.py")
        return 1

    print(f"发现 {len(wheels)} 个 wheel，开始离线安装 ...")
    cmd = [
        sys.executable, "-m", "pip", "install",
        "--no-index",          # 禁止访问网络索引（避开卡死的关键）
        "--no-deps",           # 不做依赖解析（依赖已备齐）
        "--find-links", str(WH),
        "--progress-bar", "off",
        *[str(w) for w in wheels],
    ]
    print("执行:", " ".join(cmd[:8]), f"... 共 {len(wheels)} 个包")
    rc = subprocess.call(cmd)
    print("-" * 60)
    if rc == 0:
        print("离线安装完成。接着运行:  python _verify_env.py")
    else:
        print(f"安装失败（退出码 {rc}）")
    return rc


if __name__ == "__main__":
    sys.exit(main())
