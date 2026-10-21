import asyncio
import logging
import uuid
import shutil
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from config import MEDIA_DIR
from database import get_db
from deps import get_current_user
from face_detect import process_uploaded_image_with_mtcnn
from models import MediaAsset, MediaType, User
from services.video_thumbnail import create_video_thumbnail

router = APIRouter(prefix="/api")
logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".mp4", ".avi", ".mov", ".webm"}


@router.post("/upload/image")
async def upload_image(
    file: UploadFile = File(...),
    patient: Optional[str] = Query(None, description="所属患者名（可选，最长 64 字符）"),
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    ext = Path(file.filename or "upload.jpg").suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"不支持的文件格式: {ext}")

    patient_name = (patient or "").strip()
    if len(patient_name) > 64:
        raise HTTPException(status_code=400, detail="患者名最长 64 个字符")

    # Save file with unique name
    unique_name = f"{uuid.uuid4().hex}{ext}"
    dest = MEDIA_DIR / unique_name
    with dest.open("wb") as f:
        shutil.copyfileobj(file.file, f)

    # Determine media type
    media_type = MediaType.video if ext in {".mp4", ".avi", ".mov", ".webm"} else MediaType.image

    # 图片：MTCNN 人脸检测并提取人脸区域为新图像，供后续抑郁检测使用
    if media_type == MediaType.image:
        await process_uploaded_image_with_mtcnn(dest)

    thumbnail_url = ""
    if media_type == MediaType.video:
        try:
            thumbnail_url = await asyncio.to_thread(create_video_thumbnail, dest, MEDIA_DIR)
        except Exception:
            # 首帧只是列表展示增强，不能导致视频本身上传失败。
            logger.exception("上传视频后生成首帧失败 · file=%s", unique_name)
            thumbnail_url = ""

    # Create DB record
    # ★ 只存文件名，不存绝对路径：depression.db 会随仓库/备份在 Windows 与 Linux
    #   之间搬动，绝对路径一换机器就失效（见 media_paths.py 的说明）。
    asset = MediaAsset(
        name=file.filename or unique_name,
        uploader_name=_user.username,
        patient=patient_name or None,
        file_path=unique_name,
        type=media_type,
        duration=None,
        thumbnail_url=thumbnail_url,
    )
    db.add(asset)
    await db.commit()
    await db.refresh(asset)

    return {
        "id": str(asset.id),
        "name": asset.name,
        "type": asset.type.value,
        "url": f"/media/{unique_name}",
        "thumbnail_url": thumbnail_url,
        "patient": asset.patient or "",
    }
