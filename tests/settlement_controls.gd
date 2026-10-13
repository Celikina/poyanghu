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
func wait_for(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
func controls_locked(label: String) -> void:
	check(game.hand_sort_btn.disabled and game.refresh_btn.disabled, label + " disables both hand buttons")
	for button in game.lever_handle.buttons: check(button.disabled, label + " disables stamp targets")
	check(is_equal_approx(game.lever_handle.modulate.a, 0.55), label + " visibly fades the policy parchment")
	check(not game.hand_sort_btn.text.contains("禁用") and not game.refresh_btn.text.contains("禁用") and not game.lever_cd_label.text.contains("禁用"), label + " adds no disabled label")
func check_settlement() -> void:
	GameState.funds = 1000
	for metric in GameState.metrics: GameState.metrics[metric] = 65
	game.current_hand = []
	for id in ["patrol", "research", "education", "guard_team", "water_control", "veg_restore", "community_comp"]:
		game.current_hand.append(GameState.card_by_id(id))
	game.play_deal_anim = false
	game._build_hand_panel()
	await wait_for(0.5)
	for i in 2:
		var info: Dictionary = game.card_infos[i]
		info.selected = true
		info.staged_by_drag = true
		info.stage_order = i
		info.stage_zone = "board"
		info.tier = "effective"
	game._layout_fan()
	await wait_for(0.6)
	game._sort_cooldown_ms = -10000
	game._lever_cooldown_ms = -10000
	game._refresh_allocation_controls()
	check(not game.hand_sort_btn.disabled and not game.refresh_btn.disabled and not game.lever_handle.buttons[0].disabled, "Allocation controls start available")
	var mode: bool = game._deck_sort_by_category
	var tier: String = game.play_tier
	game._finish_turn()
	check(game._score_animating, "Actual settlement begins")
	controls_locked("Immediately on settlement")
	var funds: int = GameState.funds
	var stamp_cursor: int = game._sfx_cursor
	game.hand_sort_btn.pressed.emit()
	game.refresh_btn.pressed.emit()
	game.lever_handle.buttons[0].pressed.emit()
	game._toggle_deck_sort()
	game._set_play_tier("deep")
	check(game._deck_sort_by_category == mode and not game._sort_animating, "Rejected input never starts hand or library sorting")
	check(game.play_tier == tier and game._sfx_cursor == stamp_cursor, "Rejected stamps neither change tier nor play audio")
	check(GameState.funds == funds and game._refresh_used_turn != GameState.turn, "Rejected refresh does not charge or consume the turn's use")
	await wait_for(0.16)
	await shot("settlement-locked")
	var deadline := Time.get_ticks_msec() + 7000
	while game._score_animating and Time.get_ticks_msec() < deadline:
		game._update_sort_cooldown()
		game._update_lever_cooldown()
		game._refresh_action_buttons()
		check(game.hand_sort_btn.disabled and game.refresh_btn.disabled and game.lever_handle.buttons[0].disabled, "Cooldown and HUD updates do not re-enable settlement controls")
		await wait_for(0.05)
	check(not game._score_animating and game._current_phase == "popup_settlement", "Settlement completes normally")
	game._refresh_allocation_controls()
	controls_locked("Settlement confirmation")
	game._toggle_hand_sort()
	game._on_policy_stamp_requested("deep")
	check(game._deck_sort_by_category == mode and game.play_tier == tier, "Confirmation popup keeps hand controls locked")
	for i in 36:
		if game.crisis_root.visible: game._on_crisis_dismiss()
		if game.popup_root.visible: game._on_popup_button()
		await wait_for(0.12)
		if game._current_phase == "allocate" and not game._sort_animating and not game.popup_root.visible and not game.crisis_root.visible: break
	await wait_for(0.8)
	game._refresh_allocation_controls()
	check(game._current_phase == "allocate" and not game._score_animating, "Continue reaches the next allocation")
	check(not game.hand_sort_btn.disabled and not game.refresh_btn.disabled, "Next turn restores both hand buttons")
	check(not game.lever_handle.buttons[0].disabled and is_equal_approx(game.lever_handle.modulate.a, 1.0), "Next turn restores stamp interaction and normal opacity")
func check_library(kind: String) -> void:
	var open: Callable
	var close: Callable
	var scroll: ScrollContainer
	match kind:
		"deck":
			open = game._open_deck_viewer
			close = game._close_deck_viewer
		"knowledge":
			open = game._open_knowledge_viewer
			close = game._close_knowledge_viewer
		"dispatch":
			open = game._open_dispatch_panel
			close = game._close_dispatch_panel
	open.call()
	await wait_for(1.5)
	match kind:
		"deck": scroll = game.deck_viewer_scroll
		"knowledge": scroll = game.knowledge_scroll
		"dispatch": scroll = game.dispatch_scroll
	var bar := scroll.get_v_scroll_bar()
	var bottom := bar.max_value - bar.page
	check(bottom > 30, kind + " has a real scrollable library")
	scroll.scroll_vertical = int(bottom * 0.7)
	await wait_for(0.1)
	check(scroll.scroll_vertical > 0, kind + " can scroll away from its first row")
	var driver: Node = scroll.get_node("MotionWebScroll")
	driver.bar = bar
	driver.current = bar.value
	driver.target = bottom
	driver.set_process(true)
	close.call()
	open.call()
	check(scroll.scroll_vertical == 0 and is_zero_approx(driver.target), kind + " reopens at zero immediately")
	await wait_for(0.7)
	check(scroll.scroll_vertical == 0 and is_zero_approx(driver.target) and not driver.is_processing(), kind + " stays at the top after rebuilding and old inertia")
	await shot(kind + "-reopened-at-top")
	close.call()
	await wait_for(0.4)
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
	await check_settlement()
	for kind in ["deck", "knowledge", "dispatch"]: await check_library(kind)
	print("SETTLEMENT_CONTROLS: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
