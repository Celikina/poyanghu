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
	state.funds = 500
	state.run_seed = 20261011
	var rule: Dictionary = state.water_reference()
	state.metrics = {"water_level": (int(rule.low) + int(rule.high)) / 2, "water_quality": 90, "vegetation": 90, "fish": 90, "birds": 55, "community": 80}
	state.bird_population = {}
	state.used_action_ids = []
	state.action_tiers = {}
	state._is_settlement_preview = true
func _ready() -> void:
	var state = load("res://scripts/game_state.gd").new()
	var actual = load("res://scripts/game_state.gd").new()
	var events: Array = state.CRISES.filter(func(c): return c.get("seasonal_social", false))
	check(events.size() == 14, "All fourteen expert events are implemented")
	check(_unique_count(events) == 14, "Event identifiers are unique")
	for difficulty in 4:
		for event in events:
			var at_turn: int = state.SEASONS.find(event.season) + 1
			fixture(state, difficulty, at_turn)
			var counters: Array = state.season_pool().filter(func(c): return state.counter_ids_for(event).has(c.id))
			check(not counters.is_empty(), "Every event has a counter in the actual seasonal pool")
			var response_id: String = counters[0].id
			for tier in ["none", "basic", "effective", "deep"]:
				fixture(state, difficulty, at_turn)
				state.pending_crisis = event.duplicate(true)
				var queue: Array = []
				if tier != "none": queue.append({"card_id": response_id, "tier": tier})
				var saved: Dictionary = state.serialize().duplicate(true)
				var preview: Dictionary = state.preview_settlement(queue)
				check(state.serialize() == saved, "Event forecast is read-only")
				actual.load_state(saved, false)
				actual._is_settlement_preview = true
				if tier != "none": actual.execute_action(response_id, tier)
				var expected: float = 0.0 if tier == "none" else state.SEASONAL_MITIGATION[tier]
				check(is_equal_approx(actual.crisis_mitigation(event), expected), "Card tier controls mitigation")
				actual.record_crisis_notice(event, 1, actual.turn - 1)
				actual.end_turn()
				check(actual.metrics == preview, "Forecast equals actual mitigated settlement")
				var history: Dictionary = actual.warn_history[0].crisis
				check(is_equal_approx(float(history.mitigation_ratio), expected), "Review retains mitigation")
				for effect in history.effects:
					var raw: int = event.effects.filter(func(e): return e.metric == effect.metric)[0].delta
					check(int(effect.delta) == roundi(raw * (1.0 - expected)), "Actual damage uses rounded mitigation without difficulty multiplier")
				for effect in history.legacy_effects:
					var raw: int = event.legacy_effects.filter(func(e): return e.kind == effect.kind)[0].delta
					check(int(effect.delta) == roundi(raw * (1.0 - expected)), "Food and water legacies use the same real mitigation")
				var recorded: Dictionary = history.duplicate(true)
				actual.restore_crisis_notices(actual.turn)
				check(actual.warn_history[0].crisis == recorded, "History restoration retains actual mitigation and legacy effects")
				if tier == "deep": check(not actual.is_failure, "Full counter prevents event damage near trust redline")
			fixture(state, difficulty, at_turn)
			state.pending_crisis = event
			for sample in 30:
				seed(9000 + sample)
				var hand: Array = state.draw_cards(7, true)
				check(hand.any(func(c): return state.counter_ids_for(event).has(c.id)), "Seasonal warning hand has a usable counter")
				check(hand.size() == 7 and _unique_count(hand) == 7, "Guarantee preserves hand size and uniqueness")
				check(hand.any(func(c): return c.season == state.current_season()), "Guarantee preserves seasonal card")
		fixture(state, difficulty, 3)
		var line: int = state.failure_threshold_for("community")
		for pair in [[line, 0.6], [line + 4, 0.6], [line + 5, 0.3], [line + 9, 0.3], [line + 10, 0.08]]:
			state.metrics.community = pair[0]
			check(is_equal_approx(state.seasonal_social_chance(), pair[1]), "Risk bands follow difficulty and handle exact boundaries")
		state.metrics.community = line + 5
		var hits := 0
		seed(61011)
		for sample in 1000:
			var event: Dictionary = state._roll_crisis(3)
			if not event.is_empty():
				hits += 1
				check(event.get("season", "") == "winter", "Autumn warning only selects winter seasonal events")
		check(hits >= 250 and hits <= 350, "Thirty percent risk band passes frequency check")
		state.crisis_history = [{"id": "winter_poaching", "turn": 4}]
		for event in events:
			if event.season == "winter": state.crisis_history.append({"id": event.id, "turn": 4})
		for sample in 30: check(state._roll_crisis(7).is_empty(), "Seasonal events obey shared cooldown")
		for warn_turn in range(4, 8):
			fixture(state, difficulty, warn_turn)
			state.metrics.community = state.failure_threshold_for("community") + 5
			var seen := {}
			for sample in 150:
				var selected: Dictionary = state._roll_crisis(warn_turn)
				if selected.is_empty(): continue
				check(selected.season == state.SEASONS[warn_turn % 4], "Event warning uses the hit season across the year boundary")
				seen[selected.id] = true
			var expected_events: Array = events.filter(func(c): return c.season == state.SEASONS[warn_turn % 4])
			check(seen.size() == expected_events.size(), "Every event can be drawn through the real shared queue")
	fixture(state, 2, 4)
	state.pending_crisis = state.crisis_by_id("winter_poaching")
	state.bird_population = {"base": 55, "migrants": 3, "loss": 0, "season": "winter", "total": 58}
	state.metrics.birds = 58
	state._resolve_pending_crisis()
	check(state.metric_health("birds") == 55 and state.metrics.birds == 55, "Poaching cannot remove nonexistent migrants or damage base")
	check(state.warn_history[0].crisis.effects[0].delta == -3, "Review reports actual truncated migrant loss")
	fixture(state, 2, 4)
	state.pending_crisis = state.crisis_by_id("winter_poaching")
	state.execute_action("patrol", "effective")
	var save: Dictionary = state.serialize().duplicate(true)
	actual.load_state(save, false)
	check(actual.action_tiers == state.action_tiers and actual.crisis_effects(actual.pending_crisis) == state.crisis_effects(state.pending_crisis), "Reload retains counter tier")
	check(events.all(func(c): return not c.has("mitigation_ratio") and not c.has("legacy_settled")), "Shared event catalog remains unchanged after all settlements")
	state.free()
	actual.free()
	print("SEASONAL_EVENTS checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
func _unique_count(hand: Array) -> int:
	var ids := {}
	for c in hand: ids[c.id] = true
	return ids.size()
