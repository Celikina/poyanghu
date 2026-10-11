extends Control
## The resident fill is the white ProgressBar. Cover its migrant portion with
## a static translucent white fill; the forecast above this layer alone blinks.
const MIGRANT_ALPHA := 0.38
var bar: ProgressBar
var residents := 0
var migrants := 0
var _last_value := -1.0

func configure(base: int, visiting: int) -> void:
	residents = base
	migrants = visiting
	queue_redraw()

func fill_end(value: float) -> float:
	var minimum := bar.get_theme_stylebox("fill").get_minimum_size().x
	var pixels := roundf(clampf(value / 100.0, 0.0, 1.0) * (bar.size.x - minimum))
	return pixels + minimum if pixels > 0.0 else 0.0

func migrant_rect() -> Rect2:
	var total := float(residents + migrants)
	# Keep the split inside the animated fill while values settle.
	var boundary := float(residents) * bar.value / total if total > 0.0 else 0.0
	var left := fill_end(boundary)
	return Rect2(left, 0.0, maxf(0.0, fill_end(bar.value) - left), bar.size.y)

func _draw() -> void:
	if bar == null or migrants <= 0: return
	var rect := migrant_rect()
	if rect.size.x <= 0.0: return
	var backdrop := bar.get_theme_stylebox("background").duplicate() as StyleBoxFlat
	var visiting := bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	for style in [backdrop, visiting]:
		style.corner_radius_top_left = 0
		style.corner_radius_bottom_left = 0
	backdrop.border_color = backdrop.bg_color
	visiting.bg_color = Color(1.0, 1.0, 1.0, MIGRANT_ALPHA)
	visiting.border_color = Color(1.0, 1.0, 1.0, 0.48)
	draw_style_box(backdrop, rect)
	draw_style_box(visiting, rect)
	if residents > 0:
		draw_line(Vector2(rect.position.x, 1.0), Vector2(rect.position.x, rect.size.y - 1.0), Color("0b252e"), 1.0)

func _ready() -> void:
	resized.connect(queue_redraw)

func _process(_delta: float) -> void:
	if bar != null and not is_equal_approx(_last_value, bar.value):
		_last_value = bar.value
		queue_redraw()
