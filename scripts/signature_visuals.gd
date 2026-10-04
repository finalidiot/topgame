extends RefCounted
## Pure draw policy for native Aseprite cels. No simulation writes or RNG.
const SHEETS: Dictionary = {
	"redline":preload("res://assets/powers/signature_redline.png"),
	"dead_centre":preload("res://assets/powers/signature_dead_centre.png"),
	"afterimage":preload("res://assets/powers/signature_afterimage.png"),
	"combat":preload("res://assets/powers/signature_combat.png")}
const EVENTS: Dictionary = {
	"redline":["redline","rank1_active"],"redline_ii":["redline","rank2_active"],
	"runaway":["redline","runaway_low"],"runaway_hit":["redline","runaway_high"],
	"breakneck_charge":["redline","breakneck_charge"],"breakneck_impact":["redline","breakneck_hit"],"breakneck_recovery":["redline","breakneck_recovery"],
	"anchor":["dead_centre","anchor_full"],"bulwark_impact":["dead_centre","bulwark_contact"],
	"counterweight_store":["dead_centre","anchor_full"],"counterweight_release":["dead_centre","counterweight_release"],
	"ghost_closure":["afterimage","ghost_closure"],"ghost_activation":["afterimage","ghost_active"],"slipstream_cross":["afterimage","slipstream_cross"],
	"contact_light":["combat","light"],"contact_meaningful":["combat","meaningful"],"contact_heavy":["combat","heavy"],"contact_signature":["combat","signature"],
	"elite_entry":["combat","elite_entry"],"boss_entry":["combat","boss_entry"],"boss_defeat":["combat","boss_defeat"],"rpm_reclaim":["combat","reclaim"],"second_wind":["combat","second_wind"]}
const FOREGROUND: Array[String] = ["breakneck_impact","breakneck_recovery","runaway_hit","counterweight_release","contact_light","contact_meaningful","contact_heavy","contact_signature","boss_defeat","rpm_reclaim","second_wind","slipstream_cross"]
static var metadata: Dictionary = {}
static func meta(family: String) -> Dictionary:
	if metadata.is_empty(): metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/powers/signature_manifest.json"))
	return metadata[family]
static func frame(family: String, tag: String, age: float, loop: bool = true) -> int:
	var m: Dictionary = meta(family)
	var span: Dictionary = m.tags[tag]
	var total: float = 0.0
	for i: int in range(int(span.from),int(span.to)+1): total += float(m.durations_ms[i])/1000.0
	var t: float = fmod(maxf(age,0.0),total) if loop else maxf(age,0.0)
	for i: int in range(int(span.from),int(span.to)+1):
		t -= float(m.durations_ms[i])/1000.0
		if t < 0.0: return i
	return int(span.to)
static func cel(c: CanvasItem, family: String, tag: String, at: Vector2, age: float = 0.0, alpha: float = 1.0, stage: int = -1) -> void:
	var m: Dictionary = meta(family)
	var i: int = frame(family,tag,age) if stage < 0 else int(m.tags[tag].from)+clampi(stage,0,5)
	c.draw_texture_rect_region(SHEETS[family],Rect2((at-Vector2(48,48)).round(),Vector2(96,80)),Rect2(Vector2(i%6*96,floori(float(i)/6.0)*80),Vector2(96,80)),Color(1,1,1,alpha))
static func redline_tag(f: Dictionary) -> String:
	var branch: String = f.get("redline_active_mutation",f.get("power_mutations",{}).get("redline",""))
	if branch == "breakneck": return "breakneck_charge"
	if branch == "runaway": return "runaway_high" if float(f.get("runaway_heat",0.0)) >= 0.5 else "runaway_low"
	return "rank2_active" if int(f.get("redline_active_rank",f.get("power_ranks",{}).get("redline",1))) >= 2 else "rank1_active"
static func anchor_tag(f: Dictionary) -> String:
	var branch: String = f.get("power_mutations",{}).get("dead_centre","")
	if branch == "counterweight": return "counterweight_store"
	if branch == "bulwark": return "bulwark_lock"
	return "anchor_full" if int(f.get("power_ranks",{}).get("dead_centre",1)) >= 2 and float(f.get("anchor_charge",0.0)) >= 0.7 else "anchor_build"
static func aura(c: CanvasItem, f: Dictionary, at: Vector2, clock: float) -> void:
	if not str(f.get("outcome","")).is_empty(): return
	if float(f.get("redline_time",0.0)) > 0.0:
		var tag: String = redline_tag(f)
		cel(c,"redline",tag,at,clock*(1.6 if tag=="runaway_high" else 1.0))
		var direction: Vector2 = f.get("redline_heading",f.get("vel",Vector2.RIGHT))
		var forward: Vector2 = Vector2(direction.x-direction.y,(direction.x+direction.y)*0.5).normalized()
		# Sprite stays in the fixed projection; composition follows true heading.
		if tag=="breakneck_charge":
			for i: int in range(3): cel(c,"redline",tag,at-forward*float(8+i*12),clock,0.7-float(i)*0.18)
		elif tag != "rank1_active": cel(c,"redline",tag,at-forward*17.0,clock+0.1,0.40)
	var charge: float = float(f.get("anchor_charge",0.0))
	if charge > 0.07:
		var tag: String = anchor_tag(f)
		var stage: int = clampi(int(roundf(charge*5.0)),0,5)
		if tag=="counterweight_store": stage=clampi(int(ceilf(float(f.get("stored_force",0.0))/30.0)),0,5)
		cel(c,"dead_centre",tag,at,clock,0.35+charge*0.65,stage if tag in ["anchor_build","counterweight_store"] else -1)
	if float(f.get("rpm",1.0)) < 0.25: cel(c,"combat","low_rpm",at,clock*0.7)
static func effect(c: CanvasItem, e: Dictionary, at: Vector2) -> bool:
	var kind: String = e.kind
	if not EVENTS.has(kind): return false
	var spec: Array = EVENTS[kind]
	var progress: float = clampf(float(e.age)/maxf(.01,float(e.duration)),0.0,.999)
	cel(c,spec[0],spec[1],at,progress*.48,clampf((1.0-progress)*3.0,0.0,1.0),mini(5,int(progress*6.0)))
	return true
static func entry(c: CanvasItem, at: Vector2, kind: String, remaining: float) -> void:
	cel(c,"combat","boss_entry" if kind=="boss" else "elite_entry",at,maxf(0.0,2.2-remaining))
static func marker(c: CanvasItem, f: Dictionary, at: Vector2, clock: float) -> void:
	if f.get("enemy_kind","")=="elite":
		# Ballast uses broad planted brackets; Hotwire uses a moving split crown.
		if f.get("archetype","")=="ballast": cel(c,"dead_centre","bulwark_lock",at,clock,.65)
		else: cel(c,"combat","elite_entry",at,clock*.5,.65,0)
	elif f.get("enemy_kind","")=="boss": cel(c,"combat","boss_entry",at,clock*.4,.70,5)

static func impact_tier(severity: float, signature: bool = false) -> String:
	return "signature" if signature else ("heavy" if severity>=0.75 else ("meaningful" if severity>=0.32 else "light"))
static func impact_hold(tier: String) -> float:
	return {"light":0.0,"meaningful":1.0/60.0,"heavy":2.0/60.0,"signature":3.0/60.0}[tier]
static func impact_shake(tier: String) -> float:
	return {"light":0.0,"meaningful":0.5,"heavy":1.5,"signature":3.0}[tier]
