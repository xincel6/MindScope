"""Quick test: predict BDI-II score for a single image."""
import sys
import time
import numpy as np
import cv2
import torch

sys.path.insert(0, "..")
from LMTformer_model.LMTformer import LMTformer

IMAGE_PATH = sys.argv[1] if len(sys.argv) > 1 else "test.jpg"
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# --- 加载模型 ---
model = LMTformer(
    image_size=(24, 128, 128),
    patches=(2, 4, 4),
    dim=32, num_heads=4, num_layers=12,
    dropout_rate=0.1, device=DEVICE,
).to(DEVICE)

ckpt = torch.load("best.pt", map_location=DEVICE, weights_only=False)
model.load_state_dict({k.replace(".module.", "."): v for k, v in ckpt.items()})
model.eval()
print(f"模型已加载到 {DEVICE}")

# --- 预处理（和训练完全一致）---
img = cv2.imread(IMAGE_PATH)
if img is None:
    print(f"无法读取图片: {IMAGE_PATH}")
    sys.exit(1)

img = cv2.resize(img, (128, 128))

# 复制24帧
frames = np.empty((24, 128, 128, 3), dtype=np.float32)
for i in range(24):
    frames[i] = img.astype(np.float32)

frames -= np.array([[[90.0, 98.0, 102.0]]], dtype=np.float32)
buffer = frames.transpose((3, 0, 1, 2))
tensor = torch.from_numpy(buffer).unsqueeze(0).to(DEVICE)

# --- 推理 ---
t0 = time.perf_counter()
with torch.no_grad():
    score = model(tensor).item()
elapsed_ms = (time.perf_counter() - t0) * 1000


def get_level(s):
    if s < 14:
        return "无抑郁/极轻微"
    elif s < 20:
        return "轻度抑郁"
    elif s < 29:
        return "中度抑郁"
    else:
        return "重度抑郁"


print("=" * 50)
print(f"图片路径: {IMAGE_PATH}")
print(f"BDI-II 抑郁分数: {score:.2f}")
print(f"抑郁等级: {get_level(score)}")
print(f"推理耗时: {elapsed_ms:.2f} ms ({DEVICE})")
print("=" * 50)
