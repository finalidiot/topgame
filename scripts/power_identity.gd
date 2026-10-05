extends RefCounted
## Read-only art direction: authored cels, true headings and existing live state.
## This module never advances gameplay timers, writes a fighter, queries physics
## or samples RNG. One finite event uses one native cel; active marks are bounded.
const PATH: String = "res://assets/powers/identity_manifest.json"
static var metadata: Dictionary = {}
static var textures: Dictionary = {}
static var event_lookup: Dictionary = {}

static func meta() -> Dictionary:
	if metadata.is_empty() and FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			metadata = parsed
			for family: String in metadata.get("families", {}):
				for kind: String in metadata.families[family].get("event_tags", {}):
					event_lookup[kind] = family
	return metadata

static func art(art_id: String) -> Dictionary:
	return meta().get("art", {}).get(art_id, {}).duplicate(true)

static func family_info(family: String) -> Dictionary:
	return meta().get("families", {}).get(family, {})

static func event_family(kind: String) -> String:
	meta()
	return str(event_lookup.get(kind, ""))

static func texture(path: String) -> Texture2D:
	if not textures.has(path): textures[path] = load(path)
	return textures[path] as Texture2D

static func has_active(family: String, semantic: String) -> bool:
	return family_info(family).get("active_tags", {}).has(semantic)

static func direction_screen(direction: Vector2) -> Vector2:
	return Vector2(direction.x-direction.y, (direction.x+direction.y)*0.5).normalized()

static func ghost_preview_points(fighter: Dictionary, floor_at: Vector2) -> PackedVector2Array:
	var preview: Dictionary = fighter.get("ghost_preview",{})
	if not preview.has("a") or not preview.has("b"): return PackedVector2Array()
	var origin: Vector2 = fighter.get("pos",Vector2.ZERO)
	var points: PackedVector2Array = PackedVector2Array()
	for endpoint: Vector2 in [Vector2(preview.a),Vector2(preview.b)]:
		var offset: Vector2 = endpoint-origin
		points.append(floor_at+Vector2(offset.x-offset.y,(offset.x+offset.y)*0.5))
	return points

static func heading(direction: Vector2) -> String:
	var projected: Vector2 = Vector2(direction.x-direction.y, (direction.x+direction.y)*0.5)
	return ["e", "se", "s", "sw", "w", "nw", "n", "ne"][posmod(int(roundf(projected.angle()/(TAU/8.0))), 8)]

static func contact_art_direction(kind: String, force_direction: Vector2) -> Vector2:
	# Guard's emitted vector is incoming force toward its owner. The exposed
	# damper faces the attacking contact, opposite that already-applied force.
	return -force_direction if kind == "crash_guard" else force_direction

static func variant(family: String, base: String, rank: int, direction: Vector2) -> String:
	var tags: Dictionary = family_info(family).get("fx", {}).get("tags", {})
	var developed: String = base + "_ii" if rank >= 2 else base
	for candidate: String in [developed+"_"+heading(direction), developed, base+"_"+heading(direction), base]:
		if tags.has(candidate): return candidate
	return ""

static func frame(family: String, tag: String, age: float, loop: bool = false) -> int:
	var m: Dictionary = family_info(family).get("fx", {})
	var span: Dictionary = m.get("tags", {}).get(tag, {})
	if span.is_empty(): return -1
	var total: float = 0.0
	for index: int in range(int(span.from), int(span.to)+1): total += float(m.durations_ms[index])*0.001
	var remaining: float = fmod(maxf(0.0,age), maxf(0.001,total)) if loop else maxf(0.0,age)
	for index: int in range(int(span.from), int(span.to)+1):
		remaining -= float(m.durations_ms[index])*0.001
		if remaining < 0.0: return index
	return int(span.to)

static func cel(canvas: CanvasItem, family: String, tag: String, at: Vector2, age: float,
	alpha: float = 1.0, stage: int = -1, loop: bool = false) -> bool:
	var m: Dictionary = family_info(family).get("fx", {})
	var span: Dictionary = m.get("tags", {}).get(tag, {})
	if span.is_empty(): return false
	var index: int = frame(family,tag,age,loop) if stage < 0 else int(span.from)+clampi(stage,0,int(span.to)-int(span.from))
	var size: Vector2 = Vector2(float(m.cell[0]), float(m.cell[1]))
	var pivot: Vector2 = Vector2(float(m.pivot[0]), float(m.pivot[1]))
	var source: Rect2 = Rect2(Vector2(index%int(m.columns)*size.x, floori(float(index)/float(m.columns))*size.y),size)
	canvas.draw_texture_rect_region(texture(str(m.texture)),Rect2((at-pivot).round(),size),source,Color(1,1,1,clampf(alpha,0.0,1.0)))
	return true

static func chain_visual_plan(effect_data: Dictionary) -> Array[Dictionary]:
	# Presentation follows existing paid provenance. The first historical burst
	# and at most two real receiver reactions retain the three-cel ceiling.
	var age: float = maxf(0.0, float(effect_data.get("age", 0.0)))
	var duration: float = maxf(0.001, float(effect_data.get("duration", 0.38)))
	var result: Array[Dictionary] = [{"historical":true,"position":Vector2(effect_data.pos),"progress":clampf(age/duration,0.0,1.0)}]
	var index: int = 0
	for receiver: Vector2 in effect_data.get("receivers", []):
		if index >= 2: break
		var delay: float = 0.055 + float(index)*0.05
		if age >= delay:
			result.append({"historical":false,"position":receiver,"progress":clampf((age-delay)/maxf(0.001,duration-delay),0.0,1.0)})
		index += 1
	return result

static func historical_chain_cel(canvas: CanvasItem, at: Vector2, progress: float) -> bool:
	var m: Dictionary = family_info("chain_impact").get("historical_fx", {})
	if m.is_empty(): return false
	var span: Dictionary = m.tags.pressure
	var total: float = 0.0
	for index: int in range(int(span.from), int(span.to)+1): total += float(m.durations_ms[index])
	var remaining: float = progress*total
	var key: int = int(span.to)
	for index: int in range(int(span.from), int(span.to)+1):
		remaining -= float(m.durations_ms[index])
		if remaining < 0.0: key = index; break
	var size: Vector2 = Vector2(m.cell[0], m.cell[1])
	var pivot: Vector2 = Vector2(m.pivot[0], m.pivot[1])
	var source: Rect2 = Rect2(Vector2(key%int(m.columns)*size.x, floori(float(key)/float(m.columns))*size.y),size)
	canvas.draw_texture_rect_region(texture(str(m.texture)), Rect2((at-pivot).round(),size),source,Color(3.2,1.25,0.60))
	return true

static func effect(canvas: CanvasItem, effect_data: Dictionary, at: Vector2) -> bool:
	var kind: String = str(effect_data.kind)
	var family: String = event_family(kind)
	if family.is_empty(): return false
	var info: Dictionary = family_info(family)
	var direction: Vector2 = contact_art_direction(kind,effect_data.get("direction", Vector2.RIGHT))
	var tag: String = variant(family, str(info.event_tags[kind]), int(effect_data.get("rank",1)), direction)
	if tag.is_empty(): return false
	var span: Dictionary = info.fx.tags[tag]
	var authored_duration: float = 0.0
	for index: int in range(int(span.from), int(span.to)+1): authored_duration += float(info.fx.durations_ms[index])*0.001
	var progress: float = clampf(float(effect_data.age)/maxf(0.001,float(effect_data.duration)),0.0,1.0)
	if family == "chain_impact" and info.has("historical_fx"):
		var origin: Vector2 = effect_data.pos
		for item: Dictionary in chain_visual_plan(effect_data):
			var offset: Vector2 = Vector2(item.position)-origin
			var point: Vector2 = at+Vector2(offset.x-offset.y,(offset.x+offset.y)*0.5)
			if item.historical:
				historical_chain_cel(canvas,point,float(item.progress))
			else:
				cel(canvas,family,tag,point,float(item.progress)*authored_duration,0.95)
		return true
	if family == "chain_impact" and not effect_data.get("receivers",[]).is_empty():
		var origin: Vector2 = effect_data.pos
		var receiver_index: int = 0
		for receiver: Vector2 in effect_data.receivers:
			var offset: Vector2 = receiver-origin
			var finish: Vector2 = at+Vector2(offset.x-offset.y,(offset.x+offset.y)*0.5)
			var delay: float = float(receiver_index)*0.10
			var travel: float = clampf((progress-delay)*1.8,0.0,1.0)
			if progress >= delay and progress < delay+0.70:
				# Sparse impulse link follows real nearby recipients of this pulse.
				var tip: Vector2 = at.lerp(finish,travel)
				canvas.draw_line(at.lerp(tip,0.68).round(),tip.round(),Color(0.95,0.71,0.36,1.0-travel*0.45),1.0)
				var receiver_tag: String = variant(family,str(info.event_tags[kind]),int(effect_data.get("rank",1)),offset)
				cel(canvas,family,receiver_tag,tip,progress*authored_duration,0.9)
			receiver_index += 1
		return true
	return cel(canvas,family,tag,at,progress*authored_duration,1.0)

static func active(canvas: CanvasItem, family: String, semantic: String, fighter: Dictionary,
	at: Vector2, age: float, alpha: float = 1.0, stage: int = -1) -> bool:
	var info: Dictionary = family_info(family)
	if not info.get("active_tags", {}).has(semantic): return false
	var base: String = str(info.active_tags[semantic])
	if family == "high_gear":
		var branch: String = str(fighter.get("power_mutations",{}).get(family,""))
		if info.active_tags.has(branch): base = str(info.active_tags[branch])
		elif not branch.is_empty() and not variant(family,branch,1,fighter.get("vel",Vector2.RIGHT)).is_empty(): base = branch
	var tag: String = variant(family,base,int(fighter.get("power_ranks",{}).get(family,1)),fighter.get("vel",Vector2.RIGHT))
	return cel(canvas,family,tag,at,age,alpha,stage,stage < 0)

static func bank_stored_stage(fighter: Dictionary) -> int:
	# This is a read-only choice among existing native charge cels. An earned
	# positive amount must not truncate to the intentionally empty key zero.
	var rank: int = int(fighter.get("power_ranks",{}).get("momentum_bank",0))
	var bank: float = float(fighter.get("momentum_charge",0.0))
	if rank <= 0 or bank <= 3.0 or not str(fighter.get("outcome","")).is_empty(): return -1
	var cap: float = 150.0 if rank >= 2 else 95.0
	return clampi(int(ceilf(bank/cap*7.0)),1,7)

static func aura(canvas: CanvasItem, fighter: Dictionary, at: Vector2, clock: float) -> void:
	if not str(fighter.get("outcome", "")).is_empty(): return
	var floor_at: Vector2 = at+Vector2(0,float(fighter.get("height",0.0)))
	var velocity: Vector2 = fighter.get("vel",Vector2.ZERO)
	var ranks: Dictionary = fighter.get("power_ranks",{})
	if int(ranks.get("redline",0)) > 0:
		# Retained fragmented C4 signatures carry the sustained wake. One
		# additional authored state exposes actual unsafe heat or excess spin.
		var heat: float = clampf(float(fighter.get("redline_heat",0.0)),0.0,1.0)
		if heat >= 0.70: active(canvas,"redline","heat",fighter,at,clock,heat)
		elif float(fighter.get("rpm",0.0)) > 1.0:
			active(canvas,"redline","overcap",fighter,at,clock,0.35+heat*0.45)
	var anchor_charge: float = float(fighter.get("anchor_charge",0.0))
	if anchor_charge > 0.07 and has_active("dead_centre","anchor"):
		var semantic: String = "anchor_ii" if int(ranks.get("dead_centre",1)) >= 2 and has_active("dead_centre","anchor_ii") else "anchor"
		var branch: String = str(fighter.get("power_mutations",{}).get("dead_centre",""))
		if branch in ["bulwark","counterweight"] and has_active("dead_centre",branch): semantic = branch
		var stage: int = clampi(int(roundf(anchor_charge*7.0)),0,7)
		if semantic == "counterweight": stage = clampi(int(ceilf(float(fighter.get("stored_force",0.0))/150.0*7.0)),0,7)
		active(canvas,"dead_centre",semantic,fighter,floor_at,clock,0.35+anchor_charge*0.65,stage)
	if int(ranks.get("iron_comet",0)) > 0 and float(fighter.get("iron_comet_time",0.0)) > 0.0:
		var span: float = 2.8 if int(ranks.iron_comet) >= 2 else 2.0
		var age: float = maxf(0.0,span-float(fighter.iron_comet_time))
		active(canvas,"iron_comet","charged" if age < 0.28 else "flight",fighter,at,age)
	if int(ranks.get("high_gear",0)) > 0 and velocity.length_squared() > 14400.0:
		active(canvas,"high_gear","speed",fighter,at,clock)
	if bool(fighter.get("drift_active",false)):
		active(canvas,"orbit_drive","drift",fighter,floor_at,clock)
	if bool(fighter.get("clutch_active",false)) or float(fighter.get("clutch_time",0.0)) > 0.0:
		active(canvas,"clutch","danger",fighter,floor_at,clock)
	if float(fighter.get("clutch_recovery_time",0.0)) > 0.0:
		active(canvas,"clutch","recover",fighter,floor_at,clock)
	if float(fighter.get("guard_time",0.0)) > 0.0:
		active(canvas,"crash_guard","guarded",fighter,at,clock,0.58)
	var bank_stage: int = bank_stored_stage(fighter)
	if bank_stage >= 0:
		active(canvas,"momentum_bank","stored",fighter,floor_at,0.0,0.84,bank_stage)

static func draw_links(canvas: CanvasItem, fighters: Array[Dictionary], clock: float) -> void:
	if not has_active("predator_line","tracking"): return
	for fighter: Dictionary in fighters:
		var stacks: int = clampi(int(fighter.get("hunt_stacks",0)),0,3)
		if stacks == 0 or not str(fighter.get("outcome","")).is_empty(): continue
		var target: Dictionary = {}
		for candidate: Dictionary in fighters:
			if int(candidate.entity_id) == int(fighter.get("hunt_target",0)) and str(candidate.get("outcome","")).is_empty(): target = candidate; break
		if target.is_empty(): continue
		var origin: Vector2 = fighter.pos
		var direction: Vector2 = Vector2(target.pos)-origin
		if direction.length_squared() > 25600.0: continue
		var from_screen: Vector2 = canvas.call("project",origin)
		var info: Dictionary = family_info("predator_line")
		var tag: String = variant("predator_line",str(info.active_tags.tracking),int(fighter.get("power_ranks",{}).get("predator_line",1)),direction)
		# Pursuit scuffs start at the hunter's actual floor contact and point
		# toward its one live rival. No detached midpoint hardware or reticle.
		cel(canvas,"predator_line",tag,from_screen,clock,0.55+float(stacks)*0.10,stacks*2)
