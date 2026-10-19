from pydantic import BaseModel
import datetime
from typing import Optional


# --- Auth ---
class UserRegister(BaseModel):
    username: str
    password: str
    email: Optional[str] = None


class UserLogin(BaseModel):
    username: str
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: int
    username: str
    email: Optional[str] = None
    created_at: str

    model_config = {"from_attributes": True}


# --- Media ---
class MediaItemOut(BaseModel):
    id: str
    name: str
    type: str
    thumbnail_url: str
    url: str
    duration: Optional[int] = None
    patient: Optional[str] = None
    created_at: str

    model_config = {"from_attributes": True}


class MediaListOut(BaseModel):
    items: list[MediaItemOut]


class PatientUpdateIn(BaseModel):
    """PUT /api/media/{media_id}/patient 的请求体；空串 / null 表示清除患者名"""
    patient: Optional[str] = None


# --- Analysis ---
class AnalysisRequest(BaseModel):
    id: str


class AnalysisResponse(BaseModel):
    task_id: str


class FaceB64Request(BaseModel):
    """对齐后人脸图的 base64（与 WebSocket 帧中 aligned_face 一致，可为裸 base64 或 data URL）"""
    image_base64: str


class FaceAnalyzeOut(BaseModel):
    bdi_score: float
    inference_time_ms: float
    heatmap_data: list[list[float]]


# --- Report ---
class ReportOut(BaseModel):
    id: int
    media_id: int
    bdi_score: float
    severity: str
    detected_at: str
    inference_time_ms: float
    notes: Optional[str] = None

    model_config = {"from_attributes": True}


# --- WebSocket frame ---
class AnalysisFrame(BaseModel):
    frame_id: int
    timestamp: float
    bdi_score: float
    aligned_face: str  # base64
    heatmap_data: list[list[float]]
    inference_time_ms: float
    progress: float


# --- Report list (joined with media) ---
class ReportListItem(BaseModel):
    id: int
    media_id: int
    media_name: str
    media_type: str
    uploader_name: Optional[str] = None
    bdi_score: float
    severity: str
    detected_at: str
    inference_time_ms: float

    model_config = {"from_attributes": True}


class ReportListOut(BaseModel):
    items: list[ReportListItem]
    total: int


# --- Stats ---
class StatsOut(BaseModel):
    total_analyses: int
    total_media: int
    severity_distribution: dict  # {"none": N, "mild": N, ...}
    avg_inference_time_ms: float
    bdi_trend: list[dict]  # [{"date": "2026-05-01", "avg_score": 18.5}, ...]
    recent_reports: list[ReportListItem]
