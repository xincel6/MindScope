from contextlib import asynccontextmanager

from fastapi import FastAPI
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
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
