# -*- coding: utf-8 -*-
"""《保卫鄱阳湖》知识卡照片导入器（纯 Python 标准库 + Pillow）

用法：
    python tools/import_knowledge_photos.py "C:/Users/17707/Downloads/鄱阳湖 · 知识卡图集.pptx"

产出：
    assets/art/knowledge/photos/<card_id>.png   40 张 256×256（1:1 方裁）RGB
    assets/art/knowledge/photos/_manifest.json  编号 / 卡 id / 卡名 / 类别 / 来源图 / 图片出处

为什么这么做：
  · 知识卡详情页要求「图片 1:1」—— 原图宽高比在 1.00~1.13 之间，统一以中心方裁，
    裁掉的最多只有横向约 5%，不会切掉主体。
  · 原图最长边 3000~5000 px、单张 1~3 MB，直接入库会让工程多出上百 MB，
    所以降到 256×256（详情页最大只画到约 210 px，2 倍余量足够）。
  · 卡 37「草洲不是越野场」的合影是替换件（用户另行提供的一张国产车照片），
    不走 pptx 里的 BLM 那张。

⚠ 生成后必须在 Godot 里跑一次 --headless --import，否则 res://...png 加载不到。
"""

import io
import json
import os
import re
import sys
import zipfile

try:
    from PIL import Image
except ImportError:                       # pragma: no cover
    sys.exit("需要 Pillow：pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "art", "knowledge", "photos")
GAME_STATE = os.path.join(ROOT, "scripts", "game_state.gd")
SIDE = 256                                 # 输出边长（1:1）

# 替换件：卡 37「草洲不是越野场」
REPLACEMENT = {
    "protect_wetland_tracks": {
        "file": r"C:/Users/17707/Downloads/Cache_-60402dd135362f28.jpg",
        "credit": "图片：易车 · 吉普穆马人论坛（草洲上的越野车）",
        "url": "https://baa.m.yiche.com/jipumumaren/thread-50427945.html",
    },
}

A_NS = "http://schemas.openxmlformats.org/drawingml/2006/main"
P_NS = "http://schemas.openxmlformats.org/presentationml/2006/main"
R_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

# pptx 里卡名后面那一格写的类别；也用来把版权说明页（散落着 "01" 之类文本）滤掉
CATEGORIES = {"植物", "鸟类", "机制", "地理", "水生动物", "外来物种", "案例",
              "管理策略", "保护行动"}


def game_card_names():
    """从 game_state.gd 的 KNOWLEDGE_CARDS 里读 {id: 卡名}（只认 id 行 + 紧邻的 name）。"""
    text = io.open(GAME_STATE, encoding="utf-8").read()
    start = text.index("const KNOWLEDGE_CARDS := {")
    end = text.index("\n}\n", start)                       # 这个常量到顶格大括号为止
    out = {}
    for m in re.finditer(r'^\t"([a-z0-9_]+)": \{\n\t\t"name": "([^"]+)"', text[start:end], re.M):
        out[m.group(1)] = m.group(2)
    if len(out) < 40:
        raise SystemExit("只解析到 %d 张知识卡，KNOWLEDGE_CARDS 的写法可能变了" % len(out))
    return out


def read_slides(pptx):
    """返回 [(编号, 卡名, 类别, 图片出处, media 名, 宽, 高), ...]，按 pptx 里的卡片编号排。"""
    z = zipfile.ZipFile(pptx)
    rows = []
    for i in range(1, 60):
        name = "ppt/slides/slide%d.xml" % i
        if name not in z.namelist():
            continue
        xml = z.read(name).decode("utf-8")
        txts = re.findall(r"<a:t>(.*?)</a:t>", xml)
        if not any(re.fullmatch(r"\d{2}", t) for t in txts):
            continue                                   # 封面 / 版权页
        rels = z.read("ppt/slides/_rels/slide%d.xml.rels" % i).decode("utf-8")
        rmap = dict(re.findall(r'Id="([^"]+)"[^>]*Target="([^"]+)"', rels))
        media = re.search(r'<a:blip[^>]*r:embed="([^"]+)"', xml)
        if not media:
            continue                                   # 版权说明页：只有文字，没有图
        media_file = os.path.basename(rmap[media.group(1)])
        # 顺序：编号 / 卡名 / 类别 / [图片：...]
        idx = next(k for k, t in enumerate(txts) if re.fullmatch(r"\d{2}", t))
        number = txts[idx]
        card_name = txts[idx + 1]
        category = txts[idx + 2]
        if category not in CATEGORIES:
            continue                                   # 版权页里也散落着 "01" 这种独立文本
        credit = ""
        if idx + 3 < len(txts) and txts[idx + 3].startswith("图片："):
            credit = txts[idx + 3]
        data = z.read("ppt/media/" + media_file)
        im = Image.open(io.BytesIO(data))
        rows.append((number, card_name, category, credit, media_file, im.size[0], im.size[1]))
    rows.sort(key=lambda r: r[0])
    return rows


def square(img):
    w, h = img.size
    side = min(w, h)
    img = img.crop(((w - side) // 2, (h - side) // 2, (w - side) // 2 + side, (h - side) // 2 + side))
    return img.resize((SIDE, SIDE), Image.LANCZOS)


def main():
    pptx = sys.argv[1] if len(sys.argv) > 1 else r"C:/Users/17707/Downloads/鄱阳湖 · 知识卡图集.pptx"
    names = game_card_names()
    by_name = {v: k for k, v in names.items()}
    rows = read_slides(pptx)
    print("pptx 里读到 %d 张卡、%d 张游戏卡" % (len(rows), len(names)))
    os.makedirs(OUT_DIR, exist_ok=True)

    manifest = []
    used = set()
    for number, card_name, category, credit, media_file, w, h in rows:
        kid = by_name.get(card_name)
        if kid is None:
            raise SystemExit("pptx 第 %s 张「%s」在 KNOWLEDGE_CARDS 里找不到同名卡" % (number, card_name))
        used.add(kid)
        src = "ppt/media/" + media_file
        if kid in REPLACEMENT:
            rep = REPLACEMENT[kid]
            img = Image.open(rep["file"]).convert("RGB")
            credit = rep["credit"]
            src = os.path.basename(rep["file"])
            url = rep["url"]
        else:
            z = zipfile.ZipFile(pptx)
            img = Image.open(io.BytesIO(z.read(src))).convert("RGB")
            url = ""
        before = img.size
        img = square(img)
        path = os.path.join(OUT_DIR, kid + ".png")
        img.save(path, "PNG", optimize=True)
        manifest.append({
            "number": number, "card_id": kid, "name": card_name, "category": category,
            "credit": credit, "credit_url": url, "source": src,
            "source_size": "%dx%d" % before, "out_size": "%dx%d" % (SIDE, SIDE),
            "bytes": os.path.getsize(path),
        })
        print("  %s %-14s %-22s %-34s %s -> %dx%d  %d KB"
              % (number, kid, card_name, credit[:34], "%dx%d" % before, SIDE, SIDE,
                 os.path.getsize(path) // 1024))

    missing_credit = [m["number"] + " " + m["name"] for m in manifest if not m["credit"]]
    left = sorted(set(names) - used)
    print("\n共写出 %d 张，总计 %.1f MB" % (len(manifest),
          sum(m["bytes"] for m in manifest) / 1048576.0))
    print("pptx 未标图片出处的卡：%s" % ("、".join(missing_credit) if missing_credit else "无"))
    print("游戏里有、pptx 里没有的卡（应为彩蛋卡）：%s" % ("、".join(left) if left else "无"))
    with io.open(os.path.join(OUT_DIR, "_manifest.json"), "w", encoding="utf-8") as fh:
        fh.write(json.dumps(manifest, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
