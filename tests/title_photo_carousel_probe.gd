extends SceneTree
## 开始页照片条的确定性自检（不问鼠标 —— 真窗口里 PostMessage 注入点击本来就不稳）。
##
## 跑法（工程根目录下）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> \
##       --script res://tests/title_photo_carousel_probe.gd --quit-after 900
##
## 断言的是「逻辑与顺序」，不是屏幕坐标：headless 没有渲染器，窗口尺寸也不一样。
## 屏幕上的版式（面板位置、彩蛋留白）靠真窗口截图看，见 outputs/title-photos-20261014/。

const Carousel := preload("res://scripts/title_photo_carousel.gd")

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK   ", what)
	else:
		_fails += 1
		print("FAIL ", what)


func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var c: Control = Carousel.new()
	get_root().add_child(c)
	await process_frame
	c.visible = true

	var loaded := 0
	for p in Carousel.PHOTOS:
		if load(p) != null:
			loaded += 1
	_check(Carousel.PHOTOS.size() == 13, "清单里有 13 张（实际 %d）" % Carousel.PHOTOS.size())
	_check(loaded == 13, "13 张全部 load() 成功（实际 %d）" % loaded)
	_check(c._index == 0, "起始 index=0（实际 %d）" % c._index)
	_check(c._caption.text.contains("01 / 13"), "起始读数文字「%s」" % c._caption.text)

	# 换下一张：index 前进，前层纹理非空，动画落定
	c._step(1)
	_check(c._index == 1, "换下一张后 index=1（实际 %d）" % c._index)
	_check(c._caption.text.contains("02 / 13"), "读数变成「%s」" % c._caption.text)
	_check(c._rects[c._front].texture != null, "前层纹理非空")
	c._step_fade(0.4)
	_check(c._fade >= 1.0, "淡入动画已落定（_fade=%.2f）" % c._fade)

	# 放大层：大图跟当前那张一致，链接是出处的真地址
	# headless 里 _zoom 拿不到窗口尺寸（layout 是 0），直接喂设计分辨率来验版式算术
	c._zoom.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	c._zoom.size = Vector2(1280, 720)
	c._open_zoom()
	_check(c._zoom.visible, "放大层 visible")
	_check(c._zoom_photo.texture == c._current_tex, "大图 = 当前那张的纹理")
	_check(c._zoom_link.uri == Carousel.SOURCE_URL, "链接 uri = %s" % c._zoom_link.uri)
	_check(c._zoom_link.text == Carousel.SOURCE_URL, "链接文字就是地址本身")
	_check(c._zoom_panel.size.x > c._zoom_photo.size.x and c._zoom_panel.size.y > c._zoom_photo.size.y,
		"外框比大图大一圈（%s vs %s）" % [c._zoom_panel.size, c._zoom_photo.size])
	var aspect := float(c._zoom_photo.texture.get_width()) / float(c._zoom_photo.texture.get_height())
	var expect_w: float = minf(1280.0 - 200.0, 540.0 * aspect)
	_check(is_equal_approx(c._zoom_photo.size.y, 540.0) and is_equal_approx(c._zoom_photo.size.x, expect_w),
		"大图按原比例铺到 540 高：%s（期望 %.1f × 540）" % [c._zoom_photo.size, expect_w])
	_check(is_equal_approx(c._zoom_photo.position.x, roundf((1280.0 - expect_w) * 0.5)), "大图水平居中")
	_check(c._zoom_photo.position.y + c._zoom_photo.size.y <= c.ZOOM_HINT_Y,
		"大图底边（%.0f）没压到出处文字（%.0f）" % [c._zoom_photo.position.y + c._zoom_photo.size.y, c.ZOOM_HINT_Y])

	# 放大层里换片：大图跟着走
	var big_before: Texture2D = c._zoom_photo.texture
	c._step(-1)
	_check(c._index == 0, "放大层里换上一张 → index=0（实际 %d）" % c._index)
	_check(c._zoom_photo.texture != big_before, "大图跟着换了")
	_check(c._zoom_photo.texture == c._current_tex, "大图 = 换过之后的当前纹理")

	# ESC 关掉；close_zoom 幂等
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	c._input(esc)
	_check(not c._zoom.visible, "按 ESC 关掉放大层")
	c.close_zoom()
	_check(not c._zoom.visible, "close_zoom() 之后仍不可见")

	# 循环取模：从第 1 张往前一张应回到最后一张
	c._index = 0
	c._step(-1)
	_check(c._index == 12, "第 1 张往前 → 第 13 张（实际 index=%d）" % c._index)

	# 版式常量（改版式时这两个数要跟着 版本更新 doc 里的彩蛋留白一起动）
	_check(c.BLOCK.y < 328.0 and c.FRAME.y < 278.0,
		"面板块 %s / 照片框 %s" % [c.BLOCK, c.FRAME])
	_check(is_equal_approx(c.FRAME_MARGIN_TOP, 116.0), "照片框上缘留白 %.0f（让开苦力怕彩蛋）" % c.FRAME_MARGIN_TOP)

	print("title_photo_carousel_probe: %d failures" % _fails)
	c._zoom.queue_free()
	c.queue_free()
	await process_frame
	quit(0 if _fails == 0 else 1)
