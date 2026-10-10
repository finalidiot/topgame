extends Control
## Fixed receipt presentation only. No RNG, ownership or wallet mutation lives here.
signal cue(kind: String)
signal settled
signal presented(cursor: int)

const Catalog = preload("res://scripts/parts.gd")
const ROOT: String = "res://assets/ui/shop_003a/"
var phase: String = "SEALED"
var elapsed: float = 0.0
var opening: bool = false
var receipt: Dictionary = {}
var _packet: Texture2D
var _mat: Texture2D
var _parts: Array[Texture2D] = []
var _clinks: int = 0
var _landed: bool = false
var _metadata: Dictionary = {}
var _tear_seconds: float = 0.64
var _quantity: int = 1
var _cursor: int = 0
var _batch_started: int = -1
var _batch_spilled: int = -1
const BATCH_STAGGER: float = 0.34
const BATCH_PACKET_SECONDS: float = 1.72

func configure(value: Dictionary, recovered: bool = false) -> void:
	receipt = value.duplicate(true)
	_quantity = int(receipt.get("quantity", 1))
	_cursor = int(receipt.get("cursor", 0))
	var basename: String = "reclaimed_packet" if receipt.get("kind", "standard") == "reclaimed" else "packet"
	_packet = load(ROOT + basename + ".png")
	_metadata = JSON.parse_string(FileAccess.get_file_as_string(ROOT + basename + ".json"))
	_tear_seconds = 0.0
	for frame: int in range(int(_metadata.tags.TEAR_START.from), int(_metadata.tags.TEAR_OPEN.to) + 1):
		_tear_seconds += float(_metadata.durations_ms[frame]) / 1000.0
	_mat = load(ROOT + "reveal_mat.png")
	_parts.clear()
	for row: Dictionary in receipt.get("rows", []):
		var texture: Texture2D = load(Catalog.texture_path(str(row.category), str(row.id)))
		var pixels: Image = texture.get_image()
		if pixels.is_compressed(): pixels.decompress()
		var crop: AtlasTexture = AtlasTexture.new()
		crop.atlas = texture
		crop.region = pixels.get_used_rect()
		_parts.append(crop)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if recovered and (_quantity == 1 or _cursor == _quantity): resolve()
	else: queue_redraw()

func tear() -> void:
	if opening or phase == "RESULT": return
	opening = true
	elapsed = 0.0
	phase = "TEAR"
	if _quantity > 1: _batch_started = int(receipt.get("cursor", 0))
	cue.emit("packet_tear")
	queue_redraw()

func resolve() -> void:
	if phase == "RESULT": return
	opening = false
	elapsed = 2.8
	phase = "RESULT"
	_clinks = 3
	_cursor = _quantity
	presented.emit(_cursor)
	cue.emit("packet_clink")
	settled.emit()
	queue_redraw()

func _process(delta: float) -> void:
	if phase == "RESULT": return
	elapsed += delta * (3.5 if opening and Input.is_action_pressed("ui_accept") else 1.0)
	if _quantity > 1:
		_process_batch()
		queue_redraw()
		return
	if not opening:
		if not _landed and elapsed >= 0.18:
			_landed = true
			cue.emit("packet_land")
		if phase == "SEALED" and elapsed >= 0.45:
			phase = "CRINKLE"
			cue.emit("packet_crinkle")
	else:
		if phase == "TEAR" and elapsed >= _tear_seconds:
			phase = "SPILL"
			cue.emit("packet_spill")
		for index: int in range(3):
			if _clinks == index and elapsed >= 1.32 + index * 0.22:
				_clinks += 1
				cue.emit("packet_clink")
		if elapsed >= 2.35: resolve()
	queue_redraw()

func _process_batch() -> void:
	if not opening:
		if not _landed and elapsed >= 0.18:
			_landed = true
			cue.emit("packet_land")
		if phase == "SEALED" and elapsed >= 0.45:
			phase = "CRINKLE"
			cue.emit("packet_crinkle")
		return
	phase = "SPILL"
	var start: int = int(receipt.get("cursor", 0))
	for index: int in range(start, _quantity):
		var local: float = elapsed - (index - start) * BATCH_STAGGER
		if local >= 0 and _batch_started < index:
			_batch_started = index
			cue.emit("packet_tear")
		if local >= _tear_seconds and _batch_spilled < index:
			_batch_spilled = index
			cue.emit("packet_spill")
		if local >= BATCH_PACKET_SECONDS and _cursor <= index:
			_cursor = index + 1
			cue.emit("packet_clink")
			presented.emit(_cursor)
	if _cursor == _quantity: resolve()

func _draw() -> void:
	if _mat != null: draw_texture_rect(_mat, Rect2(48, 58, 544, 268), false)
	if _packet == null: return
	if _quantity > 1:
		_draw_batch()
		return
	var frame: int = 0
	var center: Vector2 = Vector2(320, 218)
	var factor: float = 2.0
	if phase == "SEALED": center.y = 218 - roundf(maxf(0.0, 1.0 - elapsed / 0.18) * 42.0)
	elif phase == "CRINKLE":
		frame = _frame_at("CRINKLE", maxf(0.0, elapsed - 0.45))
	elif phase == "TEAR": frame = _frame_range(int(_metadata.tags.TEAR_START.from), int(_metadata.tags.TEAR_OPEN.to), elapsed)
	elif phase == "SPILL":
		frame = _frame_at("SPILL", elapsed - _tear_seconds)
		if elapsed - _tear_seconds > 0.44: frame = int(_metadata.tags.EMPTY_PACKET.from)
		var slide: float = clampf((elapsed - _tear_seconds) / 0.95, 0.0, 1.0)
		center = Vector2(320, 218).lerp(Vector2(95, 282), slide)
		factor = 2.0 - slide
		# The parts have settled; slide the discarded wrapper off the bench.
		var discard: float = clampf((elapsed - 1.98) / 0.37, 0.0, 1.0)
		center = center.lerp(Vector2(-64, 336), discard)
	elif phase == "RESULT":
		frame = 12
		center = Vector2(95, 282)
		factor = 1.0
	var dimensions: Vector2 = Vector2(96, 96) * factor
	var origin: Vector2 = center - Vector2(48, 86) * factor
	if phase != "RESULT":
		draw_texture_rect_region(_packet, Rect2(origin.round(), dimensions.round()), Rect2(frame * 96, 0, 96, 96))
	if phase not in ["SPILL", "RESULT"]: return
	for index: int in range(_parts.size()):
		var progress: float = 1.0 if phase == "RESULT" else clampf((elapsed - 0.65 - index * 0.13) / 0.85, 0.0, 1.0)
		if progress <= 0.0: continue
		var target: Vector2 = Vector2(164 + index * 156, 166)
		var location: Vector2 = Vector2(335, 102).lerp(target, 1.0 - pow(1.0 - progress, 3.0))
		location.y -= sin(progress * PI) * (20.0 + index * 5.0)
		var texture: Texture2D = _parts[index]
		var scale_factor: int = 3 if str(receipt.rows[index].category) == "bit" else 2
		var size_pixels: Vector2 = texture.get_size() * scale_factor
		draw_style_box(_shadow(), Rect2(location - Vector2(size_pixels.x * 0.42, -size_pixels.y * 0.34), Vector2(size_pixels.x * 0.84, 5)))
		var angle: float = sin(progress * PI) * (0.24 if index % 2 == 0 else -0.28)
		draw_set_transform(location.round(), angle)
		draw_texture_rect(texture, Rect2(-size_pixels * 0.5, size_pixels), false)
		draw_set_transform(Vector2.ZERO)

func _draw_batch() -> void:
	var start: int = int(receipt.get("cursor", 0))
	for index: int in range(_quantity):
		var local: float = elapsed - (index - start) * BATCH_STAGGER
		var done: bool = index < start or phase == "RESULT" or local >= BATCH_PACKET_SECONDS
		if not done:
			var frame: int = 0
			if not opening and phase == "CRINKLE": frame = _frame_at("CRINKLE", maxf(0, elapsed - 0.45))
			elif opening and local >= 0:
				frame = _frame_range(int(_metadata.tags.TEAR_START.from), int(_metadata.tags.TEAR_OPEN.to), local)
				if local >= _tear_seconds: frame = _frame_at("SPILL", local - _tear_seconds)
				if local > _tear_seconds + 0.44: frame = int(_metadata.tags.EMPTY_PACKET.from)
			var center: Vector2 = Vector2(320 + (index - (_quantity - 1) * 0.5) * 76, 217 + absf(index - (_quantity - 1) * 0.5) * 9)
			if not opening: center.y -= roundf(maxf(0, 1 - elapsed / 0.18) * (30 + index * 3))
			if opening and local > _tear_seconds:
				center = center.lerp(Vector2(40 + index * 108, 365), clampf((local - _tear_seconds) / 1.0, 0, 1))
			draw_texture_rect_region(_packet, Rect2((center - Vector2(48, 86)).round(), Vector2(96, 96)), Rect2(frame * 96, 0, 96, 96))
		for category: int in range(3):
			var progress: float = 1.0 if done else (clampf((local - _tear_seconds - category * 0.06) / 0.68, 0, 1) if opening else 0.0)
			if progress <= 0: continue
			var width: float = 596.0 / _quantity
			var target: Vector2 = Vector2(22 + width * (index + 0.5), 106 + category * 62)
			var location: Vector2 = Vector2(320 + (index - (_quantity - 1) * 0.5) * 76, 156).lerp(target, 1.0 - pow(1.0 - progress, 3))
			location.y -= sin(progress * PI) * 13
			var texture: Texture2D = _parts[index * 3 + category]
			var factor: int = 1 if _quantity == 5 else 2
			if category == 2: factor += 1
			var dimensions: Vector2 = texture.get_size() * factor
			draw_texture_rect(texture, Rect2((location - dimensions * 0.5).round(), dimensions), false)

func _frame_at(tag: String, seconds: float) -> int:
	return _frame_range(int(_metadata.tags[tag].from), int(_metadata.tags[tag].to), seconds)

func _frame_range(first: int, last: int, seconds: float) -> int:
	var left: float = seconds * 1000.0
	for frame: int in range(first, last + 1):
		left -= float(_metadata.durations_ms[frame])
		if left < 0.0: return frame
	return last

func _shadow() -> StyleBoxFlat:
	var value: StyleBoxFlat = StyleBoxFlat.new()
	value.bg_color = Color(0, 0, 0, 0.35)
	return value
