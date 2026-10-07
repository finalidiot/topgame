extends Control
## Pixel-perfect workshop assembly, built from the same three parts as combat.
const StarterDefinitions = preload("res://scripts/starters.gd")
const Parts = preload("res://scripts/parts.gd")

var build: Dictionary = {"blade": "balance", "ratchet": "mid", "bit": "ball"}
var animated: bool = true
var preview_scale: float = 3.0
var _clock: float = 0.0
var _textures: Dictionary = {}
var identity: String = ""
var accent: Color = Color.WHITE
var show_station: bool = false
var _images: Dictionary = {}
var _geometry: Dictionary = {}
const STATION_PATH: String = "res://assets/ui/human_feedback003a/preview_station.png"

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

func set_collection_build(value: Dictionary) -> void:
	# The save's first-choice history is not a permanent rendering class. Only
	# an exact authored assembly keeps that starter's enamel and motion rhythm.
	set_build(value)
	identity = ""
	accent = Color.WHITE
	for starter_id: String in StarterDefinitions.IDS:
		if value == StarterDefinitions.build_for(starter_id):
			var data: Dictionary = StarterDefinitions.get_starter(starter_id)
			identity = starter_id
			accent = data.accent
			break
	queue_redraw()

func _process(delta: float) -> void:
	if animated:
		_clock += delta
		queue_redraw()

func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path] as Texture2D

func _image(path: String) -> Image:
	if not _images.has(path):
		var texture: Texture2D = _texture(path)
		var pixels: Image = texture.get_image() if texture != null else null
		if pixels != null and pixels.is_compressed(): pixels.decompress()
		_images[path] = pixels
	return _images[path] as Image

func assembly_geometry() -> Dictionary:
	# The machine's visible assembly, rather than its 48px export cell/contact
	# pivot, owns menu placement. Union every authored rotor key once so wide,
	# asymmetric and narrow blades stay centred without spin-frame jitter.
	var height: float = Parts.visual_height(build)
	var identity_path: String = "res://assets/top/starters/%s_spin.png" % identity
	var blade_path: String = identity_path if not identity.is_empty() and ResourceLoader.exists(identity_path) else "res://assets/top/parts/blades/%s_spin.png" % str(build.get("blade", "balance"))
	var key: String = JSON.stringify(build) + "/" + blade_path + "/" + str(height)
	if _geometry.has(key): return _geometry[key]
	var base: Rect2 = Rect2()
	for category: String in ["bit", "ratchet"]:
		var pixels: Image = _image(Parts.texture_path(category, str(build.get(category, ""))))
		if pixels == null: continue
		var used: Rect2 = Rect2(pixels.get_used_rect())
		if used.has_area(): base = base.merge(used) if base.has_area() else used
	var blade: Image = _image(blade_path)
	var union: Rect2 = base
	var frames: Array[Rect2] = []
	if blade != null:
		var columns: int = maxi(1, blade.get_width() / 48)
		var count: int = columns * maxi(1, blade.get_height() / 48)
		for index: int in range(count):
			var source: Rect2i = Rect2i((index % columns) * 48, floori(float(index) / columns) * 48, 48, 48)
			var used: Rect2 = Rect2(blade.get_region(source).get_used_rect())
			used.position.y += height
			var frame: Rect2 = base.merge(used) if base.has_area() and used.has_area() else (used if used.has_area() else base)
			frames.append(frame)
			if frame.has_area(): union = union.merge(frame) if union.has_area() else frame
	if not union.has_area(): union = Rect2(0, 0, 48, 48)
	var result: Dictionary = {"bounds":union, "center":union.get_center(), "frames":frames, "blade_path":blade_path, "height":height}
	_geometry[key] = result
	return result

func preview_origin() -> Vector2:
	return (size * 0.5 - Vector2(assembly_geometry().center) * preview_scale).round()

func ambient_samples(clock: float) -> Array[Dictionary]:
	# A finite analytic schedule consumes no simulation/cosmetic RNG and creates
	# no particle nodes. Irregular hot fragments go out; controlled cool flecks
	# come in. Existing Vane orbit remains unchanged in _draw_identity_motion.
	var samples: Array[Dictionary] = []
	if identity not in ["breaker", "bastion"]: return samples
	var cycle: float = fposmod(clock, 4.5)
	var times: Array[float] = [0.31, 1.04, 1.53, 2.63, 3.08, 3.91]
	for index: int in range(times.size()):
		var life: float = 0.42 + float(index % 3) * 0.065
		var age: float = cycle - times[index]
		if age < 0.0 or age >= life: continue
		var progress: float = age / life
		var angle: float = [0.28, 2.63, 4.98, 0.94, 3.68, 5.74][index]
		var radius: float = (17.0 + progress * (11.0 + index % 3)) if identity == "breaker" else (31.0 * (1.0 - progress))
		var point: Vector2 = Vector2(cos(angle) * radius, sin(angle) * radius * 0.36)
		if identity == "breaker": point.y -= progress * (2.0 + index % 2)
		samples.append({"offset":point, "alpha":(0.84 if identity == "breaker" else 0.95) * (1.0 - progress),
			"radius":radius, "direction":"outward" if identity == "breaker" else "inward"})
	return samples

func _draw() -> void:
	var scale_factor: float = preview_scale
	var origin: Vector2 = preview_origin()
	# Whole pixel motion keeps the authored silhouettes crisp. Breaker hunts,
	# Bastion stays planted, and Vane glides through a small elliptical orbit.
	if identity == "breaker":
		origin += Vector2(roundf(sin(_clock * 5.0) * 3.0), roundf(cos(_clock * 7.0) * 1.0))
	elif identity == "vane":
		origin += Vector2(roundf(cos(_clock * 1.8) * 6.0), roundf(sin(_clock * 1.8) * 2.0))
	var blade_id: String = str(build.get("blade", "balance"))
	var ratchet_id: String = str(build.get("ratchet", "mid"))
	var bit_id: String = str(build.get("bit", "ball"))
	var height_offset: float = Parts.visual_height(build)
	var contact: Vector2 = origin + Vector2(24.0, 40.0) * scale_factor
	if show_station:
		var station: Texture2D = _texture(STATION_PATH)
		if station != null:
			# The authored fixture is centred on the display, never baked behind
			# unrelated menus. Gameplay/contact pivots retain their original data.
			draw_texture(station, (Vector2(size.x * 0.5, contact.y) - Vector2(80, 18)).round())
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
	for sample: Dictionary in ambient_samples(_clock):
		var point: Vector2 = (center + Vector2(sample.offset) * factor).round()
		var tint: Color = Color("ed654c") if identity == "breaker" else Color("79bed0")
		tint.a = float(sample.alpha)
		# Only the new ambient flecks are clipped to their owned preview. Small
		# ceremony displays must not shed pixels into the adjacent machine card.
		var fleck: Rect2 = Rect2(point, Vector2(factor, factor)).intersection(Rect2(Vector2.ZERO, size))
		if fleck.has_area(): draw_rect(fleck, tint)
	if identity == "vane":
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
