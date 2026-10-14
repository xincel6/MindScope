# -*- coding: utf-8 -*-
"""
环境自检脚本：逐个导入后端所需依赖，并验证模型权重能否加载。
用法（在 backend 目录下）:
    venv\\Scripts\\python.exe ..\\..\\_verify_env.py
"""
import importlib
import sys
import traceback

MODULES = [
    "fastapi", "uvicorn", "sqlalchemy", "aiosqlite", "pydantic",
    "multipart", "aiofiles", "numpy", "PIL", "cv2", "torch",
    "facenet_pytorch", "jose", "bcrypt", "httpx", "einops",
    "websockets", "watchfiles",
]

print("=" * 62)
print("解释器:", sys.executable)
print("Python 版本:", sys.version.split()[0])
print("=" * 62)

failed = []
for name in MODULES:
    try:
        mod = importlib.import_module(name)
        ver = getattr(mod, "__version__", "?")
        print(f"  OK    {name:18s} {ver}")
    except Exception as exc:
        failed.append((name, exc))
        print(f"  FAIL  {name:18s} {type(exc).__name__}: {exc}")

print("-" * 62)
print(f"导入结果: {len(MODULES) - len(failed)}/{len(MODULES)} 成功")

# --- 模型权重加载验证 -------------------------------------------------
print("-" * 62)
print("验证 LMTformer 权重加载 ...")
try:
    import torch
    from pathlib import Path

    backend = Path.cwd()
    ckpt_path = backend / "best.pt"
    print(f"  权重文件: {ckpt_path}  存在={ckpt_path.exists()}")

    sys.path.insert(0, str(backend))
    from LMTformer_model.LMTformer import LMTformer

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"  推理设备: {device}")

    model = LMTformer(
        image_size=(24, 128, 128), patches=(2, 4, 4), dim=32,
        num_heads=4, num_layers=12, dropout_rate=0.1, device=device,
    ).to(device)

    ckpt = torch.load(str(ckpt_path), map_location=device, weights_only=False)
    sd = {k.replace(".module.", "."): v for k, v in ckpt.items()}
    missing, unexpected = model.load_state_dict(sd, strict=False)
    model.eval()

    print(f"  state_dict 条目: {len(sd)}")
    print(f"  缺失键: {len(missing)}   多余键: {len(unexpected)}")
    if missing:
        print(f"    缺失示例: {missing[:5]}")
    if unexpected:
        print(f"    多余示例: {unexpected[:5]}")

    # 真实前向推理：输入 [1, 3, 24, 128, 128]
    dummy = torch.randn(1, 3, 24, 128, 128, device=device)
    with torch.no_grad():
        out = model(dummy)
    print(f"  前向推理成功，输出 shape={tuple(out.shape)} 值={out.item():.4f}")
    print("  模型验证: 通过")
except Exception:
    print("  模型验证: 失败")
    traceback.print_exc()

print("=" * 62)
if failed:
    print("结论: 仍有依赖缺失 ->", ", ".join(n for n, _ in failed))
    sys.exit(1)
print("结论: 全部依赖就绪")
