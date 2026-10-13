# -*- coding: utf-8 -*-
"""《保卫鄱阳湖》知识卡照片导入器（纯 Python 标准库 + Pillow）

用法：
    python tools/import_knowledge_photos.py "图集.pptx" --replacement "汽车照片.jpg"

产出：
    assets/art/knowledge/photos/<card_id>.png   40 张 512×512（1:1 方裁）RGB
    assets/art/knowledge/photos/_manifest.json  编号 / 卡 id / 卡名 / 类别 / 来源图 / 图片出处

原图按卡名逐一匹配，并中心方裁。保留 512px 原图细节，牌面固定画成
狄鑫斛同样的 246×246。卡 37 使用 --replacement 指定的作者授权照片。
原图来源和许可声明写入随作品提供的 licenses 文档。

⚠ 生成后必须在 Godot 里跑一次 --headless --import，否则 res://...png 加载不到。
"""

import argparse
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
SIDE = 512                                 # 保留图集细节；游戏统一画成 246×246。

# 替换件：卡 37「草洲不是越野场」
REPLACEMENT = {
    "protect_wetland_tracks": {
        "file": None,
        "credit": "图片：易车 · 吉普牧马人论坛（作者授权，用户于 2026-10-13 确认）",
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pptx")
    parser.add_argument("--replacement", help="草洲不是越野场的作者授权替换照片")
    args = parser.parse_args()
    pptx = args.pptx
    REPLACEMENT["protect_wetland_tracks"]["file"] = args.replacement
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
        if kid in REPLACEMENT and REPLACEMENT[kid]["file"]:
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
        license_match = re.search(r"CC BY(?:-SA)? [234]\.0|CC0|公有领域|作者授权", credit)
        declared_license = license_match.group(0) if license_match else "未注明具体许可"
        evidence = "用户确认作者授权" if "作者授权" in credit else "图集图片注释及第 42–43 页声明，尚缺原图来源页核对"
        manifest.append({
            "number": number, "card_id": kid, "name": card_name, "category": category,
            "credit": credit, "credit_url": url, "source": src,
            "source_size": "%dx%d" % before, "out_size": "%dx%d" % (SIDE, SIDE),
            "bytes": os.path.getsize(path),
            "declared_license": declared_license, "license_evidence": evidence,
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

    # 随作品提供署名和许可文本，游戏内不展示来源链接。
    notice = ["知识卡照片来源与许可记录（2026-10-13）", "",
              "原图按用户提供的《鄱阳湖 · 知识卡图集》编号逐一匹配卡名。",
              "处理：中心正方形裁切、缩放为 512×512；牌面显示为 246×246。",
              "以下许可除汽车照片外均是供应图集的声明，不能替代原图来源页和授权证据。",
              "仅写自由许可或未注明出处的图片，需补具体原图链接、作者和许可证后再确认公开分发。",
              "CC BY：保留作者与许可证并说明裁切缩放。CC BY-SA：照片的改作按相同许可证提供。",
              "许可证文本：",
              "https://creativecommons.org/licenses/by/3.0/",
              "https://creativecommons.org/licenses/by/4.0/",
              "https://creativecommons.org/licenses/by-sa/2.0/",
              "https://creativecommons.org/licenses/by-sa/3.0/",
              "https://creativecommons.org/licenses/by-sa/4.0/",
              "https://creativecommons.org/publicdomain/zero/1.0/", ""]
    for row in manifest:
        notice += [f'{row["number"]} {row["name"]} ({row["card_id"]})',
                   row["credit"] or "图集未提供这张照片的出处。",
                   "声明许可：" + row["declared_license"],
                   "证据：" + row["license_evidence"],
                   "原图标识：" + row["source"]]
        if row["credit_url"]: notice.append(row["credit_url"])
        notice.append("")
    notice += ["发牌音效：ZapSplat，playing cards dealing table 002 (20484)。",
               "用户于 2026-10-13 确认：付费账号下载或已有免署名许可。",
               "游戏中整段加速，并限制在发牌动画期间使用；不作为独立素材对外分发。",
               "https://www.zapsplat.com/license-type/standard-license/"]
    with io.open(os.path.join(ROOT, "licenses", "knowledge-photos-and-deal-audio.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(notice) + "\n")


if __name__ == "__main__":
    main()
