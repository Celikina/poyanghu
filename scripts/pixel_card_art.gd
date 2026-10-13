extends RefCounted
## Bitmap card fronts preserve category artwork and the existing glyph font.
const PAPER := preload("res://assets/art/artist-test-card-blank.png")
const SUITS := {
	"ecology": preload("res://assets/art/card-suits/ecology.png"),
	"social": preload("res://assets/art/card-suits/social.png"),
	"manage": preload("res://assets/art/card-suits/manage.png"),
}
## 图鉴使用完整知识卡牌面，与普通手牌和紧急调度分别取材。
const KNOWLEDGE_FACES := {
	"地理": preload("res://assets/art/knowledge/geography.png"),
	"植物": preload("res://assets/art/knowledge/plants.png"),
	"鸟类": preload("res://assets/art/knowledge/birds.png"),
	"水生动物": preload("res://assets/art/knowledge/aquatic.png"),
	"外来物种": preload("res://assets/art/knowledge/invasive.png"),
	"机制": preload("res://assets/art/knowledge/mechanisms.png"),
	"保护行动": preload("res://assets/art/knowledge/conservation.png"),
	"案例": preload("res://assets/art/knowledge/cases.png"),
	"管理策略": preload("res://assets/art/knowledge/management.png"),
}
const KNOWLEDGE_CATEGORIES := preload("res://scripts/knowledge_categories.gd").ORDER
const DISPATCH_SUITS := {
	"ecology": preload("res://assets/art/dispatch/ecology.png"),
	"social": preload("res://assets/art/dispatch/social.png"),
	"manage": preload("res://assets/art/dispatch/manage.png"),
}
## 未解锁与彩蛋均使用美术提供的完整牌面，不额外写标题。
const KNOWLEDGE_FACE_LOCKED := preload("res://assets/art/knowledge/unknown.png")
const KNOWLEDGE_FACE_EGG := preload("res://assets/art/knowledge/easter-egg.png")
## 往新卡面上写卡名用的排版参数（测试也读这三个，别在别处再写一遍魔数）
const FACE_SCALE := 4        # 400×600 卡面上，字形放大 4 倍（与行动卡的卡名同规格）
const FACE_SPACING := 80     # 行距
const FACE_BAND_CENTER := 338 # 中间空白带的垂直中心（实测卡面 145~530）
## 卡照（pptx 图集导入的 40 张方图）的位置与尺寸。
## 数值照抄彩蛋卡狄鑫斛（kd-07）里那块插画面板：实测 x79..324 / y175..420，正好 246×246 的方图，
## 名字写在方图下面。用户口径：「知识卡优先保证图片 1:1 大小，和狄鑫斛一样，
## 文字自动调整大小做避让，同时要求能放得下」。
const FACE_PHOTO_TOP := 175
const FACE_PHOTO_MAX := 246
const FACE_PHOTO_X := 79
const FACE_PHOTO_GAP := 6      # 方图与卡名之间的空隙
const FACE_NAME_BOTTOM := 510  # 卡名块下限（再往下 y≈540 是印好的「点击查看」，留 30px 喘气）
const FACE_NAME_SCALES: Array[int] = [4, 3, 2]  # 卡名候选字形倍数，从大到小退
const FACE_NAME_INDENT := 18
const FACE_NAME_WIDTH := 284
const GLYPHS := preload("res://assets/art/card-font-glyphs.png")
const SHADOW := Color8(150, 150, 150)
const INK := Color.BLACK
const COST_INK := Color8(56, 68, 53) # #384435，采自新手牌图例的金额数字
static var mapping: Dictionary = {}
static var glyph_image: Image
static var paper_image: Image
static var textures: Dictionary = {}
static var suit_images: Dictionary = {}
static var glyph_stamps: Dictionary = {}

static func _load_pixels() -> void:
	if paper_image != null:
		return
	mapping = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/card-font-glyphs.json"))
	glyph_image = GLYPHS.get_image()
	paper_image = PAPER.get_image()
	paper_image.convert(Image.FORMAT_RGBA8)
	# Knowledge cards have no action suit. Restore the baked social icon's area
	# from the opposite blank corner, including the paper edge and outer frame.
	var knowledge_paper := paper_image.duplicate() as Image
	for y in range(6, 34):
		for x in range(64, 94):
			knowledge_paper.set_pixel(x, y, paper_image.get_pixel(95 - x, y))
	suit_images["knowledge"] = knowledge_paper
	for category in SUITS:
		var image: Image = SUITS[category].get_image()
		image.convert(Image.FORMAT_RGBA8)
		suit_images[category] = image

static func category_for(title: String) -> String:
	for card in GameState.ACTION_CARDS:
		if str(card["name"]) == title: return str(card["category"])
	return ""

static func base_image(category: String) -> Image:
	_load_pixels()
	return suit_images.get(category, paper_image)


## 全部已收集知识卡都有无便签纸的完整卡面。
static func knowledge_face(category: String) -> Texture2D:
	return KNOWLEDGE_FACES.get(category)

## 专用素材牌库按 id 读取整张副本；生成素材时只写名称，不写费用。
static func dispatch_texture(card: Dictionary, baked: bool = true) -> Texture2D:
	_load_pixels()
	var key := "dispatch\n" + str(card["id"])
	if baked and textures.has(key):
		return textures[key]
	var path := "res://assets/art/dispatch/cards/%s.png" % str(card["id"])
	if baked and ResourceLoader.exists(path):
		textures[key] = load(path)
		return textures[key]
	var image := (DISPATCH_SUITS[str(card["category"])] as Texture2D).get_image().duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	image.resize(400, 600, Image.INTERPOLATE_NEAREST)
	var lines := _lines(str(card["name"]))
	var top := 133 if lines.size() >= 4 else 167
	var spacing := 71 if lines.size() >= 4 else 75
	for i in lines.size():
		_write(image, lines[i], top + i * spacing, INK, -1, 4)
	var result := ImageTexture.create_from_image(image)
	if baked: textures[key] = result
	return result


## 用画好的卡面做一张知识卡。
## 有卡照（photo）时：方图摆在中间，卡名挪到方图下面，字号自动往下退直到放得下；
## 没卡照时走老路 —— 只写卡名、垂直居中在中间那块空白带里。
## （底部「点击查看」在 y≈540，所以文字块别压下去。图里的类别与「知识卡」是印好的，不再写。）
static func knowledge_texture(title: String, category: String, photo: Texture2D = null) -> Texture2D:
	_load_pixels()
	var key := "kface\n" + title + "\n" + category
	var plan: Dictionary = face_photo_plan(title) if photo != null else {}
	if plan.is_empty():
		if textures.has(key):
			return textures[key]
	else:
		key += "\nphoto"
		if textures.has(key):
			return textures[key]
	var source: Texture2D = knowledge_face(category)
	var image := source.get_image().duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	if plan.is_empty():
		var lines := _lines(title)
		var block_h := 16 * FACE_SCALE + (lines.size() - 1) * FACE_SPACING
		var top := FACE_BAND_CENTER - block_h / 2
		for i in lines.size():
			_write(image, lines[i], top + i * FACE_SPACING, INK, -1, FACE_SCALE)
	else:
		_paste_photo(image, photo, plan)
		var scale := int(plan["scale"])
		var lines: Array = plan["name_lines"]
		for i in lines.size():
			_write(image, lines[i], int(plan["name_top"]) + i * FACE_NAME_INDENT * scale, INK, -1, scale)
	var result := ImageTexture.create_from_image(image)
	textures[key] = result
	return result


## 所有照片固定使用狄鑫斛的同一块区域；只按各自卡名调整字号与换行。
static func face_photo_plan(title: String) -> Dictionary:
	_load_pixels()
	for scale in FACE_NAME_SCALES:
		var name_lines := _lines(title, int(FACE_NAME_WIDTH / scale))
		var count := name_lines.size()
		# 长卡名收尾只有一两个字时平均分行，避免单字悬在下一行。
		if count > 1 and _width(name_lines.back()) < FACE_NAME_WIDTH / scale * 0.4:
			var balanced := _lines(title, int(ceil(float(_width(title)) / count)))
			if balanced.size() == count:
				name_lines = balanced
		var name_h := 16 * scale + maxi(count - 1, 0) * FACE_NAME_INDENT * scale
		var name_top := FACE_PHOTO_TOP + FACE_PHOTO_MAX + FACE_PHOTO_GAP
		# 阴影也占一个字形倍数，计入可用高度。
		if name_top + name_h + scale > FACE_NAME_BOTTOM:
			continue
		name_top += int((FACE_NAME_BOTTOM - name_top - name_h - scale) / 2.0)
		return {"side": FACE_PHOTO_MAX, "scale": scale, "lines": count,
			"name_lines": name_lines, "name_top": name_top, "photo_x": FACE_PHOTO_X}
	return {}


static func source_width() -> int:
	return 400


## 把方图贴到卡面上。photo 已经是 1:1（tools/import_knowledge_photos.py 方裁过），
## 这里只在边长和 246 对不上时缩一次，绝不改长宽比。
static func _paste_photo(image: Image, photo: Texture2D, plan: Dictionary) -> void:
	var side := int(plan["side"])
	# ⚠ 必须 duplicate：ImageTexture.get_image() 给的是**纹理内部那张图**，
	#   直接 resize 会把缓存里的照片纹理本身改小，下一张卡就拿到缩过的图。
	var src := photo.get_image().duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	if src.get_width() != side or src.get_height() != side:
		src.resize(side, side, Image.INTERPOLATE_LANCZOS)
	image.blit_rect(src, Rect2i(0, 0, side, side), Vector2i(int(plan["photo_x"]), FACE_PHOTO_TOP))


## 这张卡面上「代码允许改」的那块区域（测试拿它断言别处像素没被动过）。
## 有照片时 = 方图 + 卡名那一整条；没照片时 = 原来那条居中的文字带。
static func knowledge_text_band(title: String, with_photo: bool = false) -> Rect2i:
	_load_pixels()
	if with_photo:
		var plan := face_photo_plan(title)
		if not plan.is_empty():
			var bottom := int(plan["name_top"]) + 16 * int(plan["scale"]) \
				+ maxi(int(plan["lines"]) - 1, 0) * FACE_NAME_INDENT * int(plan["scale"])
			return Rect2i(0, FACE_PHOTO_TOP, source_width(), bottom - FACE_PHOTO_TOP)
	var lines := _lines(title)
	var block_h := 16 * FACE_SCALE + (lines.size() - 1) * FACE_SPACING
	var top := FACE_BAND_CENTER - block_h / 2
	return Rect2i(0, top, source_width(), block_h)

static func _width(text: String) -> int:
	var width := 0
	for character in text:
		width += int(mapping.get(character, mapping["？"])[2])
	return width

static func _lines(text: String, max_width: int = 64) -> Array[String]:
	var lines: Array[String] = []
	var line := ""
	for character in text:
		if not line.is_empty() and _width(line + character) > max_width:
			lines.append(line)
			line = ""
		line += character
	if not line.is_empty():
		lines.append(line)
	return lines

static func _write(image: Image, text: String, top: int, ink: Color = INK, left_override: int = -1, glyph_scale: int = 1) -> void:
	var left := int((image.get_width() - _width(text) * glyph_scale) / 2.0) if left_override < 0 else left_override
	# All shadows first, then all foregrounds: neighboring glyphs never overwrite ink.
	for pass_index in 2:
		var x := left
		var offset := glyph_scale if pass_index == 0 else 0
		var color := SHADOW if pass_index == 0 else ink
		for character in text:
			var glyph: Array = mapping.get(character, mapping["？"])
			var stamp := _glyph_stamp(glyph, color, glyph_scale)
			image.blend_rect(stamp, Rect2i(Vector2i.ZERO, stamp.get_size()), Vector2i(x + offset, top + offset))
			x += int(glyph[2]) * glyph_scale

static func _glyph_stamp(glyph: Array, color: Color, scale: int) -> Image:
	var key := "%d:%d:%d:%d:%s" % [glyph[0], glyph[1], glyph[2], scale, color.to_html()]
	if glyph_stamps.has(key): return glyph_stamps[key]
	var stamp := Image.create(int(glyph[2]), 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in int(glyph[2]):
			if glyph_image.get_pixel(int(glyph[0]) + x, int(glyph[1]) + y).a > 0.5:
				stamp.set_pixel(x, y, color)
	if scale != 1: stamp.resize(stamp.get_width() * scale, 16 * scale, Image.INTERPOLATE_NEAREST)
	glyph_stamps[key] = stamp
	return stamp
static func texture(title: String, footer: String = "", category: String = "") -> Texture2D:
	_load_pixels()
	if category.is_empty():
		category = "knowledge" if footer in ["知识卡", "未收集"] else category_for(title)
	var key := title + "\n" + footer + "\n" + category
	if textures.has(key):
		return textures[key]
	var image := base_image(category).duplicate() as Image
	var lines := _lines(title)
	var top := 32 if lines.size() >= 4 else 40
	var spacing := 17 if lines.size() >= 4 else 18
	var glyph_scale := 4 if SUITS.has(category) else 1
	if SUITS.has(category):
		top = 133 if lines.size() >= 4 else 167
		spacing = 71 if lines.size() >= 4 else 75
	for i in lines.size():
		_write(image, lines[i], top + i * spacing, INK, -1, glyph_scale)
	if not footer.is_empty():
		# Costs are already in ten-thousands; the supplied banknote prints 萬.
		if SUITS.has(category):
			_write(image, footer, 417, COST_INK, 179 - _width(footer) * 2, glyph_scale)
		else: _write(image, footer, 100)
	var result := ImageTexture.create_from_image(image)
	textures[key] = result
	return result

static func add_face(panel: PanelContainer, title: String, footer: String = "", locked: bool = false, category: String = "", dixinhu: bool = false, knowledge_category: String = "", photo: Texture2D = null) -> TextureRect:
	var face := TextureRect.new()
	face.name = "PixelCardFace"
	# 卡面来源：彩蛋 → 画好的整张；未解锁 → 统一的「未知」卡面；有该类别卡面 → 卡面 + 方图 + 卡名；
	# 行动卡 → 三类手牌模板 + 卡名 + 深绿色金额。
	# photo（知识卡卡照）只有走「该类别卡面」这条路时才用得上：彩蛋与未解锁都用画好的整张图。
	var art: Texture2D = null
	if dixinhu:
		art = KNOWLEDGE_FACE_EGG
	elif locked and KNOWLEDGE_FACE_LOCKED != null:
		art = KNOWLEDGE_FACE_LOCKED
	elif knowledge_face(knowledge_category) != null:
		art = knowledge_texture(title, knowledge_category, photo)
	face.texture = art if art != null else texture(title, footer, category)
	# Text and photos change only the opaque interior; retain one exact alpha
	# silhouette per supplied template instead of reading every color variant.
	var resolved_category := category
	if resolved_category.is_empty(): resolved_category = "knowledge" if footer in ["知识卡", "未收集"] else category_for(title)
	var silhouette := "action/" + resolved_category
	if dixinhu: silhouette = "knowledge/egg"
	elif locked and art != null: silhouette = "knowledge/locked"
	elif art != null: silhouette = "knowledge/" + knowledge_category
	face.set_meta("shadow_silhouette", silhouette + "/" + str(face.texture.get_size()))
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 新未知牌面自带灰调，再压一层 0.68 会发黑，所以只有回退路径才调暗。
	if locked and art == null:
		face.modulate = Color(0.68, 0.68, 0.68)
	panel.add_child(face)
	panel.set_meta("pixel_face", face)
	var outline := Node2D.new()
	outline.set_script(preload("res://scripts/card_outline.gd"))
	outline.name = "CardArtOutline"
	outline.use_parent_material = true
	panel.add_child(outline)
	return face
