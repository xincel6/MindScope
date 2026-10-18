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
from services.frame_plan import heatmap_for_frame, tail_plan
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
    """Image path: align face, run **one** inference, emit exactly **one** frame.

    ★ 为什么只推 1 帧（历史遗留问题的修复）：
      旧实现为了让网页端的评分曲线"有点可画"，把同一次推理的结果重复推 10 帧
      （一个 10 步的循环 + 每帧 sleep 0.2 秒）。这在客户端造成两个可见后果：
        · 一张图片看起来像"10 帧的视频"，端上分不清图片和视频；
        · 端上按"收到帧数"渲染逐帧列表/曲线时，数量随实现而变（10 → 1），
          用户看到"分析时有十帧，退出再看只剩一帧"。
      图片本来就只有一次推理，**一次推理就该只有一帧**：
      前端的"单帧图片"语义（水平直线 + 档位刻度尺）由客户端按素材类型渲染，
      不需要服务端伪造帧数。
    """
    frame_bgr = _imread_unicode(path)
    if frame_bgr is None:
        await queue.put(None)
        return

    aligned, _heatmap = await align_face(frame_bgr)
    face_b64 = _encode_base64(aligned)

    scores, inf_ms, heatmaps = await lmtformer_inference(
        [aligned] * FRAMES_PER_BATCH
    )
    score = scores[0]
    elapsed_ms = round(inf_ms, 3)

    af = AnalysisFrame(
        frame_id=1,
        timestamp=time.time(),
        bdi_score=score,
        aligned_face=face_b64,
        heatmap_data=heatmap_for_frame(heatmaps, 0),
        inference_time_ms=elapsed_ms,
        progress=1.0,
    )
    await queue.put(af)

    await queue.put(None)


async def _process_video(
    path: Path,
    task_id: str,
    queue: asyncio.Queue,
) -> None:
    """Video path: sample frames, batch by 24, stream results.

    MTCNN runs only on keyframes (every KEYFRAME_EVERY sampled frames)
    to keep latency manageable. Intermediate frames reuse the last transform.

    ★ 三条与"用户看到的帧"直接相关的规则：
      1. 每批 24 帧只跑**一次**推理，模型给的是 clip 级分数，批内 24 帧相同（段级语义）；
      2. 注意力按 12 个时间 token 拆开，每个 token 覆盖 2 帧 —— 所以批内热力图**不再全同**；
      3. 尾批不足 24 帧时，补帧只用于凑齐模型输入，**只发送真实帧**且帧号连续
         （旧实现把补帧也发出去、还按补齐后的长度倒推起点，导致重复帧 + 错号）。
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
    frame_id = 0
    read_idx = 0
    last_aligned = None
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
            aligned, _ = await align_face(frame_bgr)
            last_aligned = aligned
        else:
            aligned = last_aligned

        frame_buffer.append(aligned)
        frame_id += 1

        if len(frame_buffer) == FRAMES_PER_BATCH:
            await _flush_batch(
                queue, frame_buffer,
                frame_id - FRAMES_PER_BATCH + 1,
                total, sample_every,
            )
            frame_buffer.clear()

    # Flush remaining frames: pad only for the model input, emit real frames only
    if frame_buffer:
        plan = tail_plan(len(frame_buffer), frame_id)
        padded = list(frame_buffer)
        if plan.padding > 0:
            padded.extend([frame_buffer[-1]] * plan.padding)
        await _flush_batch(
            queue, padded,
            plan.start_id,
            total, sample_every,
            emit_count=plan.emit_count,
        )

    cap.release()
    await queue.put(None)


async def _flush_batch(
    queue: asyncio.Queue,
    faces: list[np.ndarray],
    start_id: int,
    total_frames: int,
    sample_every: int,
    emit_count: Optional[int] = None,
) -> None:
    """Run inference on one batch and push each **real** frame result to queue.

    Args:
        faces: 24 帧（尾批可能是补帧后的副本）。模型要求固定批大小。
        start_id: 本批第一条真实帧的全局帧号（1-based）。
        emit_count: 只发送前多少条；None = 全部（满批）。
                    ★ 尾批必须传真实帧数，否则会把补帧副本也发出去。
    """
    scores, inf_ms, heatmaps = await lmtformer_inference(faces)

    emit = len(faces) if emit_count is None else max(0, min(emit_count, len(faces)))
    for i in range(emit):
        face = faces[i]
        face_b64 = _encode_base64(face)

        progress = min(1.0, (start_id + i) / max(1, total_frames // sample_every))

        af = AnalysisFrame(
            frame_id=start_id + i,
            timestamp=time.time(),
            bdi_score=scores[i],
            aligned_face=face_b64,
            # 该帧所在时间片（2 帧）的热力图，不是整批共用一张
            heatmap_data=heatmap_for_frame(heatmaps, i),
            inference_time_ms=round(inf_ms, 3),
            progress=round(progress, 4),
        )
        await queue.put(af)
        await asyncio.sleep(0)
