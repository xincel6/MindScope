/**
 * 报告接口 · GET /api/reports · GET /api/report/{media_id}
 *
 * ★ 坑：
 *   1. `/api/report/{media_id}` 的 path 参数是 **int**，传字符串会被 422 拒掉；
 *   2. `ReportListItem.media_id` 是**数字**，而 `MediaItemOut.id` 是字符串，
 *      比较前必须 `normalizeMediaId()` 归一化；
 *   3. 后端**没有**「删报告」「改报告」接口，别按 UI 想象去实现。
 */

import { ReportListOutDto, ReportOutDto } from '../types/Index';
import { HttpClient } from './HttpClient';

/**
 * 报告列表查询参数
 * 传空字符串表示「不筛选」（后端 Query 参数为空串时视作未传）
 */
export interface ReportQuery {
  severity: string;
  mediaType: string;
  page: number;
  limit: number;
}

/** 拼查询串 · 空值不落 URL，避免 ?severity=&media_type= 被后端当非法枚举 */
function buildQuery(query: ReportQuery): string {
  const parts: string[] = [];
  if (query.severity.length > 0) {
    parts.push(`severity=${encodeURIComponent(query.severity)}`);
  }
  if (query.mediaType.length > 0) {
    parts.push(`media_type=${encodeURIComponent(query.mediaType)}`);
  }
  parts.push(`page=${query.page}`);
  parts.push(`limit=${query.limit}`);
  return `?${parts.join('&')}`;
}

/** 报告接口 · 集中对外接口在顶部 */
export class ReportApi {
  /** 分页拉取报告列表 · 响应 `{items, total}` */
  public static list(query: ReportQuery): Promise<ReportListOutDto> {
    return HttpClient.get<ReportListOutDto>(`/api/reports${buildQuery(query)}`);
  }

  /**
   * 按媒体 id 拉该媒体的全部报告（不分页）
   * @param mediaId 数字形式 · 后端 path 参数声明为 int，传非数字会 422
   */
  public static listByMedia(mediaId: number): Promise<ReportOutDto[]> {
    return HttpClient.get<ReportOutDto[]>(`/api/report/${mediaId}`);
  }

  /** 便捷重载：从字符串 id 转数字（解析失败返回 null，调用方据此提示） */
  public static listByMediaIdText(mediaId: string): Promise<ReportOutDto[]> {
    const numeric: number = Number.parseInt(mediaId, 10);
    if (!Number.isFinite(numeric)) {
      return Promise.reject(new Error(`非法媒体 id：${mediaId}`));
    }
    return ReportApi.listByMedia(numeric);
  }
}
