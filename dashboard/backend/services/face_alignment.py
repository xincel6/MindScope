"""
Face detection + alignment using MTCNN.

Pipeline:
  1. MTCNN detects face bounding box + 5-point landmarks.
  2. Affine transform aligns eyes to canonical 128×128 positions.
  3. Returns aligned BGR crop + attention heatmap.
"""

from typing import Optional

import numpy as np
import cv2

# ---------------------------------------------------------------------------
# Lazy-load MTCNN once at module level (slow first-time download ~2-5s)
# ---------------------------------------------------------------------------
_mtcnn: Optional[object] = None


def _get_mtcnn():
    global _mtcnn
    if _mtcnn is None:
        from facenet_pytorch import MTCNN
        import torch
        device = 'cuda' if torch.cuda.is_available() else 'cpu'
        _mtcnn = MTCNN(
            image_size=128,
            margin=20,
            min_face_size=40,
            thresholds=[0.6, 0.7, 0.7],  # detection / RNet / ONet
            factor=0.709,
            keep_all=False,
            device=device,
        )
        print(f"[face_alignment] MTCNN loaded on {device}")
    return _mtcnn


# ---------------------------------------------------------------------------
# Canonical face positions for 128×128 (eye centres)
# ---------------------------------------------------------------------------
CANONICAL_LEFT_EYE = (38, 52)
CANONICAL_RIGHT_EYE = (90, 52)


def _affine_from_eyes(src_left: tuple, src_right: tuple, size: int = 128):
    """
    Compute similarity transform that maps source eye positions
    to canonical eye positions in a `size × size` image.
    """
    src = np.array([src_left, src_right], dtype=np.float32)
    dst = np.array([CANONICAL_LEFT_EYE, CANONICAL_RIGHT_EYE], dtype=np.float32)

    # Rotation + scale: the distance between canonical eyes is 52 px
    dx_src = src[1] - src[0]
    dx_dst = dst[1] - dst[0]
    scale = np.linalg.norm(dx_dst) / (np.linalg.norm(dx_src) + 1e-8)
    angle = np.arctan2(dx_src[1], dx_src[0]) - np.arctan2(dx_dst[1], dx_dst[0])

    # Build rotation matrix around left eye
    cos_a = np.cos(angle) * scale
    sin_a = np.sin(angle) * scale
    tx = dst[0, 0] - (cos_a * src[0, 0] - sin_a * src[0, 1])
    ty = dst[0, 1] - (sin_a * src[0, 0] + cos_a * src[0, 1])

    M = np.array([[cos_a, -sin_a, tx],
                   [sin_a,  cos_a, ty]], dtype=np.float32)
    return M


async def align_face(frame: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """
    Args:
        frame: BGR frame (H, W, 3) from video / image.

    Returns:
        aligned: (128, 128, 3) uint8 BGR aligned face.
        heatmap: (16, 16) float32 attention heatmap.
    """
    h, w = frame.shape[:2]

    try:
        mtcnn = _get_mtcnn()

        # MTCNN expects RGB
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # Detect – returns (boxes, probs, landmarks) if keep_all=False
        boxes, probs, landmarks = mtcnn.detect(frame_rgb, landmarks=True)

        if boxes is not None and len(boxes) > 0:
            # Pick best detection
            best_idx = int(np.argmax(probs))
            lm = landmarks[best_idx]  # (5, 2)  [left-eye, right-eye, nose, left-mouth, right-mouth]

            left_eye = (lm[0, 0], lm[0, 1])
            right_eye = (lm[1, 0], lm[1, 1])

            # Affine alignment
            M = _affine_from_eyes(left_eye, right_eye, 128)
            aligned_bgr = cv2.warpAffine(frame, M, (128, 128),
                                          flags=cv2.INTER_LANCZOS4,
                                          borderMode=cv2.BORDER_CONSTANT,
                                          borderValue=(0, 0, 0))

            # Generate heatmap from the detection box
            x1, y1, x2, y2 = boxes[best_idx].astype(int)
            heatmap = _box_to_heatmap(x1, y1, x2, y2, h, w, lm, 128)

            return aligned_bgr, heatmap

    except Exception as e:
        print(f"[face_alignment] MTCNN failed, falling back to centre crop: {e}")

    # Fallback: centre-crop
    return _centre_crop_fallback(frame)


# ---------------------------------------------------------------------------
# Fallback
# ---------------------------------------------------------------------------
def _centre_crop_fallback(frame: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    h, w = frame.shape[:2]
    side = min(h, w)
    y0 = (h - side) // 2
    x0 = (w - side) // 2
    crop = frame[y0:y0 + side, x0:x0 + side]
    from PIL import Image
    rgb = crop[..., ::-1]
    aligned_rgb = Image.fromarray(rgb).resize((128, 128), Image.LANCZOS)
    aligned_bgr = np.array(aligned_rgb)[..., ::-1].copy()
    heatmap = _synthetic_heatmap()
    return aligned_bgr, heatmap


# ---------------------------------------------------------------------------
# Heatmap helpers
# ---------------------------------------------------------------------------
def _box_to_heatmap(
    x1: int, y1: int, x2: int, y2: int,
    img_h: int, img_w: int,
    landmarks: Optional[np.ndarray],
    target_size: int = 16,
) -> np.ndarray:
    """Create a 16×16 attention-like heatmap from detection box and landmarks."""
    heatmap = np.zeros((target_size, target_size), dtype=np.float32)
    sx = target_size / img_w
    sy = target_size / img_h

    # Face bounding box region
    bx1 = max(0, int(x1 * sx))
    by1 = max(0, int(y1 * sy))
    bx2 = min(target_size - 1, int(x2 * sx))
    by2 = min(target_size - 1, int(y2 * sy))
    heatmap[by1:by2 + 1, bx1:bx2 + 1] = 0.6

    # Landmark hotspots (eyes, nose, mouth)
    if landmarks is not None:
        for i, (lx, ly) in enumerate(landmarks):
            hx = int(lx * sx)
            hy = int(ly * sy)
            weight = 1.0 if i < 2 else 0.7  # eyes > nose/mouth
            _add_gaussian_spot(heatmap, hx, hy, sigma=2.0, weight=weight)

    heatmap = heatmap / (heatmap.max() + 1e-8)
    return heatmap


def _add_gaussian_spot(
    heatmap: np.ndarray, cx: int, cy: int,
    sigma: float = 2.0, weight: float = 1.0,
) -> None:
    h, w = heatmap.shape
    for y in range(max(0, cy - 6), min(h, cy + 7)):
        for x in range(max(0, cx - 6), min(w, cx + 7)):
            d2 = (x - cx)**2 + (y - cy)**2
            v = weight * np.exp(-d2 / (2 * sigma**2))
            heatmap[y, x] = max(heatmap[y, x], v)


def _synthetic_heatmap() -> np.ndarray:
    """Fallback synthetic heatmap."""
    size = 16
    xs = np.linspace(-2, 2, size)
    ys = np.linspace(-2, 2, size)
    xv, yv = np.meshgrid(xs, ys)
    g1 = np.exp(-((xv - 0.6)**2 + (yv + 0.5)**2) / 0.5)
    g2 = np.exp(-((xv + 0.6)**2 + (yv + 0.5)**2) / 0.5)
    g3 = np.exp(-((xv)**2 + (yv - 0.8)**2) / 0.4)
    heatmap = (g1 + g2 + g3 * 0.7)
    heatmap = heatmap / heatmap.max()
    return heatmap.astype(np.float32)
