extends Node
## Real main scene, real dealt hands/budgets, no fixture boosts. The driver
## operates the production drag/drop, undo, save/load and settlement handlers.
const CardInput = preload("res://tests/card_input.gd")
var game: Node
var checks := 0
var failures := 0
var records: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func wait_for(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func close_popups() -> void:
	for i in 100:
		if game._current_phase == "popup_report": return
		if game.crisis_root.visible: game._on_crisis_dismiss()
		if game.popup_root.visible: game._on_popup_button()
		if game._current_phase == "allocate" and not game.popup_root.visible and not game.crisis_root.visible and not game._sort_animating:
			await wait_for(0.8)
			return
		await wait_for(0.06)
	check(false, "Popup flow must reach allocation within six seconds")

func queue_cards() -> Array:
	var queue: Array = []
	for index in game._ordered_staged_indices():
		var info: Dictionary = game.card_infos[index]
		queue.append({"card_id": info.card_id, "tier": game._info_tier(info), "dispatched": info.get("dispatched", false)})
	return queue

func value_of(metrics: Dictionary) -> float:
	var value := 0.0
	for metric in ["water_quality", "vegetation", "fish", "birds", "community"]:
		var amount := float(metrics[metric])
		var threshold := float(GameState.failure_threshold_for(metric))
		value += amount - pow(maxf(0.0, threshold + 18.0 - amount), 2.0) * 3.0
	return value

func best_play() -> Dictionary:
	var queue := queue_cards()
	var best_value := value_of(GameState.preview_settlement(queue))
	var best: Dictionary = {}
	for info in game.card_infos:
		if info.selected or info.get("dispatched", false): continue
		for tier in ["basic", "effective", "deep"]:
			if GameState.tier_cost(info.card_id, tier) + game._committed_funds() > GameState.funds: continue
			var proposed := queue.duplicate(true)
			proposed.append({"card_id": info.card_id, "tier": tier, "dispatched": false})
			var value := value_of(GameState.preview_settlement(proposed))
			if value > best_value + 0.001:
				best_value = value
				best = {"info": info, "tier": tier}
	return best

func shot(label: String) -> void:
	var folder := OS.get_environment("POYANG_SCREENSHOT_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))

func play_run(difficulty: int, run_seed: int) -> void:
	game._on_title_start()
	game._on_difficulty_pick(difficulty)
	game.seed_input.text = str(run_seed)
	game._on_start_pressed()
	await close_popups()
	game.score_speed = game.SCORE_SPEED_MAX
	var run: Dictionary = {"difficulty": difficulty, "seed": run_seed, "turns": []}
	for step in 16:
		if GameState.game_over: break
		check(game._current_phase == "allocate" and not game.card_infos.is_empty(), "Real run reaches a dealt hand")
		var turn: int = GameState.turn
		var funds: int = GameState.funds
		for slot in GameState.action_slots():
			var choice := best_play()
			if choice.is_empty(): break
			game._lever_cooldown_ms = -6000
			game._set_play_tier(choice.tier, false)
			CardInput.drop_on_board(game, choice.info)
			check(choice.info.selected and choice.info.stage_zone == "board", "Real-budget candidate can be dragged onto wood")
			await wait_for(0.14)
		await wait_for(0.65)
		check(GameState.funds == funds, "Ordinary queued cards reserve funds without charging yet")
		if turn % 3 == 1 and not game._ordered_staged_indices().is_empty():
			var undo: Dictionary = game.card_infos[game._ordered_staged_indices().back()]
			var queue_before := queue_cards()
			var tier: String = undo.tier
			CardInput.retract(game, undo)
			await wait_for(0.65)
			check(not undo.selected and not undo.get("flying", false), "Real run undo returns automatically")
			game._lever_cooldown_ms = -6000
			game._set_play_tier(tier, false)
			CardInput.drop_on_board(game, undo)
			await wait_for(0.65)
			check(queue_cards() == queue_before and GameState.funds == funds, "Undo/replay preserves order, tier and funds")
		game._update_metric_preview()
		var expected := GameState.preview_settlement(queue_cards())
		check(game._metric_preview_values.is_empty() if queue_cards().is_empty() else game._metric_preview_values == expected, "Real run HUD uses the current complete forecast")
		if turn % 4 == 1:
			var queue_before := queue_cards()
			var effects_before: Array = GameState.effects_queue.duplicate(true)
			game.save_game()
			check(game.load_game(), "Real run saves and reloads")
			await wait_for(0.7)
			game._update_metric_preview()
			check(queue_cards() == queue_before and GameState.funds == funds and GameState.effects_queue == effects_before, "Reload preserves queue, budget and inherited effects")
			check(GameState.preview_settlement(queue_cards()) == expected, "Reload preserves this turn's weather and exact forecast")
		if turn in [1, 8, 16]: await shot("run-%d-%d-turn-%02d-board" % [difficulty, run_seed, turn])
		var played := queue_cards()
		game._finish_turn()
		var actual: Dictionary = GameState.metrics.duplicate(true)
		check(actual == expected, "Real main-scene settlement exactly matches six forecast values: difficulty %d seed %d turn %d" % [difficulty, run_seed, turn])
		run.turns.append({"turn": turn, "funds": funds, "cards": played, "preview": expected, "actual": actual, "inherited_effects_remaining": GameState.effects_queue.size()})
		for i in 180:
			if not game._score_animating: break
			await wait_for(0.08)
		check(not game._score_animating, "Real settlement animation completes without getting stuck")
		for info in game.card_infos:
			check(info.panel.get_node_or_null("CardFlight") == null, "Real settlement leaves no active card-flight driver")
		if GameState.game_over: break
		await close_popups()
		check(GameState.turn == turn + 1 or GameState.game_over, "Continue advances the real season exactly once")
		run["final_metrics"] = GameState.metrics.duplicate(true)
	run["game_over"] = GameState.game_over
	run["failure"] = GameState.failure_reason
	run["final_metrics"] = GameState.metrics.duplicate(true)
	records.append(run)
	print("AUDIT_RUN: difficulty=%d seed=%d turns=%d failure=%s" % [difficulty, run_seed, run.turns.size(), str(GameState.is_failure)])

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	game = scene.get_node("Game")
	add_child(scene)
	await wait_for(0.5)
	if game._intro_playing: game._finish_intro()
	for difficulty in range(4):
		for run_seed in [20261010, 20261011]:
			await play_run(difficulty, run_seed)
	var output := OS.get_environment("POYANG_AUDIT_JSON")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "runs": records}, "\t"))
	print("GAMEPLAY_AUDIT: %d checks, %d failures, %d runs" % [checks, failures, records.size()])
	get_tree().quit(0 if failures == 0 else 1)
