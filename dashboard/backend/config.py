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

# JWT（生产环境请设置环境变量 JWT_SECRET_KEY）
JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY", "depression-dashboard-dev-secret-change-in-production")
JWT_ALGORITHM = "HS256"
JWT_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", str(60 * 24 * 7)))  # default 7 days
MEDIA_DIR = BASE_DIR / "media"
DATABASE_URL = f"sqlite+aiosqlite:///{BASE_DIR / 'depression.db'}"

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
CORS_ORIGINS = ["*"]
