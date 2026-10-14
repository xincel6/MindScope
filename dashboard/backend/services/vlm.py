"""
Call GLM-4.6V vision-language model to interpret facial depression cues.

Image mode:  single aligned face → VLM analysis.
Video mode:  3 key-frames (25% / 50% / 100% progress) → temporal-aware analysis.
"""

import json
import http.client

from config import VLM_API_KEY, VLM_API_HOST, VLM_API_PATH, VLM_MODEL

_IMAGE_PROMPT = """观察人物面部，从**眉间、眼睛、嘴角**三个细节特征进行抑郁相关推理。
已知BDI-II抑郁量表总分：{score}分
BDI-II评分标准：
0~13分：无抑郁～极轻微抑郁
14~19分：轻度抑郁
20~28分：中度抑郁
29~63分：重度抑郁

严格按下面固定格式输出，**不要多余解释、不要客套话**第一前提必须是**量表总分**：
【量表总分】
【抑郁程度判定】
【面部特征抑郁推理依据】（只从眉间、眼睛、嘴角三点分别描述,除去这三个特征也可通过其他面部信息进行推理）
【抑郁情绪缓解建议】（给出实用可执行的调理缓解方法）（分数低的化不要乱说）"""

_VIDEO_PROMPT = """以下三张图片来自同一段视频的三个不同时间点（前段、中段、后段），请综合分析人物在整个视频过程中的面部表情变化，从**眉间、眼睛、嘴角**三个细节特征进行抑郁相关推理。
已知BDI-II抑郁量表总分：{score}分
BDI-II评分标准：
0~13分：无抑郁～极轻微抑郁
14~19分：轻度抑郁
20~28分：中度抑郁
29~63分：重度抑郁

严格按下面固定格式输出，**不要多余解释、不要客套话**第一前提必须是**量表总分**：
【量表总分】
【抑郁程度判定】
【面部特征动态变化】（描述眉间、眼睛、嘴角三个部位在视频前中后段的变化趋势）
【面部特征抑郁推理依据】（结合动态变化，从眉间、眼睛、嘴角三点分别描述）
【抑郁情绪缓解建议】（给出实用可执行的调理缓解方法）（分数低的化不要乱说）"""


def _image_block(b64: str) -> dict:
    return {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}}


async def call_vlm_image(face_base64: str, bdi_score: float) -> str:
    """VLM analysis for a single image."""
    prompt = _IMAGE_PROMPT.format(score=round(bdi_score, 1))
    return await _call_api([_image_block(face_base64)], prompt)


async def call_vlm_video(faces: list[str], bdi_score: float) -> str:
    """VLM analysis for video — 3 key-frames."""
    prompt = _VIDEO_PROMPT.format(score=round(bdi_score, 1))
    blocks = [_image_block(f) for f in faces]
    return await _call_api(blocks, prompt)


async def _call_api(image_blocks: list[dict], prompt: str) -> str:
    """Shared HTTP call. Returns empty string on any failure (VLM is non-critical)."""
    payload = {
        "model": VLM_MODEL,
        "messages": [
            {
                "role": "user",
                "content": [*image_blocks, {"type": "text", "text": prompt}],
            }
        ],
        "temperature": 0.2,
        "stream": False,
    }

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {VLM_API_KEY}",
    }

    try:
        conn = http.client.HTTPSConnection(VLM_API_HOST, timeout=45)
        conn.request("POST", VLM_API_PATH, json.dumps(payload), headers)
        res = conn.getresponse()
        data = res.read()
        result = json.loads(data.decode("utf-8"))
        return result["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"[vlm] VLM call failed: {e}")
        return ""
