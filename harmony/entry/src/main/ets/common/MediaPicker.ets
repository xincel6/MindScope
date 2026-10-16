/**
 * MediaPicker · 系统「选择图片或视频」的唯一入口
 *
 * 用 `photoAccessHelper.PhotoViewPicker`（系统相册选择器）：
 *   - **不需要任何权限**，也不需要自己写 `requestPermissionsFromUser`：
 *     选择器由系统弹窗承载，用户选中后系统才把 URI 临时授权给本应用。
 *     所以本模块**没有**往 `module.json5` 加相册权限，这是刻意的 —— 加了反而会被应用市场判为过度申请。
 *   - 选择器返回的是 `file://media/...` 形式的 URI，`@kit.NetworkKit` 的
 *     `multiFormDataList[].filePath` 可以直接吃这个 URI，不需要先拷贝进沙箱。
 *
 * ★ 为什么需要这个文件而不是在页面里直接调：
 *   ① 页面纪律要求"页面只做展示"，系统能力调用属于基础设施；
 *   ② 选完之后的"URI → 文件名 / MIME / 图片还是视频"这段推导有细节，
 *      集中一处才好维护（且可单测）。
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
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
  /**
   * 弹出系统选择器，让用户选**一张图片或一段视频**
   *
   * ★ 取消不算错误：返回 `{media: null, error: ''}`，调用方据此静默返回即可
   *   （把"用户主动取消"弹成红色错误是常见的体验缺陷）。
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
      return MediaPicker.fromUri(uris[0]);
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
      fileName: fileName,
      mimeType: MediaPicker.mimeOf(ext),
      type: isVideo ? MediaType.video : MediaType.image
    };
    return { media: media, error: '' };
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
