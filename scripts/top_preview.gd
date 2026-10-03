extends Control
## Pixel-perfect workshop assembly, built from the same three parts as combat.

var build: Dictionary = {"blade": "balance", "ratchet": "mid", "bit": "ball"}
var animated: bool = true
var preview_scale: float = 3.0
var _clock: float = 0.0
var _textures: Dictionary = {}

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
	var blade_id: String = str(build.get("blade", "balance"))
	var ratchet_id: String = str(build.get("ratchet", "mid"))
	var bit_id: String = str(build.get("bit", "ball"))
	var height_offset: float = 3.0 if ratchet_id == "low" else (-3.0 if ratchet_id == "high" else 0.0)
	var contact: Vector2 = origin + Vector2(24.0, 40.0) * scale_factor
	draw_ellipse_shadow(contact, scale_factor)
	var bit: Texture2D = _texture("res://assets/top/parts/bits/%s.png" % bit_id)
	var ratchet: Texture2D = _texture("res://assets/top/parts/ratchets/%s.png" % ratchet_id)
	var blade: Texture2D = _texture("res://assets/top/parts/blades/%s_spin.png" % blade_id)
	var destination: Rect2 = Rect2(origin.round(), Vector2(48.0, 48.0) * scale_factor)
	if bit != null:
		draw_texture_rect(bit, destination, false)
	if ratchet != null:
		draw_texture_rect(ratchet, destination, false)
	if blade != null:
		var phase: int = int(_clock / 0.11) % 8 if animated else 0
		var columns: int = maxi(1, int(blade.get_width()) / 48)
		var source: Rect2 = Rect2(Vector2(phase % columns, phase / columns) * 48.0, Vector2(48.0, 48.0))
		destination.position.y += height_offset * scale_factor
		draw_texture_rect_region(blade, destination, source)

func draw_ellipse_shadow(center: Vector2, scale_factor: float) -> void:
	var points: PackedVector2Array = []
	for step in range(24):
		var angle: float = TAU * float(step) / 24.0
		points.append(center + Vector2(cos(angle) * 13.0, sin(angle) * 4.0) * scale_factor)
	draw_colored_polygon(points, Color(0.025, 0.04, 0.055, 0.7))
