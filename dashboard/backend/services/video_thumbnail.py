"""Generate a stable still-cover image from the first decodable video frame."""

import shutil
import tempfile
from pathlib import Path

import cv2


def _has_non_ascii(path: Path) -> bool:
    return any(ord(ch) > 127 for ch in str(path))


def _open_capture(path: Path) -> tuple[cv2.VideoCapture, Path | None]:
    """Open with Unicode-safe fallback for OpenCV's platform-dependent path handling."""
    direct = cv2.VideoCapture(str(path))
    if direct.isOpened() or not _has_non_ascii(path):
        return direct, None

    direct.release()
    suffix = path.suffix or ".mp4"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp_path = Path(tmp.name)
    shutil.copyfile(path, tmp_path)
    return cv2.VideoCapture(str(tmp_path)), tmp_path


def create_video_thumbnail(video_path: Path, media_dir: Path) -> str:
    """
    Return the public URL for a video's opening frame.

    The cover file is deterministic, so repeated media-list requests are cheap
    and existing records can be backfilled without another database column.
    """
    if not video_path.is_file():
        return ""

    thumbnail_path = media_dir / f"{video_path.stem}.thumb.jpg"
    if thumbnail_path.is_file() and thumbnail_path.stat().st_size > 0:
        return f"/media/{thumbnail_path.name}"

    cap = None
    temporary_path = None
    try:
        cap, temporary_path = _open_capture(video_path)
        if not cap.isOpened():
            return ""
        ok, frame = cap.read()
        if not ok or frame is None:
            return ""

        height, width = frame.shape[:2]
        max_side = max(height, width)
        if max_side > 512:
            scale = 512 / max_side
            frame = cv2.resize(
                frame,
                (max(1, round(width * scale)), max(1, round(height * scale))),
                interpolation=cv2.INTER_AREA,
            )

        encoded, buffer = cv2.imencode(
            ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 82]
        )
        if not encoded:
            return ""
        buffer.tofile(str(thumbnail_path))
        return f"/media/{thumbnail_path.name}"
    except Exception:
        # A corrupt/unsupported video must not break the whole media list.
        return ""
    finally:
        if cap is not None:
            cap.release()
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
