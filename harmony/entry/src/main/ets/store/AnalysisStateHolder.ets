/**
 * AnalysisStateHolder · WS 回调 → 响应式状态 的桥接（**按素材归档分析结果**）
 *
 * 为什么单独一个文件：`AnalysisSocket` 的回调是**抽象类**（ArkTS 不允许用对象字面量
 * 初始化「带方法」的接口），而回调里要写的是 `@Trace` 状态；把这两件事解耦后：
 *   - `network/AnalysisSocket.ets` 只懂协议；
 *   - `store/AppStore.ets` 只懂状态与业务编排；
 *   - 本文件是两者之间唯一的接缝，改协议或改状态都只动一处。
 *
 * ★ `done` / `error` 之后服务端会主动 close，那是**正常收尾**，
 *   本类据此把 `running` 置回 false，不会去触发重连。
 *
 * ══════════════════ ★★ 本轮（分析页实装轮）的结构性改动 ══════════════════
 * 旧实现：「一份全局帧缓冲」（`state.frameHistory` / `state.scoreHistory`）+ `start()`
 * 里先把它们清空。这带来两个**用户直接看到**的缺陷：
 *
 *   ① **换素材就丢历史**：开始分析 B 时 A 的帧被 `reset()` 清掉；历史素材页没有
 *      自己的帧，只能拿"全局最新一帧"顶替 → 「后上传的素材覆盖了之前的素材」。
 *   ② **热力图张冠李戴**：正因那条"全局最新一帧"兜底，所有素材的历史视图都显示
 *      最近分析的那个人的脸与热度。
 *
 * 现在：「按 mediaId 归档的会话列表」（`state.sessions`）。
 *   · 同一素材再次分析 = **只覆盖它自己那一条**，其它素材的结果原样保留；
 *   · live 会话就是 `mediaId === state.mediaId` 的那一条，**没有第二份帧数据**；
 *   · 历史素材页按 mediaId 取会话，取不到就老实显示"本机未保留逐帧数据"，
 *     **绝不再跨素材兜底**。
 */

import { AnalysisListener, AnalysisSocket } from '../network/AnalysisSocket';
import {
  AnalysisFrameModel, AnalysisSessionModel, BdiThreshold, MediaType, SocketState, TaskStatus, UiConstant
} from '../types/Index';
import { AnalysisState } from '../types/storeState';
import { Logger } from '../common/Logger';

/** 分析结束后需要做的事（统计/报告刷新）· 由 AppStore 注入 */
export type AnalysisFinishedHook = () => Promise<void>;

/** 单个会话最多保留的逐帧分数点数（超出后丢弃最旧的，避免超长视频把数组撑爆） */
export const MAX_SCORE_POINTS: number = 120;

/**
 * live 会话在收帧期间最多保留的帧数
 *
 * 取值依据（服务端 `services/frame_processor.py`）：
 *   · **图片**：只推 **1 帧**（单次推理，`_process_image`）；
 *   · **视频**：按 `total // 60` 采样，目标约 **60 帧**，按 24 一组成批 flush，
 *     最后一组会补重复帧凑满，所以实际略多于 60。
 * 取 90 可完整覆盖一次视频分析，同时把内存钉在可控范围：
 * 每帧含一张 128×128 JPEG 的 base64（约 5–15KB），90 帧 ≈ 0.5–1.3MB。
 */
export const MAX_FRAME_HISTORY: number = 90;

/**
 * 会话收尾（done / error）后帧数组的裁剪上限
 *
 * 为什么收尾还要裁：横向逐帧列表的**渲染上限是 24 格**（见
 * `components/charts/HeatmapViewModel.ets` 的 `MAX_STRIP_TILES`），
 * 保留 30 帧既足够回看，又把"多素材并存"的内存从 ~6MB 压到 ~2MB 量级。
 * 曲线不受影响：分数序列单独存在 `scores` 里，最多 120 点。
 *
 * ★ 裁剪方式是**按时间均匀抽到 30 帧**（保留首尾），不是"从头部切掉、只留最后 30"：
 *   服务端每 24 帧才推理一次，只留尾部 = 列表里全是同一批的同一张图。
 *   均匀抽样后，30 帧仍覆盖整段视频（live 侧上限 90 帧），逐帧列表才有"切分视图"的意义。
 */
export const MAX_ARCHIVE_FRAMES: number = 30;

/**
 * 等距抽样（保留首尾）· 与 `HeatmapViewModel.sampleEvenly` 同一口径
 *
 * 这里不能直接 import 组件层：store 是数据层，不应该依赖 UI 组件目录。
 * 两处实现都很短（十行），保持一致即可；口径一致性由 `test-heatmap-strip.mjs` 的镜像断言守着。
 */
function sampleEvenly(frames: AnalysisFrameModel[], maxCount: number): AnalysisFrameModel[] {
  if (maxCount <= 0) {
    return [];
  }
  if (frames.length <= maxCount) {
    return frames;
  }
  const out: AnalysisFrameModel[] = [];
  const lastIndex: number = frames.length - 1;
  const step: number = lastIndex / (maxCount - 1);
  for (let i = 0; i < maxCount; i++) {
    let index: number = Math.round(i * step);
    if (index < 0) {
      index = 0;
    }
    if (index > lastIndex) {
      index = lastIndex;
    }
    out.push(frames[index]);
  }
  return out;
}

/**
 * 同时保留多少个素材的归档会话
 *
 * 超出后淘汰 `updatedAt` 最旧的那条（**永不淘汰 live 会话**）。
 * 被淘汰的素材再次打开时走"报告分数 + 本机未保留逐帧数据 + 重新分析"分支。
 */
export const MAX_ARCHIVE_SESSIONS: number = 6;

/** WS → 状态 的桥接器 · 集中对外接口在顶部 */
export class AnalysisStateHolder extends AnalysisListener {
  private readonly state: AnalysisState;
  private readonly socket: AnalysisSocket;
  private readonly onFinished: AnalysisFinishedHook;
  private readonly log = Logger.scope('Analysis');

  constructor(state: AnalysisState, onFinished: AnalysisFinishedHook) {
    super();
    this.state = state;
    this.onFinished = onFinished;
    this.socket = new AnalysisSocket(this);
  }

  // ────────────────── 对外接口 ──────────────────

  /**
   * 开始分析一段媒体
   *
   * ★ 只重置 **live 指针** 与"这个素材自己的会话"，其它素材的归档原样保留。
   * ★ `mediaType` 必须传对：图片 / 视频的展示语义（单帧 vs 逐帧）全靠它。
   *
   * @param mediaId 服务端媒体 id（字符串）
   * @param mediaType 素材类型（图片 / 视频）
   */
  public start(mediaId: string, mediaType: MediaType = MediaType.image): void {
    if (this.state.running) {
      this.log.w('已有分析在进行中，先停止旧会话再开始新会话');
      this.stop();
    }
    this.resetLive();
    this.state.mediaId = mediaId;
    this.state.running = true;
    // 该素材重算：覆盖它自己那一条会话（界面立刻回到"收到 0 帧"的干净状态）
    this.writeSession(this.freshSession(mediaId, mediaType));
    this.log.i(`开始分析 · mediaId=${mediaId} type=${mediaType as string}`);
    this.socket.start(mediaId);
  }

  /** 请求取消（★ 视频场景服务端基本已经算完，UI 不应承诺可中断） */
  public cancel(): void {
    this.socket.cancel();
  }

  /**
   * 主动停止并释放连接（登出 / 换账号时必须调用）
   * ★ **不清结果**：用户切走页签再回来，仍能看到那个素材的分数与热力图。
   * ★ 会话状态不动：真在跑的任务会在 `onDone` / `onError` 里收尾。
   */
  public stop(): void {
    this.socket.stop();
    this.state.running = false;
    this.state.socketState = SocketState.idle;
  }

  /** 是否正在分析 */
  public isRunning(): boolean {
    return this.state.running;
  }

  /** 清空全部归档（登出 / 换账号 · 避免看到上一个用户的分析结果） */
  public clearSessions(): void {
    this.state.sessions = [];
    // live 指针一起清：否则登出后 `analysisLiveMediaIdOf()` 仍指向旧素材，
    // 页面会误判成"这条素材正在跑"（虽然此登录态已销毁，但状态要自洽）
    this.state.mediaId = '';
    this.state.lastFrame = null;
    this.state.frameCount = 0;
    this.state.bdiScore = 0;
    this.state.progress = 0;
    this.state.vlmText = '';
    this.state.finalScore = 0;
    this.state.errorMsg = '';
  }

  /**
   * 恢复一次**已收尾**的评估会话（工作台持久化恢复的唯一入口）
   *
   * ★ 只在 App 启动/登录后由 `AppStore.restoreAssessment()` 调用一次。
   * ★ 恢复出来的不是 live 会话：`mediaId` 置空、`running=false`，
   *   于是工作台会按"归档"展示（无取消按钮、无实时进度），文案由页面负责。
   * ★ 同步把 live 指针/镜像字段写成该会话的快照，避免 `currentTask()` 与
   *   `analysisErrorOf()` 之类访问器读到半截状态。
   */
  public restoreSession(session: AnalysisSessionModel): void {
    const frames: AnalysisFrameModel[] = session.frames;
    const lastFrame: AnalysisFrameModel | null =
      frames.length === 0 ? null : frames[frames.length - 1];

    this.state.sessions = [session];
    this.state.mediaId = '';
    this.state.running = false;
    this.state.socketState = SocketState.idle;
    this.state.progress = session.progress;
    this.state.bdiScore = session.score;
    this.state.frameCount = session.frameCount;
    this.state.lastFrame = lastFrame;
    this.state.vlmText = session.vlmText;
    this.state.finalScore = session.score;
    this.state.errorMsg = session.errorMsg;

    this.log.i(
      `恢复上一次评估 · mediaId=${session.mediaId} status=${session.status as number}`
    );
  }

  /**
   * **按素材归档的全部会话**（工作台分析区的唯一帧数据入口）
   * ★ 返回的就是 `@Trace` 的那个数组本身：页面在 `@Computed` 里读它，
   *   每帧整体替换引用时会自动失效重算，不依赖窗口层的同步时机。
   */
  public sessionsOf(): AnalysisSessionModel[] {
    return this.state.sessions;
  }

  /**
   * 取某个素材的会话（没有则 null）
   * ★ 这是"看哪个素材就只拿那个素材的结果"的**唯一**入口 —— 不允许跨素材兜底。
   */
  public sessionOf(mediaId: string): AnalysisSessionModel | null {
    if (mediaId.length === 0) {
      return null;
    }
    const index: number = this.indexOf(mediaId);
    if (index < 0) {
      return null;
    }
    return this.state.sessions[index];
  }

  /** 当前 live 会话的素材 id（空串 = 还没有任何会话） */
  public liveMediaIdOf(): string {
    return this.state.mediaId;
  }

  /** 最新一帧的热力图（无帧时返回空数组） */
  public heatmap(): number[][] {
    const frame: AnalysisFrameModel | null = this.state.lastFrame;
    return frame === null ? [] : frame.heatmapData;
  }

  /**
   * 最新一帧的人脸图 DataURL（ArkUI 的 Image 组件可直接吃 `data:image/jpeg;base64,...`）
   * 无帧时返回空串。
   */
  public alignedFaceDataUrl(): string {
    const frame: AnalysisFrameModel | null = this.state.lastFrame;
    if (frame === null || frame.alignedFace.length === 0) {
      return '';
    }
    const raw: string = frame.alignedFace;
    if (raw.startsWith('data:')) {
      return raw;
    }
    return `data:image/jpeg;base64,${raw}`;
  }

  /** 当前进度百分比文案 · ★ 服务端 progress 会从 0 直接跳到 1，UI 请用动画过渡 */
  public progressText(): string {
    return `${Math.round(this.state.progress * 100)}%`;
  }

  /** 最新帧的严重度中文标签 */
  public severityLabel(): string {
    return UiConstant.severityLabel(BdiThreshold.severityOf(this.state.bdiScore));
  }

  /** 错误文案（空串表示无错） */
  public errorOf(): string {
    return this.state.errorMsg;
  }

  /** 当前进度 0–1 */
  public progressOf(): number {
    return this.state.progress;
  }

  /** 最新 BDI 分数 */
  public scoreOf(): number {
    return this.state.bdiScore;
  }

  /** 已收到的帧数 */
  public frameCountOf(): number {
    return this.state.frameCount;
  }

  /** 最近一帧（无帧为 null） */
  public lastFrameOf(): AnalysisFrameModel | null {
    return this.state.lastFrame;
  }

  /** VLM 文本解读 */
  public vlmTextOf(): string {
    return this.state.vlmText;
  }

  /** 连接状态 */
  public socketStateOf(): SocketState {
    return this.state.socketState;
  }

  // ────────────────── 回调实现（全部下压）──────────────────

  public onFrame(frame: AnalysisFrameModel): void {
    this.state.lastFrame = frame;
    this.state.bdiScore = frame.bdiScore;
    this.state.progress = frame.progress;
    this.state.frameCount = this.state.frameCount + 1;

    const index: number = this.indexOf(this.state.mediaId);
    if (index < 0) {
      // 理论上不会发生（start 已建会话）；真发生时宁可丢这一帧，也不要写错素材
      this.log.w('收到帧但找不到对应的会话，已忽略');
      return;
    }
    const prev: AnalysisSessionModel = this.state.sessions[index];

    // ★ 用 concat 产出**新数组**再赋值：V2 的 @Trace 只认引用变化
    let frames: AnalysisFrameModel[] = prev.frames.concat([frame]);
    if (frames.length > MAX_FRAME_HISTORY) {
      frames = frames.slice(frames.length - MAX_FRAME_HISTORY);
    }

    let scores: number[] = prev.scores.concat([Math.round(frame.bdiScore)]);
    if (scores.length > MAX_SCORE_POINTS) {
      scores = scores.slice(scores.length - MAX_SCORE_POINTS);
    }

    this.writeSession(this.withFrame(prev, frames, scores, frame, prev.frameCount + 1));
  }

  public onStatus(taskId: string): void {
    this.log.i(`服务端已受理 · taskId=${taskId}`);
    this.state.errorMsg = '';
  }

  public onVlm(text: string): void {
    this.state.vlmText = text;
    const index: number = this.indexOf(this.state.mediaId);
    if (index < 0) {
      return;
    }
    this.writeSession(this.withVlm(this.state.sessions[index], text));
  }

  public onDone(finalScore: number): void {
    this.state.running = false;
    this.state.finalScore = finalScore;
    this.state.bdiScore = finalScore;
    this.state.progress = 1;
    this.log.i(`分析完成 · 最终分数 ${finalScore}`);

    const index: number = this.indexOf(this.state.mediaId);
    if (index >= 0) {
      // 收尾：帧数组裁到 MAX_ARCHIVE_FRAMES，会话置 done
      this.writeSession(this.withDone(this.state.sessions[index], finalScore));
    }

    // 服务端此刻已写入 diagnosis_report，刷新统计与列表就能看到
    this.notifyFinished();
  }

  public onError(message: string): void {
    this.state.running = false;
    this.state.errorMsg = message;
    this.log.w(`分析出错 · ${message}`);
    const index: number = this.indexOf(this.state.mediaId);
    if (index >= 0) {
      this.writeSession(this.withFailed(this.state.sessions[index], message));
    }
  }

  public onStateChanged(state: SocketState): void {
    this.state.socketState = state;
  }

  public onReconnecting(attempt: number): void {
    // ★ 重连会重发媒体 id，服务端会【从头再跑一遍完整分析】，必须提示用户
    this.state.errorMsg = `连接中断，正在第 ${attempt} 次重连（服务端将重新分析该素材）`;
    this.log.w(this.state.errorMsg);
  }

  public onUnauthorized(): void {
    this.state.running = false;
    this.state.errorMsg = '登录已过期，请重新登录';
    this.log.w('WS 鉴权失败（close 1008）');
  }

  // ────────────────── 会话构造 / 写入（保持 ArkTS 友好：逐字段显式赋值）──────────────────

  /** 新会话（开始分析时 · 覆盖该素材的旧结果） */
  private freshSession(mediaId: string, mediaType: MediaType): AnalysisSessionModel {
    const session: AnalysisSessionModel = {
      mediaId: mediaId,
      mediaType: mediaType,
      status: TaskStatus.running,
      progress: 0,
      score: 0,
      frameCount: 0,
      frames: [],
      firstFrameFace: '',
      scores: [],
      vlmText: '',
      errorMsg: '',
      updatedAt: Date.now()
    };
    return session;
  }

  /** 追加一帧后的会话 */
  private withFrame(
    prev: AnalysisSessionModel,
    frames: AnalysisFrameModel[],
    scores: number[],
    frame: AnalysisFrameModel,
    frameCount: number
  ): AnalysisSessionModel {
    const session: AnalysisSessionModel = {
      mediaId: prev.mediaId,
      mediaType: prev.mediaType,
      status: TaskStatus.running,
      progress: frame.progress,
      score: frame.bdiScore > 0 ? frame.bdiScore : prev.score,
      frameCount: frameCount,
      frames: frames,
      // ★ 只认**第一次**写入：后续帧不覆盖，于是首帧图不会因为 frames 被裁剪而丢失
      firstFrameFace: prev.firstFrameFace.length > 0 ? prev.firstFrameFace : frame.alignedFace,
      scores: scores,
      vlmText: prev.vlmText,
      // 帧能到达说明链路正常：清掉上一次的重连提示
      errorMsg: '',
      updatedAt: Date.now()
    };
    return session;
  }

  /** 追加 VLM 文本后的会话 */
  private withVlm(prev: AnalysisSessionModel, text: string): AnalysisSessionModel {
    const session: AnalysisSessionModel = {
      mediaId: prev.mediaId,
      mediaType: prev.mediaType,
      status: prev.status,
      progress: prev.progress,
      score: prev.score,
      frameCount: prev.frameCount,
      frames: prev.frames,
      firstFrameFace: prev.firstFrameFace,
      scores: prev.scores,
      vlmText: text,
      errorMsg: prev.errorMsg,
      updatedAt: Date.now()
    };
    return session;
  }

  /** 收尾（done）后的会话 · 帧数组按时间均匀抽稀 + 状态置 done */
  private withDone(prev: AnalysisSessionModel, finalScore: number): AnalysisSessionModel {
    // ★ 抽稀而不是"砍掉前段"：只留最后 30 帧会让逐帧列表退化成"同一批的同一张图"
    const frames: AnalysisFrameModel[] = sampleEvenly(prev.frames, MAX_ARCHIVE_FRAMES);
    const session: AnalysisSessionModel = {
      mediaId: prev.mediaId,
      mediaType: prev.mediaType,
      status: TaskStatus.done,
      progress: 1,
      score: finalScore > 0 ? finalScore : prev.score,
      frameCount: prev.frameCount,
      frames: frames,
      // ★ 首帧图与裁剪无关：`frames` 被从头部切掉后它仍然在
      firstFrameFace: prev.firstFrameFace,
      scores: prev.scores,
      vlmText: prev.vlmText,
      errorMsg: '',
      updatedAt: Date.now()
    };
    return session;
  }

  /** 失败后的会话 */
  private withFailed(prev: AnalysisSessionModel, message: string): AnalysisSessionModel {
    const session: AnalysisSessionModel = {
      mediaId: prev.mediaId,
      mediaType: prev.mediaType,
      status: TaskStatus.failed,
      progress: prev.progress,
      score: prev.score,
      frameCount: prev.frameCount,
      frames: prev.frames,
      firstFrameFace: prev.firstFrameFace,
      scores: prev.scores,
      vlmText: prev.vlmText,
      errorMsg: message,
      updatedAt: Date.now()
    };
    return session;
  }

  /** 只重置 live 指针（归档会话一概不动） */
  private resetLive(): void {
    this.state.running = false;
    this.state.socketState = SocketState.idle;
    this.state.progress = 0;
    this.state.bdiScore = 0;
    this.state.frameCount = 0;
    this.state.lastFrame = null;
    this.state.vlmText = '';
    this.state.finalScore = 0;
    this.state.errorMsg = '';
  }

  /** 找到某素材会话的下标（-1 = 没有） */
  private indexOf(mediaId: string): number {
    if (mediaId.length === 0) {
      return -1;
    }
    const list: AnalysisSessionModel[] = this.state.sessions;
    for (let i = 0; i < list.length; i++) {
      if (list[i].mediaId === mediaId) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 写入/替换一条会话（**整体替换数组引用**，保证 @Trace 触发刷新）
   * ★ 同时做归档淘汰：超过 MAX_ARCHIVE_SESSIONS 时丢掉 updatedAt 最旧的那条，
   *   live 会话永不淘汰。
   */
  private writeSession(next: AnalysisSessionModel): void {
    const list: AnalysisSessionModel[] = this.state.sessions;
    const merged: AnalysisSessionModel[] = [];
    let replaced: boolean = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].mediaId === next.mediaId) {
        merged.push(next);
        replaced = true;
      } else {
        merged.push(list[i]);
      }
    }
    if (!replaced) {
      merged.push(next);
    }
    this.state.sessions = this.trimSessions(merged);
  }

  /** 归档淘汰：保留 live 会话 + 最近的 (MAX_ARCHIVE_SESSIONS - 1) 条 */
  private trimSessions(list: AnalysisSessionModel[]): AnalysisSessionModel[] {
    if (list.length <= MAX_ARCHIVE_SESSIONS) {
      return list;
    }
    const liveId: string = this.state.mediaId;
    let live: AnalysisSessionModel | null = null;
    const others: AnalysisSessionModel[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].mediaId === liveId) {
        live = list[i];
      } else {
        others.push(list[i]);
      }
    }
    others.sort((a: AnalysisSessionModel, b: AnalysisSessionModel): number => a.updatedAt - b.updatedAt);
    const keepCount: number = live === null ? MAX_ARCHIVE_SESSIONS : MAX_ARCHIVE_SESSIONS - 1;
    const kept: AnalysisSessionModel[] =
      others.length > keepCount ? others.slice(others.length - keepCount) : others;

    const out: AnalysisSessionModel[] = [];
    if (live !== null) {
      out.push(live);
    }
    for (let i = 0; i < kept.length; i++) {
      out.push(kept[i]);
    }
    if (out.length < list.length) {
      this.log.i(`归档淘汰 · ${list.length} → ${out.length} 条（上限 ${MAX_ARCHIVE_SESSIONS}）`);
    }
    return out;
  }

  private notifyFinished(): void {
    this.onFinished().catch((err: Object) => {
      this.log.e('分析收尾刷新失败', err);
    });
  }
}
