"""
Frame-level processing pipeline: video decode → face alignment → inference.

This module reads a video file frame-by-frame, runs the alignment +
inference pipeline, and yields AnalysisFrame results suitable for
streaming over WebSocket.
"""

import asyncio
import base64
import shutil
import tempfile
import time
from io import BytesIO
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
from PIL import Image

from config import FRAMES_PER_BATCH, FACE_SIZE, TARGET_INFERENCE_MS
from schemas import AnalysisFrame
from services.face_alignment import align_face
from services.inference import lmtformer_inference


# ---------------------------------------------------------------------------
# OpenCV 文件 I/O 的 Unicode 安全封装
# cv2.imread / imwrite / VideoCapture 在 Windows 上走 8 位 ANSI 接口，
# 遇到含中文等非 ASCII 字符的路径会返回 None / False / 打不开。
# ---------------------------------------------------------------------------
def _has_non_ascii(path) -> bool:
    return any(ord(ch) > 127 for ch in str(path))


def _imread_unicode(path):
    """cv2.imread 的安全替代（支持中文路径）。"""
    p = str(path)
    if not _has_non_ascii(p):
        return cv2.imread(p)
    return cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)


def _video_capture(path):
    """cv2.VideoCapture 的安全替代（中文路径时复制到 ASCII 临时文件再打开）。"""
    p = str(path)
    cap = cv2.VideoCapture(p)
    if cap.isOpened():
        return cap
    if _has_non_ascii(p):
        cap.release()
        suffix = Path(p).suffix or ".mp4"
        tmp = tempfile.NamedTemporaryFile(suffix=suffix, delete=False)
        tmp_name = tmp.name
        tmp.close()
        shutil.copyfile(p, tmp_name)
        return cv2.VideoCapture(tmp_name)
    return cap


def _encode_base64(bgr: np.ndarray) -> str:
    """Encode BGR numpy array (128,128,3) → base64 JPEG string."""
    rgb = bgr[..., ::-1]
    img = Image.fromarray(rgb)
    buf = BytesIO()
    img.save(buf, format="JPEG", quality=75)
    return base64.b64encode(buf.getvalue()).decode()


def _get_total_frames(cap: cv2.VideoCapture) -> int:
    count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    return count if count > 0 else FRAMES_PER_BATCH * 5  # fallback for live streams


async def process_media(
    media_path: Path,
    media_type: str,
    task_id: str,
) -> asyncio.Queue[Optional[AnalysisFrame]]:
    """
    Process a media file asynchronously, pushing AnalysisFrame dicts into a queue.

    Args:
        media_path: absolute path to video or image file.
        media_type: "video" or "image".
        task_id: unique task identifier.

    Returns:
        asyncio.Queue that receives AnalysisFrame dicts; a None sentinel
        signals completion.
    """
    queue: asyncio.Queue[Optional[AnalysisFrame]] = asyncio.Queue()

    if media_type == "image":
        await _process_image(media_path, task_id, queue)
    else:
        await _process_video(media_path, task_id, queue)

    return queue


async def _process_image(
    path: Path,
    task_id: str,
    queue: asyncio.Queue,
) -> None:
    """Image path: align face, run inference, emit multiple frames for chart."""
    frame_bgr = _imread_unicode(path)
    if frame_bgr is None:
        await queue.put(None)
        return

    aligned, _heatmap = await align_face(frame_bgr)
    face_b64 = _encode_base64(aligned)

    t0 = time.perf_counter()
    scores, inf_ms, attn_heatmap = await lmtformer_inference(
        [aligned] * FRAMES_PER_BATCH
    )
    score = scores[0]
    elapsed_ms = round(inf_ms, 3)

    # Emit 10 frames over ~2 seconds so the emotion curve is visible
    steps = 10
    for i in range(1, steps + 1):
        progress = i / steps
        af = AnalysisFrame(
            frame_id=i,
            timestamp=time.time(),
            bdi_score=score,
            aligned_face=face_b64,
            heatmap_data=attn_heatmap,
            inference_time_ms=elapsed_ms,
            progress=progress,
        )
        await queue.put(af)
        if i < steps:
            await asyncio.sleep(0.2)

    await queue.put(None)


async def _process_video(
    path: Path,
    task_id: str,
    queue: asyncio.Queue,
) -> None:
    """Video path: sample frames, batch by 24, stream results.

    MTCNN runs only on keyframes (every KEYFRAME_INTERVAL sampled frames)
    to keep latency manageable. Intermediate frames reuse the last transform.
    """
    cap = _video_capture(path)
    if not cap.isOpened():
        await queue.put(None)
        return

    total = _get_total_frames(cap)
    # Sample ~60 frames total for real-time responsiveness
    sample_every = max(1, total // 60)
    KEYFRAME_EVERY = 10  # re-detect face every 10 sampled frames

    frame_buffer: list[np.ndarray] = []
    heatmap_buffer: list[np.ndarray] = []
    frame_id = 0
    read_idx = 0
    last_aligned = None
    last_heatmap = None
    sampled_count = 0

    while True:
        ret, frame_bgr = cap.read()
        if not ret:
            break

        read_idx += 1
        if read_idx % sample_every != 0:
            continue

        sampled_count += 1

        # Full MTCNN detection only on keyframes
        if sampled_count % KEYFRAME_EVERY == 1 or last_aligned is None:
            aligned, heatmap = await align_face(frame_bgr)
            last_aligned = aligned
            last_heatmap = heatmap
        else:
            aligned = last_aligned
            heatmap = last_heatmap

        frame_buffer.append(aligned)
        heatmap_buffer.append(heatmap)
        frame_id += 1

        if len(frame_buffer) == FRAMES_PER_BATCH:
            await _flush_batch(
                queue, frame_buffer, heatmap_buffer,
                frame_id - FRAMES_PER_BATCH + 1,
                total, sample_every,
            )
            frame_buffer.clear()
            heatmap_buffer.clear()

    # Flush remaining frames (pad with duplicates if needed)
    if frame_buffer:
        while len(frame_buffer) < FRAMES_PER_BATCH:
            frame_buffer.append(frame_buffer[-1])
            heatmap_buffer.append(heatmap_buffer[-1])
        await _flush_batch(
            queue, frame_buffer, heatmap_buffer,
            frame_id - len(frame_buffer) + 1,
            total, sample_every,
        )

    cap.release()
    await queue.put(None)


async def _flush_batch(
    queue: asyncio.Queue,
    faces: list[np.ndarray],
    heatmaps: list[np.ndarray],
    start_id: int,
    total_frames: int,
    sample_every: int,
) -> None:
    """Run inference on a batch and push each frame result to queue."""
    scores, inf_ms, attn_heatmap = await lmtformer_inference(faces)

    for i, (face, score) in enumerate(zip(faces, scores)):
        face_b64 = _encode_base64(face)

        progress = min(1.0, (start_id + i) / max(1, total_frames // sample_every))

        af = AnalysisFrame(
            frame_id=start_id + i,
            timestamp=time.time(),
            bdi_score=score,
            aligned_face=face_b64,
            heatmap_data=attn_heatmap,
            inference_time_ms=round(inf_ms, 3),
            progress=round(progress, 4),
        )
        await queue.put(af)
        await asyncio.sleep(0)
