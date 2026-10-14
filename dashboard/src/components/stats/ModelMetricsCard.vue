<script setup lang="ts">
</script>

<template>
  <div class="compute-section glass-card">
    <div class="section-title">MSSTformer 模型算力</div>
    <div class="compute-grid">
      <div class="compute-item">
        <div class="compute-value mono-num" style="color:var(--accent-cyan)">0.12<span class="unit">M</span></div>
        <div class="compute-label">参数量</div>
        <div class="compute-sub">Params</div>
      </div>
      <div class="compute-item">
        <div class="compute-value mono-num" style="color:#3b82f6">~0.35<span class="unit">G</span></div>
        <div class="compute-label">FLOPs</div>
        <div class="compute-sub">单次推理计算量</div>
      </div>
      <div class="compute-item">
        <div class="compute-value mono-num" style="color:#22c55e">~25<span class="unit">ms</span></div>
        <div class="compute-label">推理延迟</div>
        <div class="compute-sub">24帧批次</div>
      </div>
      <div class="compute-item">
        <div class="compute-value mono-num" style="color:#f59e0b">32<span class="unit">dim</span></div>
        <div class="compute-label">嵌入维度</div>
        <div class="compute-sub">4头 · 12层</div>
      </div>
    </div>
    <div class="compute-arch">
      <div class="arch-row">
        <span class="arch-label">输入规格</span>
        <span class="arch-val mono-num">24帧 × 128×128 × 3通道</span>
      </div>
      <div class="arch-row">
        <span class="arch-label">Patch 划分</span>
        <span class="arch-val mono-num">(2, 4, 4) → 12×4×4 = 192 时空块</span>
      </div>
      <div class="arch-row">
        <span class="arch-label">骨干网络</span>
        <span class="arch-val">3D CNN Stem (3级池化) → 3级 Multi-Scale Transformer</span>
      </div>
      <div class="arch-row">
        <span class="arch-label">核心模块</span>
        <span class="arch-val">MSMHSA · MSSTFF · MSGFA · 自适应平均池化 · MLP</span>
      </div>
      <div class="arch-row">
        <span class="arch-label">部署方式</span>
        <span class="arch-val">端侧推理 (CPU) · 支持 GPU 加速 · ONNX 可导出</span>
      </div>
    </div>
    <div class="compute-note">
      <el-icon :size="12"><InfoFilled /></el-icon>
      <span>轻量化多尺度 Transformer · 端云协同架构 · 适合临床边缘部署场景</span>
    </div>
  </div>
</template>

<style scoped>
.compute-section {
  padding: 16px;
  margin-bottom: 20px;
}

.compute-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px;
  margin-bottom: 14px;
}

.compute-item {
  text-align: center;
  padding: 14px 8px;
  background: var(--bg-muted);
  border-radius: 8px;
  border: 1px solid var(--border-color);
}

.compute-value {
  font-size: 28px;
  font-weight: 700;
  letter-spacing: 1px;
  margin-bottom: 2px;
}

.unit {
  font-size: 14px;
  font-weight: 400;
  opacity: 0.6;
  margin-left: 2px;
}

.compute-label {
  font-size: 12px;
  color: var(--text-secondary);
  margin-bottom: 2px;
}

.compute-sub {
  font-size: 10px;
  color: var(--text-muted);
}

.compute-arch {
  padding: 10px 14px;
  background: var(--bg-muted);
  border-radius: 6px;
  border: 1px solid var(--border-color);
  margin-bottom: 10px;
}

.arch-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 4px 0;
  font-size: 11px;
}

.arch-row + .arch-row {
  border-top: 1px solid rgba(148, 163, 184, 0.06);
}

.arch-label {
  color: var(--text-muted);
  flex-shrink: 0;
}

.arch-val {
  color: var(--text-secondary);
  text-align: right;
}

.compute-note {
  display: flex;
  align-items: center;
  gap: 4px;
  padding-top: 10px;
  border-top: 1px solid rgba(148, 163, 184, 0.08);
  font-size: 10px;
  color: var(--text-muted);
}
</style>
