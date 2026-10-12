extends Control
## Resident, migrant and forecast change are three adjoining segments.
const MIGRANT_ALPHA := 0.38
const LOSS_COLOR := Color("ef5350")
var bar: ProgressBar
var effects_owner: Node
var tint := Color.WHITE
var residents := 0
var migrants := 0
var current := 0.0
var predicted := 0.0
var predicted_residents := 0
var predicted_migrants := 0
var forecast_available := false
var _from_population := Vector2.ZERO
var _configured := false
var _swap_progress := 1.0
var _track: StyleBoxFlat
var _resident_fill: StyleBoxFlat
var _migrant_fill: StyleBoxFlat
var _change_fill: StyleBoxFlat

func configure(base: int, visiting: int) -> void:
	base = clampi(base, 0, 60)
	visiting = clampi(visiting, 0, 40)
	if _configured and residents == base and migrants == visiting: return
	_from_population = display_population() if _configured else Vector2.ZERO
	residents = base
	migrants = visiting
	current = float(base + visiting)
	_swap_progress = 0.0 if is_equal_approx(_from_population.x + _from_population.y, current) else 1.0
	_configured = true
	clear_forecast()
	queue_redraw()

func configure_forecast(base: int, visiting: int) -> void:
	predicted_residents = clampi(base, 0, 60)
	predicted_migrants = clampi(visiting, 0, 40)
	predicted = float(predicted_residents + predicted_migrants)
	forecast_available = predicted_residents != residents or predicted_migrants != migrants
	queue_redraw()

func clear_forecast() -> void:
	predicted_residents = residents
	predicted_migrants = migrants
	predicted = current
	forecast_available = false
	queue_redraw()

func display_population() -> Vector2:
	if bar == null: return Vector2(residents, migrants)
	var displayed := clampf(bar.value, 0.0, 100.0)
	var start_total := _from_population.x + _from_population.y
	var progress := _swap_progress if is_equal_approx(start_total, current) else clampf((displayed - start_total) / (current - start_total), 0.0, 1.0)
	var base := lerpf(_from_population.x, float(residents), progress)
	# Intermediate settlement totals retain the real 60 / 40 capacities.
	base = clampf(base, maxf(0.0, displayed - 40.0), minf(60.0, displayed))
	return Vector2(base, displayed - base)

func fill_end(value: float) -> float:
	return 2.0 + maxf(0.0, size.x - 4.0) * clampf(value / 100.0, 0.0, 1.0)

func resident_rect() -> Rect2:
	var population := shown_population()
	return Rect2(2.0, 2.0, maxf(0.0, fill_end(population.x) - 2.0), maxf(0.0, bar.size.y - 4.0))

func migrant_rect() -> Rect2:
	var population := shown_population()
	return Rect2(fill_end(population.x), 2.0, maxf(0.0, fill_end(population.x + population.y) - fill_end(population.x)), maxf(0.0, bar.size.y - 4.0))

func forecast_delta() -> float:
	return predicted - current

func shown_population() -> Vector2:
	if not forecast_available: return display_population()
	# Gains follow the current populations; losses follow the surviving ones.
	# The separate change segment brings the full length to the larger total.
	return Vector2(residents, migrants) if predicted > current else Vector2(predicted_residents, predicted_migrants)

func forecast_rect() -> Rect2:
	# Only the net total changes blink. Opposite population changes merely
	# shift the projected split and never manufacture a gain or loss tail.
	var left := fill_end(minf(current, predicted))
	var right := fill_end(maxf(current, predicted))
	return Rect2(left, 2.0, maxf(0.0, right - left), maxf(0.0, bar.size.y - 4.0))

func forecast_color() -> Color:
	return Color.WHITE if forecast_delta() > 0 else LOSS_COLOR

func _segment_corners(style: StyleBoxFlat, first: bool, last: bool) -> void:
	# Internal joins are straight; only the outside ends are rounded.
	style.corner_radius_top_left = 3 if first else 0
	style.corner_radius_bottom_left = style.corner_radius_top_left
	style.corner_radius_top_right = 3 if last else 0
	style.corner_radius_bottom_right = style.corner_radius_top_right

func blink_alpha() -> float:
	if effects_owner == null: return 0.75
	var reduce: bool = effects_owner.wetland != null and effects_owner.wetland.reduced_motion
	return 0.75 if reduce else 0.28 + 0.72 * (0.5 + 0.5 * sin(effects_owner._metric_preview_clock * TAU * 1.1))

func _style(color: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style

func _ready() -> void:
	_track = _style(Color("0b252e"), Color("607975"))
	_track.set_corner_radius_all(5)
	_resident_fill = _style(Color.WHITE, Color(1.0, 1.0, 1.0, 0.85))
	_migrant_fill = _style(Color(1.0, 1.0, 1.0, MIGRANT_ALPHA), Color(1.0, 1.0, 1.0, 0.60))
	_change_fill = _style(Color.WHITE, Color.WHITE)
	# Segments touch directly. Their color / opacity alone distinguishes them;
	# individual outlines would introduce bright or dark seams at every join.
	for style in [_resident_fill, _migrant_fill, _change_fill]:
		style.set_border_width_all(0)
	resized.connect(queue_redraw)
	bar.value_changed.connect(_on_value_changed)

func _on_value_changed(_value: float) -> void:
	queue_redraw()

func _draw() -> void:
	if bar == null or _track == null or size.x <= 4.0: return
	draw_style_box(_track, Rect2(Vector2.ZERO, Vector2(size.x, bar.size.y)))
	var base := resident_rect()
	var visiting := migrant_rect()
	var change := forecast_rect() if forecast_available else Rect2()
	var has_change := change.has_area()
	_segment_corners(_resident_fill, true, not visiting.has_area() and not has_change)
	_segment_corners(_migrant_fill, not base.has_area(), not has_change)
	_segment_corners(_change_fill, not base.has_area() and not visiting.has_area(), true)
	if base.size.x > 0.0:
		draw_style_box(_resident_fill, base)
	if visiting.size.x > 0.0:
		draw_style_box(_migrant_fill, visiting)
	if not has_change: return
	var color := forecast_color()
	var opacity := maxf(0.48, blink_alpha()) if forecast_delta() < 0 else blink_alpha()
	_change_fill.bg_color = Color(color, opacity)
	draw_style_box(_change_fill, change)

func _process(delta: float) -> void:
	if _swap_progress < 1.0:
		var reduce: bool = effects_owner != null and effects_owner.wetland != null and effects_owner.wetland.reduced_motion
		if effects_owner == null or not effects_owner._paused:
			_swap_progress = 1.0 if reduce else minf(1.0, _swap_progress + delta / 0.35)
			queue_redraw()
	if forecast_available and not is_zero_approx(forecast_delta()) and is_visible_in_tree(): queue_redraw()
