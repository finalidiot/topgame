extends SceneTree
## Independent contract boundaries plus actual canonical fixed-step replay.
const Fixture=preload("res://tests/mutation_physics_fixture_003a2.gd")
const Draft=preload("res://tests/mutation_draft_policy_003a2.gd")
var checks: int=0
var failures: Array[String]=[]
var rows: Array[Dictionary]=[]
var output: String=""

func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func near(a: float,b: float) -> bool:return absf(a-b)<0.000001
func vector_scalar_near(a: float,b: float) -> bool:return absf(a-b)<0.0001
func count(b: Node2D, event: String) -> int:return int(b.roster.ecology.counters.get(event,0))
func event_owner(b: Node2D, event: String, owner: int, target: int=0) -> void:
	var found: bool=false
	for e: Dictionary in b.powers.events:
		if e.kind==event:
			var f: Dictionary=b.entity(owner)
			var cause: Dictionary=b.powers._owned_effect_cause(f,event)
			found=true;check(int(e.owner)==owner and int(e.target)==target and int(e.root)!=0 and int(e.root)==int(cause.root_event_id),event+" has actual owner/receiver/stable root provenance")
			check(int(cause.owner_entity_id)==owner and cause.owner_id==f.owner_id and cause.team_id==f.team_id,event+" carries the exact canonical owner and team cause")
			if target!=0:
				var physical_shove: bool=event in ["wallbreaker_hit","ricochet_hit","centrifuge_hit","reactive_counter"]
				check(b._progression_contacted.has(target)==(owner==1 and physical_shove),event+" attribution follows actual owned receiver impulses; defence/recoil-only cues and NPC effects cannot invent player credit")
	check(found,event+" enters the bounded ordinary power event history")
	check(b.powers._requests.is_empty() and b.powers._next_tick_pulses.is_empty(),event+" cannot queue recursive contact attacks")
func save(b: Node2D, branch: String, owner: int) -> void:
	rows.append({"branch":branch,"owner":owner,"counters":b.roster.ecology.counters.duplicate(true),"diagnostic":b.roster.ecology.diagnostics(b.entity(owner)),"events":b.powers.events.duplicate(true),"economy":b.continuous.economy.snapshot(),"owner_rpm":b.entity(owner).rpm,"owner_velocity":b.entity(owner).vel,"owner_wobble":b.entity(owner).wobble})
func make(branch: String, owner: int=1) -> Node2D:
	for family: String in Draft.NEW_PAIRS:
		if branch in Draft.NEW_PAIRS[family]:return Fixture.create(root,family,branch,owner)
	return null
func target(b: Node2D, owner: int) -> Dictionary:return b.entity(3-owner)

func wallbreaker(owner: int) -> void:
	var b: Node2D=make("wallbreaker",owner);var p: Dictionary=b.entity(owner);var t: Dictionary=target(b,owner);var e: RefCounted=b.roster.ecology
	var initial: float=p.rpm
	e.wall_velocity(p,Vector2(200,0),Vector2(-140,0),159.999,Vector2.RIGHT,p.pos)
	check(count(b,"wallbreaker_arm")==0,"Wallbreaker rejects a rebound below160")
	p.vel=e.wall_velocity(p,Vector2(200,0),Vector2(-140,0),160.0,Vector2.RIGHT,p.pos)
	check(count(b,"wallbreaker_arm")==1 and near(initial-float(p.rpm),.018),"Wallbreaker charges once and pays its exact accounted arm cost")
	check(Vector2(p.vel).x<0 and p.ecology_commit_time>1.19,"Wallbreaker carries the actual reflected heading")
	var controls: Dictionary=e.controls(p,Vector2.RIGHT,true)
	var m: Dictionary=b.roster.movement(p,b.powers.movement_control(p,controls.direction,controls.braking,1.0/60.0),1.0/60.0)
	check(Vector2(m.direction).dot(Vector2.LEFT)>.95 and not m.braking,"Wallbreaker commitment cannot be perfectly retargeted or braked")
	e.wall_velocity(p,Vector2(200,0),Vector2(-140,0),200.0,Vector2.RIGHT,p.pos)
	check(count(b,"wallbreaker_arm")==1,"Wallbreaker arm cooldown rejects repeated wall spam")
	e.contact(p,t,.449,Vector2.LEFT,Vector2(-180,0));check(count(b,"wallbreaker_hit")==0,"Wallbreaker rejects a contact below its severity")
	var recoil_before: Vector2=p.vel
	e.contact(p,t,.45,Vector2.LEFT,Vector2(-180,0))
	check(count(b,"wallbreaker_hit")==1 and near(float(t.vel.x),-100.0),"Wallbreaker adds one100-unit normal shove to the actual receiver")
	check(near(Vector2(p.vel).x-recoil_before.x,45.0) and p.wobble>=.07 and p.ecology_commit_time==0.0,"Wallbreaker pays recoil/wobble and consumes its commitment")
	e.contact(p,t,.9,Vector2.LEFT,Vector2(-180,0));check(count(b,"wallbreaker_hit")==1,"Wallbreaker cannot spend its hit charge twice")
	event_owner(b,"wallbreaker_hit",owner,3-owner);save(b,"wallbreaker",owner);b.free()
	b=make("wallbreaker",owner);p=b.entity(owner);e=b.roster.ecology
	p.vel=e.wall_velocity(p,Vector2(200,0),Vector2(-140,0),200.,Vector2.RIGHT,p.pos);initial=p.rpm
	e.begin_tick(1.201);check(count(b,"wallbreaker_miss")==1 and near(initial-float(p.rpm),.025) and p.wobble>=.1,"Missing Wallbreaker expires once with the actual downside")
	e.begin_tick(.1);check(count(b,"wallbreaker_miss")==1,"Wallbreaker expiry cannot repeat its miss tax");b.free()

func ricochet(owner: int) -> void:
	var b: Node2D=make("ricochet_engine",owner);var p: Dictionary=b.entity(owner);var t: Dictionary=target(b,owner);var e: RefCounted=b.roster.ecology;var r: Dictionary=b.roster.state(p)
	r.input=Vector2(-.5,.6);r.braking=false
	var initial: float=p.rpm;var before:=Vector2(180,140);var after:=Vector2(-120,110)
	e.wall_velocity(p,Vector2(200,0),Vector2(-120,0),200.,Vector2.RIGHT,p.pos);check(count(b,"ricochet_rebound")==0,"Ricochet rejects a head-on incidence")
	p.vel=e.wall_velocity(p,before,after,180.,Vector2.RIGHT,p.pos)
	check(count(b,"ricochet_rebound")==1 and near(initial-float(p.rpm),.006),"Controlled oblique Ricochet pays its exact rebound cost")
	check(Vector2(p.vel).length()<=before.length()*.94+.000001 and Vector2(p.vel).length()<=after.length()*1.24+.000001,"Ricochet preserves the real pre-wall and reflection energy ceilings")
	e.wall_velocity(p,before,after,180.,Vector2.RIGHT,p.pos);check(count(b,"ricochet_rebound")==1,"Ricochet has a real0.30s arm cooldown")
	for beat: int in range(4):e.time+=.301;e.wall_velocity(p,before,after,180.,Vector2.RIGHT,p.pos)
	check(int(e.state(p).ricochets)==3,"Ricochet route stock has a three-beat cap")
	var heading: Vector2=e.state(p).comet_heading
	e.contact(p,t,.3,heading,heading*100.0)
	check(count(b,"ricochet_hit")==1 and near(Vector2(t.vel).length(),30.0) and int(e.state(p).ricochets)==2,"Ricochet's smaller physical strike consumes one earned beat")
	event_owner(b,"ricochet_hit",owner,3-owner)
	e.movement(p,{"direction":-Vector2(p.vel).normalized(),"braking":true,"speed":1.0,"acceleration":1.0,"drain":1.0,"drag":1.0},.01)
	check(count(b,"ricochet_break")==1 and int(e.state(p).ricochets)==0,"Brake or hard correction breaks the finite route")
	e.movement(p,{"direction":Vector2.RIGHT,"braking":true,"speed":1.0,"acceleration":1.0,"drain":1.0,"drag":1.0},.01);check(count(b,"ricochet_break")==1,"An already-broken Ricochet route cannot retrigger")
	save(b,"ricochet_engine",owner);b.free()

func centrifuge(owner: int) -> void:
	var b: Node2D=make("centrifuge",owner);var p: Dictionary=b.entity(owner);var t: Dictionary=target(b,owner);var e: RefCounted=b.roster.ecology;var r: Dictionary=b.roster.state(p)
	r.input=Vector2.DOWN;r.orbit=.99999;p.orbit_charge=r.orbit;p.orbit_flow=true;p.vel=Vector2(0,200)
	e.contact(p,t,.6,Vector2.RIGHT,p.vel);check(count(b,"centrifuge_hit")==0,"Centrifuge rejects just-below-full DRIVE")
	r.orbit=1.0;p.orbit_charge=1.0;p.orbit_flow=false;e.contact(p,t,.6,Vector2.RIGHT,p.vel);check(count(b,"centrifuge_hit")==0,"Centrifuge rejects stale full charge without a fresh same-sign curve")
	p.orbit_flow=true;e.contact(p,t,.449,Vector2.RIGHT,p.vel);check(count(b,"centrifuge_hit")==0,"Centrifuge rejects soft tangential contacts")
	var initial: float=p.rpm;e.contact(p,t,.45,Vector2.RIGHT,p.vel)
	check(count(b,"centrifuge_hit")==1 and near(float(t.vel.y),90.0),"Full curved contact produces a real bounded lateral shove")
	check(near(initial-float(p.rpm),.012) and near(float(r.orbit),.30) and near(float(p.vel.y),173.0) and p.wobble>=.04,"Centrifuge spends DRIVE/RPM and pays physical recoil")
	r.orbit=1.0;p.orbit_charge=1.0;e.contact(p,t,.8,Vector2.RIGHT,Vector2(0,200));check(count(b,"centrifuge_hit")==1,"Centrifuge's cooldown cannot be bypassed by a declared full-charge gate fixture")
	event_owner(b,"centrifuge_hit",owner,3-owner);save(b,"centrifuge",owner);b.free()

func perpetual(owner: int) -> void:
	var b: Node2D=make("perpetual_orbit",owner);var p: Dictionary=b.entity(owner);var e: RefCounted=b.roster.ecology;var r: Dictionary=b.roster.state(p)
	r.input=Vector2.RIGHT;r.heading=Vector2.RIGHT;r.orbit=1.0;r.turn_sign=1.0;p.orbit_charge=1.0;p.vel=Vector2(130,0)
	e.state(p).orbit_heading=Vector2.RIGHT;e.state(p).orbit_sign=1.0
	var curved: Vector2=p.vel.rotated(.02)
	p.vel=b.roster.velocity(p,p.vel,curved,1.0/60.0)
	check(p.orbit_flow and float(p.orbit_charge)==1.0,"Perpetual real same-sign curve maintains full DRIVE")
	p.rpm=.5;p.energy=.5;b.powers.begin_tick(1.0/60.0);b.powers._state(p).motion_input=.7
	var initial: float=p.rpm;b.powers.after_movement()
	check(near(float(p.rpm)-initial,.017/60.0),"Perpetual recovery uses the same paid capped Orbit bucket and exact rank rate")
	var original: float=float(r.orbit);initial=p.rpm;r.input=-Vector2(p.vel).normalized()
	var before: Vector2=p.vel;p.vel=b.roster.velocity(p,before,before,1.0/60.0)
	check(count(b,"perpetual_break")==1 and near(initial-float(p.rpm),.012*original),"Hard correction prices PRE-update DRIVE exactly once")
	check(float(r.orbit)==0.0 and float(p.orbit_charge)==0.0 and vector_scalar_near(Vector2(p.vel).length(),before.length()*.90),"Perpetual correction dumps charge and loses real carried velocity")
	initial=p.rpm;b.roster.velocity(p,p.vel,p.vel,1.0/60.0);check(near(float(p.rpm),initial) and count(b,"perpetual_break")==1,"Broken flow cannot repeatedly charge a correction fee")
	check(count(b,"centrifuge_hit")==0,"Perpetual sibling has no direct attack proc")
	event_owner(b,"perpetual_break",owner);save(b,"perpetual_orbit",owner);b.free()

func flywheel(owner: int) -> void:
	var b: Node2D=make("flywheel_release",owner);var p: Dictionary=b.entity(owner);var t: Dictionary=target(b,owner);var e: RefCounted=b.roster.ecology;var r: Dictionary=b.roster.state(p)
	check(e.bank_capacity(p)==240.0 and e.bank_leak(p)==9.0,"Flywheel has a larger finite reservoir with faster leakage")
	r.bank=59.999;e.burst(p,Vector2.RIGHT,Vector2(150,0));check(count(b,"flywheel_release")==0 and near(float(r.bank),59.999),"Flywheel rejects less than60 stored motion")
	r.bank=100.0;p.vel=Vector2(150,0);var initial: float=p.rpm;e.burst(p,Vector2.RIGHT,p.vel)
	check(count(b,"flywheel_release")==1 and near(float(r.bank),0.0) and near(float(p.vel.x),265.0),"Flywheel consumes actual storage into a physical forward launch")
	check(near(initial-float(p.rpm),.024) and p.ecology_commit_time>.64,"Flywheel pays the extra power fee and commits the line")
	var controls: Dictionary=e.controls(p,Vector2.LEFT,true)
	var m: Dictionary=b.roster.movement(p,b.powers.movement_control(p,controls.direction,controls.braking,.01),.01)
	check(Vector2(m.direction).x>.95 and not m.braking,"Flywheel cannot cancel its committed release with Brake or perfect steering")
	r.bank=100.0;e.burst(p,Vector2.RIGHT,Vector2(150,0));check(count(b,"flywheel_release")==1,"Flywheel release respects its1.2s cooldown")
	e.contact(p,t,.599,Vector2.RIGHT,Vector2(200,0));check(count(b,"flywheel_hit")==0,"Flywheel rejects a soft follow-through")
	e.contact(p,t,.6,Vector2.RIGHT,Vector2(200,0));check(count(b,"flywheel_hit")==1 and near(float(p.vel.x),247.0) and p.wobble>=.05,"Hard Flywheel follow-through pays owner recoil without magic target damage")
	check(Vector2(t.vel)==Vector2.ZERO,"Flywheel does not invent an extra target shove")
	event_owner(b,"flywheel_hit",owner,3-owner);save(b,"flywheel_release",owner);b.free()
	b=make("flywheel_release",owner);p=b.entity(owner);e=b.roster.ecology;b.roster.state(p).bank=100.;e.burst(p,Vector2.RIGHT,Vector2(100,0));initial=p.rpm
	e.begin_tick(.651);check(count(b,"flywheel_miss")==1 and near(initial-float(p.rpm),.016) and p.wobble>=.10,"Flywheel miss expires once with its real cost/wobble downside");b.free()

func countersteer(owner: int) -> void:
	var b: Node2D=make("countersteer",owner);var p: Dictionary=b.entity(owner);var e: RefCounted=b.roster.ecology;var r: Dictionary=b.roster.state(p)
	r.bank=100.;p.vel=Vector2(220,0);e.burst(p,Vector2.RIGHT,Vector2(180,0))
	check(count(b,"countersteer")==0 and float(r.bank)==100.,"Countersteer straight Burst retains its store")
	r.bank=34.999;e.burst(p,Vector2.DOWN,Vector2(180,0));check(count(b,"countersteer")==0,"Countersteer rejects less than35 stored motion")
	r.bank=100.;var initial: float=p.rpm;e.burst(p,Vector2.DOWN,Vector2(180,0))
	check(count(b,"countersteer")==1 and near(float(p.vel.x),0.) and near(float(p.vel.y),202.),"Countersteer redirects PRE-Burst carried motion with its lower speed payoff")
	check(near(initial-float(p.rpm),.016) and float(r.bank)==0. and p.ecology_commit_time==0.,"Countersteer pays for storage without a prolonged steering lock or RPM gain")
	r.bank=100.;e.burst(p,Vector2.LEFT,Vector2(180,0));check(count(b,"countersteer")==1,"Countersteer obeys its0.8s cooldown")
	event_owner(b,"countersteer",owner);save(b,"countersteer",owner);b.free()

func reactive(owner: int) -> void:
	var b: Node2D=make("reactive_plating",owner);var p: Dictionary=b.entity(owner);var t: Dictionary=target(b,owner);var e: RefCounted=b.roster.ecology
	e.prepare_contact(p,t,.599,Vector2.RIGHT,Vector2.ZERO,Vector2(-120,0),100.);check(count(b,"reactive_charge")==0,"Reactive Plating rejects a soft incoming hit")
	e.prepare_contact(p,t,.6,Vector2.RIGHT,Vector2.ZERO,Vector2(-120,0),54.999);check(count(b,"reactive_charge")==0,"Reactive Plating requires actual solver delta55")
	e.prepare_contact(p,t,.6,Vector2.RIGHT,Vector2.ZERO,Vector2(-120,0),100.)
	check(count(b,"reactive_charge")==1 and near(float(p.reactive_force),32.) and e.collision_cost(p)==.65,"Reactive Plating stores actual incoming force and uses a weaker brief damper thanII")
	b.roster.state(p).input=Vector2.RIGHT;p.vel=Vector2(100,0);var initial: float=p.rpm
	e.contact(p,t,.8,Vector2.RIGHT,p.vel);check(count(b,"reactive_counter")==0 and near(float(p.reactive_force),32.),"The charging collision cannot spend its own counter")
	e.prepare_contact(p,t,.4,Vector2.RIGHT,p.vel,Vector2.ZERO,20.)
	e.contact(p,t,.25,Vector2.RIGHT,p.vel)
	check(count(b,"reactive_counter")==1 and near(float(t.vel.x),32.) and near(initial-float(p.rpm),.010),"Next distinct aimed contact consumes stored recoil for a priced physical counter")
	check(float(p.reactive_force)==0. and vector_scalar_near(float(p.vel.x),94.24),"Reactive counter pays owner recoil and clears stock")
	e.prepare_contact(p,t,.9,Vector2.RIGHT,p.vel,Vector2(-180,0),120.);check(count(b,"reactive_charge")==1,"Reactive charge cooldown rejects repeated incoming hits")
	event_owner(b,"reactive_counter",owner,3-owner);save(b,"reactive_plating",owner);b.free()
	b=make("reactive_plating",owner);p=b.entity(owner);t=target(b,owner);e=b.roster.ecology;e.prepare_contact(p,t,.8,Vector2.RIGHT,Vector2.ZERO,Vector2(-120,0),100.);e.begin_tick(.751)
	check(float(p.reactive_force)==0. and e.collision_cost(p)==1. and count(b,"reactive_counter")==0,"Unused Reactive stock expires with no idle pulse, recovery or permanent guard");b.free()

func damper(owner: int) -> void:
	var b: Node2D=make("sacrificial_damper",owner);var p: Dictionary=b.entity(owner);var t: Dictionary=target(b,owner);var e: RefCounted=b.roster.ecology
	var ordinary: Dictionary=e.prepare_contact(p,t,.849,Vector2.RIGHT,Vector2.ZERO,Vector2(-200,0),100.)
	check(ordinary.recoil==1. and count(b,"damper_absorb")==0,"Sacrificial Damper rejects severity below0.85")
	ordinary=e.prepare_contact(p,t,.85,Vector2.RIGHT,Vector2.ZERO,Vector2(-200,0),79.999)
	check(ordinary.recoil==1. and count(b,"damper_absorb")==0,"Sacrificial Damper requires actual solver delta80")
	var result: Dictionary=e.prepare_contact(p,t,.85,Vector2.RIGHT,Vector2.ZERO,Vector2(-200,0),80.)
	check(result.recoil==.40 and result.shock==.28 and result.cost==.009 and count(b,"damper_absorb")==1,"Only the accepted huge collision gets the priced recoil/shock retention")
	check(p.wobble>=.04 and p.damper_time>1.39,"Sacrifice enters a visible finite buckled state")
	var m: Dictionary=e.movement(p,{"direction":Vector2.RIGHT,"braking":false,"speed":1.0,"acceleration":1.0,"drain":1.0,"drag":1.0},.01)
	check(m.acceleration==.45 and m.speed==.65 and m.drag==2.2,"Sacrificial protection slows and weakens real movement")
	ordinary=e.prepare_contact(p,t,1.0,Vector2.RIGHT,Vector2.ZERO,Vector2(-200,0),120.)
	check(ordinary.recoil==1. and ordinary.shock==1. and count(b,"damper_absorb")==1,"A later hit has no permanent retention and cannot bypass seven-second cooldown")
	var initial: float=p.rpm;e.begin_tick(.5);check(near(initial-float(p.rpm),.005),"Buckled Sacrifice pays its ongoing0.010RPM/s downside")
	event_owner(b,"damper_absorb",owner,3-owner);save(b,"sacrificial_damper",owner);b.free()

func guarded_states(branch: String) -> void:
	var b: Node2D=make(branch);var p: Dictionary=b.entity(1);var t: Dictionary=b.entity(2);var e: RefCounted=b.roster.ecology
	var initial: Dictionary=b.fixture_snapshot();b.set_paused(true)
	for tick: int in range(10):b.fixture_step(Vector2.RIGHT,true,true)
	check(initial==b.fixture_snapshot(),branch+" pause freezes physics, all four clocks, mechanisms and economy")
	b.set_paused(false);t.team_id=p.team_id
	e.prepare_contact(p,t,1.3,Vector2.RIGHT,Vector2(200,0),Vector2(-200,0),200.);e.contact(p,t,1.3,Vector2.RIGHT,Vector2(200,200))
	check(e.counters.is_empty(),branch+" allied contact cannot trigger or consume an attack")
	t.team_id="neutral";e.prepare_contact(p,t,1.3,Vector2.RIGHT,Vector2(200,0),Vector2(-200,0),200.);e.contact(p,t,1.3,Vector2.RIGHT,Vector2(200,200))
	check(e.counters.is_empty(),branch+" neutral targets cannot trigger or receive combat procs")
	t.team_id="hostile";t.combatant_type="small_top";e.prepare_contact(p,t,1.3,Vector2.RIGHT,Vector2(200,0),Vector2(-200,0),200.);e.contact(p,t,1.3,Vector2.RIGHT,Vector2(200,200))
	check(e.counters.is_empty(),branch+" small tops cannot satisfy full-top mutation contacts")
	t.combatant_type="full_top";b.battle_status="finished";initial=b.fixture_snapshot()
	for tick: int in range(10):b.fixture_step(Vector2.RIGHT,true,true)
	e.wall_velocity(p,Vector2(200,140),Vector2(-130,140),200.,Vector2.RIGHT,p.pos);e.burst(p,Vector2.RIGHT,Vector2(200,0));e.prepare_contact(p,t,1.3,Vector2.RIGHT,Vector2.ZERO,Vector2(-200,0),200.);e.contact(p,t,1.3,Vector2.RIGHT,Vector2(200,200))
	check(initial==b.fixture_snapshot(),branch+" terminal controls/hooks cannot restart combat or payoffs")
	b.free()

func replay(branch: String) -> void:
	var histories: Array=[]
	for repeat: int in range(2):
		var b: Node2D=make(branch);var p: Dictionary=b.entity(1)
		# One declared initial physical pose/velocity. No subsequent actor/charge/RPM writes.
		p.pos=Vector2(158,0) if branch in ["wallbreaker","ricochet_engine"] else Vector2(-65,-35)
		p.vel=Vector2(225,140) if branch=="ricochet_engine" else (Vector2(230,0) if branch=="wallbreaker" else Vector2(150,80))
		var rows_actual: Array=[]
		for tick: int in range(240):
			var direction: Vector2=Vector2.from_angle(float(tick)*.018)*.65
			b.fixture_step(direction,tick==90,tick>=35 and tick<55)
			if tick%12==0:rows_actual.append(b.fixture_snapshot())
			if b.battle_status=="finished":break
		histories.append(rows_actual);b.free()
	check(histories[0]==histories[1],branch+" exact seed and controls replay actual physics/costs/events/mechanisms")
	rows.append({"branch":branch,"actual_replay_samples":histories[0].size(),"physics_replay_exact":histories[0]==histories[1],"natural_outcome_not_held":true})

func commitment_brake_equivalence(branch: String) -> void:
	var histories: Array=[]
	for held: bool in [false,true]:
		var b: Node2D=make(branch);var p: Dictionary=b.entity(1)
		p.powers.append_array(["orbit_drive","high_gear","redline"])
		p.power_ranks.merge({"orbit_drive":2,"high_gear":2,"redline":2},true)
		b.powers.setup(b);b.roster.setup(b)
		p.pos=Vector2.ZERO;p.vel=Vector2(160,0)
		var heading: Vector2=Vector2.RIGHT
		if branch=="wallbreaker":
			p.vel=b.roster.ecology.wall_velocity(p,Vector2(200,0),Vector2(-140,0),200.,Vector2.RIGHT,p.pos)
			heading=Vector2.LEFT
		else:b.roster.state(p).bank=100.0
		# One legal ordinary Burst, with disclosed initial hook stock for Flywheel.
		b._attempt_burst(p,heading)
		var samples: Array=[]
		for tick: int in range(18):
			b.fixture_step(heading.rotated(.70),false,held)
			samples.append(b.fixture_snapshot())
			check(not bool(p.get("drift_active",false)) and not bool(b.roster.state(p).braking),branch+" raw Brake cannot secretly carve or bank during its commitment")
		histories.append(samples);b.free()
	check(histories[0]==histories[1],branch+" held vs released raw Brake gives identical actual combined Orbit/Gear/Redline physics and accounting")
	rows.append({"branch":branch,"combined_power_ids":["orbit_drive","high_gear","redline"],"raw_brake_equivalence_samples":18,"exact":histories[0]==histories[1],"hook_stock_fixture":branch=="flywheel_release"})

func stacking_priority() -> void:
	var b: Node2D=make("wallbreaker");var p: Dictionary=b.entity(1)
	p.powers.append_array(["momentum_bank","redline","high_gear","orbit_drive"])
	p.power_ranks.merge({"momentum_bank":3,"redline":3,"high_gear":3,"orbit_drive":2},true)
	p.power_mutations.merge({"momentum_bank":"flywheel_release","redline":"breakneck","high_gear":"flow_state"},true)
	b.powers.setup(b);b.roster.setup(b)
	# Declared paid Breakneck phase for a precise overlap boundary. New Comet
	# arming comes from the actual wall solver, never a forged Comet charge.
	var red: Dictionary=b.powers._state(p)
	red.redline_until=1.6;red.redline_commit_until=.48;red.redline_heading=Vector2.RIGHT;red.redline_rank=3;red.redline_mutation="breakneck"
	p.redline_time=1.6;p.redline_active_rank=3;p.redline_active_mutation="breakneck";p.redline_commit_time=.48
	p.pos=Vector2(169,0);p.vel=Vector2(200,0)
	b._resolve_boundary(p)
	check(count(b,"wallbreaker_arm")==1 and Vector2(p.comet_heading).x<-.9,"Actual wall rebound during existing Breakneck earns a reflected Comet lock")
	var prepared: Dictionary=b.roster.ecology.controls(p,Vector2.DOWN,true)
	check(prepared.committed and Vector2(prepared.direction).dot(Vector2.LEFT)>.95 and not prepared.braking,"Live Comet takes direction priority over opposite Breakneck")
	b._update_fighter(p,Vector2.DOWN,true,1.0/60.0)
	check(Vector2(b.roster.state(p).input).dot(Vector2.LEFT)>.95 and Vector2(p.ecology_heading).dot(Vector2.LEFT)>.95,"Actual winning control and mounted heading agree after Flow/Orbit smoothing")
	b.roster.state(p).bank=100.0
	b.roster.burst(p,Vector2.UP,Vector2(p.vel))
	check(count(b,"flywheel_release")==1,"Bank releases through its ordinary hook while Breakneck and Comet are live")
	prepared=b.roster.ecology.controls(p,Vector2.RIGHT,true)
	check(Vector2(prepared.direction).dot(Vector2.UP)>.95 and not prepared.braking,"Current Bank release takes priority over Comet and Breakneck")
	b._update_fighter(p,Vector2.RIGHT,true,1.0/60.0)
	check(Vector2(b.roster.state(p).input).dot(Vector2.UP)>.95 and Vector2(p.ecology_heading).dot(Vector2.UP)>.95,"Bank physical line and mounted metadata agree in the stacked build")
	var s: Dictionary=b.roster.ecology.state(p);var before_bank: float=float(s.bank_until);var before_comet: float=float(s.comet_until)
	b.roster.begin_tick(.651)
	prepared=b.roster.ecology.controls(p,Vector2.DOWN,false)
	check(before_bank<before_comet and count(b,"flywheel_miss")==1 and Vector2(prepared.direction).dot(Vector2.LEFT)>.95,"Expired Bank relinquishes direction to the still-live Comet with its one miss cost")
	check(Vector2(p.ecology_heading).dot(Vector2.LEFT)>.95,"Mounted heading switches at the same Bank expiry boundary")
	b.roster.begin_tick(.55)
	prepared=b.roster.ecology.controls(p,Vector2.DOWN,true)
	check(not prepared.committed and prepared.direction==Vector2.DOWN and prepared.braking and count(b,"wallbreaker_miss")==1,"After both locks expire ordinary controls resume with no permanent direction or Brake override")
	rows.append({"stacked_power_ids":p.powers,"declared_initial_breakneck":true,"actual_wall_rebound":true,"direction_order":["bank","wallbreaker","ordinary_or_breakneck"],"events":b.powers.events.duplicate(true),"diagnostic":b.roster.ecology.diagnostics(p)})
	b.free()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	if not output.is_absolute_path() or FileAccess.file_exists(output):quit(2);return
	for owner: int in [1,2]:
		wallbreaker(owner);ricochet(owner);centrifuge(owner);perpetual(owner);flywheel(owner);countersteer(owner);reactive(owner);damper(owner)
	for family: String in Draft.NEW_PAIRS:
		for branch: String in Draft.NEW_PAIRS[family]:guarded_states(branch);replay(branch)
	commitment_brake_equivalence("wallbreaker");commitment_brake_equivalence("flywheel_release")
	stacking_priority()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(Draft.portable({"checks":checks,"failures":failures,"observations":rows,
		"scope":"Independent exact semantic threshold/cost/payoff/downside/cooldown fixtures for each branch and both actual player/NPC owners; declared initial stored/curve states isolate gates. Team/small/neutral/paused/terminal guards and event provenance are checked. Eight deterministic canonical Battle replay fixtures use initial legal loadout/position/velocity, then only sampled ordinary controls; no ongoing charge/reserve/pose/outcome writes. Acquisition and current-native runtime showcases are separate evidence; no natural survival or AI skill claim."}),"\t"))
	print("MUTATION_PHYSICS_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()]);quit(0 if failures.is_empty() else 1)
