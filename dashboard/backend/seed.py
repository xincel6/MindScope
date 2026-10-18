"""
Seed the database with sample media entries.
Generates dummy mp4 files using OpenCV (no ffmpeg dependency needed).
Run: python seed.py
"""

import asyncio
import numpy as np
from pathlib import Path

from database import async_session, init_db
from models import MediaAsset, MediaType

MEDIA_DIR = Path(__file__).parent / "media"

SAMPLE_MEDIA = [
    {"name": "患者A_初始访谈.mp4", "type": MediaType.video, "duration": 120, "file": "patient_a.mp4"},
    {"name": "患者B_随访记录.mp4", "type": MediaType.video, "duration": 90, "file": "patient_b.mp4"},
    {"name": "匿名样本_001.mp4", "type": MediaType.video, "duration": 60, "file": "anonymous_001.mp4"},
]


def _create_dummy_video(path: Path, duration_sec: int = 10, fps: int = 24):
    """Create a minimal mp4 using OpenCV VideoWriter (no ffmpeg needed)."""
    import cv2
    fourcc = cv2.VideoWriter_fourcc(*'avc1')  # H.264
    out = cv2.VideoWriter(str(path), fourcc, fps, (640, 480))
    if not out.isOpened():
        # Fallback to MJPG
        fourcc = cv2.VideoWriter_fourcc(*'MJPG')
        out = cv2.VideoWriter(str(path.with_suffix('.avi')), fourcc, fps, (640, 480))
    total_frames = duration_sec * fps
    for i in range(total_frames):
        # Moving gradient frame for visual interest
        r = int(16 + 8 * np.sin(i * 0.05))
        g = int(24 + 8 * np.cos(i * 0.03))
        b = int(48 + 12 * np.sin(i * 0.04 + 1))
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
        frame[:] = (b, g, r)
        # Draw a moving circle as "face"
        cx = 320 + int(20 * np.sin(i * 0.1))
        cy = 240 + int(15 * np.cos(i * 0.08))
        cv2.circle(frame, (cx, cy), 100, (200, 180, 160), -1)
        cv2.circle(frame, (cx - 30, cy - 20), 12, (80, 80, 80), -1)
        cv2.circle(frame, (cx + 30, cy - 20), 12, (80, 80, 80), -1)
        cv2.ellipse(frame, (cx, cy + 30), (20, 10), 0, 0, 180, (100, 90, 90), -1)
        out.write(frame)
    out.release()
    print(f"  Created: {path} ({total_frames} frames)")


async def seed():
    await init_db()
    MEDIA_DIR.mkdir(parents=True, exist_ok=True)

    async with async_session() as db:
        for item in SAMPLE_MEDIA:
            file_path = MEDIA_DIR / item["file"]
            if not file_path.exists():
                print(f"Generating dummy video: {file_path.name}")
                _create_dummy_video(file_path, duration_sec=10)

            asset = MediaAsset(
                name=item["name"],
                # 只存文件名：DB 随仓库搬机器后绝对路径会失效（见 media_paths.py）
                file_path=file_path.name,
                type=item["type"],
                duration=item["duration"],
                thumbnail_url="",
            )
            db.add(asset)

        await db.commit()

    print("Seed complete.")


if __name__ == "__main__":
    asyncio.run(seed())
