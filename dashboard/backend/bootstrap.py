#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
MindScope 一键启动引导（Windows / Linux 通用）

双击 `启动-仅本机.bat` / `启动-局域网共享.bat` 之后，这个脚本负责剩下所有事情：

    [1/5] 环境检查        Python 版本、项目文件是否齐全
    [2/5] 虚拟环境        缺失就自动 python -m venv 建一个 backend\\venv
    [3/5] 依赖安装        自动装 requirements.txt
                          · 有 backend\\wheelhouse 就离线安装（最快、最稳）
                          · 否则用国内镜像在线安装，卡死会自动中断换源
                          · 全失败时改用 fetch_wheels.py 强制 IPv4 抓包再离线装
    [4/5] 项目文件        .env、模型权重、前端 dist 的检查（缺失时尽量自动补齐）
    [5/5] 启动服务        自动选端口、启动 uvicorn、端口就绪后自动打开浏览器

设计目标：**任何人拿到这个项目，双击 bat 就能用**，不需要先手动装依赖、
不需要知道 venv 是什么、不需要改任何源码。

命令行参数（一般用不到）：
    --check           只做检查与依赖自检，不启动服务
    --no-browser      启动后不自动打开浏览器
    --force-deps      忽略“依赖已就绪”标记，强制重新安装依赖
    --rebuild-venv    删除并重建虚拟环境
    --port 8000       指定端口（等价于设置环境变量 PORT）

日志：所有输出同时写入 backend\\bootstrap.log，出问题时把它一起发出来即可。
"""

from __future__ import annotations

import argparse
import hashlib
import os
import queue
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

# --------------------------------------------------------------------------- 路径
BACKEND = Path(__file__).resolve().parent
DASHBOARD = BACKEND.parent
VENV = BACKEND / "venv"
VENV_PY = VENV / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
REQUIREMENTS = BACKEND / "requirements.txt"
WHEELHOUSE = BACKEND / "wheelhouse"
DEPS_MARK = VENV / ".mindscope_deps_ok"
FETCH_WHEELS = BACKEND / "fetch_wheels.py"
SERVE_ALL = BACKEND / "serve_all.py"
ENV_FILE = BACKEND / ".env"
ENV_EXAMPLE = BACKEND / ".env.example"
MODEL_CKPT = BACKEND / "best.pt"
# 模型结构有两份，服务不同入口（见 .gitignore 末尾说明）：
#   dashboard/LMTformer_model/          应用运行时用（services/inference.py）
#   dashboard/backend/LMTformer_model/  _verify_env.py 自检时用
MODEL_SRC = DASHBOARD / "LMTformer_model" / "LMTformer.py"
MODEL_SRC_BACKEND = BACKEND / "LMTformer_model" / "LMTformer.py"
DIST_INDEX = DASHBOARD / "dist" / "index.html"
LOG_FILE = BACKEND / "bootstrap.log"

MIN_PY = (3, 10)
MAX_PY = (3, 14)
DEFAULT_PORT = 8000
DEPS_SCHEMA = "v2"          # 改动安装逻辑时同步改这里，可让旧标记失效

# --------------------------------------------------------------------------- 镜像
# 顺序即优先级：国内镜像快，官方源兜底
# (显示名, index-url, --trusted-host 参数, 探测用主机名)
PYPI_MIRRORS = [
    ("阿里云", "https://mirrors.aliyun.com/pypi/simple/",
     "mirrors.aliyun.com", "mirrors.aliyun.com"),
    ("清华大学", "https://pypi.tuna.tsinghua.edu.cn/simple/",
     "pypi.tuna.tsinghua.edu.cn", "pypi.tuna.tsinghua.edu.cn"),
    ("腾讯云", "https://mirrors.cloud.tencent.com/pypi/simple/",
     "mirrors.cloud.tencent.com", "mirrors.cloud.tencent.com"),
    ("PyPI 官方", "https://pypi.org/simple/", None, "pypi.org"),
]

# 依赖自检清单（与 _verify_env.py 保持一致，另加两个"启动就会崩"的关键项）
#  · greenlet / sqlalchemy.ext.asyncio：database.py 用异步引擎，缺 greenlet 时
#    依赖装得像模像样，但 import main 直接 ImportError（实测踩到过：离线有、
#    在线没有）。这里提前查出来，比等服务启动到一半才崩好得多。
CHECK_MODULES = [
    "fastapi", "uvicorn", "sqlalchemy", "sqlalchemy.ext.asyncio", "greenlet",
    "aiosqlite", "pydantic", "multipart",
    "aiofiles", "numpy", "PIL", "cv2", "torch", "torchvision",
    "facenet_pytorch", "jose", "bcrypt", "httpx", "einops", "websockets",
    "watchfiles",
]

CHECK_CODE = (
    "import importlib, sys\n"
    "mods = %r\n"
    "missing = []\n"
    "for name in mods:\n"
    "    try:\n"
    "        importlib.import_module(name)\n"
    "        print('  OK    ' + name)\n"
    "    except Exception as exc:\n"
    "        missing.append(name)\n"
    "        print('  FAIL  ' + name + '  ' + type(exc).__name__ + ': ' + str(exc)[:160])\n"
    "print('MISSING=' + ','.join(missing))\n"
    "sys.exit(1 if missing else 0)\n"
) % (CHECK_MODULES,)

_log_lock = threading.Lock()


# =========================================================================== 输出
def log(message: str = "", echo: bool = True) -> None:
    """打印一行并同时写入 bootstrap.log（写日志失败不影响运行）。"""
    with _log_lock:
        if echo:
            try:
                print(message, flush=True)
            except UnicodeEncodeError:                       # 极端老终端兜底
                print(message.encode("ascii", "replace").decode("ascii"), flush=True)
        try:
            with LOG_FILE.open("a", encoding="utf-8") as fh:
                fh.write("[%s] %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), message))
        except OSError:
            pass


def _prepare_console() -> None:
    """被重定向到管道/文件时用 UTF-8 输出，避免中文变成乱码。"""
    for stream in (sys.stdout, sys.stderr):
        try:
            if not stream.isatty():
                stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


def _banner() -> None:
    log("")
    log("=" * 66)
    log("  MindScope  抑郁辅助诊断系统  -  一键启动")
    log("  第一次运行会自动安装依赖，约 1-2 GB，请保持联网、耐心等待")
    log("=" * 66)
    log("  日志文件：%s" % LOG_FILE)
    log("")


# =========================================================================== 工具
def child_env(extra: dict | None = None) -> dict:
    env = os.environ.copy()
    env.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")     # torch + opencv 双 OpenMP
    env["PYTHONIOENCODING"] = "utf-8"                   # 中文路径不炸
    env["PYTHONUTF8"] = "1"
    env["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
    env["PIP_NO_INPUT"] = "1"
    if extra:
        env.update(extra)
    return env


def _kill(proc: subprocess.Popen) -> None:
    try:
        proc.terminate()
        proc.wait(timeout=10)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def _probe_host(host: str, port: int = 443, timeout: float = 6.0) -> tuple[bool, str]:
    """快速判断某个镜像主机能不能用，并区分「DNS 解析失败」和「连不上」。

    实测过：某些机器上 Python 的域名解析会整体失败（getaddrinfo failed），
    这时再让 pip / 抓包脚本硬试，只会白等十几分钟。先探测能省下这段时间，
    也能给用户一句真正有用的结论。
    """
    try:
        socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
    except Exception as exc:
        return False, "域名解析失败（DNS）：%s" % type(exc).__name__
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True, ""
    except Exception as exc:
        return False, "连接 %s:%d 失败：%s" % (host, port, type(exc).__name__)


def _fetcher_hopeless(lines: list[str]) -> bool:
    """给 fetch_wheels.py 用的“别等了”判据：连续 3 个包都是网络错误就放弃。

    抓包脚本每个包失败都要退避重试约 14 秒，48 个包就是 11 分钟。网络整体
    不通时这是纯浪费，所以这里提前叫停。
    """
    fails = [line for line in lines if "FAIL" in line]
    if len(fails) < 3:
        return False
    markers = ("getaddrinfo failed", "URLError", "urlopen error",
               "Temporary failure", "timed out", "Name or service not known")
    return all(any(marker in line for marker in markers) for line in fails[-3:])


def run_streaming(cmd, label: str, cwd: Path | None = None, env: dict | None = None,
                  silence_timeout: int = 300, overall_timeout: int | None = None,
                  quiet: bool = False, abort_when=None) -> tuple[int, list[str]]:
    """运行子进程并实时回显输出。

    超过 silence_timeout 秒没有任何输出，判定为“卡死”（本项目实测过 pip 因
    IPv6 地址选择而空转数分钟），直接中断并返回 -9，让上层换下一种方案。
    abort_when(lines) 返回 True 时同样提前中断。
    返回 (退出码, 输出行)。
    """
    cmd = [str(c) for c in cmd]
    if not quiet:
        shown = " ".join(cmd).replace("\r", " ").replace("\n", " ")
        log("    $ " + (shown if len(shown) <= 300 else shown[:300] + " ..."))
    try:
        proc = subprocess.Popen(
            cmd, cwd=str(cwd or BACKEND), env=env or child_env(),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1,
            universal_newlines=True, encoding="utf-8", errors="replace",
        )
    except OSError as exc:
        log("    [!] 无法执行命令：%s" % exc)
        return 127, []

    box: queue.Queue = queue.Queue()

    def _reader() -> None:
        try:
            for line in proc.stdout:                       # type: ignore[union-attr]
                box.put(line)
        except Exception:
            pass
        finally:
            box.put(None)

    threading.Thread(target=_reader, daemon=True).start()

    out_lines: list[str] = []
    started = time.time()
    last_out = started
    next_beat = started + 30.0

    while True:
        try:
            line = box.get(timeout=1.0)
        except queue.Empty:
            now = time.time()
            if proc.poll() is not None and now - last_out > 5:
                break                                      # 已退出且输出读完
            if now - last_out > silence_timeout:
                log("    [!] %s 已 %d 秒没有任何输出，判定卡死，正在中断 ..." % (label, silence_timeout))
                _kill(proc)
                return -9, out_lines
            if overall_timeout and now - started > overall_timeout:
                log("    [!] %s 超过 %d 秒仍未完成，正在中断 ..." % (label, overall_timeout))
                _kill(proc)
                return -9, out_lines
            if now >= next_beat:
                log("    ... %s 进行中，已用 %d 秒（下载较大，请勿关闭窗口）" % (label, int(now - started)))
                next_beat = now + 30.0
            continue
        if line is None:
            break
        text = line.rstrip("\r\n")
        out_lines.append(text)
        if text.strip():
            last_out = time.time()          # 只有“有内容的输出”才算进度
            log("    " + (text if len(text) <= 400 else text[:400] + " ..."))
        if abort_when is not None and abort_when(out_lines):
            log("    [!] %s 连续失败，判定当前网络不可用，提前终止。" % label)
            _kill(proc)
            return -9, out_lines

    return proc.wait(), out_lines


def probe_python(exe: Path | str) -> str | None:
    """返回 '3.12.0' 这样的版本号；不可用或版本不在范围内时返回 None。"""
    try:
        done = subprocess.run(
            [str(exe), "-c", "import sys;print('%d.%d.%d' % sys.version_info[:3])"],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return None
    if done.returncode != 0:
        return None
    version = (done.stdout or "").strip().splitlines()
    if not version:
        return None
    parts = version[-1].split(".")
    if len(parts) < 2 or not parts[0].isdigit() or not parts[1].isdigit():
        return None
    pair = (int(parts[0]), int(parts[1]))
    if not (MIN_PY <= pair < MAX_PY):
        return None
    return version[-1]


def pip_install(*args: str) -> list[str]:
    return [str(VENV_PY), "-m", "pip", "install", "--disable-pip-version-check",
            "--no-input", "--progress-bar", "off", *args]


def _venv_is_real() -> bool:
    """确认 venv\\Scripts\\python.exe 真的在用它自己的 site-packages。

    为什么要查：`pyvenv.cfg` 丢失 / Python 被卸载重装之后，venv 里的那个
    python.exe 仍然能跑，但会退化成系统 Python —— 这时 pip 装依赖会直接污染
    系统环境，还查不出原因（依赖"装上了"却 import 不到）。用 prefix 判断一次最稳。
    """
    try:
        done = subprocess.run(
            [str(VENV_PY), "-c", "import sys;print('1' if sys.prefix!=sys.base_prefix else '0')"],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return False
    return done.returncode == 0 and (done.stdout or "").strip().endswith("1")


# =========================================================================== 步骤
def ensure_venv(rebuild: bool = False) -> bool:
    """确保 backend\\venv 存在且可用。"""
    if rebuild and VENV.exists():
        log("  --rebuild-venv：删除旧虚拟环境 %s ..." % VENV)
        shutil.rmtree(VENV, ignore_errors=True)

    try:
        if Path(sys.executable).resolve() == VENV_PY.resolve() and VENV_PY.is_file():
            log("  已运行在项目虚拟环境内，无需创建。")
            return True
    except OSError:
        pass

    if VENV_PY.is_file():
        version = probe_python(VENV_PY)
        if version and _venv_is_real():
            log("  已存在可用的虚拟环境：Python %s" % version)
            return True
        log("  现有虚拟环境无法使用（可能随 Python 升级/重装失效），正在重建 ...")
        shutil.rmtree(VENV, ignore_errors=True)

    log("  正在创建虚拟环境 backend\\venv ...")
    code, _ = run_streaming(
        [sys.executable, "-m", "venv", str(VENV)],
        label="创建虚拟环境", silence_timeout=180,
    )
    if code != 0 or not VENV_PY.is_file():
        log("")
        log("  [ERROR] 虚拟环境创建失败。常见原因：")
        log("          · 磁盘空间不足（项目需要约 6 GB 可用空间）")
        log("          · 杀毒软件拦截了 python.exe 写文件，加入白名单后重试")
        log("          · Python 安装不完整，重新安装 Python 3.12 并勾选 Add to PATH")
        return False
    log("  [OK] 虚拟环境已创建。")
    return True


def deps_fingerprint() -> str:
    digest = hashlib.sha256()
    digest.update(REQUIREMENTS.read_bytes())
    digest.update(("|" + (probe_python(VENV_PY) or "?") + "|" + DEPS_SCHEMA).encode())
    return digest.hexdigest()


def verify_imports() -> tuple[bool, list[str]]:
    """用虚拟环境的 Python 逐个 import 关键依赖。"""
    code, lines = run_streaming(
        [str(VENV_PY), "-c", CHECK_CODE], label="依赖自检", silence_timeout=300,
    )
    missing: list[str] = []
    for line in lines:
        if line.startswith("MISSING="):
            missing = [m for m in line[len("MISSING="):].strip().split(",") if m]
    return (code == 0 and not missing), missing


def install_from_wheelhouse() -> bool | None:
    """有本地 wheelhouse 就离线安装。返回 None 表示没有 wheelhouse。

    这里**先走逐个 wheel 的 --no-deps 安装**，而不是让 pip 做依赖解析。原因实测过：
    wheelhouse 里的 opencv-python-headless 5.0.0.93 元数据写着 `numpy>=2`，
    而同一份 wheelhouse 为了 torch 的兼容固定了 numpy 1.26.4，于是 pip 的解析器
    必然报 `ResolutionImpossible`（这个组合实际可用，cv2 的 cvtColor/resize 都正常，
    已实测）。项目原本的 install_offline.py 一直是这么装的。
    所以：直接按清单装 → 立刻用 import 自检验证 → 缺什么再走在线补齐，
    既不会在正常路径上甩一段吓人的解析失败堆栈，也不会漏装。
    """
    wheels = sorted(WHEELHOUSE.glob("*.whl"))
    if not wheels:
        return None
    total_mb = sum(w.stat().st_size for w in wheels) / 1e6
    log("  发现本地离线依赖包 %d 个（%.0f MB），离线安装中（不联网、最快）..."
        % (len(wheels), total_mb))

    code, _ = run_streaming(
        pip_install("--no-index", "--no-deps", "--find-links", str(WHEELHOUSE),
                    *[str(w) for w in wheels]),
        label="离线依赖安装", silence_timeout=900, quiet=True,
    )
    if code == 0:
        return True

    log("  离线逐个安装失败，改用依赖解析方式再试一次 ...")
    code, _ = run_streaming(
        pip_install("-r", str(REQUIREMENTS), "--no-index", "--find-links", str(WHEELHOUSE)),
        label="离线依赖安装", silence_timeout=900,
    )
    return code == 0


def install_online() -> bool:
    """用国内镜像在线安装；每种源失败或卡死就换下一个，最后用 IPv4 抓包兜底。"""
    log("  先探测各依赖源是否可用（省得在断网的机器上空等）...")
    reachable: list[tuple] = []
    unreachable: list[tuple] = []
    for item in PYPI_MIRRORS:
        name, _url, _trusted, probe_host = item
        ok, reason = _probe_host(probe_host)
        if ok:
            log("    [OK] %s 可用" % name)
            reachable.append(item)
        else:
            log("    [!] %s 不可用 - %s" % (name, reason))
            unreachable.append(item)

    all_dead = not reachable
    if all_dead:
        log("    [!] 四个源全部探测不通。若你走的是代理，仍会试一次；否则这就是网络问题。")
        reachable = list(PYPI_MIRRORS[:1])

    for name, url, host, _probe in reachable:
        log("  使用「%s」源安装依赖 ..." % name)
        args = [
            "-r", str(REQUIREMENTS),
            "--index-url", url,
            "--prefer-binary",
            "--timeout", "30",
            "--retries", "2",
        ]
        if host:
            args += ["--trusted-host", host]
        code, _ = run_streaming(
            pip_install(*args), label="%s 依赖安装" % name,
            # pip 输出到管道时不会打印下载进度条，所以「很久没有输出」在下大包
            # （torch 约 200 MB）时是正常的。实测过一次教训：阈值设 240 秒时，
            # 一个 6 MB/s、正在正常下载的任务被判成卡死掐掉了，于是换源重下 1 GB。
            # 所以这里放到 30 分钟，只当作最后一道保险；真正的网络故障由
            # pip 自己的 --timeout 30、以及装之前的源探测负责兜住。
            silence_timeout=1800, overall_timeout=7200,
        )
        if code == 0:
            log("  [OK] 依赖安装完成（%s 源）。" % name)
            return True
        log("  [!]「%s」源未成功（退出码 %s），换下一个源 ..." % (name, code))

    if all_dead:
        log("  网络整体不可用（DNS 解析或连接就失败了），跳过 IPv4 抓包兜底：")
        log("  它同样需要联网，硬跑只会再多等十几分钟。")
        return False

    log("  所有在线源都失败了，改用 IPv4 强制下载脚本 fetch_wheels.py ...")
    if not FETCH_WHEELS.is_file():
        return False
    code, _ = run_streaming([str(VENV_PY), str(FETCH_WHEELS)],
                            label="依赖包下载", silence_timeout=300, overall_timeout=5400,
                            abort_when=_fetcher_hopeless)
    if code != 0:
        return False
    return bool(install_from_wheelhouse())


def install_and_verify() -> tuple[bool, list[str]]:
    """先离线后在线地装依赖，每一步都用 import 自检确认，失败自动升级到下一方案。"""
    offline = install_from_wheelhouse()
    if offline is not None:
        if offline is True:
            ok, missing = verify_imports()
            if ok:
                return True, []
            log("  [!] 离线安装完成，但自检仍缺少：%s" % (", ".join(missing) or "未知"))
        log("  转为在线安装 ...")

    if install_online():
        return verify_imports()
    return False, []


def ensure_deps(force: bool = False) -> bool:
    """确保依赖装齐。装了就不再重复装，requirements.txt 变了会自动重装。"""
    fingerprint = deps_fingerprint()

    if not force and DEPS_MARK.is_file():
        try:
            if DEPS_MARK.read_text(encoding="utf-8").strip() == fingerprint:
                log("  依赖已就绪且与 requirements.txt 一致，跳过安装。")
                ok, _ = verify_imports()
                if ok:
                    return True
                log("  [!] 依赖自检未通过，重新安装 ...")
            else:
                log("  requirements.txt 有变化，重新安装依赖 ...")
        except OSError:
            pass

    log("  开始安装依赖。这一步最耗时间：约 1-2 GB，视网速 5-30 分钟。")
    log("  中途会打印下载日志，长时间没有输出会自动换下一个源，请不要关闭窗口。")

    ok, missing = install_and_verify()
    if not ok or missing:
        log("")
        log("  [ERROR] 依赖安装失败，缺少：%s" % (", ".join(missing) or "未知"))
        log("          可以这样排查：")
        log("          1) 确认能上网（浏览器能打开 https://mirrors.aliyun.com）")
        log("          2) 关掉代理 / VPN 再试一次")
        log("          3) 若在完全离线的内网，请在能联网的 Windows 电脑上运行")
        log("             backend\\fetch_wheels.py，把生成的 wheelhouse 目录一起拷过来")
        log("          4) 仍然失败请把 backend\\bootstrap.log 发给开发者")
        return False

    try:
        DEPS_MARK.write_text(fingerprint + "\n", encoding="utf-8")
    except OSError:
        pass

    # 首次装完做一次深度自检：验证模型权重能否真正加载并推理
    if MODEL_CKPT.is_file():
        verify_env = BACKEND / "_verify_env.py"
        if verify_env.is_file():
            log("")
            log("  正在做深度自检（加载模型权重并试算一次，约 10-60 秒）...")
            run_streaming([str(VENV_PY), str(verify_env)], label="模型自检",
                          silence_timeout=600)
    return True


def ensure_env_file() -> None:
    """缺少 .env 时从 .env.example 复制一份，保证配置项齐全。"""
    if ENV_FILE.is_file():
        return
    if ENV_EXAMPLE.is_file():
        try:
            shutil.copyfile(ENV_EXAMPLE, ENV_FILE)
            log("  已从 .env.example 生成 .env（云端大模型相关密钥留空即可，不影响本地评分）。")
        except OSError as exc:
            log("  [!] 生成 .env 失败：%s" % exc)


def check_model_assets(warnings: list[str]) -> None:
    if MODEL_CKPT.is_file():
        log("  [OK] 模型权重 best.pt 就绪（%.1f MB）。" % (MODEL_CKPT.stat().st_size / 1e6))
    else:
        warnings.append(
            "缺少模型权重 backend\\best.pt（该文件已随项目提交，缺失说明包不完整，"
            "请重新完整下载项目）。系统仍可启动，但视频/图像分析功能不可用。"
        )

    missing_src = [str(p.relative_to(DASHBOARD)) for p in (MODEL_SRC, MODEL_SRC_BACKEND)
                   if not p.is_file()]
    if not missing_src:
        log("  [OK] 模型结构 LMTformer_model 就绪（两份齐全）。")
    else:
        warnings.append(
            "缺少模型结构 %s（该目录已随项目提交，缺失说明包不完整）。"
            "系统仍可启动，但分析功能不可用。" % "、".join(missing_src)
        )


def _run_npm(args: list[str]) -> tuple[int, list[str]]:
    if os.name == "nt":
        return run_streaming(["cmd", "/c", "npm", *args], label="前端构建", silence_timeout=300)
    return run_streaming(["npm", *args], label="前端构建", silence_timeout=300)


def ensure_frontend(warnings: list[str]) -> None:
    """前端页面 dist/index.html 由仓库直接提供；万一缺失，有 Node 就自动构建。"""
    if DIST_INDEX.is_file():
        log("  [OK] 前端页面 dashboard\\dist 就绪。")
        return

    log("  [!] 缺少前端页面 dashboard\\dist\\index.html，尝试自动构建 ...")
    npm = shutil.which("npm")
    if npm and (DASHBOARD / "package.json").is_file():
        code, _ = _run_npm(["install", "--no-audit", "--no-fund"])
        if code == 0:
            code, _ = _run_npm(["run", "build"])
        if code != 0 or not DIST_INDEX.is_file():
            # `npm run build` 会先跑 vue-tsc 类型检查；仓库里存在历史类型错误时它会失败，
            # 但这些问题不影响运行。退回直接调 vite 构建（跳过类型检查）把页面出出来。
            log("  [!] npm run build 未成功（通常是历史类型检查报错），改用 vite 直接构建 ...")
            code, _ = _run_npm(["exec", "--", "vite", "build"])
        if code == 0 and DIST_INDEX.is_file():
            log("  [OK] 前端构建完成。")
            return
    warnings.append(
        "前端页面缺失（dashboard\\dist\\index.html）。服务仍会启动，接口可用，"
        "但浏览器打开是 404。请在联网电脑上于 dashboard 目录执行 npm install && npm run build，"
        "再把 dist 目录拷过来。"
    )


# =========================================================================== 启动
def port_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(1.0)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def already_serving(port: int) -> bool:
    """端口上是不是已经跑着本项目（用 /health 判断，避免误判别的程序）。"""
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=2) as resp:
            return resp.status == 200 and b"ok" in resp.read(200)
    except Exception:
        return False


def local_ipv4_addresses() -> list[str]:
    found: list[str] = []
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            found.append(sock.getsockname()[0])
    except Exception:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = info[4][0]
            if address not in found and not address.startswith("127."):
                found.append(address)
    except Exception:
        pass
    return found


def pick_port(preferred: int) -> int:
    if not port_open(preferred):
        return preferred
    for candidate in range(preferred + 1, preferred + 21):
        if not port_open(candidate):
            log("  [!] 端口 %d 被其它程序占用，改用 %d。" % (preferred, candidate))
            return candidate
    log("  [!] 端口 %d - %d 都被占用，仍尝试用 %d（可能启动失败）。"
        % (preferred, preferred + 20, preferred))
    return preferred


def _open_browser_when_ready(proc: subprocess.Popen, port: int, url: str,
                            stop: threading.Event) -> None:
    deadline = time.time() + 180
    while time.time() < deadline and not stop.is_set():
        if proc.poll() is not None:
            log("  [!] 服务进程已退出，未能自动打开浏览器（请看上方报错）。")
            return
        if already_serving(port):
            time.sleep(0.5)
            log("  [OK] 服务已就绪，正在打开浏览器：%s" % url)
            try:
                if hasattr(os, "startfile"):
                    os.startfile(url)                       # type: ignore[attr-defined]
                else:
                    import webbrowser
                    webbrowser.open(url)
            except Exception as exc:
                log("  [!] 自动打开浏览器失败（%s），请手动访问 %s" % (exc, url))
            return
        time.sleep(1.0)
    log("  [!] 等待服务就绪超时。若窗口里没有报错，请手动打开：%s" % url)


def run_server(args) -> int:
    host = os.environ.get("HOST", "127.0.0.1")
    try:
        preferred = int(args.port or os.environ.get("PORT", DEFAULT_PORT))
    except ValueError:
        preferred = DEFAULT_PORT

    log("")
    log("==> [5/5] 启动服务")

    if already_serving(preferred):
        url = "http://127.0.0.1:%d" % preferred
        log("  [OK] 检测到服务已经在运行：%s" % url)
        log("       如需重启，请先关闭原来那个黑色窗口。")
        if not args.no_browser:
            try:
                if hasattr(os, "startfile"):
                    os.startfile(url)                       # type: ignore[attr-defined]
                else:
                    import webbrowser
                    webbrowser.open(url)
            except Exception:
                pass
        return 0

    port = pick_port(preferred)
    url = "http://127.0.0.1:%d" % port

    if not SERVE_ALL.is_file():
        log("  [ERROR] 找不到启动入口 backend\\serve_all.py，项目文件不完整。")
        return 1

    env = child_env({"PORT": str(port), "HOST": host})
    log("  服务地址：%s" % url)
    if host not in ("127.0.0.1", "localhost"):
        for address in local_ipv4_addresses():
            log("  局域网内其它设备可用：http://%s:%d" % (address, port))
        log("  [!] 局域网共享模式会把界面开放给同网段设备，用完请关闭本窗口。")
    log("  这个窗口就是服务本体，关闭它服务即停止。首次启动加载模型需要 10-60 秒。")
    log("")

    proc = subprocess.Popen([str(VENV_PY), str(SERVE_ALL)], cwd=str(BACKEND), env=env)
    stop = threading.Event()
    if not args.no_browser:
        threading.Thread(target=_open_browser_when_ready,
                         args=(proc, port, url, stop), daemon=True).start()

    try:
        code = proc.wait()
    except KeyboardInterrupt:
        log("")
        log("  收到中断，正在停止服务 ...")
        _kill(proc)
        code = 0
    finally:
        stop.set()

    if code == 0:
        log("")
        log("  服务已停止。")
    else:
        log("")
        log("  [!] 服务退出，退出码 %s。常见原因：" % code)
        log("      · 端口被占用（本脚本一般会自动换端口，除非手动指定了 --port）")
        log("      · 依赖或模型文件被改动，重新双击启动脚本即可自动修复")
        log("      详细报错见上方输出与 %s" % LOG_FILE)
    return code


# =========================================================================== 入口
def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="MindScope 一键启动引导：自动建虚拟环境、自动装依赖、自动启动服务",
        add_help=True,
    )
    parser.add_argument("--check", action="store_true",
                        help="只做环境检查与依赖自检，不启动服务")
    parser.add_argument("--no-browser", action="store_true",
                        default=os.environ.get("MINDSCOPE_NO_BROWSER", "") not in ("", "0"),
                        help="启动后不自动打开浏览器（也可设环境变量 MINDSCOPE_NO_BROWSER=1）")
    parser.add_argument("--force-deps", action="store_true",
                        help="忽略依赖就绪标记，强制重新安装依赖")
    parser.add_argument("--rebuild-venv", action="store_true",
                        help="删除并重建虚拟环境")
    parser.add_argument("--port", default=None, help="指定服务端口，默认 8000")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    _prepare_console()
    _banner()

    warnings: list[str] = []

    # ---------------------------------------------------------------- [1/5]
    log("==> [1/5] 环境检查")
    current = sys.version_info[:2]
    log("  Python: %s   (%s)" % (sys.version.split()[0], sys.executable))
    log("  项目目录: %s" % DASHBOARD)
    if not (MIN_PY <= current < MAX_PY):
        warnings.append(
            "当前 Python %s 不在推荐范围 3.10 - 3.13 内。依赖包按 3.12 编译，"
            "建议安装 Python 3.12 后重新双击启动脚本（脚本会自动优先使用 3.12）。"
            % sys.version.split()[0]
        )
    if not REQUIREMENTS.is_file():
        log("  [ERROR] 找不到 %s，项目文件不完整，无法继续。" % REQUIREMENTS)
        return 1
    log("  [OK] 项目文件基本齐全。")

    # ---------------------------------------------------------------- [2/5]
    log("")
    log("==> [2/5] 准备虚拟环境")
    if not ensure_venv(args.rebuild_venv):
        return 1

    # ---------------------------------------------------------------- [3/5]
    log("")
    log("==> [3/5] 准备 Python 依赖")
    if not ensure_deps(args.force_deps):
        return 1

    # ---------------------------------------------------------------- [4/5]
    log("")
    log("==> [4/5] 检查项目文件")
    ensure_env_file()
    check_model_assets(warnings)
    ensure_frontend(warnings)

    if warnings:
        log("")
        log("  提示（不影响启动，但功能可能不完整）：")
        for item in warnings:
            log("    [!] %s" % item)

    if args.check:
        log("")
        log("  [OK] 自检完成，环境可以启动。去掉 --check 即可启动服务。")
        return 0

    # ---------------------------------------------------------------- [5/5]
    return run_server(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        log("")
        log("  已取消。")
        sys.exit(130)
