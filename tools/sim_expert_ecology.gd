extends SceneTree
## Paired seeds, real seven-card seasonal hands and real action/cost limits.
## Planned policies use the same settlement forecast available to the player.
var games := 100
var difficulty := 0
var label := "updated"
var full_tree := false   # 第 4 个参数传 "tree" 时，每局都按「满天赋树」跑（作者玩测时就是这个状态）
var state: Node
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: difficulty = int(args[0])
	if args.size() > 1: games = int(args[1])
	if args.size() > 2: label = str(args[2])
	# ⚠ args[3] 是作者原来留的 JSON 输出路径（见文件末尾），满树开关放第 5 个参数。
	if args.size() > 4: full_tree = str(args[4]) == "tree"
	call_deferred("run")
func health(node: Node, metric: String) -> int:
	if node.has_method("metric_failure_value"): return int(node.metric_failure_value(metric))
	return int(node.metric_health(metric)) if node.has_method("metric_health") else int(node.metrics[metric])
func value(node: Node) -> float:
	var result := 0.0
	var minimum := 100
	for metric in node.metrics:
		if metric == "water_level": continue
		var slack: int = health(node, metric) - int(node.failure_threshold_for(metric))
		minimum = mini(minimum, slack)
		result += clampf(float(slack), -30.0, 25.0)
	result += float(mini(minimum, 15)) * 5.0
	result -= float(node.water_pressure(int(node.metrics.water_level)).deviation) * 0.7
	if node.is_failure: result -= 10000.0
	return result + float(node.carry) * 0.04
func excluded(card: Dictionary, strategy: String) -> bool:
	var metric := "birds" if strategy == "ignore_birds" else "community"
	if strategy not in ["ignore_birds", "ignore_trust"]: return false
	for tier in card.tiers.values():
		for effect in tier.effects:
			if effect.metric == metric and int(effect.delta) > 0: return true
	return false
func choose(hand: Array, strategy: String) -> Dictionary:
	var best: Dictionary = {}
	var best_value := -1.0e20
	var options: Array = []
	var save: Dictionary = state.serialize().duplicate(true)
	for card in hand:
		if excluded(card, strategy): continue
		for tier in ["basic", "effective", "deep"]:
			if not state.can_execute(card.id, tier): continue
			if strategy == "random":
				options.append({"id": card.id, "tier": tier})
				continue
			var forecast: Node = state.get_script().new()
			forecast.load_state(save.duplicate(true), false)
			forecast._is_settlement_preview = true
			forecast.execute_action(card.id, tier)
			if not forecast.game_over: forecast.end_turn()
			var utility := value(forecast)
			if utility > best_value:
				best_value = utility
				best = {"id": card.id, "tier": tier}
			forecast.free()
	if strategy == "random" and not options.is_empty(): return options[randi() % options.size()]
	return best
func run() -> void:
	state = root.get_node("GameState")
	var talents: Node = root.get_node("Talents")
	var started := Time.get_ticks_msec()
	var all_results := {}
	for strategy in ["random", "planned", "ignore_birds", "ignore_trust"]:
		var wins := 0
		var turns := 0
		var deaths := {}
		var events := {}
		var conflicts := 0
		var bird_plays := 0
		var eco_score := 0.0
		var funding := 0
		# 每局记录「离红线最近的那一刻还差多少点」——胜率会被规划策略打满，这个量才看得出吃力不吃力。
		var run_slacks: Array = []
		var worst_marks: Dictionary = {}   # 最紧那一刻出现在第几回合、是哪一项（找「吃力」到底卡在哪）
		var worst_turns: Dictionary = {}
		var worst_metrics: Dictionary = {}
		for sample in games:
			talents.reset_all()
			if full_tree:
				# 「满天赋树」= 噩梦通关后的全树满级：本局加成来自 tree_ranks，
				# roll_for_run() 会把 mastery 展开成满级树（见 talents.gd:129）。
				talents.nightmare_mastery = true
			state.difficulty = difficulty
			state.run_seed = 1000 + sample
			state._is_settlement_preview = false
			state.reset_game()
			var worst_slack := 999
			while not state.game_over:
				funding += int(state.last_metric_funding)
				var hand: Array = state.draw_cards(7, state.is_season_opener())
				for slot in state.action_slots():
					var choice := choose(hand, strategy)
					if choice.is_empty(): break
					state.execute_action(choice.id, choice.tier)
					var played: Dictionary = state.card_by_id(choice.id)
					if excluded(played, "ignore_birds"): bird_plays += 1
					hand = hand.filter(func(c): return c.id != choice.id)
					if state.game_over: break
				if not state.game_over: state.end_turn()
				for metric in state.FAILURE_METRICS:
					var slack := int(state.metric_failure_value(metric)) - int(state.failure_threshold_for(metric))
					if slack < worst_slack:
						worst_slack = slack
						worst_marks["turn"] = int(state.turn)
						worst_marks["metric"] = str(metric)
				run_slacks.append(worst_slack)
				if not state.game_over: state.start_new_turn()
			var wt := int(worst_marks.get("turn", 0))
			worst_turns[wt] = int(worst_turns.get(wt, 0)) + 1
			var wm := str(worst_marks.get("metric", ""))
			worst_metrics[wm] = int(worst_metrics.get(wm, 0)) + 1
			turns += state.turn
			eco_score += float(state.generate_report().eco.score)
			if state.is_failure: deaths[state.failure_metric] = int(deaths.get(state.failure_metric, 0)) + 1
			else: wins += 1
			conflicts += state.conflict_history.size()
			for event in state.crisis_history: events[event.id] = int(events.get(event.id, 0)) + 1
		run_slacks.sort_custom(func(a, b): return int(a) < int(b))
		all_results[strategy] = {"wins": wins, "games": games, "win_rate": float(wins) / games,
			"slack_p10": int(run_slacks[mini(run_slacks.size() - 1, run_slacks.size() / 10)]) if not run_slacks.is_empty() else 999,
			"slack_median": int(run_slacks[run_slacks.size() / 2]) if not run_slacks.is_empty() else 999,
			"worst_turns": worst_turns, "worst_metrics": worst_metrics,
			"avg_turns": float(turns) / games, "deaths": deaths, "events": events,
			"conflicts_per_game": float(conflicts) / games, "bird_cards_per_game": float(bird_plays) / games,
			"avg_eco_score": eco_score / games, "avg_extra_funding": float(funding) / games}
		print("POLICY ", label, " difficulty=", difficulty, " ", strategy, " ", JSON.stringify(all_results[strategy]))
	var result := {"version": label, "difficulty": difficulty, "games_per_policy": games,
		"seed_start": 1000, "elapsed_ms": Time.get_ticks_msec() - started, "strategies": all_results}
	var args := OS.get_cmdline_user_args()
	if args.size() > 3:
		var output := FileAccess.open(str(args[3]), FileAccess.WRITE)
		output.store_string(JSON.stringify(result, "\t"))
	print("BALANCEJSON ", JSON.stringify(result))
	quit()
