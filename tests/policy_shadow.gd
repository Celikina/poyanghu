extends Node
var game: Node
var checks := 0
var failures := 0
var output := OS.get_environment("POYANG_SCREENSHOT_DIR")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
func shadow_check(card: Control, label: String) -> void:
	await RenderingServer.frame_post_draw
	var shadow: Node2D = card.get_meta("projected_shadow")
	check(shadow.points.size() > 4, label + " uses a rounded silhouette")
	var before: PackedVector2Array = shadow.points.duplicate()
	card.scale *= 0.7
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	check(shadow.points != before, label + " shadow tracks actual scale without a gyro update")
	card.scale /= 0.7
func detail_shadow_check(big: Control, label: String) -> void:
	game._step_card_gyro(big, Vector2.ZERO, 1.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shadow: Node2D = big.get_meta("projected_shadow")
	check(shadow.points.size() > 4 and big.get_meta("shadow_preserve_size", false), label + " retains a rounded footprint at enlarged size")
	var with_shadow := get_viewport().get_texture().get_image()
	shadow.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var without_shadow := get_viewport().get_texture().get_image()
	shadow.show()
	var rect := big.get_global_rect()
	var area := rect.grow(45.0).intersection(get_viewport().get_visible_rect())
	var scale := Vector2(with_shadow.get_size()) / get_viewport().get_visible_rect().size
	var visible_pixels := 0
	for y in range(int(area.position.y * scale.y), int(area.end.y * scale.y)):
		for x in range(int(area.position.x * scale.x), int(area.end.x * scale.x)):
			if rect.has_point(Vector2(x + 0.5, y + 0.5) / scale): continue
			var a := with_shadow.get_pixel(x, y)
			var b := without_shadow.get_pixel(x, y)
			if b.r + b.g + b.b - a.r - a.g - a.b > 0.03: visible_pixels += 1
	check(visible_pixels > 200, label + " shadow is visibly rendered beyond the enlarged card: " + str(visible_pixels))
	print(label, " VISIBLE_SHADOW_PIXELS: ", visible_pixels)
func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.5)
	if game._intro_playing: game._finish_intro()
	game._on_title_start()
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	game.seed_input.text = "20261013"
	game._on_start_pressed()
	for i in 24:
		if game.popup_root.visible: game._on_popup_button()
		await settle(0.1)
	game.set_process(false)
	check(Achievements.LIST.size() == 4 and Achievements.find("rigged").is_empty(), "Removed achievement has no game definition")
	var selector: Control = game.lever_handle
	for i in 3:
		game._lever_cooldown_ms = -10000
		game._update_lever_cooldown()
		selector.buttons[i].pressed.emit()
		await settle(0.25)
		check(game.play_tier == selector.TIERS[i] and selector.selected == i, "Clicking each box selects and stamps that tier")
		check(selector.page.texture == selector.PAGES[i] and selector.seal.texture == selector.SEALS[i], "Only the chosen seal is displayed")
		check(selector.seal.scale.is_equal_approx(Vector2.ONE), "Seal settles without changing parchment layout")
		await shot("policy-" + selector.TIERS[i])
	game._update_lever_cooldown()
	check(selector.buttons[0].disabled, "Policy cooldown disables stamping")
	game._lever_cooldown_ms = -10000
	game._update_lever_cooldown()
	check(not selector.buttons[0].disabled, "Policy cooldown releases stamping")
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		get_window().size = dimensions
		await settle(0.25)
		check(get_viewport().get_visible_rect().encloses(game.tier_lever.get_global_rect()), "Policy parchment fits the viewport")
		var water: Dictionary = game.metric_bars.water_level
		water.bar.value = 100
		water.preview.hide()
		water.ripple.hide()
		for marker in [water.line, water.high_line]:
			var bar_rect: Rect2 = water.bar.get_global_rect()
			var mark_rect: Rect2 = marker.get_global_rect()
			check(is_equal_approx(bar_rect.position.y - mark_rect.position.y, 1.0) and is_equal_approx(mark_rect.end.y - bar_rect.end.y, 1.0), "Water markers protrude symmetrically by one pixel")
			check(marker.z_index > water.preview.z_index and is_equal_approx(marker.color.a, 0.45), "Water markers overlay fill and forecast with 45 percent opacity")
		await shot("layout-" + str(dimensions.x))
	await shadow_check(game.card_infos[0].panel, "Hand")
	for kind in ["deck", "dispatch", "knowledge"]:
		var panel: PanelContainer
		if kind == "knowledge": panel = game._make_knowledge_card("plant_kucao", true)
		else: panel = game._make_card(GameState.ACTION_CARDS[0], "effective", kind == "dispatch").panel
		var view: Control = game._make_gyro_card_view(panel)
		add_child(view)
		view.position = Vector2(400, 250)
		await settle(0.1)
		await shadow_check(view, kind)
		view.queue_free()
	game._deal_sfx_turn = -1
	game.play_deal_anim = true
	game._build_hand_panel()
	await get_tree().process_frame
	var card: Control = game.card_infos[0].panel
	var shadow: Node2D = card.get_meta("projected_shadow")
	var builds_before: int = shadow.geometry_builds
	await settle(0.25)
	check(shadow.geometry_builds > builds_before + 3, "Shadow continuously updates while cards fly")
	await settle(0.75)
	await RenderingServer.frame_post_draw
	var settled: PackedVector2Array = shadow.points.duplicate()
	var builds_settled: int = shadow.geometry_builds
	await settle(0.15)
	await RenderingServer.frame_post_draw
	check(shadow.points == settled and shadow.geometry_builds == builds_settled, "Settled shadow retains one geometry without a late rebuild or flash")
	await shot("dealt-rounded-shadow")
	game.wetland.set_process(false)
	game._open_deck_viewer()
	await settle(1.5)
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		get_window().size = dimensions
		await settle(0.3)
		var view: Control = game.deck_viewer_grid.get_child(0)
		game._show_card_detail(view, view.get_meta("card"))
		await settle(0.8)
		await detail_shadow_check(game._detail_big_card, "Deck detail " + str(dimensions.x))
		await shot("deck-detail-shadow-" + str(dimensions.x))
		game._close_card_detail()
	game._close_deck_viewer()
	Knowledge.unlock("plant_kucao")
	game._open_knowledge_viewer()
	await settle(1.5)
	game._show_knowledge_detail(game.knowledge_grid.get_child(Knowledge.all_ids().find("plant_kucao")), "plant_kucao")
	await settle(0.8)
	await detail_shadow_check(game._knowledge_big_card, "Knowledge detail")
	await shot("knowledge-detail-shadow")
	print("POLICY_SHADOW: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
