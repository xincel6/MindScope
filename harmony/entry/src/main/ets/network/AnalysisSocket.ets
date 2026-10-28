/**
 * WebSocket 分析通道 · 封装 `/ws/analysis`
 *
 * 真实交互时序（docs/鸿蒙端网络层与类型共享方案.md 第 1.2 节）：
 * ```
 * ① HTTP POST /api/upload/image            → 拿到 media_id
 * ② WSS  wss://xincell1013.xyz/ws/analysis   +   Sec-WebSocket-Protocol: auth.<JWT>
 *        ★ token 走子协议头，不落 URL 日志；服务端校验后回显同一子协议完成握手
 *        ★ 服务端 accept 后只等 15 秒，客户端必须在 on('open') 里立刻发 {"id":"<media_id>"}
 * ③ ◀ {"type":"status","message":"analysis_started","task_id":...}
 * ④ ◀ AnalysisFrame × N   ★★ 帧消息【没有 type 字段】
 * ⑤ ◀ {"type":"vlm_analysis","content":"..."}   可能没有
 * ⑥ ◀ {"type":"done","final_score":18.42}
 * ⑦ 服务端主动 close（正常收尾）
 * ```
 *
 * 五个必须遵守的边界（同文档第 1.3 节）：
 *  1. 帧无 `type` → 判据是 `type === undefined`，不是 `=== 'frame'`
 *  2. `done` 后服务端主动 close → 必须用 `analysisFinished` 区分「正常收尾」与「真断线」
 *  3. ping 不回复 → **不能靠等 pong 判活**，只能靠 close/error 事件
 *  4. `cancel` 对视频基本无效（处理早在 15s 前 await 完了），UI 别承诺可中断
 *  5. 重连 ≠ 断点续传 → 重连会重发 `{"id":...}`，服务端**从头再跑一遍完整分析**
 */

import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiConfig } from '../common/ApiConfig';
import { Logger } from '../common/Logger';
import { AnalysisFrameDto, AnalysisFrameModel, Mapper, SocketState, WsInboundDto } from '../types/Index';

/** 服务端 close code：鉴权失败（无效 token → 应直接登出） */
const CLOSE_UNAUTHORIZED: number = 1008;

/** 出站消息 · 用带参构造的 class（ArkTS 不允许对象字面量初始化带参构造的类） */
class StartMessage {
  public id: string;

  constructor(id: string) {
    this.id = id;
  }
}

class TypeMessage {
  public type: string;

  constructor(type: string) {
    this.type = type;
  }
}

/**
 * 回调抽象类 · ★ ArkTS 不允许用对象字面量初始化「带方法的接口」，
 * 所以回调一律做成抽象类，调用方 `extends` 后重写需要的方法。
 */
export abstract class AnalysisListener {
  /** 收到一帧（帧消息没有 type） */
  public onFrame(frame: AnalysisFrameModel): void {}

  /** 服务端确认开始分析 */
  public onStatus(taskId: string): void {}

  /** VLM 文本解读（可能不触发） */
  public onVlm(text: string): void {}

  /** 正常收尾 · finalScore 来自 done 消息 */
  public onDone(finalScore: number): void {}

  /** 服务端下发的 error 消息，或本地重连耗尽 */
  public onError(message: string): void {}

  /** 连接状态变化 */
  public onStateChanged(state: SocketState): void {}

  /**
   * 正在分析时发生断线并即将重连 · **服务端会从头再跑一遍**，UI 必须提示用户
   * @param attempt 第几次重连（从 1 开始）
   */
  public onReconnecting(attempt: number): void {}

  /** 令牌失效（close 1008）· 调用方应清理登录态并跳回登录页 */
  public onUnauthorized(): void {}
}

/** 分析通道唯一入口 · 集中对外接口在顶部 */
export class AnalysisSocket {
  // ────────────────── 对外接口 ──────────────────

  constructor(listener: AnalysisListener) {
    this.listener = listener;
  }

  /** 开一条新连接并立刻订阅该媒体的分析结果（每次分析都是短命连接） */
  public start(mediaId: string): void {
    this.mediaId = mediaId;
    this.manualClosed = false;
    this.analysisFinished = false;
    this.reconnectCount = 0;
    this.openSocket();
  }

  /** 请求取消 · 只在服务端帧循环期间有效，视频场景基本无效 */
  public cancel(): void {
    this.sendRaw(JSON.stringify(new TypeMessage('cancel')));
  }

  /** 发送心跳 ping · 服务端不回复，仅用于保持链路活跃 */
  public ping(): void {
    this.sendRaw(JSON.stringify(new TypeMessage('ping')));
  }

  /** 主动关闭 · 页面 aboutToDisappear / onPageHide 必须调用，避免连接泄漏 */
  public stop(): void {
    this.manualClosed = true;
    this.stopHeartbeat();
    this.clearReconnectTimer();
    this.teardown();
    this.setState(SocketState.closed);
  }

  /** 当前连接状态 */
  public currentState(): SocketState {
    return this.state;
  }

  /** 是否正在等待/接收分析结果 */
  public isRunning(): boolean {
    return this.state === SocketState.connecting || this.state === SocketState.open;
  }

  /** 当前订阅的媒体 id */
  public currentMediaId(): string {
    return this.mediaId;
  }

  // ────────────────── 状态（全部私有，下压实现）──────────────────

  private listener: AnalysisListener;
  private socket: webSocket.WebSocket | null = null;
  private state: SocketState = SocketState.idle;
  private mediaId: string = '';
  /** 心跳定时器句柄 · ArkTS 没有 ReturnType<typeof setInterval>，只能用 number */
  private heartbeatTimer: number = -1;
  private reconnectTimer: number = -1;
  private reconnectCount: number = 0;
  /** 空闲态断线自动重连上限（分析态重连需要用户确认，见 onReconnecting） */
  private readonly maxReconnect: number = 3;
  /** 主动关闭标志 · 与 analysisFinished 共同决定「要不要重连」 */
  private manualClosed: boolean = false;
  /** 收到 done / error · 服务端随后会主动 close，此时**不是**断线 */
  private analysisFinished: boolean = false;

  // ────────────────── 建连 ──────────────────

  private openSocket(): void {
    this.teardown();
    this.setState(SocketState.connecting);

    const socket: webSocket.WebSocket = webSocket.createWebSocket();
    this.socket = socket;

    socket.on('open', () => {
      this.setState(SocketState.open);
      this.reconnectCount = 0;
      // ★ 服务端只等 15 秒，必须在这里立刻发出媒体 id
      this.sendRaw(JSON.stringify(new StartMessage(this.mediaId)));
      this.startHeartbeat();
      Logger.i(`WS 已连接并已订阅媒体 ${this.mediaId}`);
    });

    socket.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      // 服务端全部是文本消息；二进制帧忽略
      if (typeof value !== 'string') {
        return;
      }
      this.dispatch(value as string);
    });

    socket.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      this.stopHeartbeat();
      this.setState(SocketState.closed);
      const code: number = value === undefined || value === null ? 0 : value.code;
      Logger.i(`WS 已关闭 · code=${code}`);
      if (code === CLOSE_UNAUTHORIZED) {
        this.analysisFinished = true;
        this.listener.onUnauthorized();
        return;
      }
      // ★ 正常收尾（done 后服务端主动 close）不算断线，不能触发重连
      if (this.manualClosed || this.analysisFinished) {
        return;
      }
      this.scheduleReconnect();
    });

    socket.on('error', (err: BusinessError) => {
      Logger.e('WS 出错', err as Object);
      this.stopHeartbeat();
      this.setState(SocketState.closed);
      if (!this.manualClosed && !this.analysisFinished) {
        this.scheduleReconnect();
      }
    });

    const url: string = ApiConfig.analysisWsUrl();
    Logger.i(`WS 连接中 · ${url}`);

    // ★ token 走子协议（Sec-WebSocket-Protocol: auth.<jwt>），不拼进 URL。
    //   鸿蒙 SDK 的 WebSocketRequestOptions 提供专门的 `protocol` 字段（API 12+），
    //   用它比往 header 里塞 Sec-WebSocket-Protocol 更可靠。
    const subprotocol: string = ApiConfig.wsSubprotocol();
    const options: webSocket.WebSocketRequestOptions = {
      protocol: subprotocol
    };

    socket.connect(url, options, (err: BusinessError, ok: boolean) => {
      if (err !== undefined && err !== null && err.code !== undefined && err.code !== 0) {
        Logger.e('WS 连接失败', err as Object);
        this.setState(SocketState.closed);
        if (!this.manualClosed) {
          this.scheduleReconnect();
        }
      }
    });
  }

  // ────────────────── 消息分流 ──────────────────

  /** 唯一分流入口 · ★ 帧消息没有 type 字段 */
  private dispatch(text: string): void {
    let msg: WsInboundDto;
    try {
      msg = JSON.parse(text) as WsInboundDto;
    } catch (err) {
      Logger.w('WS 收到非 JSON 消息，已忽略');
      return;
    }
    const type: string | undefined = msg.type;
    if (type === undefined || type === null || type.length === 0) {
      if (this.analysisFinished) {
        // done 之后理论上不再有帧；真收到也只当噪声丢弃
        return;
      }
      this.listener.onFrame(Mapper.toAnalysisFrame(AnalysisSocket.toFrameDto(msg)));
      return;
    }
    if (type === 'status') {
      this.listener.onStatus(msg.task_id === undefined ? '' : msg.task_id);
      return;
    }
    if (type === 'vlm_analysis') {
      this.listener.onVlm(msg.content === undefined ? '' : msg.content);
      return;
    }
    if (type === 'done') {
      // ★ 先打标志：服务端马上要 close，不然后续 close 会被误判成断线
      this.analysisFinished = true;
      const score: number = msg.final_score === undefined ? 0 : msg.final_score;
      this.listener.onDone(score);
      return;
    }
    if (type === 'error') {
      this.analysisFinished = true;
      this.listener.onError(msg.message === undefined ? '分析失败' : msg.message);
      return;
    }
    // 未知类型忽略（服务端不推 pong）
    Logger.d(`WS 未知消息类型：${type}`);
  }

  /** 把联合消息收敛成帧 DTO · 逐字段显式赋值，禁止对象展开 */
  private static toFrameDto(msg: WsInboundDto): AnalysisFrameDto {
    const frame: AnalysisFrameDto = {
      frame_id: msg.frame_id === undefined ? 0 : msg.frame_id,
      timestamp: msg.timestamp === undefined ? 0 : msg.timestamp,
      bdi_score: msg.bdi_score === undefined ? 0 : msg.bdi_score,
      aligned_face: msg.aligned_face === undefined ? '' : msg.aligned_face,
      heatmap_data: msg.heatmap_data === undefined ? [] : msg.heatmap_data,
      inference_time_ms: msg.inference_time_ms === undefined ? 0 : msg.inference_time_ms,
      progress: msg.progress === undefined ? 0 : msg.progress
    };
    return frame;
  }

  // ────────────────── 心跳 / 重连 / 清理 ──────────────────

  /** 仅用于保活；服务端在帧循环里丢弃 ping，**不能作为判活依据** */
  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      this.sendRaw(JSON.stringify(new TypeMessage('ping')));
    }, 30000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  /** 指数退避重连 · ★ 重连会重发媒体 id，服务端从头再跑一遍完整分析 */
  private scheduleReconnect(): void {
    if (this.reconnectCount >= this.maxReconnect) {
      this.listener.onError('连接已断开且重连失败，请检查服务端地址与网络');
      return;
    }
    const delay: number = Math.min(1000 * Math.pow(2, this.reconnectCount), 16000);
    this.reconnectCount++;
    this.listener.onReconnecting(this.reconnectCount);
    Logger.w(`WS 将在 ${delay}ms 后进行第 ${this.reconnectCount} 次重连`);
    this.clearReconnectTimer();
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      if (this.manualClosed) {
        return;
      }
      this.openSocket();
    }, delay);
  }

  private teardown(): void {
    const socket: webSocket.WebSocket | null = this.socket;
    if (socket === null) {
      return;
    }
    socket.off('open');
    socket.off('message');
    socket.off('close');
    socket.off('error');
    socket.close((err: BusinessError, ok: boolean) => {
      if (err !== undefined && err !== null && err.code !== undefined && err.code !== 0) {
        Logger.d(`WS close 回调异常 code=${err.code}`);
      }
    });
    this.socket = null;
  }

  private sendRaw(text: string): void {
    const socket: webSocket.WebSocket | null = this.socket;
    if (socket === null || this.state !== SocketState.open) {
      return;
    }
    socket.send(text, (err: BusinessError, ok: boolean) => {
      if (err !== undefined && err !== null && err.code !== undefined && err.code !== 0) {
        Logger.e('WS 发送失败', err as Object);
      }
    });
  }

  private setState(next: SocketState): void {
    if (this.state === next) {
      return;
    }
    this.state = next;
    this.listener.onStateChanged(next);
  }
}
