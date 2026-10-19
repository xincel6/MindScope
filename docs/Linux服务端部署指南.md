# MindScope 服务端 · Linux 部署指南

> 适用：把仓库上传到 GitHub 后，在 **Linux 服务器**上拉取并运行。
> 本指南只涉及服务端（`dashboard/`），鸿蒙端在 DevEco Studio 里编译，与服务器无关。
>
> 代码本身**不需要为 Linux 改动**：已核实无 Windows 专属 API、无硬编码绝对路径、全部路径基于
> `Path(__file__).resolve().parent` 推导，`DATABASE_URL` 在 Linux 上会自动得到
> `sqlite+aiosqlite:////.../backend/depression.db`（四斜杠绝对路径，SQLAlchemy 要求的形式）。
> 线上可用环境变量 `DATABASE_PATH` 把库指到**仓库外**（见 3.4.1，强烈建议）。

---

## 一、上传前必须先修的三个问题（已在本仓库修好）

| # | 问题 | 后果 | 状态 |
|---|---|---|---|
| 1 | `requirements.txt` **缺 `einops`** | `LMTformer_model/LMTformer.py:9` 是模块级 `from einops import rearrange`；缺失时 `import main` 直接失败，**整个服务起不来**（不只是推理不可用） | ✅ 已补 |
| 2 | `.env.example` **不存在**，但 README 让人 `copy .env.example .env`、`.gitignore` 里也写了 `!.env.example` | 新机器按文档操作第一步就报文件不存在 | ✅ 已补（含全部键与注释，无任何真实密钥） |
| 3 | 只有 Windows `.bat` 启动脚本 | Linux 上无法一键启动 | ✅ 已补 `启动-局域网共享.sh` / `启动-仅本机.sh` |

另外补了根目录 `.gitattributes`：强制 `.sh` 用 LF、`.bat` 用 CRLF，并把
`*.pt / *.db / *.mp4 / *.webm` 标记为二进制，避免 Windows 与 Linux 之间克隆时被换行符转换弄坏。

> **为什么 `einops` 这个坑最隐蔽**：项目的 venv 是从 `wheelhouse/` 离线装的，而 `wheelhouse/` 被
> `.gitignore` 排除、不会上传。作者本机装过 `einops` 所以一直没暴露；别人克隆后重建 venv 才会踩到。
> 同类隐式依赖已排查完毕：`thop` 只在 `LMTformer.py:154` 的 `profile_model()` 函数体内 import
> （仅用于统计 FLOPs，不参与服务启动），已在 `requirements.txt` 里注释说明为可选。

---

## 二、依赖清单核对结论

`requirements.txt` 现已覆盖全部第三方依赖，逐项对应关系：

| 依赖 | 被谁使用 |
|---|---|
| `fastapi` / `uvicorn[standard]` / `python-multipart` / `aiofiles` | `main.py`、`serve_all.py`、`routers/upload.py` |
| `sqlalchemy` / `aiosqlite` / `pydantic` | `database.py`、`models.py`、`schemas.py` |
| `python-jose[cryptography]` / `bcrypt` | `auth_utils.py` |
| `numpy` / `pillow` / `opencv-python-headless` | `services/frame_processor.py`、`face_detect.py` |
| `torch` | `LMTformer_model/`、`services/inference.py` |
| `facenet-pytorch` | MTCNN 检测（`services/face_alignment.py`）；**其 `torchvision` 依赖会自动拉取**，无需单独声明 |
| **`einops`** | `LMTformer_model/LMTformer.py`（★ 本次补上） |

---

## 三、Linux 部署步骤

### 3.1 系统依赖

`opencv-python-headless` 与 `torch` 需要这些系统库（Ubuntu/Debian 示例）：

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip git
# opencv-python-headless 已内置编解码器，但仍建议装齐基础运行库：
sudo apt install -y libglib2.0-0 libgl1 || true
```

> 用 `opencv-python-headless` 而不是 `opencv-python`，所以**不需要** X11/显示环境，服务器上跑没问题。

### 3.2 拉取代码

```bash
git clone <你的仓库地址> MindScope
cd MindScope/dashboard/backend
```

### 3.3 建虚拟环境并装依赖

```bash
python3 -m venv venv
venv/bin/pip install --upgrade pip
venv/bin/pip install -r requirements.txt
```

> ⚠ **`torch` 体积提醒（Linux 上最需要注意的一点）**：`pip install torch` 会从 PyPI 拉到
> 带 CUDA 运行时的版本，**下载量约 800 MB–2.5 GB**、解压后数 GB。本项目是**CPU 推理**
> （`best.pt` 仅 3.8 MB，24 帧/批次目标 28ms），如果服务器没 GPU 且磁盘/带宽紧张，装 CPU 版即可：
>
> ```bash
> # 先单独装 CPU 版 torch，再装其余依赖（requirements 里的 torch>=2.0.0 会被满足，不会重复下载）
> venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cpu
> venv/bin/pip install -r requirements.txt
> ```
>
> 国内网络建议加镜像：`-i https://pypi.tuna.tsinghua.edu.cn/simple`

### 3.4 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env`，**至少**改这两项：

```ini
# 1) 必须改：否则任何人都能用默认密钥伪造 JWT 令牌
JWT_SECRET_KEY=<用下面命令生成>
# 2) 手机/其它电脑要访问时必须放开监听
HOST=0.0.0.0
```

生成随机密钥：

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(48))"
```

VLM / LLM 密钥：

- **填了** → 分析结束后会调用云端大模型生成中文诊断文本（需要外网）。
- **不填** → 分析与评分、报告落库、统计面板全部正常，只是缺少 VLM 语义化解读文本
  （`services/vlm.py` 与 `llm.py` 会静默跳过，不会报错）。

### 3.4.1 数据目录与备份（线上必做）

**背景**：2026-10-18 的一次部署把线上库换成了仓库里的旧快照，注册账号与十余条报告丢失（BUG-26）。
根因是 `depression.db` 当时**被 git 跟踪**，`git pull` / `git reset` / 重新 clone 都会用仓库版本覆盖它。

现在仓库里只保留**演示种子** `dashboard/backend/demo/depression.db`；运行库首次启动时自动复制出来，
默认路径 `dashboard/backend/depression.db` 已加入 `.gitignore`。线上再把它移到**仓库外**：

```bash
sudo mkdir -p /var/lib/mindscope/backups
sudo chown -R "$USER" /var/lib/mindscope

# 把当前线上库挪出仓库（只需做一次；先停服务）
sudo systemctl stop mindscope 2>/dev/null || true
mv /opt/MindScope/dashboard/backend/depression.db /var/lib/mindscope/depression.db
```

在 `.env` 里写死（相对路径会按 backend 目录解析，仍建议写绝对路径）：

```ini
DATABASE_PATH=/var/lib/mindscope/depression.db
DB_BACKUP_DIR=/var/lib/mindscope/backups
```

`serve_all.py` **每次启动前自动热备份**一份到 `DB_BACKUP_DIR`（保留最近 10 份；
`DB_BACKUP_ON_START=0` 可关闭）。也可以手动跑：

```bash
cd /opt/MindScope/dashboard/backend
venv/bin/python backup_db.py                 # → /var/lib/mindscope/backups/depression-YYYYmmdd-HHMMSS.db
venv/bin/python backup_db.py --keep 20       # 保留 20 份
```

恢复（**先停服务**，别在进程写入时覆盖）：

```bash
sudo systemctl stop mindscope
cp /var/lib/mindscope/backups/depression-20261018-153000.db /var/lib/mindscope/depression.db
sudo systemctl start mindscope
```

以后更新代码（数据在仓库外，git 碰不到）：

```bash
cd /opt/MindScope
git pull --ff-only
dashboard/backend/venv/bin/pip install -r dashboard/backend/requirements.txt   # 依赖有变时
sudo systemctl restart mindscope      # 启动前会自动备份一次
```

> ⚠ **不要用 `git reset --hard` / `git checkout .` 去"解决冲突"**：以前那次数据被覆盖，
> 正是从这里进去的。库文件不在仓库里之后，冲突源也就不存在了。

### 3.5 启动

```bash
cd <仓库路径>/dashboard
chmod +x 启动-局域网共享.sh 启动-仅本机.sh      # 只需一次
./启动-局域网共享.sh                            # 开放局域网（手机可访问）
# 或
./启动-仅本机.sh                                # 仅本机，安全默认
```

脚本会自动：切到 `backend/`、探测 `venv/bin/python`、设置 `HOST=0.0.0.0`、打印本机局域网 IP。

也可以手工启动：

```bash
cd <仓库路径>/dashboard/backend
export KMP_DUPLICATE_LIB_OK=TRUE
export HOST=0.0.0.0
venv/bin/python serve_all.py
```

启动成功的标志：

```
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

### 3.6 放行防火墙

```bash
# ufw（Ubuntu 常见）
sudo ufw allow 8000/tcp
# firewalld（CentOS/RHEL 系）
sudo firewall-cmd --add-port=8000/tcp --permanent && sudo firewall-cmd --reload
```

云服务器还要在**安全组 / 网络 ACL** 里放行 8000 端口（这一步最容易漏，表现为"本机 curl 通、外网不通"）。

---

## 四、部署验收（逐条可执行）

```bash
# 1) 依赖是否齐全（最关键的一条：验证 einops 已装）
venv/bin/python -c "import einops, torch, cv2, facenet_pytorch, fastapi, sqlalchemy, aiosqlite, jose, bcrypt; print('依赖 OK')"

# 2) 应用能否导入（等价于"服务能不能起来"）
venv/bin/python -c "import main; print('app 导入 OK，路由数:', len(main.app.routes))"

# 3) 健康检查
curl -s http://127.0.0.1:8000/health
# 期望：{"status":"ok"}

# 4) 鉴权链路（未带令牌应 401）
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/api/media/list
# 期望：401

# 5) 演示数据是否随仓库到位（期望 8 / 11 / 121）
venv/bin/python - <<'EOF'
import sqlite3
c = sqlite3.connect("depression.db")
for t in ("users", "media_assets", "diagnosis_reports"):
    print(t, c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0])
EOF

# 6) 前端页面（dist 已被 serve_all.py 托管）
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/
# 期望：200

# 7) 局域网可达性（把 IP 换成服务器真实 IP；从另一台机器执行）
curl -s http://<服务器IP>:8000/health
```

> 上述第 1–6 条已在开发机实测通过（服务端冒烟测试：注册 → bcrypt → JWT → 鉴权 → SQLite
> → 分页 → SPA 首页 → 静态媒体文件，全部返回预期结果）。
> 第 7 条依赖你的网络环境，请自行验证。

---

## 五、鸿蒙端连接服务器

这是本轮鸿蒙端开发的落地闭环，两处要对上：

1. **服务端地址**：鸿蒙端的占位地址在
   `harmony/entry/src/main/ets/common/ApiConfig.ets`：

   ```ts
   public static host: string = '127.0.0.1';   // 改成服务器 IP 或域名
   public static port: number = 8000;
   ```

   也支持运行期修改（答辩现场不用重装）：`AppStore.get().changeServer(ip, 8000)`，
   改完会自动持久化并探活。

2. **明文 HTTP 放行**：本项目用 `http://` / `ws://`，鸿蒙端已在
   `harmony/entry/src/main/module.json5` + `resources/base/profile/network_config.json`
   配好明文放行（该配置需 SDK 6.1.0(23) 及以上，本工程正好满足）。

3. **自测顺序**：先在手机浏览器打开 `http://<服务器IP>:8000/health`，能看到
   `{"status":"ok"}` 说明网络通；再启动鸿蒙端，用 App 内「探活」按钮复验。

> ⚠ 用 `http://IP:8000` 而不是 `http://127.0.0.1:8000` —— 手机上的 127.0.0.1 是手机自己。

---

## 六、生产化建议（答辩演示可跳过）

当前 `serve_all.py` 用的是 **uvicorn 开发服务器**（`uvicorn.run` 单进程、无自动重启、
无优雅退出管理）。长期运行建议：

```ini
# /etc/systemd/system/mindscope.service
[Unit]
Description=MindScope Backend
After=network.target

[Service]
Type=simple
User=mindscope
WorkingDirectory=/opt/MindScope/dashboard/backend
Environment=KMP_DUPLICATE_LIB_OK=TRUE
Environment=HOST=0.0.0.0
Environment=PORT=8000
# ★ 数据在仓库外：部署/更新代码永远碰不到线上库（见 3.4.1）
Environment=DATABASE_PATH=/var/lib/mindscope/depression.db
Environment=DB_BACKUP_DIR=/var/lib/mindscope/backups
EnvironmentFile=/opt/MindScope/dashboard/backend/.env
ExecStart=/opt/MindScope/dashboard/backend/venv/bin/python serve_all.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mindscope
sudo systemctl status mindscope
journalctl -u mindscope -f          # 看日志
```

**注意**：本项目用了 WebSocket（`/ws/analysis`），如果要换 gunicorn，必须带
`-k uvicorn.workers.UvicornWorker`，且**建议单 worker**（推理模型加载在进程内存里，
多 worker 会成倍占用内存并重复加载 `best.pt`）。

其他上线前必改项（README 第九节也提到了）：

- `JWT_SECRET_KEY` 换成随机值（**必改**）。
- `config.py` 的 `CORS_ORIGINS = ["*"]` 收紧到实际域名。
- 若要对外网开放，前面套 Nginx 加 HTTPS —— 但注意鸿蒙端的 WS 会用 `ws://`，
  换 `wss://` 时需同步改 `ApiConfig.analysisWsUrl()`。

---

## 七、本次为 Linux 部署所做的改动

```
修改  dashboard/backend/requirements.txt      补 einops>=0.7.0；分组加注释；标注 thop 为可选
新增  dashboard/backend/.env.example          环境变量模板（README 与 .gitignore 本就引用它）
新增  dashboard/启动-局域网共享.sh             Linux 一键启动（HOST=0.0.0.0 + 自动探 IP）
新增  dashboard/启动-仅本机.sh                 Linux 一键启动（仅本机）
新增  .gitattributes                          .sh 强制 LF / .bat 强制 CRLF / 二进制文件标记
修改  dashboard/backend/serve_all.py          清理重复的 import 块（原有 10 行重复导入）
新增  docs/Linux服务端部署指南.md              本文
```

**未改动**：所有路由、模型、推理、鉴权代码 —— 服务端业务逻辑与数据契约完全不变，
鸿蒙端本轮已实现的 `network/` 层无需任何调整。
