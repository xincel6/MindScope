"""
一体化启动入口（不改动任何原代码，仅新增此文件）。

用法（默认仅本机可访问，安全）：
    python serve_all.py                        # 仅监听 127.0.0.1，只有本机能访问
    HOST=0.0.0.0 python serve_all.py           # 临时开放，局域网其它电脑可访问

本机浏览器打开 http://127.0.0.1:8000 即可；临时开放后，局域网内其它电脑用
http://<本机IP>:8000 访问。停止该进程即可关闭外部访问。

原理：复用 main.py 里现成的 FastAPI 应用（已包含 /api、/ws、/media 路由），
在路由表末尾追加一条 SPA 兜底路由，把 dist/ 打包好的前端页面与后端接口
放到同一个端口上，从而让前端用相对路径访问，规避跨源（CORS/跨域）问题。
"""
import os

from pathlib import Path

from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse

from backup_db import backup_database
from config import DATABASE_PATH
from main import app  # 复用现有后端应用

# 隧道/移动网络下 1.5 MB 的未压缩入口包很容易传不完；这里给所有响应加 gzip。
# 浏览器只在 Accept-Encoding 含 gzip 时才压缩，图片/视频等已是压缩格式的响应基本不受影响。
app.add_middleware(GZipMiddleware, minimum_size=1024, compresslevel=6)

# 前端打包产物目录：backend 的上级目录下的 dist/
DIST = (Path(__file__).resolve().parent.parent / "dist").resolve()
INDEX = DIST / "index.html"

# 带内容哈希的 assets 可以长期缓存；index.html 必须每次回源，避免继续引用旧 hash。
IMMUTABLE_CACHE = {"Cache-Control": "public, max-age=31536000, immutable"}
REVALIDATE_CACHE = {"Cache-Control": "no-cache"}


@app.get("/{full_path:path}", include_in_schema=False)
async def serve_spa(full_path: str):
    # 根路径或显式 index.html -> 首页
    if full_path in ("", "index.html"):
        return FileResponse(INDEX, headers=REVALIDATE_CACHE)

    # 真实静态文件（如 /assets/xxx.js、/favicon.svg、/icons.svg）
    candidate = (DIST / full_path).resolve()
    if candidate.is_file() and candidate.is_relative_to(DIST):
        headers = IMMUTABLE_CACHE if full_path.startswith("assets/") else REVALIDATE_CACHE
        return FileResponse(candidate, headers=headers)

    # 前端 history 路由统一回退到首页
    return FileResponse(INDEX, headers=REVALIDATE_CACHE)


if __name__ == "__main__":
    import uvicorn

    # ★ 启动前先备份一次（热备，不中断）：部署/清库/迁移之前总有一份可回滚的快照。
    #   DB_BACKUP_ON_START=0 可关闭（例如 CI 里反复冷启动）。
    if os.getenv("DB_BACKUP_ON_START", "1") != "0":
        try:
            snapshot = backup_database()
            if snapshot is not None:
                print(f"[serve_all] 启动前已备份数据库 → {snapshot}")
        except Exception as exc:  # 备份失败不能挡住服务启动
            print(f"[serve_all] 启动前备份失败（不影响启动）：{exc}")
    print(f"[serve_all] 数据库：{DATABASE_PATH}")

    from config import SSL_CERTFILE, SSL_KEYFILE

    host = os.getenv("HOST", "127.0.0.1")   # 默认仅本机（安全）；临时开放用 HOST=0.0.0.0
    port = int(os.getenv("PORT", "8000"))

    # HTTPS：证书路径从环境变量读（SSL_CERTFILE / SSL_KEYFILE，见 config.py）。
    # 两个都配置时才启用 TLS；否则保持纯 HTTP（默认）。
    if SSL_CERTFILE and SSL_KEYFILE:
        uvicorn.run(
            app,
            host=host,
            port=port,
            ssl_certfile=SSL_CERTFILE,
            ssl_keyfile=SSL_KEYFILE,
        )
    else:
        uvicorn.run(app, host=host, port=port)
