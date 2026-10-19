/**
 * MediaStore · 媒体库（`BaseStore` 子类）
 *
 * 数据来源：服务端 `/api/media/list`（无分页，一次全量）
 * 离线兜底：RDB 镜像表 `media_asset`（冷启动先灌内存，UI 立即可见）
 *
 * 对外暴露的字段：`items` / `current` / `loading` / `errorMsg` / `lastSyncAt`
 * 对外暴露的方法：`refresh` / `loadFromCache` / `warmUp` / `deleteMedia` / `uploadImage`
 *                 `findById` / `options` / `setFilter` / `clear`
 */

import { ApiConfig } from '../common/ApiConfig';
import { MediaApi } from '../network/MediaApi';
import { isNetworkFailure, toApiError } from '../network/ApiError';
import { UploadFileSpec } from '../network/HttpClient';
import { StorageManager } from '../persistence/StorageManager';
import {
  ActionResultModel, Mapper, MediaItemModel, MediaItemOutDto, MediaOptionModel, MediaType,
  normalizeMediaId, UploadImageOutDto
} from '../types/Index';
import { BaseStore } from './BaseStore';

/** 媒体库 · 集中对外接口在顶部 */
@ObservedV2
export class MediaStore extends BaseStore {
  // ────────────────── 对外字段（UI 直接读）──────────────────

  /** 媒体列表 · UI 唯一读数来源 */
  @Trace items: MediaItemModel[] = [];

  /** 当前查看的单条媒体（详情页用） */
  @Trace current: MediaItemModel | null = null;

  @Trace loading: boolean = false;
  @Trace errorMsg: string = '';
  @Trace lastSyncAt: number = 0;

  /** 媒体库筛选（null = 全部） */
  @Trace typeFilter: MediaType | null = null;

  /** 最近一次成功上传的素材 · 供窗口层拿到 id 去开分析会话 */
  @Trace lastUploaded: MediaItemModel | null = null;

  /** 当前患者名筛选（空串 = 全部患者） */
  @Trace patientFilter: string = '';

  // ────────────────── 单例 ──────────────────

  private static instance: MediaStore | null = null;

  public static get(): MediaStore {
    if (MediaStore.instance === null) {
      MediaStore.instance = new MediaStore();
    }
    return MediaStore.instance;
  }

  // ────────────────── 派生数据（UI 计算属性）──────────────────

  /** 应用了筛选后的列表（UI 的 ForEach 直接吃这个） */
  public visibleItems(): MediaItemModel[] {
    const filter: MediaType | null = this.typeFilter;
    if (filter === null) {
      return this.items;
    }
    const out: MediaItemModel[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].type === filter) {
        out.push(this.items[i]);
      }
    }
    return out;
  }

  /** 条目总数 */
  public totalCount(): number {
    return this.items.length;
  }

  /** 图片数量 */
  public imageCount(): number {
    return this.countByType(MediaType.image);
  }

  /**
   * 去重后的患者名列表（含「未命名」占位，空串归为"未命名"）
   * ★ UI 顶部筛选器直接用；顺序按首次出现，稳定不跳。
   */
  public patientOptions(): string[] {
    const out: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const p: string = this.items[i].patient;
      const label: string = p.length > 0 ? p : '未命名';
      if (!this.containsString(out, label)) {
        out.push(label);
      }
    }
    return out;
  }

  /** 当前患者筛选（空串 = 全部） */
  public patientFilterValue(): string {
    return this.patientFilter;
  }

  /** 设置患者筛选（空串 = 全部患者） */
  public setPatientFilter(patient: string): void {
    this.patientFilter = patient;
  }

  /** 应用了「患者 + 类型」双重筛选后的列表（UI 直接吃） */
  public filteredItems(type: MediaType): MediaItemModel[] {
    const out: MediaItemModel[] = [];
    const patient: string = this.patientFilter;
    for (let i = 0; i < this.items.length; i++) {
      const item: MediaItemModel = this.items[i];
      if (item.type !== type) {
        continue;
      }
      // 患者筛选：空串 = 全部；否则按「未命名」或具体名字匹配
      if (patient.length > 0) {
        const itemPatient: string = item.patient.length > 0 ? item.patient : '未命名';
        if (itemPatient !== patient) {
          continue;
        }
      }
      out.push(item);
    }
    return out;
  }

  /** 是否已筛选患者（用于顶部显示「清除筛选」） */
  public hasPatientFilter(): boolean {
    return this.patientFilter.length > 0;
  }

  /** 视频数量 */
  public videoCount(): number {
    return this.countByType(MediaType.video);
  }

  /** 按 id 查找（★ 入参可能是数字形态，内部会归一化成字符串再比） */
  public findById(mediaId: string): MediaItemModel | null {
    const normalized: string = normalizeMediaId(mediaId);
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === normalized) {
        return this.items[i];
      }
    }
    return null;
  }

  /** 下拉选项（筛选器/选择器用） */
  public options(): MediaOptionModel[] {
    const out: MediaOptionModel[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: MediaItemModel = this.items[i];
      const option: MediaOptionModel = { id: item.id, name: item.name, type: item.type };
      out.push(option);
    }
    return out;
  }

  /** 拿到可直接喂给 Image/Video 的绝对地址（自动补服务端前缀） */
  public playableUrl(item: MediaItemModel): string {
    return ApiConfig.resolveMediaUrl(item.url);
  }

  /** 缩略图地址 · 后端可能没给缩略图，退回原图 */
  public thumbnailUrl(item: MediaItemModel): string {
    const thumb: string = item.thumbnailUrl;
    return ApiConfig.resolveMediaUrl(thumb.length > 0 ? thumb : item.url);
  }

  // ────────────────── 对外方法 ──────────────────

  /** 设置筛选（null = 全部） */
  public setFilter(type: MediaType | null): void {
    this.typeFilter = type;
  }

  /** 选中一条媒体（详情页进入时调用） */
  public select(mediaId: string): MediaItemModel | null {
    this.current = this.findById(mediaId);
    return this.current;
  }

  /** 实现 BaseStore：从服务端拉全量列表，成功后回写 RDB 镜像表 */
  public async refresh(): Promise<void> {
    this.beginLoad();
    try {
      const dtos: MediaItemOutDto[] = await MediaApi.list();
      const items: MediaItemModel[] = Mapper.toMediaItems(dtos);
      this.items = items;
      // 回写镜像表（离线兜底的数据来源）
      await StorageManager.mediaDao().replaceAll(items);
      await StorageManager.markSynced();
      this.endLoadOk();
      this.log().i(`媒体库已同步 · ${items.length} 条`);
    } catch (err) {
      const apiErr = toApiError(err as Object);
      if (isNetworkFailure(err as Object)) {
        // 网络不通不算错误：静默切离线，本地还有缓存
        this.loading = false;
        this.log().w('媒体库同步失败（网络不可达）· 使用本地缓存');
        return;
      }
      this.endLoadErr(apiErr.message);
      this.log().e('媒体库同步失败', err as Object);
    }
  }

  /** 从 RDB 镜像表读回（离线兜底 / 冷启动预热） */
  public async loadFromCache(): Promise<number> {
    if (!StorageManager.isRdbReady()) {
      return 0;
    }
    const cached: MediaItemModel[] = await StorageManager.mediaDao().loadAll();
    if (cached.length > 0) {
      this.items = cached;
      this.lastSyncAt = await StorageManager.lastSyncAt();
      this.log().i(`媒体库已从本地缓存恢复 · ${cached.length} 条`);
    }
    return cached.length;
  }

  /**
   * 冷启动预热 · 有本地数据就先进内存，随后由 AppBootstrap 触发在线刷新
   * @returns 是否拿到过缓存数据
   */
  public async warmUp(): Promise<boolean> {
    const count: number = await this.loadFromCache();
    return count > 0;
  }

  /** 删除媒体 · 服务端成功后同步删本地镜像，并清掉已选中的详情 */
  public async deleteMedia(mediaId: string): Promise<ActionResultModel> {
    const normalized: string = normalizeMediaId(mediaId);
    try {
      await MediaApi.deleteMedia(normalized);
      await StorageManager.mediaDao().deleteById(normalized);
      this.removeLocal(normalized);
      this.log().i(`媒体已删除 · ${normalized}`);
      return MediaStore.ok('已删除');
    } catch (err) {
      const apiErr = toApiError(err as Object);
      this.log().e(`删除媒体失败 · ${normalized}`, err as Object);
      return MediaStore.fail(apiErr.message);
    }
  }

  /**
   * 上传素材（图片或视频）· multipart 字段名固定为 `file`
   *
   * ★ 后端响应只有 4 个字段，这里用 `Mapper.toUploadedMedia` 补齐后入 store + 镜像表。
   * ★ 视频与图片是**同一个端点**（后端 `/api/upload/image` 的白名单含视频扩展名），
   *   所以这里不按类型分流；类型由响应里的 `type` 字段决定（服务端按扩展名判定）。
   */
  public async uploadMedia(file: UploadFileSpec): Promise<MediaItemModel | null> {
    const dto: UploadImageOutDto = await MediaApi.uploadMedia(file);
    return this.commitUpload(dto, '');
  }

  /** 上传素材并附带患者名（供素材库患者命名用）· 返回整条模型便于窗口层拿 id */
  public async uploadMediaWithPatient(file: UploadFileSpec, patient: string): Promise<MediaItemModel | null> {
    const dto: UploadImageOutDto = await MediaApi.uploadImageWithPatient(file, patient);
    return this.commitUpload(dto, patient);
  }

  /** 上传图片（旧签名兼容）· 语义等价于 `uploadMedia` 的图片场景 */
  public async uploadImage(file: UploadFileSpec): Promise<ActionResultModel> {
    const item: MediaItemModel | null = await this.uploadMedia(file);
    if (item === null) {
      return MediaStore.fail(this.errorMsg.length > 0 ? this.errorMsg : '上传失败');
    }
    return MediaStore.ok('上传成功');
  }

  /** 上传图片并附带患者名（供素材库患者命名用） */
  public async uploadImageWithPatient(file: UploadFileSpec, patient: string): Promise<ActionResultModel> {
    const item: MediaItemModel | null = await this.uploadMediaWithPatient(file, patient);
    if (item === null) {
      return MediaStore.fail(this.errorMsg.length > 0 ? this.errorMsg : '上传失败');
    }
    return MediaStore.ok('上传成功');
  }

  /**
   * 上传收尾的公共实现：拿到 dto → 补字段 → 入 store + 镜像表 → 返回整条模型
   * ★ `patient` 为空串表示不命名；后端若未回显 patient 则用入参补齐。
   */
  private async commitUpload(dto: UploadImageOutDto, patient: string): Promise<MediaItemModel | null> {
    this.beginLoad();
    try {
      const item: MediaItemModel = Mapper.toUploadedMedia(dto, new Date());
      if (item.patient.length === 0) {
        item.patient = patient;
      }
      this.prependLocal(item);
      await StorageManager.mediaDao().save(item);
      this.endLoadOk();
      this.log().i(`素材已上传 · id=${item.id} type=${item.type as string} · patient=${item.patient}`);
      // ★ 返回整条模型而不是 ActionResultModel：窗口层要拿 id 去开分析会话
      this.lastUploaded = item;
      return item;
    } catch (err) {
      const apiErr = toApiError(err as Object);
      this.endLoadErr(apiErr.message);
      this.log().e('素材上传失败', err as Object);
      return null;
    }
  }

  /** 给素材命名/改所属患者 · 服务端成功后同步更新本地镜像与内存 */
  public async renamePatient(mediaId: string, patient: string): Promise<ActionResultModel> {
    const normalized: string = normalizeMediaId(mediaId);
    try {
      await MediaApi.updatePatient(normalized, patient);
      await StorageManager.mediaDao().updatePatient(normalized, patient);
      this.patchPatientLocal(normalized, patient);
      this.log().i(`素材患者名已更新 · ${normalized} → ${patient}`);
      return MediaStore.ok('已命名');
    } catch (err) {
      const apiErr = toApiError(err as Object);
      this.log().e(`更新患者名失败 · ${normalized}`, err as Object);
      return MediaStore.fail(apiErr.message);
    }
  }

  /** 实现 BaseStore：清空内存（磁盘缓存由 StorageManager.clearBusinessCache 负责） */
  public clear(): void {
    this.items = [];
    this.current = null;
    this.typeFilter = null;
    this.patientFilter = '';
    this.loading = false;
    this.errorMsg = '';
    this.lastSyncAt = 0;
    this.lastUploaded = null;
  }

  /** 实现 BaseStore */
  protected storeName(): string {
    return 'MediaStore';
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  private countByType(type: MediaType): number {
    let total: number = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].type === type) {
        total++;
      }
    }
    return total;
  }

  /** 字符串数组是否已包含目标（避免每次写内联循环） */
  private containsString(list: string[], target: string): boolean {
    for (let i = 0; i < list.length; i++) {
      if (list[i] === target) {
        return true;
      }
    }
    return false;
  }

  /** 内存中就地更新某条素材的患者名（保持 @Trace 触发 UI 刷新） */
  private patchPatientLocal(mediaId: string, patient: string): void {
    const next: MediaItemModel[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: MediaItemModel = this.items[i];
      if (item.id === mediaId) {
        const updated: MediaItemModel = {
          id: item.id,
          name: item.name,
          type: item.type,
          thumbnailUrl: item.thumbnailUrl,
          url: item.url,
          duration: item.duration,
          createdAt: item.createdAt,
          patient: patient
        };
        next.push(updated);
      } else {
        next.push(item);
      }
    }
    this.items = next;
    // 同步当前选中详情（若有）
    const current: MediaItemModel | null = this.current;
    if (current !== null && current.id === mediaId) {
      const updatedCurrent: MediaItemModel = {
        id: current.id,
        name: current.name,
        type: current.type,
        thumbnailUrl: current.thumbnailUrl,
        url: current.url,
        duration: current.duration,
        createdAt: current.createdAt,
        patient: patient
      };
      this.current = updatedCurrent;
    }
  }

  /** 新上传的条目置顶（列表按创建时间倒序，与服务端一致） */
  private prependLocal(item: MediaItemModel): void {
    const next: MediaItemModel[] = [item];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id !== item.id) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
  }

  private removeLocal(mediaId: string): void {
    const next: MediaItemModel[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id !== mediaId) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
    const current: MediaItemModel | null = this.current;
    if (current !== null && current.id === mediaId) {
      this.current = null;
    }
  }

  private static ok(message: string): ActionResultModel {
    const result: ActionResultModel = { ok: true, message: message };
    return result;
  }

  private static fail(message: string): ActionResultModel {
    const result: ActionResultModel = { ok: false, message: message };
    return result;
  }
}
