extends Node
const Access := preload("res://scripts/changelog_access.gd")
var checks := 0
var failures := 0
var game: Node
var output_dir := OS.get_environment("POYANG_SCREENSHOT_DIR")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle(seconds: float = 0.15) -> void:
	await get_tree().create_timer(seconds).timeout

func capture(label: String) -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(label + ".png"))

func locked(message: String) -> void:
	check(game._changelog_gate.visible and not game._changelog_content.visible, message + ": log hidden")
	check(game._changelog_rows.get_child_count() == 0, message + ": no log rows")
	check(game._changelog_password.text.is_empty(), message + ": password cleared")

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.keycode = code
	Input.parse_input_event(event)

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		push_error("Changelog lock tests require an isolated user directory")
		get_tree().quit(1)
		return
	var password := OS.get_environment("POYANG_CHANGELOG_TEST_PASSWORD")
	OS.unset_environment("POYANG_CHANGELOG_TEST_PASSWORD")
	if password.is_empty():
		push_error("Supply the changelog test password through the environment")
		get_tree().quit(1)
		return
	check(Access.verify(password), "Generated password matches salted verifier")
	check(not Access.verify("") and not Access.verify(password + " "), "Empty and altered passwords rejected")
	check(not Access.verify(password.to_upper()), "Password is case sensitive")
	check(not Access.verify("x".repeat(129)), "Oversized input rejected")
	for i in password.length():
		var altered := password.substr(0, i) + ("x" if password[i] != "x" else "y") + password.substr(i + 1)
		check(not Access.verify(altered), "Every single-character alteration rejected")
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	game = scene.get_node("Game")
	await settle(0.5)
	if game._intro_playing: game._finish_intro()
	await settle(0.4)
	game._show_menu()
	game._show_settings_panel()
	game.menu_changelog_btn.pressed.emit()
	await settle()
	locked("First opening")
	check(game._changelog_password.secret, "Password input is masked")
	check(get_viewport().gui_get_focus_owner() == game._changelog_password, "Opening focuses the password input")
	await capture("changelog-locked")
	key(KEY_ESCAPE)
	await settle()
	check(not game.menu_changelog_panel.visible and game.menu_settings_panel.visible, "Escape also closes the locked input UI")
	game.menu_changelog_btn.pressed.emit()
	await settle()
	locked("Reopening after locked Escape")
	game._submit_changelog_password()
	check(game._changelog_status.text == "请输入密码", "Blank submission gives a useful prompt")
	for i in 3:
		game._changelog_password.text = "incorrect"
		game._submit_changelog_password()
		locked("Wrong password")
	check(game._changelog_retry_at_ms > Time.get_ticks_msec(), "Three failures trigger retry delay")
	game._changelog_password.text = password
	game._submit_changelog_password()
	locked("Retry delay blocks submission")
	game._on_changelog_back()
	check(game.menu_settings_panel.visible, "Back returns to the originating settings")
	game.menu_changelog_btn.pressed.emit()
	await settle()
	locked("Reopening during retry delay")
	check(game._changelog_retry_at_ms > Time.get_ticks_msec(), "Closing does not bypass retry delay")
	await settle(5.1)
	game._changelog_password.text = password
	game._changelog_password.grab_focus()
	key(KEY_ENTER)
	await settle(0.4)
	check(game._changelog_content.visible and not game._changelog_gate.visible, "Enter unlocks the actual UI")
	check(game._changelog_rows.get_child_count() > 0, "Successful authentication builds the release rows")
	check(game._changelog_password.text.is_empty(), "Successful authentication immediately clears plaintext")
	check(game._changelog_failed_attempts == 0, "Success resets retry failures")
	await capture("changelog-unlocked")
	key(KEY_ESCAPE)
	await settle()
	check(not game.menu_changelog_panel.visible and game.menu_settings_panel.visible, "Escape closes the log and returns to settings")
	locked("Escape relocks")
	for i in 8:
		game.menu_changelog_btn.pressed.emit()
		await settle(0.05)
		locked("Repeated opening")
		game._changelog_password.text = password
		game._changelog_password.text_submitted.emit(password)
		check(game._changelog_content.visible, "Repeated valid submissions unlock")
		game._on_changelog_back()
		locked("Repeated closing")
	game.menu_changelog_btn.pressed.emit()
	game._changelog_password.text = password
	game._changelog_gate.get_children().back().pressed.emit()
	check(game._changelog_content.visible, "The unlock button accepts a valid password")
	game._show_settings_panel()
	locked("Leaving through another menu relocks")
	game.menu_changelog_btn.pressed.emit()
	game._changelog_password.text = password
	game._submit_changelog_password()
	game.menu_root.visible = false
	locked("Hiding the entire menu relocks")
	game._show_menu()
	game._show_changelog_panel()
	game._changelog_password.text = password
	game._submit_changelog_password()
	game._on_changelog_back()
	check(game.menu_col.visible, "A direct menu entry returns to the main menu")
	game._show_changelog_panel()
	get_window().size = Vector2i(960, 540)
	await settle(0.4)
	locked("Small-window opening")
	check(get_viewport().get_visible_rect().encloses(game.menu_changelog_panel.get_global_rect()), "Lock UI fits the small window")
	await capture("changelog-locked-small")
	get_window().size = Vector2i(1280, 720)
	game._on_changelog_back()
	game._on_title_start()
	game._on_difficulty_pick(GameState.Difficulty.EASY)
	game.seed_input.text = "20261014"
	game._on_start_pressed()
	for i in 16:
		if game.popup_root.visible: game._on_popup_button()
		await settle(0.1)
	check(not game.menu_root.visible and not GameState.game_over, "The password gate does not obstruct starting a game")
	check(game.card_infos.size() > 0, "Normal gameplay still deals a hand")
	game._show_menu()
	game._show_settings_panel()
	game.menu_changelog_btn.pressed.emit()
	await settle()
	locked("Returning from gameplay")
	password = ""
	print("CHANGELOG_LOCK: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
