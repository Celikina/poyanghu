extends RefCounted

const Motion = preload("res://scripts/motion.gd")
## Shared presentation tokens. No gameplay state is changed here.
const INK := Color("303e49")
const PANEL := Color("44565c")
const EDGE := Color("91a397")
const PAPER := Color("f5ecd8")
const GOLD := Color("edc68a")
const MINT := Color("c7dcae")
const MEADOW := Color("b8c66d")
const SUMMER_MEADOW := Color("a4bd65")
const AUTUMN_MEADOW := Color("d8ad71")
const SNOW := Color("edf1e9")
const WATER_DEEP := Color("526e86")
const WATER_MID := Color("779ba9")
const WATER_SHALLOW := Color("acc9ce")
const SAND := Color("e0c89b")
const SOIL := Color("baaa86")
const ART := preload("res://assets/art/conservation-cards.png")
const UiSkin := preload("res://scripts/ui_skin.gd")

static func box(bg: Color, edge: Color, margin: int = 12) -> StyleBoxFlat:
	# 16bit：直角 + 2px 硬描边，不要圆角和柔光投影。
	# 颜色仍由调用方决定（指标条 / 天赋树节点靠颜色传数据），
	# 想统一配色的地方走 UiSkin.panel() / UiSkin.text_box()。
	return UiSkin.styled(bg, edge, float(margin))

static func card_style(selected: bool = false) -> StyleBoxFlat:
	var s := box(Color.TRANSPARENT, GOLD, 0)
	s.set_border_width_all(0)
	s.set_meta("card_outline", selected)
	s.set_corner_radius_all(0)
	# 卡牌投影由独立接收平面绘制，StyleBox 阴影会随卡面一起旋转。
	s.shadow_size = 0
	s.shadow_color = Color(0.02, 0.10, 0.11, 0.55)
	return s

static func illustration(card: Dictionary) -> AtlasTexture:
	var category := str(card.get("category", "ecology"))
	var column: int = {"ecology": 0, "social": 1, "manage": 2}.get(category, 0)
	# Stable artwork selection without consuming the game's random generator.
	var row := posmod(str(card.get("id", "")).hash(), 2)
	var tile := Vector2(ART.get_width() / 3.0, ART.get_height() / 2.0)
	var atlas := AtlasTexture.new()
	atlas.atlas = ART
	atlas.region = Rect2(Vector2(column, row) * tile, tile)
	atlas.filter_clip = true
	return atlas

static func style_button(b: Button, danger: bool = false, primary: bool = false) -> void:
	preload("res://scripts/motion_button.gd").attach(b)
	# 16bit 按钮：四个状态只换填充色，描边统一奶白，按下时缩 1px。
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(state, UiSkin.button(state, primary, danger))
	# 键盘焦点仍然要有可见框（透明底 + 金边），别把可访问性一起换掉
	var focus := UiSkin.styled(Color(0, 0, 0, 0), GOLD, 7.0)
	b.add_theme_stylebox_override("focus", focus)
	# 深蓝底上文字统一亮白 + 深色描边，和 16bit 的块状字一个调子
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, UiSkin.LABEL_COLOR)
	b.add_theme_color_override("font_disabled_color", UiSkin.LABEL_DISABLED)
	b.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.12, 0.9))
	b.add_theme_constant_override("outline_size", 3)

static func button_feedback(b: Button, active: bool) -> void:
	var previous: Tween = b.get_meta("feedback_tween") if b.has_meta("feedback_tween") else null
	if previous and previous.is_valid(): previous.kill()
	var tw := Motion.tween(b, "response", "feedback")
	b.set_meta("feedback_tween", tw)
	tw.tween_property(b, "modulate", Color(1.09, 1.09, 1.04) if active else Color.WHITE, 0.14)
