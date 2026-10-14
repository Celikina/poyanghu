extends Control
## 开始页右上角的照片条：鄱阳湖实景轮播（主标题右边那几张滚动图片）。
##
## 需求（2026-10-14）：主标题右边放几张照片，可左右切换；点击图片放大看，
## 放大后要标出处（鄱阳湖国家湿地公园官网「摄影佳作」栏目）。
##
## 三条改之前先读的约束：
## 1. 纯展示层：不读也不写任何游戏状态（存档 / 天赋 / 成就都不碰）。
## 2. 照片清单写死在 PHOTOS 里，**不扫目录** —— 导出包里 res:// 只有导入产物
##    （.ctex），源 jpg 不在包内，DirAccess 扫描在发行版上会扫到 0 张。
## 3. 放大层挂在**父节点**（menu_root）上，不是挂在自己这个 444×328 的子树里 ——
##    否则「全屏」只铺满这个小方块。
## 显隐由 main.gd 的 _sync_title_photos() 控制（跟着左下角选项列走）。

const VisualTheme := preload("res://scripts/visual_theme.gd")
const UiSkin := preload("res://scripts/ui_skin.gd")

## 13 张照片，顺序 = 文件名（title-photo-01..13）；与原图的对照见
## assets/title-photos/README.md
const PHOTOS: Array[String] = [
	"res://assets/title-photos/title-photo-01.jpg",
	"res://assets/title-photos/title-photo-02.jpg",
	"res://assets/title-photos/title-photo-03.jpg",
	"res://assets/title-photos/title-photo-04.jpg",
	"res://assets/title-photos/title-photo-05.jpg",
	"res://assets/title-photos/title-photo-06.jpg",
	"res://assets/title-photos/title-photo-07.jpg",
	"res://assets/title-photos/title-photo-08.jpg",
	"res://assets/title-photos/title-photo-09.jpg",
	"res://assets/title-photos/title-photo-10.jpg",
	"res://assets/title-photos/title-photo-11.jpg",
	"res://assets/title-photos/title-photo-12.jpg",
	"res://assets/title-photos/title-photo-13.jpg",
]

const SOURCE_SITE := "图片来源：鄱阳湖国家湿地公园官网「摄影佳作」"
const SOURCE_URL := "http://www.jxpoyanghu.com.cn/lyfw_3/p-12-12.html"

## 版式（设计分辨率 1280×720 下的像素）
## ⚠ 上边距不是随意定的：右上角草地上贴着苦力怕彩蛋（屏幕 (1041,62)~(1061,87)），
## 照片条压住它就是把这个彩蛋藏了。所以照片框上缘压到 116，整块从 y=104 开始，
## 彩蛋那 25px 高的方块脸留在地图里。改小/改位置前先量一遍彩蛋（见 版本更新 doc）。
const FRAME_MARGIN_RIGHT := 56.0          # 照片框右缘距屏幕右边
const FRAME_MARGIN_TOP := 116.0           # 照片框上缘距屏幕顶（让开苦力怕彩蛋）
const BLOCK := Vector2(444.0, 328.0)      # 整块 = 面板（照片框 + 一行说明）
const FRAME := Vector2(420.0, 278.0)      # 照片区 1.51:1 —— 这 13 张的宽高比中位数
const PANEL_PAD := 12.0                   # UiSkin.panel() 的内容边距
const TEXT_X := 12.0                      # 说明文字与照片框左右对齐
const TEXT_W := 420.0
const ARROW := Vector2(36.0, 64.0)
const CAPTION_Y := 300.0
const AUTO_SEC := 6.0                     # 自动换片间隔（鼠标停在照片上时暂停）
const SLIDE_SEC := 0.28                   # 换片：淡入 + 从箭头方向滑入 24px

## 放大层版式
const ZOOM_TOP := 40.0
const ZOOM_PHOTO_H := 540.0
const ZOOM_SIDE_MARGIN := 200.0
const ZOOM_ARROW := Vector2(48.0, 96.0)
const ZOOM_SITE_Y := 596.0
const ZOOM_URL_Y := 630.0
const ZOOM_HINT_Y := 664.0

## main.gd 注入：静止偏好为真 → 不自动换片、不做滑动动画
var reduced_motion_check := Callable()

var _index := 0
var _front := 1                            # 当前显示的是 _rects[..] 里的哪一个
var _current_tex: Texture2D = null         # 当前这张的纹理
var _fade := 1.0                           # 1 = 上一次切换动画已经落定
var _slide_from := 0.0
var _auto_clock := 0.0
var _hover := false
var _rects: Array[TextureRect] = []
var _frame_box: Control = null
var _border: Panel = null
var _caption: Label = null
var _zoom: Control = null
var _zoom_panel: Panel = null
var _zoom_photo: TextureRect = null
var _zoom_prev: Button = null
var _zoom_next: Button = null
var _zoom_link: LinkButton = null


func _ready() -> void:
	# 右上角锚定；块本身不吃输入（只有照片框、箭头、放大层吃）
	# 位置按「照片框右缘 / 上缘距屏幕边」反推：面板比框外扩 PANEL_PAD，所以块本身要
	# 往回让出这 12px，否则照片框会往外多出 12px（右边距看着比设计值小一圈）。
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -(FRAME_MARGIN_RIGHT - PANEL_PAD)
	offset_left = offset_right - BLOCK.x
	offset_top = FRAME_MARGIN_TOP - PANEL_PAD
	offset_bottom = offset_top + BLOCK.y
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false                        # 由 main.gd 的 _sync_title_photos() 点亮
	_build_strip()
	_build_zoom()
	_begin(0, 0, true)


func _process(delta: float) -> void:
	_step_fade(delta)
	if not visible or _zoom != null and _zoom.visible or _hover or PHOTOS.size() <= 1:
		return
	if _reduced_motion():
		return
	_auto_clock += delta
	if _auto_clock >= AUTO_SEC:
		_auto_clock = 0.0
		_step(1)


# ==================== 照片条 ====================

func _build_strip() -> void:
	var panel := Panel.new()
	panel.name = "PhotoPanel"
	panel.add_theme_stylebox_override("panel", UiSkin.panel())
	panel.position = Vector2.ZERO
	# 面板包住照片 + 下面三行说明：说明文字压在亮色的沙盘上根本读不出来
	# （2026-10-14 截图实测：绿草地上 12px 淡字几乎看不见），所以全部坐进面板里。
	panel.size = BLOCK
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_frame_box = Control.new()
	_frame_box.name = "PhotoFrame"
	_frame_box.position = Vector2(PANEL_PAD, PANEL_PAD)
	_frame_box.size = FRAME
	_frame_box.clip_contents = true        # 照片以 COVER 铺满，溢出的部分靠这层裁掉
	_frame_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame_box)

	var back := ColorRect.new()
	back.color = Color("101820")
	back.position = Vector2.ZERO
	back.size = FRAME
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_box.add_child(back)

	# 两张 TextureRect 交替做淡入淡出：不必重排子节点顺序，也就不会把箭头压到照片下面
	for i in 2:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2.ZERO
		tr.size = FRAME
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.visible = i == 0
		_frame_box.add_child(tr)
		_rects.append(tr)

	# 点图放大：一整块透明按钮盖在照片上（箭头加在它之后，所以箭头优先）
	var catcher := Button.new()
	catcher.name = "PhotoCatcher"
	catcher.position = Vector2.ZERO
	catcher.size = FRAME
	catcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	catcher.add_theme_stylebox_override("normal", _flat_box(Color(0, 0, 0, 0)))
	catcher.add_theme_stylebox_override("hover", _flat_box(Color(1, 1, 1, 0.06)))
	catcher.add_theme_stylebox_override("pressed", _flat_box(Color(0, 0, 0, 0.16)))
	catcher.add_theme_stylebox_override("focus", _flat_box(Color(0, 0, 0, 0)))
	catcher.pressed.connect(_open_zoom)
	catcher.mouse_entered.connect(func() -> void: _hover = true)
	catcher.mouse_exited.connect(func() -> void: _hover = false)
	catcher.gui_input.connect(_on_catcher_input)
	_frame_box.add_child(catcher)

	# 左右切换箭头（贴在照片两边）
	var prev_btn := _arrow_button("◀", _step.bind(-1))
	prev_btn.position = Vector2(8.0, (FRAME.y - ARROW.y) * 0.5)
	prev_btn.size = ARROW
	_frame_box.add_child(prev_btn)
	var next_btn := _arrow_button("▶", _step.bind(1))
	next_btn.position = Vector2(FRAME.x - ARROW.x - 8.0, (FRAME.y - ARROW.y) * 0.5)
	next_btn.size = ARROW
	_frame_box.add_child(next_btn)

	# 框线压在照片最上层：2px 深墨 + 内圈 1px 金，和 16bit 皮肤一个调子
	_border = Panel.new()
	_border.add_theme_stylebox_override("panel", _edge_box(Color("1a1206"), 3.0))
	_border.position = Vector2.ZERO
	_border.size = FRAME
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_box.add_child(_border)
	var inner := Panel.new()
	inner.add_theme_stylebox_override("panel", _edge_box(Color(VisualTheme.GOLD, 0.42), 1.0))
	inner.position = Vector2(3.0, 3.0)
	inner.size = FRAME - Vector2(6.0, 6.0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_box.add_child(inner)

	_caption = _label("", 12, VisualTheme.MINT)
	_caption.position = Vector2(TEXT_X, CAPTION_Y)
	add_child(_caption)
	# 出处只出现在放大页（含可点链接）。开始页这条只留计数 + 入口提示，
	# 别把长 URL 杵在沙盘上（2026-10-14 用户口径：链接只出现在详情页）。
	var hint := _label("点击图片放大 ▸", 12, VisualTheme.GOLD)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.position = Vector2(TEXT_X, CAPTION_Y)
	hint.size = Vector2(TEXT_W, 18.0)
	add_child(hint)

	_refresh_caption()


## 滚轮也能换片（触控板用户更顺手）；点左键仍然交给按钮去放大
func _on_catcher_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var button := (event as InputEventMouseButton).button_index
	if button == MOUSE_BUTTON_WHEEL_DOWN:
		_step(1)
	elif button == MOUSE_BUTTON_WHEEL_UP:
		_step(-1)


## 换一张。dir: -1 上一张 / +1 下一张（决定从哪一侧滑进来）
func _step(dir: int) -> void:
	if PHOTOS.size() <= 1:
		return
	_settle_fade()
	_begin(posmod(_index + dir, PHOTOS.size()), dir, false)
	_auto_clock = 0.0


## instant = true 时不做动画（开机第一张贴上就是这么来的）
func _begin(index: int, dir: int, instant: bool) -> void:
	if PHOTOS.is_empty():
		return
	_index = posmod(index, PHOTOS.size())
	var incoming: TextureRect = _rects[1 - _front]
	var outgoing: TextureRect = _rects[_front]
	incoming.texture = load(PHOTOS[_index]) as Texture2D
	# ⚠ 大图（放大层）读的是这个 _current_tex，不是 _rects[_front].texture：
	#   _front 要等淡入结束才翻页，淡入期间 [_front] 还是**上一张**。
	#   早先 _refresh_zoom() 直接读了 [_front]，结果在放大页里按箭头大图不动
	#   （tests/title_photo_carousel_probe.gd 抓到的）。
	_current_tex = incoming.texture
	incoming.visible = true
	_slide_from = 0.0 if instant or _reduced_motion() else 24.0 * float(dir)
	incoming.position = Vector2(_slide_from, 0.0)
	incoming.modulate.a = 1.0 if instant or _reduced_motion() else 0.0
	if instant or _reduced_motion():
		outgoing.visible = false
		outgoing.modulate.a = 1.0
		_fade = 1.0
		_front = 1 - _front
	else:
		_fade = 0.0
	_refresh_caption()
	if _zoom != null and _zoom.visible:
		_refresh_zoom()


## 没走完的淡入直接落定（连点箭头时不会两张叠在一起）
func _settle_fade() -> void:
	if _fade >= 1.0:
		return
	var incoming: TextureRect = _rects[1 - _front]
	incoming.modulate.a = 1.0
	incoming.position = Vector2.ZERO
	_rects[_front].visible = false
	_rects[_front].modulate.a = 1.0
	_front = 1 - _front
	_fade = 1.0


func _step_fade(delta: float) -> void:
	if _fade >= 1.0:
		return
	_fade = minf(1.0, _fade + delta / maxf(0.0001, SLIDE_SEC))
	var eased := 1.0 - pow(1.0 - _fade, 3.0)
	var incoming: TextureRect = _rects[1 - _front]
	incoming.modulate.a = eased
	incoming.position = Vector2(_slide_from * (1.0 - eased), 0.0)
	_rects[_front].modulate.a = 1.0 - eased
	if _fade >= 1.0:
		_rects[_front].visible = false
		_rects[_front].modulate.a = 1.0
		_front = 1 - _front


func _refresh_caption() -> void:
	if _caption == null:
		return
	_caption.text = "第 %d / %d 张" % [_index + 1, PHOTOS.size()]


# ==================== 放大层 ====================

func _build_zoom() -> void:
	var host := get_parent()
	if host == null:
		return
	var overlay := Control.new()
	overlay.name = "PhotoZoom"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP     # 模态：盖住底下的标题页
	overlay.visible = false
	# 挂到 menu_root 上而不是自己的子树里 —— 这里才是「全屏」坐标系
	host.add_child(overlay)
	_zoom = overlay

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	_zoom_panel = Panel.new()
	_zoom_panel.add_theme_stylebox_override("panel", UiSkin.panel())
	_zoom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_zoom_panel)

	_zoom_photo = TextureRect.new()
	_zoom_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_zoom_photo.stretch_mode = TextureRect.STRETCH_SCALE    # 尺寸由 _refresh_zoom 按原图比例算
	_zoom_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_zoom_photo)

	_zoom_prev = _arrow_button("◀", _step.bind(-1), ZOOM_ARROW)
	overlay.add_child(_zoom_prev)
	_zoom_next = _arrow_button("▶", _step.bind(1), ZOOM_ARROW)
	overlay.add_child(_zoom_next)

	var site := _label(SOURCE_SITE, 24, VisualTheme.PAPER)
	site.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_full_width(site, ZOOM_SITE_Y, 30.0)
	overlay.add_child(site)
	# 出处链接做成真超链接：LinkButton + uri，点它走系统默认浏览器打开。
	# 用 HBox 居中而不是靠 LinkButton 自己的 alignment —— 后者在 LinkButton 上
	# 各版本行为不一，塞进居中容器最稳（链接宽度是文字宽度决定的）。
	var link_row := HBoxContainer.new()
	link_row.alignment = BoxContainer.ALIGNMENT_CENTER
	link_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_width(link_row, ZOOM_URL_Y, 34.0)
	overlay.add_child(link_row)
	var link := LinkButton.new()
	link.text = SOURCE_URL
	link.uri = SOURCE_URL            # 引擎自带：按下即 OS.shell_open(uri)
	link.underline = LinkButton.UNDERLINE_MODE_ALWAYS   # 不悬停也看得出来是链接
	link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	link.add_theme_font_size_override("font_size", 24)
	link.add_theme_color_override("font_color", VisualTheme.GOLD)
	link.add_theme_color_override("font_hover_color", Color.WHITE)
	link.add_theme_color_override("font_pressed_color", VisualTheme.PAPER)
	link_row.add_child(link)
	_zoom_link = link
	var hint := _label("◀ ▶ 或方向键切换 · 点击任意处或按 ESC 关闭", 12, Color(VisualTheme.MINT, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_full_width(hint, ZOOM_HINT_Y, 20.0)
	overlay.add_child(hint)

	var close_btn := _styled_button("关闭", 12, _close_zoom)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -152.0
	close_btn.offset_right = -24.0
	close_btn.offset_top = 24.0
	close_btn.offset_bottom = 72.0
	overlay.add_child(close_btn)

	overlay.gui_input.connect(_on_zoom_input)


func _open_zoom() -> void:
	if _zoom == null or PHOTOS.is_empty():
		return
	_settle_fade()
	_zoom.visible = true
	_auto_clock = 0.0
	_refresh_zoom()


func close_zoom() -> void:
	if _zoom != null:
		_zoom.visible = false


func _close_zoom() -> void:
	close_zoom()


func _refresh_zoom() -> void:
	if _zoom == null or _zoom_photo == null:
		return
	# ⚠ 读 _current_tex，不要读 _rects[_front].texture：_front 要等淡入结束才翻页，
	#   淡入期间那一格还是**上一张**，大图就会赖着不换（探针抓到的那个 bug）。
	var tex: Texture2D = _current_tex
	if tex == null:
		return
	var view: Vector2 = _zoom.size
	var max_w: float = maxf(320.0, minf(view.x - ZOOM_SIDE_MARGIN, 1180.0))
	var scale: float = minf(max_w / float(tex.get_width()), ZOOM_PHOTO_H / float(tex.get_height()))
	var w := float(tex.get_width()) * scale
	var h := float(tex.get_height()) * scale
	var pos := Vector2(roundf((view.x - w) * 0.5), ZOOM_TOP)
	_zoom_photo.texture = tex
	_zoom_photo.position = pos
	_zoom_photo.size = Vector2(w, h)
	_zoom_panel.position = pos - Vector2(PANEL_PAD, PANEL_PAD)
	_zoom_panel.size = Vector2(w, h) + Vector2(PANEL_PAD, PANEL_PAD) * 2.0
	_zoom_prev.position = Vector2(maxf(16.0, pos.x - ZOOM_ARROW.x - 12.0), pos.y + (h - ZOOM_ARROW.y) * 0.5)
	_zoom_next.position = Vector2(minf(view.x - ZOOM_ARROW.x - 16.0, pos.x + w + 12.0), pos.y + (h - ZOOM_ARROW.y) * 0.5)


func _on_zoom_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_close_zoom()
		(_zoom as Control).accept_event()


## 放大层开着时：ESC 关闭、左右方向键换片。挂在 _input 上是为了抢在
## main.gd 的 _unhandled_input（ESC = 暂停）之前把按键吃掉。
func _input(event: InputEvent) -> void:
	if _zoom == null or not _zoom.visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		_close_zoom()
	elif key == KEY_LEFT:
		_step(-1)
	elif key == KEY_RIGHT:
		_step(1)
	else:
		return
	get_viewport().set_input_as_handled()


# ==================== 小工具 ====================

func _reduced_motion() -> bool:
	return reduced_motion_check.is_valid() and bool(reduced_motion_check.call())


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(12, int(round(size / 12.0)) * 12))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 拉满整宽、只给纵向位置（放大页的文字与链接行都按这个对齐）
func _full_width(l: Control, y: float, height: float) -> void:
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_left = 0.0
	l.offset_right = 0.0
	l.offset_top = y
	l.offset_bottom = y + height


func _flat_box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(0)
	s.set_border_width_all(0)
	return s


func _edge_box(color: Color, width: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false                  # 只画框，不挡照片
	s.bg_color = Color(0, 0, 0, 0)
	s.set_border_width_all(int(width))
	s.border_color = color
	s.set_corner_radius_all(0)
	return s


func _arrow_button(text: String, cb: Callable, box: Vector2 = ARROW) -> Button:
	var b := Button.new()
	b.text = text
	b.size = box
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color(VisualTheme.PAPER, 0.92))
	b.add_theme_color_override("font_hover_color", VisualTheme.GOLD)
	b.add_theme_color_override("font_pressed_color", VisualTheme.GOLD)
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.08, 0.9))
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_stylebox_override("normal", _arrow_box(0.42, Color(VisualTheme.PAPER, 0.5)))
	b.add_theme_stylebox_override("hover", _arrow_box(0.68, VisualTheme.GOLD))
	b.add_theme_stylebox_override("pressed", _arrow_box(0.82, VisualTheme.GOLD))
	b.add_theme_stylebox_override("focus", _arrow_box(0.42, VisualTheme.MINT))
	b.pressed.connect(cb)
	return b


func _arrow_box(alpha: float, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.06, 0.08, alpha)
	s.set_border_width_all(2)
	s.border_color = edge
	s.set_corner_radius_all(0)
	s.set_content_margin_all(0.0)
	return s


func _styled_button(text: String, size: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", maxi(12, int(round(size / 12.0)) * 12))
	VisualTheme.style_button(b, false)
	b.mouse_entered.connect(func() -> void: VisualTheme.button_feedback(b, true))
	b.mouse_exited.connect(func() -> void: VisualTheme.button_feedback(b, false))
	b.pressed.connect(cb)
	return b
