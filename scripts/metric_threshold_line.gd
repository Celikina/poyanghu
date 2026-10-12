extends ColorRect
## All five failure thresholds share a 2px design width and snap to screen pixels.
const WIDTH := 2.0

func _ready() -> void:
	get_parent().resized.connect(_schedule_snap)
	get_viewport().size_changed.connect(_schedule_snap)
	_schedule_snap()

func _schedule_snap() -> void:
	call_deferred("snap_to_pixels")

func snap_to_pixels() -> void:
	var wrap := get_parent() as Control
	if wrap == null: return
	var transform := get_viewport().get_stretch_transform() * wrap.get_global_transform_with_canvas()
	var scale_x := absf(transform.get_scale().x)
	if is_zero_approx(scale_x): return
	var center := (transform * Vector2(wrap.size.x * anchor_left, 0.0)).x
	var pixels := maxf(1.0, roundf(WIDTH * scale_x))
	var left := roundf(center - pixels * 0.5)
	offset_left = (left - center) / scale_x
	offset_right = (left + pixels - center) / scale_x
