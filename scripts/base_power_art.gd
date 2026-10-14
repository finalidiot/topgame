extends RefCounted
## Native vector identity assets; rank and focus semantics remain in card style.
const IDS: Array[String] = ["crimson_impact", "azure_stability", "emerald_endurance", "true_bearing", "last_stand", "prismatic_current"]
const COLORS: Array[Color] = [Color("ff5968"), Color("62b5ff"), Color("69e997"), Color("d4b0ff"), Color("ffd173"), Color("84eee8")]
const PRISM_COLORS: Array[Color] = [Color("ff657b"), Color("7aeeec"), Color("70baff"), Color("75ec9b")]

static func art(id: String) -> Dictionary:
	var family: String = id.trim_suffix("_ii")
	var index: int = IDS.find(family)
	if index < 0: return {}
	var row: int = index + (6 if id.ends_with("_ii") else 0)
	return {"art_id":id, "source_tag":id, "icon":"res://assets/powers/base003a2/icons.svg", "icon_frame":row, "card_texture":"res://assets/powers/base003a2/cards.svg", "card_row":row, "card_cell":64, "card_frames":6, "card_static_frame":2, "card_durations_ms":[110,90,75,75,100,170], "aura_color":COLORS[index]}

static func _arc(canvas: CanvasItem, at: Vector2, radius: float, start: float, span: float, color: Color, width: float) -> void:
	# Project a thin rim ellipse, never a floor-sized opaque disc.
	var points := PackedVector2Array()
	for step: int in range(9):
		var angle: float = start + span * float(step) / 8.0
		points.append(at + Vector2(cos(angle) * radius, sin(angle) * radius * 0.53))
	canvas.draw_polyline(points, Color(color, color.a * 0.11), width + 3.0, true)
	canvas.draw_polyline(points, Color(color, color.a * 0.80), width, true)

static func aura(canvas: CanvasItem, f: Dictionary, at: Vector2, clock: float, quality: float = 1.0) -> void:
	if not str(f.get("outcome", "")).is_empty(): return
	var owned: Array = f.get("powers", [])
	var radius: float = clampf(float(f.get("radius", 12.0)), 8.0, 17.0)
	# Fixed separated lanes keep every combination bounded and recognizable.
	for index: int in range(IDS.size()):
		if IDS[index] not in owned: continue
		var phase: float = clock * (1.0 + float(index) * 0.11) + float(index) * 0.83
		var color: Color = COLORS[index]
		var r: float = radius + 1.0 + float(index) * 1.8
		var segments: int = 3 if index in [0, 1] else 2
		var span: float = 0.42 if index == 0 else (0.72 if index == 1 else 1.0)
		if index == 3: r = radius - 1.0; segments = 4; span = 0.16
		if index == 4:
			color.a = 1.0 if float(f.get("rpm", 1.0)) < 0.35 else 0.32
			span = 0.50
		if index == 5:
			color = PRISM_COLORS[clampi(int(f.get("prismatic_state", 0)), 0, 3)]
			segments = 4; span = 0.22
		var pulse: float = 0.86 + 0.14 * sin(clock * 3.0 + float(index))
		for segment: int in range(segments):
			var start: float = phase + TAU * float(segment) / float(segments)
			_arc(canvas, at, r, start, span, Color(color, color.a * pulse), 1.2 if quality >= 0.5 else 1.0)
			if index == 0:
				var point: Vector2 = at + Vector2(cos(start) * (r + 1.8), sin(start) * (r + 1.8) * 0.53)
				canvas.draw_line(point, at + Vector2(cos(start + 0.10) * r, sin(start + 0.10) * r * 0.53), color, 1.0, true)
