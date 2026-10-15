# Windows 部署与复现指南

> 面向：拿到项目包、电脑上**什么都没装**的 Windows 用户。
> 结论先给：**双击 `dashboard\启动-仅本机.bat` 就行了。** 没有 Python 它会自己装，
> 没有依赖它会自己装，装完自动启动并自动打开浏览器。

---

## 0. 一键启动（当前推荐，也是唯一需要做的事）

在 `dashboard` 目录下双击：

| 文件 | 用途 | 访问地址 |
|---|---|---|
| `启动-仅本机.bat` | **日常使用，推荐**。只有这台电脑能访问 | `http://127.0.0.1:8000` |
| `启动-局域网共享.bat` | 演示用。同 WiFi 的手机 / 平板 / 其它电脑也能访问 | `http://本机IP:8000`（窗口里会打印） |

### 双击之后脚本自动做了什么

```
[1/5] 环境检查      报告 Python 版本与项目路径
[2/5] 虚拟环境      没有 backend\venv 就自动 python -m venv 建一个
[3/5] 依赖安装      自动安装 requirements.txt（第一次约 1-2 GB）
[4/5] 项目文件      .env / 模型权重 / 前端 dist 的检查与补齐
[5/5] 启动服务      自动选端口 -> 启动 -> 端口就绪后自动打开浏览器
```

**第一次运行**：因为要下载约 1-2 GB 依赖（含 torch），视网速大概 **5-30 分钟**，
窗口里会一直打印进度，**不要关窗口**。装了之后再启动只要 **10-60 秒**。

### 启动前请确认三件事

| 项目 | 要求 | 说明 |
|---|---|---|
| 操作系统 | Windows 10 / 11 64 位 | 依赖轮子里只有 `win_amd64` 版本 |
| 磁盘空间 | **≥ 6 GB 可用** | 其中 torch 单独占约 1 GB |
| 网络 | **第一次需要联网** | 之后可完全离线运行 |

**Python 不用自己装。** 脚本会按这个顺序找一个可用的：

1. 官方的 `py` 启动器（优先 3.12，其次 3.11 / 3.10 / 3.13）
2. `PATH` 里的 `python` / `python3`
3. 常见安装位置（`%LOCALAPPDATA%\Programs\Python\Python3xx`、Anaconda、`C:\Python3xx` …）
4. 都找不到时，**自动安装 Python 3.12.10**：先试 `winget`，
   失败则从国内镜像下载官方安装包静默安装

### 装依赖的顺序（脚本内部会自己挑，不用你管）

1. **本地离线包**：如果 `backend\wheelhouse` 目录存在（57 个 wheel，约 206 MB），
   直接离线装，最快最稳，完全不联网
2. **国内镜像在线装**：阿里云 → 清华 → 腾讯云 → PyPI 官方，逐个换源重试。
   某个源卡住超过 4 分钟没有输出，会被判定为卡死并自动中断换下一个源
3. **IPv4 强制抓包兜底**：所有源都失败时，调用 `backend\fetch_wheels.py`
   （它绕开 pip 的网络层，强制只走 IPv4）把包装下来，再离线安装

装完立刻用 `import` 自检 21 个关键依赖（含 `greenlet`、`sqlalchemy.ext.asyncio`
这类「缺了会让服务启动直接崩」的项目），并加载一次模型权重确认可用；
自检没过会自动回到第 2 步换源重装。

### 停止 / 重启

- **这个黑窗口就是服务本体**，关掉窗口 = 停止服务，浏览器随即打不开
- 想换端口：先 `set PORT=8001` 再双击，或者 `--port 8001`
- 再次双击时如果服务已经在跑，脚本**不会重复启动**，只会把浏览器再打开一次

### 出问题时

| 现象 | 处理 |
|---|---|
| 窗口里报错、或想看得更细 | 看 `backend\bootstrap.log`，全部输出都在里面 |
| 依赖装到一半失败了 | 直接重新双击；已装的包会跳过，从断点继续 |
| 怀疑环境装坏了 | 删除 `backend\venv` 目录后重新双击（会干净重装） |
| 页面上"分析"功能报错 | 多半是缺模型权重，见第 4 节末尾与第 7 节 |
| 完全离线的内网电脑 | 在能联网的 Windows 上跑一次 `backend\fetch_wheels.py`，把 `wheelhouse` 目录一起拷过去，再双击 bat |

### 给排错/自动化用的参数

`backend\bootstrap.py` 可以直接带参数运行（一般用不到）：

```bat
backend\venv\Scripts\python.exe backend\bootstrap.py --check         :: 只体检，不启动
backend\venv\Scripts\python.exe backend\bootstrap.py --force-deps    :: 强制重装依赖
backend\venv\Scripts\python.exe backend\bootstrap.py --rebuild-venv  :: 删掉重建虚拟环境
backend\venv\Scripts\python.exe backend\bootstrap.py --port 8001     :: 换端口
backend\venv\Scripts\python.exe backend\bootstrap.py --no-browser    :: 不自动开浏览器
```

> `--check` 是做演示前最值得跑的一条：它会把依赖、模型权重、前端产物一次性体检完，
> 结尾看到 `[OK] 自检完成，环境可以启动。` 就可以放心上台。

---

## 0.1 历史说明：为什么以前的脚本会失败

如果你拿到的是**旧包**，双击会直接报：

```
系统找不到指定的路径。
请按任意键继续. . .
```

原因是旧脚本第 10 行写死了作者电脑上的绝对路径：

```bat
"C:\anaconda3\python.exe" serve_all.py
```

你电脑上几乎不可能正好也是这个路径，于是 cmd 直接抛错。
**这句报错跟你的操作无关，也不是项目坏了**；`请按任意键继续` 来自脚本末尾的 `pause`。

旧流程一共四道坎，现在全部由一键脚本自动处理了：

| # | 问题 | 旧症状 | 现在怎么办 |
|---|---|---|---|
| 1 | 脚本写死了别人的 Python 路径 | `系统找不到指定的路径。` | 脚本改用 `%~dp0` 相对路径 + 自动探测，见 `_ensure_python.bat` |
| 2 | 电脑上根本没有 Python | 同上，或 `python 不是内部或外部命令` | 自动装 Python 3.12.10 |
| 3 | 依赖一个都没装 | `ModuleNotFoundError: No module named 'fastapi'` | 自动装依赖并自检 |
| 4 | **pip 安装时卡死**（本机网络栈问题） | 卡住不动、CPU 满载却零输出 | 4 分钟无输出即中断换源，最后用 IPv4 强制抓包兜底 |

下面的第 1-9 节是**手动部署 / 深度排错**的完整参考。一键脚本正常工作的话，
你不需要看它们；脚本失败或想弄清原理时，按需查阅。

---

## 1. 前置条件

| 项目 | 要求 | 说明 |
|---|---|---|
| 操作系统 | Windows 10 / 11 64 位 | 本项目依赖包里只有 `win_amd64` 版本 |
| Python | **3.12**（务必 3.10–3.12） | 依赖包是编译好的二进制，版本必须匹配，见下方说明 |
| 磁盘空间 | **≥ 6 GB** | 其中 torch 单独占约 1 GB |
| 内存 | ≥ 4 GB | 模型运行时约占 600 MB |
| 网络 | 首次安装需要 | 之后可完全离线运行 |

**为什么 Python 版本必须卡准？**

Python 的第三方包（`numpy`、`torch`、`opencv` 等）不是纯文本，而是**针对特定 Python 版本编译**的二进制文件。文件名里 `cp312` 就表示"Python 3.12 专用"。装错版本会看到：

```
ERROR: Could not find a version that satisfies the requirement torch
```

所以本指南统一按 **Python 3.12** 走。安装时请务必勾选 **Add Python to PATH**。

---

## 2. 安装 Python

1. 打开 <https://www.python.org/downloads/release/python-3120/>
2. 下载 **Windows installer (64-bit)**
3. 运行安装包，**必须勾选** `Add python.exe to PATH`（在安装界面最底部，很容易漏）
4. 安装完成后验证 —— 按 `Win + R`，输入 `cmd`，回车，然后输入：

```bat
python --version
```

看到 `Python 3.12.x` 就成功了。

> **如果提示"不是内部或外部命令"**：说明第 3 步的勾没打上。重新运行安装包，选 `Modify` → 补勾 PATH，或者直接卸载重装。

**验证 pip 也能用：**

```bat
python -m pip --version
```

---

## 3. 修正启动脚本（本项目已内置完成，无需再改）

> **现状说明**：仓库里的 `启动-仅本机.bat` / `启动-局域网共享.bat` 已经是一键版本，
> 它们只负责「找 Python」然后交给 `backend\bootstrap.py` 做剩下的事。
> **你不需要再按本节手动替换任何脚本**，本节仅作为「拿到旧包」或想理解原理时的参考。

进入项目目录，路径大致是：

```
...\系统代码\
```

你会看到这两个文件：

- `启动-仅本机.bat` —— 只有自己电脑能访问（安全，默认用这个）
- `启动-局域网共享.bat` —— 同一 WiFi 下别人也能访问

### 旧包的问题与现在的做法

旧脚本里写死了作者的 Python 绝对路径，现在改成了「相对路径 + 自动探测」：

```bat
cd /d "%~dp0backend"        :: 定位到脚本旁边的 backend，路径里有中文/空格都不受影响
call "_ensure_python.bat"   :: 自动找 Python；找不到就自动装 Python 3.12.10
"%PY_EXE%" %PY_ARGS% "bootstrap.py"   :: 剩下的（建环境、装依赖、启动、开浏览器）交给它
```

`_ensure_python.bat` 会依次尝试：`py -3.12` → `py -3.11` → `py -3.10` → `py -3.13`
→ `py -3` → `PATH` 里的 `python` / `python3` → 常见安装目录（含 Anaconda）；
全部失败才走 `winget` 或从镜像下载官方安装包静默安装。

下面保留旧版脚本内容，**仅供对照历史问题**（旧包的写法与失败原因）。

### 改法（旧包参考）：整份替换

用记事本打开，**把内容全部删掉**，粘贴下面这份，保存。

**`启动-仅本机.bat`**（旧版写法，仅作对照）

```bat
@echo off
cd /d "%~dp0backend"
set KMP_DUPLICATE_LIB_OK=TRUE
echo ==============================================
echo  Depression System - LOCAL ONLY (safe mode)
echo  Open http://127.0.0.1:8000 on THIS computer
echo ==============================================
if not exist "venv\Scripts\python.exe" goto NOPY
"venv\Scripts\python.exe" serve_all.py
pause
exit /b 0

:NOPY
echo  [ERROR] Python environment not found: backend\venv\Scripts\python.exe
echo  Please finish Section 4 of the deployment guide first.
pause
exit /b 1
```

**`启动-局域网共享.bat`**

```bat
@echo off
cd /d "%~dp0backend"
set KMP_DUPLICATE_LIB_OK=TRUE
set HOST=0.0.0.0
echo ==================================================
echo  Depression System - LAN SHARING (temporary)
echo  Other devices open: http://YOUR_IP:8000
echo  Close this window to STOP external access
echo ==================================================
if not exist "venv\Scripts\python.exe" goto NOPY
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
  for /f "tokens=* delims= " %%b in ("%%a") do echo  This machine IP: %%b
)
echo ==================================================
"venv\Scripts\python.exe" serve_all.py
pause
exit /b 0

:NOPY
echo  [ERROR] Python environment not found: backend\venv\Scripts\python.exe
echo  Please finish Section 4 of the deployment guide first.
pause
exit /b 1
```

### 改动的三处关键点（理解即可，不必自己改）

1. **`"venv\Scripts\python.exe"` 取代了 `"C:\anaconda3\python.exe"`**
   改用项目自己的虚拟环境，不再依赖你电脑上 Python 装在哪。这就是 `%~dp0`（脚本所在目录）配合 `cd /d` 的作用 —— **先切到 backend 目录，再用相对路径调 Python**，路径里有多少中文、多少空格都不影响。

2. **加了 `if not exist ... goto NOPY` 自检**
   以后若环境没装好，它会明确告诉你"环境没准备好，去看第 4 节"，而不是又丢一句让人摸不着头脑的 `系统找不到指定的路径`。

3. **保留 `KMP_DUPLICATE_LIB_OK=TRUE`**
   原作者写的，**不要删**。torch 和 opencv 会各自加载一份 OpenMP 运行库，不加这个变量会直接崩溃退出。

> **局域网共享脚本注意**：它设置 `HOST=0.0.0.0`，会让**同一局域网内任何设备**都能访问，也会把人脸数据暴露出去。演示完记得关掉那个黑窗口 —— 它就是唯一的开关。

---

## 4. 安装项目依赖（最关键的一节）

> **一键版**：双击 `启动-仅本机.bat` 会自动完成本节全部内容
> （建虚拟环境 → 装依赖 → 自检 → 报告缺什么）。本节留给想手动装、
> 或自动安装失败需要手工排错的情况。

依赖有 13 个核心包（含 torch），总计约 1 GB。这一步最容易失败。

### 4.0 先建虚拟环境

虚拟环境 = 给这个项目单独一间"房间"，不和系统里其他 Python 项目互相干扰。

打开 `cmd`，切到 **backend** 目录（注意是 backend，不是项目根目录）：

```bat
cd /d "路径\系统代码\backend"
```

然后建环境并激活：

```bat
python -m venv venv
venv\Scripts\activate
```

激活成功后，命令行开头会出现 `(venv)` 字样。**后面所有命令都在这个状态下执行。**

> 看到 `(venv)` 很重要。没有它就会装到系统 Python 里，容易污染别的项目。

---

### 4.1 方案 A（推荐）：先用 `pip` 试一次

```bat
pip install -r requirements.txt
```

- **顺利装完** → 跳到第 5 节验证。
- **卡住不动**（几分钟以上没反应、CPU 却跑满）→ **别等，按 `Ctrl + C` 中断**，走方案 B。

> 顺手加个国内镜像会快很多：
> ```bat
> pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
> ```

---

### 4.2 方案 B：pip 卡死时的绕行方案（重要）

**卡死的表现**：`pip` 停在 `Looking in indexes:` 之后就不动了，几十秒到几分钟零输出，任务管理器里 Python 进程 CPU 却占满一个核。实测有一次连续空转了 **296 秒**仍无任何产出。

**原因**：不是网络不通（同一台机器用 `curl` 访问同一个镜像站，下载完全正常），而是**本机 Python 网络栈的地址选择行为**：DNS 只返回 IPv4 地址、IPv6 直连直接失败报 `gaierror`，而 Python 不像 `curl` 那样会快速回退到 IPv4，于是长时间挂起。这是环境问题，**不是项目的问题**。

**绕行思路**：绕开 pip 的"边查索引边解析依赖"环节，改成
① 自己把 wheel 文件抓下来 → ② 用 pip 做**纯离线**安装（查本地文件，不走网络）。

#### 第 1 步：保存这个抓取脚本

在 **backend** 目录下新建文件 `fetch_wheels.py`，内容如下（**完整复制**）：

```python
# -*- coding: utf-8 -*-
"""
绕开 pip 网络层，直接抓取 wheel 依赖包。
用法:
    python fetch_wheels.py            # 抓取全部
    python fetch_wheels.py torch      # 只抓指定包
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

# 关键修复：强制只用 IPv4（必须在任何网络请求之前生效）
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

PACKAGES = [
    "fastapi", "starlette", "uvicorn", "sqlalchemy", "aiosqlite",
    "python-multipart", "aiofiles", "httpx", "httpcore", "h11", "anyio",
    "sniffio", "idna", "certifi", "typing-extensions", "websockets",
    "watchfiles", "httptools", "python-dotenv", "pyyaml", "colorama",
    "click", "numpy", "pillow", "opencv-python-headless", "python-jose",
    "ecdsa", "rsa", "pyasn1", "cryptography", "cffi", "pycparser",
    "bcrypt", "pydantic", "pydantic-core", "annotated-types",
    "annotated-doc", "greenlet", "mako", "markupsafe", "einops",
    "torch", "torchvision", "facenet-pytorch",
    "filelock", "sympy", "mpmath", "networkx", "jinja2", "fsspec",
    "requests", "urllib3", "charset-normalizer", "tqdm",
    "typing-inspection", "opentelemetry-api", "opentelemetry-sdk",
]

PY_TAGS = {"py3", "cp312", "cp312t", "py2.py3", "py310", "py311", "py312"}
PLAT_TAGS = {"any", "win_amd64", "win32"}
PLAT_RANK = {"win_amd64": 3, "win32": 2, "any": 1}
ABI3_MIN = {"cp36": 36, "cp37": 37, "cp38": 38, "cp39": 39, "cp310": 310,
            "cp311": 311, "cp312": 312}
MIN_VER = {
    "fastapi": "0.115", "pydantic": "2.0", "pydantic-core": "2.0",
    "sqlalchemy": "2.0", "uvicorn": "0.30", "starlette": "0.37",
    "numpy": "1.26", "python-jose": "3.3", "aiofiles": "24.0",
}
UA = "Mozilla/5.0 (compatible; wheel-fetcher)"
_ctx = ssl.create_default_context()


def log(msg):
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
        except Exception as e:
            last = e
        if attempt < tries - 1:
            time.sleep(delay)
            delay *= 2
    raise last


def parse_wheel(name):
    """解析 wheel 文件名 -> dict(py, abi, plat, ver)"""
    if not name.endswith(".whl"):
        return None
    stem = name[:-4]
    head, _, plat = stem.rpartition("-")
    head, _, abi = head.rpartition("-")
    distver, _, pytag = head.rpartition("-")
    _, _, ver = distver.partition("-")
    return {"py": pytag, "abi": abi, "plat": plat, "ver": ver,
            "py_set": set(pytag.split("."))}


def ver_key(ver):
    """版本号转定长元组。必须补齐到固定长度再截断，
    否则段数不同的版本会比较错（例如 1.10.26 会被误判大于 2.13.4）。"""
    out = []
    for part in re.split(r"[._\-+]", ver):
        m = re.match(r"^(\d+)", part)
        if m:
            out.append(int(m.group(1)))
        elif part:
            out.append(0)
    return tuple((out + [0] * 6)[:6])


def compatible(info, pkg):
    """PEP 425 兼容性 + 版本约束"""
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
    if re.search(r"(a|b|rc|dev|post)\d*$", v):
        return False
    if pkg == "numpy" and not v.startswith("1.26."):
        return False
    floor = MIN_VER.get(pkg)
    if floor and ver_key(v) < ver_key(floor):
        return False
    return True


def index_map(pkg, mirror):
    """返回 {wheel 文件名: 绝对 URL}"""
    text = get(mirror + pkg + "/").decode("utf-8", "replace")
    base = mirror.rsplit("/simple/", 1)[0]
    out = {}
    for h in re.findall(r'href="([^"#]+)', text):
        fn = urllib.parse.unquote(h.rsplit("/", 1)[-1])
        if fn.endswith(".whl"):
            out[fn] = h if h.startswith("http") else base + h
    return out


def fetch_one(pkg):
    already = (list(DEST.glob(pkg + "-*.whl"))
               + list(DEST.glob(pkg.replace("-", "_") + "-*.whl")))
    if already:
        return "skip", already[0].name

    errors = []
    for mirror in MIRRORS:
        host = mirror.split("/")[2]
        try:
            files = index_map(pkg, mirror)
        except Exception as e:
            errors.append(f"{host}: {type(e).__name__} {e}")
            continue

        best, best_key = None, None
        for fn, url in files.items():
            info = parse_wheel(fn)
            if not compatible(info, pkg):
                continue
            # 版本号优先，平台仅用于同版本决胜
            key = (ver_key(info["ver"]), PLAT_RANK[info["plat"]])
            if best_key is None or key > best_key:
                best, best_key = (fn, url), key
        if not best:
            errors.append(f"{host}: 无适配 cp312/win_amd64 的 wheel")
            continue

        fn, url = best
        try:
            data = get(url, timeout=120)
            (DEST / fn).write_bytes(data)
            return "ok", f"{fn}  {len(data)/1e6:.1f} MB"
        except Exception as e:
            errors.append(f"{host}: 下载失败 {type(e).__name__} {e}")
            continue

    return "fail", " | ".join(errors)


def main():
    targets = sys.argv[1:] or PACKAGES
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
    log(f"完成: 新下载 {counts['ok']}  已存在 {counts['skip']}  失败 {counts['fail']}")
    log(f"wheelhouse: {len(wheels)} 个 wheel, {total/1e6:.1f} MB")
    if failed:
        log("失败清单: " + ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

#### 第 2 步：运行它，把所有依赖包抓到本地

```bat
python fetch_wheels.py
```

它会在 `backend` 下建一个 `wheelhouse` 文件夹，把依赖包一个个下进去。**总共约 206 MB、50 多个包**。

其中 `torch` 一个就占 124 MB，而且很慢 —— 实测花了 **647 秒（约 11 分钟）**。看到进度卡在 torch 上是正常的，**耐心等，别中断**。

全部成功时最后会打印：

```
完成: 新下载 57  已存在 0  失败 0
wheelhouse: 57 个 wheel, 206.1 MB
```

#### 第 3 步：保存离线安装脚本并运行

在 **backend** 目录下新建 `install_offline.py`，内容如下（**完整复制**）：

```python
# -*- coding: utf-8 -*-
"""
纯离线安装 wheelhouse 里的全部 wheel。

为什么需要它：pip 不接受"目录"或通配符作为包参数（会报
`*.whl is not a valid wheel filename` / `No matching distribution found`），
手工敲几十个文件名极易出错。本脚本自动枚举并安装，全程不联网。

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
```

运行：

```bat
python install_offline.py
```

**这一步完全不联网。** 三个关键参数的作用（这正是绕行的核心）：

- `--no-index` —— **禁止访问网络索引**，从根上避开卡死
- `--no-deps` —— 不做依赖解析（依赖闭包已由抓取脚本备齐）
- `--find-links wheelhouse` —— 只从本地文件夹取包

实测：57 个包（含 124 MB 的 torch）**72.7 秒装完，零报错**。成功时会看到 `Successfully installed ...` 一长串包名，最后提示 `离线安装完成`。

> **不要手工敲** `pip install ... wheelhouse\*.whl` 这种写法 —— 实测会失败：
> 在 cmd 里 `*.whl` 不会被展开，pip 会把它当成字面文件名，报
> `ERROR: *.whl is not a valid wheel filename`。
> 传目录同样不行，会被当成包名，报 `No matching distribution found for wheelhouse`。

---

## 5. 验证环境是否装好

在 `backend` 目录下新建 `_verify_env.py`：

```python
# -*- coding: utf-8 -*-
"""环境自检：逐个导入依赖，并验证模型权重能否加载。"""
import importlib
import sys
import traceback
from pathlib import Path

MODULES = [
    "fastapi", "uvicorn", "sqlalchemy", "aiosqlite", "pydantic",
    "multipart", "aiofiles", "numpy", "PIL", "cv2", "torch",
    "facenet_pytorch", "jose", "bcrypt", "httpx", "einops",
    "websockets", "watchfiles",
]

print("=" * 62)
print("解释器:", sys.executable)
print("Python 版本:", sys.version.split()[0])
print("=" * 62)

failed = []
for name in MODULES:
    try:
        mod = importlib.import_module(name)
        print(f"  OK    {name:18s} {getattr(mod, '__version__', '?')}")
    except Exception as exc:
        failed.append((name, exc))
        print(f"  FAIL  {name:18s} {type(exc).__name__}: {exc}")

print("-" * 62)
print(f"导入结果: {len(MODULES) - len(failed)}/{len(MODULES)} 成功")

print("-" * 62)
print("验证 LMTformer 权重加载 ...")
try:
    import torch

    backend = Path.cwd()
    ckpt_path = backend / "best.pt"
    print(f"  权重文件: {ckpt_path}  存在={ckpt_path.exists()}")

    sys.path.insert(0, str(backend))
    from LMTformer_model.LMTformer import LMTformer

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"  推理设备: {device}")

    model = LMTformer(
        image_size=(24, 128, 128), patches=(2, 4, 4), dim=32,
        num_heads=4, num_layers=12, dropout_rate=0.1, device=device,
    ).to(device)

    ckpt = torch.load(str(ckpt_path), map_location=device, weights_only=False)
    sd = {k.replace(".module.", "."): v for k, v in ckpt.items()}
    missing, unexpected = model.load_state_dict(sd, strict=False)
    model.eval()

    print(f"  state_dict 条目: {len(sd)}")
    print(f"  缺失键: {len(missing)}   多余键: {len(unexpected)}")

    dummy = torch.randn(1, 3, 24, 128, 128, device=device)
    with torch.no_grad():
        out = model(dummy)
    print(f"  前向推理成功，输出 shape={tuple(out.shape)} 值={out.item():.4f}")
    print("  模型验证: 通过")
except Exception:
    print("  模型验证: 失败")
    traceback.print_exc()

print("=" * 62)
if failed:
    print("结论: 仍有依赖缺失 ->", ", ".join(n for n, _ in failed))
    sys.exit(1)
print("结论: 全部依赖就绪")
```

运行：

```bat
python _verify_env.py
```

**期望输出（关键三行）**：

```
导入结果: 18/18 成功
  缺失键: 0   多余键: 0
结论: 全部依赖就绪
```

`缺失键: 0   多余键: 0` 说明 `best.pt` 权重和模型结构**完全对得上**，这是最重要的一条确认。看到这个就基本成功了。

---

## 6. 启动

> **一键版**：直接双击 `启动-仅本机.bat` 即可。如果你已经按第 2-5 节手动装好了环境，
> 双击同样能用 —— 脚本发现环境齐全会直接启动，不会重复安装。

**退出虚拟环境**（`.bat` 会自己找 venv，不需要激活状态）：

```bat
deactivate
```

然后直接**双击** `启动-仅本机.bat`。

成功时会看到（前面还有脚本自己的 5 步进度）：

```
INFO:     Started server process [xxxxx]
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
```

脚本会在端口就绪后**自动打开浏览器**；手动打开 <http://127.0.0.1:8000> 也一样。
**这个黑窗口就是服务本体，关掉它服务就停。**

---

## 7. 常见问题速查

### `ModuleNotFoundError: No module named 'fastapi'`（或别的包名）

依赖没装全。确认：
1. 你是在 `backend` 目录下操作的
2. 装之前命令行有 `(venv)` 前缀
3. 回到第 4 节重跑

**补装缺失的包**（离线方式，比如缺 `annotated_doc`）：

```bat
python fetch_wheels.py annotated-doc
python install_offline.py
```

两条命令的含义：第一条只抓缺的那个包进 `wheelhouse`（已存在的会自动跳过），第二条把 `wheelhouse` 里的全部包重新过一遍 —— **pip 对已装好的包会自动跳过，所以这是安全的重跑**，正好把新补的包装上。

> 提示：这类"漏网"的传递依赖是正常的。抓取脚本的包清单已尽量列全，但上游包偶尔会引入新的依赖。**缺什么就按上面补什么**即可。实际踩过的例子：`fastapi` 新版需要 `annotated-doc` 和 `opentelemetry-api`，`facenet-pytorch` 需要 `requests`、`tqdm`、`torchvision` —— 这些都已收进包清单。

### 一键脚本报「四个源全部探测不通」/ `getaddrinfo failed` / `Read timed out`

这是**网络或 DNS 问题，不是项目问题**。一键脚本会自动这么处理：

1. 启动前先花几秒探测 4 个源（阿里云 / 清华 / 腾讯云 / PyPI 官方），
   逐个打印 `[OK] 可用` 或 `[!] 不可用 - 域名解析失败（DNS）`
2. 只对**探测通**的源尝试安装，不通的直接跳过，不再白等
3. 如果**四个源都探测不通**，脚本会明确指出这是 DNS / 连接问题，
   并**跳过 IPv4 抓包兜底**（它也要联网，硬跑只会多等十几分钟）

**实测踩到的真实情况**：某台机器上 `mirrors.aliyun.com` 能连通并下载了一部分包，
随后 `Read timed out`，紧接着 `pypi.tuna.tsinghua.edu.cn`、`pypi.org` 全部
`[Errno 11001] getaddrinfo failed`（域名解析失败）—— 同一台机器用 `curl` 访问同一
地址却正常。这类故障与项目无关，处理办法：

- 关掉代理 / VPN 再试（或反过来，把代理打开再试）
- 换手机热点等网络环境重试一次
- 直接走离线路线：在能联网的电脑上跑 `fetch_wheels.py`，把 `wheelhouse\` 拷过来
- 依赖装到一半失败不用慌：**重新双击 bat 即可**，已装好的包会自动跳过

### `ERROR: [Errno 10048] error while attempting to bind on address ('127.0.0.1', 8000)`

**端口已被占用**，通常是**上一次的服务窗口没关干净**（或还开着另一个）。

注意：这条报错**不代表启动失败**。日志里如果已出现 `Application startup complete.`，说明环境完全正常，只是最后"抢端口"这一步失败。

**排查：**

```bat
netstat -ano | findstr :8000
```

最后一列是 PID，去任务管理器结束它，或直接关掉那个残留的黑窗口。也可以等 1–4 分钟让系统自动释放。

**换端口启动**（避免冲突）：

```bat
venv\Scripts\python.exe serve_all.py
```
若要用别的端口，先设环境变量：
```bat
set PORT=8001
venv\Scripts\python.exe serve_all.py
```

### 编辑 `.bat` 时中文变乱码

用**记事本**打开保存即可。若用 VSCode 等编辑器，注意保存为 **ANSI/GBK** 编码 —— cmd 默认按 GBK 读脚本，存成 UTF-8 会让中文提示变乱码。

（本指南提供的两个 `.bat` 内容**全是英文提示**，就是为了避开这个坑，用记事本直接保存不会有编码问题。）

### 人脸检测第一次很慢 / 报网络错误

系统的面部检测用的是 MTCNN 模型，**它的权重文件不在项目包里**，首次运行会从 GitHub 下载。实测首次检测耗时约 **7.4 秒**（含下载），之后会缓存到本地，后续就快了。

如果这台电脑**完全无法联网**，检测会失败并自动**回退到"中心裁剪"** —— 系统不会崩溃，但人脸对齐精度会下降。**建议首次在有网环境下跑一次**，把权重缓存下来。

### 报告里"面部特征分析""缓解建议"是空的

这些文字由**云端大模型**生成（`config.py` 里指向 `cloud.infini-ai.com`），需要有效的 API 密钥。原包里写死的密钥**已失效**，接口会返回：

```
HTTP 401  {"error":{"message":"请使用正确的api key进行请求","code":"invalid_api_key"}}
```

**这不影响核心功能** —— BDI-II 抑郁评分是**本地模型算的**，完全正常。只是那几段文字为空（代码里已做容错，不会报错崩溃）。

若要恢复，需在 `config.py` 里换一个有效的 `VLM_API_KEY`。

> **隐私提醒**：该功能会把**用户人脸图像上传到第三方云端**。原始包**不含任何可直接运行的界面**（前端已打包在 `dist/`）。用于真实数据或正式演示前，请务必知悉这一点——如果不需要云端解读，把 `config.py` 的 `VLM_API_KEY` 留空即可让它安静地跳过。

### 登录时不知道用户名密码

数据库 `depression.db` 里是**原作者的真实使用记录**（8 个账号、98 条诊断报告），不是演示用假数据。你可以直接**注册一个新账号**使用。

若希望干净起步，可备份后清空数据表。**先关掉服务**，再执行：

```bat
copy depression.db depression.db.bak
venv\Scripts\python.exe -c "import sqlite3;c=sqlite3.connect('depression.db');c.execute('DELETE FROM diagnosis_reports');c.execute('DELETE FROM media_assets');c.commit();print('已清空')"
```

---

## 8. 如果是 Linux 服务器

以上绕行方案针对 Windows。**Linux 上通常不需要**这些步骤 —— 第 4 节的卡死源于本机 Python 网络栈的地址选择，Linux 下少见。

标准流程：

```bash
sudo apt update && sudo apt install -y python3.12 python3.12-venv python3-pip
cd 系统代码/backend
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/
python _verify_env.py
```

启动（要外部访问必须设 `HOST`）：

```bash
HOST=0.0.0.0 venv/bin/python serve_all.py
```

**注意：`wheelhouse` 里的 wheel 是 Windows 专用的，不能在 Linux 上用**，必须在 Linux 上重新下载。若服务器无法联网，需要在一台联网的 Linux 机器上先执行 `pip download -r requirements.txt -d wheelhouse`，再把整个目录拷过去。

**服务器部署必读：**

- **不要用 `.bat`**，它们是 Windows 批处理。直接用上面的命令行。
- **对外暴露前请改默认密钥**：`config.py` 里 `JWT_SECRET_KEY` 有默认开发值，启动时通过环境变量覆盖：
  ```bash
  JWT_SECRET_KEY="换成随机长字符串" HOST=0.0.0.0 venv/bin/python serve_all.py
  ```
  否则任何人都能用默认密钥伪造登录令牌。
- **建议放在反向代理后面**（Nginx），由它处理 HTTPS；`serve_all.py` 自带的 uvicorn 是开发级服务器，不适合直接对公网暴露。
- **人脸数据有隐私属性**，公网部署前请确认合规性。

---

## 9. 一句话总结

**现在：双击 `dashboard\启动-仅本机.bat` 就行。** 没有 Python 会自动装 Python，
没有环境会自动建虚拟环境，没有依赖会自动装依赖（先离线 wheelhouse、再国内镜像、
最后 IPv4 抓包兜底），装完自动启动并自动打开浏览器。

历史失败链条（旧包）：**脚本写死了别人电脑上的 Python 路径 → 本机没有 Python →
有 Python 但依赖全缺 → 装依赖时 pip 卡死**。四条现在全部由脚本自动处理。

### 相关文件清单（本项目已包含，无需手动创建）

| 文件 | 位置 | 作用 |
|---|---|---|
| `启动-仅本机.bat` | `dashboard\` | **一键启动（推荐）**，只有本机能访问 |
| `启动-局域网共享.bat` | `dashboard\` | 一键启动 + 同网段其它设备可访问 |
| `_ensure_python.bat` | `dashboard\backend\` | 自动查找 Python；找不到就自动装 3.12.10 |
| `bootstrap.py` | `dashboard\backend\` | 建虚拟环境、装依赖、自检、启动、开浏览器 |
| `fetch_wheels.py` | `dashboard\backend\` | 离线/断网时的抓包脚本（强制 IPv4） |
| `install_offline.py` | `dashboard\backend\` | 纯离线安装 wheelhouse 里的 wheel |
| `_verify_env.py` | `dashboard\backend\` | 环境深度自检（导入依赖 + 加载模型权重） |
| `wheelhouse\` 目录 | `dashboard\backend\` | 可选。57 个 wheel、约 206 MB，有它就能离线装 |
| `best.pt` | `dashboard\backend\` | LMTformer 推理权重（3.78 MB），**已随项目提交，clone 就有** |
| `LMTformer_model\` | `dashboard\` 和 `dashboard\backend\` | 模型结构定义，**两份都已提交**（前者应用运行时用，后者自检用） |
| `bootstrap.log` | `dashboard\backend\` | 启动脚本的运行日志，排错先看它 |

> `venv\`、`wheelhouse\`、`bootstrap.log` 不在 Git 仓库里（见 `.gitignore`），
> 前两者分别由脚本自动生成；**模型相关的 `best.pt` 与两份 `LMTformer_model\` 已经提交**，
> 所以从 GitHub clone 下来就能直接分析，不需要再去别处找模型文件。

### 如果你的电脑无法联网

一键脚本会自动走这条路，手动做也一样：

1. 在**另一台能联网的 Windows 电脑**上，于 `backend` 目录执行 `python fetch_wheels.py`
   （生成 `wheelhouse\`，约 206 MB）
2. 把整个 `wheelhouse\` 目录拷到目标电脑的 `backend\` 下
3. 双击 `启动-仅本机.bat` —— 脚本优先用本地 wheelhouse 离线安装

注意：`wheelhouse` 里的包是 **Windows + Python 3.12 专用**的，不能给 Linux 或别的 Python 版本用（见第 8 节）。

### 完成的标志

一键脚本自己会做这件事，输出里能看到：

```
导入结果: 18/18 成功
  缺失键: 0   多余键: 0
结论: 全部依赖就绪
```

外加脚本最后打印 `[OK] 服务已就绪，正在打开浏览器：http://127.0.0.1:8000`，
浏览器里能看到登录页。看到这些，就算复现成功了。
