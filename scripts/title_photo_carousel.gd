extends Control
## 开始页观察相册：相纸叠放、跟手拖动、原图查看。
##
## 需求（2026-10-14）：主标题右边放几张照片，可左右切换；点击图片放大看，
## 放大后要标出处（鄱阳湖国家湿地公园官网「摄影佳作」栏目）。
##
## 三条改之前先读的约束：
## 1. 纯展示层：不读也不写任何游戏状态（存档 / 天赋 / 成就都不碰）。
## 2. 照片清单写死在 PHOTOS 里，**不扫目录** —— 导出包里 res:// 只有导入产物
##    （.ctex），源 jpg 不在包内，DirAccess 扫描在发行版上会扫到 0 张。
## 3. 放大层挂在**父节点**（menu_root）上，不是挂在相册的小方块里 ——
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
const BLOCK := Vector2(380.0, 294.0)
const FRAME := Vector2(356.0, 236.0)
const PANEL_PAD := 12.0                   # UiSkin.panel() 的内容边距
const TEXT_X := 12.0                      # 说明文字与照片框左右对齐
const TEXT_W := 356.0
const ARROW := Vector2(32.0, 48.0)
const CAPTION_Y := 258.0
const AUTO_SEC := 10.0
const MANUAL_PAUSE_SEC := 15.0
const SLIDE_SEC := 0.30
const DRAG_SLOP := 8.0
const FLICK_SPEED := 600.0
const PAPER := Color("f6eedb")
const INK := Color("4c4030")

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
var _front := 0
var _current_tex: Texture2D
var _fade := 1.0
var _hover := false
var _rects: Array[TextureRect] = []
var _sheets: Array[Control] = []
var _sheet_captions: Array[Label] = []
var _textures: Dictionary = {}
var _frame_box: Control
var _strip: Control
var _caption: Label
var _zoom: Control
var _zoom_panel: Panel
var _zoom_photo: TextureRect
var _zoom_prev: Button
var _zoom_next: Button
var _zoom_link: LinkButton
var _catcher: Control
var _departing := -1
var _turn_position := Vector2.ZERO
var _turn_rotation := 0.0
var _arrival_position := Vector2.ZERO
var _arrival_alpha := 1.0
var _arrival_rotation := 0.0
var _turn_direction := 1
var _turn_alpha := 1.0
var _turn_target := Vector2.ZERO
var _returning := false
var _return_position := Vector2.ZERO
var _return_rotation := 0.0
var _return_alpha := 1.0
var _preview_return_position := Vector2.ZERO
var _preview_return_alpha := 0.0
var _preview_return_target := Vector2.ZERO
var _drag_direction := 1
var _gesture_age := 0.0
var _drag_x := 0.0
var _pressed := false
var _dragging := false
var _press_point := Vector2.ZERO
var _press_pose := Vector2.ZERO
var _last_point := Vector2.ZERO
var _last_sample_ms := 0
var _velocity := 0.0
var _next_auto_ms := 0

func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	offset_right = -(FRAME_MARGIN_RIGHT - PANEL_PAD)
	offset_left = offset_right - BLOCK.x
	offset_top = FRAME_MARGIN_TOP - PANEL_PAD
	offset_bottom = offset_top + BLOCK.y
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_strip()
	_build_zoom()
	_begin(0, 0, true)
	_next_auto_ms = Time.get_ticks_msec() + int(AUTO_SEC * 1000.0)
	visibility_changed.connect(_visibility_reset)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_step_fade(delta)
	_hover = get_global_rect().has_point(get_global_mouse_position())
	var now := Time.get_ticks_msec()
	_tick_auto(now, _hover)

func _tick_auto(now: int, hovering: bool) -> void:
	if hovering:
		_next_auto_ms = maxi(_next_auto_ms, now + 3000)
	if _pressed or hovering or (_zoom and _zoom.visible) or _reduced_motion(): return
	if now >= _next_auto_ms: _step(1, false)

func _paper_box(color: Color, shadow: bool = true) -> StyleBoxFlat:
	var style := _flat_box(color)
	style.set_border_width_all(1)
	style.border_color = Color("c6b99b")
	if shadow:
		style.shadow_color = Color(0.12, 0.09, 0.05, 0.28)
		style.shadow_size = 5
		style.shadow_offset = Vector2(2, 4)
	return style

func _paper_layer(color: Color) -> Panel:
	var sheet := Panel.new()
	sheet.size = BLOCK
	sheet.pivot_offset = BLOCK * 0.5
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_theme_stylebox_override("panel", _paper_box(color))
	return sheet

func _paper_label(text: String, color: Color) -> Label:
	var label := _label(text, 12, color)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	return label

func _build_strip() -> void:
	_strip = Control.new()
	_strip.name = "AlbumContents"
	_strip.size = BLOCK
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	# Two quiet backing papers connect the real photographs to the game's paper cards.
	for i in 2:
		var backing := _paper_layer(Color("ded3bb") if i == 0 else Color("eee4ce"))
		backing.position = Vector2(-4 if i == 0 else 6, 9 if i == 0 else 5)
		backing.rotation = deg_to_rad(-2.2 if i == 0 else 1.7)
		_strip.add_child(backing)
	_frame_box = Control.new()
	_frame_box.name = "PhotoFrame"
	_frame_box.size = BLOCK
	_frame_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(_frame_box)
	for i in 2:
		var sheet := _paper_layer(PAPER)
		sheet.visible = i == 0
		_frame_box.add_child(sheet)
		_sheets.append(sheet)
		var crop := Control.new()
		crop.position = Vector2(PANEL_PAD, PANEL_PAD)
		crop.size = FRAME
		crop.clip_contents = true
		crop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(crop)
		var photo := TextureRect.new()
		photo.size = FRAME
		photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crop.add_child(photo)
		_rects.append(photo)
		var rim := Panel.new()
		rim.size = FRAME
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rim.add_theme_stylebox_override("panel", _edge_box(Color("b7a78c"), 1))
		crop.add_child(rim)
		var title := _paper_label("鄱阳湖 · 观察相册", INK)
		title.position = Vector2(TEXT_X, CAPTION_Y)
		sheet.add_child(title)
		var caption := _paper_label("", INK)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		caption.position = Vector2(TEXT_X, CAPTION_Y)
		caption.size = Vector2(TEXT_W, 18)
		sheet.add_child(caption)
		_sheet_captions.append(caption)
		var hint := _paper_label("拖动翻看 · 点击放大", Color("8c7b62"))
		hint.position = Vector2(TEXT_X, 276)
		hint.size = Vector2(TEXT_W, 16)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sheet.add_child(hint)
	_catcher = Control.new()
	_catcher.name = "PhotoCatcher"
	_catcher.position = Vector2(PANEL_PAD, PANEL_PAD)
	_catcher.size = FRAME
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.z_index = 4
	_catcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_catcher.focus_mode = Control.FOCUS_ALL
	_catcher.gui_input.connect(_on_catcher_input)
	_strip.add_child(_catcher)

func _texture(index: int) -> Texture2D:
	index = posmod(index, PHOTOS.size())
	if not _textures.has(index): _textures[index] = load(PHOTOS[index]) as Texture2D
	return _textures[index]

func _sheet_text(index: int) -> String:
	return "%02d / %02d" % [index + 1, PHOTOS.size()]

func _manual_activity() -> void:
	_next_auto_ms = Time.get_ticks_msec() + int(MANUAL_PAUSE_SEC * 1000.0)

func _local_point(point: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * point

func _begin_pointer(point: Vector2, now: int) -> void:
	_manual_activity()
	# _index already belongs to the committed arrival. Promote it fully before
	# either paper buffer is reused by another gesture, especially a previous swipe.
	if _departing >= 0 and not _returning:
		_settle_fade()
	_pressed = true
	_dragging = false
	_returning = false
	_fade = 1.0
	var preview := 1 - _front
	_sheets[preview].visible = false
	_sheets[preview].position = Vector2.ZERO
	_sheets[preview].rotation = 0.0
	_sheets[preview].scale = Vector2.ONE
	_sheets[preview].modulate.a = 1.0
	_sheets[preview].z_index = 1
	_departing = -1
	_press_point = _local_point(point)
	_last_point = _press_point
	_press_pose = Vector2(clampf(_sheets[_front].position.x, -FRAME.x, 0.0), 0.0)
	_sheets[_front].position = _press_pose
	_sheets[_front].modulate.a = 1.0 + _press_pose.x / FRAME.x
	_sheets[_front].rotation = 0.0
	_sheets[_front].scale = Vector2.ONE
	_gesture_age = 0.0
	_drag_x = 0.0
	_last_sample_ms = now
	_velocity = 0.0
	_catcher.grab_focus()

func _move_pointer(point: Vector2, now: int) -> void:
	if not _pressed: return
	var local := _local_point(point)
	var movement := local - _press_point
	if not _dragging and movement.length() < DRAG_SLOP: return
	_dragging = true
	var dt := maxf(0.001, float(now - _last_sample_ms) / 1000.0)
	_velocity = lerpf(_velocity if now - _last_sample_ms < 100 else 0.0, (local.x - _last_point.x) / dt, 0.65)
	_last_point = local
	_last_sample_ms = now
	_drag_direction = 1 if movement.x <= 0 else -1
	_drag_x = movement.x
	var preview := 1 - _front
	_rects[preview].texture = _texture(_index + _drag_direction)
	_sheet_captions[preview].text = _sheet_text(posmod(_index + _drag_direction, PHOTOS.size()))
	_sheets[preview].visible = true
	_apply_held_pose()

func _apply_held_pose() -> void:
	# Finish the inherited return while held; never add old offsets indefinitely.
	var residual := Vector2.ZERO if _reduced_motion() else _press_pose * pow(1.0 - clampf(_gesture_age / SLIDE_SEC, 0.0, 1.0), 3)
	_sheets[_front].position = residual
	_sheets[_front].modulate.a = 1.0 + residual.x / FRAME.x
	_sheets[_front].rotation = 0.0
	_sheets[_front].z_index = 2
	if not _dragging: return
	var preview := 1 - _front
	_sheets[preview].rotation = 0.0
	var distance := clampf(absf(_drag_x), 0.0, FRAME.x)
	var progress := distance / FRAME.x
	if _drag_direction < 0:
		# Previous photograph comes back from the left; the current paper stays put.
		_press_pose = Vector2.ZERO
		_sheets[_front].position = Vector2.ZERO
		_sheets[_front].modulate.a = 1.0
		_sheets[preview].z_index = 3
		_sheets[preview].position = Vector2(-FRAME.x + distance, 0)
		_sheets[preview].modulate.a = progress
	else:
		# Next photograph already lies beneath. The current paper leaves to the left.
		_sheets[preview].z_index = 1
		_sheets[preview].position = Vector2.ZERO
		_sheets[preview].modulate.a = 1.0
		_sheets[_front].position = Vector2(clampf(residual.x - distance, -FRAME.x, 0.0), 0.0)
		_sheets[_front].modulate.a = 1.0 + _sheets[_front].position.x / FRAME.x
	if _reduced_motion():
		_sheets[_front].position = Vector2.ZERO
		_sheets[_front].modulate.a = 1.0
		_sheets[preview].visible = false


func _end_pointer(point: Vector2, now: int) -> void:
	if not _pressed: return
	_pressed = false
	_manual_activity()
	if not _dragging:
		if _catcher.get_global_rect().has_point(point): _open_zoom()
		else: _return_home()
		return
	_dragging = false
	var dx := (_local_point(point) - _press_point).x
	var speed := _velocity if now - _last_sample_ms <= 100 else 0.0
	if absf(dx) >= FRAME.x * 0.20 or (absf(speed) >= FLICK_SPEED and absf(dx) >= 14.0):
		_step(1 if (speed if absf(speed) >= FLICK_SPEED else dx) < 0 else -1, true, true)
	else: _return_home()

func _return_home() -> void:
	if _reduced_motion():
		_settle_fade()
		return
	_returning = true
	_fade = 0.0
	_return_position = _sheets[_front].position
	_return_rotation = _sheets[_front].rotation
	_return_alpha = _sheets[_front].modulate.a
	_preview_return_position = _sheets[1 - _front].position
	_preview_return_alpha = _sheets[1 - _front].modulate.a
	_preview_return_target = Vector2(-FRAME.x, 0) if _drag_direction < 0 else Vector2.ZERO

func _on_catcher_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin_pointer(event.global_position, Time.get_ticks_msec())
			_catcher.accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			_catcher.accept_event()
	elif event is InputEventPanGesture:
		_catcher.accept_event()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_SPACE]:
		_open_zoom()
		_catcher.accept_event()

func _step(dir: int, manual: bool = true, from_drag: bool = false) -> void:
	if PHOTOS.size() <= 1: return
	_pressed = false
	_dragging = false
	_returning = false
	if manual: _manual_activity()
	else: _next_auto_ms = Time.get_ticks_msec() + int(AUTO_SEC * 1000.0)
	_begin(posmod(_index + dir, PHOTOS.size()), dir, _reduced_motion(), from_drag and dir == _drag_direction)

func _begin(index: int, dir: int, instant: bool, from_drag: bool = false) -> void:
	if PHOTOS.is_empty(): return
	var old := _front
	var incoming := 1 - old
	_index = posmod(index, PHOTOS.size())
	_current_tex = _texture(_index)
	_rects[incoming].texture = _current_tex
	_sheet_captions[incoming].text = _sheet_text(_index)
	_sheets[incoming].visible = true
	_turn_direction = dir
	if not from_drag:
		_sheets[incoming].position = Vector2(-FRAME.x, 0) if dir < 0 else Vector2.ZERO
		_sheets[incoming].modulate.a = 0.0 if dir < 0 else 1.0
	_sheets[incoming].rotation = 0.0
	_sheets[incoming].z_index = 3 if dir < 0 else 1
	_arrival_position = _sheets[incoming].position
	_arrival_alpha = _sheets[incoming].modulate.a
	_arrival_rotation = 0.0
	_turn_position = _sheets[old].position
	_turn_rotation = _sheets[old].rotation
	_turn_alpha = _sheets[old].modulate.a
	_turn_target = _turn_position if dir < 0 else Vector2(-FRAME.x, 0)
	_sheets[old].z_index = 2
	_front = incoming
	_departing = old
	_fade = 0.0
	_refresh_caption()
	if instant: _settle_fade()
	if _zoom and _zoom.visible: _refresh_zoom()

func _settle_fade() -> void:
	for i in _sheets.size():
		_sheets[i].position = Vector2.ZERO
		_sheets[i].rotation = 0.0
		_sheets[i].scale = Vector2.ONE
		_sheets[i].modulate.a = 1.0
		_sheets[i].z_index = 2 if i == _front else 1
		_sheets[i].visible = i == _front
	_departing = -1
	_returning = false
	_fade = 1.0

func _step_fade(delta: float) -> void:
	if _pressed:
		_gesture_age = minf(SLIDE_SEC, _gesture_age + delta)
		_apply_held_pose()
		return
	if _fade >= 1.0: return
	if _reduced_motion():
		_settle_fade()
		return
	_fade = minf(1.0, _fade + delta / SLIDE_SEC)
	var ease := 1.0 - pow(1.0 - _fade, 3)
	if _returning:
		_sheets[_front].position = _return_position * (1.0 - ease)
		_sheets[_front].rotation = _return_rotation * (1.0 - ease)
		_sheets[_front].modulate.a = lerpf(_return_alpha, 1.0, ease)
		var preview := 1 - _front
		_sheets[preview].position = _preview_return_position.lerp(_preview_return_target, ease)
		_sheets[preview].modulate.a = _preview_return_alpha * (1.0 - ease) if _drag_direction < 0 else 1.0
	else:
		_sheets[_front].position = _arrival_position * (1.0 - ease)
		_sheets[_front].rotation = _arrival_rotation * (1.0 - ease)
		_sheets[_front].modulate.a = lerpf(_arrival_alpha, 1.0, ease)
		if _departing >= 0:
			_sheets[_departing].position = _turn_position.lerp(_turn_target, ease)
			_sheets[_departing].rotation = _turn_rotation * (1.0 - ease)
			_sheets[_departing].modulate.a = _turn_alpha if _turn_direction < 0 else _turn_alpha * (1.0 - ease)
	if _fade >= 1.0: _settle_fade()

func _refresh_caption() -> void:
	_caption = _sheet_captions[_front]
	_caption.text = _sheet_text(_index)

func _visibility_reset() -> void:
	_pressed = false
	_dragging = false
	_settle_fade()
	_next_auto_ms = Time.get_ticks_msec() + int(AUTO_SEC * 1000.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _pressed:
		_pressed = false
		_dragging = false
		_return_home()


# ==================== 放大层 ====================

func _build_zoom() -> void:
	var host := get_parent()
	if host == null:
		return
	var overlay := Control.new()
	overlay.name = "PhotoZoom"
	overlay.z_index = 10
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP     # 模态：盖住底下的标题页
	overlay.visible = false
	# 挂到 menu_root 上而不是自己的子树里 —— 这里才是「全屏」坐标系
	host.add_child.call_deferred(overlay)
	_zoom = overlay
	overlay.resized.connect(_refresh_zoom)

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
	_pressed = false
	_dragging = false
	_settle_fade()
	_strip.visible = false
	_zoom.visible = true
	_manual_activity()
	_refresh_zoom()


func close_zoom() -> void:
	_manual_activity()
	if _zoom != null:
		_zoom.visible = false
	if _strip != null:
		_strip.visible = true


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
	# Navigation belongs to the fixed viewing area, not the current photograph.
	var navigation_y := ZOOM_TOP + (ZOOM_PHOTO_H - ZOOM_ARROW.y) * 0.5
	_zoom_prev.position = Vector2(maxf(16.0, (view.x - max_w) * 0.5 - ZOOM_ARROW.x - 16.0), navigation_y)
	_zoom_next.position = Vector2(minf(view.x - ZOOM_ARROW.x - 16.0, (view.x + max_w) * 0.5 + 16.0), navigation_y)


func _on_zoom_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_close_zoom()
		(_zoom as Control).accept_event()


## 放大层开着时：ESC 关闭、左右方向键换片。挂在 _input 上是为了抢在
## main.gd 的 _unhandled_input（ESC = 暂停）之前把按键吃掉。
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if _pressed:
		if event is InputEventMouseMotion:
			_move_pointer(event.position, Time.get_ticks_msec())
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_pointer(event.position, Time.get_ticks_msec())
			get_viewport().set_input_as_handled()
			return
	if not event is InputEventKey or not event.pressed: return
	var key: Key = event.keycode
	if key == KEY_ESCAPE and _zoom and _zoom.visible:
		_close_zoom()
	elif key in [KEY_LEFT, KEY_RIGHT] and _zoom and _zoom.visible:
		if not event.echo: _step(-1 if key == KEY_LEFT else 1)
	else: return
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
