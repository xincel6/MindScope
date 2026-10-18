import base64

import cv2
import numpy as np
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from config import FRAMES_PER_BATCH
from database import get_db
from deps import get_current_user
from media_paths import media_file_name, resolve_media_path
from models import DiagnosisReport, MediaAsset, User
from schemas import (
    AnalysisRequest,
    AnalysisResponse,
    FaceAnalyzeOut,
    FaceB64Request,
    MediaItemOut,
    MediaListOut,
    PatientUpdateIn,
)
from services.inference import lmtformer_inference

router = APIRouter(prefix="/api")


@router.get("/media/list", response_model=MediaListOut)
async def list_media(
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    result = await db.execute(select(MediaAsset).order_by(MediaAsset.created_at.desc()))
    assets = result.scalars().all()

    items: list[MediaItemOut] = []
    for a in assets:
        # DB 里可能是 Windows 反斜杠路径 / 别的机器上的绝对路径；
        # 统一交给 media_file_name（POSIX 的 Path.name 不认反斜杠，会返回整条字符串）
        fname = media_file_name(a.file_path)
        items.append(MediaItemOut(
            id=str(a.id),
            name=a.name,
            type=a.type.value,
            thumbnail_url=a.thumbnail_url or "",
            url=f"/media/{fname}" if fname else "",
            duration=a.duration,
            patient=a.patient,
            created_at=a.created_at.strftime("%Y-%m-%d"),
        ))

    return MediaListOut(items=items)


@router.delete("/media/{media_id}")
async def delete_media(
    media_id: str,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    try:
        pk = int(media_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="无效的资源 ID")

    result = await db.execute(select(MediaAsset).where(MediaAsset.id == pk))
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="资源不存在")

    # 记录里的路径可能来自别的机器；按文件名回到本机 MEDIA_DIR 找真实文件
    file_path = resolve_media_path(asset.file_path)
    await db.execute(delete(DiagnosisReport).where(DiagnosisReport.media_id == pk))
    await db.execute(delete(MediaAsset).where(MediaAsset.id == pk))
    await db.commit()

    if file_path is not None:
        try:
            file_path.unlink()
        except OSError:
            pass

    return {"ok": True}


@router.put("/media/{media_id}/patient")
async def update_media_patient(
    media_id: str,
    req: PatientUpdateIn,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    """给素材命名 / 改所属患者；空串或 null 表示清除。"""
    try:
        pk = int(media_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="无效的资源 ID")

    patient = (req.patient or "").strip()
    if len(patient) > 64:
        raise HTTPException(status_code=400, detail="患者名最长 64 个字符")

    result = await db.execute(select(MediaAsset).where(MediaAsset.id == pk))
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="资源不存在")

    asset.patient = patient or None
    await db.commit()
    return {"ok": True, "patient": asset.patient or ""}


@router.post("/analyze", response_model=AnalysisResponse)
async def analyze_media(
    req: AnalysisRequest,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(MediaAsset).where(MediaAsset.id == int(req.id))
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Media not found")
    # Analysis is triggered via WebSocket; return task_id for tracking
    return AnalysisResponse(task_id=req.id)


def _b64_to_aligned_face_bgr(raw: str) -> np.ndarray:
    """Decode JPEG/PNG base64 → BGR 128×128 (aligned face crop)."""
    s = raw.strip()
    if "base64," in s:
        s = s.split("base64,", 1)[1]
    try:
        data = base64.b64decode(s)
    except Exception as e:
        raise ValueError(f"无效 base64: {e}") from e
    arr = np.frombuffer(data, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("无法解码为人脸图像")
    if img.shape[0] != 128 or img.shape[1] != 128:
        img = cv2.resize(img, (128, 128), interpolation=cv2.INTER_AREA)
    return img


@router.post("/analyze/face", response_model=FaceAnalyzeOut)
async def analyze_single_face(
    req: FaceB64Request,
    _user: User = Depends(get_current_user),
):
    """
    对已对齐的人脸图（128×128）做单次 LMTformer 推理。
    输入与实时帧中的 aligned_face 相同；模型需要 24 帧输入，故复制同一帧。
    """
    try:
        face = _b64_to_aligned_face_bgr(req.image_base64)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    faces = [face] * FRAMES_PER_BATCH
    scores, ms, heatmap = await lmtformer_inference(faces)
    return FaceAnalyzeOut(
        bdi_score=float(scores[0]),
        inference_time_ms=float(ms),
        heatmap_data=heatmap,
    )
