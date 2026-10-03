extends Control
## Pixel-perfect workshop assembly, built from the same three parts as combat.

var build: Dictionary = {"blade": "balance", "ratchet": "mid", "bit": "ball"}
var animated: bool = true
var preview_scale: float = 3.0
var _clock: float = 0.0
var _textures: Dictionary = {}
var identity: String = ""
var accent: Color = Color.WHITE

func set_identity(starter_id: String, color: Color) -> void:
	identity = starter_id
	accent = color
	queue_redraw()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_build(value: Dictionary) -> void:
	build = value.duplicate()
	queue_redraw()

func _process(delta: float) -> void:
	if animated:
		_clock += delta
		queue_redraw()

func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path] as Texture2D

func _draw() -> void:
	var scale_factor: float = preview_scale
	var origin: Vector2 = Vector2((size.x - 48.0 * scale_factor) / 2.0, (size.y - 48.0 * scale_factor) / 2.0)
	# Whole pixel motion keeps the authored silhouettes crisp. Breaker hunts,
	# Bastion stays planted, and Vane glides through a small elliptical orbit.
	if identity == "breaker":
		origin += Vector2(roundf(sin(_clock * 5.0) * 3.0), roundf(cos(_clock * 7.0) * 1.0))
	elif identity == "vane":
		origin += Vector2(roundf(cos(_clock * 1.8) * 6.0), roundf(sin(_clock * 1.8) * 2.0))
	var blade_id: String = str(build.get("blade", "balance"))
	var ratchet_id: String = str(build.get("ratchet", "mid"))
	var bit_id: String = str(build.get("bit", "ball"))
	var height_offset: float = 3.0 if ratchet_id == "low" else (-3.0 if ratchet_id == "high" else 0.0)
	var contact: Vector2 = origin + Vector2(24.0, 40.0) * scale_factor
	draw_ellipse_shadow(contact, scale_factor)
	if not identity.is_empty(): _draw_identity_motion(origin, scale_factor)
	var bit: Texture2D = _texture("res://assets/top/parts/bits/%s.png" % bit_id)
	var ratchet: Texture2D = _texture("res://assets/top/parts/ratchets/%s.png" % ratchet_id)
	var identity_path: String = "res://assets/top/starters/%s_spin.png" % identity
	var authored_identity: bool = not identity.is_empty() and ResourceLoader.exists(identity_path)
	var blade: Texture2D = _texture(identity_path if authored_identity else "res://assets/top/parts/blades/%s_spin.png" % blade_id)
	var destination: Rect2 = Rect2(origin.round(), Vector2(48.0, 48.0) * scale_factor)
	if bit != null:
		draw_texture_rect(bit, destination, false)
	if ratchet != null:
		draw_texture_rect(ratchet, destination, false)
	if blade != null:
		var frame_seconds: float = 0.065 if identity == "breaker" else (0.16 if identity == "bastion" else 0.1)
		var phase: int = int(_clock / frame_seconds) % 8 if animated else 0
		var columns: int = maxi(1, int(blade.get_width()) / 48)
		var source: Rect2 = Rect2(Vector2(phase % columns, phase / columns) * 48.0, Vector2(48.0, 48.0))
		destination.position.y += height_offset * scale_factor
		draw_texture_rect_region(blade, destination, source, Color.WHITE if authored_identity or identity.is_empty() else Color.WHITE.lerp(accent, 0.7))
		if not identity.is_empty():
			# A coloured, mechanical hub joins the silhouette instead of replacing it.
			var hub: Vector2 = (destination.position + Vector2(24, 25) * scale_factor).round()
			draw_rect(Rect2(hub - Vector2(2, 1) * scale_factor, Vector2(4, 2) * scale_factor), accent)
			draw_rect(Rect2(hub - Vector2(1, 2) * scale_factor, Vector2(2, 4) * scale_factor), accent)

func _draw_identity_motion(origin: Vector2, factor: float) -> void:
	var center: Vector2 = (origin + Vector2(24, 29) * factor).round()
	var dim: Color = Color(accent.r, accent.g, accent.b, 0.4)
	if identity == "breaker":
		for index: int in range(3):
			var offset: Vector2 = Vector2(-19 - index * 3, 4 + index * 2) * factor
			draw_line((center + offset).round(), (center + offset + Vector2(7, -2) * factor).round(), dim, factor)
	elif identity == "bastion":
		var radius: Vector2 = Vector2(20, 6) * factor
		for side: int in [-1, 1]:
			var point: Vector2 = center + Vector2(side * radius.x, radius.y)
			draw_line((point - Vector2(0, factor * 2)).round(), (point + Vector2(0, factor * 2)).round(), dim, factor)
			draw_line(point.round(), (point + Vector2(-side * factor * 5, 0)).round(), dim, factor)
	elif identity == "vane":
		for index: int in range(3):
			var phase: float = _clock * 2.0 - index * 0.28
			var point: Vector2 = (center + Vector2(cos(phase) * 20, sin(phase) * 6) * factor).round()
			draw_rect(Rect2(point, Vector2(factor, factor)), Color(accent.r, accent.g, accent.b, 0.6 - index * 0.14))

func draw_ellipse_shadow(center: Vector2, scale_factor: float) -> void:
	var points: PackedVector2Array = []
	for step in range(24):
		var angle: float = TAU * float(step) / 24.0
		points.append(center + Vector2(cos(angle) * 13.0, sin(angle) * 4.0) * scale_factor)
	draw_colored_polygon(points, Color(0.025, 0.04, 0.055, 0.7))
