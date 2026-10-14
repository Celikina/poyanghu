extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(what)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.5).timeout
	var game: Node = scene.get_node("Game")
	if game._intro_playing: game._finish_intro()
	var water: Node = game.wetland
	water.set_process(false)
	var route: Array[Vector2] = water._boat_route
	var lengths: PackedFloat64Array = water._boat_lengths
	var total := lengths[-1]
	var straight_sections := 0
	var bends := 0
	var max_frame_movement := 0.0
	var max_heading_change := 0.0
	for i in range(1, route.size()):
		var length := lengths[i] - lengths[i - 1]
		var middle: Vector2 = (route[i - 1] + route[i]) * 0.5
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var phase := lerpf(lengths[i - 1], lengths[i], fraction) / total
			var sample: Dictionary = water._boat_route_sample(phase)
			var tangent: Vector2 = sample.direction
			var normal := Vector2(-tangent.y, tangent.x)
			for side in [-1.0, 1.0]:
				check(water._near_route(sample.pos + normal * water.RIVER_BOAT_LANE * side, water.yangtze_route, water.YANGTZE_HALF_WIDTH - 0.008), "Simplified boat lanes stay inside original river with shore clearance")
		if length > 0.02 and middle.x > 0 and middle.x < 0.6:
			straight_sections += 1
			var a: Dictionary = water._boat_route_sample((lengths[i - 1] + length * 0.2) / total)
			var b: Dictionary = water._boat_route_sample((lengths[i - 1] + length * 0.8) / total)
			check((a.direction as Vector2).dot(b.direction) > 0.999999, "Straight sailing keeps exact heading")
		if i < route.size() - 1:
			var phase := lengths[i] / total
			var a: Dictionary = water._boat_route_sample(phase - 0.000001 / total)
			var b: Dictionary = water._boat_route_sample(phase + 0.000001 / total)
			check((a.direction as Vector2).dot(b.direction) > 0.9999, "Navigation joins have continuous heading")
			if middle.x > 0.42 and middle.x < 0.49 and absf((a.direction as Vector2).angle_to(water._boat_tangents[maxi(0, i - 2)])) > 0.01:
				bends += 1
	check(straight_sections >= 3, "River course has long straight sailing sections")
	check(bends > 0, "Hukou course changes remain present")
	for fixture in [[4, 100.0], [4, 350.0], [5, 0.0], [5, -180.0]]:
		var ship: int = fixture[0]
		for frame in 9000:
			var time := float(frame) / 60.0 + float(fixture[1])
			var a: Dictionary = water._yangtze_boat_sample(ship, time)
			var b: Dictionary = water._yangtze_boat_sample(ship, time + 1.0 / 60.0)
			if (a.pos as Vector2).x < 0 or (a.pos as Vector2).x > 0.6: continue
			var move: float = water._shadow_point(a.pos).distance_to(water._shadow_point(b.pos))
			max_frame_movement = maxf(max_frame_movement, move)
			var da: Vector2 = water._shadow_projection.basis_xform(a.direction).normalized()
			var db: Vector2 = water._shadow_projection.basis_xform(b.direction).normalized()
			max_heading_change = maxf(max_heading_change, absf(da.angle_to(db)))
			check(move < 0.6, "Boat position moves smoothly at sixty FPS")
			check(absf(da.angle_to(db)) < deg_to_rad(2.0), "Boat turns without per-frame orientation snaps")
	print("RIVER_BOAT_MOTION: ", checks, " checks, ", failures, " failures; max_frame_px=", max_frame_movement, " max_frame_degrees=", rad_to_deg(max_heading_change))
	quit(0 if failures == 0 else 1)
