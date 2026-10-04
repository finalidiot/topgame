extends RefCounted
## Pure draw policy for native Aseprite cels. No simulation writes or RNG.
const SHEETS: Dictionary = {
	"redline":preload("res://assets/powers/signature_redline.png"),
	"dead_centre":preload("res://assets/powers/signature_dead_centre.png"),
	"afterimage":preload("res://assets/powers/signature_afterimage.png"),
	"roster":preload("res://assets/powers/roster_effects.png"),
	"combat":preload("res://assets/powers/signature_combat.png")}
const EVENTS: Dictionary = {
	"redline":["redline","rank1_active"],"redline_ii":["redline","rank2_active"],
	"runaway":["redline","runaway_low"],"runaway_hit":["redline","runaway_high"],
	"breakneck_charge":["redline","breakneck_charge"],"breakneck_impact":["redline","breakneck_hit"],"breakneck_recovery":["redline","breakneck_recovery"],
	"anchor":["dead_centre","anchor_full"],"bulwark_impact":["dead_centre","bulwark_contact"],
	"counterweight_store":["dead_centre","anchor_full"],"counterweight_release":["dead_centre","counterweight_release"],
	"ghost_closure":["afterimage","ghost_closure"],"ghost_activation":["afterimage","ghost_active"],"slipstream_cross":["afterimage","slipstream_cross"],
	"contact_light":["combat","light"],"contact_meaningful":["combat","meaningful"],"contact_heavy":["combat","heavy"],"contact_signature":["combat","signature"],
	"elite_entry":["combat","elite_entry"],"boss_entry":["combat","boss_entry"],"boss_defeat":["combat","boss_defeat"],"rpm_reclaim":["combat","reclaim"],"second_wind":["combat","second_wind"],
	"comet_charge":["roster","comet_charge"],"comet_release":["roster","comet_impact"],
	"redline_overcap":["roster","overcap"],"redline_heat":["roster","heat_extreme"],
	"clutch_activate":["roster","clutch_danger"],"clutch_recover":["roster","clutch_recover"],
	"high_gear_surge":["roster","terminal_surge"],"orbit_drift":["roster","orbit_drift"],
	"momentum_store":["roster","momentum_store"],"momentum_release":["roster","momentum_release"],
	"crash_guard":["roster","crash_guard"],"predator_lock":["roster","predator_lock"],"crosscut":["roster","crosscut"],"ghost_preview":["roster","ghost_preview"]}
const FOREGROUND: Array[String] = ["breakneck_impact","breakneck_recovery","runaway_hit","counterweight_release","contact_light","contact_meaningful","contact_heavy","contact_signature","boss_defeat","rpm_reclaim","second_wind","slipstream_cross","comet_release","clutch_recover","momentum_release","crosscut"]
static var metadata: Dictionary = {}
static var roster_metadata: Dictionary = {}
static func meta(family: String) -> Dictionary:
	if family == "roster":
		if roster_metadata.is_empty(): roster_metadata=JSON.parse_string(FileAccess.get_file_as_string("res://assets/powers/roster_manifest.json"))
		return roster_metadata.effects
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
		# A modern Breakneck's first overclock is setup; its next paid Burst commits.
		if f.has("redline_commit_time") and tag=="breakneck_charge" and float(f.redline_commit_time)<=0.0: tag="rank2_active"
		cel(c,"redline",tag,at,clock*(1.6 if tag=="runaway_high" else 1.0))
		var direction: Vector2 = f.get("redline_heading",f.get("vel",Vector2.RIGHT))
		var forward: Vector2 = Vector2(direction.x-direction.y,(direction.x+direction.y)*0.5).normalized()
		# Sprite stays in the fixed projection; composition follows true heading.
		if tag=="breakneck_charge":
			for i: int in range(3): cel(c,"redline",tag,at-forward*float(8+i*12),clock,0.7-float(i)*0.18)
		elif tag != "rank1_active": cel(c,"redline",tag,at-forward*17.0,clock+0.1,0.40)
		var heat: float=clampf(float(f.get("redline_heat",f.get("runaway_heat",0.0))),0.0,1.0)
		if float(f.get("rpm",0.0))>1.0:
			cel(c,"roster","overcap",at,clock*(1.1+heat),0.65+heat*0.35)
			rotor_wake(c,at,Vector2(f.get("vel",Vector2.ZERO)),clock,heat,Color(1.0,0.64,0.25,0.75))
		if heat>=0.70: cel(c,"roster","heat_extreme",at,clock*(1.0+heat),heat)
	var comet: float=float(f.get("iron_comet_time",0.0))
	if comet>0.0:
		var span: float=2.8 if int(f.get("power_ranks",{}).get("iron_comet",1))>=2 else 2.0
		var age: float=maxf(0.0,span-comet)
		cel(c,"roster","comet_charge" if age<0.28 else "comet_flight",at,clock)
		rotor_wake(c,at,Vector2(f.get("vel",Vector2.ZERO)),clock,0.55,Color(1.0,0.77,0.40,0.78))
	var gear: int=int(f.get("power_ranks",{}).get("high_gear",0))
	var velocity: Vector2=f.get("vel",Vector2.ZERO)
	if gear>0 and velocity.length_squared()>14400.0:
		var branch: String=f.get("power_mutations",{}).get("high_gear","")
		var gear_tag: String="terminal_surge" if branch=="terminal_velocity" else ("flow_state" if branch=="flow_state" else ("gear2" if gear>=2 else "gear1"))
		cel(c,"roster",gear_tag,at,clock,0.70)
		rotor_wake(c,at,velocity,clock,0.85 if gear>=2 else 0.30,Color(0.50,0.78,0.94,0.65))
	var floor_at: Vector2=at+Vector2(0.0,float(f.get("height",0.0)))
	if bool(f.get("drift_active",false)):
		cel(c,"roster","orbit_drift",floor_at,clock)
	elif float(f.get("orbit_charge",0.0))>0.35:
		cel(c,"roster","flow_state",floor_at,clock,float(f.orbit_charge)*0.60)
	if bool(f.get("clutch_active",false)) or float(f.get("clutch_time",0.0))>0.0:
		cel(c,"roster","clutch_danger",floor_at,clock,0.65)
	if float(f.get("clutch_recovery_time",0.0))>0.0: cel(c,"roster","clutch_recover",floor_at,clock,0.85)
	if float(f.get("guard_time",0.0))>0.0: cel(c,"roster","crash_guard",at,clock,0.55)
	var bank: float=float(f.get("momentum_charge",0.0))
	if bank>3.0: cel(c,"roster","momentum_store",floor_at,0.0,0.75,clampi(int(ceilf(bank/30.0)),0,5))
	if int(f.get("hunt_stacks",0))>0: cel(c,"roster","predator_lock",at,clock,0.3+float(f.hunt_stacks)*0.2)
	closure_preview(c,f,floor_at,clock)
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
	if kind=="comet_release" and progress>0.25:
		cel(c,"roster","comet_recovery",at,0.0,1.0-progress,mini(5,int(progress*6.0)))
	return true

static func rotor_wake(c: CanvasItem, at: Vector2, velocity: Vector2, clock: float, strength: float, ink: Color) -> void:
	if velocity.length_squared()<14400.0: return
	var forward: Vector2=Vector2(velocity.x-velocity.y,(velocity.x+velocity.y)*0.5).normalized()
	var side: Vector2=forward.orthogonal()
	var center: Vector2=at-Vector2(0,14)
	var span: float=18.0+clampf(strength,0.0,1.0)*28.0
	var phase: float=float(int(clock*20.0)%3-1)
	# Two short disconnected rotor wakes, never a filled directional wedge.
	for bank: int in [-1,1]:
		var start: Vector2=center+side*float(bank)*10.0-forward*15.0
		var end: Vector2=center+side*(float(bank)*8.0+phase)-forward*span
		c.draw_line(start.round(),start.lerp(end,0.55).round(),ink,2.0)
		c.draw_line(start.lerp(end,0.72).round(),end.round(),ink,1.0)

static func closure_preview(c: CanvasItem, f: Dictionary, at: Vector2, clock: float) -> void:
	var preview: Dictionary=f.get("ghost_preview",{})
	if preview.is_empty() or not preview.has("a") or not preview.has("b"): return
	var origin: Vector2=f.get("pos",Vector2.ZERO)
	var old: Vector2=Vector2(preview.a)-origin
	var live: Vector2=Vector2(preview.b)-origin
	var a: Vector2=at+Vector2(old.x-old.y,(old.x+old.y)*0.5)
	var b: Vector2=at+Vector2(live.x-live.y,(live.x+live.y)*0.5)
	var strength: float=clampf(float(preview.get("strength",0.0)),0.0,1.0)
	var alpha: float=0.62+strength*0.34
	for dash: int in range(6):
		var t: float=float(dash)/6.0
		c.draw_line(a.lerp(b,t).round(),a.lerp(b,t+0.075).round(),Color(0.72,1.0,0.85,alpha),2.0)
	cel(c,"roster","ghost_preview",a,clock*(1.0+strength),alpha)
	cel(c,"roster","ghost_preview",b,clock*(1.0+strength)+0.08,alpha)
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
