extends Node
var game: Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func wait_for(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
func make_hand(count: int) -> void:
	GameState.turn += 1
	GameState.funds = 1000
	game.current_hand = GameState.ACTION_CARDS.slice(0, count)
	game.play_deal_anim = false
	game._deal_sfx_turn = GameState.turn
	game._build_hand_panel()
	await wait_for(0.4)
func stage(count: int) -> Array:
	var played: Array = []
	for i in count:
		var info: Dictionary = game.card_infos[i]
		info.selected = true
		info.staged_by_drag = true
		info.stage_order = i
		info.stage_zone = "board"
		info.tier = ["basic", "effective", "deep"][i % 3]
		played.append(info)
	game._layout_fan()
	game._update_selected_label()
	return played
func return_cards(played: Array) -> void:
	for info in played: game._return_staged_to_hand(info)
	await wait_for(0.6)
func verify_stamp() -> void:
	check(game._sfx_streams.has("stamp"), "Stamp audio is loaded")
	check(is_equal_approx(game._sfx_streams.stamp.get_length(), 0.23), "Only one short stamp is played")
	var landed: Array = []
	var monitor := func(): landed.append([Time.get_ticks_msec(), game.lever_handle.seal.scale])
	game.lever_handle.stamp_landed.connect(monitor)
	var cursor: int = game._sfx_cursor
	game._refresh_lever_visuals(false)
	await wait_for(0.2)
	check(game._sfx_cursor == cursor and landed.is_empty(), "Loading the existing stamp does not play a sound")
	game._lever_cooldown_ms = -10000
	var start := Time.get_ticks_msec()
	game.lever_handle.buttons[0].pressed.emit()
	check(game.play_tier == "basic" and game._sfx_cursor == cursor, "Stamp sound waits for contact rather than playing early")
	await wait_for(0.14)
	check(landed.size() == 1 and game._sfx_cursor == (cursor + 1) % game._sfx_players.size(), "One stamp contact plays one sound")
	if landed.size() == 1:
		check(landed[0][0] - start >= 85 and landed[0][0] - start < 180, "Sound lands with the 0.10-second press")
		check(landed[0][1].distance_to(Vector2(0.96, 0.96)) < 0.001, "Sound coincides with the pressed seal pose")
	var player: AudioStreamPlayer = game._sfx_players[cursor]
	check(player.stream == game._sfx_streams.stamp and is_equal_approx(player.volume_db, linear_to_db(maxf(game.bgm_volume, 0.001)) - 3.0), "Stamp uses the shared volume setting")
	cursor = game._sfx_cursor
	game.lever_handle.buttons[2].pressed.emit()
	await wait_for(0.25)
	check(game.play_tier == "basic" and game._sfx_cursor == cursor, "Cooldown rejects both the change and its sound")
	game._lever_cooldown_ms = -10000
	game.lever_handle.buttons[0].pressed.emit()
	game._on_policy_stamp_requested("invalid")
	await wait_for(0.25)
	check(game._sfx_cursor == cursor, "Same tier and invalid requests are silent")
	game.wetland.reduced_motion = true
	game._on_policy_stamp_requested("deep")
	check(game.play_tier == "deep" and game._sfx_cursor == (cursor + 1) % game._sfx_players.size(), "Reduced motion still plays the accepted stamp sound once")
	game.wetland.reduced_motion = false
	game.lever_handle.stamp_landed.disconnect(monitor)
func verify_refresh() -> void:
	await make_hand(7)
	var played := stage(4)
	await wait_for(0.5)
	var poses: Array = []
	var tiers: Array = []
	for info in played:
		poses.append(info.base_pos)
		tiers.append(info.tier)
	check(game._refreshable_hand_count() == 3 and not game.refresh_btn.disabled, "Four played cards leave three refreshable cards")
	game._on_refresh_hand()
	game._on_refresh_hand()
	check(GameState.funds == 995, "Three-card refresh still costs exactly five, even on a repeated click")
	check(game.refresh_btn.text == "本回合已刷新", "Refresh status still changes immediately")
	await wait_for(1.5)
	check(game.current_hand.size() == 3 and game.card_infos.size() == 7, "Four played plus three replacement cards remain seven, not eleven")
	for i in played.size():
		check(game.card_infos.has(played[i]) and is_instance_valid(played[i].panel), "Played card identity survives refresh")
		check(played[i].tier == tiers[i] and played[i].base_pos.is_equal_approx(poses[i]) and played[i].panel.position.distance_to(poses[i]) < 0.1, "Played cards keep their locked tier and table position")
	game.save_game()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.SAVE_PATH))
	check(saved.hand_ids.size() == 7 and saved.staged_queue.size() == 4, "Saving a refreshed hand retains the conserved total and table queue")
	await return_cards(played)
	check(game._refreshable_hand_count() == 7 and game.card_infos.size() == 7, "Returning all four played cards restores exactly seven cards")
	for count in [7, 9]:
		await make_hand(count)
		game._on_refresh_hand()
		await wait_for(1.5)
		check(game.card_infos.size() == count and game.current_hand.size() == count and GameState.funds == 995, "Full or bonus-sized hands refresh their own count for five")
	await make_hand(7)
	played = stage(2)
	check(GameState.dispatch_card("water_control"), "Dispatch fixture pays the normal dispatch fee")
	game._sync_dispatched_stage_cards()
	var dispatched: Dictionary = game.card_infos.back()
	check(dispatched.get("dispatched", false) and game._refreshable_hand_count() == 5, "Dispatch and table cards are excluded from replacement count")
	var budget: int = GameState.funds
	game._on_refresh_hand()
	await wait_for(1.5)
	check(game.current_hand.size() == 5 and game.card_infos.size() == 8 and game.card_infos.has(dispatched), "Refresh retains five hand, two table and one dispatch card")
	check(GameState.funds == budget - 5, "Dispatch presence does not change the fixed refresh price")
	game._return_staged_to_hand(dispatched)
	await return_cards(played)
	check(game.card_infos.size() == 7 and game._refreshable_hand_count() == 7 and GameState.dispatched_cards.is_empty(), "Undo dispatch and played cards leaves the original ordinary hand count")
	await make_hand(4)
	played = stage(4)
	check(game.refresh_btn.disabled and game._refreshable_hand_count() == 0, "An empty hand disables refresh")
	game._on_refresh_hand()
	check(GameState.funds == 1000 and game._refresh_used_turn != GameState.turn, "Empty-hand attempt neither charges nor consumes the turn's refresh")
	game._return_staged_to_hand(played.pop_back())
	await wait_for(0.6)
	check(not game.refresh_btn.disabled and game._refreshable_hand_count() == 1, "Returning one card re-enables refresh")
	game._on_refresh_hand()
	await wait_for(1.5)
	check(GameState.funds == 995 and game.current_hand.size() == 1 and game.card_infos.size() == 4, "One remaining card refreshes one card for five")
	await return_cards(played)
	check(game._refreshable_hand_count() == 4, "Undo after a one-card refresh restores only the original four")
	await make_hand(1)
	GameState.funds = 4
	game._update_hud()
	game._on_refresh_hand()
	check(GameState.funds == 4 and game._refresh_used_turn != GameState.turn and game.refresh_btn.disabled, "Insufficient budget keeps the existing hand and refresh available for later")
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
	await verify_stamp()
	await verify_refresh()
	print("STAMP_REFRESH: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
