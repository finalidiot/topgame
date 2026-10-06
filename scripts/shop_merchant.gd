extends Control
## Small authored counter attendant; reactions never own purchase state.
const ROOT: String = "res://assets/ui/human_feedback003a/"
var reaction: String = "IDLE"
var _elapsed: float = 0.0
var _sheet: Texture2D
var _metadata: Dictionary = {}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(ROOT + "merchant.png"): _sheet = load(ROOT + "merchant.png")
	if FileAccess.file_exists(ROOT + "merchant.json"):
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "merchant.json"))
		if source is Dictionary: _metadata = source

func react(kind: String) -> void:
	reaction = kind if kind in ["IDLE", "SELECT", "PURCHASE", "RARE"] else "IDLE"
	_elapsed = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	var tag: Dictionary = _metadata.get("tags", {}).get(reaction, {"from":0, "to":3})
	var duration: float = 0.0
	for frame: int in range(int(tag.get("from", 0)), int(tag.get("to", 3)) + 1): duration += _duration(frame)
	if duration > 0.0 and _elapsed >= duration:
		if reaction != "IDLE": react("IDLE")
		else: _elapsed = fmod(_elapsed, duration)
	queue_redraw()

func _duration(frame: int) -> float:
	var durations: Array = _metadata.get("durations_ms", [])
	return float(durations[frame]) / 1000.0 if frame < durations.size() else 0.14

func _draw() -> void:
	if _sheet == null: return
	var tag: Dictionary = _metadata.get("tags", {}).get(reaction, {"from":0, "to":3})
	var left: float = _elapsed
	var selected: int = int(tag.get("from", 0))
	for frame: int in range(selected, int(tag.get("to", selected)) + 1):
		selected = frame
		left -= _duration(frame)
		if left < 0.0: break
	draw_texture_rect_region(_sheet, Rect2(Vector2.ZERO, Vector2(96, 128)), Rect2(selected * 48, 0, 48, 64))
