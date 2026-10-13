extends Node
## Run only in the isolated project made by prepare_visual_test.py.
var checks := 0
var failures: Array[String] = []
var game: Node
var output_dir := OS.get_environment("POYANG_SCREENSHOT_DIR")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle(seconds: float = 0.3) -> void:
	await get_tree().create_timer(seconds).timeout

func capture(label: String) -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(label + ".png"))

func check_foil_render(card: Control, label: String) -> void:
	var panel: Control = card.get_meta("panel", card)
	var overlay: ColorRect = panel.get_node("KnowledgeFoil")
	check(not overlay.use_parent_material, label + " retains the foil material")
	game._step_card_gyro(card, Vector2(0.15, -0.20), 0.2)
	var foil := overlay.material as ShaderMaterial
	var gyro := card.material as ShaderMaterial
	check(is_equal_approx(float(foil.get_shader_parameter("tilt_x")), float(gyro.get_shader_parameter("tilt_x"))), label + " foil follows tilt")
	check(Vector2(foil.get_shader_parameter("card_center")).is_equal_approx(game._card_gyro_center(card)), label + " foil shares perspective center")
	game._step_card_gyro(card, Vector2.ZERO, 2.0)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var bounds := card.get_global_rect().grow(-6).intersection(get_viewport().get_visible_rect())
	var ratio := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var dark_pixels := 0
	var bright_pixels := 0
	for y in range(int(bounds.position.y * ratio.y), int(bounds.end.y * ratio.y), 2):
		for x in range(int(bounds.position.x * ratio.x), int(bounds.end.x * ratio.x), 2):
			var color := img.get_pixel(x, y)
			var brightness := (color.r + color.g + color.b) / 3.0
			if brightness < 0.48:
				dark_pixels += 1
			if brightness > 0.65:
				bright_pixels += 1
	check(dark_pixels > 30 and bright_pixels > 100, label + " renders legible ink and foil paper instead of a blank cover")

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		push_error("Knowledge tests require an isolated user directory")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	Knowledge.reset_all()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.4)
	if game._intro_playing:
		game._finish_intro()
	await settle(1.0)
	game._open_knowledge_viewer()
	await settle(1.8)
	check(game.knowledge_grid.get_child_count() == 41, "All 41 cards must appear")
	check(game.knowledge_count_label.text == "已收集 0 / 41", "New profile starts at 0 / 41")
	# 未收集统一的「未知」卡面（assets/art/knowledge/kd-11.png）：图里自带「未知 / ？ / UNKNOW」，
	# 所以代码不再往上写「？」和「未收集」，也不额外压灰。
	await capture("knowledge-locked-grid")
	game._show_knowledge_detail(game.knowledge_grid.get_child(Knowledge.all_ids().find("geo_poyang")), "geo_poyang")
	check(game.knowledge_detail_title.text == "？？？", "Locked card title stays hidden")
	check(not "https://" in game.knowledge_detail_body.text and not "https://" in game.knowledge_detail_source.text, "Locked card sources stay hidden")
	check(game.knowledge_detail_source.text.is_empty(), "Locked card source footer stays empty")
	game._close_knowledge_detail()
	game._close_knowledge_viewer()
	game._show_knowledge("geo_poyang")
	check(Knowledge.is_collected("geo_poyang"), "Gameplay popup collects the new card")
	check("资料来源" in game.popup_body.text, "Gameplay popup includes source")
	game.popup_root.visible = false
	for kid in Knowledge.all_ids():
		Knowledge.unlock(kid)
	Knowledge._load()
	check(Knowledge.collected_count() == 41, "All new cards survive save reload")
	game._open_knowledge_viewer()
	await settle(1.8)
	check(game.knowledge_count_label.text == "已收集 41 / 41", "Full collection count is correct")
	var egg_view: Control = game.knowledge_grid.get_child(Knowledge.all_ids().find("egg_dixinhu"))
	# 按类别重排后彩蛋在末尾，先滚到可见区域再检查实际像素。
	var gallery_scroll: ScrollContainer = game.knowledge_grid.get_parent().get_parent()
	gallery_scroll.ensure_control_visible(egg_view)
	await settle(0.5)
	await check_foil_render(egg_view, "Gallery egg")
	await capture("knowledge-dixinhu-gallery-fixed")
	game._show_knowledge_detail(egg_view, "egg_dixinhu")
	await settle(0.8)
	await check_foil_render(game._knowledge_big_card, "Detail egg")
	await capture("knowledge-dixinhu-detail-fixed")
	game._close_knowledge_detail()
	gallery_scroll.scroll_vertical = 0
	for i in Knowledge.all_ids().size():
		var kid: String = Knowledge.all_ids()[i]
		var view: Control = game.knowledge_grid.get_child(i)
		var panel: PanelContainer = view.get_meta("panel")
		check(panel.size.x <= 122.1 and panel.size.y <= 165.1, "%s must fit its card texture: %s" % [kid, panel.size])
		check(game._knowledge_art(kid) != null, "%s needs an illustration" % kid)
		game._show_knowledge_detail(view, kid)
		check(game.knowledge_detail_title.text == GameState.KNOWLEDGE_CARDS[kid]["name"], "%s opens the correct title" % kid)
		# 新卡面（植物 / 鸟类 / 彩蛋）在放大后的详情大牌上也要正常
		if kid in ["plant_kucao", "bird_baihe", "plant_sedge"]:
			await settle(1.2)
			await capture("knowledge-face-%s" % kid)
		if GameState.KNOWLEDGE_CARDS[kid].has("source_url"):
			check(GameState.KNOWLEDGE_CARDS[kid]["source_url"] in game.knowledge_detail_source.text, "%s opens its source link" % kid)
	game._close_knowledge_detail()
	await capture("knowledge-all-desktop")
	for window_size in [Vector2i(1280, 720), Vector2i(960, 540)]:
		get_window().size = window_size
		await settle(0.4)
		game._show_knowledge_detail(game.knowledge_grid.get_child(Knowledge.all_ids().find("protect_scientific_release")), "protect_scientific_release")
		await settle(2.6)
		var bounds := get_viewport().get_visible_rect()
		check(bounds.encloses(game._knowledge_big_card.get_global_rect()), "Enlarged card must fit window")
		check(bounds.encloses(game.knowledge_detail_title.get_global_rect()), "Long title must fit window")
		check(bounds.encloses(game.knowledge_detail_body.get_global_rect()), "Body must fit window")
		check(game.knowledge_detail_body.scroll_active, "Long details need scrolling")
		await capture("knowledge-detail-%d" % window_size.x)
		game._close_knowledge_detail()
	game._show_knowledge_detail(game.knowledge_grid.get_child(Knowledge.all_ids().find("mech_wetland_carbon")), "mech_wetland_carbon")
	check("初中拓展" in game.knowledge_detail_body.text, "Carbon card carries age-level label")
	await settle(2.6)
	await capture("knowledge-carbon-small")
	game._close_knowledge_detail()
	game._close_knowledge_viewer()

	# ---- 0.1.35：卡照贴在**牌面上**（1:1 方图）+ 卡名自动退让 + 出处写进详情 ----
	var PixelArt := preload("res://scripts/pixel_card_art.gd")
	game._open_knowledge_viewer()
	await settle(1.8)
	for kid in Knowledge.all_ids():
		var card: Dictionary = GameState.KNOWLEDGE_CARDS[kid]
		var view: Control = game.knowledge_grid.get_child(Knowledge.all_ids().find(kid))
		game._show_knowledge_detail(view, kid)
		await settle(0.5)
		var credit := str(card.get("photo_credit", ""))
		if credit != "":
			check(credit in game.knowledge_detail_source.text, "%s writes its photo credit in the source footer" % kid)
			check("图片来源" in game.knowledge_detail_source.text, "%s labels the photo credit" % kid)
			check(get_viewport().get_visible_rect().encloses(game.knowledge_detail_source.get_global_rect()),
				"%s source footer is visible without scrolling" % kid)
		var panel: Control = game._knowledge_big_card
		var face: TextureRect = panel.get_meta("pixel_face")
		var img: Image = face.texture.get_image()
		var plan: Dictionary = PixelArt.face_photo_plan(str(card["name"]))
		if kid == "egg_dixinhu":
			check(face.texture == PixelArt.KNOWLEDGE_FACE_EGG and game._knowledge_photo(kid) == null,
				"Egg card keeps its own drawn face and has no imported photo")
			game._close_knowledge_detail()
			continue
		check(not plan.is_empty(), "%s gets a photo layout" % kid)
		var tex: Texture2D = game._knowledge_photo(kid)
		check(tex != null, "%s has an imported photo" % kid)
		check(tex.get_width() == tex.get_height(),
			"%s imported photo is square: %dx%d" % [kid, tex.get_width(), tex.get_height()])
		var side := int(plan["side"])
		var src: Image = tex.get_image().duplicate()
		if src.get_width() != side:
			src.resize(side, side, Image.INTERPOLATE_LANCZOS)
		# 贴上去的必须是**这张卡自己的**照片：抽 5 个点（四角 + 中心）逐点比色
		var worst := 0.0
		for frac in [Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.5, 0.5),
				Vector2(0.1, 0.9), Vector2(0.9, 0.9)]:
			var fx := int(frac.x * side)
			var fy := int(frac.y * side)
			var got := img.get_pixel(int(plan["photo_x"]) + fx, PixelArt.FACE_PHOTO_TOP + fy)
			var want := src.get_pixel(fx, fy)
			worst = maxf(worst, absf(got.r - want.r) + absf(got.g - want.g) + absf(got.b - want.b))
		check(worst < 0.06, "%s face carries that card's own photo (worst delta %.3f)" % [kid, worst])
		# 卡名：在方图下方、不压到 y≈540 的「点击查看」、字号不低于 2 倍
		check(int(plan["name_top"]) >= PixelArt.FACE_PHOTO_TOP + side,
			"%s name sits below the photo" % kid)
		var name_bottom := int(plan["name_top"]) + 16 * int(plan["scale"]) \
			+ maxi(int(plan["lines"]) - 1, 0) * PixelArt.FACE_NAME_INDENT * int(plan["scale"])
		check(name_bottom <= 540, "%s name clears the printed footer: %d" % [kid, name_bottom])
		check(int(plan["scale"]) >= 2, "%s name never shrinks below 2x" % kid)
		game._close_knowledge_detail()
	# 换过照片的那张（草洲不是越野场）单独截一张正脸：牌面 + 详情里的出处链接
	game._show_knowledge_detail(game.knowledge_grid.get_child(Knowledge.all_ids().find("protect_wetland_tracks")), "protect_wetland_tracks")
	await settle(1.4)
	check(str(GameState.KNOWLEDGE_CARDS["protect_wetland_tracks"]["photo_url"]) in game.knowledge_detail_source.text,
		"Replacement photo's source link is written in the source footer")
	await capture("knowledge-photo-protect_wetland_tracks")
	game._close_knowledge_detail()
	game._show_knowledge_detail(game.knowledge_grid.get_child(Knowledge.all_ids().find("plant_sedge")), "plant_sedge")
	await settle(1.4)
	await capture("knowledge-photo-plant_sedge")
	game._close_knowledge_detail()
	await capture("knowledge-photo-gallery")
	get_window().size = Vector2i(960, 540)
	await settle(0.5)
	await capture("knowledge-photo-960")
	get_window().size = Vector2i(1280, 720)
	await settle(0.4)
	game._close_knowledge_viewer()

	# ---- 0.1.35：粗体不再让文字糊成一团 ----
	# [b] 必须落在项目主题自己钉住的正文字体上，不能掉回引擎默认主题那份
	# FontVariation(base=无衬线, embolden=1.2) —— 那正是「粗体字看不清」的来源。
	var root_theme: Theme = get_tree().root.theme
	var bold_font: Font = root_theme.get_font("bold_font", "RichTextLabel")
	check(bold_font != null, "The project theme pins RichTextLabel bold_font")
	check(bold_font == root_theme.default_font, "Bold must use the same pixel font as body text")
	check(not (bold_font is FontVariation), "Bold must not be a synthetic FontVariation")
	check(not game._md_emphasis("**重点**").contains("[b]"), "Changelog emphasis no longer uses [b]")
	game._show_menu()
	game._show_changelog_panel()
	await settle(1.0)
	await capture("bold-changelog")
	game._on_changelog_back()
	await settle(0.4)
	game._hide_menu()
	var egg: Dictionary = GameState.KNOWLEDGE_CARDS["egg_dixinhu"].duplicate(true)
	egg["condition"] = "turn == 1"
	egg["seasons"] = ["春", "夏", "秋", "冬"]
	egg["action_ids"] = ["water_control"]
	GameState.turn = 1
	GameState.used_action_ids = ["water_control"]
	check(not GameState._knowledge_condition_met(egg), "Random-only card rejects even injected trigger conditions")
	var drops := 0
	GameState._knowledge_rng.seed = 1042026
	for sample in 20000:
		GameState.turn = 1
		GameState.knowledge_last_turn = -99
		GameState.knowledge_unlocked.clear()
		GameState.pending_knowledge.clear()
		GameState._check_knowledge_triggers()
		if "egg_dixinhu" in GameState.pending_knowledge:
			drops += 1
			GameState.turn = 2
			GameState._check_knowledge_triggers()
			check(GameState.pending_knowledge.size() == 1, "Egg respects quiet next turn")
	check(drops > 60 and drops < 140, "Random egg appears at approximately 0.5 percent: %d / 20000" % drops)
	game._hide_menu()
	game._show_knowledge("egg_dixinhu")
	await settle(1.0)
	check(is_instance_valid(game._knowledge_egg_reveal), "Acquisition displays foil card")
	await capture("knowledge-dixinhu-acquired")
	game._show_popup("普通弹窗", "内容", "继续", Callable())
	check(game._knowledge_egg_reveal == null, "Next popup cleans special presentation")
	print("KNOWLEDGE_UI: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
