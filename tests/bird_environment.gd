extends Node
const Model := preload("res://scripts/bird_population.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _ready() -> void:
	var healthy: Dictionary = Model.anchor_environment({"base": 60, "migrants": 40, "loss": 0, "season": "winter", "year": 1, "total": 100}, 80)
	for habitat in range(101):
		var coefficient: float = Model.environment_coefficient(habitat)
		var base := roundi(60.0 * coefficient)
		for season in Model.SEASON_CAPACITY:
			var capacity: int = Model.SEASON_CAPACITY[season]
			var result: Dictionary = Model.project(healthy, season, habitat, 1.0, 0, 1)
			check(result.base == base and result.migrants == roundi(float(capacity) * coefficient), "B and M use exactly the same environmental coefficient")
			check(result.base >= 0 and result.base <= 60 and result.migrants >= 0 and result.migrants <= 40 and result.total == result.base + result.migrants and result.total <= 100, "Population bounds and sum hold in every habitat and season")
			var repeated := Model.project(result, season, habitat, 2.0, 0, 1)
			check(repeated == result, "Unchanged habitat is not charged again or multiplied only for B")
			var loaded: Dictionary = Model.snapshot(JSON.parse_string(JSON.stringify(result)), result.total, season)
			check(loaded == result and Model.project(loaded, season, habitat, 1.5, 0, 1) == result, "Integer environmental reference survives JSON without rounding drift")
	var full := Model.project(healthy, "winter", 100, 1.0, 0, 1)
	check(full.base == 60 and full.migrants == 40 and full.total == 100, "Excellent habitat admits all forty winter migrants")
	var half := Model.project(healthy, "winter", 50, 1.0, 0, 1)
	check(half.base == 30 and half.migrants == 20 and half.total == 50, "Half suitability affects each population by the same fifty percent")
	var capped := Model.project(Model.anchor_environment({"base": 55, "migrants": 20, "loss": 0, "season": "winter", "total": 75}, 50), "winter", 80, 1.0)
	var receded := Model.project(capped, "winter", 50, 1.0)
	check(capped.base == 60 and receded.base == 30 and receded.migrants == 20, "The cap cannot store invisible surplus that masks later environmental losses")
	var poor := Model.project(healthy, "winter", 23, 1.0, 0, 1)
	check(poor.base == 3 and poor.migrants == 2, "Very poor habitat attracts almost no winter migrants")
	var saved: Dictionary = healthy.duplicate(true)
	for season in ["spring", "summer", "autumn", "winter"]:
		saved = Model.project(saved, season, 80, 1.0, 0, 1)
		check(saved.base == 60 and saved.migrants == Model.SEASON_CAPACITY[season], "Seasonal departure changes only M under equal habitat")
	var fish_low := {"vegetation": 80, "water_quality": 80, "fish": 0}
	var fish_high := fish_low.duplicate()
	fish_high.fish = 100
	check(Model.habitat(fish_low, 0) == Model.habitat(fish_high, 0), "Environmental coefficient only reads plants, water quality and water level")
	var injured := Model.change(full, -12, true)
	check(Model.project(injured, "winter", 100, 1.0, 0, 1).migrants == 28, "Repeated favorable habitat cannot erase actual injuries")
	var rescued := Model.change(injured, 6, false, true)
	check(Model.project(rescued, "winter", 100, 1.0, 0, 1).migrants == 34, "Rescue remains effective through environmental recalculation")
	var investment := Model.change(half, 6)
	check(Model.project(investment, "winter", 50, 1.0, 0, 1).base == 36, "Resident card investment persists at unchanged habitat")
	var legacy := Model.snapshot({"base": 80, "migrants": 20, "loss": 12, "season": "winter", "year": 1, "total": 100}, 100, "winter")
	check(legacy.base == 60 and legacy.migrants == 40 and legacy.total == 100 and legacy.loss == 12 and legacy.year == 1, "Previous eighty-point base saves retain total, injury and year")
	for mode in 4:
		for seed_value in range(10):
			GameState.difficulty = mode
			GameState.run_seed = 61000 + seed_value
			GameState.reset_game()
			check(GameState.metrics.birds <= 60 and GameState.bird_snapshot().migrants == 0, "New run never invents migrants from a base above sixty")
	print("BIRD_ENVIRONMENT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
