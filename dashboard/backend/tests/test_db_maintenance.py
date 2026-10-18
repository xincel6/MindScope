"""运行库初始化 / 热备份的离线测试（不加载 torch、不启动服务）。

守卫 BUG-26 的两条修法：
  ① 仓库里只放 `demo/depression.db` 种子，首次启动复制成运行库，**已存在绝不覆盖**；
  ② 备份用 sqlite3 的 backup API（运行中也能拿一致快照），并按份数轮转。

跑法（在 dashboard/backend 下）：
    venv/bin/python -m unittest discover -s tests
"""

import os
import sqlite3
import tempfile
import unittest
from pathlib import Path

from backup_db import backup_database, prune_backups
from database import ensure_database


def make_db(path: Path, value: int) -> None:
    """造一个最小 SQLite 库（只有一张表一行）。"""
    conn = sqlite3.connect(str(path))
    try:
        conn.execute("CREATE TABLE sample (v INTEGER)")
        conn.execute("INSERT INTO sample (v) VALUES (?)", (value,))
        conn.commit()
    finally:
        conn.close()


def read_value(path: Path) -> int:
    conn = sqlite3.connect(str(path))
    try:
        return int(conn.execute("SELECT v FROM sample").fetchone()[0])
    finally:
        conn.close()


class EnsureDatabaseTest(unittest.TestCase):
    def test_copies_seed_only_when_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            demo = tmp_path / "demo" / "depression.db"
            demo.parent.mkdir()
            make_db(demo, 42)
            runtime = tmp_path / "depression.db"

            self.assertTrue(ensure_database(runtime, demo))
            self.assertTrue(runtime.is_file())
            self.assertEqual(read_value(runtime), 42)

            # 已有运行库：绝不能再拿种子覆盖（线上数据只能人工迁移）
            conn = sqlite3.connect(str(runtime))
            conn.execute("INSERT INTO sample (v) VALUES (7)")
            conn.commit()
            conn.close()

            self.assertFalse(ensure_database(runtime, demo))
            self.assertEqual(read_value(runtime), 42)  # 第一行仍是种子内容
            conn = sqlite3.connect(str(runtime))
            rows = [r[0] for r in conn.execute("SELECT v FROM sample ORDER BY rowid")]
            conn.close()
            self.assertEqual(rows, [42, 7])

    def test_no_seed_no_database(self):
        with tempfile.TemporaryDirectory() as tmp:
            runtime = Path(tmp) / "depression.db"
            self.assertFalse(ensure_database(runtime, Path(tmp) / "missing.db"))
            self.assertFalse(runtime.exists())


class BackupTest(unittest.TestCase):
    def test_backup_is_a_readable_snapshot(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            db = tmp_path / "depression.db"
            make_db(db, 11)
            out = tmp_path / "backups"

            target = backup_database(db, out, keep=10, stamp="20261018-153000")
            self.assertIsNotNone(target)
            self.assertEqual(target.name, "depression-20261018-153000.db")
            self.assertEqual(read_value(target), 11)

    def test_missing_database_is_noop(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = backup_database(Path(tmp) / "nope.db", Path(tmp) / "backups")
            self.assertIsNone(target)

    def test_prune_keeps_newest(self):
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp)
            made = []
            for i, stamp in enumerate(["a", "b", "c"]):
                path = backup_dir / f"depression-{stamp}.db"
                path.write_bytes(b"x")
                # 明确设置修改时间：a 最旧、c 最新
                os.utime(path, (1000 + i, 1000 + i))
                made.append(path)

            removed = prune_backups(backup_dir, "depression", keep=2)
            self.assertEqual(len(removed), 1)
            self.assertFalse(made[0].exists())   # 最旧的被删
            self.assertTrue(made[1].exists())
            self.assertTrue(made[2].exists())

    def test_prune_keep_zero_does_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "depression-x.db"
            path.write_bytes(b"x")
            self.assertEqual(prune_backups(Path(tmp), "depression", 0), [])
            self.assertTrue(path.exists())


if __name__ == "__main__":
    unittest.main()
