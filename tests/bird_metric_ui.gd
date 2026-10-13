extends Node
var checks := 0
var failures := 0
var game: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func shot(name: String) -> void:
	var folder := OS.get_environment("POYANG_SCREENSHOT_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.5)
	if game._intro_playing: game._finish_intro()
	game._on_title_start()
	game._on_difficulty_pick(0)
	game.seed_input.text = "20261012"
	game._on_start_pressed()
	await settle(0.8)
	for i in 40:
		if game.popup_root.visible: game._on_popup_button()
		if game._current_phase == "allocate" and not game.popup_root.visible: break
		await settle(0.06)
	game.set_process(false)
	game.popup_root.hide()
	game.crisis_root.hide()
	game.right_panel.show()
	game._update_hud()
	await settle(0.4)
	var state := GameState.serialize().duplicate(true)
	var data: Dictionary = game.metric_bars.birds
	var renderer: Control = data.bird_segments
	var bar: ProgressBar = data.bar
	check(data.preview == renderer and bar.get_theme_stylebox("fill") is StyleBoxEmpty, "Birds have no independent full-white preview or fill layer")
	check(renderer._migrant_fill.bg_color.a < 0.5 and renderer._resident_fill.bg_color == Color.WHITE, "Residents and static migrants remain visually distinct")
	var redline: ColorRect = data.line
	var fixed_anchor := redline.anchor_left
	for values in [[45, 16, 48, 28], [45, 16, 48, 8], [45, 16, 40, 21], [60, 40, 60, 0], [45, 0, 50, 0], [0, 40, 0, 20], [0, 0, 0, 0], [30, 5, 40, 10], [45, 16, 40, 30], [60, 40, 0, 0], [0, 0, 60, 40], [45, 16, 45, 15], [45, 16, 45, 17], [45, 0, 0, 0]]:
		renderer.configure(values[0], values[1])
		bar.value = values[0] + values[1]
		renderer._swap_progress = 1.0
		renderer.configure_forecast(values[2], values[3])
		var live: Rect2 = renderer.resident_rect()
		var visiting: Rect2 = renderer.migrant_rect()
		check(is_equal_approx(live.end.x, visiting.position.x), "Resident and migrant geometry joins without an extra live segment")
		check(is_equal_approx(visiting.end.x, renderer.fill_end(minf(renderer.current, renderer.predicted))), "Two population segments end where the separate change segment begins")
		var rect: Rect2 = renderer.forecast_rect()
		check(rect.position.y == 2 and is_equal_approx(rect.size.y, bar.size.y - 4), "Net changes use the full inner bar thickness")
		check(is_equal_approx(rect.position.x, renderer.fill_end(minf(renderer.current, renderer.predicted))) and is_equal_approx(rect.end.x, renderer.fill_end(maxf(renderer.current, renderer.predicted))), "The tail spans exactly the current and projected total endpoints")
		if renderer.forecast_delta() != 0:
			check(renderer.forecast_color() == (Color.WHITE if renderer.forecast_delta() > 0 else renderer.LOSS_COLOR), "Net gain is white and net loss red")
		if renderer.forecast_delta() < 0:
			check(rect.position.x + 0.001 >= maxf(live.end.x, visiting.end.x), "Red net loss starts after both projected populations (with subpixel tolerance)")
		check(rect.position.x + 0.001 >= maxf(live.end.x, visiting.end.x), "Both gain and loss are separate tails after the populations")
		check(renderer.shown_population() == (Vector2(values[0], values[1]) if renderer.forecast_delta() > 0 else Vector2(values[2], values[3])), "Increase retains current populations and decrease shows survivors")
		renderer.queue_redraw()
		await RenderingServer.frame_post_draw
		var last_style: StyleBoxFlat = renderer._change_fill if rect.has_area() else (renderer._migrant_fill if visiting.has_area() else renderer._resident_fill)
		check(last_style.corner_radius_top_right == 0 and last_style.corner_radius_bottom_right == 0, "The last nonempty segment matches the square pixel style")
		if rect.has_area():
			check(renderer._migrant_fill.corner_radius_top_right == 0 and renderer._resident_fill.corner_radius_top_right == 0, "Population joins before a change segment are straight and continuous")
		var before: Rect2 = renderer.migrant_rect()
		for phase in [0.1, 0.4, 0.8]:
			game._metric_preview_clock = phase
			renderer._process(0.0)
			check(renderer.migrant_rect() == before, "Pulse phase never changes the projected migrant split or endpoint")
			check(is_equal_approx(renderer._migrant_fill.bg_color.a, renderer.MIGRANT_ALPHA), "Migrant transparency is static and independent of change flashing")
		check(redline.anchor_left == fixed_anchor and redline.anchor_right == fixed_anchor, "Forecasts never move the ecological redline")
	# When changes cancel, show only the new population split, without a tail.
	renderer.configure(45, 16)
	bar.value = 61
	renderer._swap_progress = 1.0
	renderer.configure_forecast(49, 12)
	check(renderer.forecast_available and renderer.current == renderer.predicted, "Equal totals do not hide opposite population changes")
	check(not renderer.forecast_rect().has_area(), "Cancelling changes draw no flashing red or white tail")
	check(is_equal_approx(renderer.resident_rect().end.x, renderer.fill_end(49)) and is_equal_approx(renderer.migrant_rect().end.x, renderer.fill_end(61)), "Only the split changes while the total endpoint remains fixed")
	for total in range(101):
		bar.value = total
		var pop: Vector2 = renderer.display_population()
		check(is_equal_approx(pop.x + pop.y, float(total)) and pop.x >= 0 and pop.x <= 60 and pop.y >= 0 and pop.y <= 40, "Animated composition is additive and bounded at every displayed value")
	bar.value = 61
	game.wetland.reduced_motion = true
	check(renderer.blink_alpha() == 0.75, "Reduced motion keeps a steady forecast")
	game.wetland.reduced_motion = false
	renderer.clear_forecast()
	check(not renderer.forecast_available and renderer.predicted == renderer.current, "Leaving allocation clears changes without hiding current populations")
	check(GameState.serialize() == state, "Rendering and forecasts never alter gameplay state")
	# Capture the original reported state and all problematic pulse phases.
	bar.value = 61
	renderer.configure(45, 16)
	renderer._swap_progress = 1.0
	data.val.text = "61"
	for fixture in [["gain", 48, 28], ["loss", 48, 8], ["exchange", 49, 12], ["tiny-loss", 45, 15], ["tiny-gain", 45, 17], ["resident-only-loss", 40, 0]]:
		renderer.configure_forecast(fixture[1], fixture[2])
		data.val.text = "61 → %d" % renderer.predicted if renderer.predicted != 61 else "61"
		var shown: Vector2 = renderer.shown_population()
		data.reference_label.text = "留湖 %d · 迁徙 %d · 生态红线 %d" % [int(shown.x), int(shown.y), GameState.failure_threshold_for("birds")]
		data.val.add_theme_color_override("font_color", renderer.LOSS_COLOR if renderer.predicted < renderer.current else Color.WHITE)
		for phase in [0.1, 0.4, 0.8]:
			game._metric_preview_clock = phase
			renderer.queue_redraw()
			await settle(0.04)
			await shot("bird-" + fixture[0] + "-" + str(phase))
	get_window().size = Vector2i(960, 540)
	await settle(0.3)
	check(is_equal_approx(renderer.size.y, bar.size.y) and renderer.size.x > 80, "Small window uses one bar with no extra forecast tracks")
	await shot("bird-small")
	await check_skin_layout()
	print("BIRD_METRIC_UI checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func check_skin_layout() -> void:
	var water: Dictionary = game.metric_bars.water_level
	var bird: Dictionary = game.metric_bars.birds
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		get_window().size = dimensions
		await settle(0.2)
		for metric in game.metric_bars:
			var bar: ProgressBar = game.metric_bars[metric].bar
			check(bar.size == bird.bar.size, "All six bars have the same width and thickness")
			var track: StyleBoxTexture = bar.get_theme_stylebox("background")
			check(track.texture == bird.bar.get_theme_stylebox("background").texture, "Birds share the other five pixel track frames")
			bar.value = 100
			if metric != "birds": game.metric_bars[metric].preview.hide()
			game.metric_bars[metric].ripple.hide()
		water.preview.hide()
		water.ripple.hide()
		water.bar.value = 100
		bird.bar.value = 100
		bird.bird_segments.configure(60, 40)
		bird.bird_segments.clear_forecast()
		bird.bird_segments._swap_progress = 1.0
		for marker in [water.line, water.high_line]:
			var bar_rect: Rect2 = water.bar.get_global_rect()
			var mark_rect: Rect2 = marker.get_global_rect()
			check(is_equal_approx(bar_rect.position.y - mark_rect.position.y, 1.0) and is_equal_approx(mark_rect.end.y - bar_rect.end.y, 1.0), "Water reference protrudes equally above and below")
			check(marker.z_index > water.preview.z_index and marker.color.a < 0.6, "Water references overlay the bar translucently")
		await RenderingServer.frame_post_draw
		if DisplayServer.get_name() != "headless":
			var image := get_viewport().get_texture().get_image()
			var rect: Rect2 = water.bar.get_global_rect()
			var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
			var expected: Color = game.METRIC_COLORS.water_level
			for x in range(int((rect.position.x + 3) * scale.x), int((rect.end.x - 3) * scale.x)):
				var pixel := image.get_pixel(x, int(rect.get_center().y * scale.y))
				var target := expected
				for marker in [water.line, water.high_line]:
					if marker.get_global_rect().has_point(Vector2((float(x) + 0.5) / scale.x, rect.get_center().y)):
						target = expected.lerp(Color(marker.color.r, marker.color.g, marker.color.b, 1.0), marker.color.a)
				check(absf(pixel.r - target.r) < 0.015 and absf(pixel.g - target.g) < 0.015 and absf(pixel.b - target.b) < 0.015, "Blue water fill stays continuous through both green references")
		await shot("pixel-monitor-" + str(dimensions.x))
		await check_threshold_widths()
		await check_water_previews(str(dimensions.x))
		game._pause_game()
		game._on_pause_settings()
		await check_volume_layout(game.pause_volume_slider, game.pause_volume_label, "pause-" + str(dimensions.x))
		game._resume_game()
		game.menu_root.show()
		game._show_settings_panel()
		await check_volume_layout(game.audio_volume_slider, game.audio_volume_label, "menu-" + str(dimensions.x))
		game.menu_root.hide()

func check_threshold_widths() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var widths: Array[int] = []
	for metric in game.metric_bars:
		if metric == "water_level": continue
		var bar: ProgressBar = game.metric_bars[metric].bar
		var y := int(bar.get_global_rect().get_center().y * scale.y)
		var line: ColorRect = game.metric_bars[metric].line
		var x := int(line.get_global_rect().get_center().x * scale.x)
		var pixels := 0
		for dx in range(-4, 5):
			var color := image.get_pixel(x + dx, y)
			if color.r > 0.9 and color.g < 0.3 and color.b < 0.4: pixels += 1
		widths.append(pixels)
	check(widths.all(func(width): return width > 0 and width == widths[0]), "All five ecological redlines have identical rendered pixel widths: " + str(widths))

func check_water_previews(suffix: String) -> void:
	var water: Dictionary = game.metric_bars.water_level
	for marker in [water.line, water.high_line]: marker.hide()
	var overlay: Control = water.preview
	var bar: ProgressBar = water.bar
	bar.value = 0
	overlay.hide()
	await RenderingServer.frame_post_draw
	var baseline := get_viewport().get_texture().get_image()
	for values in [[18, 30], [48, 62], [62, 74], [75, 90], [50, 51], [70, 55], [62, 48], [50, 49], [0, 100], [100, 0]]:
		bar.value = values[0]
		overlay.configure(values[0], values[1])
		for phase in [0.1, 0.4, 0.8]:
			game._metric_preview_clock = phase
			await settle(0.04)
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var rect := bar.get_global_rect()
			var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
			var segment: Rect2 = overlay.segment_rect()
			var split := roundi((rect.position.x + segment.position.x) * scale.x)
			var end := int((rect.position.x + segment.end.x) * scale.x)
			var y := int(rect.get_center().y * scale.y)
			var tint: Color = game.METRIC_COLORS.water_level if values[1] > values[0] else overlay.LOSS_COLOR
			var continuous := true
			for x in range(int((rect.position.x + 3) * scale.x), end):
				var tail := baseline.get_pixel(x, y).lerp(tint, overlay.blink_alpha())
				var expected: Color = game.METRIC_COLORS.water_level if x < split else tail
				var pixel := image.get_pixel(x, y)
				# Screen clipping can sample the adjacent grain texel at 75% scale.
				# At the split, either adjoining segment may own the boundary pixel.
				var matches := absf(pixel.r - expected.r) <= 0.10 and absf(pixel.g - expected.g) <= 0.10 and absf(pixel.b - expected.b) <= 0.10
				if not matches and absi(x - split) <= 1:
					var blue: Color = game.METRIC_COLORS.water_level
					matches = (absf(pixel.r - blue.r) <= 0.01 and absf(pixel.g - blue.g) <= 0.01 and absf(pixel.b - blue.b) <= 0.01) or (absf(pixel.r - tail.r) <= 0.10 and absf(pixel.g - tail.g) <= 0.10 and absf(pixel.b - tail.b) <= 0.10)
				if not matches: continuous = false
			check(continuous, "Water gain/loss preview remains seamless for %s at phase %.1f and width %s" % [str(values), phase, suffix])
		if values in [[18, 30], [48, 62], [70, 55]]: await shot("water-preview-" + suffix + "-" + str(values[0]) + "-" + str(values[1]))

	for marker in [water.line, water.high_line]: marker.show()

func check_volume_layout(slider: HSlider, label: Label, suffix: String) -> void:
	await settle(0.2)
	var initial := slider.get_global_rect()
	var settings: Control = game.pause_settings_panel if slider == game.pause_volume_slider else game.menu_settings_panel
	check(absf(initial.get_center().x - settings.get_global_rect().get_center().x) < 1.0, "Volume slider is centered in its settings panel")
	var duplicated := false
	for node in settings.find_children("*", "Label", true, false):
		if node.text == "音量": duplicated = true
	check(not duplicated, "Settings remove the redundant white volume label")
	for value in [0, 9, 10, 99, 100]:
		slider.value = value
		await settle(0.04)
		check(slider.get_global_rect() == initial, "Volume text length never changes the slider's bounds")
		check(label.get_global_rect().position.y >= initial.end.y, "Volume percentage is below the slider")
		check(label.text == "音量：%d%%" % value, "Volume percentage updates through one, two and three digits")
		check(is_equal_approx(game.bgm_volume, value / 100.0), "Volume still changes the audio setting")
		check(game.audio_volume_label.text == game.pause_volume_label.text, "Both settings panels stay synchronized")
		if value in [9, 100]: await shot("volume-" + suffix + "-" + str(value))
