/**
 * MediaPicker · 系统「选择图片或视频」的唯一入口
 *
 * 用 `photoAccessHelper.PhotoViewPicker`（系统相册选择器）：
 *   - **不需要任何权限**，也不需要自己写 `requestPermissionsFromUser`：
 *     选择器由系统弹窗承载，用户选中后系统才把 URI 临时授权给本应用。
 *     所以本模块**没有**往 `module.json5` 加相册权限，这是刻意的 —— 加了反而会被应用市场判为过度申请。
 *
 * ══════════════════ ★★ 选完之后**必须**把文件拷进应用沙箱（BUG-12）══════════════════
 * 早期版本的注释写着"选择器返回的 `file://media/...` URI 可以直接喂给
 * `multiFormDataList[].filePath`，不需要先拷贝进沙箱" —— **这句话是错的**，真机实测：
 *
 * ```
 * 网络不可达：Failed to open or read local data from the file or application。
 * ```
 *
 * 这句是 HarmonyOS `@ohos.net.http` 的 **2300026** 错误（见 SDK 里 http.d.ts 的错误码表），
 * 意思是"打不开要上传的本地文件"，**请求连正文都没读出来**，与服务端毫无关系。
 * 根因：`file://media/Photo/...` 是**媒体库 provider 的 URI**，不是文件系统路径；
 * `MultiFormData.filePath` 只接受真实路径（或应用沙箱路径）。
 *
 * 正确做法（本模块 `stageToCache` 做的）：
 *   `fs.openSync(uri, READ_ONLY)`（选择器给了临时读权限，能打开）
 *     → `fs.copyFileSync(fd, cacheDir/picked/<原文件名>)`
 *     → 上传时用**沙箱路径**。
 *
 * ★ 为什么需要这个文件而不是在页面里直接调：
 *   ① 页面纪律要求"页面只做展示"，系统能力调用属于基础设施；
 *   ② 选完之后的"URI → 文件名 / MIME / 图片还是视频 / 沙箱副本"这段推导有细节，
 *      集中一处才好维护（且可单测）。
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';
import { MediaType, PickedMediaModel } from '../types/Index';

/** 图片扩展名 → MIME */
const IMAGE_MIME: Record<string, string> = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'bmp': 'image/bmp',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif'
};

/** 视频扩展名 → MIME */
const VIDEO_MIME: Record<string, string> = {
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'avi': 'video/x-msvideo',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska'
};

/**
 * 后端 `routers/upload.py` 的 `ALLOWED_EXTENSIONS` 只认这些扩展名。
 * ★ 不在名单里的文件即使选中了也会被服务端 400 拒掉，所以这里先本地拦一次，
 *   给出"支持哪些格式"的明确提示，而不是等一个 400 回来再说。
 */
const ALLOWED_EXTENSIONS: string[] = [
  'jpg', 'jpeg', 'png', 'bmp', 'mp4', 'avi', 'mov', 'webm'
];

/** 选择结果 · 区分"用户取消"与"选了但不支持" */
export interface PickResult {
  /** 用户选中的素材 · 取消或失败时为 null */
  media: PickedMediaModel | null;
  /** 失败/不支持的原因 · 空串表示没有错误（含"用户取消"） */
  error: string;
}

/** 素材选择器 · 全为静态方法 */
export class MediaPicker {
  /** 沙箱副本目录（应用缓存下）· 不进图库、不占用户可见空间，由系统缓存回收 */
  private static readonly STAGE_DIR: string = 'picked';

  /**
   * 应用上下文 · 由 `AppBootstrap.start(context)` 在启动时注入一次
   * ★ 只有"把相册 URI 落进沙箱"这一步需要它（要 `cacheDir`）；
   *   本模块其余逻辑都是纯函数，便于单测。
   */
  private static appContext: Context | null = null;

  /** 注入应用上下文（幂等；未注入时 `stageToCache` 会直接失败并记日志） */
  public static attachContext(context: Context): void {
    MediaPicker.appContext = context;
  }

  /**
   * 弹出系统选择器，让用户选**一张图片或一段视频**
   *
   * ★ 取消不算错误：返回 `{media: null, error: ''}`，调用方据此静默返回即可
   *   （把"用户主动取消"弹成红色错误是常见的体验缺陷）。
   * ★ 选到之后会先把文件拷进沙箱，再返回带 `uploadPath` 的结果 —— 原因见文件头。
   */
  public static async pickOne(): Promise<PickResult> {
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    // 图片 + 视频都能选（需求原话："选择图片或视频"）
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    // 本轮一次只分析一个素材，所以限制单选
    options.maxSelectNumber = 1;

    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      const uris: string[] = result.photoUris;
      if (uris === undefined || uris === null || uris.length === 0) {
        // 用户取消选择
        return MediaPicker.cancelled();
      }
      const parsed: PickResult = MediaPicker.fromUri(uris[0]);
      const picked: PickedMediaModel | null = parsed.media;
      if (picked === null) {
        // 格式不支持等：原样把提示带回去
        return parsed;
      }
      // ★ 关键一步：拷进沙箱，拿到真正能上传的路径
      const staged: string = await MediaPicker.stageToCache(picked);
      if (staged.length === 0) {
        return { media: null, error: '无法读取所选素材（相册授权可能已失效），请重新选择' };
      }
      const media: PickedMediaModel = {
        uri: picked.uri,
        uploadPath: staged,
        fileName: picked.fileName,
        mimeType: picked.mimeType,
        type: picked.type
      };
      return { media: media, error: '' };
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e('打开素材选择器失败', err as Object);
      // 13900042 是系统"未知错误"，通常是用户在系统弹窗层取消
      if (e !== undefined && e !== null && e.code === 13900042) {
        return MediaPicker.cancelled();
      }
      return { media: null, error: '无法打开系统选择器，请稍后重试' };
    }
  }

  /** 用户取消 · 不是错误，但也没有素材 */
  private static cancelled(): PickResult {
    return { media: null, error: '' };
  }

  /**
   * 把系统 URI 推导成上传所需的素材描述
   *
   * ★ 文件名从 URI 最后一段解码而来（形如 `IMG_20260101_120000.jpg`）。
   *   后端会把这个名字写进 `media_assets.name`，也就是工作台/列表上显示的名字，
   *   所以它必须尽量像原始文件名，而不是 uuid。
   * ★ 解析不出扩展名时按扩展名白名单判失败（而不是瞎猜成图片），
   *   避免把一个不支持的格式传给后端换回一个 400。
   */
  public static fromUri(uri: string): PickResult {
    const fileName: string = MediaPicker.fileNameOf(uri);
    const ext: string = MediaPicker.extensionOf(fileName);

    if (ext.length === 0) {
      return { media: null, error: '无法识别该文件的格式，请选择图片或视频' };
    }
    if (ALLOWED_EXTENSIONS.indexOf(ext) < 0) {
      return { media: null, error: `暂不支持 .${ext} 格式，请选择 jpg / png / bmp / mp4 / mov / avi / webm` };
    }

    const isVideo: boolean = VIDEO_MIME[ext] !== undefined;
    const media: PickedMediaModel = {
      uri: uri,
      // ★ 沙箱路径由 `stageToCache()` 在 pickOne 里补上；单独调 fromUri 时留空
      uploadPath: '',
      fileName: fileName,
      mimeType: MediaPicker.mimeOf(ext),
      type: isVideo ? MediaType.video : MediaType.image
    };
    return { media: media, error: '' };
  }

  /**
   * 把相册选择器返回的 URI **复制进应用沙箱**，返回可直接上传的绝对路径（失败返回空串）
   *
   * ★★ 为什么必须复制（BUG-12，真机实测）：
   *   `file://media/Photo/...` 是媒体库 provider 的 URI，不是文件系统路径；
   *   `http.MultiFormData.filePath` 拿去 open 会抛 **2300026
   *   "Failed to open or read local data from the file or application"**，
   *   而这个错误在 `ApiError` 里被归到"网络不可达"，看起来极像服务端问题。
   *   `fs.open(uri, READ_ONLY)` 能打开它（选择器已给临时读权限），
   *   所以这里 open → copyFile 到 `cacheDir/picked/`，上传改用沙箱路径。
   *
   * ★ 用**异步** fs API：视频素材可能几十上百 MB，同步拷贝会把 UI 线程卡住。
   * ★ 保留原文件名：后端按扩展名判类型（图片/视频），并把名字写进 `media_assets.name`。
   * ★ 任何失败都不抛异常，只记日志 + 返回空串，由调用方给用户一句明确的话。
   */
  private static async stageToCache(media: PickedMediaModel): Promise<string> {
    const context: Context | null = MediaPicker.appContext;
    if (context === null) {
      Logger.e('MediaPicker 未注入上下文，无法复制相册素材（引导流程未跑？）');
      return '';
    }

    let src: fs.File | null = null;
    try {
      const dir: string = `${context.cacheDir}/${MediaPicker.STAGE_DIR}`;
      try {
        // recursion=true 等价于 mkdir -p；个别版本在目录已存在时仍会 reject，忽略即可
        await fs.mkdir(dir, true);
      } catch (mkdirErr) {
        Logger.d(`缓存目录已存在或创建被跳过 · ${dir}`);
      }

      const dest: string = `${dir}/${media.fileName}`;
      src = await fs.open(media.uri, fs.OpenMode.READ_ONLY);
      await fs.copyFile(src.fd, dest);
      const stat: fs.Stat = await fs.stat(dest);
      Logger.i(`相册素材已复制到沙箱 · ${media.fileName} · ${stat.size} 字节`);
      return dest;
    } catch (err) {
      Logger.e(`相册素材复制失败（上传会因读不到文件而报 2300026）· ${media.uri}`, err as Object);
      return '';
    } finally {
      if (src !== null) {
        try {
          await fs.close(src);
        } catch (closeErr) {
          Logger.w('关闭相册文件句柄失败');
        }
      }
    }
  }

  /** 从 URI 末段取文件名（解码百分号转义；取不到时回退一个占位名） */
  private static fileNameOf(uri: string): string {
    const raw: string = uri.length > 0 ? uri : 'material';
    const cut: number = raw.lastIndexOf('/');
    const tail: string = cut >= 0 ? raw.substring(cut + 1) : raw;
    let name: string = tail;
    try {
      name = decodeURIComponent(tail);
    } catch (err) {
      // URI 含非法转义时保持原样，不因为一个名字把整个选择流程打断
      Logger.w('素材名解码失败，沿用原始 URI 末段');
    }
    return name.length > 0 ? name : 'material';
  }

  /** 扩展名（小写、不含点）· 没有扩展名时返回空串 */
  private static extensionOf(fileName: string): string {
    const dot: number = fileName.lastIndexOf('.');
    if (dot < 0 || dot === fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  /** 扩展名 → MIME（未知时给通用二进制，后端不依赖它，只用于 multipart 头） */
  private static mimeOf(ext: string): string {
    const image: string | undefined = IMAGE_MIME[ext];
    if (image !== undefined) {
      return image;
    }
    const video: string | undefined = VIDEO_MIME[ext];
    if (video !== undefined) {
      return video;
    }
    return 'application/octet-stream';
  }
}
