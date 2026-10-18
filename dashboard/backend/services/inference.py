"""
LMTformer inference service.

Interface contract:
    lmtformer_inference(faces) -> (scores, elapsed_ms, heatmaps)

    Input:  list of 24 aligned face crops, each (128, 128, 3) uint8 BGR.
    Output: scores   —— 24 个 BDI-II 分数（0–63）。
                       ★ 模型输出的是**整段 clip 级**回归值，不是逐帧值；
                       这里按原样广播给 24 帧，客户端必须按"每 24 帧一次推理"的
                       段级口径展示（界面文案已标注）。
            heatmaps —— 12 张 16×16 热度矩阵，对应 12 个时间 token（每个覆盖 2 帧）。
                       ★ 旧实现把 12 个 token 在时间维取平均成 1 张，导致
                       "同一批 24 帧热力图完全同色"（用户报的"所有帧都是同一帧"）。
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
def _blank_heatmap() -> list[list[float]]:
    """占位矩阵：注意力取不到时前端走"无数据"分支，绝不能拿假热度充数。"""
    return [[0.0] * 16 for _ in range(16)]


def _extract_attention_heatmaps(scores_tensor) -> list[list[list[float]]]:
    """
    从最后一个 Transformer 块的自注意力里，**按时间 token 拆出多张**热力图。

    scores_tensor: [B, h, 192, 192] —— 192 patches = 12 个时间 token × 4×4 空间。
    Returns: 12 张 16×16 热力图（token t 对应批内第 2t / 2t+1 帧）。

    ★ 为什么不沿用旧实现的"在时间维取平均"：
      那样一批 24 帧共用同一张图，用户看到的就是"所有帧都是同一帧"。
      注意力本来就是逐 token 的，拆分是**零额外算力**的（只是不取平均）。
    ★ 归一化用**整批全局 min/max**，不是逐张归一：
      逐张归一会把每张图都拉满到 [0,1]，时间上的强弱变化就看不出来了。
    """
    # Average across attention heads → [B, 192, 192]
    attn = scores_tensor.mean(dim=1)

    # Average attention received by each patch (as key) from all queries → [B, 192]
    attn = attn.mean(dim=1)

    # Take first batch item → [192]
    attn = attn[0]

    spatial = 4 * 4
    patch_count = int(attn.numel())
    if patch_count % spatial != 0:
        raise ValueError(f"注意力 patch 数 {patch_count} 不是 {spatial} 的整数倍")
    tokens = patch_count // spatial
    if tokens <= 0:
        raise ValueError("注意力 patch 数为 0")

    # 12 个时间 token × 4×4 空间
    attn = attn.view(tokens, 4, 4)

    # 整批一起归一化 → 时间上的强弱可比
    attn_np = attn.cpu().numpy()
    lo = float(attn_np.min())
    hi = float(attn_np.max())
    attn_np = (attn_np - lo) / (hi - lo + 1e-8)

    # 4×4 → 16×16（逐 token），再夹回 [0,1]
    import cv2
    maps: list[list[list[float]]] = []
    for t in range(tokens):
        up = cv2.resize(attn_np[t], (16, 16), interpolation=cv2.INTER_CUBIC)
        np.clip(up, 0.0, 1.0, out=up)
        maps.append(up.tolist())
    return maps


def average_heatmaps(maps: list[list[list[float]]]) -> list[list[float]]:
    """多张同尺寸热力图取平均（单张图片端点用：整段都是同一张脸，没有"时间"）。

    纯 Python 实现：该函数在端点请求路径上被调用，不希望为了它引入 numpy 依赖链。
    """
    if not maps:
        return []
    rows = len(maps[0])
    cols = len(maps[0][0]) if rows else 0
    if rows == 0 or cols == 0:
        return []
    acc: list[list[float]] = [[0.0] * cols for _ in range(rows)]
    used = 0
    for m in maps:
        if len(m) != rows or any(len(row) != cols for row in m):
            continue
        used += 1
        for y in range(rows):
            for x in range(cols):
                acc[y][x] += float(m[y][x])
    if used == 0:
        return []
    return [[round(acc[y][x] / used, 4) for x in range(cols)] for y in range(rows)]


# ---------------------------------------------------------------------------
# Public API (async-safe — call from FastAPI event loop)
# ---------------------------------------------------------------------------
async def lmtformer_inference(
    faces: list[np.ndarray],
    seed: Optional[float] = None,
) -> tuple[list[float], float, list[list[list[float]]]]:
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

    # Extract per-temporal-token heatmaps from the last transformer block's self-attention
    try:
        last_attn_module = _model.transformer3.blocks[-1].attn
        if last_attn_module.scores is not None:
            heatmaps = _extract_attention_heatmaps(last_attn_module.scores)
        else:
            heatmaps = [_blank_heatmap()]
    except Exception:
        heatmaps = [_blank_heatmap()]

    # Model outputs one clip-level score — assign to all 24 frames（段级，不是逐帧）
    scores = [round(score, 2)] * FRAMES_PER_BATCH
    return scores, elapsed_ms, heatmaps
