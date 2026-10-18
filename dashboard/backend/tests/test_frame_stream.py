"""帧流映射回归测试（不加载 torch / 不碰真实视频，秒级可跑）。

跑法（在 dashboard/backend 下）：
    venv/bin/python -m unittest discover -s tests
    # Windows: venv\\Scripts\\python.exe -m unittest discover -s tests

守卫两件事：
  ① 每帧该配哪张热力图（12 个时间 token，每个覆盖 2 帧）；
  ② 尾批只发真实帧、帧号连续 —— 这正是"逐帧列表里出现一屏完全相同的格子"的根因。
"""

import unittest

from services.frame_plan import (
    ATTENTION_TEMPORAL_TOKENS,
    FRAMES_PER_TEMPORAL_TOKEN,
    heatmap_for_frame,
    tail_plan,
    token_index,
)


class TokenMappingTest(unittest.TestCase):
    """24 帧 → 12 个时间 token，每 2 帧共用一张热力图。"""

    def test_constants(self):
        self.assertEqual(ATTENTION_TEMPORAL_TOKENS, 12)
        self.assertEqual(FRAMES_PER_TEMPORAL_TOKEN, 2)

    def test_pair_mapping(self):
        # 批内前 2 帧 → token 0，接下来 2 帧 → token 1，末尾 2 帧 → token 11
        self.assertEqual([token_index(i) for i in range(6)], [0, 0, 1, 1, 2, 2])
        self.assertEqual(token_index(22), 11)
        self.assertEqual(token_index(23), 11)

    def test_out_of_range_clamps(self):
        self.assertEqual(token_index(0), 0)
        self.assertEqual(token_index(-3), 0)
        self.assertEqual(token_index(999), ATTENTION_TEMPORAL_TOKENS - 1)

    def test_heatmap_picked_per_frame(self):
        maps = [[[float(t)] * 16 for _ in range(16)] for t in range(12)]
        self.assertEqual(heatmap_for_frame(maps, 0)[0][0], 0.0)
        self.assertEqual(heatmap_for_frame(maps, 1)[0][0], 0.0)
        self.assertEqual(heatmap_for_frame(maps, 2)[0][0], 1.0)
        self.assertEqual(heatmap_for_frame(maps, 23)[0][0], 11.0)

    def test_heatmap_falls_back_when_missing(self):
        # 注意力取不到时端点返回空列表 → 前端走占位态，不能编造热度
        self.assertEqual(heatmap_for_frame([], 5), [])

    def test_fewer_maps_than_tokens_clamps(self):
        maps = [[[0.5] * 16 for _ in range(16)]]
        self.assertEqual(heatmap_for_frame(maps, 23)[0][0], 0.5)


class TailPlanTest(unittest.TestCase):
    """尾批（不足 24 帧）必须补齐推理输入，但只发送真实帧。"""

    def test_sample_video_60_frames(self):
        # 样本视频 anonymous_001.mp4：采样 60 帧，最后一批 12 帧
        plan = tail_plan(12, 60)
        self.assertEqual(plan.padding, 12)
        self.assertEqual(plan.emit_count, 12)
        # ★ 回归点：旧实现是 60 - 24 + 1 = 37（把补帧算进长度），新实现是 49
        self.assertEqual(plan.start_id, 49)

    def test_ids_are_contiguous_and_end_at_last_frame(self):
        plan = tail_plan(19, 211)
        emitted = [plan.start_id + i for i in range(plan.emit_count)]
        self.assertEqual(emitted, list(range(193, 212)))
        self.assertEqual(emitted[-1], 211)

    def test_full_batch_has_no_padding(self):
        plan = tail_plan(24, 216)
        self.assertEqual(plan.padding, 0)
        self.assertEqual(plan.start_id, 193)
        self.assertEqual(plan.emit_count, 24)

    def test_single_frame(self):
        plan = tail_plan(1, 1)
        self.assertEqual(plan.padding, 23)
        self.assertEqual(plan.start_id, 1)
        self.assertEqual(plan.emit_count, 1)

    def test_empty(self):
        plan = tail_plan(0, 7)
        self.assertEqual((plan.padding, plan.start_id, plan.emit_count), (0, 8, 0))

    def test_rejects_more_than_batch(self):
        with self.assertRaises(ValueError):
            tail_plan(25, 25)


class AverageHeatmapTest(unittest.TestCase):
    """单帧图片端点把 12 个时间 token 平均回一张（口径与旧版一致）。"""

    def test_average_of_identical_maps_is_itself(self):
        from services.inference import average_heatmaps

        one = [[0.25] * 16 for _ in range(16)]
        avg = average_heatmaps([one, one, one])
        self.assertEqual(len(avg), 16)
        self.assertAlmostEqual(avg[0][0], 0.25, places=6)

    def test_average_of_two_maps(self):
        from services.inference import average_heatmaps

        a = [[0.0] * 16 for _ in range(16)]
        b = [[1.0] * 16 for _ in range(16)]
        avg = average_heatmaps([a, b])
        self.assertAlmostEqual(avg[7][7], 0.5, places=6)

    def test_empty(self):
        from services.inference import average_heatmaps

        self.assertEqual(average_heatmaps([]), [])


if __name__ == "__main__":
    unittest.main()
