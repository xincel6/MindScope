/**
 * 统计接口 · GET /api/stats
 *
 * 响应含 `severity_distribution`（dict）、`bdi_trend`（数组）、`recent_reports`（联表列表）。
 * 后端没有筛选参数，一次全量返回。
 */

import { StatsOutDto } from '../types/Index';
import { HttpClient } from './HttpClient';

/** 统计接口 · 集中对外接口在顶部 */
export class StatsApi {
  /** 拉取统计面板数据 */
  public static stats(): Promise<StatsOutDto> {
    return HttpClient.get<StatsOutDto>('/api/stats');
  }
}
