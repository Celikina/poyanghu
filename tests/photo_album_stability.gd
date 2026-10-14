extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		quit(1)
		return
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var album: Control = load("res://scripts/title_photo_carousel.gd").new()
	host.add_child(album)
	await process_frame
	album.visible = true
	album.set_process(false)
	album.set_process_input(false)
	album.reduced_motion_check = func(): return false
	var center: Vector2 = album._catcher.get_global_rect().get_center()
	var initial_nodes := album.get_child_count()
	# Regrab a short cancelled swipe before its return animation can finish.
	album._begin(0, 0, true)
	var max_cancel_offset := 0.0
	for i in 120:
		var now := i * 200
		album._begin_pointer(center, now)
		album._step_fade(0.12)
		album._move_pointer(center - Vector2(40, 0), now + 120)
		max_cancel_offset = maxf(max_cancel_offset, absf(album._sheets[album._front].position.x))
		album._end_pointer(center - Vector2(40, 0), now + 160)
		album._step_fade(0.01)
	check(album._index == 0, "Cancelled rapid swipes never advance index")
	check(max_cancel_offset < 80.0, "Repeated short swipes do not accumulate an ever-widening exposed edge")
	album._step_fade(0.4)
	check(album._sheets[album._front].position == Vector2.ZERO and album._sheets[album._front].modulate.a == 1.0, "Interrupted returns finish exactly home")
	var max_edge := 0.0
	var bounds_ok := true
	var alpha_ok := true
	var index_ok := true
	for fps in [30, 60, 120]:
		album._begin(0, 0, true)
		for i in 600:
			var distance: float = [22.0, 90.0, 220.0, 800.0][i % 4]
			var direction := -1.0 if i % 3 == 0 else 1.0
			var now := i * 100
			var expected := posmod(album._index + (1 if direction < 0 else -1), 13)
			album._begin_pointer(center, now)
			album._step_fade(1.0 / fps)
			album._move_pointer(center + Vector2(distance * direction, 0), now + 12)
			for sheet in album._sheets:
				if not sheet.visible: continue
				max_edge = maxf(max_edge, absf(sheet.position.x))
				bounds_ok = bounds_ok and sheet.position.x >= -album.FRAME.x - 0.001 and sheet.position.x <= 0.001 and is_zero_approx(sheet.position.y)
				alpha_ok = alpha_ok and sheet.modulate.a >= 0.0 and sheet.modulate.a <= 1.0
			album._end_pointer(center + Vector2(distance * direction, 0), now + 18)
			index_ok = index_ok and album._index == expected
			album._step_fade(1.0 / fps)
		album._step_fade(0.4)
		check(album._sheets[album._front].position == Vector2.ZERO and album._sheets[album._front].modulate.a == 1.0, "Fast chain settles correctly at %d FPS" % fps)
		check(not album._sheets[1 - album._front].visible and album._sheets[1 - album._front].position == Vector2.ZERO and album._sheets[1 - album._front].modulate.a == 1.0, "Inactive sheet is clean after chain at %d FPS" % fps)
	check(bounds_ok, "All papers stay within one drag width during repeated interruptions and reversals")
	check(alpha_ok, "Interrupted opacity never drifts out of range")
	check(index_ok, "Every rapid flick advances exactly once with no wait or input queue")
	check(album.get_child_count() == initial_nodes and album._sheets.size() == 2, "Fast input reuses two papers and leaves no new layers")
	check(album._rects[album._front].texture == album._current_tex, "Visible photo remains synchronized with index")
	# Previous-page flicks must keep the newly current background at home, not just in bounds.
	var right_background_ok := true
	var right_index_ok := true
	var max_right_background_edge := 0.0
	for fps in [30, 60, 120]:
		album._begin(5, 0, true)
		for i in 200:
			var now := i * 100
			var distance: float = [22.0, 80.0, 200.0][i % 3]
			var expected := posmod(album._index - 1, 13)
			album._begin_pointer(center, now)
			max_right_background_edge = maxf(max_right_background_edge, absf(album._sheets[album._front].position.x))
			right_background_ok = right_background_ok and album._sheets[album._front].position == Vector2.ZERO and album._sheets[album._front].modulate.a == 1.0
			album._move_pointer(center + Vector2(distance, 0), now + 12)
			album._step_fade(1.0 / fps)
			max_right_background_edge = maxf(max_right_background_edge, absf(album._sheets[album._front].position.x))
			right_background_ok = right_background_ok and album._sheets[album._front].position == Vector2.ZERO and album._sheets[album._front].modulate.a == 1.0
			album._end_pointer(center + Vector2(distance, 0), now + 18)
			right_index_ok = right_index_ok and album._index == expected
			album._step_fade(1.0 / fps)
		album._step_fade(0.4)
	check(right_background_ok, "Consecutive previous swipes keep current photo opaque and exactly home throughout each new gesture")
	check(right_index_ok, "Every consecutive right flick goes back exactly one photograph")
	check(is_zero_approx(max_right_background_edge), "Right-swipe background never exposes a growing edge")
	print("PHOTO_ALBUM_STABILITY: ", checks, " checks, ", failures, " failures; max_cancel_edge=", max_cancel_offset, " max_chain_edge=", max_edge)
	print("RIGHT_SWIPE_BACKGROUND_EDGE=", max_right_background_edge)
	host.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
