extends RefCounted
## Presentation-only atlas renderer. All positions arrive already projected.
## No collision queries, random numbers, timers, or gameplay writes belong here.

const SMALL: Texture2D = preload("res://assets/powers/small_top.png")
const EFFECTS: Texture2D = preload("res://assets/powers/effects.png")
const ICONS: Texture2D = preload("res://assets/powers/icons.png")
static var metadata: Dictionary = {}

static func _meta(group: String) -> Dictionary:
	if metadata.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/powers/manifest.json"))
		if parsed is Dictionary:
			metadata = parsed
	return metadata.get(group, {})

static func _frame(group: String, tag: String, elapsed: float, loop: bool = false, duration: float = -1.0) -> int:
	var meta: Dictionary = _meta(group)
	var tags: Dictionary = meta.get("tags", {})
	if not tags.has(tag):
		return 0
	var first: int = int(tags[tag]["from"])
	var last: int = int(tags[tag]["to"])
	var durations: Array = meta["durations_ms"]
	var total: float = 0.0
	for i: int in range(first, last + 1):
		total += float(durations[i]) / 1000.0
	var t: float = maxf(0.0, elapsed)
	if duration > 0.0:
		t *= total / duration
	if loop:
		t = fmod(t, maxf(total, 0.001))
	for i: int in range(first, last + 1):
		t -= float(durations[i]) / 1000.0
		if t < 0.0:
			return i
	return last

static func _cell(canvas: CanvasItem, group: String, texture: Texture2D, frame: int, position: Vector2, tint: Color = Color.WHITE) -> void:
	var meta: Dictionary = _meta(group)
	if meta.is_empty():
		return
	var size: Vector2 = Vector2(float(meta["cell"][0]), float(meta["cell"][1]))
	var pivot: Vector2 = Vector2(float(meta["pivot"][0]), float(meta["pivot"][1]))
	var columns: int = int(meta["columns"])
	var bounded: int = clampi(frame, 0, int(meta["frame_count"]) - 1)
	var source: Rect2 = Rect2(Vector2(float(bounded % columns) * size.x, floorf(float(bounded) / float(columns)) * size.y), size)
	canvas.draw_texture_rect_region(texture, Rect2((position - pivot).round(), size), source, tint)

static func draw_small(canvas: CanvasItem, fighter: Dictionary, position: Vector2, clock: float) -> void:
	var outcome: String = str(fighter.get("outcome", ""))
	var age: float = float(fighter.get("out_time", 0.0))
	if not outcome.is_empty() and age > 0.34:
		return
	var frame: int = _frame("small_top", "spin", clock + float(fighter.get("entity_id", 0)) * 0.07, true)
	if not outcome.is_empty():
		frame = _frame("small_top", "retire", age)
	elif float(fighter.get("impact_time", 0.0)) > 0.0:
		frame = _frame("small_top", "contact", 0.0)
	_cell(canvas, "small_top", SMALL, frame, position)

static func draw_effect(canvas: CanvasItem, effect: Dictionary, position: Vector2, quality: float = 1.0) -> void:
	var kind: String = str(effect.get("kind", "impact_wake"))
	var age: float = float(effect.get("age", 0.0))
	var duration: float = maxf(0.01, float(effect.get("duration", 0.4)))
	var tag: String = "contact_arc"
	var tint: Color = Color.WHITE
	match kind:
		"impact_wake", "chain_impact":
			tag = "pressure"
			if kind == "chain_impact":
				# Lift the cyan source red channel into a warm metal release;
				# ordinary RGB multiplication by orange would turn it muddy green.
				tint = Color(3.2, 1.25, 0.60)
		"second_wind":
			tag = "recovery"
		"redline":
			tag = "corona"
		"redline_release":
			tag = "corona"
			tint = Color(0.7, 0.56, 0.50, maxf(0.0, 1.0 - age / duration))
		"comet_charge", "wave", "spawn", "small_retire":
			tag = "floor_stamp"
		"comet_release":
			tag = "contact_arc"
		"afterimage":
			tag = "echo"
	if quality < 0.5 and kind in ["afterimage", "redline_release"]:
		return
	_cell(canvas, "effects", EFFECTS, _frame("effects", tag, age, false, duration), position, tint)
	# A sharp local contact core makes the beginning of a pressure wave legible.
	# The two-cell ceiling also applies to full quality during a dense chain.
	if kind in ["impact_wake", "chain_impact"] and age < 0.19:
		_cell(canvas, "effects", EFFECTS, _frame("effects", "contact_arc", age, false, 0.22), position)

static func draw_aura(canvas: CanvasItem, fighter: Dictionary, position: Vector2, clock: float, quality: float = 1.0) -> void:
	if not str(fighter.get("outcome", "")).is_empty():
		return
	if float(fighter.get("redline_time", 0.0)) > 0.0:
		var tint: Color = Color(1.0, 1.0, 1.0, 0.82 if quality < 0.5 else 1.0)
		_cell(canvas, "effects", EFFECTS, _frame("effects", "corona", clock, true), position, tint)
	if float(fighter.get("iron_comet_time", 0.0)) > 0.0:
		var velocity: Vector2 = fighter.get("vel", Vector2.RIGHT)
		if velocity.length_squared() < 1.0:
			velocity = fighter.get("facing", Vector2.RIGHT)
		var angle: float = Vector2(velocity.x - velocity.y, velocity.x + velocity.y).angle()
		var heading: int = posmod(int(roundf(angle / (TAU / 8.0))), 8)
		var first: int = int(_meta("effects")["tags"]["comet_headings"]["from"])
		_cell(canvas, "effects", EFFECTS, first + heading, position)

static func draw_trace(canvas: CanvasItem, trace: Dictionary, from_screen: Vector2, to_screen: Vector2, quality: float = 1.0) -> void:
	draw_trace_path(canvas, trace, PackedVector2Array([from_screen, to_screen]), quality)

static func draw_trace_path(canvas: CanvasItem, trace: Dictionary, points: PackedVector2Array, quality: float = 1.0) -> void:
	if points.size() < 2:
		return
	var maximum: float = maxf(0.01, float(trace.get("max_life", 0.45)))
	var life: float = clampf(float(trace.get("life", maximum)), 0.0, maximum)
	var age: float = maximum - life
	var alpha: float = 0.50 * life / maximum
	# Sparse scars explicitly expose the active lane. Echoes have no bit, cap,
	# shadow or ownership marker, so they cannot read as another physical rig.
	var middle: Vector2 = points[points.size() / 2]
	for index: int in range(points.size() - 1):
		canvas.draw_line(points[index].round(), points[index + 1].round(), Color(0.27, 0.65, 0.76, alpha), 1.0)
	_cell(canvas, "effects", EFFECTS, _frame("effects", "echo", age, false, maximum), middle, Color(1.0, 1.0, 1.0, 0.70))
	if quality >= 0.5:
		_cell(canvas, "effects", EFFECTS, _frame("effects", "echo", age + 0.08, false, maximum), points[0], Color(1.0, 1.0, 1.0, 0.38))

static func recovery_pose(fighter: Dictionary, effects: Array[Dictionary]) -> Dictionary:
	# Compress only the recovering rig, with the Bit fixed at its contact pivot.
	# The stopped phase is captured by add_power_fx, independent of current RPM.
	for effect: Dictionary in effects:
		if str(effect.get("kind", "")) != "second_wind" or int(effect.get("owner_entity_id", -1)) != int(fighter.get("entity_id", 0)):
			continue
		var age: float = float(effect.get("age", 0.0))
		if age < 0.32:
			var contraction: float = clampf(age / 0.24, 0.0, 1.0)
			return {"phase": posmod(int(effect.get("phase", 0)) + int(age * 5.0), 8), "lean": Vector2(roundf(contraction * 4.0), 1.0), "stance": roundf(contraction * 4.0)}
		var release: float = clampf((age - 0.32) / 0.20, 0.0, 1.0)
		return {"phase": int(fighter.get("phase", 0)) % 8, "lean": Vector2.ZERO, "stance": roundf(-2.0 * (1.0 - release))}
	return {}

static func draw_spawn(canvas: CanvasItem, position: Vector2, progress: float) -> void:
	# Four visible mechanical brackets persist through the whole safe-entry cue.
	var age: float = clampf(progress, 0.0, 0.999) * 0.28
	_cell(canvas, "effects", EFFECTS, _frame("effects", "floor_stamp", age), position, Color(1.0, 0.90, 0.65))

static func icon_region(power_id: String) -> Rect2:
	var meta: Dictionary = _meta("icons")
	var tags: Dictionary = meta.get("tags", {})
	var frame: int = int(tags.get(power_id, {"from": 0})["from"])
	return Rect2(float(frame) * 16.0, 0.0, 16.0, 16.0)
