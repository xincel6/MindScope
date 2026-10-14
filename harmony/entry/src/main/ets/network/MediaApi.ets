/**
 * 媒体接口 · GET /api/media/list · DELETE /api/media/{id} · POST /api/upload/image
 *
 * ★ 三个坑：
 *   1. `MediaItemOut.id` 是**字符串**（`schemas.py:34` 是 `str`）；
 *   2. `/api/upload/image` 响应**只有 4 个字段**，其余需客户端补齐（见 Mapper.toUploadedMedia）；
 *   3. 列表接口**没有分页参数**，一次全量返回。
 */

import { MediaListOutDto, MediaItemOutDto, UploadImageOutDto } from '../types/Index';
import { HttpClient, UploadFileSpec } from './HttpClient';

/** 删除结果 */
export interface DeleteMediaResult {
  ok: boolean;
}

/** 媒体接口 · 集中对外接口在顶部 */
export class MediaApi {
  /** 拉取全部媒体（响应形如 `{items:[...]}`） */
  public static async list(): Promise<MediaItemOutDto[]> {
    const out: MediaListOutDto = await HttpClient.get<MediaListOutDto>('/api/media/list');
    const items: MediaItemOutDto[] | undefined = out.items;
    return items === undefined || items === null ? [] : items;
  }

  /** 删除媒体 · 注意 mediaId 传字符串（后端接的是 str 也能吃 int，但统一字符串最稳） */
  public static async deleteMedia(mediaId: string): Promise<boolean> {
    const result: DeleteMediaResult = await HttpClient.del<DeleteMediaResult>(`/api/media/${mediaId}`);
    return result.ok === true;
  }

  /**
   * 上传图片 · multipart，字段名必须是 `file`
   * ★ 返回体不完整（缺 thumbnail_url / duration / created_at），调用方必须走
   *   `Mapper.toUploadedMedia(dto, new Date())` 补齐后再入 store/RDB。
   */
  public static uploadImage(file: UploadFileSpec): Promise<UploadImageOutDto> {
    return HttpClient.upload<UploadImageOutDto>('/api/upload/image', 'file', file);
  }
}
