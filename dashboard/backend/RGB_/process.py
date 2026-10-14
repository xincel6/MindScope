import cv2
import os

# -------------------------- 核心增强函数 --------------------------
def rgb_histogram_equalization(img):
    """生成(a) RGB空间全局直方图均衡化"""
    b, g, r = cv2.split(img)
    b_eq = cv2.equalizeHist(b)
    g_eq = cv2.equalizeHist(g)
    r_eq = cv2.equalizeHist(r)
    return cv2.merge((b_eq, g_eq, r_eq))

def rgb_adaptive_histogram_equalization(img, clip_limit=2.0, tile_size=(8, 8)):
    """生成(b) RGB空间自适应直方图均衡化(CLAHE)"""
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=tile_size)
    b, g, r = cv2.split(img)
    return cv2.merge((clahe.apply(b), clahe.apply(g), clahe.apply(r)))

def yuv_histogram_equalization(img):
    """生成(c) YUV空间全局直方图均衡化（仅增强亮度，保留肤色）"""
    yuv = cv2.cvtColor(img, cv2.COLOR_BGR2YUV)
    y, u, v = cv2.split(yuv)
    y_eq = cv2.equalizeHist(y)
    return cv2.cvtColor(cv2.merge((y_eq, u, v)), cv2.COLOR_YUV2BGR)

def yuv_adaptive_histogram_equalization(img, clip_limit=2.0, tile_size=(8, 8)):
    """生成(d) YUV空间自适应直方图均衡化（抑郁症/微表情检测首选）"""
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=tile_size)
    yuv = cv2.cvtColor(img, cv2.COLOR_BGR2YUV)
    y, u, v = cv2.split(yuv)
    y_clahe = clahe.apply(y)
    return cv2.cvtColor(cv2.merge((y_clahe, u, v)), cv2.COLOR_YUV2BGR)

# -------------------------- 单张图片处理 --------------------------
if __name__ == "__main__":
    # 👇 只需要修改这里的输入图片路径
    INPUT_IMAGE_PATH = "0.jpg"  # 替换成你的裁剪后人脸图片路径
    OUTPUT_DIR = "enhanced_single"     # 输出结果文件夹

    # 创建输出文件夹
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # 读取图片
    img = cv2.imread(INPUT_IMAGE_PATH)
    if img is None:
        print(f"错误：无法读取图片 {INPUT_IMAGE_PATH}")
        exit(1)

    # 获取文件名（不含扩展名）
    filename = os.path.splitext(os.path.basename(INPUT_IMAGE_PATH))[0]

    # 生成4种增强效果
    img_a = rgb_histogram_equalization(img)
    img_b = rgb_adaptive_histogram_equalization(img)
    img_c = yuv_histogram_equalization(img)
    img_d = yuv_adaptive_histogram_equalization(img)

    # 保存结果
    cv2.imwrite(os.path.join(OUTPUT_DIR, f"{filename}_a_RGB_HE.jpg"), img_a)
    cv2.imwrite(os.path.join(OUTPUT_DIR, f"{filename}_b_RGB_AHE.jpg"), img_b)
    cv2.imwrite(os.path.join(OUTPUT_DIR, f"{filename}_c_YUV_HE.jpg"), img_c)
    cv2.imwrite(os.path.join(OUTPUT_DIR, f"{filename}_d_YUV_AHE.jpg"), img_d)

    print(f"处理完成！4张增强图片已保存到：{os.path.abspath(OUTPUT_DIR)}")
    print(f"对应关系：")
    print(f"  {filename}_a_RGB_HE.jpg → 图(a)")
    print(f"  {filename}_b_RGB_AHE.jpg → 图(b)")
    print(f"  {filename}_c_YUV_HE.jpg → 图(c)")
    print(f"  {filename}_d_YUV_AHE.jpg → 图(d)")