extends RefCounted
## Declared initial assemblies/positions/velocity; subsequent controls only.
const Fixture = preload("res://tests/mutation_physics_fixture_003a2.gd")
const SPECS: Array[Dictionary] = [
	{"id":"aggression","family":"iron_comet","branch":"wallbreaker","title":"AGGRESSION / WALLBREAKER + CHAIN II","events":["wallbreaker_arm","wallbreaker_hit"],"existing_events":["chain_prime"],"support":{"chain_impact":2},"pos":Vector2(158,0),"vel":Vector2(350,0)},
	{"id":"fortress","family":"crash_guard","branch":"sacrificial_damper","title":"FORTRESS / DAMPER + SINK II + GYRO II","events":["damper_absorb"],"existing_events":["sink_store"],"support":{"impact_sink":2,"gyro_lock":2},"pos":Vector2.ZERO,"vel":Vector2.ZERO},
	{"id":"technique","family":"iron_comet","branch":"ricochet_engine","title":"TECHNIQUE / RICOCHET + AFTERIMAGE II","events":["ricochet_rebound","ricochet_hit"],"existing_events":["afterimage"],"support":{"afterimage":2},"pos":Vector2(158,-55),"vel":Vector2(200,170)},
	{"id":"endurance","family":"orbit_drive","branch":"perpetual_orbit","title":"ENDURANCE / PERPETUAL ORBIT","events":["perpetual_break"],"pos":Vector2(85,0),"vel":Vector2(0,133)},
	{"id":"sibling_a","family":"momentum_bank","branch":"flywheel_release","title":"BANK SIBLING A / FLYWHEEL RELEASE","events":["flywheel_release"],"pos":Vector2(-70,0),"vel":Vector2(300,0)},
	{"id":"sibling_b","family":"momentum_bank","branch":"countersteer","title":"BANK SIBLING B / COUNTERSTEER","events":["countersteer"],"pos":Vector2(-70,0),"vel":Vector2(300,0)},
	{"id":"second_family","family":"orbit_drive","branch":"centrifuge","title":"ORBIT SIBLING / CENTRIFUGE + GEAR II","events":["centrifuge_hit"],"tangent_boost":.70,"npc_lead":1.50,"pos":Vector2(85,0),"vel":Vector2(0,133)},
	{"id":"hybrid","family":"crash_guard","branch":"reactive_plating","title":"HYBRID / REACTIVE + FIVE COMPLEMENTARY II FAMILIES","events":["reactive_charge","reactive_counter"],"existing_events":["sink_store","chain_prime"],"support":{"high_gear":2,"gyro_lock":2,"impact_sink":2,"chain_impact":2,"iron_comet":2},"pos":Vector2.ZERO,"vel":Vector2.ZERO},
]

static func curve(actor: Dictionary, radius: float=85.0, pace: float=133.0) -> Vector2:
	var pos: Vector2=actor.pos;var vel: Vector2=actor.vel
	var radial: Vector2=pos.normalized() if pos.length()>1.0 else Vector2.RIGHT
	var tangent: Vector2=Vector2(-radial.y,radial.x)
	var route: Vector2=tangent*pace+radial*(radius-pos.length())*2.0
	var thrust: Vector2=(route-vel)*4.0+route*.75-radial*(pace*pace/radius)
	var available: float=(123.0+float(actor.stats.grip)*17.0)*float(actor.handling.get("acceleration",1.0))
	return thrust.limit_length(available)/available

static func toward(actor: Dictionary, point: Vector2, pace: float=130.0) -> Vector2:
	var wanted: Vector2=(point-Vector2(actor.pos)).normalized()*minf(pace,point.distance_to(Vector2(actor.pos))*4.0)
	var available: float=(123.0+float(actor.stats.grip)*17.0)*float(actor.handling.get("acceleration",1.0))
	return ((wanted-Vector2(actor.vel))*5.0+wanted*.75).limit_length(available)/available

static func create(parent: Node, spec: Dictionary) -> Dictionary:
	var b: Node2D=Fixture.create(parent,str(spec.family),str(spec.branch))
	var p: Dictionary=b.player_entity();var e: Dictionary=b.entity(2)
	p.pos=spec.pos;p.vel=spec.vel
	if spec.family=="orbit_drive" or spec.id=="hybrid":
		p.powers.append("high_gear");p.power_ranks.high_gear=2
	for family: String in spec.get("support",{}):
		if not family in p.powers:p.powers.append(family)
		p.power_ranks[family]=int(spec.support[family])
	match str(spec.id):
		"aggression":e.pos=Vector2(75,0)
		"technique":e.pos=Vector2(70,30)
		"fortress":e.pos=Vector2(42,0);e.vel=Vector2(-300,0)
		"hybrid":
			e.pos=Vector2(42,0);e.vel=Vector2(-245,0)
			b.add_full_top(p.build,3,b.HOSTILE_TEAM,"fixture_rival_2",Vector2(-70,0))
			var third: Dictionary=b.entity(3);third.ai_burst_delay=99999.;third.erase("role");third.erase("pilot")
		"endurance":e.pos=Vector2.ZERO
		"second_family":e.pos=spec.get("enemy_pos",Vector2.ZERO)
		_:e.pos=Vector2(100,35)
	b.powers.setup(b);b.roster.setup(b)
	var scene: Dictionary={"battle":b,"spec":spec,"released":false,"initial":b.fixture_snapshot(),"controls":[],"contacts":[],"peak_orbit":0.0,"peak_bank":0.0,"flow_frames":0,"clock_failures":0}
	b.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		var r: Dictionary=b.roster.state(p)
		scene.contacts.append({"event":event.duplicate(true),"orbit":r.orbit,"flow":p.get("orbit_flow",false),"input":r.input}))
	return scene

static func step(scene: Dictionary, tick: int) -> Dictionary:
	var b: Node2D=scene.battle;var p: Dictionary=b.player_entity();var e: Dictionary=b.entity(2)
	var direction: Vector2=Vector2.ZERO;var braking: bool=false;var bursting: bool=false
	match str(scene.spec.id):
		"aggression":direction=Vector2.RIGHT if tick<5 else Vector2.LEFT*.55
		"technique":direction=Vector2(-.45,.70) if tick<6 else (Vector2(e.pos)-Vector2(p.pos)).normalized()*.70
		"fortress":direction=Vector2.RIGHT*.55;braking=tick>=60 and tick<150
		"hybrid":direction=Vector2.LEFT*.95
		"endurance":
			direction=curve(p)
			if tick>=540:braking=true;direction=Vector2.ZERO
		"second_family":
			direction=(curve(p)+Vector2(p.vel).normalized()*float(scene.spec.get("tangent_boost",.30))).limit_length(1.0)
			if tick>=int(scene.spec.get("npc_start",180)):
				var angular: float=Vector2(p.pos).cross(Vector2(p.vel))/maxf(1.0,Vector2(p.pos).length_squared())
				var intercept: Vector2=Vector2(p.pos).rotated(angular*float(scene.spec.get("npc_lead",.75)))
				b.fixture_controls[2]={"direction":toward(e,intercept,190.0),"brake":false}
		"sibling_a","sibling_b":
			if not scene.released:
				direction=Vector2.RIGHT*.8;braking=true
				if float(p.get("momentum_charge",0.0))>=75.0:
					scene.released=true;braking=false;bursting=true
					direction=Vector2.UP if scene.spec.id=="sibling_b" else (Vector2(e.pos)-Vector2(p.pos)).normalized()
			else:direction=Vector2.UP*.30 if scene.spec.id=="sibling_b" else (Vector2(e.pos)-Vector2(p.pos)).normalized()*.65
	var control: Dictionary={"tick":tick,"direction":direction,"burst":bursting,"brake":braking,"npc":b.fixture_controls.duplicate(true)}
	scene.controls.append(control);b.fixture_step(direction,bursting,braking)
	scene.peak_orbit=maxf(float(scene.peak_orbit),float(p.get("orbit_charge",0.0)))
	scene.peak_bank=maxf(float(scene.peak_bank),float(p.get("momentum_charge",0.0)))
	if bool(p.get("orbit_flow",false)):scene.flow_frames+=1
	if not is_equal_approx(b.elapsed,b.powers.time) or not is_equal_approx(b.elapsed,b.roster.time) or not is_equal_approx(b.elapsed,b.roster.ecology.time):scene.clock_failures+=1
	return control
