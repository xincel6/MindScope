"""media_paths 的跨平台解析回归测试（不加载 torch / 不碰真实数据库）。

跑法（在 dashboard/backend 下）：
    venv/bin/python -m unittest discover -s tests
    # Windows: venv\\Scripts\\python.exe -m unittest discover -s tests
"""

import tempfile
import unittest
from pathlib import Path

import media_paths


class MediaFileNameTest(unittest.TestCase):
    """`media_file_name` 必须同时认 Windows 反斜杠与 POSIX 斜杠。"""

    def test_windows_absolute_path(self):
        # ★ 回归点：Linux 上 Path(r"D:\\...").name 会返回整条字符串，
        #   曾经因此拼出 .../media/D:\\Code_java\\...\\xxx.mp4 这种假路径。
        self.assertEqual(
            media_paths.media_file_name(
                r"D:\Code_java\depression-dashboard\backend\media\3b706ccd.mp4"
            ),
            "3b706ccd.mp4",
        )

    def test_macos_absolute_path(self):
        self.assertEqual(
            media_paths.media_file_name(
                "/Users/guoshuping/Desktop/depression-dashboard/backend/media/patient_b.mp4"
            ),
            "patient_b.mp4",
        )

    def test_plain_file_name(self):
        self.assertEqual(media_paths.media_file_name("3b706ccd.mp4"), "3b706ccd.mp4")

    def test_blank_values(self):
        self.assertEqual(media_paths.media_file_name(None), "")
        self.assertEqual(media_paths.media_file_name(""), "")
        self.assertEqual(media_paths.media_file_name("   "), "")


class ResolveMediaPathTest(unittest.TestCase):
    """记录里的路径不可用时，必须按文件名回到 MEDIA_DIR 找。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._orig_media_dir = media_paths.MEDIA_DIR
        self.media_dir = Path(self._tmp.name) / "media"
        self.media_dir.mkdir()
        media_paths.MEDIA_DIR = self.media_dir

    def tearDown(self):
        media_paths.MEDIA_DIR = self._orig_media_dir
        self._tmp.cleanup()

    def test_legacy_windows_path_falls_back_to_media_dir(self):
        target = self.media_dir / "abc.mp4"
        target.write_bytes(b"x")
        self.assertEqual(
            media_paths.resolve_media_path(r"D:\dev\project\backend\media\abc.mp4"),
            target,
        )

    def test_legacy_macos_path_falls_back_to_media_dir(self):
        target = self.media_dir / "abc.mp4"
        target.write_bytes(b"x")
        self.assertEqual(
            media_paths.resolve_media_path("/Users/someone/Desktop/backend/media/abc.mp4"),
            target,
        )

    def test_existing_absolute_path_is_used_as_is(self):
        local = Path(self._tmp.name) / "elsewhere.mp4"
        local.write_bytes(b"x")
        self.assertEqual(media_paths.resolve_media_path(str(local)), local)

    def test_missing_file_returns_none(self):
        self.assertIsNone(
            media_paths.resolve_media_path(r"D:\dev\project\backend\media\missing.mp4")
        )

    def test_blank_values_return_none(self):
        self.assertIsNone(media_paths.resolve_media_path(None))
        self.assertIsNone(media_paths.resolve_media_path(""))
        self.assertIsNone(media_paths.resolve_media_path("   "))


if __name__ == "__main__":
    unittest.main()
