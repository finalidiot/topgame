extends SceneTree
const Roles = preload("res://scripts/enemy_roles.gd")
const Catalog = preload("res://scripts/parts.gd")
const Battle = preload("res://scripts/battle.gd")
const Continuous = preload("res://scripts/continuous_run.gd")
class SingleThreat:
	extends Continuous
	func after_tick(_dt: float) -> void:pass
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
static func fixture(role: String,build: Dictionary={},id: int=2) -> Dictionary:
	var assembly: Dictionary=Roles.BUILDS[role] if build.is_empty() else build
	var stats: Dictionary=Catalog.derive(assembly)
	var physical: Dictionary=Catalog.derive_physics(assembly)
	var f: Dictionary={"entity_id":id,"pos":Vector2(80,0),"vel":Vector2.ZERO,"stats":stats,"part_physics":physical,"build":assembly,
		"mass":(3.8+float(stats.mass)*0.56)*float(physical.mass),"radius":float(physical.radius),"rpm":1.0,"wobble":0.0,"cooldown":0.0,"burst_time":0.0,"powers":[]}
	Roles.configure(f,{"role":role,"kind":"rival","key":role,"name":role,"serial":1,"cost":2.6})
	return f
static func target() -> Dictionary:return {"entity_id":1,"pos":Vector2.ZERO,"vel":Vector2.ZERO,"rpm":1.0,"wobble":0.0,"burst_time":0.0,"mass":7.0}
func deterministic() -> void:
	for role: String in Roles.BUILDS:
		var a: Dictionary=fixture(role)
		var b: Dictionary=a.duplicate(true)
		var p: Dictionary=target()
		var before: Dictionary=a.duplicate(true)
		for tick: int in range(720):
			var time: float=float(tick)*0.25
			p.pos=Vector2(sin(time*0.4)*50,cos(time*0.4)*28)
			p.vel=Vector2(cos(time*0.4)*20,-sin(time*0.4)*11.2)
			p.wobble=0.6 if tick%71==0 else 0.0
			var da: Vector2=Roles.direction(a,p,time)
			var db: Vector2=Roles.direction(b,p,time)
			check(da==db and a.pilot==b.pilot,"Identical observed states produce deterministic decisions")
			check(da.is_finite() and da.length()<=0.951,"Steering is finite and bounded")
			check(a.pilot.state in Roles.STATES and a.pilot.size()<=36 and a.pilot.history.size()<=Roles.MAX_HISTORY,"State and history memory stay bounded")
			check(time-float(a.pilot.entered)<3.0,"No pilot state can become an infinite timer")
			var saved: Dictionary=a.pilot.duplicate(true)
			check(Roles.direction(a,p,time)==da and a.pilot==saved,"Repeated decision timestamp is idempotent")
		check(a.stats==before.stats and a.mass==before.mass and a.part_physics==before.part_physics and a.rpm==before.rpm and a.vel==before.vel and a.pos==before.pos,"AI writes only intent/memory, never solver values or reserve")
		check(a.pilot.attack_attempts>0 and a.pilot.recoveries>0,"Every role creates finite attacks and real recovery openings")
func commitment() -> void:
	for role: String in Roles.BUILDS:
		var f: Dictionary=fixture(role)
		var p: Dictionary=target()
		var now: float=0.0
		while now<10.0:
			Roles.direction(f,p,now)
			if f.pilot.state=="commit":break
			now+=0.1
		check(f.pilot.state=="commit","First rival uses readable explicit commitment")
		var heading: Vector2=f.pilot.heading
		p.pos=Vector2(0,90);p.vel=Vector2(250,-30)
		check(Roles.direction(f,p,now+0.05).normalized().is_equal_approx(heading),"A dodge cannot rotate the sampled commitment")
		f.pos=Vector2(-30,0);p.pos=Vector2.ZERO
		var follow: Vector2=Roles.direction(f,p,now+0.1)
		check(follow.normalized().dot(heading)>0.999 and f.pilot.state=="follow_through","Overshoot retains heading through real follow-through")
		check(not Roles.wants_burst(f,p,now+0.1),"No backward Burst onto a passed target")
		check(Roles.decision_interval(f,0.0)>Roles.decision_interval(f,600.0) and Roles.decision_interval(f,600.0)>=0.16,"Early reactions are slower than mature decisions, never frame perfect")
func tactics() -> void:
	var p: Dictionary=target()
	var hunter: Dictionary=fixture("hunter");hunter.pos=Vector2(25,0)
	check(Roles.direction(hunter,p,0.0).x>0.0,"Close Hunter creates physical run-up")
	var flanker: Dictionary=fixture("flanker")
	var flank: Vector2=Roles.direction(flanker,p,0.0)
	check(absf(flank.y)>absf(flank.x),"Flanker creates side angles rather than the same frontal lane")
	var guard: Dictionary=fixture("bulwark");guard.pos=Vector2(20,0)
	p.pos=Vector2(-50,0);p.vel=Vector2(150,0)
	Roles.direction(guard,p,0.0)
	check(guard.pilot.state=="defend" and Roles.wants_brake(guard,p,0.0),"Bulwark claims ground and braces an observed incoming strike")
	Roles.observe_contact(guard,p,0.1,0.7);p.vel=Vector2.ZERO
	Roles.direction(guard,p,0.4)
	check(guard.pilot.state=="setup" and guard.pilot.counter_used==1,"Real physical contact creates a measured counter opportunity")
	var harasser: Dictionary=fixture("harasser")
	p=target();Roles.direction(harasser,p,0.0)
	harasser.pilot.state="recover";harasser.pilot.entered=0.0;harasser.pilot.deadline=1.0
	check(Roles.direction(harasser,p,0.2).x>0.0,"Harasser withdraws after its poke instead of staying in a mass contest")
	for role: String in Roles.BUILDS:
		var f: Dictionary=fixture(role);f.rpm=0.11;f.wobble=0.8
		Roles.direction(f,p,0.0)
		check(f.pilot.state=="retreat" and not Roles.wants_burst(f,p,0.0),"Critical reserve/wobble selects survival and refuses wasteful Burst")
		f=fixture(role);f.pos=Vector2(160,0);f.vel=Vector2(180,0)
		var before: Vector2=f.pos
		var direction: Vector2=Roles.direction(f,p,0.0)
		check(direction.x<0.0 and Roles.wants_brake(f,p,0.0) and f.pos==before,"Edge defence is steering/braking intent, never an invisible position rail")
	var alone: Dictionary=fixture("hunter")
	var crowded: Dictionary=alone.duplicate(true)
	Roles.direction(alone,p,0.0)
	var context: Dictionary={"neighbors":[{"entity_id":3,"pos":Vector2(40,0),"radius":14.0,"state":"commit","commit_heading":Vector2.LEFT}]}
	Roles.direction(crowded,p,0.0,context)
	check(alone.pilot.lane_clear and not crowded.pilot.lane_clear,"Bounded present-neighbor snapshots reject a congested attack lane")
func builds_and_burst() -> void:
	var builds: Array[Dictionary]=[{"blade":"smash","ratchet":"high","bit":"flat"},{"blade":"guard","ratchet":"low","bit":"ball"},
		{"blade":"hook","ratchet":"mid","bit":"rubber"},{"blade":"balance","ratchet":"flywheel","bit":"freewheel"}]
	var profiles: Dictionary={}
	for build: Dictionary in builds:
		var f: Dictionary=fixture("hunter",build)
		profiles[str(Roles.build_tendencies(f))]=true
	check(profiles.size()==4,"Four actual assemblies yield distinct build tendencies under the same role")
	var f: Dictionary=fixture("hunter",builds[0])
	var altered: Dictionary=f.duplicate(true);altered.stats.speed=1.0;altered.mass*=1.7;altered.part_physics.control*=0.5
	check(Roles.build_tendencies(f)!=Roles.build_tendencies(altered),"Tendencies read actual stats/mass/physics, not the unchanged role/archetype labels")
	var p: Dictionary=target();p.wobble=0.5
	var now: float=0.0
	while now<10.0:
		Roles.direction(f,p,now)
		if f.pilot.state=="commit":break
		now+=0.1
	check(Roles.wants_burst(f,p,now),"Valid affordable sampled strike can Burst")
	f.cooldown=1.0;check(not Roles.wants_burst(f,p,now),"Physical cooldown cannot be bypassed")
	f.cooldown=0.0;f.rpm=0.13;check(not Roles.wants_burst(f,p,now),"Resource-aware reserve threshold avoids a near-empty activation")
	f.rpm=1.0;f.vel=Vector2.RIGHT*120;check(not Roles.wants_burst(f,p,now),"Bad real heading alignment cannot be disguised by steering intent")
	f.vel=Vector2.ZERO;f.pos=Vector2(-150,0);f.pilot.heading=Vector2.LEFT
	check(not Roles.wants_burst(f,p,now),"Predictable self-ring-out lane refuses Burst")

func actual_machine_controls() -> void:
	var attack: Dictionary={"blade":"smash","ratchet":"high","bit":"flat"}
	var defence: Dictionary={"blade":"guard","ratchet":"low","bit":"ball"}
	var stamina: Dictionary={"blade":"balance","ratchet":"flywheel","bit":"freewheel"}
	var p: Dictionary=target()
	for build: Dictionary in [defence,stamina]:
		var f: Dictionary=fixture("hunter",build);f.pos=Vector2(20,0)
		p.pos=Vector2(-50,0);p.vel=Vector2(150,0)
		Roles.direction(f,p,0.0)
		check(f.pilot.state=="defend" and Vector2(f.pilot.goal).length()<=32.0 and f.pilot.brake_intent,"Actual defence/stamina dominance claims ground and braces even under the common Hunter role")
		Roles.observe_contact(f,p,0.1,0.7);p.vel=Vector2.ZERO
		Roles.direction(f,p,0.4)
		check(f.pilot.state=="setup" and f.pilot.counter_used==1,"Actual stable machine counters a received hit without losing the assigned role")
	# Identical affordable, aligned decision fixtures simulate an observed real
	# Burst field, then wait beyond ordinary cooldown. No reserve is minted.
	var aggressive: Dictionary=fixture("hunter",attack)
	var conserving: Dictionary=fixture("hunter",stamina)
	p=target();p.wobble=0.6
	for f: Dictionary in [aggressive,conserving]:
		Roles.direction(f,p,0.0);f.burst_time=0.3;Roles.direction(f,p,0.4);f.burst_time=0.0
		f.pilot.state="commit";f.pilot.entered=5.0;f.pilot.deadline=5.7;f.pilot.heading=Vector2.LEFT;f.pilot.burst_intent=true
		f.pilot.lane_clear=true;f.pilot.brake_intent=false
	check(Roles.wants_burst(aggressive,p,5.0) and not Roles.wants_burst(conserving,p,5.0),"Stamina intentionally budgets an observed Burst beyond ordinary cooldown despite the same full reserve/opportunity")
	conserving.pilot.entered=11.0
	check(Roles.wants_burst(conserving,p,11.0),"A finite stamina budget still permits a valuable affordable attack")
	conserving.pilot.target_vulnerable=false;conserving.pilot.last_contact=-INF
	check(not Roles.wants_burst(conserving,target(),11.0),"Stable machine requires an actual exposed target or recent received-hit counter")
	var f: Dictionary=fixture("flanker");f.powers=["orbit_drive"];f.vel=Vector2(0,160)
	p=target();Roles.direction(f,p,600.0)
	f.pilot.state="setup";f.pilot.entered=600.0;f.pilot.deadline=600.34
	var direction: Vector2=Roles.direction(f,p,600.5)
	check(f.pilot.state=="setup" and direction.normalized().dot(f.vel.normalized())>0.999 and f.pilot.brake_intent,"Tangent setup physically brakes straight instead of committing sideways or entering Orbit drift")
	check(not Roles.wants_burst(f,p,600.5),"Unstraightened setup cannot Burst")
	f.vel=Vector2(-55,-5);Roles.direction(f,p,600.7)
	check(f.pilot.state=="commit","Actual straightening permits the finite locked strike")
	var heading: Vector2=f.pilot.heading;p.pos=Vector2(0,95)
	check(Roles.direction(f,p,600.8).normalized().is_equal_approx(heading),"The alignment setup does not introduce tracking during commitment")
	f=fixture("flanker");f.powers=["orbit_drive"];f.vel=Vector2(0,160);p=target()
	Roles.direction(f,p,600.0);f.pilot.state="setup";f.pilot.entered=600.0;f.pilot.deadline=600.34
	Roles.direction(f,p,601.3)
	check(f.pilot.state=="recover","A lane that never physically straightens has a finite recovery exit")
	for role: String in Roles.BUILDS:
		f=fixture(role);f.pos=Vector2(85,-85);f.vel=Vector2(180,-180)
		var before: Vector2=f.pos
		Roles.direction(f,target(),0.0)
		check(float(f.pilot.clearance)>22.0 and f.pilot.state=="defend" and f.pilot.brake_intent and f.pos==before,"Forecast includes early decision latency and initiates real Brake before the retired22unit threshold")
		f.pilot.state="commit";f.pilot.entered=0.0;f.pilot.deadline=0.7;f.pilot.heading=Vector2(1,-1).normalized()
		direction=Roles.direction(f,target(),0.1)
		check(direction.normalized().is_equal_approx(f.pilot.heading) and f.pilot.brake_intent and not Roles.wants_burst(f,target(),0.1),"A dangerous ongoing strike retains its locked direction while ordinary Brake sheds carried momentum")
func power_tactics() -> void:
	var p: Dictionary=target()
	var f: Dictionary=fixture("bulwark");f.pos=Vector2(20,0);f.powers=["dead_centre"];f.anchor_stress=0.60;f.anchor_recovery_remaining=0.20
	var move: Vector2=Roles.direction(f,p,0.0)
	check(f.pilot.power_control.anchor_reposition and move.length()>=0.35 and not Roles.wants_brake(f,p,0.0),"Loaded Anchor deliberately releases and rotates toward the real rearm circle")
	check(f.anchor_stress==0.60 and f.anchor_recovery_remaining==0.20,"Pilot cannot cool Stress or mint quota")
	f.pos=Vector2(103,0);f.vel=Vector2(0,-50);f.anchor_stress=0.25;f.anchor_recovery_remaining=0.0
	Roles.direction(f,p,0.4)
	check(f.pilot.power_control.anchor_reposition and not f.pilot.brake_intent,"Depleted quota maintains real released rotation even after cooling")
	f.anchor_recovery_remaining=0.20;Roles.direction(f,p,0.8)
	check(not f.pilot.power_control.anchor_reposition and f.pilot.state=="position","Actual runtime rearm permits return to useful ground")
	f=fixture("bulwark");f.pos=Vector2(20,0);f.powers=["impact_sink"];f.sink_charge=24.0
	Roles.direction(f,p,0.0);check(f.pilot.brake_intent,"Real stored Impact Sink charge requests a fresh low-speed Brake")
	Roles.direction(f,p,0.4);check(not f.pilot.brake_intent and f.sink_charge==24.0,"Brake release is deliberate and AI never drains/injects the reservoir itself")
	f=fixture("hunter");f.powers=["momentum_bank","orbit_drive"];Roles.direction(f,p,0.0)
	f.pilot.state="setup";f.pilot.entered=0.0;f.pilot.deadline=1.0;f.vel=Vector2(-100,-20);f.momentum_charge=0.0
	move=Roles.direction(f,p,0.4)
	check(f.pilot.brake_intent and move.length()>0.08 and move.normalized().dot(f.vel.normalized())>0.999,"Momentum Bank uses straight steered Brake rather than incompatible Orbit drift")
	check(f.momentum_charge==0.0,"Only the actual solver/runtime can store lost momentum")
	f=fixture("flanker");f.powers=["orbit_drive"];f.vel=Vector2(-80,-80)
	Roles.direction(f,p,600.0);check(f.pilot.brake_intent,"Useful high-speed curve can enter real Orbit Drive drift")
	Roles.direction(f,p,600.25);check(not f.pilot.brake_intent,"Orbit drift uses intermittent Brake rather than an endless held brake")
	f=fixture("flanker");f.powers=["afterimage"];f.power_mutations={"afterimage":"ghost_circuit"}
	Roles.direction(f,p,0.0);Roles.direction(f,p,1.0)
	check(f.pilot.state=="position" and float(f.pilot.deadline)<=3.6,"Ghost Circuit is the actual Afterimage mutation with a finite reachable closure route")

func physical_outplays() -> void:
	# Explicit gate approach/velocity and ownership fixtures; after stepping,
	# contact impulse, Brake, Burst, powers and ring-out are ordinary production
	# mechanics. No forced outcome, immunity or solver override is used.
	var builds: Array[Dictionary]=[{"blade":"smash","ratchet":"high","bit":"flat"},{"blade":"guard","ratchet":"low","bit":"ball"},
		{"blade":"hook","ratchet":"mid","bit":"rubber"},{"blade":"balance","ratchet":"flywheel","bit":"freewheel"}]
	for index: int in range(builds.size()):
		var b: Node2D=Battle.new();root.add_child(b);b.set_physics_process(false);b.set_process(false)
		b.begin_encounter(builds[0],{"opponent_build":builds[index],"slot":1,"seed":421,"difficulty":1,"starter_id":"custom","player_power_ids":[],"live_time_limit":10000.0})
		var flow: RefCounted=SingleThreat.new();b.continuous=flow;flow.setup(b,421)
		var role: String="bulwark" if index in [1,3] else ("flanker" if index==2 else "hunter")
		var event: Dictionary={"role":role,"kind":"rival","key":role,"name":role,"serial":1,"cost":2.6,"tier_at_entry":5}
		Roles.configure(b.entity(2),event)
		load("res://scripts/enemy_power_packages.gd").apply(b.entity(2),event)
		b.powers.setup(b);b.roster.setup(b);b.beasts.setup(b);b.battle_status="battle";b.elapsed=480.0
		b.player_entity().pos=Vector2(92,-92);b.player_entity().vel=Vector2(190,-190)
		b.entity(2).pos=Vector2(116,-116);b.entity(2).vel=Vector2.ZERO
		var actual: Dictionary={"hits":0,"severity":0.0}
		b.full_top_impact_accepted.connect(func(impact: Dictionary) -> void:
			actual.hits+=1;actual.severity=maxf(float(actual.severity),float(impact.severity)))
		for tick: int in range(180):
			b.test_step(Battle.FIXED_DT,Vector2.RIGHT,tick==0,false)
			if not str(b.entity(2).outcome).is_empty():break
		check(int(actual.hits)>0 and float(actual.severity)>0.6,"Declared gate approach creates a genuine hard player contact against actual assembly%d"%index)
		check(b.entity(2).outcome=="ring_out","Predictive intent and coherent powers leave actual assembly%d physically ring-out-able by a player hit"%index)
		b.free()
func run() -> void:
	deterministic();commitment();tactics();builds_and_burst();actual_machine_controls();power_tactics();physical_outplays()
	var code: String=FileAccess.get_file_as_string("res://scripts/enemy_roles.gd")
	check(not "Input." in code and not "InputMap." in code and not "randf" in code and not "randi" in code,"Decision module reads no input/future intent and consumes no simulation RNG")
	print("ENEMY_INTELLIGENCE_003A1_%s checks=%d failures=%d"%["PASS" if failures==0 else "FAIL",checks,failures]);quit(1 if failures else 0)
