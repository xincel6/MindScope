"""帧流映射的**纯函数**（无 torch / cv2 / DB，可离线单测）。

为什么单独一层：`services/frame_processor.py` 里有两个"改坏了也看不出来"的映射 ——
  ① 一帧该配哪一张注意力热力图（模型有 12 个时间 token，每个覆盖 2 帧）；
  ② 尾批补帧时该发哪几条、帧号从几开始。

这两处此前都是内联写法，尾批还出过一个用户可见的 bug：
补帧后按**补齐后的长度**算起始帧号，于是帧号错位、同一帧被重复发送
（客户端"逐帧热力图"里出现一屏完全相同的格子）。

抽成纯函数后，它们可以在没有模型、没有视频的环境里逐条断言，
而不是靠"装机看截图"才发现。
"""

from typing import NamedTuple, Sequence

from config import FRAMES_PER_BATCH

# 模型 patch_embedding 的时间核 = 2（LMTformer_model/LMTformer.py: patches=(2,4,4)），
# 所以 24 帧 → 12 个时间 token，每个 token 覆盖 2 帧。
ATTENTION_TEMPORAL_TOKENS: int = 12
FRAMES_PER_TEMPORAL_TOKEN: int = FRAMES_PER_BATCH // ATTENTION_TEMPORAL_TOKENS

#: 一张 16×16 的热度矩阵
Heatmap = list[list[float]]


def token_index(frame_index: int, token_count: int = ATTENTION_TEMPORAL_TOKENS) -> int:
    """批内第 `frame_index` 帧（0-based）落在第几个时间 token 上。

    token_count 允许调用方按实际拿到的热力图数量传入（测试 / 降级路径）。
    """
    if token_count <= 0 or frame_index <= 0:
        return 0
    index = frame_index // FRAMES_PER_TEMPORAL_TOKEN
    if index >= token_count:
        return token_count - 1
    return index


def heatmap_for_frame(heatmaps: Sequence[Heatmap], frame_index: int) -> Heatmap:
    """取该帧对应的时间片热力图；热力图缺失时返回空矩阵（前端走占位态）。"""
    if not heatmaps:
        return []
    return heatmaps[token_index(frame_index, len(heatmaps))]


class TailPlan(NamedTuple):
    """尾批（不足 24 帧）的发送计划。"""

    #: 为凑满模型输入需要补几帧 —— **只用于推理，绝不能发送**
    padding: int
    #: 第一条真实帧的帧号（全局连续，1-based）
    start_id: int
    #: 实际要发送的帧数（= 真实帧数，不含补帧）
    emit_count: int


def tail_plan(
    real_frames: int,
    last_frame_id: int,
    batch_size: int = FRAMES_PER_BATCH,
) -> TailPlan:
    """计算尾批计划。

    ★ 回归点：旧实现先补帧、再用 `len(buffer)`（补齐后的 24）反推起点，
      于是 19 条真实帧被标成 188..206、末尾 5 条是同一帧的副本。
      这里一律用**补帧前**的真实帧数推起点。
    """
    if real_frames <= 0:
        return TailPlan(0, last_frame_id + 1, 0)
    if real_frames > batch_size:
        raise ValueError(
            f"尾批真实帧数不能超过批大小：{real_frames} > {batch_size}"
        )
    return TailPlan(
        padding=batch_size - real_frames,
        start_id=last_frame_id - real_frames + 1,
        emit_count=real_frames,
    )
