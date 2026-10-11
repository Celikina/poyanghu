extends Node
var checks := 0
var failures := 0
var reports := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture(state: Node, mode: int, water: int) -> void:
	state.difficulty = mode
	state.turn = 4
	state.game_over = false
	state.is_failure = false
	state.failure_metric = ""
	state.metrics = {"water_level": water, "vegetation": 80, "water_quality": 80, "fish": 80, "birds": 80, "community": 80}
	state.bird_population = {"base": 80, "migrants": 0, "loss": 0, "season": "winter", "total": 80}
	state._set_bird_baseline(60)
	reports = 0
func _ready() -> void:
	var state = load("res://scripts/game_state.gd").new()
	state.game_ended.connect(func(_report): reports += 1)
	for mode in 4:
		for water in [0, 100]:
			fixture(state, mode, water)
			check(state.failure_threshold_for("water_level") == -1, "Water has no direct failure line")
			check(not state.check_failure_now() and not state.game_over and reports == 0, "Extreme water alone cannot end the run")
			check(state.metrics_below_threshold().is_empty(), "Extreme water omitted from failure report")
			for metric in state.FAILURE_METRICS:
				fixture(state, mode, water)
				var line: int = state.failure_threshold_for(metric)
				state.metrics[metric] = line
				if metric == "birds": state.bird_population.base = line
				check(not state.check_failure_now(), "Exact redline remains safe: " + metric)
				state.metrics[metric] = line - 1
				if metric == "birds":
					state.bird_population.base = line - 1
					state.bird_population.migrants = 40
					state.bird_population.total = line + 39
					state.metrics.birds = line + 39
					check(not state.check_failure_now(), "Resident and migrant total above redline remains safe")
					state.bird_population.migrants = 0
					state.bird_population.total = line - 1
					state.metrics.birds = line - 1
				check(state.check_failure_now() and state.is_failure and state.failure_metric == metric and reports == 1, "Each of five metrics can end the run; birds use total: " + metric)
				var below: Array = state.metrics_below_threshold()
				check(below.size() == 1 and below[0].metric == metric and below[0].value == line - 1, "Report matches failing metric: " + metric)
				state.check_failure_now()
				check(reports == 1, "Failure emitted only once")
	state.free()
	print("FIVE_METRIC_FAILURE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
