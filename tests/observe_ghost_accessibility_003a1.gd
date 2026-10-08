extends SceneTree
## Declared starting Ghost investment; all movement/traces/AI/Director are real.
const Battle=preload("res://scripts/battle.gd")
const Encounters=preload("res://scripts/encounters.gd")
const Starters=preload("res://scripts/starters.gd")
const Diagnostics=preload("res://tests/ghost_circuit_diagnostics_003a1.gd")
class ObservedRuntime extends "res://scripts/power_runtime.gd":
	var reasons: Dictionary={}
	var candidates: Array=[]
	var closures: Array=[]
	var calls: int=0
	var emitted_attempts: int=0
	func _modern_circuit(owner: Dictionary, emitted: bool) -> void:
		var row: Dictionary=Diagnostics.analyse(self,owner,emitted)
		calls+=1; if emitted: emitted_attempts+=1
		reasons[row.reason]=int(reasons.get(row.reason,0))+1
		var before: int=int(counters.get("ghost_closure",0))
		super._modern_circuit(owner,emitted)
		var closed: bool=int(counters.get("ghost_closure",0))>before
		if row.has("candidate") and emitted:
			row.actual_closure=closed; candidates.append(row)
			if candidates.size()>2000: candidates.pop_front()
		if closed: closures.append(row)
var report: String
var horizon: float=90
var runs: Array=[]
var case_set: String="standard"
var configurations: Array=[
	{"id":"vane_manual_loop","starter":"vane","pattern":"manual","radius":60.0,"speed":.90,"gear":1,"wobble":0.0},
	{"id":"vane_manual_imperfect","starter":"vane","pattern":"manual","radius":60.0,"speed":.88,"gear":1,"wobble":.22},
	{"id":"vane_smooth_60","starter":"vane","pattern":"curve","radius":60.0,"speed":150.0,"gear":1,"wobble":0.0},
	{"id":"vane_wide_92","starter":"vane","pattern":"curve","radius":92.0,"speed":165.0,"gear":2,"wobble":0.0},
	{"id":"vane_imperfect_68","starter":"vane","pattern":"oval","radius":68.0,"speed":155.0,"gear":1,"wobble":.18},
	{"id":"breaker_square","starter":"breaker","pattern":"square","radius":70.0,"speed":165.0,"gear":2,"wobble":0.0},
	{"id":"custom_oval","starter":"custom","pattern":"oval","radius":90.0,"speed":160.0,"gear":1,"wobble":.13},
	{"id":"vane_idle","starter":"vane","pattern":"idle","radius":60.0,"speed":0.0,"gear":2,"wobble":0.0},
	{"id":"vane_straight","starter":"vane","pattern":"straight","radius":60.0,"speed":155.0,"gear":2,"wobble":0.0},
	{"id":"vane_tiny","starter":"vane","pattern":"curve","radius":15.0,"speed":90.0,"gear":2,"wobble":0.0}]
func _initialize() -> void: call_deferred("run")
static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value: result[str(key)]=portable(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(portable(item))
		return result
	return value
func control(b: Node2D, config: Dictionary, tick: int) -> Vector2:
	var p: Dictionary=b.player_entity(); var position: Vector2=p.pos; var velocity: Vector2=p.vel
	var desired: Vector2=Vector2.ZERO
	if config.pattern=="manual":
		var angle: float=b.elapsed*1.45+sin(b.elapsed*3.4)*float(config.wobble)
		return Vector2(cos(angle),sin(angle))*float(config.speed)
	if config.pattern=="idle": return Vector2.ZERO
	if config.pattern=="straight": desired=Vector2.RIGHT*float(config.speed)
	elif config.pattern=="square":
		var points: Array[Vector2]=[Vector2(70,-70),Vector2(70,70),Vector2(-70,70),Vector2(-70,-70)]
		desired=(points[floori(b.elapsed/1.15)%4]-position).limit_length(60)*2.5
	else:
		var radius: float=float(config.radius); var aspect: float=.72 if config.pattern=="oval" else 1.0
		var angle: float=atan2(position.y/aspect,position.x)
		var center_offset:=Vector2(8*sin(b.elapsed*.41),5*cos(b.elapsed*.36)) if float(config.wobble)>0 else Vector2.ZERO
		var radial:=Vector2(cos(angle),sin(angle)*aspect)
		var tangent:=Vector2(-sin(angle),cos(angle)*aspect).normalized()
		var target: Vector2=radial*(radius+sin(b.elapsed*2.3)*float(config.wobble)*radius*.3)+center_offset
		desired=tangent*float(config.speed)+(target-position)*2.8
		desired=desired.rotated(sin(tick*.023)*float(config.wobble))
	var drive: Vector2=(desired-velocity)*.010
	return Vector2(drive.x-drive.y,(drive.x+drive.y)*.5).limit_length(1.0)
func observe(config: Dictionary, seed: int) -> void:
	var b: Node2D=Battle.new(); root.add_child(b); b.set_physics_process(false); b.particles_enabled=false
	var build: Dictionary=Starters.build_for(str(config.starter)) if config.starter!="custom" else {"blade":"hook","ratchet":"kickback","bit":"chisel"}
	var d: Dictionary=Encounters.for_run_event(1,seed); d.starter_id=config.starter; d.player_power_ids=["afterimage","high_gear"]; d.player_power_ranks={"afterimage":3,"high_gear":int(config.gear)}; d.player_power_mutations={"afterimage":"ghost_circuit"}
	b.begin_run(build,d,seed)
	var runtime:=ObservedRuntime.new(); runtime.setup(b); b.powers=runtime
	b.continuous.progression_level=3+int(config.gear)
	var actual_drops: int=0; var direction:=Vector2.ZERO; var path_samples: Array=[]; var maximum_speed: float=0; var controls: int=0
	for tick: int in range(roundi(horizon*60)+300):
		if b.elapsed>=horizon or b.battle_status=="finished" or not str(b.player_entity().outcome).is_empty(): break
		if tick%12==0: direction=control(b,config,tick); controls+=1
		b.test_step(Battle.FIXED_DT,direction,false,false)
		var p: Dictionary=b.player_entity(); maximum_speed=maxf(maximum_speed,Vector2(p.vel).length())
		if tick%60==0: path_samples.append({"time":b.elapsed,"position":p.pos,"velocity":p.vel,"rpm":p.rpm,"trace_count":runtime.traces.size(),"closures":runtime.closures.size()})
	var p: Dictionary=b.player_entity()
	runs.append({"configuration":config,"seed":seed,"survival":b.elapsed,"outcome":p.outcome,"rpm":p.rpm,"max_speed":maximum_speed,"control_samples":controls,"calls":runtime.calls,"paid_attempts":runtime.emitted_attempts,"reasons":runtime.reasons,"candidates":runtime.candidates,"closures":runtime.closures,"closed_count":runtime.closures.size(),"trace_emissions":runtime.counters.get("afterimage",0),"route_samples":path_samples,"economy":b.continuous.economy.snapshot(),"director":b.continuous.snapshot(),"initial_loadout_fixture":true,"intervention_after_initialization":false})
	b.free()
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
		if arg.begins_with("--horizon="): horizon=float(arg.trim_prefix("--horizon="))
		if arg.begins_with("--case-set="): case_set=arg.trim_prefix("--case-set=")
	var valid: bool=report.is_absolute_path() and report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/") and not FileAccess.file_exists(report)
	if not valid: quit(2); return
	for config: Dictionary in configurations:
		if (case_set=="manual")!=str(config.id).contains("manual"): continue
		for seed: int in [421,7341,2026]:
			observe(config,seed); await process_frame
			print("GHOST_STUDY_CASE ",config.id," seed=",seed," closures=",runs[-1].closed_count)
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify(portable({"runs":runs,"case_set":case_set,"horizon":horizon,"seeds":[421,7341,2026],"scope":"Legal initial Ghost Circuit + High Gear investment fixture, not naturally earned. Actual production fixed solver/AI/Director and paid trace emission with5Hz sampled imperfect controls. Offline duplicated geometric observer reads before canonical closure; no injected live traces/positions/reserve/outcomes and no player save."}),"\t"))
	print("GHOST_ACCESSIBILITY_STUDY_PASS runs=",runs.size()); quit()
