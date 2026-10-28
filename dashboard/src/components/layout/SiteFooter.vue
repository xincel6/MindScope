<script setup lang="ts">
const year = new Date().getFullYear()
</script>

<template>
  <footer class="site-footer">
    <span class="site-footer-copy">© {{ year }} MindScope · 抑郁症智能辅助诊断系统</span>
    <a
      class="site-footer-icp"
      href="https://beian.miit.gov.cn/"
      target="_blank"
      rel="noopener noreferrer"
    >
      皖ICP备2026037674号-1
    </a>
  </footer>
</template>

<style scoped>
.site-footer {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 6px 14px;
  padding: 12px 24px;
  border-top: 1px solid var(--border);
  background: var(--bg-page);
  color: var(--text-secondary);
  font-size: var(--font-xs);
  line-height: 1.5;
}

.site-footer-copy {
  opacity: 0.85;
}

.site-footer-icp {
  color: var(--text-secondary);
  text-decoration: none;
}

.site-footer-icp:hover {
  color: var(--color-primary);
  text-decoration: underline;
}
</style>
