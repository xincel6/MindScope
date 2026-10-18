"""把 `media_assets.file_path` 解析成当前机器上真实可读的文件。

为什么需要这一层
────────────────
`depression.db` 是随仓库分发的（里面带着演示数据），而 `file_path` 字段里历史上
混着三种写法：

  · Windows 绝对路径   ``D:\\Code_java\\...\\backend\\media\\3b70....mp4``
  · macOS 绝对路径     ``/Users/guoshuping/Desktop/.../backend/media/xxx.mp4``
  · 纯文件名           ``3b70....mp4``

这些绝对路径只在"当初上传它的那台机器"上成立。换到 Linux 服务器后，文件内容其实
就在 ``MEDIA_DIR`` 下、文件名也没变，只是记录里的目录前缀失效了。

★ 关键坑：POSIX 的 `pathlib` **不把 ``\\`` 当路径分隔符**。
  ``Path(r"D:\\a\\b.mp4").name`` 在 Linux 上返回的是整条字符串（不是 ``b.mp4``），
  于是 ``MEDIA_DIR / Path(stored).name`` 会拼出
  ``.../media/D:\\a\\b.mp4`` 这种必然不存在的路径 —— 这正是分析页报
  ``File not found: .../media/D:\\Code_java\\...`` 的原因。
  所以这里先统一分隔符再取末段，行为与运行平台无关。
"""

from pathlib import Path, PurePosixPath
from typing import Optional

from config import MEDIA_DIR


def media_file_name(stored: Optional[str]) -> str:
    """从任意写法的记录里取纯文件名（不含目录）；取不到时返回空串。"""
    if not stored:
        return ""
    # 先把 Windows 反斜杠统一成斜杠，再交给 POSIX 语义取末段
    return PurePosixPath(stored.strip().replace("\\", "/")).name


def resolve_media_path(stored: Optional[str]) -> Optional[Path]:
    """返回本机上真实存在的素材文件；找不到时返回 ``None``。

    解析顺序：
      1. 记录里的路径本身（仅当它是绝对路径且文件存在 —— 在本机上传、记录仍然有效）；
      2. ``MEDIA_DIR / <文件名>``（跨机器/跨系统迁移后的主路径）。
    """
    if not stored or not stored.strip():
        return None

    raw = stored.strip()

    direct = Path(raw)
    if direct.is_absolute() and direct.is_file():
        return direct

    name = media_file_name(raw)
    if not name:
        return None

    candidate = MEDIA_DIR / name
    return candidate if candidate.is_file() else None
