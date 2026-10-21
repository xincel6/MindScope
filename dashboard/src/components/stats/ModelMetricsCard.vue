<script setup lang="ts">
/**
 * 模型信息（可折叠）
 * ================================================================
 * 规则：卡片里的每个数字/取值都必须能指到后端源码的某一行。
 * P2 删掉的旧值（无出处，已确认后端不存在）：
 *   参数量、FLOPs、推理延迟常数、「MSMHSA · MSSTFF · MSGFA」核心模块、「ONNX 可导出」
 *   —— `LMTformer_model/LMTformer.py` 里没有这些类名，也没有导出脚本。
 * 延迟不写常数：真实耗时应看「本次推理指标」里的实测值。
 */
import { ref } from 'vue'

interface ModelRow {
  label: string
  value: string
  source: string
}

const active = ref<string[]>([])

const rows: ModelRow[] = [
  {
    label: '权重文件',
    value: 'best.pt',
    source: 'backend/config.py:120 MODEL_CHECKPOINT',
  },
  {
    label: '模型定义',
    value: 'LMTformer',
    source: 'backend/LMTformer_model/LMTformer.py:37',
  },
  {
    label: '输入规格',
    value: '24 帧 × 128×128 × 3 通道',
    source: 'backend/services/inference.py:46 image_size=(24,128,128) · config.py:115 FRAMES_PER_BATCH=24',
  },
  {
    label: 'Patch 划分',
    value: 'patches = (2, 4, 4)',
    source: 'backend/services/inference.py:46 patches=(2,4,4)',
  },
  {
    label: '嵌入维度',
    value: 'dim 32 · 4 头 · 12 层',
    source: 'backend/services/inference.py:46-54 dim=32 / num_heads=4 / num_layers=12',
  },
  {
    label: '输出内容',
    value: '每个片段 1 个 BDI-II 总分 + 12 张 16×16 热力图',
    source: 'backend/services/inference.py:7-14 文件头说明（clip 级回归，热力图每个 token 覆盖 2 帧）',
  },
  {
    label: '运行设备',
    value: 'CUDA 可用则 GPU，否则 CPU',
    source: 'backend/services/inference.py:44 torch.device("cuda" if cuda_available else "cpu")',
  },
]
</script>

<template>
  <div class="model-info glass-card">
    <el-collapse v-model="active" class="model-collapse">
      <el-collapse-item name="info">
        <template #title>
          <span class="model-info-title">模型信息</span>
          <span class="model-info-sub">每个取值都标注了后端来源</span>
        </template>

        <div class="model-rows">
          <div v-for="row in rows" :key="row.label" class="model-row">
            <span class="row-label">{{ row.label }}</span>
            <div class="row-body">
              <span class="row-value mono-num">{{ row.value }}</span>
              <span class="row-source">{{ row.source }}</span>
            </div>
          </div>
        </div>

        <div class="model-note">
          <el-icon :size="12"><InfoFilled /></el-icon>
          <span>
            参数量 / FLOPs 后端未提供，所以这里不写；推理延迟请看「智能分析 · 本次推理指标」里的实测值。
          </span>
        </div>
      </el-collapse-item>
    </el-collapse>
  </div>
</template>

<style scoped>
.model-info {
  padding: 4px 16px;
  margin-bottom: 20px;
}

.model-collapse {
  --el-collapse-border-color: var(--border);
}

.model-info-title {
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.model-info-sub {
  margin-left: 10px;
  font-size: var(--font-xs);
  font-weight: 400;
  color: var(--text-secondary);
}

.model-rows {
  display: flex;
  flex-direction: column;
}

.model-row {
  display: grid;
  grid-template-columns: 88px 1fr;
  gap: 12px;
  padding: 8px 0;
  border-top: 1px solid var(--border);
}

.model-row:first-child {
  border-top: none;
}

.row-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  padding-top: 2px;
}

.row-body {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.row-value {
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.row-source {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  line-height: 1.5;
  word-break: break-word;
}

.model-note {
  display: flex;
  align-items: flex-start;
  gap: 4px;
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px solid var(--border);
  font-size: var(--font-xs);
  color: var(--text-secondary);
  line-height: 1.55;
}
</style>
