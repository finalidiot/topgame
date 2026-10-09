extends RefCounted
## Bounded cosmetic reactions to accepted physical events. No fighter/RNG writes.
const Beasts = preload("res://scripts/beast_manifestations.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const SPARKS = preload("res://assets/powers/impact_003a1/contact_sparks.png")
const CRACKS = preload("res://assets/powers/impact_003a1/contact_crack.png")
const CRACK_WORK: float = 500000.0
const CRACK_CLOSING: float = 140.0
const CRACK_SEVERITY: float = 0.75
const CRACK_COOLDOWN: float = 0.22
const MAX_CRACK_EVENTS: int = 4
const GRIND_CONTINUITY: float = 0.12
const GRIND_TANGENT: float = 24.0
const GRIND_GAP: float = 2.0
const GRIND_SEPARATION_SPEED: float = 70.0
const MAX_GRIND_BODIES: int = 16
const MAX_GRIND_PAIRS: int = 12
const MAX_SPARK_EVENTS: int = 8
const MAX_NUMBERS: int = 4
const NUMBER_MIN_RPM: int = 240
const NUMBER_COOLDOWN: float = 0.60
const MAX_HISTORY: int = 96
var numbers_enabled: bool = false
var _clock: float = 0.0
var _theatre_ready: float = 0.0
var _small_ready: float = 0.0
var _latest_collision: int = 0
var _sparks: Array[Dictionary] = []
var _numbers: Array[Dictionary] = []
var _number_ready: Dictionary = {}
var _eliminations: Dictionary = {}
var _events: Array[Dictionary] = []
var _meta: Dictionary = {}
var _counts: Dictionary = {}
var _confirmation: String = ""
var _confirmation_left: float = 0.0
var _cracks: Array[Dictionary] = []
var _crack_ready: float = 0.0
var _crack_meta: Dictionary = {}
var _grind_pairs: Dictionary = {}
var _grind_state: Dictionary = {"active":false,"strength":0.0,"pitch":1.0,"pairs":0}

func reset() -> void:
	_clock = 0.0
	_theatre_ready = 0.0
	_small_ready = 0.0
	_latest_collision = 0
	_sparks.clear()
	_numbers.clear()
	_number_ready.clear()
	_eliminations.clear()
	_events.clear()
	_counts.clear()
	_confirmation = ""
	_confirmation_left = 0.0
	_cracks.clear()
	_crack_ready = 0.0
	_grind_pairs.clear()
	_grind_state = {"active":false,"strength":0.0,"pitch":1.0,"pairs":0}

static func tier(event: Dictionary) -> String:
	if Beasts.qualifies_impact(event): return "extreme"
	var severity: float = float(event.get("severity", 0.0))
	return "hard" if severity >= 0.75 else ("strong" if severity >= 0.32 else "light")

static func audio_family(event: Dictionary) -> String:
	var level: String = tier(event)
	if level == "extreme": return "metal_extreme"
	if qualifies_crack(event): return "metal_massive"
	if level == "hard": return "metal_clang"
	var normal: Vector2 = event.get("normal", Vector2.RIGHT)
	var relative: Vector2 = Vector2(event.get("first_velocity", Vector2.ZERO)) - Vector2(event.get("second_velocity", Vector2.ZERO))
	var tangent: float = absf(relative.dot(normal.orthogonal()))
	var closing: float = float(event.get("closing", 0.0))
	if tangent > maxf(40.0, closing * 1.4): return "metal_scrape"
	if tangent > maxf(25.0, closing * 0.65): return "metal_edge"
	return "metal_normal" if level == "strong" else "metal_light"

static func qualifies_crack(event: Dictionary) -> bool:
	if Beasts.qualifies_impact(event): return true
	return float(event.get("severity",0.0)) >= CRACK_SEVERITY and float(event.get("closing",0.0)) >= CRACK_CLOSING and float(event.get("impulse",0.0)) * float(event.get("closing",0.0)) >= CRACK_WORK

func _crack(event: Dictionary, level: String) -> String:
	if not qualifies_crack(event) or _clock < _crack_ready: return ""
	_crack_ready = _clock + CRACK_COOLDOWN
	var normal: Vector2 = event.get("normal",Vector2.RIGHT)
	var direction: Vector2 = Vector2(normal.x-normal.y,(normal.x+normal.y)*0.5)
	var facing: int = posmod(roundi(direction.angle()/TAU*8.0),8)
	var tag: String = "extreme" if level == "extreme" else "hard"
	if _cracks.size() >= MAX_CRACK_EVENTS: _cracks.pop_front()
	_cracks.append({"position":event.get("contact_position",event.position),"height":float(event.get("contact_height",12.0)),"tag":tag+"_"+str(facing),"tier":tag,"age":0.0,"duration":0.145 if tag == "extreme" else 0.12,"segments":5 if tag == "extreme" else 3})
	return "metal_crack"

## Read-only geometry sampled once after the completed fixed physics tick.
## Surface continuity and tangential sliding are independent of hit cooldowns.
func observe_grinding(fighters: Array, dt: float) -> void:
	var tops: Array[Dictionary] = []
	for fighter: Dictionary in fighters:
		if fighter.get("combatant_type","") == "full_top" and str(fighter.get("outcome","")).is_empty() and float(fighter.get("rpm",0.0)) > 0.045:
			tops.append(fighter)
			if tops.size() >= MAX_GRIND_BODIES: break
	tops.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.entity_id)<int(b.entity_id))
	var seen: Dictionary = {}
	for first: int in range(tops.size()):
		for second: int in range(first+1,tops.size()):
			if seen.size() >= MAX_GRIND_PAIRS: break
			var a: Dictionary = tops[first]
			var b: Dictionary = tops[second]
			var offset: Vector2 = Vector2(b.pos)-Vector2(a.pos)
			var distance: float = offset.length()
			if distance <= 0.001 or distance-float(a.get("radius",12.0))-float(b.get("radius",12.0)) > GRIND_GAP or absf(float(a.get("height",0.0))-float(b.get("height",0.0))) > 6.0: continue
			var normal: Vector2 = offset/distance
			var relative: Vector2 = Vector2(a.vel)-Vector2(b.vel)
			var tangent: float = absf(relative.dot(normal.orthogonal()))
			if tangent < GRIND_TANGENT or absf(relative.dot(normal)) > GRIND_SEPARATION_SPEED: continue
			var key: String = "%d:%d" % [int(a.entity_id),int(b.entity_id)]
			var held: float = minf(4.0,float(_grind_pairs.get(key,{}).get("held",0.0))+maxf(0.0,dt))
			seen[key] = {"held":held,"tangent":tangent,"missing":0.0}
	# A bounded40ms gap allows a real contact solver's tiny separation jitter;
	# sustained separation, low slip, retired bodies and reset all end the grind.
	for key: String in _grind_pairs:
		if seen.has(key): continue
		var old: Dictionary = _grind_pairs[key]
		if float(old.get("missing",0.0))+dt <= 0.04 and seen.size() < MAX_GRIND_PAIRS:
			seen[key] = {"held":old.held,"tangent":old.tangent,"missing":float(old.get("missing",0.0))+dt}
	_grind_pairs = seen
	var strength: float = 0.0
	var count: int = 0
	for pair: Dictionary in seen.values():
		if float(pair.held)+0.000001 < GRIND_CONTINUITY: continue
		count += 1
		strength = maxf(strength,clampf((float(pair.tangent)-GRIND_TANGENT)/250.0,0.10,1.0)*(0.65 if float(pair.missing)>0.0 else 1.0))
	_grind_state = {"active":count>0,"strength":strength,"pitch":0.90+strength*0.18,"pairs":count}

func grind_snapshot() -> Dictionary:
	return _grind_state.duplicate()

func _record(event: Dictionary) -> void:
	_events.append(event)
	if _events.size() > MAX_HISTORY: _events.pop_front()

func _spark(position: Vector2, normal: Vector2, level: String, height: float = 12.0) -> void:
	var direction: Vector2 = Vector2(normal.x-normal.y, (normal.x+normal.y)*0.5)
	var facing: int = posmod(roundi(direction.angle() / TAU * 8.0), 8)
	var duration: float = {"light":0.169,"strong":0.215,"hard":0.265,"extreme":0.315}[level]
	var item: Dictionary = {"position":position,"height":height,"tag":level+"_"+str(facing),"tier":level,"age":0.0,"duration":duration}
	if _sparks.size() >= MAX_SPARK_EVENTS:
		# An enormous event replaces the least spectacular resolving spray.
		var weakest: int = 0
		for i: int in range(_sparks.size()):
			if ["light","strong","hard","extreme"].find(_sparks[i].tier) < ["light","strong","hard","extreme"].find(_sparks[weakest].tier): weakest = i
		if ["light","strong","hard","extreme"].find(level) < ["light","strong","hard","extreme"].find(_sparks[weakest].tier): return
		_sparks.remove_at(weakest)
	_sparks.append(item)

func _number(event: Dictionary, prefix: String) -> void:
	if not numbers_enabled: return
	var actual: float = float(event.get(prefix+"_rpm_loss", 0.0)) * 9000.0
	var amount: int = roundi(actual)
	var id: int = int(event.get(prefix+"_entity_id", 0))
	if actual < NUMBER_MIN_RPM or id <= 0 or _clock < float(_number_ready.get(id, 0.0)): return
	_number_ready[id] = _clock + NUMBER_COOLDOWN
	if _numbers.size() >= MAX_NUMBERS: _numbers.pop_front()
	_numbers.append({"entity_id":id,"position":Vector2(event.get(prefix+"_position", event.position)),
		"amount":amount,"age":0.0,"duration":0.62,"player":bool(event.get(prefix+"_player", false))})
	while _number_ready.size() > 64: _number_ready.erase(_number_ready.keys()[0])

func accept_impact(event: Dictionary) -> Dictionary:
	var id: int = int(event.get("collision_id", 0))
	if id <= _latest_collision or not Vector2(event.get("position", Vector2.INF)).is_finite(): return {}
	_latest_collision = id
	var level: String = tier(event)
	var cue: String = audio_family(event)
	var crack_cue: String = _crack(event,level)
	_spark(event.get("contact_position", event.position), event.get("normal", Vector2.RIGHT), level, float(event.get("contact_height", 12.0)))
	_number(event, "first")
	_number(event, "second")
	var hold: float = 0.0
	var shake: float = 0.0
	if _clock >= _theatre_ready and level != "light":
		hold = {"strong":1.0/60.0,"hard":3.0/60.0,"extreme":4.0/60.0}[level]
		shake = {"strong":0.65,"hard":2.5,"extreme":4.0}[level]
		_theatre_ready = _clock + (0.35 if level == "extreme" else 0.22)
	_counts[level] = int(_counts.get(level, 0)) + 1
	_record({"collision_id":id,"tier":level,"cue":cue,"crack_cue":crack_cue,"hold":hold,"shake":shake,
		"score":Beasts.impact_metric(event),"contact":event.get("contact_position", event.position),
		"first_rpm_loss":float(event.get("first_rpm_loss", 0.0)),"second_rpm_loss":float(event.get("second_rpm_loss", 0.0))})
	return {"tier":level,"cue":cue,"crack_cue":crack_cue,"hold":hold,"shake":shake}

func accept_small(position: Vector2, normal: Vector2) -> void:
	if _clock < _small_ready: return
	_small_ready = _clock + 0.08
	_spark(position,normal,"light",8.0)

func accept_elimination(fighter: Dictionary) -> Dictionary:
	var id: int = int(fighter.get("entity_id", 0))
	var outcome: String = str(fighter.get("outcome", ""))
	if id <= 0 or _eliminations.has(id) or fighter.get("combatant_type", "") != "full_top" or outcome not in ["spin_out","ring_out","impact"]: return {}
	_eliminations[id] = true
	while _eliminations.size() > 256: _eliminations.erase(_eliminations.keys()[0])
	var kind: String = str(fighter.get("enemy_kind", "rival"))
	_spark(fighter.pos,Vector2(fighter.get("vel", Vector2.RIGHT)).normalized(),"extreme" if kind == "boss" else "hard")
	_confirmation = ("BOSS " if kind == "boss" else ("ELITE " if kind == "elite" else "")) + ("RING OUT" if outcome == "ring_out" else "SPIN OUT")
	_confirmation_left = 0.85
	_record({"elimination_entity_id":id,"outcome":outcome,"enemy_kind":kind})
	return {"cue":"metal_takedown","hold":3.0/60.0 if kind in ["boss","elite"] else 2.0/60.0,"shake":3.0 if kind in ["boss","elite"] else 1.8}

func update(dt: float) -> void:
	_clock += maxf(0.0, dt)
	_confirmation_left = maxf(0.0, _confirmation_left-dt)
	for list: Array[Dictionary] in [_sparks, _numbers, _cracks]:
		for index: int in range(list.size()-1,-1,-1):
			list[index].age += dt
			if float(list[index].age) >= float(list[index].duration): list.remove_at(index)
	if not numbers_enabled: _numbers.clear()

func snapshot() -> Dictionary:
	return {"tiers":_counts.duplicate(),"events":_events.duplicate(true),"sparks":_sparks.duplicate(true),"cracks":_cracks.duplicate(true),"grind":grind_snapshot(),
		"numbers":_numbers.duplicate(true),"spark_cap":MAX_SPARK_EVENTS,"number_cap":MAX_NUMBERS,
		"number_min_rpm":NUMBER_MIN_RPM,"number_cooldown":NUMBER_COOLDOWN,"numbers_enabled":numbers_enabled,
		"confirmation":_confirmation if _confirmation_left > 0.0 else "","gameplay_writes":0}

func confirmation() -> String:
	return _confirmation if _confirmation_left > 0.0 else ""

func _frame(item: Dictionary) -> int:
	if _meta.is_empty(): _meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/powers/impact_003a1/manifest.json"))
	var span: Dictionary = _meta.tags[item.tag]
	var remaining: float = float(item.age)
	for frame: int in range(int(span.from),int(span.to)+1):
		remaining -= float(_meta.durations_ms[frame])/1000.0
		if remaining < 0.0: return frame
	return int(span.to)

func _crack_frame(item: Dictionary) -> int:
	if _crack_meta.is_empty(): _crack_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/powers/impact_003a1/crack_manifest.json"))
	var span: Dictionary = _crack_meta.tags[item.tag]
	var remaining: float = float(item.age)
	for frame: int in range(int(span.from),int(span.to)+1):
		remaining -= float(_crack_meta.durations_ms[frame])/1000.0
		if remaining < 0.0: return frame
	return int(span.to)

func draw(canvas: CanvasItem, project: Callable, reduced_flashing: bool, show_sparks: bool = true) -> void:
	if show_sparks:
		for item: Dictionary in _sparks:
			var index: int = _frame(item)
			var at: Vector2 = project.call(Vector2(item.position)) - Vector2(0,float(item.height))
			canvas.draw_texture_rect_region(SPARKS,Rect2((at-Vector2(32,24)).round(),Vector2(64,48)),
				Rect2(Vector2(index%16*64,index/16*48),Vector2(64,48)),Color(1,1,1,0.70 if reduced_flashing else 1.0))
		for item: Dictionary in _cracks:
			var index: int = _crack_frame(item)
			var at: Vector2 = project.call(Vector2(item.position))-Vector2(0,float(item.height))
			var fade: float = clampf(1.0-float(item.age)/float(item.duration),0.0,1.0)
			canvas.draw_texture_rect_region(CRACKS,Rect2((at-Vector2(32,24)).round(),Vector2(64,48)),Rect2(Vector2(index%16*64,index/16*48),Vector2(64,48)),Color(1,1,1,fade*(0.35 if reduced_flashing else 1.0)))
	var font: Font = FrontEnd.pixel_font()
	if font == null: return
	for item: Dictionary in _numbers:
		var progress: float = float(item.age)/float(item.duration)
		var at: Vector2 = project.call(Vector2(item.position)) + Vector2(-12,-27-progress*9)
		var text: String = "-%d" % int(item.amount)
		var tint: Color = Color("e8a39a") if item.player else Color("f4c57a")
		tint.a = minf(1.0, (1.0-progress)*2.2)
		canvas.draw_string(font,(at+Vector2(1,1)).round(),text,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(0.05,0.08,0.10,tint.a))
		canvas.draw_string(font,at.round(),text,HORIZONTAL_ALIGNMENT_LEFT,-1,10,tint)
