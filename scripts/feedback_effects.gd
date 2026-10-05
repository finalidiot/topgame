extends RefCounted
## Authored pressure waves are triggered only by accepted collision contacts.
const MANIFEST: String = "res://assets/powers/feedback_002c5_2/manifest.json"
static var _metadata: Dictionary = {}
static var _textures: Dictionary = {}

static func impact_tag(strength: float) -> String:
	return "impact_extreme" if strength >= 0.88 else ("impact_heavy" if strength >= 0.50 else "impact_light")

static func _impact_metadata() -> Dictionary:
	if _metadata.is_empty() and FileAccess.file_exists(MANIFEST):
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if decoded is Dictionary: _metadata = decoded
	return _metadata.get("effects", {}).get("impact", {})

static func impact_duration(tag: String) -> float:
	return float(_impact_metadata().get("tags", {}).get(tag, {}).get("duration_ms", 320)) / 1000.0

static func impact_frame(tag: String, age: float) -> int:
	var metadata: Dictionary = _impact_metadata()
	var span: Dictionary = metadata.get("tags", {}).get(tag, {})
	if span.is_empty(): return -1
	var remaining: float = maxf(0.0, age)
	for frame: int in range(int(span.from), int(span.to) + 1):
		var seconds: float = float(metadata.durations_ms[frame]) / 1000.0
		if remaining < seconds: return frame
		remaining -= seconds
	return -1

static func draw_impact(canvas: CanvasItem, event: Dictionary, floor_position: Vector2) -> void:
	var frame: int = impact_frame(str(event.tag), float(event.age))
	if frame < 0: return
	var metadata: Dictionary = _impact_metadata()
	var path: String = str(metadata.get("texture", ""))
	if not ResourceLoader.exists(path): return
	if not _textures.has(path): _textures[path] = load(path)
	var texture: Texture2D = _textures[path]
	var cell: Vector2 = Vector2(metadata.cell[0], metadata.cell[1])
	var pivot: Vector2 = Vector2(metadata.pivot[0], metadata.pivot[1])
	var columns: int = int(metadata.columns)
	var region: Rect2 = Rect2(Vector2(frame % columns, frame / columns) * cell, cell)
	canvas.draw_texture_rect_region(texture, Rect2(floor_position.round() - pivot, cell), region)
