"""把 export_game_text.py 导出的《文本编号映射.json》铺成可编辑的 XLSX，并标注每条的出处。

列：A 编号 / B 分类 / C 原文 / D 修改后文本 / E 出现界面（在哪能看到）/ F 代码位置 /
    G 关联位置数 / H 注意事项。

E 列按代码位置推断：先看这条文本挂在哪个常量 / 函数上（映射里的 context），再映射到它在
游戏里出现的那块界面；推断不出细则回落到「文件名 › 函数名」。同一条原文落在多处时列出各处。

回填入口是 `python tools/export_game_text.py plan <这个 xlsx>`：它只认工作表「全部文本」的
A 列编号、C 列原文、D 列修改后文本，别的列随便加减都不影响；A 必须仍是数字、C 必须仍是原文
（它靠 C 校验你只动了 D），D 里写 [删除文本] 表示清空。
"""
import argparse
import json
import re
from collections import OrderedDict
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill

ROOT = Path(__file__).resolve().parents[1]
HEAD = ["编号", "分类", "原文", "修改后文本", "出现界面（在哪能看到）", "代码位置", "关联位置数", "注意事项"]

USAGE = [
    "只改 D 列「修改后文本」，A 列编号和 C 列原文请保留（回填时靠它校验你只动了 D）。",
    "E 列是出处：按代码位置推断这条文案在游戏里哪块界面能看到；F 列给到具体文件与行号。",
    "筛选、排序都不影响回填；相同原文共用一个编号，会一次同步到全部关联位置。",
    "要清空一条文案就在 D 列写 [删除文本]；留空或原样保留都表示不改。",
    "%s、%d、%+.1f、%% 这类是运行时占位符，数量与顺序必须保留；[color]、[b] 之类方括号标签同理。",
    "E 列写「卡面 / 图鉴图片里」的，字是画在图片上的，改文本要同步改素材。",
    "改完把 xlsx 发回或告知路径，回填走：python tools/export_game_text.py plan <xlsx>。",
]

# context（文本挂着的常量 / 函数）→ 玩家能在哪看到
CONTEXT_PLACES = {
    "RELEASES": "主菜单 › 更新日志面板",
    "CURRENT": "主菜单 › 更新日志面板（当前版本号）",
    "KNOWLEDGE_CARDS": "知识卡图鉴与知识卡详情",
    "KNOWLEDGE_FACES": "知识卡卡面",
    "KNOWLEDGE_CATEGORY_COLORS": "知识卡图鉴（类别色）",
    "ORDER": "知识卡图鉴（分类顺序）",
    "LIST": "图鉴列表（知识卡 / 成就）",
    "ACTION_CARDS": "行动卡：手牌、牌库、卡牌详情",
    "EVENTS": "危机预警与季节事件弹窗",
    "NATURAL_CRISES": "危机预警与季节事件弹窗",
    "TALENTS": "天赋研修 / 开局天赋弹窗",
    "GROUPS": "天赋树面板（分组名）",
    "NODES": "天赋树面板（词条）",
    "SYNERGIES": "卡牌协同提示（结算小票）",
    "SPECIES": "物种图鉴与沙盘悬停",
    "PLANTS": "植物图鉴与沙盘悬停",
    "SITUATION_TEXT": "顶部事件横幅与事件弹窗",
    "SITUATION_WHY": "顶部事件横幅与事件弹窗",
    "NARRATIVE_BEATS": "顶部事件横幅（开场 / 政策 / 收官）",
    "METRIC_NAMES": "右侧生态监测面板与结算日志",
    "METRIC_REMEDY": "失败报告（下次怎么打）",
    "FAILURE_TEXT": "失败报告（被撤换）",
    "SEASON_NAMES": "HUD 季节显示与结算日志",
    "SEASON_TAGLINE": "HUD 季节标签",
    "SEASONS": "HUD 季节显示",
    "WATER_SEASON_RULES": "结算日志与水位悬停（季节参考区间）",
    "WARN_SHORT_METRIC": "顶部预警条",
    "SCORE_PHASE_NAMES": "结算小票（来源分项名）",
    "TIER_NAMES": "出牌档位（基础 / 有效 / 深度投入）",
    "LEVER_STATE_TEXT": "出牌档位木杆提示",
    "CATEGORY_NAMES": "知识卡图鉴（类别名）",
    "CONFLICT_FEED_TAGS": "内部标签（人鸟矛盾抽牌权重，不在界面显示）",
    "BGM_NAMES": "设置里的背景音乐名",
    "文件配置": "游戏名称（窗口标题 / 主菜单大字）",
    "已画入卡面，需同步改素材": "卡面 / 图鉴图片里（字画在图上，要同步改素材）",
}

# context 前缀 → 界面
PREFIX_PLACES = [
    ("_fill_", "右侧生态监测面板与悬停小窗"),
    ("_eval_", "结算报告（生态 / 社会 / 管理维度）"),
    ("_build_achievement", "成就面板"),
    ("_build_knowledge", "知识卡图鉴与详情"),
    ("_build_dispatch", "紧急调度面板"),
    ("_fill_dispatch", "紧急调度面板"),
    ("_build_warn", "顶部预警条与预警历史"),
    ("_crisis_", "危机预警与季节事件弹窗"),
    ("_show_crisis", "危机预警与季节事件弹窗"),
    ("_maybe_", "结算日志（事件与危机判定）"),
    ("_resolve_", "结算日志（危机与遗留结算）"),
    ("_advance_", "结算日志与提前胜利进度"),
    ("_restore_", "读档 / 结算日志（遗留恢复）"),
    ("_apply_", "结算过程（应用到指标）"),
    ("_update_", "游戏内 HUD（实时刷新）"),
    ("_refresh_", "游戏内 HUD（实时刷新）"),
    ("_sync_", "暂停菜单与设置"),
    ("_on_", "界面交互提示（按钮回调）"),
    ("_make_", "界面构件文字（按钮 / 标签 / 卡片）"),
    ("_open_", "牌库与知识卡查看器"),
    ("_draw_", "天赋树面板（绘制）"),
]

# 文件 → 界面（context 兜不住时用）
FILE_PLACES = {
    "changelog.gd": "主菜单 › 更新日志面板",
    "seasonal_events.gd": "危机预警与季节事件弹窗",
    "achievements.gd": "成就面板",
    "knowledge.gd": "知识卡图鉴与收藏（存档文案）",
    "knowledge_categories.gd": "知识卡图鉴（分类）",
    "talent_tree_data.gd": "天赋树面板",
    "talent_tree_panel.gd": "天赋树面板",
    "talents.gd": "天赋研修 / 开局天赋弹窗",
    "pixel_card_art.gd": "卡面像素画的内部命名（不直接显示）",
    "card_art_preview.gd": "美术预览工具（不显示给玩家）",
    "sandpan_view.gd": "沙盘视图（查看沙盘按钮）",
    "main.gd": "游戏内 HUD / 各类弹窗（见代码位置）",
    "game_state.gd": "结算日志与规则文案",
    "manifest.json": "紧急调度牌面",
    "project.godot": "游戏名称（窗口标题 / 主菜单大字）",
}


def place_for(location, category):
    context = str(location.get("context", ""))
    name = Path(location.get("path", "")).name
    if location.get("kind") == "raster":
        return "卡面 / 图鉴图片里（字画在图上，要同步改素材）"
    if category == "开发诊断":
        return "不显示给玩家（调试信息）"
    # 「文件配置」在 project.godot 里是游戏名，在调度牌清单里是牌名，得分开
    if name == "project.godot":
        return "游戏名称（窗口标题 / 主菜单大字）"
    if name == "manifest.json":
        return "紧急调度牌面与调度面板"
    if context in CONTEXT_PLACES:
        return CONTEXT_PLACES[context]
    for prefix, place in PREFIX_PLACES:
        if context.startswith(prefix):
            return place
    if name in FILE_PLACES:
        return FILE_PLACES[name]
    return "%s › %s" % (name or "?", context or "?")


def summarize(rows, limit=3):
    """去重并保留顺序；超过 limit 条时收成「甲、乙 等 N 处」。"""
    unique = list(OrderedDict.fromkeys(rows))
    if len(unique) <= limit:
        return "；".join(unique)
    return "；".join(unique[:limit]) + " 等 %d 处" % len(unique)


def code_refs(entry, limit=2):
    refs = []
    for loc in entry["locations"]:
        if loc.get("kind") == "raster":
            refs.append("%s（图）" % loc["path"])
        else:
            refs.append("%s:%s（%s）" % (loc["path"], loc.get("line", "?"), loc.get("context", "")))
    unique = list(OrderedDict.fromkeys(refs))
    if len(unique) <= limit:
        return "\n".join(unique)
    return "\n".join(unique[:limit]) + "\n等 %d 处（详见 文本编号映射.json）" % len(unique)


def build_rows(manifest):
    rows = []
    for entry in manifest["entries"]:
        places = [place_for(loc, entry["category"]) for loc in entry["locations"]]
        rows.append([entry["id"], entry["category"], entry["text"], entry["text"],
                     summarize(places), code_refs(entry), len(entry["locations"]), entry["notes"]])
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path, nargs="?",
                        default=ROOT / "outputs/text-edit-20261011/文本编号映射.json")
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    manifest = json.loads(args.mapping.read_text(encoding="utf-8"))
    rows = build_rows(manifest)
    target = args.output or args.mapping.with_name("全部文本_编号版.xlsx")

    book = Workbook()
    sheet = book.active
    sheet.title = "全部文本"
    sheet.append(HEAD)
    for cell in sheet[1]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="4A6B57")
        cell.alignment = Alignment(vertical="center", wrap_text=True)
    for row in rows:
        sheet.append(row)
    for col, width in {"A": 8, "B": 14, "C": 56, "D": 56, "E": 30, "F": 34, "G": 10, "H": 30}.items():
        sheet.column_dimensions[col].width = width
    for row in sheet.iter_rows(min_row=2, max_row=sheet.max_row, min_col=1, max_col=len(HEAD)):
        for cell in row:
            cell.alignment = Alignment(wrap_text=True, vertical="top")
    sheet.freeze_panes = "A2"

    # 按界面分组：审文案时按屏幕一块一块过
    grouped = OrderedDict()
    for entry, row in zip(manifest["entries"], rows):
        for place in OrderedDict.fromkeys(row[4].split("；")):
            grouped.setdefault(re.sub(r"\s*等 \d+ 处$", "", place), []).append(entry["id"])
    index = book.create_sheet("按界面分组")
    index.append(["出现界面", "条数", "编号"])
    for place, ids in sorted(grouped.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        index.append([place, len(ids), "、".join(str(i) for i in ids)])
    for col, width in {"A": 40, "B": 8, "C": 90}.items():
        index.column_dimensions[col].width = width
    for row in index.iter_rows(min_row=2, max_row=index.max_row, min_col=1, max_col=3):
        for cell in row:
            cell.alignment = Alignment(wrap_text=True, vertical="top")

    notes = book.create_sheet("使用说明")
    notes.column_dimensions["A"].width = 110
    for line in ["《%s》文本修改表（游戏内版本 %s，导出时间 %s）"
                 % (Path(manifest["project_root"]).name, manifest["game_version"],
                    manifest["exported_at"]), ""] + USAGE:
        notes.append([line])
    for row in notes.iter_rows():
        row[0].alignment = Alignment(wrap_text=True, vertical="top")

    book.save(target)

    # 同一份内容再落一份纯文本，方便直接搜索/对比
    plain = target.with_name("全部文本_带出处.txt")
    with plain.open("w", encoding="utf-8-sig") as fh:
        fh.write("鄱阳归翎 %s 全部文本（含出处）\n每条：编号. 出处 | 原文\n\n" % manifest["game_version"])
        for row in rows:
            fh.write("%d. %s | %s\n" % (row[0], row[4].replace("\n", " "), json.dumps(row[2], ensure_ascii=False)))

    print(json.dumps({"workbook": str(target), "plain": str(plain), "entries": len(rows),
                      "places": len(grouped), "game_version": manifest["game_version"]},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
