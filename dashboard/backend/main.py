from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from config import MEDIA_DIR, CORS_ORIGINS
from database import init_db
import models  # noqa: F401 — register ORM tables (User, MediaAsset, …)
from routers.media import router as media_router
from routers.report import router as report_router
from routers.ws import router as ws_router
from routers.upload import router as upload_router
from routers.auth import router as auth_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(title="Depression Diagnosis Backend", version="0.1.0", lifespan=lifespan)

# run :  uvicorn main:app --reload

# --- CORS ---
# ★ 默认（CORS_ORIGINS 为空）不加 CORS 中间件：跨域请求直接拒绝，同源不受影响。
#   只有显式配置了白名单才启用，且此时 allow_credentials 才允许为 True。
#   不要用 allow_origins=["*"] + allow_credentials=True：那既违反 CORS 规范，也等于放开认证。
if CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )


# --- 安全响应头 ---
@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = (
        "camera=(), microphone=(), geolocation=(), interest-cohort=()"
    )
    # ★ CSP 对含内联脚本的页面可能误伤，先给一个保守的默认值，可按需收紧
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "img-src 'self' data: blob:; "
        "media-src 'self' blob:; "
        "connect-src 'self' ws: wss:; "
        "style-src 'self' 'unsafe-inline'; "
        "script-src 'self'"
    )
    return response

# --- Routers ---
app.include_router(auth_router)
app.include_router(media_router)
app.include_router(report_router)
app.include_router(ws_router)
app.include_router(upload_router)

# --- Static files for video playback ---
MEDIA_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=str(MEDIA_DIR)), name="media")


@app.get("/health")
async def health():
    return {"status": "ok"}
