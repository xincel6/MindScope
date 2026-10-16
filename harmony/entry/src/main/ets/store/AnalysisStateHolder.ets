/**
 * AnalysisStateHolder · WS 回调 → 响应式状态 的桥接
 *
 * 为什么单独一个文件：`AnalysisSocket` 的回调是**抽象类**（ArkTS 不允许用对象字面量
 * 初始化「带方法」的接口），而回调里要写的是 `@Trace` 状态；把这两件事解耦后：
 *   - `network/AnalysisSocket.ets` 只懂协议；
 *   - `store/AppStore.ets` 只懂状态与业务编排；
 *   - 本文件是两者之间唯一的接缝，改协议或改状态都只动一处。
 *
 * ★ `done` / `error` 之后服务端会主动 close，那是**正常收尾**，
 *   本类据此把 `running` 置回 false，不会去触发重连。
 */

import { AnalysisListener, AnalysisSocket } from '../network/AnalysisSocket';
import { AnalysisFrameModel, BdiThreshold, SocketState, UiConstant } from '../types/Index';
import { AnalysisState } from '../types/storeState';
import { Logger } from '../common/Logger';

/** 分析结束后需要做的事（统计/报告刷新）· 由 AppStore 注入 */
export type AnalysisFinishedHook = () => Promise<void>;

/** 实时评分曲线最多保留的点数（超出后丢弃最旧的，避免长时间视频把数组撑爆） */
export const MAX_SCORE_POINTS: number = 120;

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
   * @param mediaId 服务端媒体 id（字符串）
   */
  public start(mediaId: string): void {
    if (this.state.running) {
      this.log.w('已有分析在进行中，先停止旧会话再开始新会话');
      this.stop();
    }
    this.reset();
    this.state.mediaId = mediaId;
    this.state.running = true;
    this.log.i(`开始分析 · mediaId=${mediaId}`);
    this.socket.start(mediaId);
  }

  /** 请求取消（★ 视频场景服务端基本已经算完，UI 不应承诺可中断） */
  public cancel(): void {
    this.socket.cancel();
  }

  /**
   * 主动停止并释放连接（页面 aboutToDisappear / onHide 必须调用）
   * ★ **不清结果**：用户离开页面后回来仍能看到上次的分数与热力图。
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

  /** 逐帧分数序列（实时评分曲线用，最旧的点最多保留 MAX_SCORE_POINTS 个） */
  public scoreHistoryOf(): number[] {
    return this.state.scoreHistory;
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

    // 实时评分曲线：★ 用 concat 产出新数组再赋值，保证 V2 的 @Trace 一定感知到变化
    let history: number[] = this.state.scoreHistory.concat([Math.round(frame.bdiScore)]);
    if (history.length > MAX_SCORE_POINTS) {
      history = history.slice(history.length - MAX_SCORE_POINTS);
    }
    this.state.scoreHistory = history;
  }

  public onStatus(taskId: string): void {
    this.log.i(`服务端已受理 · taskId=${taskId}`);
    this.state.errorMsg = '';
  }

  public onVlm(text: string): void {
    this.state.vlmText = text;
  }

  public onDone(finalScore: number): void {
    this.state.running = false;
    this.state.finalScore = finalScore;
    this.state.bdiScore = finalScore;
    this.state.progress = 1;
    this.log.i(`分析完成 · 最终分数 ${finalScore}`);
    // 服务端此刻已写入 diagnosis_report，刷新统计与列表就能看到
    this.notifyFinished();
  }

  public onError(message: string): void {
    this.state.running = false;
    this.state.errorMsg = message;
    this.log.w(`分析出错 · ${message}`);
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

  // ────────────────── 内部实现 ──────────────────

  private reset(): void {
    this.state.running = false;
    this.state.mediaId = '';
    this.state.socketState = SocketState.idle;
    this.state.progress = 0;
    this.state.bdiScore = 0;
    this.state.frameCount = 0;
    this.state.lastFrame = null;
    this.state.scoreHistory = [];
    this.state.vlmText = '';
    this.state.finalScore = 0;
    this.state.errorMsg = '';
  }

  private notifyFinished(): void {
    this.onFinished().catch((err: Object) => {
      this.log.e('分析收尾刷新失败', err);
    });
  }
}
