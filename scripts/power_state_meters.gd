extends Control
## Read-only native-pixel state display. Combat owns every value and timer.
const FrontEnd = preload("res://scripts/front_end.gd")
const LEFT: Vector2 = Vector2(12, 51)
const RIGHT: Vector2 = Vector2(406, 51)
const WIDTH: float = 222.0
const ROW_HEIGHT: float = 14.0
const LABEL_SIZE: int = 8
var _state: Dictionary = {}
var _rows: Dictionary = {"left": [], "right": []}

func _ready() -> void:
	theme = FrontEnd.make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(640, 360)

func update_state(state: Dictionary) -> void:
	_state = state.duplicate(true)
	_rows = {"left": [], "right": []}
	var anchor: Dictionary = state.get("anchor", {})
	if bool(anchor.get("owned", false)):
		var strength: float = clampf(float(anchor.get("strength", 0.0)), 0.0, 1.0)
		var stress: float = clampf(float(anchor.get("stress", 0.0)), 0.0, 1.0)
		var recovering: bool = bool(anchor.get("recovering", false)) or bool(anchor.get("overloaded", false))
		var status: String = "RECHARGE" if recovering else ("VENT" if bool(anchor.get("venting", false)) else ("HIGH LOAD" if stress >= 0.65 else ("LOAD" if stress >= 0.30 else ("HOLD" if strength >= 0.70 else "SET"))))
		var color: Color = Color("d97c61") if recovering or stress >= 0.65 else (Color("b7a770") if stress >= 0.30 else Color("93bd91"))
		_rows.left.append({"id": "anchor", "status": status, "text": "ANCHOR %s / STRESS %d%%" % [status, roundi(stress * 100.0)],
			"bars": [{"value": stress, "color": color}], "color": Color("c4d9bd"),
			"strength": strength, "safe_stress": float(anchor.get("safe_stress", 0.30)), "overload_stress": float(anchor.get("overload_stress", 0.80))})
	var sink: Dictionary = state.get("sink", {})
	if bool(sink.get("owned", false)):
		_rows.left.append({"id": "sink", "text": "STORED FORCE  %d / %d" % [roundi(float(sink.get("stored", 0.0))), roundi(float(sink.get("capacity", 0.0)))],
			"bars": [{"value": clampf(float(sink.get("ratio", 0.0)), 0.0, 1.0), "color": Color("a68cd0")}], "color": Color("c5b4dd")})
	var redline: Dictionary = state.get("redline", {})
	if bool(redline.get("owned", false)) or float(redline.get("excess", 0.0)) > 0.0:
		var active: bool = bool(redline.get("active", false)) or float(redline.get("excess", 0.0)) > 0.0
		var heat: float = clampf(float(redline.get("heat", 0.0)), 0.0, 1.0)
		var status: String = "OVERDRIVE" if active else "REDLINE"
		var suffix: String = " +%d%%" % roundi(float(redline.get("excess", 0.0)) * 100.0) if float(redline.get("excess", 0.0)) > 0.0 else ""
		_rows.right.append({"id": "redline", "active": active, "text": "%s%s / HEAT %d%%" % [status, suffix, roundi(heat * 100.0)],
			"bars": [{"value": heat, "color": Color("d87960")}], "color": Color("efb099")})
	var orbit: Dictionary = state.get("orbit", {})
	if bool(orbit.get("owned", false)):
		var drive: float = clampf(float(orbit.get("drive", 0.0)), 0.0, 1.0)
		_rows.right.append({"id": "orbit", "text": "DRIVE %d%%  /  %s" % [roundi(drive * 100.0), "DRIFTING" if bool(orbit.get("drifting", false)) else "CARVE TO BUILD"],
			"bars": [{"value": drive, "color": Color("79b8d1")}], "color": Color("b1d5e0")})
	queue_redraw()

func diagnostic_snapshot() -> Dictionary:
	return {"rows": _rows.duplicate(true), "state": _state.duplicate(true), "left": LEFT, "right": RIGHT,
		"width": WIDTH, "row_height": ROW_HEIGHT, "native_view": [640, 360], "maximum_rows": 4,
		"label_size": LABEL_SIZE, "gameplay_writes": 0, "owns_timers": false, "reduced_flashing_pulses": 0}

func _draw_column(origin: Vector2, rows: Array) -> void:
	if rows.is_empty(): return
	var font: Font = get_theme_default_font()
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var top: Vector2 = origin + Vector2(10, index * ROW_HEIGHT)
		draw_string(font, top + Vector2(0, 8), str(row.text), HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 20, LABEL_SIZE, row.color)
		var bars: Array = row.bars
		var width: float = (WIDTH - 20.0 - (bars.size() - 1) * 6.0) / bars.size()
		for bar_index: int in range(bars.size()):
			var bar: Dictionary = bars[bar_index]
			var rect: Rect2 = Rect2(top + Vector2(bar_index * (width + 6.0), 10), Vector2(width, 3))
			draw_rect(rect, Color("263641"))
			draw_rect(Rect2(rect.position, Vector2(roundf(width * float(bar.value)), 3)), bar.color)
			if row.id == "anchor":
				for threshold: float in [float(row.safe_stress), float(row.overload_stress)]:
					draw_line(rect.position + Vector2(roundf(width * threshold), 0), rect.position + Vector2(roundf(width * threshold), 3), Color("dde0ce"))

func _draw() -> void:
	_draw_column(LEFT, _rows.left)
	_draw_column(RIGHT, _rows.right)
