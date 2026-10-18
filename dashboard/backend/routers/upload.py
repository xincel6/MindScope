import uuid
import shutil
from pathlib import Path

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from config import MEDIA_DIR
from database import get_db
from deps import get_current_user
from face_detect import process_uploaded_image_with_mtcnn
from models import MediaAsset, MediaType, User

router = APIRouter(prefix="/api")

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".mp4", ".avi", ".mov", ".webm"}


@router.post("/upload/image")
async def upload_image(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    ext = Path(file.filename or "upload.jpg").suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"不支持的文件格式: {ext}")

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

    # Create DB record
    asset = MediaAsset(
        name=file.filename or unique_name,
        uploader_name=_user.username,
        file_path=str(dest),
        type=media_type,
        duration=None,
        thumbnail_url="",
    )
    db.add(asset)
    await db.commit()
    await db.refresh(asset)

    return {
        "id": str(asset.id),
        "name": asset.name,
        "type": asset.type.value,
        "url": f"/media/{unique_name}",
    }
