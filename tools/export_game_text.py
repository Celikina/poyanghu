"""Number player-facing strings and retain exact, guarded source locations.

The XLSX is authored by build_text_workbook.mjs. This script extracts text and
reads an edited workbook to prepare a reviewable replacement plan; it never
changes live game files. Run with --help for the two supported operations.
"""
from __future__ import annotations

import argparse
from bisect import bisect_right
from collections import Counter, defaultdict
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CJK = re.compile(r"[\u3400-\u9fff\uf900-\ufaff]")
FORMAT = re.compile(r"%(?:%|[-+ 0#]*\d*(?:\.\d+)?[sdiouxXfFeEgGc])")
BB_TAG = re.compile(r"\[/?(?:b|i|u|s|center|left|right|fill|color|font|font_size|url|img|outline_size|outline_color)(?:=[^\]]*)?\]")
CONTEXT = re.compile(r"^(?:(?:static )?func|const|var)\s+([A-Za-z_][A-Za-z_0-9]*)", re.M)
DISPLAY_CONTEXT = re.compile(r"(?:\.text\s*=|\.tooltip_text\s*=|\.placeholder_text\s*=|(?:_make_label|text_label|_make_button|_make_btn|_btn|button|draw_string|_label)\s*\()")
ASCII_VISIBLE = {"QQQi_ZZZhe", "Kanshin", "C3L1K1N4", "Oliveira", "P O Y A N G   /   W E T L A N D S"}
NON_DISPLAY_CONTEXTS = {"_md_emphasis", "_grid_image", "_refresh_run_talents", "_eval_cond", "_eval_condition_simple", "_parse_cond_simple", "_eval_condition"}
PRIORITY = {"界面与操作提示": 0, "行动卡": 1, "知识卡": 2, "物种与植物": 3,
            "危机与季节事件": 4, "结算、日志与规则": 5, "天赋与研修": 6,
            "成就": 7, "更新日志": 8, "通用名称与关联引用": 9, "图片内文字": 10,
            "开发诊断": 11}


def read_source(path):
    # Do not translate newlines: character positions must address original bytes
    # after decoding, and import must preserve unrelated line endings.
    return path.read_bytes().decode("utf-8")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def current_version():
    """游戏内当前版本号（scripts/changelog.gd 的 CURRENT），导出文件名与说明里都用它。"""
    try:
        match = re.search(r'const CURRENT\s*:=\s*"([^"]+)"',
                          (ROOT / "scripts/changelog.gd").read_text(encoding="utf-8"))
        return match.group(1) if match else "?"
    except OSError:
        return "?"


def decode_godot(raw, is_raw=False):
    if is_raw:
        return raw
    result, i = [], 0
    escapes = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f",
               "v": "\v", "a": "\a", "\\": "\\", '"': '"', "'": "'"}
    while i < len(raw):
        if raw[i] != "\\" or i + 1 >= len(raw):
            result.append(raw[i]); i += 1; continue
        c = raw[i + 1]
        if c in escapes:
            result.append(escapes[c]); i += 2
        elif c in ("u", "U"):
            width = 4 if c == "u" else 6
            part = raw[i + 2:i + 2 + width]
            if len(part) == width and re.fullmatch(r"[0-9a-fA-F]+", part):
                result.append(chr(int(part, 16))); i += width + 2
            else:
                raise ValueError(f"Invalid Godot Unicode escape {part!r}")
        elif c in "\r\n":
            i += 2
            if c == "\r" and i < len(raw) and raw[i] == "\n": i += 1
        else:
            # Preserve unknown escapes rather than silently destroying content.
            result.extend(("\\", c)); i += 2
    return "".join(result)


def strings(source, comment="#"):
    """Lex GDScript/config strings without including comments or quote escapes."""
    i, n = 0, len(source)
    while i < n:
        if source[i] == comment:
            stop = source.find("\n", i)
            i = n if stop < 0 else stop + 1
            continue
        if source[i] not in "\"'":
            i += 1; continue
        quote = source[i] * (3 if source.startswith(source[i] * 3, i) else 1)
        prefix = ""
        start = i
        if i > 0 and source[i - 1] in "r&^" and (i < 2 or not (source[i - 2].isalnum() or source[i - 2] == "_")):
            prefix = source[i - 1]; start -= 1
        body = i + len(quote)
        i = body
        while i < n:
            if source[i] == "\\":
                i += 2; continue
            if source.startswith(quote, i):
                raw = source[body:i]
                end = i + len(quote)
                yield {"start": start, "end": end, "quote": quote, "prefix": prefix,
                       "text": decode_godot(raw, prefix == "r"), "literal": source[start:end]}
                i = end; break
            i += 1
        else:
            raise ValueError(f"Unterminated string at character {start}")


def context_at(contexts, start):
    index = bisect_right(contexts[0], start) - 1
    return contexts[1][index] if index >= 0 else "文件配置"


def category(path, context, line):
    name = Path(path).stem
    if "push_warning(" in line or "push_error(" in line or "printerr(" in line:
        return "开发诊断"
    if name == "changelog": return "更新日志"
    if name == "achievements": return "成就"
    if "talent" in name: return "天赋与研修"
    if name == "seasonal_events" or context == "NATURAL_CRISES": return "危机与季节事件"
    if context == "ACTION_CARDS" or path.endswith("dispatch/manifest.json"): return "行动卡"
    if context == "KNOWLEDGE_CARDS": return "知识卡"
    if context in ("SPECIES", "PLANTS"): return "物种与植物"
    if name in ("main", "sandpan_view", "wooden_tier_lever", "card_art_preview") or path == "project.godot": return "界面与操作提示"
    if name == "game_state": return "结算、日志与规则"
    return "通用名称与关联引用"


def asset_texts():
    """Labels physically baked into card fronts, inspected visually on export."""
    faces = {"地理": "geography", "植物": "plants", "鸟类": "birds", "水生动物": "aquatic",
             "外来物种": "invasive", "机制": "mechanisms", "保护行动": "conservation",
             "案例": "cases", "管理策略": "management"}
    labels = defaultdict(list)
    for value, stem in faces.items():
        labels[value].append(f"assets/art/knowledge/{stem}.png")
    for value in ("知识卡", "点击查看", "Click to Check"):
        labels[value].extend(f"assets/art/knowledge/{stem}.png" for stem in faces.values())
        labels[value].append("assets/art/knowledge/easter-egg.png")
    for value in ("未知", "知识卡", "?", "UNKNOW"):
        labels[value].append("assets/art/knowledge/unknown.png")
    for value in ("彩蛋", "狄鑫斛"):
        labels[value].append("assets/art/knowledge/easter-egg.png")
    for folder in ("card-suits", "dispatch"):
        for value, stem in {"生态": "ecology", "社会": "social", "管理": "manage"}.items():
            labels[value].append(f"assets/art/{folder}/{stem}.png")
    labels["萬"].extend(f"assets/art/card-suits/{stem}.png" for stem in ("ecology", "social", "manage"))
    labels["萬"].append("assets/art/artist-test-card-blank.png")
    for card in json.loads((ROOT / "assets/art/dispatch/manifest.json").read_text(encoding="utf-8")):
        rel = f"assets/art/dispatch/cards/{card['id']}.png"
        if (ROOT / rel).exists(): labels[card["name"]].append(rel)
    return labels


def extract(output):
    output.mkdir(parents=True, exist_ok=True)
    paths = sorted(ROOT.glob("scripts/*.gd")) + sorted(ROOT.glob("scenes/**/*.tscn"))
    paths += [ROOT / "project.godot", ROOT / "assets/art/dispatch/manifest.json"]
    grouped, files, skipped, ascii_inventory = {}, {}, [], []
    for path in paths:
        rel = path.relative_to(ROOT).as_posix()
        source = read_source(path)
        file_hash = digest(path.read_bytes())
        files[rel] = file_hash
        matches = list(CONTEXT.finditer(source))
        contexts = ([m.start() for m in matches], [m.group(1) for m in matches])
        tokens = list(strings(source, ";" if path.name == "project.godot" else ("\0" if path.suffix == ".json" else "#")))
        for token in tokens:
            value = token["text"].replace("\r\n", "\n")
            line_no = source.count("\n", 0, token["start"]) + 1
            line_start = source.rfind("\n", 0, token["start"]) + 1
            line_end = source.find("\n", token["end"])
            line = source[line_start:line_end if line_end >= 0 else len(source)]
            context = context_at(contexts, token["start"])
            display = DISPLAY_CONTEXT.search(line) is not None
            if not CJK.search(value):
                if value.strip(): ascii_inventory.append((rel, line_no, context, value, line.strip()[:200]))
                if value in ("<", ">", "<=", ">=", "=="):
                    continue
                if context in NON_DISPLAY_CONTEXTS or value.startswith(("legacy:", "talent:v1:")):
                    continue
                if path.suffix == ".tscn" and not re.match(r"\s*(?:text|tooltip_text|placeholder_text)\s*=", line):
                    continue
                # UI-only ASCII/symbol fragments, dynamic format templates, credits,
                # and visible release version/date values. Never export engine keys.
                explicit_ascii = value in ASCII_VISIBLE
                visible_version = path.stem == "changelog" and (context == "CURRENT" or re.search(r'"(?:version|date)"\s*:\s*$', source[max(0, token["start"]-25):token["start"]]))
                first_argument = re.search(r"(?:_make_label|text_label|_make_button|_make_btn|_btn|button|_label)\s*\(\s*$", source[max(line_start, token["start"]-35):token["start"]])
                assignment = re.search(r"\.(?:text|tooltip_text|placeholder_text)\s*=\s*$", source[max(line_start, token["start"]-40):token["start"]])
                format_fragment = bool(FORMAT.search(value)) and (display or path.stem in ("game_state", "talents"))
                symbol_fragment = bool(value.strip()) and not re.search(r"[A-Za-z0-9_]", value) and path.stem in ("main", "talent_tree_panel", "game_state", "pixel_card_art") and len(value) <= 10
                source_url = context == "KNOWLEDGE_CARDS" and value.startswith("https://")
                if value.startswith(("http://", "https://")) and not source_url: continue
                if not (explicit_ascii or visible_version or first_argument or assignment or format_fragment or symbol_fragment or source_url): continue
            if not value.strip(): continue
            if value.startswith(("res://", "user://", "Godot/app_userdata/")):
                skipped.append({"path": rel, "line": line_no, "text": value, "reason": "资源/存档路径，不是显示文案"}); continue
            if path.suffix == ".json" and not re.search(r'"name"\s*:\s*$', source[max(0, token["start"]-25):token["start"]]): continue
            if path.name == "project.godot" and not line.lstrip().startswith("config/name="): continue
            cat = category(rel, context, line)
            entry = grouped.setdefault(value, {"text": value, "categories": [], "locations": []})
            if cat not in entry["categories"]: entry["categories"].append(cat)
            entry["locations"].append({**{k: token[k] for k in ("start", "end", "quote", "prefix", "literal")},
                "path": rel, "line": line_no, "column": token["start"] - line_start + 1,
                "context": context, "kind": "json" if path.suffix == ".json" else "godot",
                "file_sha256": file_hash, "before": source[max(0, token["start"]-80):token["start"]],
                "after": source[token["end"]:token["end"]+80]})
    for value, locations in asset_texts().items():
        entry = grouped.setdefault(value, {"text": value, "categories": [], "locations": []})
        if "图片内文字" not in entry["categories"]: entry["categories"].append("图片内文字")
        for rel in locations:
            entry["locations"].append({"path": rel, "kind": "raster", "context": "已画入卡面，需同步改素材",
                                       "file_sha256": digest((ROOT / rel).read_bytes())})
    entries = sorted(grouped.values(), key=lambda e: (min(PRIORITY[c] for c in e["categories"]),
                       e["locations"][0]["path"], e["locations"][0].get("start", 0), e["text"]))
    for index, entry in enumerate(entries, 1):
        entry["id"] = index
        entry["category"] = min(entry["categories"], key=lambda c: PRIORITY[c])
        entry["placeholders"] = [] if entry["text"].startswith(("https://", "http://")) else FORMAT.findall(entry["text"])
        entry["bbcode"] = BB_TAG.findall(entry["text"])
        notes = []
        if entry["placeholders"]: notes.append("保留占位符及顺序")
        if entry["bbcode"]: notes.append("保留方括号格式标签")
        if len(entry["locations"]) > 1: notes.append("相同原文同步回填所有关联位置")
        if any(l["kind"] == "raster" for l in entry["locations"]): notes.append("含图片文字，回填时同步修改素材")
        if any(l.get("context") in ("KNOWLEDGE_FACES", "ORDER", "CONFLICT_FEED_TAGS") or '"tags"' in l.get("before", "") or '"needs"' in l.get("before", "") for l in entry["locations"]): notes.append("名称参与分类/对策匹配，回填时同步检查关联")
        if entry["category"] == "开发诊断": notes.append("开发诊断文字，通常不向玩家显示")
        if entry["text"].startswith(("https://", "http://")): notes.append("知识卡引用链接，修改时保留有效地址")
        if re.fullmatch(r"[\d.\-/]+", entry["text"]) and entry["category"] == "更新日志": notes.append("版本号/日期，修改文字不会自动升级版本")
        entry["notes"] = "；".join(notes)
    manifest = {"schema": 1, "exported_at": datetime.now().isoformat(timespec="seconds"),
                "project_root": str(ROOT), "game_version": current_version(), "files": files,
                "numbering": "每种完全相同的原文共用一个编号，关联位置全部保存；编号以此清单为准",
                "entries": entries, "excluded": skipped}
    (output / "文本编号映射.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    (output / "全部文本_编号版.txt").write_text("鄱阳归翎 %s 全部文本\n请保留编号；每条原文为 JSON 字符串，\\n 表示换行。建议在 Excel 的‘修改后文本’列编辑。\n\n" % current_version() +
        "\n".join(f'{e["id"]}. {json.dumps(e["text"], ensure_ascii=False)}' for e in entries) + "\n", encoding="utf-8-sig")
    (output / "使用说明.txt").write_text(
        "请修改 Excel 的 D 列‘修改后文本’，该列已填入原文。未修改的条目保持原样即可。\n"
        "A 列编号和 C 列原文请保留；筛选、排序不影响回填。相同原文共用一个编号，会同步全部关联位置。\n"
        "如需清空一条文案，在 D 列填写 [删除文本]；留空表示保持原文。\n"
        "%s、%d、%+.1f、%% 等是运行时占位符，请保留数量和顺序；[color]、[b] 等方括号标签也请保留。\n"
        "实际游戏由固定文案与实时数值拼接，导出的是模板和文字片段，实时数值由游戏计算。\n"
        "图片中已画好的文字在注意事项中标明，回填时需要同步素材。开发诊断列入清单并明确标注。\n"
        "修改后把 Excel 发给我，或告诉我保存位置。我会按编号回填、检查关联名称和卡面、测试并打开最新版。\n"
        "文本编号映射.json 请保留，不必编辑。它包含来源、字符位置、原始字面量及文件校验值。\n"
        "范围：游戏 scripts、场景显示文字、项目名称、紧急调度牌面清单及已确认的卡面固定文字。\n"
        "不含源码注释、开发工具/插件说明、测试断言、资源路径，以及实时生成的数字。\n",
        encoding="utf-8-sig")
    audit = {"unique_texts": len(entries), "mapped_locations": sum(len(e["locations"]) for e in entries),
             "categories": dict(Counter(e["category"] for e in entries)), "source_files": len(files),
             "raster_locations": sum(l["kind"] == "raster" for e in entries for l in e["locations"])}
    (output / "导出核对.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8")
    inventory = ROOT / "build/text-export/ascii-inventory.txt"
    inventory.parent.mkdir(parents=True, exist_ok=True)
    inventory.write_text("\n".join(f"{p}:{line}\t{ctx}\t{json.dumps(v, ensure_ascii=False)}\t{code}" for p, line, ctx, v, code in ascii_inventory), encoding="utf-8")
    print(json.dumps(audit, ensure_ascii=False))


def read_xlsx(path):
    ns = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main", "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}
    with zipfile.ZipFile(path) as z:
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            shared = ["".join(t.text or "" for t in si.findall(".//s:t", ns)) for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("s:si", ns)]
        wb = ET.fromstring(z.read("xl/workbook.xml"))
        target_sheet = next(s for s in wb.findall("s:sheets/s:sheet", ns) if s.get("name") == "全部文本")
        relations = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        rid = target_sheet.get("{" + ns["r"] + "}id")
        target = next(r.get("Target") for r in relations if r.get("Id") == rid)
        sheet_path = target.lstrip("/") if target.startswith("/") else "xl/" + target
        doc = ET.fromstring(z.read(sheet_path))
        records = []
        for row in doc.findall("s:sheetData/s:row", ns):
            values = {}
            for cell in row.findall("s:c", ns):
                col = re.match(r"[A-Z]+", cell.get("r")).group()
                v = cell.find("s:v", ns)
                raw = v.text if v is not None and v.text is not None else ""
                kind = cell.get("t")
                value = shared[int(raw)] if kind == "s" else ("".join(t.text or "" for t in cell.findall(".//s:t", ns)) if kind == "inlineStr" else raw)
                if cell.find("s:f", ns) is not None: raise ValueError(f"不支持公式单元格：{cell.get('r')}")
                values[col] = value
            if re.fullmatch(r"\d+(?:\.0+)?", values.get("A", "")) and "C" in values:
                records.append({"id": int(float(values["A"])), "original": values["C"], "replacement": values.get("D", "")})
        return records


def encode_literal(value, location):
    if location["kind"] == "json": return json.dumps(value, ensure_ascii=False)
    quote = location["quote"]
    body = value.replace("\\", "\\\\").replace(quote[0], "\\" + quote[0])
    body = body.replace("\r", "\\r").replace("\t", "\\t").replace("\n", "\\n")
    prefix = location["prefix"] if location["prefix"] != "r" else ""
    result = prefix + quote + body + quote
    assert list(strings(result))[0]["text"] == value
    return result


def prepare_plan(workbook, mapping, output):
    manifest = json.loads(mapping.read_text(encoding="utf-8"))
    entries = {e["id"]: e for e in manifest["entries"]}
    records = read_xlsx(workbook)
    seen, replacements, raster, changed = set(), defaultdict(list), [], []
    for row in records:
        number = row["id"]
        if number in seen: raise ValueError(f"重复编号 {number}")
        seen.add(number)
        if number not in entries: raise ValueError(f"未知编号 {number}")
        entry = entries[number]
        if row["original"].replace("\r\n", "\n") != entry["text"]: raise ValueError(f"编号 {number} 的原文被修改，请只改 D 列")
        value = row["replacement"].replace("\r\n", "\n")
        if value in ("", entry["text"]): continue
        if value == "[删除文本]": value = ""
        formats = [] if entry["text"].startswith(("https://", "http://")) else FORMAT.findall(value)
        if formats != entry["placeholders"]: raise ValueError(f"编号 {number} 的格式占位符数量/顺序发生变化")
        if BB_TAG.findall(value) != entry["bbcode"]: raise ValueError(f"编号 {number} 的格式标签发生变化")
        changed.append({"id": number, "before": entry["text"], "after": value})
        for loc in entry["locations"]:
            target = (ROOT / loc["path"]).resolve()
            if not target.is_relative_to(ROOT.resolve()): raise ValueError("映射位置越出项目目录")
            if digest(target.read_bytes()) != loc["file_sha256"]: raise ValueError(f"源码/素材已变化：{loc['path']}，需按原文与上下文重新核对编号 {number}")
            if loc["kind"] == "raster":
                raster.append({"id": number, "path": loc["path"], "before": entry["text"], "after": value}); continue
            source = read_source(target)
            if source[loc["start"]:loc["end"]] != loc["literal"]: raise ValueError(f"编号 {number} 的原位置不再匹配")
            replacements[loc["path"]].append((loc, encode_literal(value, loc)))
    missing = set(entries) - seen
    if missing: raise ValueError(f"缺少 {len(missing)} 个编号，例如 {sorted(missing)[:8]}；请保留完整表格")
    output.mkdir(parents=True, exist_ok=True)
    for rel, changes in replacements.items():
        source = read_source(ROOT / rel)
        for loc, literal in sorted(changes, key=lambda c: c[0]["start"], reverse=True):
            source = source[:loc["start"]] + literal + source[loc["end"]:]
        target = output / "candidate" / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.encode("utf-8"))
    plan = {"changes": changed, "code_locations": sum(len(v) for v in replacements.values()),
            "raster_changes": raster, "candidate_files": list(replacements), "live_game_modified": False}
    (output / "回填预案.json").write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"changed_ids": len(changed), "code_locations": plan["code_locations"], "raster_locations": len(raster)}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    export = sub.add_parser("export")
    export.add_argument("--output", type=Path, default=ROOT / "outputs/text-edit-20261011")
    plan = sub.add_parser("plan")
    plan.add_argument("workbook", type=Path)
    plan.add_argument("--mapping", type=Path, default=ROOT / "outputs/text-edit-20261011/文本编号映射.json")
    plan.add_argument("--output", type=Path, default=ROOT / "build/text-export/import-plan")
    args = parser.parse_args()
    if args.command == "export": extract(args.output)
    else: prepare_plan(args.workbook, args.mapping, args.output)


if __name__ == "__main__": main()
