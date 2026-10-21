import base64
import logging

import cv2
import numpy as np
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from config import FRAMES_PER_BATCH, MEDIA_DIR
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
from services.inference import average_heatmaps, lmtformer_inference
from services.video_thumbnail import create_video_thumbnail

router = APIRouter(prefix="/api")
logger = logging.getLogger(__name__)


@router.get("/media/list", response_model=MediaListOut)
async def list_media(
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    result = await db.execute(select(MediaAsset).order_by(MediaAsset.created_at.desc()))
    assets = result.scalars().all()

    items: list[MediaItemOut] = []
    thumbnails_changed = False
    for a in assets:
        # DB 里可能是 Windows 反斜杠路径 / 别的机器上的绝对路径；
        # 统一交给 media_file_name（POSIX 的 Path.name 不认反斜杠，会返回整条字符串）
        fname = media_file_name(a.file_path)
        thumbnail_url = a.thumbnail_url or ""
        if a.type.value == "video" and not thumbnail_url:
            try:
                video_path = resolve_media_path(a.file_path)
                if video_path is not None:
                    # 封面是增强信息：生成失败只能影响这一条视频，
                    # 不能让整个素材库接口变成 500。
                    thumbnail_url = create_video_thumbnail(video_path, MEDIA_DIR)
                    if thumbnail_url:
                        a.thumbnail_url = thumbnail_url
                        thumbnails_changed = True
            except Exception:
                logger.exception("生成视频首帧失败 · media_id=%s", a.id)
                thumbnail_url = ""
        items.append(MediaItemOut(
            id=str(a.id),
            name=a.name,
            type=a.type.value,
            thumbnail_url=thumbnail_url,
            url=f"/media/{fname}" if fname else "",
            duration=a.duration,
            patient=a.patient,
            created_at=a.created_at.strftime("%Y-%m-%d"),
        ))

    if thumbnails_changed:
        try:
            await db.commit()
        except Exception:
            logger.exception("保存视频首帧地址失败 · 本次仍然返回已生成的封面")
            try:
                await db.rollback()
            except Exception:
                logger.exception("回滚视频首帧数据库事务失败")
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
        thumbnail_path = file_path.with_name(f"{file_path.stem}.thumb.jpg")
        for path in (file_path, thumbnail_path):
            try:
                path.unlink(missing_ok=True)
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
    scores, ms, heatmaps = await lmtformer_inference(faces)
    return FaceAnalyzeOut(
        bdi_score=float(scores[0]),
        inference_time_ms=float(ms),
        # 单张脸没有"时间"可言：把 12 个时间 token 平均回一张，口径与旧版一致
        heatmap_data=average_heatmaps(heatmaps),
    )
