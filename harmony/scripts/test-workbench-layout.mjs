/**
 * test-workbench-layout.mjs · 工作台主页重构的**结构/接线**离线测试
 *
 * ────────────────── 为什么需要它 ──────────────────
 * 本轮把分析内容内联进工作台，涉及三类"编译能过、运行才坏"的契约：
 *   ① 7 个 RevealCard 的 order 必须连续且与 `CARDS_WORKBENCH` 对齐，
 *      否则切页签的离场动画会被提前切断（最后一个组件演到一半页面就换了）；
 *   ② `WorkbenchPageParam` 的 scrollTopTick / refreshing 必须在页面挂载后仍能刷新，
 *      即必须是 `@ObservedV2` + `@Trace`（BUG-10/11 的根因）；
 *   ③ 分析详情页**保留**为历史报告查看器：路由 / 参数 / 页面都在，但工作台不得再引用它；
 *      工作台自己的分析内容必须保持内联。已删除的是 CurrentTaskCard / RecentMediaSection。
 *
 * 这些都是**源码级契约**，不需要真机就能验证；配合运行时的截图验收，
 * 可以把"重构后页面变回来/动画断尾/点最近素材没反应"这类回归挡在构建之前。
 *
 * 用法：node harmony/scripts/test-workbench-layout.mjs
 */

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ETS = join(HERE, '..', 'entry', 'src', 'main', 'ets');
const PAGE_PATH = join(ETS, 'pages', 'WorkbenchPage.ets');
const MAIN_PATH = join(ETS, 'pages', 'MainPage.ets');
const ROUTES_PATH = join(ETS, 'pages', 'PageRoutes.ets');
const PARAMS_PATH = join(ETS, 'types', 'PageParams.ets');
const STORE_PATH = join(ETS, 'store', 'AppStore.ets');
const TRANSIT_PATH = join(ETS, 'common', 'CardTransit.ets');
const HERO_PATH = join(ETS, 'components', 'workbench', 'AnalysisHeroCard.ets');
const HEATMAP_PATH = join(ETS, 'components', 'analysis', 'AnalysisHeatmapCard.ets');
const VLM_PATH = join(ETS, 'components', 'analysis', 'AnalysisVlmCard.ets');
const RING_PATH = join(ETS, 'components', 'common', 'ScoreRing.ets');
const RAIL_PATH = join(ETS, 'components', 'workbench', 'AnalysisStageRail.ets');
const DETAIL_PAGE_PATH = join(ETS, 'pages', 'AnalysisDetailPage.ets');
const DELETED_CARD_PATH = join(ETS, 'components', 'workbench', 'CurrentTaskCard.ets');
const DELETED_RECENT_PATH = join(ETS, 'components', 'workbench', 'RecentMediaSection.ets');
const DAO_PATH = join(ETS, 'persistence', 'AssessmentCacheDao.ets');
const SCHEMA_PATH = join(ETS, 'persistence', 'DbSchema.ets');
const STORAGE_PATH = join(ETS, 'persistence', 'StorageManager.ets');
const CONSTANT_PATH = join(ETS, 'types', 'constant.ts');
const HOLDER_PATH = join(ETS, 'store', 'AnalysisStateHolder.ets');

let failures = 0;
function check(name, ok, detail) {
  if (ok) {
    console.log(`  [OK]   ${name}`);
  } else {
    failures += 1;
    console.log(`  [FAIL] ${name}\n         ${detail}`);
  }
}

/** 递归收集 .ets 源码（用于"不得残留悬空引用"的全量扫描） */
function collectEts(dir, out) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      if (entry === 'build' || entry === 'oh_modules') {
        continue;
      }
      collectEts(full, out);
    } else if (entry.endsWith('.ets')) {
      out.push(full);
    }
  }
  return out;
}

const pageSrc = readFileSync(PAGE_PATH, 'utf8');
const mainSrc = readFileSync(MAIN_PATH, 'utf8');
const routeSrc = readFileSync(ROUTES_PATH, 'utf8');
const paramSrc = readFileSync(PARAMS_PATH, 'utf8');
const storeSrc = readFileSync(STORE_PATH, 'utf8');
const transitSrc = readFileSync(TRANSIT_PATH, 'utf8');
const heroSrc = readFileSync(HERO_PATH, 'utf8');
const heatmapSrc = readFileSync(HEATMAP_PATH, 'utf8');
const daoSrc = readFileSync(DAO_PATH, 'utf8');
const schemaSrc = readFileSync(SCHEMA_PATH, 'utf8');
const storageSrc = readFileSync(STORAGE_PATH, 'utf8');
const constantSrc = readFileSync(CONSTANT_PATH, 'utf8');
const holderSrc = readFileSync(HOLDER_PATH, 'utf8');

// ═══════════════ 1. 7 个转场块的序号与计数 ═══════════════
console.log('1) 工作台转场时间表');
const orders = [...pageSrc.matchAll(/RevealCard\(\{\s*order:\s*(\d+)/g)].map((m) => Number(m[1]));
check('工作台有 7 个 RevealCard（最近素材区块已删除）', orders.length === 7,
  `实际 ${orders.length}：${orders.join(',')}`);
check('order 恰好是 0..6 且不重复', orders.slice().sort((a, b) => a - b).join(',') === '0,1,2,3,4,5,6',
  orders.join(','));
check('CardTransit.CARDS_WORKBENCH = 7', /CARDS_WORKBENCH: number = 7/.test(transitSrc),
  '未找到 "CARDS_WORKBENCH: number = 7"');
check('页面有 scrollTopTick 回顶监听', /@Monitor\('pageParam\.scrollTopTick'\)/.test(pageSrc),
  '未找到 @Monitor(\'pageParam.scrollTopTick\')');

// ═══════════════ 2. 工作台参数的可观察契约 ═══════════════
console.log('\n2) 工作台参数的可观察契约');
check('WorkbenchPageParam 是 @ObservedV2',
  /@ObservedV2\s+export class WorkbenchPageParam/.test(paramSrc), '缺少 @ObservedV2');
for (const [label, re] of [
  ['scrollTopTick @Trace', /@Trace scrollTopTick: number/],
  ['refreshing @Trace', /@Trace refreshing: boolean/]
]) {
  check(label, re.test(paramSrc), `未匹配 ${re}`);
}
check('已移除 focusMediaId 等历史查看字段', !/focusMediaId|focusTick|focusReportScore/.test(paramSrc),
  'PageParams 仍残留 focus 字段');
check('已移除 onSelectRecent / onViewAll / onOpenTask',
  !/onSelectRecent|onViewAll|onOpenTask/.test(paramSrc),
  'PageParams 仍残留旧回调');
check('新增 onReanalyze(mediaId, mediaName, mediaType)',
  /onReanalyze: \(mediaId: string, mediaName: string, mediaType: MediaType\) => void/.test(paramSrc),
  '未找到 onReanalyze 三参签名');
check('新增 onCancelAnalysis 回调', /onCancelAnalysis: \(\) => void/.test(paramSrc),
  '未找到 onCancelAnalysis');

// ═══════════════ 3. 分析内容确实内嵌在工作台 ═══════════════
console.log('\n3) 分析内容内嵌');
for (const [label, re] of [
  ['hero 卡已挂载', /AnalysisHeroCard\(\{/],
  ['热力图卡已挂载', /AnalysisHeatmapCard\(\{/],
  ['情绪曲线卡已挂载', /EmotionCurveCard\(\{ view: this\.curveView \}\)/],
  ['严重度分布卡已挂载', /SeverityDistributionCard\(\{ view: this\.severityView \}\)/],
  ['智能解读卡已挂载', /AnalysisVlmCard\(\{/],
  ['按 mediaId 取本素材会话', /analysisSessionOf\(current\.mediaId\)/],
  ['最新报告作为 hero 回退', /get latestReport\(\): RecentMediaModel \| null/]
]) {
  check(label, re.test(pageSrc), `未匹配 ${re}`);
}
check('hero 有首帧缩略图', /firstFrameUrl/.test(heroSrc), 'hero 未使用 firstFrameUrl');
check('hero 已移除「回到当前任务」chip', !/returnToTaskLabel|onOpenTask/.test(heroSrc),
  'hero 仍残留 returnToTaskLabel / onOpenTask');
check('热力图卡按传入 frames 取数', /buildHeatmapView\(this\.frames/.test(heatmapSrc),
  '热力图卡未按 this.frames 取数');
check('门面新增 firstFrameUrlOfMedia', /public firstFrameUrlOfMedia\(mediaId: string\)/.test(storeSrc),
  'AppStore 缺少 firstFrameUrlOfMedia');
check('页面按 restored 显示「上次评估」', /currentTaskRestored/.test(storeSrc) && /get restored/.test(pageSrc),
  '缺少 currentTaskRestored / restored 接线');

// ═══════════════ 4. 分析详情页仅服务历史报告 ═══════════════
console.log('\n4) 分析详情页仅服务历史报告');
check('AnalysisDetailPage.ets 仍存在（历史报告查看器）', existsSync(DETAIL_PAGE_PATH), '文件缺失');
check('CurrentTaskCard.ets 已删除', !existsSync(DELETED_CARD_PATH), '文件仍存在');
check('RecentMediaSection.ets 已删除', !existsSync(DELETED_RECENT_PATH), '文件仍存在');
check('工作台不再挂载最近素材', !/RecentMediaSection|recentSection/.test(pageSrc),
  'WorkbenchPage 仍残留 RecentMediaSection');
check('MainPage 不再注入最近素材回调', !/onSelectRecent|onViewAll/.test(mainSrc),
  'MainPage 仍残留 onSelectRecent / onViewAll');
check('PageRoutes 保留 analysisDetail 路由', /ANALYSIS_DETAIL_ROUTE/.test(routeSrc)
  && /'analysisDetail'/.test(routeSrc), 'PageRoutes 缺少 analysisDetail 路由');
check('PageParams 保留 AnalysisDetailPageParam', /export class AnalysisDetailPageParam/.test(paramSrc),
  'PageParams 缺少 AnalysisDetailPageParam');
check('MainPage 保留 detailParam 与详情页分发', /detailParam/.test(mainSrc)
  && /ANALYSIS_DETAIL_ROUTE/.test(mainSrc), 'MainPage 缺少 detailParam / 详情页分发');
check('工作台不再引用分析详情页',
  !/AnalysisDetailPage|ANALYSIS_DETAIL_ROUTE|AnalysisDetailPageParam/.test(pageSrc),
  'WorkbenchPage 仍引用详情页');
check('历史报告通过 onOpenReport 打开详情',
  /onOpenReport/.test(paramSrc) && /reportsParam\.onOpenReport/.test(mainSrc)
  && /openReportDetail/.test(mainSrc), '历史报告 → 详情页的接线缺失');
check('MainPage 把整个 pageParam 交给工作台',
  /WorkbenchPage\(\{ pageParam: param as WorkbenchPageParam \}\)/.test(mainSrc),
  '未找到 WorkbenchPage({ pageParam: ... })');
check('上传完成走 navStack.pop()', /this\.navStack\.pop\(\)/.test(mainSrc),
  '未找到上传后的 navStack.pop()');

const ALLOWED_DETAIL_REFS = new Set([
  'pages/AnalysisDetailPage.ets',
  'pages/MainPage.ets',
  'pages/PageRoutes.ets',
  'types/PageParams.ets'
]);
const stale = [];
for (const file of collectEts(ETS, [])) {
  const src = readFileSync(file, 'utf8');
  if (/AnalysisDetailPage|ANALYSIS_DETAIL_ROUTE|AnalysisDetailPageParam|RecentMediaSection/.test(src)) {
    const rel = file.slice(ETS.length + 1).replace(/\\/g, '/');
    if (!ALLOWED_DETAIL_REFS.has(rel)) {
      stale.push(rel);
    }
  }
}
check('详情页引用只出现在预期文件（页面 / 路由 / 参数 / 窗口层）',
  stale.length === 0, stale.join(', '));

// ═══════════════ 5. 当前评估持久化 ═══════════════
console.log('\n5) 当前评估持久化');
check('RDB_VERSION 已升到 2', /RDB_VERSION: number = 2/.test(constantSrc),
  'types/constant.ts 中 RDB_VERSION 不是 2');
check('DbSchema 新增工作台评估表', /WorkbenchAssessmentTable/.test(schemaSrc)
  && /WorkbenchAssessmentTable\.createSql/.test(schemaSrc), 'DbSchema 未登记评估表');
check('StorageManager 接入评估 DAO', /AssessmentCacheDao/.test(storageSrc)
  && /assessmentDao\(\)/.test(storageSrc), 'StorageManager 未接入评估 DAO');
check('登出会清空评估缓存', /daoAssessment\.deleteAll\(\)/.test(storageSrc),
  'clearBusinessCache 未清评估表');
check('评估 DAO 已实现 save / loadPayload', /public async save\(/.test(daoSrc)
  && /public async loadPayload\(/.test(daoSrc), 'AssessmentCacheDao 缺少存取方法');
check('AppStore 新增 persistAssessment', /public async persistAssessment\(/.test(storeSrc),
  'AppStore 缺少 persistAssessment');
check('AppStore 新增 restoreAssessment', /public async restoreAssessment\(/.test(storeSrc),
  'AppStore 缺少 restoreAssessment');
check('AppStore 新增 currentTaskRestored', /@Trace currentTaskRestored: boolean/.test(storeSrc),
  'AppStore 缺少 currentTaskRestored');
check('loadAll 会恢复评估', /await this\.restoreAssessment\(\)/.test(storeSrc),
  'loadAll 未调用 restoreAssessment');
check('分析收尾会持久化评估', /await this\.persistAssessment\(\)/.test(storeSrc),
  'onAnalysisFinished 未调用 persistAssessment');
check('桥接器支持 restoreSession', /public restoreSession\(session: AnalysisSessionModel\)/.test(holderSrc),
  'AnalysisStateHolder 缺少 restoreSession');

// ═══════════════ 6. 新组件文件齐全 ═══════════════
console.log('\n6) 新组件文件');
for (const file of [HERO_PATH, HEATMAP_PATH, VLM_PATH, RING_PATH, RAIL_PATH]) {
  check(`存在 ${file.replace(ETS + '\\', '').replace(ETS + '/', '')}`, existsSync(file), '文件缺失');
}

console.log('');
if (failures === 0) {
  console.log('PASS 全部通过：7 段错峰、最近素材已移除、评估持久化/恢复链路已接通、详情页仅服务历史报告。');
  process.exit(0);
}
console.log(`FAIL 存在 ${failures} 处失败。`);
process.exit(1);
