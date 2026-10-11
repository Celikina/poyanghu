extends Node
const Model := preload("res://scripts/bird_population.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture(state: Node, difficulty: int, at_turn: int, base: int = 55) -> void:
	state.reset_game()
	Talents.reset_all()
	state.difficulty = difficulty
	state.turn = at_turn
	state.run_seed = 20261011
	var rule: Dictionary = state.water_reference()
	state.metrics = {"water_level": (int(rule.low) + int(rule.high)) / 2, "water_quality": 70, "vegetation": 65, "fish": 70, "birds": base, "community": 75}
	state.bird_population = {"base": base, "migrants": 0, "loss": 0, "season": state.current_season(), "total": base}
	state._set_bird_baseline(55)
	state.used_action_ids = ["water_monitor", "patrol"]
	state.action_tiers = {}
	state._is_settlement_preview = true
func _ready() -> void:
	var state = load("res://scripts/game_state.gd").new()
	var actual = load("res://scripts/game_state.gd").new()
	for difficulty in 4:
		for at_turn in range(1, 17):
			fixture(state, difficulty, at_turn)
			var saved: Dictionary = state.serialize().duplicate(true)
			seed(9812)
			var random_expected := randi()
			seed(9812)
			var preview: Dictionary = state.preview_settlement([])
			check(state.serialize() == saved and randi() == random_expected, "Forecast preserves state and RNG")
			actual.load_state(saved, false)
			actual._is_settlement_preview = true
			actual.end_turn()
			check(preview == actual.metrics, "Forecast equals settlement in every season/year/difficulty")
			var hover: Dictionary = state.metric_hover_preview("birds")
			check(actual.metrics.birds >= hover.end_min and actual.metrics.birds <= hover.end_max, "Abundance is within hover forecast range")
			check(actual.metric_health("birds") >= hover.health_min and actual.metric_health("birds") <= hover.health_max, "Health is within hover forecast range")
			check(actual.score_ledger.filter(func(e): return e.metric == "birds" and e.phase == "routine").size() == 1, "Natural bird settlement uses one combined entry")
		var seasons: Array[int] = []
		for season in state.SEASONS:
			var projected: Dictionary = Model.project(Model.snapshot({}, 55, season), season, 72, 1.0)
			seasons.append(int(projected.total))
		check(seasons[3] > seasons[2] and seasons[2] > seasons[0] and seasons[0] > seasons[1], "Equivalent habitats have winter peak and summer minimum")
		fixture(state, difficulty, 1, state.failure_threshold_for("birds") + 4)
		state.bird_population.migrants = 30
		state.bird_population.total += 30
		state.bird_population.season = "winter"
		state.metrics.birds = state.bird_population.total
		state.natural_evolution()
		check(not state.check_failure_now(), "Normal departure cannot kill a healthy base")
		fixture(state, difficulty, 4, state.failure_threshold_for("birds") - 1)
		state.bird_population.migrants = 30
		state.bird_population.total += 30
		state.metrics.birds = state.bird_population.total
		check(not state.check_failure_now(), "Migrants count toward the fixed redline")
		# 来客按真实回合末那样迁走（红线以内掉下去），而不是硬扣 30 —— 留湖不足 30 时
		# 扣值会先把留湖吃光，总数反而还在线上。
		state._apply_bird_state({"base": state.failure_threshold_for("birds") - 1, "migrants": 0, "loss": 0,
			"season": state.current_season(), "total": state.failure_threshold_for("birds") - 1}, "", "")
		check(state.check_failure_now() and state.failure_metric == "birds", "Combined total below the fixed redline fails")
	fixture(state, 2, 4)
	check(Model.habitat({"vegetation": 35, "water_quality": 100, "fish": 80}, 0) <= 39, "Weighted average cannot hide food shortage")
	var harmed: Dictionary = Model.change(Model.project(state.bird_snapshot(), "winter", 72, 1.0), -12, true)
	var repeated: Dictionary = Model.project(harmed, "winter", 72, 1.0)
	check(repeated.loss == 12 and repeated.migrants == harmed.migrants, "Seasonal recomputation retains actual injuries")
	var rescued: Dictionary = Model.change(harmed, 6, false, true)
	check(rescued.loss == 6 and rescued.total == harmed.total + 6, "Rescue recovers harmed migrants")
	state._apply_bird_state(harmed, "crisis", "test")
	var save: Dictionary = state.serialize().duplicate(true)
	actual.load_state(save, false)
	check(actual.bird_snapshot() == state.bird_snapshot() and actual.preview_settlement([]) == state.preview_settlement([]), "Reload preserves health and injuries")
	actual.load_state(JSON.parse_string(JSON.stringify(save)), false)
	check(actual.bird_snapshot() == state.bird_snapshot(), "JSON save roundtrip preserves bird health and injuries")
	var incomplete := Model.snapshot({"base": 55, "migrants": 10, "total": 65}, 65, "winter")
	check(incomplete.loss == 0 and Model.project(incomplete, "winter", 72, 1.0).total > 0, "Incomplete bird state receives safe migration defaults")
	var legacy: Dictionary = save.duplicate(true)
	legacy.erase("bird_population")
	actual.load_state(legacy, false)
	check(actual.metrics.birds == save.metrics.birds and actual.metric_health("birds") >= state.metric_health("birds"), "Legacy load preserves total without inventing health damage")
	fixture(state, 2, 2)
	state.funds = 500
	state.used_action_ids = []
	var before: int = state.metric_health("birds")
	actual.load_state(state.serialize(), false)
	actual.natural_evolution()
	state.execute_action("waterbird_food_supply", "deep")
	state.natural_evolution()
	check(state.metric_health("birds") <= Model.BASE_CAP and state.metric_health("birds") > actual.metric_health("birds") and state.metric_health("birds") >= before, "Card protection persists through environmental recomputation up to the sixty-point cap")
	fixture(state, 2, 2)
	var income: int = state._metric_funding()
	var score: Dictionary = state._eval_eco()
	state.bird_population.migrants = 30
	state.bird_population.total += 30
	state.metrics.birds = state.bird_population.total
	check(state._metric_funding() == income and state._eval_eco().score == score.score, "Visitors cannot manufacture funding or conservation score")
	fixture(state, 2, 2, 59)
	state._apply_delta("birds", 10, true, "card", "protection", "waterbird_food_supply")
	check(state.score_ledger.back().raw == 10 and state.score_ledger.back().applied == 1, "Capped protection retains requested and actual ledger values")
	fixture(state, 2, 4, 49)
	state.bird_population.migrants = 30
	state.bird_population.total = 79
	state.metrics.birds = 79
	check(state._build_reflection().contains("候鸟食物供给被牺牲"), "Final reflection evaluates health rather than winter visitors")
	state.free()
	actual.free()
	print("BIRD_MIGRATION checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
