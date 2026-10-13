extends RefCounted
## 16bit 复古 UI 皮肤 —— 像素 9 宫格贴图（assets/ui/，都是这个项目自己生成的，
## 不是把美术给的参考图拉伸贴上去）。贴图里已经画好了：像素阶梯圆角、右下硬投影、
## 抖动颗粒纹理、斜面高光。切图/居中平铺都在这里，改一处就换全 UI。

const PANEL := preload("res://assets/ui/ui-panel.png")              # 普通「框」
const PANEL_DANGER := preload("res://assets/ui/ui-panel-danger.png")
const TEXTBOX := preload("res://assets/ui/ui-textbox.png")          # 输入框
const TRACK := preload("res://assets/ui/ui-track.png")              # 进度条底槽
const BTN_DISABLED := preload("res://assets/ui/ui-btn-disabled.png")
const BTN := {
	"blue": {
		"normal": preload("res://assets/ui/ui-btn-blue-normal.png"),
		"hover": preload("res://assets/ui/ui-btn-blue-hover.png"),
		"pressed": preload("res://assets/ui/ui-btn-blue-pressed.png"),
	},
	"primary": {
		"normal": preload("res://assets/ui/ui-btn-primary-normal.png"),
		"hover": preload("res://assets/ui/ui-btn-primary-hover.png"),
		"pressed": preload("res://assets/ui/ui-btn-primary-pressed.png"),
	},
	"danger": {
		"normal": preload("res://assets/ui/ui-btn-danger-normal.png"),
		"hover": preload("res://assets/ui/ui-btn-danger-hover.png"),
		"pressed": preload("res://assets/ui/ui-btn-danger-pressed.png"),
	},
}

# 素材本体 48px：半径 10px 的像素圆弧 + 外描边 1 + 奶白边 3 + 斜面 2（角部结构 16px）
const EDGE := 16.0
const SHADOW := 3.0        # 右下投影
const BTN_CONTENT := 7.0   # 按钮内容边距沿用旧值 → 行高不变
const PANEL_CONTENT := 12.0
const LABEL_COLOR := Color("f4f8ff")
const LABEL_DISABLED := Color("c3cbd6")

## 通用的贴图 9 宫格：中心与边条用平铺（TILE）而不是拉伸，
## 像素颗粒才不会被拉成条状。expand 让投影/圆环画到控件框外面，不动布局。
static func _nine(tex: Texture2D, m: float, pad: float, sh: float, content: float) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = m + pad
	s.texture_margin_top = m + pad
	s.texture_margin_right = m + pad + sh
	s.texture_margin_bottom = m + pad + sh
	s.expand_margin_left = pad
	s.expand_margin_top = pad
	s.expand_margin_right = pad + sh
	s.expand_margin_bottom = pad + sh
	s.set_content_margin_all(content)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return s


## 面板／提示框（danger = 危机、清空存档那类暖红面板）
## 碎裂演出（刷新手牌用掉时）的碎片配色：跟蓝色按钮同一套色，
## 亮面 / 底色 / 暗面 / 悬停描边循环取，别再用旧的木板棕黄。
const SHARD_COLORS := [Color("34699f"), Color("2a5c8f"), Color("16344f"), Color("93b9e6")]


static func panel(danger: bool = false, margin: float = PANEL_CONTENT) -> StyleBoxTexture:
	return _nine(PANEL_DANGER if danger else PANEL, EDGE, 0.0, SHADOW, margin)


## 输入框（更暗的底，一眼看出能打字）
static func text_box(margin: float = 8.0) -> StyleBoxTexture:
	return _nine(TEXTBOX, EDGE, 0.0, SHADOW, margin)


## 按钮：state = normal / hover / pressed / hover_pressed / disabled
## 悬停态素材自带一圈 #93b9e6 描边，靠 expand 画在按钮外面，所以按钮本体的
## 大小和点击区都不会变。
static func button(state: String, primary: bool = false, danger: bool = false) -> StyleBoxTexture:
	if state == "disabled":
		return _nine(BTN_DISABLED, EDGE, 0.0, SHADOW, BTN_CONTENT)
	var pal: String = "danger" if danger else ("primary" if primary else "blue")
	var key := "hover" if state == "hover" else ("pressed" if state in ["pressed", "hover_pressed"] else "normal")
	var sh := 1.0 if key == "pressed" else SHADOW
	return _nine(BTN[pal][key], EDGE, 0.0, sh, BTN_CONTENT)


## 进度条底槽
static func progress_track() -> StyleBoxTexture:
	return _nine(TRACK, 4.0, 0.0, 0.0, 0.0)


## 进度条填充：缩进 2px 落在槽里，不盖住槽的描边（颜色仍按指标区分，那是数据）
static func progress_fill(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.set_expand_margin(SIDE_LEFT, -2.0)
	s.set_expand_margin(SIDE_RIGHT, -2.0)
	s.set_expand_margin(SIDE_TOP, -2.0)
	s.set_expand_margin(SIDE_BOTTOM, -2.0)
	return s


## 少数「颜色本身是数据」的地方（天赋树节点、指标条等）仍然现场拼 StyleBoxFlat，
## 但几何统一成 16bit：直角 + 2px 描边。
static func styled(bg: Color, edge: Color, margin: float = 12.0, border: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(margin)
	s.anti_aliasing = false
	return s
