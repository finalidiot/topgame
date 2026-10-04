extends SceneTree
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func fixture(ids: Array = [], ranks: Dictionary = {}, mutations: Dictionary = {}) -> Node2D:
	var b = Battle.new()
	root.add_child(b); b.set_physics_process(false)
	var d: Dictionary = Encounters.for_run_event(1,421)
	d.starter_id = "vane"; d.player_power_ids = ids
	d.player_power_ranks = ranks; d.player_power_mutations = mutations
	b.begin_run(Starters.build_for("vane"),d,421); b.battle_status = "battle"
	return b
func movement_speed(rank_value: int, mutation: String = "") -> float:
	var b = fixture([] if rank_value == 0 else ["high_gear"],{"high_gear":rank_value},{"high_gear":mutation})
	var p: Dictionary = b.player_entity(); p.pos = Vector2.ZERO; p.vel = Vector2.ZERO
	for tick in range(90):
		b.elapsed += Battle.FIXED_DT; b.roster.begin_tick(Battle.FIXED_DT)
		b._update_fighter(p,Vector2.RIGHT,false,Battle.FIXED_DT)
	var speed: float = Vector2(p.vel).length(); b.free(); return speed
func run() -> void:
	var base: float = movement_speed(0)
	var one: float = movement_speed(1)
	var two: float = movement_speed(2)
	var raw: float = movement_speed(3,"terminal_velocity")
	var flow: float = movement_speed(3,"flow_state")
	check(one > base*1.20,"Rank I speed is immediately noticeable in actual movement")
	check(two > one*1.09,"Rank II deepens actual movement speed")
	check(raw > flow and raw > two,"Terminal Velocity has the highest raw ceiling")
	check(raw <= b_max_speed(),"Developed speed stays below the safety ceiling")
	print("ROSTER_SPEED baseline=%.2f I=%.2f II=%.2f raw=%.2f flow=%.2f" % [base,one,two,raw,flow])
	var b = fixture(["high_gear"],{"high_gear":3},{"high_gear":"terminal_velocity"})
	var p: Dictionary = b.player_entity(); p.vel = Vector2(280,0)
	var before: float = p.rpm
	b.roster.movement(p,b.powers.movement_control(p,Vector2.LEFT,true,0.2),0.2)
	check(p.rpm < before and b.continuous.economy.losses.steering > 0.0,"Raw speed spends RPM on sharp correction and braking")
	p.vel = Vector2(10000,0); b._update_fighter(p,Vector2.RIGHT,false,0.01)
	check(Vector2(p.vel).length() <= b_max_speed()+0.00001,"Combined velocity cannot bypass speed clamp")
	b.free()
	_test_drift(); _test_bank(); _test_contacts(); _test_crosscut_safety(); _test_freeze()
	print("ROSTER_PHYSICS_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
func b_max_speed() -> float: return 480.0
func _test_drift() -> void:
	var normal = fixture()
	var drift = fixture(["orbit_drive"],{"orbit_drive":2})
	for b in [normal,drift]:
		var p: Dictionary = b.player_entity(); p.pos = Vector2.ZERO; p.vel = Vector2(190,0)
		for tick in range(90):
			b.elapsed += Battle.FIXED_DT; b.roster.begin_tick(Battle.FIXED_DT)
			b._update_fighter(p,Vector2(p.vel).normalized().rotated(0.75),true,Battle.FIXED_DT)
	var p: Dictionary = drift.player_entity()
	check(Vector2(p.vel).length() > Vector2(normal.player_entity().vel).length()*1.8,"Brake-turn drift carries momentum through a slide")
	check(bool(p.drift_active) and Vector2(p.vel).y > 15.0,"Steering deliberately carves the slide into an arc")
	check(float(p.orbit_charge) > 0.10,"Actual curved motion builds Orbit flow")
	check(drift.roster.diagnostics(p).drift_seconds > 1.35,"Drift telemetry measures actual sustained slides")
	var s: Dictionary = drift.roster.state(p); s.orbit = 0.95
	drift.roster.movement(p,drift.powers.movement_control(p,-Vector2(p.vel).normalized(),false,0.1),0.1)
	drift.roster.velocity(p,p.vel,p.vel,0.1)
	check(float(s.orbit) == 0.0,"Sharp reversal breaks flow instead of maintaining free efficiency")
	normal.free(); drift.free()
func _test_bank() -> void:
	var b = fixture(["momentum_bank"],{"momentum_bank":2})
	var p: Dictionary = b.player_entity(); p.vel = Vector2(200,0)
	var m: Dictionary = b.powers.movement_control(p,Vector2.RIGHT,true,0.1)
	b.roster.movement(p,m,0.1)
	for sample in range(20): b.roster.velocity(p,Vector2(200,0),Vector2(160,0),0.1)
	check(float(p.momentum_charge) == 150.0,"Controlled braking stores a finite bank")
	var radius: float = p.radius; var before: float = p.rpm
	b.roster.burst(p,Vector2.RIGHT)
	check(float(p.momentum_charge) == 0.0 and Vector2(p.vel).x > 200.0,"Burst converts banked braking into a real launch")
	check(p.rpm < before and b.continuous.economy.losses.powers > 0.0,"Bank release pays an accounted RPM cost")
	check(float(p.radius) == radius,"Storage changes no collision geometry")
	var speed: float = Vector2(p.vel).length()
	b.roster.burst(p,Vector2.RIGHT)
	check(Vector2(p.vel).length() == speed,"Empty bank cannot release twice")
	b.free()
func _test_contacts() -> void:
	var b = fixture(["crash_guard","predator_line","crosscut"],{"crash_guard":2,"predator_line":2,"crosscut":2})
	var p: Dictionary = b.player_entity(); var target: Dictionary = b.entity(2)
	var s: Dictionary = b.roster.state(p)
	check(b.roster.collision_cost(p) == 1.0,"Crash Guard cannot protect the initial heavy hit")
	b.roster.contact(p,target,0.70,Vector2.RIGHT,Vector2(150,0),Vector2.ZERO)
	check(b.roster.collision_cost(p) == 0.48 and float(p.guard_time) > 0.0,"Heavy hit engages temporary collision conservation")
	var until: float = s.guard_until
	b.roster.contact(p,target,0.70,Vector2.RIGHT,Vector2(150,0),Vector2.ZERO)
	check(float(s.guard_until) == until,"Contact spam cannot extend the guard")
	b.roster.time = until+0.01
	check(b.roster.collision_cost(p) == 1.0,"Guard expires and cannot grant permanent defence")
	for sample in range(3):
		b.roster.time += 0.70
		b.roster.contact(p,target,0.45,Vector2.RIGHT,Vector2(150,0),Vector2.ZERO)
	check(int(p.hunt_stacks) == 3 and int(p.hunt_target) == int(target.entity_id),"Repeated meaningful approaches focus pressure on one rival")
	b.add_full_top(target.build,3,"hostile","other",Vector2(100,30))
	var other: Dictionary = b.entity(3)
	check(b.roster.attack_multiplier(p,target) > 1.0 and b.roster.attack_multiplier(p,other) == 1.0,"Hunt pressure belongs to the pursued target")
	b.roster.time += 0.70
	b.roster.contact(p,other,0.45,Vector2.RIGHT,Vector2(150,0),Vector2.ZERO)
	check(int(p.hunt_stacks) == 1 and int(p.hunt_target) == 3,"Target switching resets accumulated pressure")
	s.input = Vector2.UP; b.roster.time += 2.0
	var before: float = p.rpm; var old_velocity: Vector2 = other.vel
	b.roster.contact(p,other,0.50,Vector2.RIGHT,Vector2(120,60),Vector2.ZERO)
	check(Vector2(other.vel).y != old_velocity.y and p.rpm < before,"Glancing steering shears the rival with a priced physical impulse")
	var procs: int = int(b.roster.counters.get("crosscut",0))
	b.roster.contact(p,other,0.50,Vector2.RIGHT,Vector2(120,60),Vector2.ZERO)
	check(int(b.roster.counters.get("crosscut",0)) == procs,"Crosscut contact cooldown prevents recursive spam")
	b.free()
func _test_freeze() -> void:
	var b = fixture(["high_gear","orbit_drive","momentum_bank"],{"high_gear":2,"orbit_drive":2,"momentum_bank":2})
	var p: Dictionary = b.player_entity(); b.set_paused(true)
	var ledger: Dictionary = b.continuous.economy.snapshot(); var time: float = b.roster.time
	for tick in range(180): b.test_step(Battle.FIXED_DT,Vector2.RIGHT,true,true)
	check(b.roster.time == time and ledger == b.continuous.economy.snapshot(),"Pause and draft freeze power storage, motion and ledger")
	check(is_same(p,b.player_entity()),"Expanded powers keep the same continuous top")
	b.free()

func _test_crosscut_safety() -> void:
	var b = fixture(["crosscut"],{"crosscut":2})
	var p: Dictionary = b.player_entity()
	var target: Dictionary = b.entity(2)
	p.pos = Vector2.ZERO
	target.pos = Vector2(0,float(p.radius)+float(target.radius)-0.5)
	p.vel = Vector2(480,0)
	target.vel = Vector2(0,-400)
	b.roster.movement(p,b.powers.movement_control(p,Vector2.LEFT,false,Battle.FIXED_DT),Battle.FIXED_DT)
	# A real glancing full-top contact clamps the primary impulse, then the
	# lateral Crosscut applies recoil. Its second contribution must retain the
	# same physical ceiling, including before any remaining swarm slices.
	b.resolve_pair(1,2)
	check(int(b.roster.counters.get("crosscut",0)) == 1 and Vector2(target.vel).x < -0.1,"A full-speed glancing collision still delivers the accepted lateral Crosscut")
	check(Vector2(p.vel).length() > 470.0 and Vector2(p.vel).length() <= b_max_speed()+0.0001,"Crosscut aftermath cannot push a genuinely fast physical collision beyond the safety ceiling")
	check(float(b.continuous.economy.losses.powers) >= 0.011999,"The speed safety correction preserves Crosscut's real accounted RPM expenditure")
	b.free()
