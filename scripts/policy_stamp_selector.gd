extends Control
## Supplied parchment artwork, with one animated seal on the chosen policy.
signal tier_requested(tier: String)
signal stamp_landed
const TIERS := ["basic", "effective", "deep"]
const PAGES := [preload("res://assets/ui/policy-stamp/basic-page.png"), preload("res://assets/ui/policy-stamp/effective-page.png"), preload("res://assets/ui/policy-stamp/deep-page.png")]
const SEALS := [preload("res://assets/ui/policy-stamp/basic-seal.png"), preload("res://assets/ui/policy-stamp/effective-seal.png"), preload("res://assets/ui/policy-stamp/deep-seal.png")]
const CENTERS := [204.0, 343.0, 482.0]
var selected := 1
var page: TextureRect
var seal: TextureRect
var buttons: Array[Button] = []
var _locked := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	page = TextureRect.new()
	page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page.stretch_mode = TextureRect.STRETCH_SCALE
	page.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	seal = TextureRect.new()
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(seal)
	for i in 3:
		var button := Button.new()
		button.flat = true
		for style in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		button.tooltip_text = ["基础政策投入 · 半价", "有效政策投入 · 全价", "深度政策投入 · 双倍价"][i]
		button.pressed.connect(func(): tier_requested.emit(TIERS[i]))
		add_child(button)
		buttons.append(button)
	resized.connect(_layout)
	snap_to_tier(selected, false)

func _layout() -> void:
	if seal == null: return
	var factor := size / Vector2(667, 500)
	seal.size = Vector2(150, 135) * factor
	seal.position = Vector2(CENTERS[selected] - 75.0, 175) * factor
	seal.pivot_offset = seal.size * 0.5
	for i in buttons.size():
		buttons[i].position = Vector2(CENTERS[i] - 65.0, 185) * factor
		buttons[i].size = Vector2(130, 170) * factor

func snap_to_tier(index: int, animate: bool) -> void:
	selected = clampi(index, 0, 2)
	if page == null: return
	page.texture = PAGES[selected]
	seal.texture = SEALS[selected]
	_layout()
	preload("res://scripts/motion.gd").cancel(seal, "stamp")
	seal.scale = Vector2.ONE
	seal.modulate.a = 1.0
	if animate:
		seal.scale = Vector2(1.22, 1.22)
		seal.modulate.a = 0.25
		var tw := preload("res://scripts/motion.gd").tween(seal, "response", "stamp")
		tw.tween_property(seal, "scale", Vector2(0.96, 0.96), 0.10)
		tw.parallel().tween_property(seal, "modulate:a", 1.0, 0.10)
		tw.tween_callback(stamp_landed.emit)
		tw.tween_property(seal, "scale", Vector2.ONE, 0.08)

func set_locked(locked: bool) -> void:
	if _locked == locked: return
	_locked = locked
	modulate.a = 0.55 if locked else 1.0
	for button in buttons: button.disabled = locked
