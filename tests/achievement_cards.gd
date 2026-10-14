extends Node
var game: Node
var checks := 0
var failures: Array[String] = []
var notifications: Array[String] = []
var output_dir := OS.get_environment("POYANG_SCREENSHOT_DIR")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle(seconds: float = 0.3) -> void:
	await get_tree().create_timer(seconds).timeout

func row_for(id: String) -> Control:
	for row in game.ach_rows_col.get_children():
		if row.get_meta("achievement_id", "") == id:
			return row
	return null

func capture(name: String) -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(name + ".png"))

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	await settle(0.1)
	Knowledge.reset_all()
	Achievements.reset_all()
	Achievements.achievement_unlocked.connect(func(id: String): notifications.append(id))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.4)
	if game._intro_playing:
		game._finish_intro()
	await settle(1.0)
	game._show_achievements_panel()
	await settle(0.4)
	check(Achievements.LIST.size() == 4, "Four achievements are defined")
	check(row_for("rigged") == null, "Locked hidden achievement has no row")
	check(game.ach_rows_col.get_child_count() == 4, "Only four achievements are initially visible")
	check(game.ach_count_label.text == "已解锁 0 / 4", "Hidden achievement does not leak through the total")
	check(row_for("ecology_expert") != null, "Ecology expert is visible before unlocking")
	await capture("achievements-hidden-locked")
	Achievements._unlocked["rigged"] = true
	Achievements._save()
	Achievements._load()
	check(not Achievements.is_unlocked("rigged"), "Removed achievement is filtered from old saves")
	check(Achievements.find("rigged").is_empty(), "Removed achievement has no definition")
	check(row_for("rigged") == null, "Removed achievement stays out of the menu")
	var ids := Knowledge.all_ids()
	for i in range(ids.size() - 1):
		Knowledge.unlock(ids[i])
		check(not Achievements.is_unlocked("ecology_expert"), "Partial collection must not unlock ecology expert")
	check(Knowledge.collected_count() == ids.size() - 1, "Boundary test reaches %d / %d" % [ids.size() - 1, ids.size()])
	game._show_knowledge(ids.back())
	check(Achievements.is_unlocked("ecology_expert"), "The final gameplay knowledge popup unlocks ecology expert")
	check(notifications.count("ecology_expert") == 1, "Ecology expert announces exactly once")
	game.popup_root.hide()
	Achievements.check_knowledge_completion()
	Knowledge.unlock(ids.back())
	check(notifications.count("ecology_expert") == 1, "Repeated checks and cards do not repeat the achievement")
	Achievements._load()
	check(not Achievements.is_unlocked("rigged") and Achievements.is_unlocked("ecology_expert"), "Known achievements survive reload without the removed achievement")
	Achievements.reset_all()
	check(not Achievements.is_unlocked("ecology_expert"), "Reset clears the achievement")
	Knowledge._load()
	Achievements._watch_knowledge()
	check(Achievements.is_unlocked("ecology_expert"), "Startup reconciliation rewards an existing complete collection")
	check(not Achievements.is_unlocked("rigged"), "Collection completion must not unlock rigged")
	game._ach_queue.clear()
	game.ach_popup.visible = false
	game._show_achievements_panel()
	await settle(0.5)
	await capture("achievements-new-unlocked")
	get_window().size = Vector2i(960, 540)
	await settle(0.5)
	check(get_viewport().get_visible_rect().encloses(game.menu_achievements_panel.get_global_rect()), "Achievement menu fits a small window")
	await capture("achievements-small")
	print("ACHIEVEMENT_CARDS: %d checks, %d failures" % [checks, failures.size()])
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
