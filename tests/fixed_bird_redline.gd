extends Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture(state: Node, mode: int) -> void:
	state.difficulty = mode
	state.turn = 4
	state.game_over = false
	state.is_failure = false
	state.metrics = {"water_level": 46, "vegetation": 90, "water_quality": 90, "fish": 90, "birds": 60, "community": 90}
	state.bird_population = {"base": 60, "migrants": 0, "loss": 0, "season": "winter", "total": 60}
	state._set_bird_baseline(60)
	state.seasonal_legacy = []
	state.winter_returns = {}
	state.used_action_ids = []
	state.action_tiers = {}
	state.pending_crisis = {}
	state._is_settlement_preview = true
func _ready() -> void:
	var state = load("res://scripts/game_state.gd").new()
	var restored = load("res://scripts/game_state.gd").new()
	for mode in 4:
		fixture(state, mode)
		var line: int = [48, 51, 53, 54][mode]
		check(state.failure_threshold_for("birds") == line, "Opening sixty produces the chosen 80–90 percent redline")
		for at_turn in range(1, 17):
			state.turn = at_turn
			for visiting in [0, 4, 8, 20, 40]:
				state._apply_bird_state({"base": 40, "migrants": visiting, "loss": 0, "season": state.current_season(), "total": 40 + visiting}, "", "")
				check(state.failure_threshold_for("birds") == line and state.metric_display_line("birds") == line, "Bird damage, migration and seasons never move the redline")
				var saved: Dictionary = JSON.parse_string(JSON.stringify(state.serialize()))
				restored.load_state(saved, false)
				check(restored.bird_initial_residents == 60 and restored.failure_threshold_for("birds") == line, "JSON roundtrip preserves opening residents and fixed redline")
		fixture(state, mode)
		state._apply_bird_state({"base": 30, "migrants": line - 30, "loss": 0, "season": "winter", "total": line}, "", "")
		check(not state.check_failure_now(), "Combined total exactly on redline is safe even with low resident count")
		state._apply_delta("birds", -1, false)
		check(state.check_failure_now() and state.failure_value == line - 1, "Combined total one below redline fails")
		check(state.generate_report().failure_threshold == line and state.generate_report().failure_value == line - 1, "Report uses fixed line and combined total")
		fixture(state, mode)
		state.turn = 5 # Winter migrants leave during the spring natural phase.
		state.metrics.water_level = 52
		state._apply_bird_state({"base": 30, "migrants": 40, "loss": 0, "season": "winter", "year": 1, "total": 70}, "", "")
		check(not state.check_failure_now(), "Winter total is safe before migration")
		var hover: Dictionary = state.metric_hover_preview("birds")
		check(hover.break_nat and hover.break_total and hover.margin_nat < 0, "Hover warns when spring departure will take total below fixed line")
		var forecast: Dictionary = state.preview_settlement_detail([])
		state.end_turn()
		check(state.is_failure and state.failure_metric == "birds" and state.metrics.birds < line, "Actual seasonal departure can trigger combined-total failure")
		check(state.metrics.birds == forecast.metrics.birds and state.failure_threshold_for("birds") == line, "Migration preview matches actual failure with unchanged redline")
		fixture(state, mode)
		var legacy: Dictionary = state.serialize()
		legacy.erase("bird_initial_residents")
		legacy.erase("bird_fixed_redline")
		restored.load_state(legacy, false)
		check(restored.bird_initial_residents == 60 and restored.failure_threshold_for("birds") == line, "Old save freezes its resident baseline on first load")
		for seed_value in [61011, 61012, 61013]:
			state.difficulty = mode
			state.run_seed = seed_value
			state.reset_game()
			check(state.bird_initial_residents == state.bird_snapshot().base, "New run captures real opening residents after talents")
			check(state.failure_threshold_for("birds") == ceili(float(state.bird_initial_residents * state.BIRD_REDLINE_PERCENT[mode]) / 100.0), "Real opening redline follows chosen formula")
	state.free()
	restored.free()
	print("FIXED_BIRD_REDLINE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
