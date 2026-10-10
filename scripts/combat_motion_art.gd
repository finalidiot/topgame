extends RefCounted
## Saved native mechanical accents. Direction/history come from presentation
## observers; this renderer never writes actors, clocks, physics or random streams.
const PATH: String = "res://assets/powers/combat_003a1/manifest.json"
static var metadata: Dictionary = {}
static var textures: Dictionary = {}

static func info(family: String) -> Dictionary:
	if metadata.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: metadata = parsed
	return metadata.get("families", {}).get(family, {})

static func frame(family: String, tag: String, age: float, looping: bool = false) -> int:
	var m: Dictionary = info(family)
	var span: Dictionary = m.get("tags", {}).get(tag, {})
	if span.is_empty(): return -1
	var length: float = 0.0
	for key: int in range(int(span.from), int(span.to) + 1): length += float(m.durations_ms[key]) * 0.001
	var left: float = fposmod(maxf(0.0, age), maxf(0.001, length)) if looping else maxf(0.0, age)
	for key: int in range(int(span.from), int(span.to) + 1):
		left -= float(m.durations_ms[key]) * 0.001
		if left < 0.0: return key
	return int(span.to)

static func cel(canvas: CanvasItem, family: String, tag: String, at: Vector2, age: float, alpha: float = 1.0, looping: bool = false) -> bool:
	var m: Dictionary = info(family)
	var key: int = frame(family, tag, age, looping)
	if key < 0: return false
	var path: String = str(m.texture)
	if not textures.has(path): textures[path] = load(path)
	var tex: Texture2D = textures[path]
	if tex == null: return false
	var cell: Vector2 = Vector2(m.cell[0], m.cell[1])
	var pivot: Vector2 = Vector2(m.pivot[0], m.pivot[1])
	var source: Rect2 = Rect2(Vector2(key % int(m.columns), floori(float(key) / float(m.columns))) * cell, cell)
	canvas.draw_texture_rect_region(tex, Rect2((at - pivot).round(), cell), source, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	return true
