import { onBeforeUnmount, onMounted, ref, type Ref } from 'vue'

/**
 * P5 T4：跟随系统「减弱动效」偏好。
 *
 * ECharts 的入场动画跑在 canvas 里，CSS 的 `prefers-reduced-motion` 规则管不到，
 * 所以图表 option 必须显式传 `animation: false`。这里用 matchMedia 的实时结果
 * 作为 computed 依赖，系统切换偏好时图表会自动重算 option。
 */
export function usePrefersReducedMotion(): Ref<boolean> {
  const reduced = ref(false)
  let media: MediaQueryList | null = null

  const update = () => {
    if (media) reduced.value = media.matches
  }

  onMounted(() => {
    media = window.matchMedia('(prefers-reduced-motion: reduce)')
    update()
    media.addEventListener('change', update)
  })

  onBeforeUnmount(() => {
    media?.removeEventListener('change', update)
    media = null
  })

  return reduced
}
