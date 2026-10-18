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

# 等待首条（带 media id 的）消息的最长时间；期间的心跳不会重置这个期限
FIRST_MESSAGE_TIMEOUT = 60.0


def _severity(score: float) -> SeverityLevel:
    if score <= 13:
        return SeverityLevel.none
    if score <= 19:
        return SeverityLevel.mild
    if score <= 28:
        return SeverityLevel.moderate
    return SeverityLevel.severe


async def _safe_send_json(ws: WebSocket, payload: dict) -> bool:
    """发送失败（客户端已经走了）时返回 False 而不是抛异常。

    uvicorn 在连接断开后调用 send 会抛 ClientDisconnected（OSError 子类），
    这类异常冒泡出去就是一条 ERROR 堆栈——那是正常的连接生命周期，不该报错。
    """
    try:
        await ws.send_json(payload)
        return True
    except (WebSocketDisconnect, RuntimeError, OSError):
        return False


async def _safe_close(ws: WebSocket) -> None:
    try:
        await ws.close()
    except (RuntimeError, OSError):
        pass


async def _verify_ws_token(ws: WebSocket) -> Optional[User]:
    # ★ token 不再放 URL（?token=…），改由子协议头携带：
    #   客户端握手时发送 Sec-WebSocket-Protocol: auth.<jwt>
    #   服务端校验通过后 accept(subprotocol=…) 回显同一子协议，完成握手。
    #   这样 token 不进入访问日志 / 代理日志 / 反向代理的 URL 记录。
    token = _token_from_subprotocol(ws)
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


def _token_from_subprotocol(ws: WebSocket) -> Optional[str]:
    """从 Sec-WebSocket-Protocol 头里解析 `auth.<jwt>` 形态的子协议。"""
    header = ws.headers.get("sec-websocket-protocol")
    if not header:
        return None
    # 客户端可能一次声明多个子协议（逗号分隔），逐个找 `auth.` 前缀的那个
    for part in header.split(","):
        proto = part.strip()
        if proto.startswith("auth."):
            return proto[len("auth."):]
    return None


@router.websocket("/ws/analysis")
async def ws_analysis(ws: WebSocket):
    token = _token_from_subprotocol(ws)
    user = await _verify_ws_token(ws)
    if not user or not token:
        await ws.close(code=1008, reason="Unauthorized")
        return

    # 回显同一子协议，完成握手（否则部分客户端会因子协议未被确认而断开）
    await ws.accept(subprotocol=f"auth.{token}")

    # 等客户端发来首条带 media id 的消息。
    #   - 心跳 {"type": "ping"} 之类的无关消息直接跳过，不打断等待
    #   - 客户端在开始分析前就断开（刷新/切页/关标签页 → close code 1005）属于正常
    #     连接生命周期，安静返回即可，不该变成一条 ASGI ERROR 堆栈
    deadline = time.monotonic() + FIRST_MESSAGE_TIMEOUT
    media_id: Optional[int] = None
    while media_id is None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            await _safe_send_json(ws, {"type": "error", "message": "No media id received"})
            await _safe_close(ws)
            return

        try:
            init_msg = await asyncio.wait_for(ws.receive_text(), timeout=remaining)
        except asyncio.TimeoutError:
            await _safe_send_json(ws, {"type": "error", "message": "No media id received"})
            await _safe_close(ws)
            return
        except WebSocketDisconnect:
            return
        except Exception:  # 协议层异常，同样安静退出
            return

        try:
            payload = json.loads(init_msg)
        except (TypeError, ValueError):
            continue  # 收到非法 JSON 不足以判定失败，继续等
        if not isinstance(payload, dict):
            continue
        if payload.get("type") == "ping":
            continue  # 前端心跳，静默忽略（回 pong 会被前端当成一帧数据）

        candidate = payload.get("id") or payload.get("media_id")
        if not candidate:
            continue
        try:
            media_id = int(candidate)
        except (TypeError, ValueError):
            await _safe_send_json(ws, {"type": "error", "message": "invalid media_id"})
            await _safe_close(ws)
            return

    # Look up media asset
    async with async_session() as db:
        result = await db.execute(
            select(MediaAsset).where(MediaAsset.id == media_id)
        )
        asset = result.scalar_one_or_none()

    if not asset:
        await _safe_send_json(ws, {"type": "error", "message": "Media not found"})
        await _safe_close(ws)
        return

    # Build full path（DB 可能存绝对路径或 Windows 反斜杠路径）
    fp = Path(asset.file_path)
    media_path = fp if fp.is_file() else MEDIA_DIR / fp.name
    if not media_path.exists():
        await _safe_send_json(ws, {"type": "error", "message": f"File not found: {media_path}"})
        await _safe_close(ws)
        return

    # Send ack
    if not await _safe_send_json(
        ws, {"type": "status", "message": "analysis_started", "task_id": str(asset.id)}
    ):
        return  # 客户端已经断开，不必再跑模型

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

            # Push frame to client（客户端已走就直接收工，别再空跑）
            if not await _safe_send_json(ws, frame.model_dump()):
                break

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
                    try:
                        msg = json.loads(data)
                    except (TypeError, ValueError):
                        msg = {}
                    if isinstance(msg, dict) and msg.get("type") == "cancel":
                        break
            except asyncio.TimeoutError:
                pass
            except WebSocketDisconnect:
                break  # 客户端中途断开，正常收尾（finally 里落库）

    except WebSocketDisconnect:
        pass
    except Exception as e:
        await _safe_send_json(ws, {"type": "error", "message": str(e)})
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
                await _safe_send_json(ws, {"type": "vlm_analysis", "content": vlm_text})
            await _safe_send_json(ws, {"type": "done", "final_score": final_score})
            await _safe_close(ws)
        except Exception:
            pass
