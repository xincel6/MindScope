import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent


def _load_dotenv(path: Path) -> None:
    """极简 .env 加载器（零依赖，离线环境同样可用）。

    只做一件事：把 KEY=VALUE 逐行写进 os.environ。
    已存在的环境变量优先，不会被 .env 覆盖（所以 .bat 里 set 的 HOST 依然生效）。
    """
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


# 先加载 .env，再读取各项配置
_load_dotenv(BASE_DIR / ".env")


def _require_secret(key: str, min_len: int = 32) -> str:
    """读取必需的密钥型环境变量 · 缺失 / 过短 / 仍是模板占位符 → 启动即失败。

    ★ 为什么不留默认值（2026-10-18 安全审计）：
      原先这里写着 `os.getenv("JWT_SECRET_KEY", "depression-dashboard-dev-secret-...")`。
      只要某次部署漏配 .env，服务会"正常启动"，但用的是**写在源码里、任何人可查的**
      对称密钥 —— 攻击者据此可以离线签发任意用户的合法 JWT，直接冒充管理员。
      加密算法的强度在这里毫无意义：密钥公开了，整套签名体系就归零。
      所以改成 fail-fast：宁可起不来（部署时立刻发现），也不能悄悄用弱密钥跑起来。
    """
    value = os.getenv(key, "").strip()
    if not value:
        raise RuntimeError(
            f"\n[配置错误] 未设置环境变量 {key}。\n"
            f"  请在 {BASE_DIR / '.env'} 中配置（参考 .env.example）。\n"
            f'  生成随机密钥：python -c "import secrets; print(secrets.token_urlsafe(48))"\n'
        )

    # 模板占位符 / 弱口令：明确拒绝，避免"copy .env.example .env"之后直接开服
    lowered = value.lower()
    weak_markers = ("change-me", "changeme", "placeholder", "your-secret", "todo")
    if lowered in {"secret", "password", "123456", "test"} or any(m in lowered for m in weak_markers):
        raise RuntimeError(
            f"\n[配置错误] {key} 仍是模板占位符或弱口令（当前值不可用于生产）。\n"
            f'  生成随机密钥：python -c "import secrets; print(secrets.token_urlsafe(48))"\n'
        )

    if len(value) < min_len:
        raise RuntimeError(
            f"\n[配置错误] {key} 太短：{len(value)} 字符，至少需要 {min_len} 字符。\n"
            f"  HS256 的强度上限就是密钥本身的熵；短密钥可被离线暴力破解后伪造令牌。\n"
            f'  生成随机密钥：python -c "import secrets; print(secrets.token_urlsafe(48))"\n'
        )
    return value


JWT_SECRET_KEY = _require_secret("JWT_SECRET_KEY")
JWT_ALGORITHM = "HS256"
JWT_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", str(60 * 24 * 7)))  # default 7 days
MEDIA_DIR = BASE_DIR / "media"

# ── SMTP 发信（邮箱验证码）─────────────────────────────────────────────────
# ★ 密码位放的是 QQ 邮箱的「授权码」，不是 QQ 密码；授权码由
#   mail.qq.com → 设置 → 账号与安全 → 开启 IMAP/SMTP 服务 生成，只显示一次。
# ★ 未配置（SMTP_HOST / SMTP_USER / SMTP_PASSWORD 任一为空）时，发码接口
#   返回 503 并提示"服务端未配置邮件服务"，**不会**静默跳过 —— 否则用户
#   以为收到验证码，实际什么也没发，注册流程会莫名卡住。
SMTP_HOST = os.getenv("SMTP_HOST", "").strip()
SMTP_PORT = int(os.getenv("SMTP_PORT", "465"))
SMTP_USE_SSL = os.getenv("SMTP_USE_SSL", "true").strip().lower() in ("1", "true", "yes")
SMTP_USER = os.getenv("SMTP_USER", "").strip()
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "").strip()
SMTP_FROM = os.getenv("SMTP_FROM", "").strip() or SMTP_USER
SMTP_FROM_NAME = os.getenv("SMTP_FROM_NAME", "MindScope").strip()


def smtp_configured() -> bool:
    """SMTP 三要素是否齐全（缺任一即视为未配置）。"""
    return bool(SMTP_HOST and SMTP_USER and SMTP_PASSWORD)


def _resolve_path(raw: str, default: Path) -> Path:
    """解析可配置路径：空值用默认；相对路径按 backend 目录解析（与启动目录无关）。"""
    value = (raw or "").strip()
    if not value:
        return default
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = (BASE_DIR / path).resolve()
    return path


# ── 数据库（★ 线上请用 DATABASE_PATH 指到仓库外，见 docs/Linux服务端部署指南.md）──
# 为什么要可配置：`depression.db` 曾经**被 git 跟踪**，服务器每次 `git pull` /
# `git reset` 都会拿仓库里的旧快照覆盖线上库 —— 2026-10-18 那次部署就因此
# 丢掉了注册账号和报告（BUG-26）。现在仓库里只放 `demo/depression.db` 种子，
# 运行库不进版本库；线上再把 DATABASE_PATH 指到仓库外，git 就再也碰不到它。
DEMO_DB_PATH = BASE_DIR / "demo" / "depression.db"
DATABASE_PATH = _resolve_path(os.getenv("DATABASE_PATH", ""), BASE_DIR / "depression.db")
DATABASE_URL = f"sqlite+aiosqlite:///{DATABASE_PATH}"

# 启动前自动备份目录（`backup_db.py` 与 serve_all.py 共用；不进版本库）
BACKUP_DIR = _resolve_path(os.getenv("DB_BACKUP_DIR", ""), BASE_DIR / "backups")

# Frame processing
FRAMES_PER_BATCH = 24
FACE_SIZE = 128
TARGET_INFERENCE_MS = 28.0  # ~0.028s

# LMTformer model paths (adjust to your actual locations)
MODEL_CHECKPOINT = str(BASE_DIR / "best.pt")
MODEL_SOURCE_DIR = str(BASE_DIR.parent)  # project root, for LMTformer_model/

# VLM (vision-language model) for facial interpretation
# ⚠️ 密钥不再硬编码在源码里：从 .env 或环境变量读取（见 .env.example）
VLM_API_KEY = os.getenv("VLM_API_KEY", "")
VLM_API_HOST = os.getenv("VLM_API_HOST", "cloud.infini-ai.com")
VLM_API_PATH = os.getenv("VLM_API_PATH", "/maas/v1/chat/completions")
VLM_MODEL = os.getenv("VLM_MODEL", "glm-4.6v")

# Text LLM (Infini-AI MaaS, OpenAI-compatible)
LLM_API_KEY = os.getenv("LLM_API_KEY") or VLM_API_KEY
LLM_API_HOST = os.getenv("LLM_API_HOST", VLM_API_HOST)
LLM_API_PATH = os.getenv("LLM_API_PATH", "/maas/v1/messages")
LLM_MODEL = os.getenv("LLM_MODEL", "deepseek-v4-flash")

# CORS
# ★ 默认只允许同源（空列表 = 不加 CORS 白名单，跨域请求一律拒绝）。
#   需要额外允许的前端来源通过环境变量配置，逗号分隔，例如：
#     CORS_ORIGINS=http://localhost:5173,http://192.168.0.10:5173
#   注意：不要再用 "*"——它无法与 allow_credentials=True 共存，等于把认证放开。
CORS_ORIGINS = [
    o.strip()
    for o in os.getenv("CORS_ORIGINS", "").split(",")
    if o.strip()
]

# HTTPS / TLS
# ★ 证书文件由运维放置（本地可用自签证书），这里只读配置，源码不硬编码证书。
#   两个都配置了才会启用 TLS；缺任一则保持纯 HTTP。
SSL_CERTFILE = os.getenv("SSL_CERTFILE", "")
SSL_KEYFILE = os.getenv("SSL_KEYFILE", "")
