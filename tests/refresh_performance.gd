extends Node
var game: Node
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func wait_for(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
func compare_shadow(panel: Control, label: String) -> void:
	add_child(panel)
	panel.position = Vector2(310, 220)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game._bind_card_gyro(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var shadow: Node2D = panel.get_meta("projected_shadow")
	var face: TextureRect = panel.get_meta("pixel_face")
	var actual: PackedVector2Array = shadow._contour(face.texture, face.get_meta("shadow_silhouette", ""))
	var exact: PackedVector2Array = shadow._contour(face.texture)
	check(actual == exact, label + " template cache retains the actual alpha contour")
	var reference: Node2D
	if ResourceLoader.exists("res://scripts/reference_shadow_before.gd"):
		reference = Node2D.new()
		reference.set_script(load("res://scripts/reference_shadow_before.gd"))
		reference.hide()
		panel.add_child(reference)
	var builds: int = shadow.surface_builds
	for i in 3:
		panel.scale = Vector2.ONE * [0.52, 1.0, 1.8][i]
		panel.rotation = [0.0, 0.25, -0.3][i]
		panel.set_meta("poke_scale", 1.0 + 0.03 * i)
		panel.set_meta("shadow_preserve_size", i == 2)
		var tilt := Vector2(0.16 * i, -0.12 * i)
		shadow.update_projection(panel, tilt)
		if reference:
			reference.update_projection(panel, tilt)
			check(shadow.points == reference.points and is_equal_approx(shadow.softness, reference.softness), label + " retains projected corners and softness at pose " + str(i))
			var a: Array = shadow._mesh.surface_get_arrays(0)
			var b: Array = reference._mesh.surface_get_arrays(0)
			check(a[Mesh.ARRAY_VERTEX] == b[Mesh.ARRAY_VERTEX] and a[Mesh.ARRAY_COLOR] == b[Mesh.ARRAY_COLOR] and a[Mesh.ARRAY_INDEX] == b[Mesh.ARRAY_INDEX], label + " retains every rendered vertex, color and triangle at pose " + str(i))
	check(shadow.surface_builds == builds and shadow.vertex_updates >= 3, label + " changes poses without rebuilding the surface")
	panel.queue_free()
func verify_shapes() -> void:
	for card in GameState.ACTION_CARDS:
		for tier in ["basic", "effective", "deep"]:
			await compare_shadow(game._make_card(card, tier).panel, str(card.id) + "/" + tier)
		await compare_shadow(game._make_card(card, "effective", true).panel, str(card.id) + "/dispatch")
	for kid in Knowledge.all_ids():
		await compare_shadow(game._make_knowledge_card(kid, true), str(kid))
	await compare_shadow(game._make_knowledge_card("plant_kucao", false), "locked knowledge")
func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await wait_for(0.5)
	if game._intro_playing: game._finish_intro()
	game._on_title_start()
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	game.seed_input.text = "20261013"
	game._on_start_pressed()
	for i in 24:
		if game.popup_root.visible: game._on_popup_button()
		await wait_for(0.1)
	game.set_process(false)
	game.wetland.set_process(false)
	var card: Control = game.card_infos[0].panel
	var shadow: Node2D = card.get_meta("projected_shadow")
	var start_position: Vector2 = card.position
	var started := Time.get_ticks_usec()
	for i in 1000:
		card.position = start_position + Vector2(float(i % 11), float(i % 7))
		shadow.update_projection(card, Vector2(float(i % 19) * 0.01, float(i % 13) * 0.01))
	print("SHADOW_BENCH moving1000_us=", Time.get_ticks_usec() - started)
	card.position = start_position
	shadow.update_projection(card, Vector2.ZERO)
	started = Time.get_ticks_usec()
	for i in 10000: shadow.update_projection(card, Vector2.ZERO)
	print("SHADOW_BENCH resting10000_us=", Time.get_ticks_usec() - started)
	var water: ProgressBar = game.metric_bars.water_level.bar
	var tweens: Array = []
	for i in 20:
		game._update_hud()
		var tween: Tween = water.get_meta("motion_value") if water.has_meta("motion_value") else null
		if tween: tweens.append(tween.get_instance_id())
	var unique: Dictionary = {}
	for id in tweens: unique[id] = true
	print("HUD_BENCH updates20_value_tween_instances=", unique.size())
	if OS.get_environment("REQUIRE_IMMEDIATE_REFRESH") == "1":
		var original: int = GameState.metrics.water_level
		GameState.metrics.water_level = original - 5
		game._update_hud()
		await wait_for(0.12)
		check(water.value < original and water.value > original - 5, "Changed metric still animates gradually")
		for i in 20: game._update_hud()
		await wait_for(0.25)
		check(is_equal_approx(water.value, original - 5), "Repeated HUD updates retain the original 0.35-second completion time")
		GameState.metrics.water_level = original + 3
		game._update_hud()
		await wait_for(0.1)
		GameState.metrics.water_level = original
		game._update_hud()
		await wait_for(0.37)
		check(is_equal_approx(water.value, original), "A changed target interrupts the old animation and reaches the new value")
		GameState.metrics.water_level = original + 2
		game._update_hud()
		await wait_for(0.1)
		game.Motion.cancel(water, "value")
		game._update_hud()
		await wait_for(0.37)
		check(is_equal_approx(water.value, original + 2), "A canceled animation resumes toward its still-current target")
		GameState.metrics.water_level = original
		game._update_hud()
		await wait_for(0.37)
	GameState.funds = 1000
	game._refresh_used_turn = -1
	game._refresh_action_buttons()
	var canvas: CanvasLayer = game._ui_canvas()
	var before := canvas.get_child_count()
	game._on_refresh_hand()
	print("REFRESH_AT_CLICK: text=", game.refresh_btn.text, " disabled=", game.refresh_btn.disabled, " alpha=", game.refresh_btn.modulate.a)
	if OS.get_environment("REQUIRE_IMMEDIATE_REFRESH") == "1":
		check(game.refresh_btn.text == "本回合已刷新" and game.refresh_btn.disabled and game.refresh_btn.modulate.a > 0.99,
			"Used text becomes visible immediately, before gathering finishes")
		check(game.refresh_btn.get_theme_stylebox("disabled") is StyleBoxEmpty,
			"Shattered button keeps its text with no restored background")
		check(unique.size() <= 1, "Money-only HUD changes do not restart identical bar animation")
	check(canvas.get_child_count() == before + 9, "Refresh still produces exactly nine shards")
	game._on_refresh_hand()
	check(GameState.funds == 995, "Rapid second click does not charge again")
	await wait_for(0.03)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("POYANG_SCREENSHOT_DIR").path_join("refresh-immediate.png"))
	await wait_for(1.2)
	check(canvas.get_child_count() == before + 9, "Shard lifetime remains 1.4 seconds even after combining tweens")
	await wait_for(0.3)
	check(canvas.get_child_count() == before, "Shards are still cleaned up after the original lifetime")
	check(game.refresh_btn.text == "本回合已刷新" and game.refresh_btn.disabled, "Used state remains correct after redealing")
	GameState.turn += 1
	await game._enter_allocate()
	check(game.refresh_btn.text.begins_with("刷新手牌") and not game.refresh_btn.disabled and game.refresh_btn.modulate.a > 0.99,
		"Next turn restores the original refresh button and state")
	check(not game.refresh_btn.get_theme_stylebox("disabled") is StyleBoxEmpty, "Original button artwork is restored for the next turn")
	if OS.get_environment("VERIFY_SHADOW_SHAPES") == "1": await verify_shapes()
	print("REFRESH_PERFORMANCE: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
