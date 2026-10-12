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
		check(last_style.corner_radius_top_right == 3 and last_style.corner_radius_bottom_right == 3, "The last nonempty segment always has a rounded right endpoint")
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
	print("BIRD_METRIC_UI checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
