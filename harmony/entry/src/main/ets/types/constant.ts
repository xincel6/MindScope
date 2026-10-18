/**
 * 表现层常量 · BDI 阈值 / 中文标签 / 颜色 / 干预建议
 *
 * ★ 阈值口径（与后端 severity 分级一致，见 docs 项目分析报告）：
 *      0–13 正常 ｜ 14–19 轻度 ｜ 20–28 中度 ｜ 29+ 重度
 *   Beck 原始切分点是 0-13 / 14-19 / 20-28 / 29-63。
 *
 * 属于「纯常量 + 纯类型」→ 必须是 `.ts`（ArkTS 规则 arkts-no-ts-deps）。
 */

import { MediaType, SeverityLevel } from './enums';

/**
 * BDI-II 满分 · 与后端口径一致（`dashboard/backend/services/vllm.py`：29~63 分属重度）
 * ★ 严重度进度条的分母就是它，改这里等于改所有"分数占比"的显示。
 */
export const BDI_MAX_SCORE: number = 63;

/** BDI 分级阈值常量 */
export class BdiThreshold {
  /** ≤ 13 视为正常 */
  public static readonly normalMax: number = 13;
  /** ≤ 19 视为轻度 */
  public static readonly mildMax: number = 19;
  /** ≤ 28 视为中度 */
  public static readonly moderateMax: number = 28;

  /** 分数 → 严重度原始字符串（与后端 severity 口径一致）· 全工程唯一定义处 */
  public static severityOf(score: number): string {
    if (score <= BdiThreshold.normalMax) {
      return SeverityLevel.none as string;
    }
    if (score <= BdiThreshold.mildMax) {
      return SeverityLevel.mild as string;
    }
    if (score <= BdiThreshold.moderateMax) {
      return SeverityLevel.moderate as string;
    }
    return SeverityLevel.severe as string;
  }

  /** 分数 → 严重度枚举 */
  public static levelOf(score: number): SeverityLevel {
    return BdiThreshold.severityOf(score) as SeverityLevel;
  }
}

/** 严重度展示配置 */
export interface SeverityMeta {
  level: SeverityLevel;
  /** 中文标签 */
  label: string;
  /** 十六进制色值 */
  color: string;
  /** 干预建议 */
  advice: string;
}

const SEVERITY_META_LIST: SeverityMeta[] = [
  {
    level: SeverityLevel.none,
    label: '正常',
    color: '#16a34a',
    advice: '未见明显抑郁倾向，保持规律作息与适度运动即可。'
  },
  {
    level: SeverityLevel.mild,
    label: '轻度',
    color: '#0284c7',
    advice: '存在轻度情绪困扰，建议持续记录并关注睡眠与社交状态。'
  },
  {
    level: SeverityLevel.moderate,
    label: '中度',
    color: '#d97706',
    advice: '情绪困扰较明显，建议尽快寻求专业心理咨询评估。'
  },
  {
    level: SeverityLevel.severe,
    label: '重度',
    color: '#dc2626',
    advice: '评分较高，强烈建议立即联系精神科或心理专业机构就诊。'
  }
];

/** 严重度以字符串取配置时的兜底 */
const SEVERITY_META_MAP: Record<string, SeverityMeta> = {
  'none': SEVERITY_META_LIST[0],
  'mild': SEVERITY_META_LIST[1],
  'moderate': SEVERITY_META_LIST[2],
  'severe': SEVERITY_META_LIST[3]
};

/** 媒体类型中文标签 */
const MEDIA_TYPE_LABEL_MAP: Record<string, string> = {
  'image': '图片',
  'video': '视频'
};

/** 表现层常量总入口 · 全部为静态只读，UI 直接引用 */
export class UiConstant {
  /** 严重度全部档位（按由轻到重排列，UI 图例/图例顺序用） */
  public static readonly severityList: SeverityLevel[] = [
    SeverityLevel.none,
    SeverityLevel.mild,
    SeverityLevel.moderate,
    SeverityLevel.severe
  ];

  /** 报告筛选器用的严重度下拉选项（首项为「全部」） */
  public static readonly severityFilterOptions: string[] = ['全部', '正常', '轻度', '中度', '重度'];

  /** 报告筛选器用的媒体类型下拉选项（首项为「全部」） */
  public static readonly mediaTypeFilterOptions: string[] = ['全部', '图片', '视频'];

  /** 报告列表默认分页大小（与后端 /api/reports 默认一致） */
  public static readonly defaultPageSize: number = 20;

  /** 一级页面路由 */
  public static readonly routeIndex: string = 'pages/Index';

  /** 页面主色 */
  public static readonly primaryColor: string = '#0284c7';

  /** 错误提示色 */
  public static readonly errorColor: string = '#dc2626';

  /** 文本主色 / 次色 */
  public static readonly textPrimaryColor: string = '#0f172a';
  public static readonly textSecondaryColor: string = '#64748b';

  /** 严重度配置（按枚举取） */
  public static severityMeta(level: SeverityLevel): SeverityMeta {
    const hit: SeverityMeta | undefined = SEVERITY_META_MAP[level as string];
    return hit !== undefined ? hit : SEVERITY_META_LIST[0];
  }

  /** 严重度中文标签（按后端原始字符串取，容错未知值） */
  public static severityLabel(raw: string): string {
    const hit: SeverityMeta | undefined = SEVERITY_META_MAP[raw];
    return hit !== undefined ? hit.label : raw;
  }

  /** 严重度颜色（按后端原始字符串取） */
  public static severityColor(raw: string): string {
    const hit: SeverityMeta | undefined = SEVERITY_META_MAP[raw];
    return hit !== undefined ? hit.color : UiConstant.textSecondaryColor;
  }

  /**
   * 严重度中文标签（按枚举取）
   * ★ 与 `severityLabel(raw)` 的区别：这个入参已经是归一化后的枚举，
   *   分数换算场景（`BdiThreshold.levelOf(score)`）直接拿它，不必再转字符串。
   */
  public static severityLabelOf(level: SeverityLevel): string {
    return UiConstant.severityMeta(level).label;
  }

  /** 严重度颜色（按枚举取） */
  public static severityColorOf(level: SeverityLevel): string {
    return UiConstant.severityMeta(level).color;
  }

  /** 严重度干预建议 */
  public static severityAdvice(raw: string): string {
    const hit: SeverityMeta | undefined = SEVERITY_META_MAP[raw];
    return hit !== undefined ? hit.advice : '';
  }

  /** 媒体类型中文标签 */
  public static mediaTypeLabel(raw: string): string {
    const hit: string | undefined = MEDIA_TYPE_LABEL_MAP[raw];
    return hit !== undefined ? hit : raw;
  }

  /** 媒体类型枚举 → 中文标签 */
  public static mediaTypeLabelOf(type: MediaType): string {
    return UiConstant.mediaTypeLabel(type as string);
  }
}

/** 全局共享的 preferences 实例名 */
export const PREFERENCES_NAME: string = 'mindscope_store';

/** RDB 库名 */
export const RDB_STORE_NAME: string = 'mindscope.db';

/** RDB 当前版本号 · 改表结构时必须 +1 并补迁移分支 */
export const RDB_VERSION: number = 2;

/** 令牌本地有效期（毫秒）· 后端 JWT 为 7 天，本地留 1 小时余量 */
export const TOKEN_TTL_MS: number = 7 * 24 * 60 * 60 * 1000 - 60 * 60 * 1000;

/** hilog 域号 */
export const LOG_DOMAIN: number = 0x8f10;

/** hilog 统一 tag */
export const LOG_TAG: string = 'MindScope';
