import asyncio
import datetime
import json
import time
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from jose import JWTError
from sqlalchemy import select

from auth_utils import decode_access_token
from database import async_session
from models import MediaAsset, DiagnosisReport, SeverityLevel, User
from services.frame_processor import process_media
from services.vlm import call_vlm_image, call_vlm_video
from config import MEDIA_DIR

router = APIRouter()


def _severity(score: float) -> SeverityLevel:
    if score <= 13:
        return SeverityLevel.none
    if score <= 19:
        return SeverityLevel.mild
    if score <= 28:
        return SeverityLevel.moderate
    return SeverityLevel.severe


async def _verify_ws_token(ws: WebSocket) -> Optional[User]:
    token = ws.query_params.get("token")
    if not token:
        return None
    try:
        payload = decode_access_token(token)
        user_id = int(payload.get("sub", 0))
    except (JWTError, ValueError, TypeError):
        return None
    async with async_session() as db:
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if user and user.is_active:
            return user
    return None


@router.websocket("/ws/analysis")
async def ws_analysis(ws: WebSocket):
    user = await _verify_ws_token(ws)
    if not user:
        await ws.close(code=1008, reason="Unauthorized")
        return

    await ws.accept()

    # Wait for client to send the media id
    try:
        init_msg = await asyncio.wait_for(ws.receive_text(), timeout=15.0)
        payload = json.loads(init_msg)
        media_id = payload.get("id") or payload.get("media_id")
    except asyncio.TimeoutError:
        await ws.send_json({"type": "error", "message": "No media id received"})
        await ws.close()
        return

    if not media_id:
        await ws.send_json({"type": "error", "message": "media_id required"})
        await ws.close()
        return

    # Look up media asset
    async with async_session() as db:
        result = await db.execute(
            select(MediaAsset).where(MediaAsset.id == int(media_id))
        )
        asset = result.scalar_one_or_none()

    if not asset:
        await ws.send_json({"type": "error", "message": "Media not found"})
        await ws.close()
        return

    # Build full path（DB 可能存绝对路径或 Windows 反斜杠路径）
    fp = Path(asset.file_path)
    media_path = fp if fp.is_file() else MEDIA_DIR / fp.name
    if not media_path.exists():
        await ws.send_json({"type": "error", "message": f"File not found: {media_path}"})
        await ws.close()
        return

    # Send ack
    await ws.send_json({"type": "status", "message": "analysis_started", "task_id": str(asset.id)})

    # Start processing
    queue = await process_media(media_path, asset.type.value, str(asset.id))

    final_score = 0.0
    final_inf_ms = 0.0
    last_face_b64 = ""
    # Video: collect faces at 25% / 50% / 75% / 100% progress
    video_faces: list[str] = []
    _video_milestones = {0.25: False, 0.50: False, 0.75: False, 1.0: False}

    try:
        while True:
            frame = await queue.get()
            if frame is None:
                break

            # Push frame to client
            await ws.send_json(frame.model_dump())

            # Track final values
            final_score = frame.bdi_score
            final_inf_ms = frame.inference_time_ms
            last_face_b64 = frame.aligned_face

            # Collect faces at milestone progress points (for video VLM)
            for ms, captured in _video_milestones.items():
                if not captured and frame.progress >= ms:
                    video_faces.append(frame.aligned_face)
                    _video_milestones[ms] = True

            # Check for client cancel
            try:
                data = await asyncio.wait_for(ws.receive_text(), timeout=0.01)
                if data:
                    msg = json.loads(data)
                    if msg.get("type") == "cancel":
                        break
            except asyncio.TimeoutError:
                pass

    except WebSocketDisconnect:
        pass
    except Exception as e:
        await ws.send_json({"type": "error", "message": str(e)})
    finally:
        # Persist diagnosis report
        if final_score > 0:
            async with async_session() as db:
                report = DiagnosisReport(
                    media_id=asset.id,
                    bdi_score=round(final_score, 2),
                    severity=_severity(final_score),
                    detected_at=datetime.datetime.now(),
                    inference_time_ms=round(final_inf_ms, 3),
                )
                db.add(report)
                await db.commit()

        # Drain queue
        while not queue.empty():
            queue.get_nowait()

        # VLM facial interpretation (non-critical — ignore failures)
        vlm_text = ""
        if last_face_b64 and final_score > 0:
            try:
                if asset.type.value == "video" and len(video_faces) >= 3:
                    vlm_text = await call_vlm_video(video_faces[:3], final_score)
                else:
                    vlm_text = await call_vlm_image(last_face_b64, final_score)
            except Exception:
                pass

        try:
            if vlm_text:
                await ws.send_json({"type": "vlm_analysis", "content": vlm_text})
            await ws.send_json({"type": "done", "final_score": final_score})
            await ws.close()
        except Exception:
            pass
