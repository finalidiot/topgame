extends Control
## Read-only native-pixel state display. Combat owns every value and timer.
const FrontEnd = preload("res://scripts/front_end.gd")
const LEFT: Vector2 = Vector2(6, 76)
const RIGHT: Vector2 = Vector2(726, 76)
const WIDTH: float = 68.0
const ROW_HEIGHT: float = 72.0
const LABEL_SIZE: int = 10
var _state: Dictionary = {}
var _rows: Dictionary = {"left": [], "right": []}
var _left_origin: Vector2 = LEFT
var _right_origin: Vector2 = RIGHT
var _panel_width: float = WIDTH

func set_layout(layout: Dictionary) -> void:
	_left_origin = layout.get("state_left",LEFT)
	_right_origin = layout.get("state_right",RIGHT)
	_panel_width = float(layout.get("state_width",WIDTH))
	size = layout.get("canvas_size",Vector2(800,480))
	queue_redraw()

func _ready() -> void:
	theme = FrontEnd.make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(800, 480)

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
	if bool(redline.get("owned", false)):
		var active: bool = bool(redline.get("active", false)) or float(redline.get("excess", 0.0)) > 0.0
		var heat: float = clampf(float(redline.get("heat", 0.0)), 0.0, 1.0)
		var status: String = "REDLINE"
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
	return {"rows": _rows.duplicate(true), "state": _state.duplicate(true), "left": _left_origin, "right": _right_origin,
		"width": _panel_width, "row_height": ROW_HEIGHT, "native_view": [800, 480], "maximum_rows": 4,
		"label_size": LABEL_SIZE, "gameplay_writes": 0, "owns_timers": false, "reduced_flashing_pulses": 0}

func _icon(id: String) -> Texture2D:
	var catalogue = preload("res://scripts/run_powers.gd")
	var family: String = {"anchor":"dead_centre", "sink":"impact_sink", "orbit":"orbit_drive"}.get(id,id)
	var power: Dictionary = catalogue.get_power(family)
	var path: String = str(power.get("icon",""))
	if path.is_empty() or not ResourceLoader.exists(path): return null
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	atlas.region = Rect2(int(power.icon_frame)*16,0,16,16)
	return atlas

func _draw_column(origin: Vector2, rows: Array) -> void:
	if rows.is_empty(): return
	var font: Font = get_theme_default_font()
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var top: Vector2 = origin + Vector2(0,index*ROW_HEIGHT)
		var box := Rect2(top,Vector2(_panel_width,66))
		draw_rect(box,Color("14222c"))
		draw_rect(box,Color("435963"),false,1)
		for corner: Vector2 in [box.position,box.position+Vector2(_panel_width-5,0),box.position+Vector2(0,65),box.position+Vector2(_panel_width-5,65)]:
			draw_line(corner,corner+Vector2(4,0),row.color)
		var icon: Texture2D = _icon(row.id)
		if icon != null: draw_texture(icon,top+Vector2(4,5))
		var label: String = {"anchor":"ANCHOR", "sink":"FORCE", "redline":"REDLINE", "orbit":"DRIVE"}.get(row.id,row.id.to_upper())
		draw_string(font,top+Vector2(22,16),label,HORIZONTAL_ALIGNMENT_LEFT,_panel_width-24,LABEL_SIZE,row.color)
		var value: float = float(row.bars[0].value)
		var detail: String = "HEAT %d%%" % roundi(value*100.0) if row.id == "redline" else "%d%%" % roundi(value*100.0)
		if row.id == "anchor": detail = "STRESS%d" % roundi(value*100.0)
		if row.id == "sink": detail = "%d / %d" % [roundi(float(_state.sink.get("stored",0))),roundi(float(_state.sink.get("capacity",0)))]
		draw_string(font,top+Vector2(5,31),detail,HORIZONTAL_ALIGNMENT_LEFT,_panel_width-10,LABEL_SIZE,Color("d1d9d7"))
		var rect := Rect2(top+Vector2(5,38),Vector2(_panel_width-10,7))
		draw_rect(rect,Color("293943"))
		draw_rect(Rect2(rect.position,Vector2(roundf(rect.size.x*value),7)),row.bars[0].color)
		for tick: int in range(1,4):
			draw_line(rect.position+Vector2(roundf(rect.size.x*tick/4.0),0),rect.position+Vector2(roundf(rect.size.x*tick/4.0),2),Color("a7b7b5"))
		var status: String = str(row.get("status",""))
		if row.id == "redline": status = "ACTIVE" if bool(_state.redline.get("active",false)) else "COOL"
		if row.id == "orbit": status = "DRIFT" if bool(_state.orbit.get("drifting",false)) else "CARVE"
		if row.id == "sink": status = "LOADED" if value >= .95 else ("STORE" if value > .01 else "EMPTY")
		if row.id == "anchor":
			status = {"HIGH LOAD":"HIGH","RECHARGE":"RECOVER"}.get(status,status)
			for threshold: float in [float(row.safe_stress),float(row.overload_stress)]:
				draw_line(rect.position+Vector2(roundf(rect.size.x*threshold),0),rect.position+Vector2(roundf(rect.size.x*threshold),7),Color("dde0ce"))
		draw_string(font,top+Vector2(5,59),status,HORIZONTAL_ALIGNMENT_LEFT,_panel_width-10,LABEL_SIZE,row.color)

func _draw() -> void:
	_draw_column(_left_origin,_rows.left)
	_draw_column(_right_origin,_rows.right)
