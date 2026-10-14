"""
MTCNN 人脸检测与人脸图提取（用于本地上传、在线拍照等图片素材）。

实现流程：
1. 使用与 `services.face_alignment` 相同的 **facenet_pytorch.MTCNN** 检测人脸（框 + 5 点特征点）；
2. 通过仿射变换将人脸对齐为 128×128，与抑郁检测模型输入一致；
3. 将结果覆盖写回上传文件路径，供后续 `frame_processor` 读图并做抑郁分析。

说明：不依赖旧版 `pip install mtcnn`（TensorFlow）包，避免与当前推理栈重复。
"""

import logging
from pathlib import Path
from typing import Optional, Tuple, List
import cv2
import numpy as np

logger = logging.getLogger(__name__)


# OpenCV 在 Windows 上对中文路径的 imread/imwrite 会失败，这里改用 Unicode 安全写法。
def _imread_unicode(path: str):
    data = np.fromfile(str(path), dtype=np.uint8)
    if data.size == 0:
        return None
    return cv2.imdecode(data, cv2.IMREAD_COLOR)


def _imwrite_unicode(path: str, img: np.ndarray, params: Optional[List[int]] = None) -> bool:
    ext = Path(path).suffix
    ok, buf = cv2.imencode(ext, img, params or [])
    if ok:
        buf.tofile(str(path))
    return ok


async def process_uploaded_image_with_mtcnn(file_path: str) -> bool:
    """
    对刚保存的上传图片做人脸检测（MTCNN）并提取对齐人脸图，覆盖原文件。

    本地选图与前端在线拍照均为同一 `/api/upload/image` 入口，保存后自动调用本函数。

    Args:
        file_path: 磁盘上的图片路径（一般为 MEDIA_DIR 下的 uuid 文件名）。

    Returns:
        成功写回人脸图为 True；失败时保留原图并返回 False（不阻断上传）。
    """
    from services.face_alignment import align_face

    p = Path(file_path)
    if not p.is_file():
        logger.warning("[face_detect] 文件不存在: %s", p)
        return False

    frame_bgr = _imread_unicode(str(p))
    if frame_bgr is None:
        logger.warning("[face_detect] 无法解码图片: %s", p)
        return False

    try:
        # MTCNN 检测 + 关键点对齐 → 128×128 BGR 人脸图
        face_bgr, _heatmap = await align_face(frame_bgr)
    except Exception as e:
        logger.warning("[face_detect] MTCNN/align_face 失败，保留原图: %s", e)
        return False

    ext = p.suffix.lower()
    encode_params: List[int] = []
    if ext in {".jpg", ".jpeg"}:
        encode_params = [int(cv2.IMWRITE_JPEG_QUALITY), 92]
    elif ext == ".png":
        encode_params = [int(cv2.IMWRITE_PNG_COMPRESSION), 3]

    ok = _imwrite_unicode(str(p), face_bgr, encode_params)
    if not ok:
        logger.warning("[face_detect] 写回文件失败: %s", p)
        return False

    logger.info("[face_detect] 已用人脸图替换上传文件: %s", p.name)
    return True


async def extract_face_for_analysis(
    frame_bgr: np.ndarray,
) -> Tuple[Optional[np.ndarray], bool]:
    """
    对内存中的 BGR 图像做人脸检测并返回对齐后人脸图，便于测试或其它模块复用。

    Returns:
        (face_bgr 为 128×128 BGR，失败时为 None, 是否成功)
    """
    from services.face_alignment import align_face

    try:
        face_bgr, _ = await align_face(frame_bgr)
        return face_bgr, True
    except Exception as e:
        logger.warning("[face_detect] extract_face_for_analysis: %s", e)
        return None, False
