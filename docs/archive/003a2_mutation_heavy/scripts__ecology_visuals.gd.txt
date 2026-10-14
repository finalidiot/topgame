extends RefCounted
## Sparse, read-only mounted feedback from earned III state. Existing saved
## native family cels keep the accepted visual grammar and nearest pixels.
const Identity = preload("res://scripts/power_identity.gd")

static func effect(canvas: CanvasItem, data: Dictionary, at: Vector2, quality: float) -> bool:
	var kind: String = str(data.get("ecology_kind",""))
	if kind.is_empty(): return false
	var family: String = ""
	var base: String = ""
	match kind:
		"wallbreaker_arm", "ricochet_rebound": family = "iron_comet"; base = "comet_charge"
		"wallbreaker_hit", "ricochet_hit": family = "iron_comet"; base = "comet_impact"
		"wallbreaker_miss", "flywheel_miss", "ricochet_break", "perpetual_break": family = "orbit_drive"; base = "orbit_drift"
		"centrifuge_hit", "reactive_counter": family = "crosscut"; base = "shear_slice"
		"flywheel_release", "flywheel_hit", "countersteer": family = "momentum_bank"; base = "bank_release"
		"reactive_charge", "damper_absorb": family = "crash_guard"; base = "damper_contact"
	if family.is_empty(): return false
	var direction: Vector2 = data.get("direction",Vector2.RIGHT)
	if family == "crash_guard": direction = -direction
	var tag: String = Identity.variant(family,base,2,direction)
	var meta: Dictionary = Identity.family_info(family).fx
	var span: Dictionary = meta.tags.get(tag,{})
	if span.is_empty(): return false
	var total: float = 0.0
	for index: int in range(int(span.from),int(span.to)+1): total += float(meta.durations_ms[index])*0.001
	var progress: float = clampf(float(data.age)/maxf(0.001,float(data.duration)),0.0,1.0)
	Identity.cel(canvas,family,tag,at,progress*total,0.65 if quality < 0.5 else 0.90)
	return true

static func aura(canvas: CanvasItem, f: Dictionary, at: Vector2, quality: float) -> void:
	if not str(f.get("outcome","")).is_empty(): return
	var floor_at: Vector2 = at+Vector2(0,float(f.get("height",0.0)))
	var alpha: float = 0.55 if quality < 0.5 or canvas.get("reduced_flashing") == true else 0.80
	var commit: float = float(f.get("ecology_commit_time",0.0))
	if commit > 0.0:
		var direction: Vector2 = Identity.direction_screen(f.get("ecology_heading",f.get("vel",Vector2.RIGHT)))
		var side: Vector2 = direction.orthogonal()*3.0
		var tip: Vector2 = (floor_at+direction*17.0).round()
		canvas.draw_polyline(PackedVector2Array([(tip-direction*4.0+side).round(),tip,(tip-direction*4.0-side).round()]),Color(0.94,0.68,0.36,alpha),1.0)
	var beats: int = clampi(int(f.get("ricochet_count",0)),0,3)
	for index: int in range(beats):
		canvas.draw_rect(Rect2((floor_at+Vector2(-3+index*3,12)).round(),Vector2(2,2)),Color(0.65,0.81,0.90,alpha))
	if float(f.get("reactive_force",0.0)) > 0.0 or float(f.get("damper_time",0.0)) > 0.0:
		var direction: Vector2 = f.get("guard_heading",Vector2(f.get("vel",Vector2.RIGHT)).normalized())
		var tag: String = Identity.variant("crash_guard","damper_contact",2,direction)
		# One held authored terminal fitting, never a flashing or looping blast.
		Identity.cel(canvas,"crash_guard",tag,at,10.0,alpha*0.60)
