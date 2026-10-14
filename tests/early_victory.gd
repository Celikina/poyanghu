extends Node
## 提前胜利（0.1.29）：五项达标并连续保持两个回合；末尾在真实主场景里渲染一次结算页。
##
## 与 tools/prepare_visual_test.py early_victory 配套跑在隔离副本里：真窗口，
## 截图目录由 POYANG_SCREENSHOT_DIR 给。
const State := preload("res://scripts/game_state.gd")
var checks := 0
var failures := 0
var game: Node
var output_dir := OS.get_environment("POYANG_SCREENSHOT_DIR")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func wait_for(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func capture(label: String) -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(label + ".png"))


## 把状态摆成「生态全面恢复」：水位落在当季参考区间中点，四项拉满、留湖基数顶格，
## 清掉预警中的危机与预告（否则紧接着的危机结算会把指标打回线内）。
func green_fixture(state: Node, at_turn: int) -> void:
	var rule: Dictionary = state.water_reference()
	state.turn = at_turn
	state.metrics = {
		"water_level": int((int(rule["low"]) + int(rule["high"])) / 2),
		"vegetation": 100, "water_quality": 100, "fish": 100, "birds": 60, "community": 100,
	}
	state.bird_population = {"base": 60, "migrants": 0, "loss": 0,
		"season": state.current_season(), "total": 60}
	state.pending_crisis = {}
	state.forecast_crisis = {}
	state.used_action_ids = []
	state.game_over = false
	state.is_failure = false


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var state := State.new()
	state.reset_game()
	Talents.reset_all()
	state.difficulty = 0                 # 简单档：水位参考区间不收窄
	state.run_seed = 20261011
	state._is_settlement_preview = false

	# ---- ① 门槛：严格高于 80，候鸟看留湖基数而不是总量 ----
	green_fixture(state, 1)
	state.metrics["vegetation"] = 80
	check(not state.early_win_met(), "恰好 80 不算达标(要求严格高于 80)")
	state.metrics["vegetation"] = 81
	check(state.early_win_met(), "五项都高于 80 且留湖顶格时达标")
	state.bird_population["base"] = 54
	state.bird_population["total"] = 54
	state.metrics["birds"] = 54
	check(not state.early_win_met(), "留湖基数 54 还没到线")
	state.bird_population["base"] = 55
	state.bird_population["total"] = 55
	state.metrics["birds"] = 55
	check(state.early_win_met(), "留湖基数 55 起达标")
	state.bird_population["base"] = 60
	state.bird_population["migrants"] = 0
	state.bird_population["total"] = 60
	state.metrics["birds"] = 60
	check(state.early_win_met(), "夏季总量只有 60 也达标(判的是留湖基数，与季节来客无关)")
	check(state.early_win_missing().is_empty(), "达标时没有缺项")

	# ---- ② 连续两个回合的结算才通关 ----
	green_fixture(state, 1)
	state.early_win_streak = 0
	state.end_turn()
	check(not state.game_over, "第一回合达标不立刻通关")
	check(state.early_win_streak == 1, "第一回合之后连续计数为 1，实际 %d" % state.early_win_streak)
	green_fixture(state, 2)
	state.end_turn()
	check(state.game_over and not state.is_failure, "连续两个回合后提前通关(不是判负)")
	var report: Dictionary = state.generate_report()
	check(bool(report["victory"]) and int(report["turns_survived"]) < state.TOTAL_TURNS,
		"报告记为提前胜利且回合数小于 16，实际 %d" % int(report["turns_survived"]))

	# ---- ③ 中途掉回线内 → 计数清零 ----
	green_fixture(state, 3)
	state.early_win_streak = 1
	state.metrics["fish"] = 60
	state.end_turn()
	check(state.early_win_streak == 0 and not state.game_over, "有一项掉回线内 → 计数清零、不通关")

	# ---- ④ 最后一回合走自然通关，不报「提前」 ----
	green_fixture(state, state.TOTAL_TURNS)
	state.early_win_streak = 1
	state.end_turn()
	var final_report: Dictionary = state.generate_report()
	check(state.game_over and int(final_report["turns_survived"]) == state.TOTAL_TURNS,
		"第 16 回合仍是打满回合的通关，turns_survived=%d" % int(final_report["turns_survived"]))

	# ---- ⑤ 预览 / 悬停推演不推进计数 ----
	green_fixture(state, 5)
	state.early_win_streak = 1
	state._is_settlement_preview = true
	state.end_turn()
	state._is_settlement_preview = false
	check(state.early_win_streak == 1 and not state.game_over, "预览结算不推进提前胜利计数")

	# ---- ⑥ 连续计数进存档、读档能接上 ----
	state.early_win_streak = 1
	var save: Dictionary = state.serialize()
	check(int(save.get("early_win_streak", -1)) == 1, "连续计数写进存档")
	var restored := State.new()
	restored.load_state(save, false)
	check(restored.early_win_streak == 1, "读档恢复连续计数")
	check(int(restored.serialize().get("early_win_streak", -1)) == 1, "再次存盘仍是 1")

	# ---- ⑦ 真实主场景：把提前胜利的结算页渲染出来 ----
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	game = scene.get_node("Game")
	add_child(scene)
	await wait_for(0.6)
	if game._intro_playing: game._finish_intro()
	game._on_title_start()
	game._on_difficulty_pick(0)
	game.seed_input.text = "20261011"
	game._on_start_pressed()
	await wait_for(1.0)
	for i in 60:
		if game.popup_root.visible: game._on_popup_button()
		if game._current_phase == "allocate" and not game.popup_root.visible: break
		await wait_for(0.06)
	# 摆成「打到第 8 回合、生态全面恢复」的局面，再走真实的 _show_report
	GameState.turn = 8
	GameState.difficulty = 0
	GameState.metrics = {"water_level": 55, "vegetation": 92, "water_quality": 90,
		"fish": 88, "birds": 100, "community": 93}
	GameState.bird_population = {"base": 60, "migrants": 40, "loss": 0, "season": "winter", "total": 100}
	GameState.total_spent = 430
	GameState.research_points = 6
	GameState.game_over = true
	GameState.is_failure = false
	game._show_report(GameState.generate_report())
	# 报告正文是逐字显示的，等它写完再截图，否则只能拍到半句
	await wait_for(4.5)
	game.popup_body.visible_characters = -1
	await wait_for(0.4)
	check(game.popup_title.text.contains("提前胜利"),
		"结算页标题是「提前胜利 · 生态报告」，实际「%s」" % game.popup_title.text)
	check(game.popup_body.text.contains("灵感"),
		"结算页正文带上通关灵感那一行")
	await capture("early-victory-report")

	print("EARLY_VICTORY checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
