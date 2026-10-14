extends Node
var checks := 0
var failures := 0
var game: Node
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("POYANG_SCREENSHOT_DIR")
	get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))
func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await get_tree().create_timer(1.0).timeout
	if game._intro_playing: game._finish_intro()
	game._on_title_start()
	game._on_difficulty_pick(2)
	game.seed_input.text = "20261011"
	game._on_start_pressed()
	for i in 24:
		if not game.popup_root.visible: break
		game._on_popup_button()
		await get_tree().create_timer(0.12).timeout
	game.set_process(false)
	GameState.turn = 4
	GameState.metrics = {"water_level": 46, "water_quality": 70, "vegetation": 65, "fish": 65, "birds": 83, "community": 54}
	GameState.bird_population = {"base": 55, "migrants": 28, "loss": 0, "season": "winter", "total": 83}
	GameState._set_bird_baseline(60)
	GameState.pending_crisis = GameState.crisis_by_id("winter_poaching").duplicate(true)
	GameState.action_tiers = {}
	GameState.used_action_ids = []
	game._update_hud()
	game._update_metric_preview()
	await get_tree().create_timer(0.8).timeout
	var bird_line: int = int(GameState.failure_threshold_for("birds"))
	var expected_birds: Dictionary = GameState.preview_settlement_detail([])["birds"]
	if int(expected_birds["total"]) > 83: expected_birds = GameState.bird_snapshot()
	check(game.metric_bars.birds.reference_label.text == "留湖 %d · 迁徙 %d · 生态红线 %d" % [expected_birds["base"], expected_birds["migrants"], bird_line], "Bird HUD numbers match the populations before a gain tail or the survivors before a loss tail")
	check(is_equal_approx(game.metric_bars.birds.line.anchor_left, bird_line / 100.0), "Bird bar uses the rolled opening redline")
	check(game.metric_bars.birds.bar.get_theme_stylebox("fill") is StyleBoxEmpty and game.metric_bars.birds.bird_segments._resident_fill.bg_color == Color.WHITE, "One renderer owns white residents without an opaque layer below migrants")
	check(game.metric_bars.birds.bird_segments.MIGRANT_ALPHA < 0.5 and not game.metric_bars.birds.ripple.visible, "Migrant segment is static translucent white")
	check(game.metric_bars.birds.bird_segments.residents == 55 and game.metric_bars.birds.bird_segments.migrants == 28, "Segment split matches population snapshot")
	game._fill_metric_tip("birds")
	check(game.metric_tip_body.text.contains("留湖") and game.metric_tip_body.text.contains("低于生态红线即判负"), "Compact tip explains the combined-total rule")
	check(game.metric_bars.birds.val.tooltip_text.contains("生态红线"), "Staged forecast includes the fixed redline")
	game.metric_tip.visible = true
	game._place_metric_tip(game.metric_bars.birds.row.get_global_rect().get_center())
	await get_tree().process_frame
	check(game.metric_tip.size.x <= 260 and not game.metric_tip.get_global_rect().intersects(game.staged_board.get_global_rect()), "Bird tip stays compact and avoids staged cards")
	await capture("expert-birds-healthy")
	game.metric_tip.visible = false
	var body: String = game._crisis_body_text(GameState.pending_crisis, true)
	check(body.contains("50%") and body.contains("80%") and body.contains("100%") and body.contains("保底"), "Warning explains real mitigation and guaranteed response")
	check(not body.contains("偏高"), "Social warning does not label high trust as a danger")
	check(not game._crisis_short_label("winter_poaching").contains("偏高"), "Review button must not label high trust as a danger")
	game._on_crisis_warn(GameState.pending_crisis)
	await get_tree().create_timer(0.5).timeout
	await capture("expert-winter-warning")
	game._on_crisis_dismiss()
	GameState.funds = 500
	GameState.execute_action("patrol", "effective")
	GameState._resolve_pending_crisis()
	var row: Control = game._make_warn_row(GameState.warn_history.back())
	check(row.get_child(0).text.contains("80%") and row.get_child(0).text.contains("实际损失"), "Review displays actual reduced damage")
	row.free()
	game.crisis_root.visible = false
	GameState.bird_population = {"base": 20, "migrants": 28, "loss": 0, "season": "winter", "total": 48}
	GameState.metrics.birds = 48
	GameState.metrics.vegetation = 35
	game._update_hud()
	game._update_metric_preview()
	await get_tree().create_timer(0.6).timeout
	game._update_metric_preview()
	check(game.metric_bars.birds.reference_label.text.contains("留湖 20"), "HUD still shows resident population after damage")
	check(is_equal_approx(game.metric_bars.birds.line.anchor_left, bird_line / 100.0), "Resident damage cannot move the redline")
	check(game.metric_bars.birds.reference_label.tooltip_text.contains("将跌破"), "Unplayed-hand forecast exposes impending total failure")
	await capture("expert-birds-risk")
	GameState.metrics.vegetation = 70
	game._metric_preview_dirty = true
	game._update_metric_preview()
	check(not game.metric_bars.birds.reference_label.tooltip_text.contains("将跌破"), "Improved forecast clears a stale total failure warning")
	GameState.metrics.vegetation = 35
	game._metric_preview_dirty = true
	game._update_metric_preview()
	get_window().size = Vector2i(960, 540)
	await get_tree().create_timer(0.5).timeout
	game._fill_metric_tip("birds")
	game.metric_tip.visible = true
	game._place_metric_tip(game.metric_bars.birds.row.get_global_rect().get_center())
	await get_tree().process_frame
	check(get_viewport().get_visible_rect().encloses(game.metric_tip.get_global_rect()), "Health tip fits minimum window")
	await capture("expert-birds-small")
	GameState.metrics = {"water_level": 50, "water_quality": 90, "vegetation": 90, "fish": 90, "birds": 55, "community": 80}
	GameState.bird_population = {}
	GameState.seasonal_legacy = []
	GameState.winter_returns = {}
	GameState.used_action_ids = []
	GameState.action_tiers = {}
	GameState.game_over = false
	GameState.is_failure = false
	game.metric_tip.visible = false
	for event in GameState.CRISES:
		if not event.get("seasonal_social", false): continue
		GameState.turn = GameState.SEASONS.find(event.season) + 1
		GameState.pending_crisis = event.duplicate(true)
		game._show_crisis_alert(event, true)
		await get_tree().create_timer(0.15).timeout
		var panel: Control = game.crisis_body.get_parent().get_parent()
		check(get_viewport().get_visible_rect().encloses(panel.get_global_rect()), "All fourteen warnings fit the minimum window")
		check(game.crisis_body.scroll_active and get_viewport().get_visible_rect().encloses(game.crisis_button.get_global_rect()), "Long warning text scrolls while the dismiss button remains accessible")
		check(game.crisis_body.text.contains("生态提示"), "Each event includes its ecological explanation")
		if event.id in ["summer_sand_mining", "wetland_encroach", "winter_drone_disturbance"]:
			await capture("full-warning-" + event.id)
		game.crisis_root.visible = false
	GameState.turn = 2
	GameState.pending_crisis = GameState.crisis_by_id("summer_sand_mining").duplicate(true)
	game._metric_preview_dirty = true
	game._update_metric_preview()
	check(game.metric_bars.water_level.val.tooltip_text.contains("秋季开局水位遗留"), "Staged forecast explains deferred autumn water loss")
	game._fill_metric_tip("water_level")
	check(game.metric_tip_body.text.contains("秋季开局遗留"), "Water hover includes currently warned legacy")
	GameState.turn = 3
	GameState.pending_crisis = GameState.crisis_by_id("wetland_encroach").duplicate(true)
	game._metric_preview_dirty = true
	game._update_metric_preview()
	check(game.metric_bars.birds.val.tooltip_text.contains("候鸟食物损失"), "Staged bird forecast explains persistent food loss")
	GameState._resolve_pending_crisis()
	row = game._make_warn_row(GameState.warn_history.back())
	check(row.get_child(0).text.contains("候鸟食物") and row.get_child(0).text.contains("冬末"), "Review explains actual food legacy and its lifetime")
	row.free()
	for card in GameState.ACTION_CARDS:
		for tier in ["basic", "effective", "deep"]:
			check(not game._tier_effects_text(card, tier).contains("候鸟食物修复"), "Card preview only lists the six metrics: " + str(card.id) + tier)
		check(not game._card_detail_text(card).contains("候鸟食物修复"), "Deck detail hides internal food restoration: " + str(card.id))
	# Numbered annotation regression: exercise dynamic formatting after deletion.
	for count in [0, 1, 3]:
		GameState.dispatch_used_count = count
		check(game._dispatch_hint_text() == "按「有效政策投入」档结算", "Dispatch text has no deleted price or cooldown fragments")
	game._sync_audio_ui()
	check(game.bgm_switch_btn == null and game.pause_bgm_btn == null, "Removed track text leaves no blank audio controls")
	for card in GameState.ACTION_CARDS:
		var detail: String = game._card_detail_text(card)
		check(not detail.contains("※ [/color]"), "Removed card side notes leave no empty bullet: " + str(card.id))
	for id in GameState.KNOWLEDGE_CARDS:
		var text: String = game._knowledge_detail_text(id, true)
		check(not text.contains("[b]生态角色") and not text.contains("[b]资料来源"), "Knowledge body renders the requested headings without bold")
	check(not game._knowledge_detail_text("egg_dixinhu", false).contains("在游戏里"), "Locked knowledge card omits the deleted instruction")
	for crisis in GameState.CRISES:
		var warning: String = game._crisis_body_text(crisis, true)
		check(not warning.contains("优先打出") and not warning.contains("应对建议("), "Warning formats after deleting the supply placeholder")
	GameState.metrics.community = 30
	GameState.used_action_ids = []
	var plan: Array = GameState.natural_evolution_plan()
	check(plan.any(func(e): return e.metric == "community" and e.why == "下降"), "Trust decline formats without a removed numeric placeholder")
	GameState.metrics.water_quality = 0
	GameState.check_failure_now()
	game._show_report(GameState.generate_report())
	check(game.popup_body.text.contains("失败原因") and not game.popup_body.text.contains("判负原因") and not game.popup_body.text.contains("直接死因"), "Failure report uses the edited heading")
	check(not game.popup_body.text.contains("反思") and not game.popup_body.text.contains("补强建议") and not game.popup_body.text.contains("同一回合跌破"), "Failure report omits deleted sections and extra suggestions")
	if game._popup_reveal and game._popup_reveal.is_valid(): game._popup_reveal.kill()
	game.popup_body.visible_characters = -1
	await get_tree().create_timer(0.3).timeout
	await capture("text-revision-failure-report")
	GameState.game_over = true
	GameState.is_failure = false
	game._show_report(GameState.generate_report())
	check(not game.popup_body.text.contains("反思"), "Victory report omits the reflection section")
	print("EXPERT_ECOLOGY_UI checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
