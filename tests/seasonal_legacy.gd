extends Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture(state: Node, difficulty: int, at_turn: int) -> void:
	state.reset_game()
	Talents.reset_all()
	state.difficulty = difficulty
	state.turn = at_turn
	state.run_seed = 20261011
	state.funds = 500
	state.turn_budget = 500
	var rule: Dictionary = state.water_reference()
	state.metrics = {"water_level": (int(rule.low) + int(rule.high)) / 2, "vegetation": 90, "water_quality": 90, "fish": 90, "birds": 55, "community": 80}
	state.bird_population = {}
	state.action_tiers = {}
	state.used_action_ids = []
	state._is_settlement_preview = true
func _ready() -> void:
	var state = load("res://scripts/game_state.gd").new()
	var control = load("res://scripts/game_state.gd").new()
	for difficulty in 4:
		for id in ["summer_sand_mining", "summer_water_dispute"]:
			for tier in ["none", "basic", "effective", "deep"]:
				fixture(state, difficulty, 2)
				state.pending_crisis = state.crisis_by_id(id).duplicate(true)
				var queue: Array = []
				var response: String = state.season_pool().filter(func(c): return state.counter_ids_for(state.pending_crisis).has(c.id))[0].id
				if tier != "none": queue.append({"card_id": response, "tier": tier})
				var before: Dictionary = state.serialize().duplicate(true)
				var preview: Dictionary = state.preview_settlement_detail(queue)
				check(state.serialize() == before, "Legacy preview is read-only")
				for choice in queue: state.execute_action(choice.card_id, choice.tier)
				state.end_turn()
				check(state.metrics == preview.metrics and state.pending_water_legacy() == preview.water_legacy, "Legacy forecast equals actual end-of-turn state")
				var shift: int = state.pending_water_legacy()
				check(shift == (-5 if tier == "none" else (-3 if tier == "basic" else (-1 if tier == "effective" else 0))), "Water legacy is mitigated and rounded once")
				var summer_level: int = state.metrics.water_level
				control.load_state(JSON.parse_string(JSON.stringify(state.serialize())), false)
				control._is_settlement_preview = true
				state.start_new_turn()
				control.start_new_turn()
				check(state.metrics.water_level == clampi(summer_level + shift, 0, 100), "Water legacy occurs at autumn start")
				check(state.metrics == control.metrics and state.seasonal_legacy == control.seasonal_legacy, "JSON reload preserves due-turn processing")
				check(state.pending_water_legacy() == 0, "Consumed water legacy is removed")
				var autumn_level: int = state.metrics.water_level
				state.start_new_turn()
				check(state.metrics.water_level == autumn_level, "Water debt never repeats in winter")
		fixture(state, difficulty, 1)
		state.pending_crisis = state.crisis_by_id("spring_overgrazing").duplicate(true)
		var vegetation: int = state.metrics.vegetation
		var base: int = state.metric_health("birds")
		state._resolve_pending_crisis()
		check(state.metrics.vegetation == vegetation and state.metric_health("birds") == base, "Grazing does not masquerade as submerged plants or direct base damage")
		check(state.wetland_food_loss() == 10 and state.wetland_food_loss(4) == 10, "Spring food damage persists through winter")
		control.load_state(state.serialize().duplicate(true), false)
		control.seasonal_legacy.clear()
		check(state.bird_evolution(state.metrics).habitat < control.bird_evolution(control.metrics).habitat, "Food damage affects the shared bird habitat")
		state.execute_action("veg_restore", "effective")
		check(state.wetland_food_loss() == 6, "Existing restoration cards restore four food points at effective tier")
		state.turn = 4
		state.start_new_turn()
		check(state.wetland_food_loss() == 0, "Annual food damage expires at the next spring")
		for id in ["winter_poaching", "bird_conflict", "winter_drone_disturbance"]:
			fixture(state, difficulty, 4)
			state.bird_population = {"base": 55, "migrants": 32, "loss": 0, "season": "winter", "total": 87}
			state.metrics.birds = 87
			state.pending_crisis = state.crisis_by_id(id).duplicate(true)
			state._resolve_pending_crisis()
			var lost: int = state.bird_snapshot().loss
			check(state.metric_health("birds") == 55, "All three winter bird events only harm migrants")
			state.start_new_turn()
			check(state.winter_return_loss() == ceili(lost * 0.5), "Unrecovered winter injuries carry once into the next year")
			state.turn = 8
			control.load_state(state.serialize().duplicate(true), false)
			control.winter_returns.clear()
			check(control.bird_evolution(control.metrics).migrants - state.bird_evolution(state.metrics).migrants == ceili(lost * 0.5), "Next winter arrivals retain the prior winter loss")
			state.natural_evolution()
			state.start_new_turn()
			check(state.winter_return_loss() == 0, "Uninjured next winter does not regenerate older debt")
	fixture(state, 2, 4)
	state.bird_population = {"base": 55, "migrants": 32, "loss": 0, "season": "winter", "total": 87}
	state.metrics.birds = 87
	state.pending_crisis = state.crisis_by_id("winter_poaching").duplicate(true)
	state._resolve_pending_crisis()
	state.execute_action("rescue", "deep")
	state.start_new_turn()
	check(state.winter_return_loss() == 3, "Winter rescue lowers next-year loss")
	state.funds = 500
	state.execute_action("rescue", "effective")
	check(state.winter_return_loss() == 2, "Early spring rescue credits unfinished winter recovery")
	state.seasonal_legacy = [{"kind": "food", "delta": -10, "until_turn": 8}]
	var before_repair: int = state.metrics.birds
	state.execute_action("wetland_restore", "effective")
	check(state.metrics.birds >= before_repair, "Spring restoration is not blamed for normal winter departure")
	fixture(state, 2, 4)
	state.bird_population = {"base": 55, "migrants": 32, "loss": 0, "season": "winter", "total": 87}
	state.metrics.birds = 87
	state.start_new_turn()
	check(state.winter_return_loss() == 0, "Normal seasonal departure never becomes mortality debt")
	fixture(state, 2, 2)
	state.pending_crisis = state.crisis_by_id("summer_sand_mining").duplicate(true)
	state._resolve_pending_crisis()
	state.metrics.water_level = 2
	state.start_new_turn()
	check(state.metrics.water_level == 0 and state.warn_history[0].crisis.legacy_settled[0].delta == -2, "Review reports clamped actual delayed water loss")
	var history: Dictionary = state.warn_history[0].crisis.duplicate(true)
	state.restore_crisis_notices(state.turn)
	check(state.warn_history[0].crisis == history, "History restoration cannot overwrite settled legacies")
	fixture(state, 2, 1)
	for i in 4:
		state.pending_crisis = state.crisis_by_id("spring_overgrazing").duplicate(true)
		state._resolve_pending_crisis()
	check(state.wetland_food_loss() == 30, "Food impairment is bounded at thirty points")
	var legacy: Dictionary = state.serialize()
	legacy.erase("seasonal_legacy")
	legacy.erase("winter_returns")
	control.load_state(legacy, false)
	check(control.wetland_food_loss() == 0 and control.winter_return_loss() == 0, "Old saves do not acquire invented legacies")
	fixture(state, 2, 4)
	state.bird_population = {"base": 60, "migrants": 40, "loss": 0, "season": "winter", "year": 1, "total": 100}
	state.metrics.birds = 100
	state.pending_crisis = state.crisis_by_id("winter_poaching").duplicate(true)
	state._resolve_pending_crisis()
	check(state.bird_evolution(state.metrics).migrants == 28, "Same-winter recalculation cannot refill injuries hidden by the total cap")
	state.execute_action("rescue", "deep")
	check(state.bird_evolution(state.metrics).migrants == 34, "Rescued migrants remain recovered at the total cap")
	state.start_new_turn()
	state.turn = 8
	check(state.bird_evolution(state.metrics).migrants == 37, "Next-year return debt also remains visible at the total cap")
	state.reset_game()
	check(state.seasonal_legacy.is_empty() and state.winter_returns.is_empty(), "New game clears all cross-season state")
	state.free()
	control.free()
	print("SEASONAL_LEGACY checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
