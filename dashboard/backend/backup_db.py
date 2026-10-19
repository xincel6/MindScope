"""数据库**热备份**（部署 / 重启前自动跑一次）。

为什么不用 `cp depression.db backups/`：
    服务运行中直接复制文件可能拿到"写了一半"的库（SQLite 页级写入 + WAL），
    恢复时会发现库损坏。`sqlite3.Connection.backup()` 会拿**一致快照**，
    运行中也能安全备份。

用法（在 dashboard/backend 下）：
    python backup_db.py                     # 备份到 backend/backups/，保留最近 10 份
    python backup_db.py --keep 7            # 只保留最近 7 份
    python backup_db.py --db /var/lib/mindscope/depression.db --dir /var/lib/mindscope/backups

恢复（先停服务，再覆盖）：
    cp backups/depression-20261018-153000.db /var/lib/mindscope/depression.db

`serve_all.py` 启动时会自动调用 `backup_database()`（可用 `DB_BACKUP_ON_START=0` 关闭）。
"""

import argparse
import sqlite3
import time
from pathlib import Path
from typing import Optional

from config import BACKUP_DIR, DATABASE_PATH


def prune_backups(backup_dir: Path, stem: str, keep: int) -> list[Path]:
    """只保留最近 `keep` 份备份（按修改时间倒序），返回被删掉的文件。"""
    if keep <= 0:
        return []
    backup_dir = Path(backup_dir)
    if not backup_dir.is_dir():
        return []
    files = sorted(
        backup_dir.glob(f"{stem}-*.db"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    removed: list[Path] = []
    for old in files[keep:]:
        try:
            old.unlink()
            removed.append(old)
        except OSError:
            pass
    return removed


def backup_database(
    db_path: Path = DATABASE_PATH,
    backup_dir: Path = BACKUP_DIR,
    keep: int = 10,
    stamp: Optional[str] = None,
) -> Optional[Path]:
    """把 `db_path` 备份成 `backup_dir/<stem>-<stamp>.db`。

    Returns: 备份文件路径；数据库不存在时返回 None（首次启动尚未初始化，不报错）。
    """
    db_path = Path(db_path)
    if not db_path.is_file():
        return None

    backup_dir = Path(backup_dir)
    backup_dir.mkdir(parents=True, exist_ok=True)

    stamp = stamp or time.strftime("%Y%m%d-%H%M%S")
    target = backup_dir / f"{db_path.stem}-{stamp}.db"

    src = sqlite3.connect(str(db_path))
    dst = sqlite3.connect(str(target))
    try:
        src.backup(dst)  # 一致快照，运行中安全
    finally:
        src.close()
        dst.close()

    prune_backups(backup_dir, db_path.stem, keep)
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="MindScope 数据库热备份")
    parser.add_argument("--db", default=str(DATABASE_PATH), help="要备份的数据库路径")
    parser.add_argument("--dir", default=str(BACKUP_DIR), help="备份输出目录")
    parser.add_argument("--keep", type=int, default=10, help="保留最近几份（默认 10）")
    args = parser.parse_args()

    target = backup_database(Path(args.db), Path(args.dir), keep=args.keep)
    if target is None:
        print(f"[backup] 数据库不存在，跳过：{args.db}")
        return 0
    print(f"[backup] 已备份 → {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
