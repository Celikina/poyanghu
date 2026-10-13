extends Node2D
## Project the actual rounded alpha silhouette after all movement for this frame.
const LIGHT_RAY := Vector2(0.14, 0.22)
const Geometry = preload("res://scripts/card_geometry.gd")
static var contours: Dictionary = {}
var points := PackedVector2Array()
var softness := 4.0
var _mesh: ArrayMesh
var _geometry_ready := false
var _last_transform := Transform2D.IDENTITY
var _last_face_transform := Transform2D.IDENTITY
var _last_shadow_transform := Transform2D.IDENTITY
var _last_rect := Rect2()
var _last_tilt := Vector2.ZERO
var _last_poke := 1.0
var _last_preserve := false
var _last_shape: Variant
var geometry_builds := 0
var _vertices := PackedVector2Array()
var _surface_vertices := 0
var surface_builds := 0
var vertex_updates := 0

func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(_sync_projection)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_projection):
		RenderingServer.frame_pre_draw.disconnect(_sync_projection)

func _sync_projection() -> void:
	if not is_visible_in_tree(): return
	var card := get_parent() as Control
	if card:
		update_projection(card, Vector2(card.get_meta("gyro_x", 0.0), card.get_meta("gyro_y", 0.0)))

static func _contour(texture: Texture2D, silhouette: String = "") -> PackedVector2Array:
	var key: Variant = texture.get_instance_id() if silhouette.is_empty() else silhouette
	if contours.has(key): return contours[key]
	var image := texture.get_image()
	var width := image.get_width()
	var height := image.get_height()
	var samples := PackedVector2Array()
	for y in height:
		if y > height * 0.12 and y < height * 0.88 and y % maxi(1, int(height / 24)) != 0: continue
		var left := -1
		var right := -1
		for x in width:
			if image.get_pixel(x, y).a > 0.5:
				if left < 0: left = x
				right = x
		if left >= 0:
			samples.append(Vector2(left, y) / Vector2(width, height))
			samples.append(Vector2(right + 1, y + 1) / Vector2(width, height))
	var hull := Geometry2D.convex_hull(samples)
	if hull.size() > 1 and hull[0] == hull[-1]: hull.remove_at(hull.size() - 1)
	contours[key] = hull
	return hull

func update_projection(card: Control, tilt: Vector2) -> void:
	var face := Geometry.face_of(card)
	if face == null or face.texture == null or face.size.x <= 0.0 or face.size.y <= 0.0: return
	var rect := Geometry.face_rect(face)
	var transform := card.get_global_transform()
	var face_transform := face.get_global_transform()
	var poke := float(card.get_meta("poke_scale", 1.0))
	var preserve_size := bool(card.get_meta("shadow_preserve_size", false))
	var silhouette: String = face.get_meta("shadow_silhouette", "")
	var shape: Variant = face.texture.get_instance_id() if silhouette.is_empty() else silhouette
	var shadow_transform := get_global_transform()
	if _geometry_ready and _last_transform == transform and _last_face_transform == face_transform \
		and _last_shadow_transform == shadow_transform and _last_rect == rect and _last_tilt == tilt \
		and _last_poke == poke and _last_preserve == preserve_size and _last_shape == shape: return
	_geometry_ready = true
	_last_transform = transform
	_last_face_transform = face_transform
	_last_shadow_transform = shadow_transform
	_last_rect = rect
	_last_tilt = tilt
	_last_poke = poke
	_last_preserve = preserve_size
	_last_shape = shape
	geometry_builds += 1
	var center := transform * (card.size * 0.5)
	var extent := Vector2(face_transform.x.length() * rect.size.x, face_transform.y.length() * rect.size.y)
	# 接收平面始终位于倾斜卡片背后，不让角点穿过背景。
	var receiver := 16.0 + extent.length() * 0.30
	# Enlarged detail cards otherwise cover the entire shrunken projection.
	# Keep their rounded footprint at face size, with the same light direction.
	var perspective := 1.0 if preserve_size else 520.0 / (520.0 + receiver)
	var inverse := get_global_transform().affine_inverse()
	var cx := cos(tilt.x)
	var sx := sin(tilt.x)
	var cy := cos(tilt.y)
	var sy := sin(tilt.y)
	points.clear()
	for uv in _contour(face.texture, silhouette):
		var c: Vector2 = (face_transform * (rect.position + rect.size * uv) - center) * poke
		var q := Vector3(c.x * cy, c.y, -c.x * sy)
		var r := Vector3(q.x, q.y * cx - q.z * sx, q.y * sx + q.z * cx)
		var projected := (Vector2(r.x, r.y) + LIGHT_RAY * (receiver - r.z)) * perspective + center
		points.append(inverse * projected)
	softness = clampf(receiver * 0.035, 2.0, 8.0) / maxf(transform.x.length(), 0.01)
	_rebuild_mesh()
	queue_redraw()

func _rebuild_mesh() -> void:
	if points.size() < 3: return
	var center := Vector2.ZERO
	for point in points: center += point / points.size()
	var stride := points.size() + 1
	var count := stride * 9
	_vertices.resize(count)
	# 多层半影固定在接收平面，独立于卡面着色器。
	for layer in range(8, -1, -1):
		var start := (8 - layer) * stride
		_vertices[start] = center
		for i in points.size():
			var point := points[i]
			_vertices[start + 1 + i] = point + (point - center).normalized() * softness * layer / 8.0
	var bounds := Rect2(_vertices[0], Vector2.ZERO)
	for i in stride: bounds = bounds.expand(_vertices[i])
	if _mesh and _surface_vertices == count:
		_mesh.surface_update_vertex_region(0, 0, _vertices.to_byte_array())
		_mesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, 0.0), Vector3(bounds.size.x, bounds.size.y, 0.0))
		vertex_updates += 1
		return
	var colors := PackedColorArray()
	colors.resize(count)
	colors.fill(Color(0.015, 0.025, 0.025, 0.055))
	var indices := PackedInt32Array()
	for layer in 9:
		var start := layer * stride
		for i in points.size(): indices.append_array(PackedInt32Array([start, start + 1 + i, start + 1 + (i + 1) % points.size()]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	# Reuse the mesh resource already attached to the canvas. Pre-draw updates
	# reach the current rendered frame instead of waiting for another _draw.
	if _mesh == null: _mesh = ArrayMesh.new()
	else: _mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	_mesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, 0.0), Vector3(bounds.size.x, bounds.size.y, 0.0))
	_surface_vertices = count
	surface_builds += 1

func _draw() -> void:
	if _mesh: draw_mesh(_mesh, null)
