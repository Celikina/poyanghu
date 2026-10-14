extends Node
## 壳层手感四件事的验收：碎片配色 / 科研点提示 / 金币与科研点可戳 / 暂停设置的返回按钮。
## 与其它 visual 测试同一套约定：独立副本、真窗口跑、末尾打一行汇总。
var checks := 0
var failures: Array[String] = []
var game: Node


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func find_button(node: Node, text: String) -> Button:
	for c in node.get_children():
		if c is Button and c.text == text:
			return c
		var found: Button = find_button(c, text)
		if found != null:
			return found
	return null


func poke_check(label: String, icon: TextureRect, target: float) -> void:
	check(icon.mouse_filter == Control.MOUSE_FILTER_STOP, "%s 图标必须接住鼠标" % label)
	check(is_equal_approx(icon.hover_target, target), "%s 图标的悬停倍数应为 %.2f" % [label, target])
	icon.mouse_entered.emit()
	await settle(0.22)
	check(icon.hover_scale > 1.01, "%s 图标悬停要放大(现在 %.3f)" % [label, icon.hover_scale])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	icon._gui_input(click)
	icon._process(0.035)
	check(icon.poke_count == 1
			and Vector2(icon.material.get_shader_parameter("shake")).length() > 0.1,
			"%s 图标点击要有可见的戳动" % label)
	icon.mouse_exited.emit()
	await settle(0.45)
	check(icon.hover_scale < 1.01, "%s 图标移开要复位" % label)


func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(1)
		return
	Talents.reset_all()
	GameState.difficulty = GameState.Difficulty.EASY
	GameState.run_seed = 20261007
	GameState.reset_game()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.5)
	if game._intro_playing:
		game._finish_intro()
	game._playing = true
	game._hide_menu()
	game.popup_root.hide()
	game.crisis_root.hide()
	game._current_phase = "allocate"
	game._enter_allocate()
	game.right_panel.show()
	await settle(0.4)
	check(game._tip_allowed(), "开局 allocate 阶段应允许悬停反馈")

	# ---- 1. 刷新手牌用掉后的碎片，要跟新 UI 的蓝色同色系 ----
	var canvas: CanvasLayer = game._ui_canvas()
	var before: int = canvas.get_child_count()
	game._play_refresh_break_animation()
	var shards: Array = []
	for i in range(before, canvas.get_child_count()):
		var c: Node = canvas.get_child(i)
		if c is ColorRect:
			shards.append(c)
	check(shards.size() == 9, "碎裂演出应炸出 9 块碎片(实际 %d)" % shards.size())
	var palette: Array = preload("res://scripts/ui_skin.gd").SHARD_COLORS
	var in_palette := 0
	var blue := 0
	for s in shards:
		if s.color in palette:
			in_palette += 1
		if s.color.b > s.color.r:
			blue += 1
	check(in_palette == shards.size(),
			"碎片颜色必须取自 UiSkin.SHARD_COLORS(%d / %d)" % [in_palette, shards.size()])
	check(blue == shards.size(), "碎片必须全是蓝色系(%d / %d)" % [blue, shards.size()])
	game.refresh_btn.modulate.a = 1.0

	# ---- 2. 科研点悬停要写清它换到什么 ----
	var tip: String = game.research_label.tooltip_text
	check(tip.contains("深预警") and tip.contains(str(GameState.DEEP_WARN_RESEARCH)),
			"科研点提示要说清深预警门槛")
	check(tip.contains("1 / 2 / 3") and tip.contains(str(GameState.MAX_CARRY)),
			"科研点提示要写清来源(档位点数与结转上限)")
	check(tip.contains("20"), "科研点提示要写清结算报告那条附加评语")
	check(game.research_icon.tooltip_text == tip, "图标与标签的提示必须一致(鼠标停在图标上也要出)")

	# ---- 3. 金币 / 科研点跟六项指标一样的悬停与戳动 ----
	await poke_check("金币", game.funds_icon, 1.15)
	await poke_check("科研点", game.research_icon, 1.25)

	# ---- 4. 暂停里的设置面板要有返回 ----
	game._pause_game()
	await settle(0.35)
	check(game.pause_root.visible, "Esc 后暂停面板要出来")
	game._on_pause_settings()
	await settle(0.35)
	check(game.pause_settings_panel.visible and not game.pause_panel.visible, "设置面板应打开")
	var back: Button = find_button(game.pause_settings_panel, "返回")
	check(back != null, "暂停设置面板底部必须有「返回」按钮")
	if back != null:
		check(back.get_parent() is VBoxContainer, "返回按钮要在设置面板的竖排里")
		back.pressed.emit()
		await settle(0.35)
		check(not game.pause_settings_panel.visible and game.pause_panel.visible,
				"「返回」必须回到暂停菜单")

	var output := OS.get_environment("POYANG_SCREENSHOT_DIR")
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		game._on_pause_settings()
		await settle(0.35)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join("pause-settings.png"))
		game._on_pause_settings_back()
		game._resume_game()
		game.funds_icon.hovered = true
		game.research_icon.hovered = true
		await settle(0.3)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join("hud-poke.png"))

	print("HUD_POLISH: ", checks, " checks, ", failures.size(), " failures")
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
