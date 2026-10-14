extends SceneTree
var checks := 0
var failures := 0
var game: Node
var album: Control
var output := OS.get_environment("POYANG_SCREENSHOT_DIR")
func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(what)
func wait(seconds: float) -> void:
	await create_timer(seconds).timeout
func shot(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(output.path_join(name + ".png"))
func pose_point() -> Vector2:
	return album._catcher.get_global_rect().get_center()
func pointer(point: Vector2, button: int = -1, pressed: bool = false) -> void:
	var event: InputEvent
	if button < 0:
		event = InputEventMouseMotion.new()
	else:
		event = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await wait(0.5)
	game = scene.get_node("Game")
	if game._intro_playing: game._finish_intro()
	await wait(0.5)
	album = game.title_photos
	album.visible = true
	album.set_process(false)
	# Direct scrubbing fixtures must not be moved by the real desktop pointer during screenshots.
	album.set_process_input(false)
	var calm := [false]
	album.reduced_motion_check = func(): return calm[0]
	for path in album.PHOTOS: check(load(path) is Texture2D, "Every original photo loads")
	album._begin(0, 0, true)
	check(album._caption.text.contains("01 / 13"), "Caption matches current photo")
	check(album.get_global_rect().position.y > 100, "Album clears top-right easter egg")
	await shot("01-album-menu")
	var center := pose_point()
	album._begin_pointer(center, 1000)
	album._move_pointer(center + Vector2(-40, 5), 1100)
	check(is_equal_approx(album._sheets[album._front].position.x, -40), "Paper follows pointer without lag")
	check(album._sheets[1 - album._front].visible, "Drag reveals following photograph")
	await shot("02-album-drag")
	album._end_pointer(center + Vector2(-40, 5), 1400)
	check(album._index == 0 and not album._zoom.visible, "Short slow drag neither flips nor zooms")
	album._step_fade(0.4)
	check(album._sheets[album._front].position == Vector2.ZERO and is_zero_approx(album._sheets[album._front].rotation), "Short drag returns exactly home")
	album._begin_pointer(center, 2000)
	album._move_pointer(center + Vector2(-90, 0), 2300)
	album._end_pointer(center + Vector2(-90, 0), 2500)
	check(album._index == 1, "Twenty-percent drag commits next photograph")
	check(not album._zoom.visible, "Committed drag never opens zoom")
	album._step_fade(0.12)
	var current_pose: Vector2 = album._sheets[album._front].position
	album._step(1)
	check(album._index == 2, "Second input is accepted during animation")
	check(album._sheets[album._departing].position == current_pose, "Interrupted turn keeps visible paper's current pose")
	album._step(-1)
	check(album._index == 1, "Immediate reversal has no queued turns")
	album._step_fade(0.4)
	album._begin_pointer(center, 3000)
	album._move_pointer(center + Vector2(22, 0), 3010)
	album._end_pointer(center + Vector2(22, 0), 3020)
	check(album._index == 0, "Fast short flick commits previous photograph")
	album._step_fade(0.4)
	# Direction-specific scrubbing, including reversal and release without a visual snap.
	album._begin(2, 0, true)
	album._begin_pointer(center, 3500)
	for distance in [20.0, 80.0, 180.0]:
		album._move_pointer(center + Vector2(distance, 0), 3600 + int(distance))
		var incoming: int = 1 - album._front
		check(album._sheets[album._front].position == Vector2.ZERO and album._sheets[album._front].modulate.a == 1.0, "Previous drag leaves current photograph stationary")
		check(is_equal_approx(album._sheets[incoming].position.x, -album.FRAME.x + distance), "Previous photograph travels from left towards home")
		check(is_equal_approx(album._sheets[incoming].modulate.a, distance / album.FRAME.x), "Previous opacity tracks drag distance")
		check(album._rects[incoming].texture == album._texture(1), "Right drag previews the previous photograph")
	await shot("05-previous-halfway")
	var preview_position: Vector2 = album._sheets[1 - album._front].position
	var preview_alpha: float = album._sheets[1 - album._front].modulate.a
	album._end_pointer(center + Vector2(180, 0), 3900)
	check(album._index == 1 and album._sheets[album._front].position == preview_position and is_equal_approx(album._sheets[album._front].modulate.a, preview_alpha), "Previous release continues from scrubbed position and opacity")
	album._step_fade(0.4)
	check(album._sheets[album._front].position == Vector2.ZERO and album._sheets[album._front].modulate.a == 1.0, "Previous photograph finishes exactly home")
	album._begin_pointer(center, 4000)
	for distance in [20.0, 80.0, 180.0]:
		album._move_pointer(center - Vector2(distance, 0), 4100 + int(distance))
		check(is_equal_approx(album._sheets[album._front].position.x, -distance), "Next drag moves current photograph left")
		check(is_equal_approx(album._sheets[album._front].modulate.a, 1.0 - distance / album.FRAME.x), "Next opacity tracks drag distance")
		check(album._sheets[1 - album._front].position == Vector2.ZERO, "Next photograph stays beneath at home")
	await shot("06-next-halfway")
	album._move_pointer(center + Vector2(30, 0), 4400)
	check(album._sheets[album._front].position == Vector2.ZERO and album._sheets[album._front].modulate.a == 1.0, "Reversing drag restores current photograph")
	album._end_pointer(center + Vector2(30, 0), 4700)
	album._step_fade(0.4)
	check(album._index == 1 and album._sheets[album._front].position == Vector2.ZERO, "Cancelled previous drag preserves index")
	var unchanged: int = album._index
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	album._on_catcher_input(wheel)
	check(album._index == unchanged, "Main album has no wheel navigation")
	check(album._strip.find_children("*", "Button", true, false).is_empty(), "Main album has no previous or next buttons")
	check(album._next_auto_ms - Time.get_ticks_msec() >= 14900, "Manual interaction delays auto-play by fifteen seconds")
	album._step_fade(0.4)
	album._begin_pointer(center, 6000)
	album._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	album._step_fade(0.4)
	check(not album._pressed and not album._zoom.visible, "Focus loss cancels gesture without zoom")
	# Real GUI dispatch: click opens, dragging beyond the hitbox still captures release.
	album.set_process_input(true)
	await pointer(center)
	await pointer(center, MOUSE_BUTTON_LEFT, true)
	await pointer(center, MOUSE_BUTTON_LEFT, false)
	check(album._zoom.visible, "Actual GUI click opens original photo")
	check(not album._strip.visible and not album._catcher.is_visible_in_tree(), "Zoom hides album papers and hitbox")

	await shot("04-zoom-without-album")
	var previous_button: Vector2 = album._zoom_prev.position
	var next_button: Vector2 = album._zoom_next.position
	for i in 13:
		album._step(1)
		check(album._zoom_prev.position == previous_button and album._zoom_next.position == next_button, "Zoom buttons stay aligned across all photo ratios")
		check(album._zoom_photo.texture == album._current_tex, "Zoom follows current photograph")
		var original: Texture2D = album._current_tex
		check(is_equal_approx(album._zoom_photo.size.aspect(), original.get_size().aspect()), "Full photo preserves original ratio")
	# Keep clicking the same physical point while image dimensions change.
	for i in 15:
		var expected := posmod(album._index + 1, 13)
		var fixed_point: Vector2 = album._zoom_next.get_global_rect().get_center()
		await pointer(fixed_point, MOUSE_BUTTON_LEFT, true)
		await pointer(fixed_point, MOUSE_BUTTON_LEFT, false)
		check(album._zoom.visible and album._index == expected, "Rapid clicks at fixed next button never dismiss zoom")
	check(album._zoom_link.uri == album.SOURCE_URL, "Original source remains in detail")
	album.close_zoom()
	check(album._strip.visible and album._catcher.is_visible_in_tree(), "Closing zoom restores album contents and interaction")
	check(album._rects[album._front].texture == album._current_tex, "Restored album shows photo last viewed in zoom")
	album._settle_fade()
	var before: int = album._index
	await pointer(center, MOUSE_BUTTON_LEFT, true)
	await pointer(center + Vector2(-220, 0))
	await pointer(center + Vector2(-220, 0), MOUSE_BUTTON_LEFT, false)
	check(album._index == posmod(before + 1, 13) and not album._pressed and not album._zoom.visible, "Actual drag captures release outside photo and flips once")
	album._step_fade(0.4)
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	before = album._index
	album._input(key)
	check(album._index == before, "Main-page arrow keys no longer flip album")
	calm[0] = true
	album._step(-1)
	check(album._fade == 1 and album._sheets[album._front].position == Vector2.ZERO, "Reduced motion turns instantly")
	calm[0] = false
	album._begin_pointer(center, 7000)
	album._move_pointer(center + Vector2(-40, 0), 7100)
	album.visible = false
	check(not album._pressed and not album._dragging, "Hiding album cancels drag")
	album.visible = true
	album._settle_fade()
	await pointer(Vector2(20, 650))
	before = album._index
	album._next_auto_ms = Time.get_ticks_msec() - 1
	album._tick_auto(Time.get_ticks_msec(), false)
	check(album._index == posmod(before + 1, 13), "Idle deadline advances once")
	check(album._next_auto_ms - Time.get_ticks_msec() >= 9900, "Automatic turns wait ten seconds")
	before = album._index
	album._manual_activity()
	album._tick_auto(Time.get_ticks_msec(), false)
	check(album._index == before, "Manual cooldown prevents premature automatic turn")
	await pointer(pose_point())
	album._next_auto_ms = Time.get_ticks_msec() - 1
	album._tick_auto(Time.get_ticks_msec(), true)
	check(album._index == before, "Hover suspends automatic turn")
	await pointer(Vector2(20, 650))
	album._open_zoom()
	album._next_auto_ms = Time.get_ticks_msec() - 1
	album._tick_auto(Time.get_ticks_msec(), false)
	check(album._index == before, "Zoom suspends automatic turn")
	album.close_zoom()
	calm[0] = true
	album._next_auto_ms = Time.get_ticks_msec() - 1
	album._tick_auto(Time.get_ticks_msec(), false)
	check(album._index == before, "Reduced motion disables automatic turns")
	calm[0] = false
	var reference: Vector2
	for fps in [30, 60, 120]:
		album._begin(0, 0, true)
		album._step(1)
		for i in int(fps / 5): album._step_fade(1.0 / fps)
		var pose: Vector2 = album._sheets[album._front].position
		if fps == 30: reference = pose
		check(pose.distance_to(reference) < 0.001, "Turn trajectory is stable at %d FPS" % fps)
	album._settle_fade()
	for window_size in [Vector2i(960, 540), Vector2i(1600, 900)]:
		root.size = window_size
		await wait(0.3)
		check(album.get_global_rect().end.x <= game.menu_root.size.x, "Album stays within resized menu")
		await shot("03-menu-%d" % window_size.x)
	# Real GUI rapid flicks interrupt the running animation rather than a synthetic fixture.
	# Input.parse_input_event uses window pixels; restore 1:1 coordinates after layout captures.
	root.size = Vector2i(1280, 720)
	await wait(0.3)
	album._begin(0, 0, true)
	album.set_process(true)
	for i in 24:
		var point := pose_point()
		var direction := -1.0 if i % 3 == 0 else 1.0
		var expected := posmod(album._index + (1 if direction < 0 else -1), 13)
		await pointer(point, MOUSE_BUTTON_LEFT, true)
		await pointer(point + Vector2(120 * direction, 0))
		await pointer(point + Vector2(120 * direction, 0), MOUSE_BUTTON_LEFT, false)
		check(album._index == expected and not album._zoom.visible, "Real rapid flick advances once without opening zoom")
		for sheet in album._sheets:
			check(sheet.position.x >= -album.FRAME.x - 0.001 and sheet.position.x <= 0.001, "Real rapid flick keeps both sheet positions bounded")
	await wait(0.5)
	check(album._sheets[album._front].position == Vector2.ZERO and not album._sheets[1 - album._front].visible, "Real rapid chain leaves a single photo exactly home")
	await shot("07-after-rapid-swipes")
	# A whole chain of rightward previous-photo gestures must keep a solid background.
	album._begin(5, 0, true)
	for i in 30:
		var point := pose_point()
		var expected := posmod(album._index - 1, 13)
		await pointer(point, MOUSE_BUTTON_LEFT, true)
		check(album._sheets[album._front].position == Vector2.ZERO and album._sheets[album._front].modulate.a == 1.0, "Real right regrab promotes current photo fully home")
		await pointer(point + Vector2(120, 0))
		check(album._sheets[album._front].position == Vector2.ZERO and album._sheets[album._front].modulate.a == 1.0, "Real consecutive right drag leaves background fixed and opaque")
		if i == 15: await shot("08-during-rapid-right-swipes")
		await pointer(point + Vector2(120, 0), MOUSE_BUTTON_LEFT, false)
		check(album._index == expected and not album._zoom.visible, "Real consecutive right swipe goes back once")
	await wait(0.5)
	check(album._sheets[album._front].position == Vector2.ZERO and not album._sheets[1 - album._front].visible, "Real right-only chain finishes without extra exposed photo")
	await shot("09-after-rapid-right-swipes")
	print("PHOTO_ALBUM: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
