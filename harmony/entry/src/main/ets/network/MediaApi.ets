/**
 * 媒体接口 · GET /api/media/list · DELETE /api/media/{id} · POST /api/upload/image
 *
 * ★ 三个坑：
 *   1. `MediaItemOut.id` 是**字符串**（`schemas.py:34` 是 `str`）；
 *   2. `/api/upload/image` 响应**只有 4 个字段**，其余需客户端补齐（见 Mapper.toUploadedMedia）；
 *   3. 列表接口**没有分页参数**，一次全量返回。
 */

import { MediaListOutDto, MediaItemOutDto, UpdatePatientReqDto, UploadImageOutDto } from '../types/Index';
import { HttpClient, UploadFileSpec } from './HttpClient';

/** 删除结果 */
export interface DeleteMediaResult {
  ok: boolean;
}

/** 更新患者名结果 */
export interface UpdatePatientResult {
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

  /**
   * 上传素材（图片**或视频**）
   *
   * ★ 名字与路径不一致是**后端现状**，不是笔误：
   *   后端只有一个 `/api/upload/image` 端点（`routers/upload.py:19`），
   *   但它的白名单 `ALLOWED_EXTENSIONS` 同时包含 `.mp4/.avi/.mov/.webm`，
   *   并会按扩展名把 `MediaAsset.type` 落成 `video`。
   *   所以视频走的就是这个端点 —— 这里保留路径原样，只把客户端侧名字说清楚，
   *   将来后端拆出 `/api/upload/media` 时，只需改本方法内部一行。
   *
   * ★ 视频文件（几十 MB）比图片慢得多，因此上传使用放宽后的超时
   *   （见 `HttpClient.uploadWithTimeout`），不要复用 30s 的读超时。
   */
  public static uploadMedia(file: UploadFileSpec): Promise<UploadImageOutDto> {
    return HttpClient.uploadWithTimeout<UploadImageOutDto>(
      '/api/upload/image', 'file', file, HttpClient.uploadTimeoutMs
    );
  }

  /** 上传图片并附带患者名（`patient` 走 query 参数，供素材库患者命名用） */
  public static uploadImageWithPatient(file: UploadFileSpec, patient: string): Promise<UploadImageOutDto> {
    const path: string = patient.length > 0
      ? `/api/upload/image?patient=${encodeURIComponent(patient)}`
      : '/api/upload/image';
    return HttpClient.upload<UploadImageOutDto>(path, 'file', file);
  }

  /** 给素材命名/改所属患者 · PUT /api/media/{id}/patient（鸿蒙 RequestMethod 无 PATCH，用 PUT） */
  public static async updatePatient(mediaId: string, patient: string): Promise<boolean> {
    const body: UpdatePatientReqDto = { patient: patient };
    const result: UpdatePatientResult = await HttpClient.put<UpdatePatientResult>(
      `/api/media/${mediaId}/patient`, JSON.stringify(body)
    );
    return result.ok === true;
  }
}
