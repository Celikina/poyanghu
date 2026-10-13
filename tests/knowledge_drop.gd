extends Node
var game: Node
var checks := 0
var failures := 0
var output := OS.get_environment("POYANG_SCREENSHOT_DIR")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func settle(seconds: float = 0.3) -> void:
	await get_tree().create_timer(seconds).timeout
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
func finish_text() -> void:
	if game._popup_reveal and game._popup_reveal.is_valid(): game._popup_reveal.kill()
	game.popup_body.visible_characters = -1
func check_layout(kid: String) -> void:
	check(game.popup_photo.texture == game._knowledge_photo(kid), kid + " shows its corresponding photograph")
	check(game.popup_photo_frame.is_visible_in_tree(), kid + " photo is visible in the actual gameplay popup")
	check(game.popup_body.text == game._knowledge_detail_text(kid, true), kid + " retains all original knowledge text")
	check(game.popup_body.scroll_active and not game.popup_body.fit_content, "Long knowledge text has its own scroll area")
	var viewport := get_viewport().get_visible_rect().grow(-8)
	check(viewport.encloses(game.popup_panel.get_global_rect()), kid + " popup fits the viewport")
	check(game.popup_panel.get_global_rect().encloses(game.popup_photo_frame.get_global_rect()) and game.popup_panel.get_global_rect().encloses(game.popup_body.get_global_rect()), kid + " image and text fit inside the panel")
	var photo: Rect2 = game.popup_photo.get_global_rect()
	check(absf(photo.size.x - photo.size.y) < 0.1, kid + " photograph keeps a square without stretching")
	check(game.popup_button.get_global_rect().position.y >= game.popup_body.get_global_rect().end.y + 8, "Collection button remains visible below the text")
	check(Knowledge.is_collected(kid), kid + " still becomes collected when presented")
	check(not game.popup_body.text.contains("https://"), "The acquisition popup has no external source links")
func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	Knowledge.reset_all()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.5)
	if game._intro_playing: game._finish_intro()
	game._on_title_start()
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	game.seed_input.text = "20261013"
	game._on_start_pressed()
	for i in 24:
		if game.popup_root.visible: game._on_popup_button()
		await settle(0.1)
	game.set_process(false)
	game.wetland.set_process(false)
	var photo_count := 0
	var longest := ""
	var max_length := 0
	for kid in Knowledge.all_ids():
		if kid == "egg_dixinhu": continue
		game._show_knowledge(kid)
		finish_text()
		await settle()
		check_layout(kid)
		photo_count += 1
		var length: int = game.popup_body.get_total_character_count()
		if length > max_length:
			longest = kid
			max_length = length
		if kid in ["plant_kucao", "bird_baihe", "protect_wetland_tracks"]: await shot("wide-" + kid)
	check(photo_count == 40, "Every photographic knowledge card appears correctly")
	check(game.popup_content.get_child_count() == 2, "Successive drops reuse one image frame without accumulating nodes")
	game.ach_popup.hide()
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1024, 768)]:
		get_window().size = dimensions
		await settle()
		for kid in ["bird_baihe", longest]:
			game._show_knowledge(kid)
			finish_text()
			await settle()
			check_layout(kid)
			check(game.popup_content.vertical == (dimensions.x < 1000), "Photo layout adapts to the window width")
			await shot("drop-" + kid + "-" + str(dimensions.x))
	# A resize while the same prompt is open must update without redisplaying it.
	get_window().size = Vector2i(960, 540)
	await settle()
	check(game.popup_content.vertical, "Live resize switches to the stacked presentation")
	get_window().size = Vector2i(1280, 720)
	await settle()
	check(not game.popup_content.vertical, "Live resize returns to the side-by-side presentation")
	game._show_knowledge("plant_kucao")
	check(game.popup_body.visible_characters == 0, "Original typewriter still starts unrevealed")
	game._on_popup_button()
	check(game.popup_root.visible and game.popup_body.visible_characters == -1, "First collection click completes text without dismissing the photograph")
	GameState.pending_knowledge = ["bird_baihe"]
	game._on_popup_button()
	check(game._knowledge_popup_card_id == "bird_baihe" and game.popup_photo.texture == game._knowledge_photo("bird_baihe"), "Second click continues to the next card and its matching photograph")
	game.save_game()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.SAVE_PATH))
	check(saved.popup.knowledge_id == "bird_baihe", "Saving records the visible knowledge card id")
	game._show_popup("普通弹窗", "内容", "继续", Callable())
	check(not game.popup_photo_frame.visible and game.popup_photo.texture == null and game.popup_body.fit_content, "An ordinary popup removes photo and restores its original text layout")
	check(game.load_game(), "Saved acquisition resumes successfully")
	check(game.popup_photo_frame.visible and game.popup_photo.texture == game._knowledge_photo("bird_baihe"), "Continue restores the acquisition photograph")
	saved.popup.erase("knowledge_id")
	var file := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	check(game.load_game() and game.popup_photo.texture == game._knowledge_photo("bird_baihe"), "Old saves recover the matching photograph from their knowledge title")
	game._show_knowledge("egg_dixinhu")
	await settle(0.8)
	check(not game.popup_photo_frame.visible and is_instance_valid(game._knowledge_egg_reveal), "The non-photographic egg keeps its original foil-card reveal")
	finish_text()
	await shot("egg-original-reveal")
	game._show_popup("普通事件", "原有事件正文", "继续", Callable())
	check(game._knowledge_egg_reveal == null and not game.popup_photo_frame.visible, "Next event cleans all knowledge presentation")
	print("KNOWLEDGE_DROP: ", checks, " checks, ", failures, " failures; longest=", longest)
	get_tree().quit(0 if failures == 0 else 1)
