extends SceneTree
## The SAME driver runs against immutable before/after sources. Explicit single
## threat/start/build fixtures; all subsequent movement/contact/powers/defeat are
## real production60Hz physics. No Main, collection, reserve refill or immunity.
const Battle = preload("res://scripts/battle.gd")
const Continuous = preload("res://scripts/continuous_run.gd")
const Roles = preload("res://scripts/enemy_roles.gd")
const Director = preload("res://scripts/threat_director.gd")
const Catalog = preload("res://scripts/parts.gd")
const PowerRuntime = preload("res://scripts/power_runtime.gd")
const TARGET_BUILD: Dictionary={"blade":"balance","ratchet":"mid","bit":"ball"}
const BUILDS: Dictionary={"attack":{"blade":"smash","ratchet":"high","bit":"flat"},"defence":{"blade":"guard","ratchet":"low","bit":"ball"},
	"mobile":{"blade":"hook","ratchet":"mid","bit":"rubber"},"stamina":{"blade":"balance","ratchet":"flywheel","bit":"freewheel"}}
const SEEDS: Array[int]=[421,933]
const START_TIMES: Array[float]=[0.0,480.0]
var output_path: String=""
var label: String=""
var seconds: float=45.0
var rows: Array[Dictionary]=[]
var supports_pilot: bool=false
var supports_packages: bool=false

class SingleThreat:
	extends Continuous
	func after_tick(_dt: float) -> void:pass # Fixture admits no extra rivals/swarms.
class MeasuredPowers:
	extends PowerRuntime
	var npc_events: Dictionary={}
	func _record(kind: String,owner: int,target: int=0,event_root: int=0,generation: int=0) -> void:
		super._record(kind,owner,target,event_root,generation)
		if owner==2:npc_events[kind]=int(npc_events.get(kind,0))+1
class MeasuredBattle:
	extends Battle
	var enemy_brake_ticks: int=0
	var enemy_brake_seconds: float=0.0
	var enemy_bursts: int=0
	var losses: Dictionary={}
	func spend_rpm(fighter: Dictionary,amount: float,source: String) -> void:
		var before: float=float(fighter.rpm)
		super.spend_rpm(fighter,amount,source)
		var id: int=int(fighter.entity_id)
		if not losses.has(id):losses[id]={}
		losses[id][source]=float(losses[id].get(source,0.0))+maxf(0.0,before-float(fighter.rpm))
	func _attempt_burst(fighter: Dictionary,direction: Vector2) -> void:
		var before: float=float(fighter.cooldown)
		super._attempt_burst(fighter,direction)
		if int(fighter.entity_id)==2 and before<=0.0 and float(fighter.cooldown)>0.0:enemy_bursts+=1
	func _update_fighter(fighter: Dictionary,direction: Vector2,braking: bool,dt: float) -> void:
		if int(fighter.entity_id)==2 and braking:enemy_brake_ticks+=1;enemy_brake_seconds+=dt
		super._update_fighter(fighter,direction,braking,dt)

func _initialize() -> void:call_deferred("run")
static func portable(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i:return [value.x,value.y]
	if value is float and not is_finite(value):return "-inf" if value<0 else "inf"
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:out[str(key)]=portable(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value:out.append(portable(item))
		return out
	return value
static func controls(b: Node2D,policy: String,age: float,tick: int) -> Dictionary:
	var p: Dictionary=b.player_entity()
	var goal: Vector2=Vector2(64,-14).rotated(age*0.48) if policy=="runner" else Vector2.ZERO
	var desired: Vector2=((goal-Vector2(p.pos))*2.1-Vector2(p.vel)*0.90).limit_length(100.0)/100.0
	if policy=="centre":desired=desired.limit_length(0.52)
	var screen: Vector2=Vector2(desired.x-desired.y,(desired.x+desired.y)*0.5).limit_length(1.0)
	var brake: bool=Vector2(p.pos).length()<18.0 and Vector2(p.vel).length()>38.0 if policy=="centre" else false
	# Fixed cadence player policy, shared unchanged before/after; does not read
	# enemy pilot intent, powers or future controls. Any difference is physics.
	var burst: bool=policy=="runner" and tick%270==0 and screen.length()>0.2 and float(p.rpm)>0.30
	return {"direction":screen,"burst":burst,"brake":brake}
func package(f: Dictionary,event: Dictionary) -> void:
	if supports_packages:
		var api: Variant=load("res://scripts/enemy_power_packages.gd")
		api.apply(f,event)
static func state_of(f: Dictionary) -> String:
	return str(f.get("pilot",{}).get("state",f.get("role_attack_state","approach")))
static func clearance(point: Vector2) -> float:
	return minf(minf(166.0-absf(point.x),166.0-absf(point.y)),minf((270.0-absf(point.x+point.y))/sqrt(2.0),(264.0-absf(point.x-point.y))/sqrt(2.0)))
func run_case(group: String,role: String,build: Dictionary,build_id: String,seed: int,start_time: float,policy: String) -> Dictionary:
	var b: Node2D=MeasuredBattle.new();root.add_child(b);b.set_physics_process(false);b.set_process(false)
	b.powers=MeasuredPowers.new()
	var descriptor: Dictionary={"opponent_build":build,"slot":1,"seed":seed,"difficulty":1,"starter_id":"custom","player_power_ids":[],"live_time_limit":100000.0}
	b.begin_encounter(TARGET_BUILD,descriptor)
	var single: RefCounted=SingleThreat.new();b.continuous=single;single.setup(b,seed)
	var event: Dictionary={"role":role,"kind":"rival","key":role,"name":role,"serial":1,"cost":2.6,"tier_at_entry":Director.tier_at(start_time)}
	Roles.configure(b.entity(2),event);package(b.entity(2),event)
	b.powers.setup(b);b.roster.setup(b);b.beasts.setup(b)
	b.battle_status="battle";b.elapsed=start_time;b.player_entity().pos=Vector2(-36,16);b.player_entity().vel=Vector2.ZERO
	b.entity(2).pos=Vector2(82,-12);b.entity(2).vel=Vector2.ZERO
	var f: Dictionary=b.entity(2)
	var initial: Dictionary={"player":b.player_entity().duplicate(true),"enemy":f.duplicate(true)}
	var r: Dictionary={"group":group,"role":role,"build_id":build_id,"build":build,"seed":seed,"start_time":start_time,"target_policy":policy,"requested_seconds":seconds,
		"initial":initial,"contacts":[],"attack_attempts":0,"meaningful_hits":0,"failed_commits":0,"burst_usage":0,"brake_ticks":0,"brake_seconds":0.0,
		"self_ring_outs":0,"player_ring_outs":0,"edge_exposure_seconds":0.0,"intended_position_occupancy_seconds":0.0,"common_useful_ground_seconds":0.0,
		"contact_severity_sum":0.0,"contact_severity_peak":0.0,"rpm_damage_caused":0.0,"survival_time":0.0,"recovery_seconds":0.0,
		"power_activation":{},"stuck_state_count":0,"states":{},"trace":[],"max_observed_speed":0.0,"distance_travelled":0.0}
	b.full_top_impact_accepted.connect(func(impact: Dictionary) -> void:
		if int(impact.first_entity_id)!=2 and int(impact.second_entity_id)!=2:return
		r.contacts.append(impact.duplicate(true));r.contact_severity_sum+=float(impact.severity)
		r.contact_severity_peak=maxf(float(r.contact_severity_peak),float(impact.severity))
		var damage: float=float(impact.first_rpm_loss) if int(impact.first_entity_id)==1 else float(impact.second_rpm_loss)
		r.rpm_damage_caused+=damage
		if damage>=0.004 and float(impact.severity)>=0.28:r.meaningful_hits+=1)
	var last_commit: int=-1
	var commit_hits: int=0
	var previous_state: String=state_of(f)
	var tick: int=0
	while tick<int(seconds*60) and b.battle_status=="battle" and str(f.outcome).is_empty() and str(b.player_entity().outcome).is_empty():
		var before: Vector2=f.pos
		var age: float=float(b.elapsed)-start_time
		var c: Dictionary=controls(b,policy,age,tick)
		b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		var advanced: float=float(b.elapsed)-start_time-float(r.survival_time)
		r.survival_time=float(b.elapsed)-start_time
		var state: String=state_of(f)
		r.states[state]=float(r.states.get(state,0.0))+advanced
		if state in ["recover","follow_through"]:r.recovery_seconds+=advanced
		var cycle: int=int(f.get("role_commit_cycle",-1))
		if str(f.get("role_attack_state",""))=="committed" and cycle!=last_commit:
			last_commit=cycle;r.attack_attempts+=1;commit_hits=int(r.meaningful_hits)
		if previous_state in ["commit","follow_through","committed"] and state in ["recover","set_up","position","setup"] and int(r.meaningful_hits)==commit_hits:r.failed_commits+=1
		previous_state=state
		var gap: float=clearance(f.pos)
		if gap<24.0:r.edge_exposure_seconds+=advanced
		if (role=="bulwark" and Vector2(f.pos).length()<50.0) or (role!="bulwark" and Vector2(f.pos).distance_to(b.player_entity().pos)>=42.0 and Vector2(f.pos).distance_to(b.player_entity().pos)<=112.0):r.common_useful_ground_seconds+=advanced
		if f.has("pilot") and Vector2(f.pos).distance_to(Vector2(f.pilot.goal))<=24.0:r.intended_position_occupancy_seconds+=advanced
		r.max_observed_speed=maxf(float(r.max_observed_speed),Vector2(f.vel).length());r.distance_travelled+=Vector2(f.pos).distance_to(before)
		if tick%60==0:r.trace.append({"time":b.elapsed,"state":state,"enemy_position":f.pos,"enemy_velocity":f.vel,"rpm":f.rpm,"wobble":f.wobble,"clearance":gap,
			"player_position":b.player_entity().pos,"player_rpm":b.player_entity().rpm,"pilot":f.get("pilot",{}).duplicate(true),"input":c,
			"anchor_stress":f.get("anchor_stress",0.0),"anchor_quota":f.get("anchor_recovery_remaining",0.0),"sink_charge":f.get("sink_charge",0.0),"momentum_charge":f.get("momentum_charge",0.0),"orbit_charge":f.get("orbit_charge",0.0)})
		tick+=1
	r.burst_usage=b.enemy_bursts;r.brake_ticks=b.enemy_brake_ticks;r.brake_seconds=b.enemy_brake_seconds
	r.self_ring_outs=1 if str(f.outcome)=="ring_out" else 0;r.player_ring_outs=1 if str(b.player_entity().outcome)=="ring_out" else 0
	r.enemy_outcome=str(f.outcome);r.player_outcome=str(b.player_entity().outcome);r.final_enemy_rpm=f.rpm;r.final_player_rpm=b.player_entity().rpm
	r.final_enemy_position=f.pos;r.final_enemy_velocity=f.vel;r.final_player_position=b.player_entity().pos;r.final_player_velocity=b.player_entity().vel
	var last_contact_age: Variant=null
	if not r.contacts.is_empty():last_contact_age=float(b.elapsed)-float(r.contacts[-1].time)
	r.ring_out_last_player_contact_age=last_contact_age
	r.remote_or_absent_contact_ring_out=int(r.self_ring_outs)==1 and (last_contact_age==null or float(last_contact_age)>4.0)
	r.recent_contact_ring_out=int(r.self_ring_outs)==1 and last_contact_age!=null and float(last_contact_age)<=1.5
	r.ring_out_attribution_note="Legacy self_ring_outs counts ANY NPC ring_out, including player outplays. Contact recency is context, not causal attribution: absent/>4sec, recent<=1.5sec, otherwise ambiguous. No automatic claim that a recent contact caused the exit."
	r.survival_censored=str(f.outcome).is_empty();r.intended_position_available=f.has("pilot")
	if not f.has("pilot"):r.intended_position_occupancy_seconds=null
	r.physics_ticks=tick;r.final_pilot=f.get("pilot",{}).duplicate(true);r.stuck_state_count=int(f.get("pilot",{}).get("stuck_count",0))
	if f.has("pilot"):r.attack_attempts=int(f.pilot.attack_attempts);r.failed_commits=int(f.pilot.failed_commits)
	r.power_activation=b.powers.npc_events.duplicate()
	for kind: String in b.roster.counters:r.power_activation[kind]=int(r.power_activation.get(kind,0))+int(b.roster.counters[kind])
	r.power_events_tail=b.powers.events.duplicate(true);r.actual_rpm_losses=b.losses.duplicate(true)
	r.power_rpm_damage_to_player=float(b.losses.get(1,{}).get("powers",0.0))
	r.position_occupancy_definition="Actual pilot goal within24units; baseline has no persistent goal, so that field is unavailable/zero. Common useful-ground metric is shared across versions (Bulwark within50centre; others42–112target gap)."
	r.contact_damage_definition="Actual accepted physical event loss to the unprotected player; power-source spending to plain unpowered target is recorded separately. No passive/movement spending is called inflicted damage."
	r.measured_loss_scope="Battle.spend_rpm observer records actual delegated losses; direct running_costs/legacy arithmetic are outside that hook. Final reserve/survival reflect all actual costs. Power event counter observes super._record unchanged before its bounded diagnostic tail can evict records."
	b.free()
	return r
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output_path=arg.trim_prefix("--report=")
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
		if arg.begins_with("--seconds="):seconds=float(arg.trim_prefix("--seconds="))
	if output_path.is_empty() or label.is_empty():push_error("Fresh external --report and --label required");quit(2);return
	var role_instance: RefCounted=Roles.new()
	supports_pilot=role_instance.get_script().get_script_method_list().any(func(method: Dictionary) -> bool:return method.name=="decision_interval")
	supports_packages=ResourceLoader.exists("res://scripts/enemy_power_packages.gd")
	for role: String in Roles.BUILDS:
		for seed: int in SEEDS:
			for time: float in START_TIMES:
				for policy: String in ["runner","centre"]:
					rows.append(run_case("roles",role,Roles.BUILDS[role],role,seed,time,policy))
	for build_id: String in BUILDS:
		for seed: int in SEEDS:
			for time: float in START_TIMES:rows.append(run_case("builds","hunter",BUILDS[build_id],build_id,seed,time,"runner"))
	var data: Dictionary={"task":"003A.1 enemy intelligence foundation","created_unix_time":Time.get_unix_time_from_system(),"label":label,"seconds_per_case":seconds,"rows":rows,"case_count":rows.size(),
		"supports_state_pilot":supports_pilot,"supports_enemy_packages":supports_packages,"target_build":TARGET_BUILD,"seeds":SEEDS,"start_times":START_TIMES,
		"scope":"Same common driver, starting poses/builds/reserve1.0/target inputs and natural fixed60Hz solver. Explicit one-rival admission fixture suppresses further Director admissions; no Main/save/XP/draft/human-input claim. No refill, protection, scripted contact/outcome/trace/charge/power activation. NPC uses each source version's actual AI, power eligibility and running costs; before/after therefore includes the declared production fairness/package changes, not a claim that every difference comes solely from pilot policy. After packages are authored ownership initialized before stepping; runtime earns all activation/storage.",
		"metrics":{"attacks":"Actual new commit serials","hits":"accepted contact severity>=.28 and player RPM loss>=.004","failed_commits":"No accepted meaningful contact before recovery; modern pilot counter available",
			"brake":"Actual fighter-update Brake ticks/seconds","survival":"Actual elapsed live time until either natural outcome or observation horizon","powers":"Actual PowerRuntime/roster recorded events, bounded tail; plain target has no powers",
			"state_occupancy":"Actual live fixed-clock seconds; hit-stop is excluded","edge":"real axis166/sum270/gate264 clearance<24"}}
	var file: FileAccess=FileAccess.open(output_path,FileAccess.WRITE);file.store_string(JSON.stringify(portable(data),"\t"));file.close()
	print("ENEMY_INTELLIGENCE_STUDY_PASS label=%s cases=%d pilot=%s packages=%s"%[label,rows.size(),supports_pilot,supports_packages]);quit(0)
