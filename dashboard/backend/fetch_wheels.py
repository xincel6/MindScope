# -*- coding: utf-8 -*-
"""
绕开 pip 网络层，直接用 urllib 从 PyPI 镜像抓取 wheel。

为什么需要这个脚本
------------------
本机 pip 23.2.1 在索引解析阶段会长时间占用 CPU 却毫无产出（实测：连
`pip download pip` 都会卡到 296 秒 CPU 时间），urllib 的请求也会间歇性挂起。
根因是本机 Python 网络栈在这一环境下的地址选择行为（DNS 只返回 IPv4，
IPv6 直连直接 gaierror，而 Python 不会像 curl 那样快速回退），并非网络不通。

对策
----
1. 强制 getaddrinfo 只返回 IPv4；
2. 自行抓取 wheel（不依赖 pip 的索引解析）；
3. 最后用 `pip install --no-index --find-links wheelhouse` 做纯离线安装。

用法
----
    python fetch_wheels.py              # 抓取全部
    python fetch_wheels.py httpx h11    # 只抓指定包（先做小样验证）
"""
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# 关键修复：强制只用 IPv4（必须在任何网络请求之前生效）
# ---------------------------------------------------------------------------
_orig_getaddrinfo = socket.getaddrinfo


def _v4_only(host, port, family=0, type=0, proto=0, flags=0):
    return _orig_getaddrinfo(host, port, socket.AF_INET, type, proto, flags)


socket.getaddrinfo = _v4_only

DEST = Path(__file__).resolve().parent / "wheelhouse"
DEST.mkdir(parents=True, exist_ok=True)

MIRRORS = [
    "https://mirrors.aliyun.com/pypi/simple/",
    "https://pypi.org/simple/",
]

# 已确认的传递依赖闭包（含 torch / facenet-pytorch 的依赖）
PACKAGES = [
    "fastapi", "starlette", "uvicorn", "sqlalchemy", "aiosqlite",
    "python-multipart", "aiofiles", "httpx", "httpcore", "h11", "anyio",
    "sniffio", "idna", "certifi", "typing-extensions", "websockets",
    "watchfiles", "httptools", "python-dotenv", "pyyaml", "colorama",
    "click", "numpy", "pillow", "opencv-python-headless", "python-jose",
    "ecdsa", "rsa", "pyasn1", "cryptography", "cffi", "pycparser",
    "bcrypt", "pydantic", "pydantic-core", "annotated-types", "greenlet",
    "mako", "markupsafe", "einops", "torch", "facenet-pytorch",
    "filelock", "sympy", "mpmath", "networkx", "jinja2", "fsspec",
]

# 本机（CPython 3.12 / Windows x64）可接受的 PEP 425 标签
PY_TAGS = {"py3", "cp312", "cp312t", "py2.py3", "py310", "py311", "py312"}
PLAT_TAGS = {"any", "win_amd64", "win32"}
# 平台优先级：win_amd64 必须优于 win32 与 any。
# 若只按版本号排序，同版本下 win_amd64 与 win32 会并列，导致误选 32 位 wheel
# （numpy/pillow 走 32 位会显著拖慢推理，torch 更是根本没有 win32 版本）。
PLAT_RANK = {"win_amd64": 3, "win32": 2, "any": 1}
# 关键包的最低版本（对应 requirements.txt / 源码实际用法），防止挑到过旧大版本
MIN_VER = {
    "fastapi": "0.115",
    "pydantic": "2.0",
    "pydantic-core": "2.0",
    "sqlalchemy": "2.0",
    "uvicorn": "0.30",
    "starlette": "0.37",
    "numpy": "1.26",
    "python-jose": "3.3",
    "aiofiles": "24.0",
}
# abi3 = stable ABI，cp37/cp39 等标注的 abi3 wheel 在 CPython 3.12 上同样可用
ABI3_MIN = {"cp36": 36, "cp37": 37, "cp38": 38, "cp39": 39, "cp310": 310,
            "cp311": 311, "cp312": 312}
UA = "Mozilla/5.0 (compatible; wheel-fetcher)"
_ctx = ssl.create_default_context()


def log(msg):
    """显式 UTF-8 输出，避免 GBK 控制台乱码。"""
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()


def get(url, tries=4, timeout=45):
    """带指数退避重试的 GET；HTTP 4xx 视为确定性失败，不重试。"""
    delay = 1.0
    last = None
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout, context=_ctx) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if 400 <= e.code < 500:
                raise
            last = e
        except Exception as e:  # noqa: BLE001
            last = e
        if attempt < tries - 1:
            time.sleep(delay)
            delay *= 2
    raise last


def parse_wheel(name):
    """
    解析 wheel 文件名 -> dict(py, abi, plat, ver) 或 None。
    格式: <dist>-<ver>([-<build>])?-<pytag>-<abitag>-<plat>.whl
    （dist / ver 中的连字符在文件名里写作下划线，故只有后 3 段是 tag）
    """
    if not name.endswith(".whl"):
        return None
    stem = name[:-4]
    head, _, plat = stem.rpartition("-")
    head, _, abi = head.rpartition("-")
    distver, _, pytag = head.rpartition("-")
    _, _, ver = distver.partition("-")
    return {"py": pytag, "abi": abi, "plat": plat, "ver": ver,
            "py_set": set(pytag.split("."))}


def compatible(info, pkg):
    """PEP 425 兼容性 + 版本约束。"""
    if not info:
        return False
    py_ok = bool(info["py_set"] & PY_TAGS)
    if not py_ok and info["abi"] == "abi3":
        need = ABI3_MIN.get(info["py"])
        py_ok = need is not None and need <= 312
    if not py_ok:
        return False
    if info["plat"] not in PLAT_TAGS:
        return False
    v = info["ver"]
    if re.search(r"(a|b|rc|dev|post)\d*$", v):        # 排除预发布
        return False
    if pkg == "numpy":
        # 钉住 1.26.x：numpy 2.x 会破坏部分 opencv / torch 组合
        if not v.startswith("1.26."):
            return False
    # 最低版本约束
    floor = MIN_VER.get(pkg)
    if floor and ver_key(v) < ver_key(floor):
        return False
    return True


def ver_key(ver):
    """
    版本号转成定长元组（仅用于挑最新）。

    注意：必须补齐到固定长度再截断。若直接 `tuple(...)[:6]`，当两个版本号
    段数不同时（如 "1.10.26" -> 6 段 与 "2.13.4" -> 7 段），Python 会先比较
    共同前缀再比较长度，反而得出 (1,10,26,0,0,0) > (2,13,4,0,0,0,0) 的错误结果。
    """
    out = []
    for part in re.split(r"[._\-+]", ver):
        m = re.match(r"^(\d+)", part)
        if m:
            out.append(int(m.group(1)))
        elif part:
            out.append(0)
    # 先统一补齐到 6 段，再截断，保证任何版本号都返回等长元组
    padded = (out + [0] * 6)[:6]
    return tuple(padded)


def index_map(pkg, mirror):
    """一次请求拿到 {wheel 文件名: 绝对 URL}，避免重复下载索引页。"""
    text = get(mirror + pkg + "/").decode("utf-8", "replace")
    base = mirror.rsplit("/simple/", 1)[0]
    out = {}
    for h in re.findall(r'href="([^"#]+)', text):
        fn = urllib.parse.unquote(h.rsplit("/", 1)[-1])
        if fn.endswith(".whl"):
            out[fn] = h if h.startswith("http") else base + h
    return out


def fetch_one(pkg):
    """返回 ('ok'|'skip'|'fail', 说明)。"""
    already = (list(DEST.glob(pkg + "-*.whl"))
               + list(DEST.glob(pkg.replace("-", "_") + "-*.whl")))
    if already:
        return "skip", already[0].name

    errors = []
    for mirror in MIRRORS:
        host = mirror.split("/")[2]
        try:
            files = index_map(pkg, mirror)
        except Exception as e:  # noqa: BLE001
            errors.append(f"{host}: {type(e).__name__} {e}")
            continue

        best, best_key = None, None
        for fn, url in files.items():
            info = parse_wheel(fn)
            if not compatible(info, pkg):
                continue
            # 版本号优先，平台优先级仅用于同版本的决胜。
            # 反例：若平台优先，pydantic-1.10.26-win_amd64（rank 3）会击败
            # pydantic-2.9.2-py3-none-any（rank 1），装出错误的 1.x 版本。
            key = (ver_key(info["ver"]), PLAT_RANK[info["plat"]])
            if best_key is None or key > best_key:
                best, best_key = (fn, url), key
        if not best:
            errors.append(f"{host}: 无适配 cp312/win_amd64 的 wheel（共 {len(files)} 个文件）")
            continue

        fn, url = best
        try:
            data = get(url, timeout=120)
            (DEST / fn).write_bytes(data)
            return "ok", f"{fn}  {len(data)/1e6:.1f} MB"
        except Exception as e:  # noqa: BLE001
            errors.append(f"{host}: 下载失败 {type(e).__name__} {e}")
            continue

    return "fail", " | ".join(errors)


def main():
    targets = sys.argv[1:] or PACKAGES
    t_start = time.time()
    counts = {"ok": 0, "skip": 0, "fail": 0}
    failed = []

    for pkg in targets:
        t0 = time.time()
        status, detail = fetch_one(pkg)
        counts[status] += 1
        mark = {"ok": "OK  ", "skip": "SKIP", "fail": "FAIL"}[status]
        log(f"  {mark}  {pkg:24s} {detail}   [{time.time()-t0:.1f}s]")
        if status == "fail":
            failed.append(pkg)

    wheels = list(DEST.glob("*.whl"))
    total = sum(f.stat().st_size for f in wheels)
    log("-" * 92)
    log(f"完成: 新下载 {counts['ok']}  已存在 {counts['skip']}  失败 {counts['fail']}"
        f"   总耗时 {time.time()-t_start:.0f}s")
    log(f"wheelhouse: {len(wheels)} 个 wheel, {total/1e6:.1f} MB")
    if failed:
        log("失败清单: " + ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
