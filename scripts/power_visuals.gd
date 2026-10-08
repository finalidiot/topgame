extends RefCounted
## Presentation-only atlas renderer. All positions arrive already projected.
## No collision queries, random numbers, timers, or gameplay writes belong here.

const Signature = preload("res://scripts/signature_visuals.gd")
const Identity = preload("res://scripts/power_identity.gd")
const Defence = preload("res://scripts/defence_art.gd")
const SMALL: Texture2D = preload("res://assets/powers/small_top.png")
const EFFECTS: Texture2D = preload("res://assets/powers/effects.png")
const ICONS: Texture2D = preload("res://assets/powers/icons.png")
const ESCALATION_EFFECTS: Texture2D = preload("res://assets/powers/escalation_effects.png")
const ESCALATION_ICONS: Texture2D = preload("res://assets/powers/escalation_icons.png")
const ROSTER_ICONS: Texture2D = preload("res://assets/powers/roster_icons.png")
const ESCALATION_KINDS: Array[String] = ["redline_ii", "runaway", "runaway_hit", "breakneck_charge", "breakneck_impact", "anchor", "anchor_ii", "anchor_break", "bulwark", "bulwark_impact", "counterweight", "counterweight_store", "counterweight_release", "afterimage_ii", "ghost_closure", "ghost_activation", "slipstream_cross", "rank_up", "mutation_select"]
static var metadata: Dictionary = {}
static var escalation_metadata: Dictionary = {}
static var roster_metadata: Dictionary = {}
static var feedback_metadata: Dictionary = {}
static var feedback_textures: Dictionary = {}

static func _meta(group: String) -> Dictionary:
	if group.begins_with("roster_"):
		if roster_metadata.is_empty():
			roster_metadata=JSON.parse_string(FileAccess.get_file_as_string("res://assets/powers/roster_manifest.json"))
		return roster_metadata.get(group.trim_prefix("roster_"),{})
	if group.begins_with("escalation_"):
		if escalation_metadata.is_empty():
			var parsed_escalation: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/powers/escalation_manifest.json"))
			if parsed_escalation is Dictionary:
				escalation_metadata = parsed_escalation
		return escalation_metadata.get(group.trim_prefix("escalation_"), {})
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
	var redline: Dictionary = redline_presentation(str(effect.get("kind", "")))
	if redline.handled:
		if redline.ring:
			var duration: float = maxf(0.01, float(effect.get("duration", 0.3)))
			var age: float = float(effect.get("age", 0.0))
			var alpha: float = clampf((1.0 - age / duration) * 2.0, 0.0, 1.0)
			_cell(canvas, "effects", EFFECTS, _frame("effects", "corona", age, false, duration), position, Color(1.0, 0.62, 0.58, alpha))
		return
	if Defence.effect(canvas, effect, position): return
	if Identity.effect(canvas,effect,position): return
	if Signature.effect(canvas,effect,position):
		if effect.kind == "counterweight_release": _draw_force_release(canvas,effect.get("direction",Vector2.RIGHT),position,float(effect.age)/float(effect.duration))
		return
	var kind: String = str(effect.get("kind", "impact_wake"))
	var age: float = float(effect.get("age", 0.0))
	var duration: float = maxf(0.01, float(effect.get("duration", 0.4)))
	if kind in ESCALATION_KINDS:
		var escalation_tag: String = kind
		var escalation_frame: int = _frame("escalation_effects", escalation_tag, age, false, duration)
		if kind == "breakneck_charge":
			escalation_tag = "breakneck_charge_headings"
			escalation_frame = int(_meta("escalation_effects").tags[escalation_tag].from) + _heading(effect.get("direction", Vector2.RIGHT))
		var fade: float = clampf((1.0 - age / duration) * 2.0, 0.0, 1.0)
		_cell(canvas, "escalation_effects", ESCALATION_EFFECTS, escalation_frame, position, Color(1.0, 1.0, 1.0, fade))
		if kind == "counterweight_release":
			_draw_force_release(canvas, effect.get("direction", Vector2.RIGHT), position, age / duration)
		return
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

static func redline_presentation(kind: String) -> Dictionary:
	# Keep the saved native ring. Sparse heat/overcap information is now on
	# the HUD; the former fragment-cloud cels add no useful physical feedback.
	var handled: bool = kind in ["redline", "redline_ii", "redline_release", "runaway", "runaway_hit", "redline_overcap", "redline_heat"]
	return {"handled": handled, "ring": handled and kind not in ["redline_overcap", "redline_heat"], "particle_cels": 0, "source": "native effects/corona", "gameplay_writes": 0}

static func draw_aura(canvas: CanvasItem, fighter: Dictionary, position: Vector2, clock: float, quality: float = 1.0) -> void:
	if not str(fighter.get("outcome", "")).is_empty():
		return
	Signature.aura(canvas,fighter,position,clock)
	Identity.aura(canvas,fighter,position,clock)
	Defence.aura(canvas, fighter, position)
	_draw_anchor_feedback(canvas, fighter, position + Vector2(0.0, float(fighter.get("height", 0.0))), clock, quality)
	if float(fighter.get("slipstream_time", 0.0)) > 0.0 and Identity.family_info("afterimage").is_empty():
		_cell(canvas, "escalation_effects", ESCALATION_EFFECTS, _frame("escalation_effects", "slipstream_cross", clock, true), position, Color(1.0, 1.0, 1.0, 0.80))

static func draw_trace(canvas: CanvasItem, trace: Dictionary, from_screen: Vector2, to_screen: Vector2, quality: float = 1.0) -> void:
	draw_trace_path(canvas, trace, PackedVector2Array([from_screen, to_screen]), quality)

static func draw_trace_path(canvas: CanvasItem, trace: Dictionary, points: PackedVector2Array, quality: float = 1.0) -> void:
	if points.size() < 2:
		return
	var maximum: float = maxf(0.01, float(trace.get("max_life", 0.45)))
	var life: float = clampf(float(trace.get("life", maximum)), 0.0, maximum)
	var age: float = maximum - life
	# Modern paid routes retain a clear physical lane, then release during their
	# final second. Increasing lifetime while fading from birth made most of the
	# retained route too faint to matter at the native battle scale.
	var extended: bool = bool(trace.get("extended_route", false))
	var fade: float = clampf(life / 0.90, 0.0, 1.0) if extended else life / maximum
	var alpha: float = (0.72 if extended else 0.50) * fade
	var rank: int = int(trace.get("rank", 1))
	var mutation: String = str(trace.get("mutation", ""))
	var energized: bool = bool(trace.get("energized", false))
	if rank >= 2 or not mutation.is_empty():
		var route_ink: Color = Color(0.25, 0.59, 0.72, 0.72 * fade)
		var route_light: Color = Color(0.64, 0.90, 0.90, 0.67 * fade)
		if mutation == "ghost_circuit":
			route_ink = Color(0.15, 0.48, 0.41, 0.70 * fade)
			route_light = Color(0.45, 0.86, 0.69, (0.95 if energized else 0.66) * fade)
		if energized:
			route_ink.a = maxf(route_ink.a, 0.58)
			route_light.a = maxf(route_light.a, 0.78)
		# Rounded integer lane and evenly spaced bearings expose the route itself.
		for index: int in range(points.size() - 1):
			canvas.draw_line(points[index].round(), points[index + 1].round(), route_ink, 3.0)
			canvas.draw_line(points[index].round(), points[index + 1].round(), route_light, 1.0)
		_draw_route_nodes(canvas, points, route_light, mutation, energized, quality)
		return
	# Sparse scars explicitly expose the active lane. Echoes have no bit, cap,
	# shadow or ownership marker, so they cannot read as another physical rig.
	var middle: Vector2 = points[points.size() / 2]
	for index: int in range(points.size() - 1):
		canvas.draw_line(points[index].round(), points[index + 1].round(), Color(0.27, 0.65, 0.76, alpha), 2.0 if extended else 1.0)
		if extended: canvas.draw_line(points[index].round(), points[index + 1].round(), Color(0.65, 0.86, 0.90, alpha * 0.66), 1.0)
	Signature.cel(canvas,"afterimage","rank1_trace",middle,age,0.70 * fade if extended else 0.70)
	if quality >= 0.5:
		Signature.cel(canvas,"afterimage","rank1_trace",points[0],age,0.38 * fade if extended else 0.38)

static func _feedback_cel(canvas: CanvasItem, tag: String, position: Vector2, clock: float, alpha: float, stage: int = -1) -> void:
	var manifest: String = "res://assets/powers/feedback_002c5_2/manifest.json"
	if feedback_metadata.is_empty() and FileAccess.file_exists(manifest):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		if parsed is Dictionary: feedback_metadata = parsed
	var meta: Dictionary = feedback_metadata.get("effects", {}).get("centre", {})
	if meta.is_empty() or not meta.get("tags", {}).has(tag): return
	var texture_path: String = str(meta.texture)
	if not feedback_textures.has(texture_path): feedback_textures[texture_path] = load(texture_path)
	var texture: Texture2D = feedback_textures[texture_path]
	if texture == null: return
	var span: Dictionary = meta.tags[tag]
	var frame: int = int(span.from)
	if stage >= 0:
		frame += clampi(stage, 0, int(span.to) - int(span.from))
	else:
		var duration: float = 0.0
		for index: int in range(int(span.from), int(span.to) + 1): duration += float(meta.durations_ms[index]) / 1000.0
		var age: float = fmod(maxf(0.0, clock), maxf(0.01, duration)) if bool(span.get("loop", false)) else maxf(0.0, clock)
		frame = int(span.to)
		for index: int in range(int(span.from), int(span.to) + 1):
			age -= float(meta.durations_ms[index]) / 1000.0
			if age < 0.0:
				frame = index
				break
	var size: Vector2 = Vector2(float(meta.cell[0]), float(meta.cell[1]))
	var pivot: Vector2 = Vector2(float(meta.pivot[0]), float(meta.pivot[1]))
	var source: Rect2 = Rect2(Vector2(frame % int(meta.columns), frame / int(meta.columns)).floor() * size, size)
	canvas.draw_texture_rect_region(texture, Rect2((position - pivot).round(), size), source, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))

static func _draw_anchor_feedback(canvas: CanvasItem, fighter: Dictionary, floor_at: Vector2, clock: float, quality: float) -> void:
	if not bool(fighter.get("anchor_feedback_enabled", false)) or not str(fighter.get("outcome", "")).is_empty(): return
	var charge: float = clampf(float(fighter.get("anchor_charge", 0.0)), 0.0, 1.0)
	if charge <= 0.07: return
	var maturity: float = clampf(float(fighter.get("anchor_maturity", 0.0)), 0.0, 1.0)
	_feedback_cel(canvas, "centre_seek", floor_at, clock * (0.65 + maturity * 1.2), 0.30 + charge * 0.50)
	if charge >= 0.35:
		var strong: bool = int(fighter.get("power_ranks", {}).get("dead_centre", 1)) >= 2 or maturity >= 0.65
		var deploy: int = clampi(roundi((charge - 0.35) / 0.35 * 5.0), 0, 5)
		_feedback_cel(canvas, "centre_brace_full" if strong else "centre_brace", floor_at, 0.0, 0.45 + charge * 0.55, deploy)
	var hit: float = float(fighter.get("anchor_hit_time", 0.0))
	if hit > 0.0: _feedback_cel(canvas, "centre_recoil", floor_at, 0.32 - hit, hit / 0.32)
	if not bool(fighter.get("anchor_central_hold", false)): return
	# White/grey floor arcs contract toward the actual socket. Their extent and
	# cadence follow the live bounded pull, never a detached targeting widget.
	var reach: float = float(fighter.get("anchor_pull_radius", 0.0))
	var pulse: float = fmod(clock * (0.55 + maturity * 0.95), 1.0)
	for bank: int in range(3 if quality >= 0.5 else 2):
		var cycle: float = fmod(pulse + float(bank) / 3.0, 1.0)
		var radius: float = lerpf(maxf(18.0, reach * 0.46), 8.0, cycle)
		var ink: Color = Color(0.78, 0.80, 0.80, (0.15 + maturity * 0.35) * sin(cycle * PI))
		for sector: int in range(4):
			var arc: PackedVector2Array = PackedVector2Array()
			for vertex: int in range(5):
				var angle: float = float(sector) * PI * 0.5 + float(vertex) * 0.15 + clock * 0.10
				arc.append((floor_at + Vector2(cos(angle) * radius, sin(angle) * radius * 0.50)).round())
			canvas.draw_polyline(arc, ink, 1.0)

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
	if str(fighter.get("outcome", "")).is_empty():
		var recovered: float = float(fighter.get("clutch_recovery_time",0.0))
		if int(fighter.get("power_ranks",{}).get("clutch",0)) > 0 and recovered > 0.0:
			# A real earned catch settles the blade above its unchanged Bit.
			# This never alters RPM, wobble, phase, actor position or collision.
			var catch_amount: float = clampf(recovered/0.80,0.0,1.0)
			return {"phase":int(fighter.get("phase",0))%8,"lean":Vector2(roundf(catch_amount*3.0),roundf(catch_amount)),"stance":roundf(catch_amount*2.0)}
		var comet: float = float(fighter.get("iron_comet_time",0.0))
		if int(fighter.get("power_ranks",{}).get("iron_comet",0)) > 0 and comet > 0.0:
			var span: float = 2.8 if int(fighter.power_ranks.iron_comet) >= 2 else 2.0
			var armed_age: float = maxf(0.0,span-comet)
			if armed_age < 0.28:
				return {"phase":int(fighter.get("phase",0))%8,"lean":Vector2.ZERO,"stance":roundf(sin(armed_age/0.28*PI)*3.0)}
	var anchor: float = clampf(float(fighter.get("anchor_charge", 0.0)), 0.0, 1.0)
	if anchor > 0.25 and str(fighter.get("outcome", "")).is_empty():
		# The Bit/contact never moves. The body visibly settles into its floor locks.
		var mutation: String = str(fighter.get("power_mutations", {}).get("dead_centre", ""))
		var strength: float = 4.0 if mutation == "bulwark" else 2.0
		return {"phase": int(fighter.get("phase", 0)) % 8, "lean": Vector2.ZERO, "stance": roundf(anchor * strength)}
	return {}

static func draw_spawn(canvas: CanvasItem, position: Vector2, progress: float) -> void:
	# Four visible mechanical brackets persist through the whole safe-entry cue.
	var age: float = clampf(progress, 0.0, 0.999) * 0.28
	_cell(canvas, "effects", EFFECTS, _frame("effects", "floor_stamp", age), position, Color(1.0, 0.90, 0.65))

static func icon_region(power_id: String) -> Rect2:
	var defence_art: Dictionary = Defence.art(power_id)
	if not defence_art.is_empty(): return Rect2(int(defence_art.icon_frame) * 16, 0, 16, 16)
	var authored: Dictionary = Identity.art(power_id)
	if not authored.is_empty(): return Rect2(int(authored.icon_frame)*16,0,16,16)
	var roster_tags: Dictionary=_meta("roster_icons").get("tags",{})
	if roster_tags.has(power_id): return Rect2(float(roster_tags[power_id].from)*16.0,0.0,16.0,16.0)
	var escalation_tags: Dictionary = _meta("escalation_icons").get("tags", {})
	if escalation_tags.has(power_id):
		return Rect2(float(escalation_tags[power_id].from) * 16.0, 0.0, 16.0, 16.0)
	var meta: Dictionary = _meta("icons")
	var tags: Dictionary = meta.get("tags", {})
	var frame: int = int(tags.get(power_id, {"from": 0})["from"])
	return Rect2(float(frame) * 16.0, 0.0, 16.0, 16.0)

static func icon_texture(power_id: String) -> Texture2D:
	var defence_art: Dictionary = Defence.art(power_id)
	if not defence_art.is_empty(): return Defence.texture(str(defence_art.icon))
	var authored: Dictionary = Identity.art(power_id)
	if not authored.is_empty(): return Identity.texture(str(authored.icon))
	if _meta("roster_icons").get("tags",{}).has(power_id): return ROSTER_ICONS
	return ESCALATION_ICONS if _meta("escalation_icons").get("tags", {}).has(power_id) else ICONS

static func _heading(direction: Vector2) -> int:
	if direction.length_squared() < 0.001:
		return 0
	# Unsquash before selecting a separately baked 2:1 isometric heading.
	var projected: Vector2 = Vector2(direction.x - direction.y, direction.x + direction.y)
	return posmod(int(roundf(projected.angle() / (TAU / 8.0))), 8)

static func _screen_direction(direction: Vector2) -> Vector2:
	return Vector2(direction.x - direction.y, (direction.x + direction.y) * 0.5).normalized()

static func _draw_overload_wake(canvas: CanvasItem, velocity: Vector2, position: Vector2, clock: float, heat: float, quality: float) -> void:
	if velocity.length_squared() < 100.0:
		return
	var forward: Vector2 = _screen_direction(velocity)
	var side: Vector2 = forward.orthogonal()
	var center: Vector2 = position - Vector2(0.0, 14.0)
	var length: float = 18.0 + heat * 34.0
	var phase: int = int(clock * (18.0 + heat * 16.0)) % 3
	for lane: int in range(2 if quality >= 0.5 else 1):
		var offset: Vector2 = side * (6.0 if lane == 0 else -6.0)
		var start: Vector2 = (center + offset - forward * 12.0).round()
		var middle: Vector2 = (center + offset - forward * (length * 0.55) + side * float(phase - 1) * 3.0).round()
		var end: Vector2 = (center + offset - forward * length).round()
		canvas.draw_polyline(PackedVector2Array([start, middle, end]), Color(0.93, 0.39, 0.24, 0.65), 2.0)
		canvas.draw_line(start, middle, Color(1.0, 0.77, 0.42, 0.78), 1.0)

static func _draw_force_release(canvas: CanvasItem, direction: Vector2, position: Vector2, progress: float) -> void:
	var forward: Vector2 = _screen_direction(direction)
	if forward.length_squared() < 0.1:
		forward = Vector2.RIGHT
	var side: Vector2 = forward.orthogonal()
	var alpha: float = maxf(0.0, 1.0 - progress)
	for index: int in range(3):
		var center: Vector2 = position + forward * (11.0 + progress * 48.0 + index * 9.0)
		var rear: Vector2 = center - forward * 7.0
		canvas.draw_polyline(PackedVector2Array([(rear + side * 5.0).round(), center.round(), (rear - side * 5.0).round()]), Color(0.96, 0.77, 0.42, alpha), 2.0)

static func _draw_route_nodes(canvas: CanvasItem, points: PackedVector2Array, ink: Color, mutation: String, energized: bool, quality: float) -> void:
	var spacing: float = 13.0 if energized else 22.0
	var carried: float = 0.0
	var count: int = 0
	for index: int in range(points.size() - 1):
		var segment: Vector2 = points[index + 1] - points[index]
		var distance: float = segment.length()
		if distance < 0.01:
			continue
		var forward: Vector2 = segment / distance
		var side: Vector2 = forward.orthogonal()
		var along: float = spacing - carried
		while along <= distance:
			var node: Vector2 = (points[index] + forward * along).round()
			if mutation == "slipstream":
				canvas.draw_polyline(PackedVector2Array([(node - forward * 3.0 + side * 2.0).round(), (node + forward * 2.0).round(), (node - forward * 3.0 - side * 2.0).round()]), ink, 1.0)
			else:
				Signature.cel(canvas,"afterimage","ghost_active" if energized else "rank2_trace",node,0.2,ink.a)
			count += 1
			if count >= (24 if quality >= 0.5 else 12):
				return
			along += spacing
		carried = fmod(carried + distance, spacing)

static func draw_circuit_field(canvas: CanvasItem, trace: Dictionary, points: PackedVector2Array) -> void:
	if points.size() < 4 or not bool(trace.get("energized", false)):
		return
	var maximum: float = maxf(0.01, float(trace.get("max_life", 5.0)))
	var fade: float = clampf(float(trace.get("life", maximum)) / maximum * 2.0, 0.0, 1.0)
	var ink: Color = Color(0.15, 0.48, 0.41, 0.65 * fade)
	var light: Color = Color(0.45, 0.86, 0.69, 0.84 * fade)
	var closed: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		closed.append(point.round())
	closed.append(points[0].round())
	canvas.draw_polyline(closed, light, 1.0)
	_draw_circuit_field(canvas, closed, ink, light)
	var age: float = float(trace.get("presentation_circuit_age",1.0))
	if age < 0.55:
		var center: Vector2 = Vector2.ZERO
		for point: Vector2 in points: center += point
		center /= float(points.size())
		var contracted: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in closed: contracted.append(point.lerp(center,age*0.75).round())
		canvas.draw_polyline(closed,Color(0.8,1.0,0.85,1.0-age),2.0)
		canvas.draw_polyline(contracted,Color(0.32,0.8,0.67,0.65-age),1.0)
		Signature.cel(canvas,"afterimage","ghost_closure",points[0],age)

static func _draw_circuit_field(canvas: CanvasItem, points: PackedVector2Array, ink: Color, light: Color) -> void:
	# The authored connected line remains the focus. Sparse interior pressure lines
	# show enclosure without filling the floor or pretending to create more hits.
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	ink.a *= 0.30
	var stripe_count: int = mini(7, int((maximum.y - minimum.y) / 7.0))
	for stripe: int in range(stripe_count):
		var y: float = roundf(lerpf(minimum.y, maximum.y, float(stripe + 1) / float(stripe_count + 1)))
		var intersections: Array[float] = []
		for index: int in range(points.size()):
			var a: Vector2 = points[index]
			var b: Vector2 = points[(index + 1) % points.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				intersections.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		intersections.sort()
		for pair: int in range(0, intersections.size() - 1, 2):
			canvas.draw_line(Vector2(roundf(intersections[pair]), y), Vector2(roundf(intersections[pair + 1]), y), ink, 1.0)
	canvas.draw_rect(Rect2(points[0].round() - Vector2(3.0, 2.0), Vector2(6.0, 4.0)), light, false, 1.0)
