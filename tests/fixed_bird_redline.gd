extends Node
var checks := 0
var failures := 0
var line := 0   # 当前 fixture 这一局抽到的候鸟红线：每次 fixture() 都会重抽并记在这里
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
	line = int(state.bird_fixed_redline)
func _ready() -> void:
	var state = load("res://scripts/game_state.gd").new()
	var restored = load("res://scripts/game_state.gd").new()
	for mode in 4:
		fixture(state, mode)
		# 下限直接问代码要，别在这里抄一份表（0.1.29 重构红线时抄的那份就过期了）
		var floor_line: int = int(state.base_metric_line("birds"))
		check(line >= floor_line and line <= state.bird_redline_cap(60),
			"Opening sixty rolls a redline between the difficulty line and eighty-five percent of residents")
		# 上限：留湖偏小时 85% 会先咬人（向下取整），这时线就是上限本身。
		for residents in [48, 51, 60]:
			state.metrics.birds = residents
			state._set_bird_baseline(residents)
			var rolled: int = state.bird_fixed_redline
			check(rolled <= state.bird_redline_cap(residents), "The roll never exceeds eighty-five percent of the opening residents")
			check(rolled >= mini(floor_line, state.bird_redline_cap(residents)), "The roll never drops below the difficulty line unless the cap itself is tighter")
		# 同一局里预览 / 悬停 / 读档都不能重抽（重抽会动随机序列，也会让线在回合中变来变去）。
		fixture(state, mode)
		state.preview_settlement([])
		state.metric_hover_preview("birds")
		check(state.failure_threshold_for("birds") == line, "Forecasting and hovering never re-roll the redline")
		for at_turn in range(1, 17):
			state.turn = at_turn
			for visiting in [0, 4, 8, 20, 40]:
				state._apply_bird_state({"base": 40, "migrants": visiting, "loss": 0, "season": state.current_season(), "total": 40 + visiting}, "", "")
				check(state.failure_threshold_for("birds") == line and state.metric_display_line("birds") == line, "Bird damage, migration and seasons never move the redline")
				var saved: Dictionary = JSON.parse_string(JSON.stringify(state.serialize()))
				restored.load_state(saved, false)
				check(restored.bird_initial_residents == 60 and restored.failure_threshold_for("birds") == line, "JSON roundtrip preserves opening residents and fixed redline")
		fixture(state, mode)
		var low_base: int = maxi(5, line - 10)
		state._apply_bird_state({"base": low_base, "migrants": line - low_base, "loss": 0, "season": "winter", "total": line}, "", "")
		check(not state.check_failure_now(), "Combined total exactly on redline is safe even with low resident count")
		state._apply_delta("birds", -1, false)
		check(state.check_failure_now() and state.failure_value == line - 1, "Combined total one below redline fails")
		check(state.generate_report().failure_threshold == line and state.generate_report().failure_value == line - 1, "Report uses fixed line and combined total")
		fixture(state, mode)
		state.turn = 5 # Winter migrants leave during the spring natural phase.
		state.metrics.water_level = 52
		state._apply_bird_state({"base": maxi(5, line - 12), "migrants": 40, "loss": 0, "season": "winter", "year": 1,
			"total": maxi(5, line - 12) + 40}, "", "")
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
		check(restored.bird_initial_residents == 60
			and restored.failure_threshold_for("birds") == state.bird_redline_cap(60),
			"Old save freezes its resident baseline and takes the eighty-five percent cap instead of re-rolling")
		for seed_value in [61011, 61012, 61013]:
			state.difficulty = mode
			state.run_seed = seed_value
			state.reset_game()
			check(state.bird_initial_residents == state.bird_snapshot().base, "New run captures real opening residents after talents")
			var opened: int = int(state.failure_threshold_for("birds"))
			check(opened >= state.base_metric_line("birds") or opened == state.bird_redline_cap(state.bird_initial_residents),
				"Real opening redline starts from the shared difficulty line")
			check(opened <= state.bird_redline_cap(state.bird_initial_residents), "Real opening redline stays under eighty-five percent of residents")
	state.free()
	restored.free()
	print("FIXED_BIRD_REDLINE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
