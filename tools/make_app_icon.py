# 把手绘原图切成游戏图标：工程根的 icon.png（引擎/窗口图标）与 icon.ico（Windows exe 用）。
#
# 用法（在工程根跑）：
#   python tools/make_app_icon.py
#
# 规则（改版面就改这里，改完重跑，两处产物一起更新）：
#   * 白纸底照原样保留 —— 手绘线条是黑的，透明底在深色任务栏上会看不见。
#   * 画布取正方形：高 = 线条高 + 顶部留白 + 底部留白，水平按线条中心对齐。
#   * 底部只留 2px：这张手稿本来就画到纸的最下缘截断，留白一多，断掉的身体笔画就飘起来。
#   * 48px 及以下先压成纯黑白再缩放、最后压暗一档：直接缩放的话 16px 那档线条会淡成灰的，
#     实测 16×16 里几乎没有够黑的像素，标题栏上认不出来。64px 以上保持柔和抗锯齿。
#   * .ico 出 16/24/32/48/64/128/256 七档（任务栏 32、资源管理器 48、桌面大图标 256），
#     每档都用上面那套自己渲，而不是让 Pillow 从 256 直接缩；帧用 BMP(DIB) 存，
#     这是 Windows 各版本都认的老格式，PNG 帧虽然也支持但导出链路上没必要冒险。

import hashlib
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "art" / "ui" / "app-icon-source.png"
OUT_PNG = ROOT / "icon.png"
OUT_ICO = ROOT / "icon.ico"

TOP_RATIO = 0.175        # 顶部留白 = 线条高度 × 这个比例
BOTTOM_PX = 2            # 底部留白（按原尺寸像素算）
INK_LUM = 160            # 亮度低于它的算“线条”
TINY_MAX = 48            # 这个尺寸及以下走「压黑白 + 缩放 + 压暗」
BILEVEL_LUM = 170        # 压黑白时的阈值
DARKEN_GAMMA = 2.0       # 压暗用的 gamma
PNG_SIZE = 256
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def ink_bbox(im: Image.Image) -> tuple[int, int, int, int]:
    px = im.load()
    w, h = im.size
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            r, g, b, _a = px[x, y]
            if (r + g + b) / 3 < INK_LUM:
                minx = min(minx, x)
                miny = min(miny, y)
                maxx = max(maxx, x)
                maxy = max(maxy, y)
    if maxx < 0:
        raise SystemExit(f"原图里没找到黑色线条，检查 {SRC}")
    return minx, miny, maxx, maxy


def square_master() -> Image.Image:
    src = Image.open(SRC).convert("RGBA")
    x0, y0, x1, y1 = ink_bbox(src)
    ink_w, ink_h = x1 - x0 + 1, y1 - y0 + 1
    side = ink_h + round(ink_h * TOP_RATIO) + BOTTOM_PX
    left_margin = round((side - ink_w) / 2)
    paper = src.getpixel((0, 0))  # 白纸底色取自左上角
    canvas = Image.new("RGBA", (side, side), (paper[0], paper[1], paper[2], 255))
    canvas.paste(src, (left_margin - x0, round(ink_h * TOP_RATIO) - y0))
    print(f"原图 {src.size[0]}×{src.size[1]}，线条范围 ({x0},{y0})-({x1},{y1})＝{ink_w}×{ink_h}")
    print(f"画布 {side}×{side}，线条左边距 {left_margin}px、上边距 {round(ink_h * TOP_RATIO)}px、下边距 {BOTTOM_PX}px")
    return canvas


def render(master: Image.Image, size: int) -> Image.Image:
    if size > TINY_MAX:
        return master.resize((size, size), Image.LANCZOS)
    flat = [0 if v < BILEVEL_LUM else 255 for v in range(256)]
    dark = [min(255, int(255 * ((v / 255) ** DARKEN_GAMMA))) for v in range(256)]
    gray = master.convert("L").point(flat).resize((size, size), Image.LANCZOS).point(dark)
    return Image.merge("RGBA", (gray, gray, gray, Image.new("L", (size, size), 255)))


def main() -> int:
    if not SRC.exists():
        print(f"缺少原图：{SRC}")
        return 1
    master = square_master()
    frames = {s: render(master, s) for s in ICO_SIZES}
    frames[PNG_SIZE].save(OUT_PNG)
    frames[PNG_SIZE].save(
        OUT_ICO,
        sizes=[(s, s) for s in ICO_SIZES],
        append_images=[frames[s] for s in ICO_SIZES if s != PNG_SIZE],
        bitmap_format="bmp",
    )

    def md5(p: Path) -> str:
        return hashlib.md5(p.read_bytes()).hexdigest()

    def dark_px(s: int) -> int:
        g = frames[s].convert("L")
        return sum(1 for v in g.get_flattened_data() if v < 100)

    print("每档够黑的线条像素数：" + "  ".join(f"{s}px={dark_px(s)}" for s in ICO_SIZES))
    print(f"{OUT_PNG.name} {PNG_SIZE}×{PNG_SIZE} md5={md5(OUT_PNG)}")
    print(f"{OUT_ICO.name} 内含 {sorted(Image.open(OUT_ICO).info.get('sizes', []))} md5={md5(OUT_ICO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
