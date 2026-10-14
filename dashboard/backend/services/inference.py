"""
LMTformer inference service.

Interface contract:
    lmtformer_inference(faces: list[np.ndarray]) -> tuple[list[float], float]

    Input:  list of 24 aligned face crops, each (128, 128, 3) uint8 BGR.
    Output: list of 24 BDI-II scores (float, 0–63), one per frame, and
            inference wall time in milliseconds.
"""

import sys
import time
from typing import Optional

import numpy as np

from config import FRAMES_PER_BATCH, MODEL_CHECKPOINT, MODEL_SOURCE_DIR

# ---------------------------------------------------------------------------
# Lazy-load the model once at module level
# ---------------------------------------------------------------------------
_model: Optional[object] = None
_device: Optional[object] = None


def _load_model():
    """Load LMTformer with multi-GPU checkpoint handling. Called once."""
    global _model, _device

    import torch

    # Add project root to path so LMTformer_model/ is importable
    if MODEL_SOURCE_DIR not in sys.path:
        sys.path.insert(0, MODEL_SOURCE_DIR)

    from LMTformer_model.LMTformer import LMTformer

    _device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    _model = LMTformer(
        image_size=(24, 128, 128),
        patches=(2, 4, 4),
        dim=32,
        num_heads=4,
        num_layers=12,
        dropout_rate=0.1,
        device=_device,
    ).to(_device)

    checkpoint = torch.load(MODEL_CHECKPOINT, map_location=_device, weights_only=False)
    new_state_dict = {}
    for k, v in checkpoint.items():
        new_key = k.replace(".module.", ".")
        new_state_dict[new_key] = v
    _model.load_state_dict(new_state_dict)
    _model.eval()

    print(f"[inference] LMTformer loaded on {_device} ({len(new_state_dict)} params)")


# ---------------------------------------------------------------------------
# Preprocessing — identical to training pipeline
# ---------------------------------------------------------------------------
_MEAN = np.array([[[90.0, 98.0, 102.0]]], dtype=np.float32)  # BGR channel mean


def _preprocess(faces: list[np.ndarray]):
    """Convert 24 BGR frames (128,128,3) → tensor [1, 3, 24, 128, 128]."""
    import torch

    # Stack frames → (24, 128, 128, 3), convert to float32
    buffer = np.stack([f.astype(np.float32) for f in faces], axis=0)

    # Normalise with training mean
    buffer -= _MEAN

    # Transpose: (24, 128, 128, 3) → (3, 24, 128, 128)
    buffer = buffer.transpose((3, 0, 1, 2))

    # Add batch dim → (1, 3, 24, 128, 128), convert to tensor
    tensor = torch.from_numpy(buffer).unsqueeze(0).to(_device)
    return tensor


# ---------------------------------------------------------------------------
# Attention heatmap extraction
# ---------------------------------------------------------------------------
def _extract_attention_heatmap(scores_tensor) -> list[list[float]]:
    """
    Extract spatial attention from the last transformer layer's self-attention scores.

    scores_tensor: [B, h, 192, 192] — 192 patches = 12 frames × 4×4 spatial.
    Returns: 16×16 heatmap (upsampled from 4×4 per-frame spatial attention).
    """
    # Average across attention heads
    attn = scores_tensor.mean(dim=1)  # [B, 192, 192]

    # Average attention received by each patch (as key) from all queries
    attn = attn.mean(dim=1)  # [B, 192]

    # Take first batch item
    attn = attn[0]  # [192]

    # Reshape: 12 frames × 4×4 spatial
    attn = attn.view(12, 4, 4)  # [12, 4, 4]

    # Average across temporal dimension → purely spatial attention
    attn = attn.mean(dim=0)  # [4, 4]

    # Convert to numpy and normalise to [0, 1]
    attn_np = attn.cpu().numpy()
    attn_np = (attn_np - attn_np.min()) / (attn_np.max() - attn_np.min() + 1e-8)

    # Upsample 4×4 → 16×16 for frontend display
    import cv2
    up = cv2.resize(attn_np, (16, 16), interpolation=cv2.INTER_CUBIC)
    # Re-normalise after resize
    up = (up - up.min()) / (up.max() - up.min() + 1e-8)

    return up.tolist()


# ---------------------------------------------------------------------------
# Public API (async-safe — call from FastAPI event loop)
# ---------------------------------------------------------------------------
async def lmtformer_inference(
    faces: list[np.ndarray],
    seed: Optional[float] = None,
) -> tuple[list[float], float, list[list[float]]]:
    assert len(faces) == FRAMES_PER_BATCH, (
        f"Expected {FRAMES_PER_BATCH} frames, got {len(faces)}"
    )

    import torch

    if _model is None:
        _load_model()

    t0 = time.perf_counter()

    tensor = _preprocess(faces)

    with torch.no_grad():
        score = _model(tensor).item()

    elapsed_ms = (time.perf_counter() - t0) * 1000

    # Extract attention heatmap from the last transformer block's self-attention
    try:
        last_attn_module = _model.transformer3.blocks[-1].attn
        if last_attn_module.scores is not None:
            attn_heatmap = _extract_attention_heatmap(last_attn_module.scores)
        else:
            attn_heatmap = [[0.0] * 16 for _ in range(16)]
    except Exception:
        attn_heatmap = [[0.0] * 16 for _ in range(16)]

    # Model outputs one clip-level score — assign to all 24 frames
    scores = [round(score, 2)] * FRAMES_PER_BATCH
    return scores, elapsed_ms, attn_heatmap
