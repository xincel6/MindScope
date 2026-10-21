/**
 * MindScope · Web 端设计令牌的 TS 镜像（P0）
 *
 * 为什么需要两份：ECharts 与 PDF 导出（html2canvas 模板字符串）读不到 CSS 自定义属性，
 * 只能拿字面值。所以本文件与 ../styles/tokens.css **逐条一一对应**，不允许单独改这里：
 * 键名 = tokens.css 里去掉 `--` 的变量名；数值必须完全相同
 * （尺寸/时长写成 number，单位为 px / ms；颜色、阴影、渐变写字符串）。
 *
 * 一致性由 `node scripts/check-tokens.mjs` 的 [E] 项机械校验，漂移即报错。
 * 来源仍是 harmony/entry/src/main/ets/common/UiTheme.ets（严重度四色来自
 * UiConstant.severityMeta()），逐条出处见 tokens.css 的行尾注释。
 */

export const tokens = {
  // ── §2.2 底色 / 描边 ──
  'bg-page': '#F2F3F7',
  'bg-card': '#FFFFFF',
  'bg-inset': '#E9EDF3',
  'bg-skeleton': '#DCE3EC',
  'bg-press': '#F2F8F7',
  border: '#E5E6EB',

  // ── §2.2 功能色 / 文字 / 状态 ──
  'color-primary': '#0D9488',
  'color-primary-text': '#0F766E',
  'color-primary-button': '#0F766E',
  'color-accent': '#0284C7',
  'color-danger': '#DC2626',
  'color-danger-soft': '#FEF2F2',
  'color-warning': '#D97706',
  'color-warning-soft': 'color-mix(in srgb, var(--color-warning) 8%, #FFFFFF)',
  'color-warning-text': '#B45309',
  'text-primary': '#1D2129',
  'text-secondary': '#4E5969',
  'status-online': '#16A34A',
  'status-offline': '#DC2626',

  // ── §2.2 严重度数据色（填充 / 文字态） ──
  'severity-none': '#16A34A',
  'severity-mild': '#0284C7',
  'severity-moderate': '#D97706',
  'severity-severe': '#DC2626',
  'severity-none-text': '#15803D',
  'severity-mild-text': '#0369A1',
  'severity-moderate-text': '#B45309',
  'severity-severe-text': '#B91C1C',

  // ── §2.2 图表 ──
  'chart-1': '#17B26A',
  'chart-2': '#2E6BE6',
  'chart-3': '#F79009',
  'chart-4': '#F04438',
  'chart-threshold-1': '#2E6BE6',
  'chart-threshold-2': '#F79009',
  'chart-grid': '#E5E6EB',
  'chart-axis': '#94A3B8',
  'heat-1': '#0000FF',
  'heat-2': '#00FFFF',
  'heat-3': '#00FF00',
  'heat-4': '#FFFF00',
  'heat-5': '#FF0000',

  // ── §2.3 字号 6 档 + 图表轴例外（px） ──
  'font-xs': 12,
  'font-sm': 14,
  'font-base': 16,
  'font-title': 22,
  'font-metric-sm': 24,
  'font-metric': 32,
  'font-axis': 11,

  // ── §2.4 间距 8 档 + 布局（px） ──
  'space-1': 4,
  'space-2': 8,
  'space-3': 12,
  'space-4': 16,
  'space-5': 24,
  'space-6': 32,
  'page-padding': 16,
  'content-gap': 16,
  'header-height': 56,
  'nav-width': 240,

  // ── §2.5 圆角 4 档（px） ──
  'radius-card': 16,
  'radius-control': 12,
  'radius-tag': 8,
  'radius-pill': 999,

  // ── §2.6 阴影 2 级 ──
  'shadow-card': '0 1px 2px rgba(29, 33, 41, 0.04), 0 3px 14px rgba(29, 33, 41, 0.08)',
  'shadow-popover': '0 8px 24px rgba(29, 33, 41, 0.10)',

  // ── §2.7 动效（ms / 无量纲） ──
  'motion-press': 120,
  'motion-enter': 260,
  stagger: 55,
  'press-scale': 0.985,

  // ── §2.8 渐变白名单 ──
  'gradient-brand': 'linear-gradient(160deg, #22B49C 0%, #0C7A69 100%)',
  'gradient-kpi': 'linear-gradient(180deg, #E8F6EF 0%, #FFFFFF 100%)',

  // ── 焦点环（Web 新增） ──
  'focus-ring': '0 0 0 2px var(--bg-card), 0 0 0 4px var(--color-primary-text)',
} as const

/** tokens.css 里定义的令牌名（不含 `--` 前缀） */
export type TokenName = keyof typeof tokens
