/**
 * types/ 统一出口 · 全工程**唯一**的对外类型出口
 *
 * 规矩（docs/本轮开发交接.md 第 5.4 节）：
 *  - **显式具名导出**，不用 `export *`（ArkTS 对聚合导出有歧义，且具名导出能点得进去）
 *  - 其它目录一律 `import { XxxModel } from '../types/Index'`，不深挖到具体文件，
 *    这样将来拆/并类型文件不会波及调用方。
 *
 * 后缀分工：
 *  - `enums.ts` / `dto.ts` / `model.ts` / `constant.ts` / `mapper.ts` → 纯 TS，Web 端可直接复用
 *  - `storeState.ets` → 含 `@ObservedV2` / `@Trace`，ArkTS 专用
 *
 * ⚠ 本文件是 `.ts`，因此**不能** re-export `storeState.ets`（`arkts-no-ts-deps`：
 *   `.ts` 不允许 import `.ets`）。渲染层需要响应式状态类型时，
 *   请直接 `import { AppState } from '../types/storeState'`。
 */

// ── 枚举 ──
export {
  SeverityLevel, MediaType, SocketState, BootPhase, ApiStatus, TaskStatus, AuthFailKind
} from './enums';

// ── 常量与配置 ──
export {
  BdiThreshold, UiConstant, SeverityMeta, PREFERENCES_NAME, RDB_STORE_NAME,
  RDB_VERSION, TOKEN_TTL_MS, LOG_DOMAIN, LOG_TAG, BDI_MAX_SCORE
} from './constant';

// ── Wire DTO（唯一允许 snake_case 的一层）──
export {
  LoginReqDto, RegisterReqDto, TokenOutDto, UserOutDto, MediaItemOutDto, MediaListOutDto,
  UploadImageOutDto, UpdatePatientReqDto, ReportOutDto, ReportListItemDto, ReportListOutDto,
  BdiTrendPointDto, StatsOutDto, AnalysisReqDto, AnalysisResDto, FaceB64ReqDto, FaceAnalyzeOutDto,
  AnalysisFrameDto, WsInboundDto, HealthOutDto, ErrorBodyDto
} from './dto';

// ── 领域模型（严格驼峰）──
export {
  UserModel, SessionModel, MediaItemModel, DiagnosisReportModel, ReportListItemModel,
  ReportPageModel, ReportFilterModel, BdiTrendPointModel, StatsModel, SeverityBucketModel,
  AnalysisFrameModel, AnalysisSessionModel, FaceAnalyzeModel, HealthModel, ActionResultModel,
  MediaOptionModel, DiagnosisReportNotes, CurrentTaskModel, RecentMediaModel, PickedMediaModel,
  AnalysisFocusModel, WorkbenchHeroModel, emptyWorkbenchHeroModel, WorkbenchAssessmentModel
} from './model';

// ── 映射器 ──
export { Mapper, normalizeMediaId, formatDateLocal, formatDateTimeLocal } from './mapper';
export type { DbRow } from './mapper';
