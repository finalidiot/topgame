extends SceneTree
## Additional independent integration contracts. Declared hook stock is used
## only for guard/Burst boundaries; the sustained curve earns DRIVE from zero.
const Fixture = preload("res://tests/mutation_physics_fixture_003a2.gd")
const Draft = preload("res://tests/mutation_draft_policy_003a2.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var output: String = ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func near(a: float, b: float) -> bool: return absf(a-b) < 0.000001
func vector_near(a: Vector2, b: Vector2) -> bool: return a.distance_to(b) < 0.00001
func total(values: Dictionary) -> float:
	var result: float = 0.0
	for value: float in values.values(): result += value
	return result
func make(family: String, branch: String, owner: int = 1) -> Node2D:
	return Fixture.create(root,family,branch,owner)
func captured(b: Node2D) -> Dictionary:
	return {"physical":b.fixture_snapshot(),"fx":b._power_fx.duplicate(true),
		"power_owner_states":b.powers._states.duplicate(true),
		"event_sequence":b.powers._next_event_id,"requests":b.powers._requests.duplicate(true),
		"pulses":b.powers._next_tick_pulses.duplicate(true),"progression":b._progression_contacted.duplicate()}

func dead_owner(family: String, branch: String, owner: int) -> void:
	var b: Node2D = make(family,branch,owner)
	var p: Dictionary = b.entity(owner)
	var t: Dictionary = b.entity(3-owner)
	var e: RefCounted = b.roster.ecology
	# Declared positive stores/armed timers isolate the live-owner boundary.
	# These are not represented as earned activations or natural balance.
	var s: Dictionary = e.state(p)
	s.comet_until = 1.0; s.comet_heading = Vector2.RIGHT; s.ricochets = 3
	s.bank_until = 1.0; s.bank_heading = Vector2.RIGHT; s.bank_release = 100.0
	s.reactive_force = 80.0; s.reactive_until = 1.0
	s.reactive_contact = 0; s.contact_serial = 1
	var r: Dictionary = b.roster.state(p)
	r.bank = 100.0; r.orbit = 1.0; r.input = Vector2.DOWN
	p.orbit_charge = 1.0; p.orbit_flow = true; p.vel = Vector2(150,150)
	p.outcome = "spin_out"
	check(b.battle_status == "battle" and str(t.outcome).is_empty(),branch+" dead-owner fixture retains a live battle and rival")
	var before: Dictionary = captured(b)
	var reflected: Vector2 = Vector2(-150,140)
	check(e.wall_velocity(p,Vector2(200,140),reflected,200.0,Vector2.RIGHT,p.pos) == reflected,branch+" dead owner cannot alter a physical rebound")
	e.burst(p,Vector2.DOWN,Vector2(200,0))
	var protection: Dictionary = e.prepare_contact(p,t,1.3,Vector2.RIGHT,Vector2.ZERO,Vector2(-300,0),200.0)
	e.contact(p,t,1.3,Vector2.RIGHT,Vector2(200,200))
	check(protection == {"recoil":1.0,"shock":1.0,"cost":0.0},branch+" dead owner cannot retain an incoming collision")
	var raw: Dictionary = {"direction":Vector2.DOWN,"braking":true,"speed":1.0,"acceleration":1.0,"drain":1.0,"drag":1.0}
	check(e.movement(p,raw.duplicate(),1.0/60.0) == raw,branch+" dead owner cannot override movement or grant efficiency")
	var controls: Dictionary = e.controls(p,Vector2.DOWN,true)
	check(controls.direction == Vector2.DOWN and controls.braking and not controls.committed,branch+" dead armed owner cannot continue a steering commitment")
	check(e.velocity(p,p.vel,Vector2(130,30),1.0/60.0) == Vector2(130,30) and e.collision_cost(p) == 1.0,branch+" dead owner cannot carve, tax or provide a later guard")
	check(before == captured(b),branch+" dead-owner hooks change no state, RPM, receiver, FX, event provenance or queued work")
	observations.append({"branch":branch,"owner":owner,"kind":"dead_owner_live_battle","declared_positive_gate_state":true,"unchanged":before == captured(b)})
	b.free()

func unowned_reference() -> Node2D:
	var b: Node2D = make("crash_guard","sacrificial_damper")
	var p: Dictionary = b.entity(1)
	p.powers = []; p.power_ranks = {}; p.power_mutations = {}
	b.powers.setup(b); b.roster.setup(b)
	return b

func damper_solver() -> void:
	var baseline: Node2D = unowned_reference()
	var actual: Node2D = make("crash_guard","sacrificial_damper")
	var data: Array[Dictionary] = []
	for b: Node2D in [baseline,actual]:
		var p: Dictionary = b.entity(1); var t: Dictionary = b.entity(2)
		# One declared genuine approaching pair, then the production solver.
		p.pos = Vector2.ZERO; p.vel = Vector2(75,20)
		t.pos = Vector2(15,0); t.vel = Vector2(-245,20)
		var prior: Dictionary = {"owner_velocity":p.vel,"target_velocity":t.vel,"rpm":p.rpm,"ledger":b.continuous.economy.snapshot()}
		b.resolve_pair(1,2)
		var ledger: Dictionary = b.continuous.economy.snapshot()
		data.append({"prior":prior,"owner_velocity":p.vel,"target_velocity":t.vel,"rpm":p.rpm,
			"collision_loss":float(ledger.losses.collisions)-float(prior.ledger.losses.collisions),
			"power_loss":float(ledger.losses.powers)-float(prior.ledger.losses.powers),
			"hits":b.hits,"counters":b.roster.ecology.counters.duplicate(),"ledger":ledger})
	check(data[0].hits == 1 and data[1].hits == 1,"Damper comparison resolves one actual accepted collision in each legal initial assembly")
	check(int(actual.roster.ecology.counters.get("damper_absorb",0)) == 1,"Actual solver earns Damper from its own severe incoming collision delta")
	var ordinary_delta: Vector2 = data[0].owner_velocity-data[0].prior.owner_velocity
	var protected_delta: Vector2 = data[1].owner_velocity-data[1].prior.owner_velocity
	check(ordinary_delta.length() >= 80.0 and vector_near(protected_delta,ordinary_delta*.40),"Damper retains THIS solver delta at40 percent and preserves pre-contact carried motion")
	check(vector_near(data[0].target_velocity,data[1].target_velocity),"Damper changes owner retention without inventing an offensive receiver impulse")
	check(near(data[1].collision_loss,data[0].collision_loss*.28),"Actual Damper collision ledger applies28 percent shock loss to THIS hit")
	check(near(data[0].power_loss,0.0) and near(data[1].power_loss,.009),"Damper separately debits its009 power fee after the protected collision loss")
	check(near(data[1].rpm,data[1].prior.rpm-data[0].collision_loss*.28-.009),"Actual reserve closes from protected shock plus the unprotected power fee")
	# A newly admitted legal incoming top makes a distinct second accepted hit.
	# A separate unowned reference starts from that exact physical state. This
	# is a solver/cooldown fixture, not a natural spawn or survival observation.
	var p: Dictionary = actual.entity(1)
	actual.add_full_top(p.build,3,actual.HOSTILE_TEAM,"fixture_second_hit",Vector2(p.pos)+Vector2(-15,0))
	var incoming: Dictionary = actual.entity(3)
	incoming.vel = Vector2(300,20)
	var later_baseline: Node2D = unowned_reference()
	var ref_owner: Dictionary = later_baseline.entity(1); var ref_target: Dictionary = later_baseline.entity(2)
	for field: String in ["pos","vel","rpm","energy","wobble"]: ref_owner[field] = p[field]
	for field: String in ["pos","vel","rpm","energy","wobble"]: ref_target[field] = incoming[field]
	var velocity_before: Vector2 = p.vel
	var actual_ledger_before: Dictionary = actual.continuous.economy.snapshot()
	var reference_ledger_before: Dictionary = later_baseline.continuous.economy.snapshot()
	actual.resolve_pair(1,3); later_baseline.resolve_pair(1,2)
	var after: Dictionary = actual.continuous.economy.snapshot()
	var reference_after: Dictionary = later_baseline.continuous.economy.snapshot()
	check(actual.hits == 2 and later_baseline.hits == 1,"Cooldown comparison receives a distinct real accepted incoming collision")
	check(int(actual.roster.ecology.counters.get("damper_absorb",0)) == 1,"Second accepted severe hit cannot retrigger the seven-second Damper cooldown")
	check(vector_near(Vector2(p.vel)-velocity_before,Vector2(ref_owner.vel)-velocity_before),"A later hit receives ordinary solver recoil while Damper is on cooldown")
	check(near(float(after.losses.collisions)-float(actual_ledger_before.losses.collisions),float(reference_after.losses.collisions)-float(reference_ledger_before.losses.collisions)),"Later accepted contact has ordinary shock cost, without permanent Damper protection")
	check(near(float(after.losses.powers),float(actual_ledger_before.losses.powers)),"The cooldown contact charges no second Damper activation fee")
	observations.append({"kind":"actual_damper_solver","first_contact_comparison":data,"later_actual":after,"later_reference":reference_after,"second_target_is_declared_admission":true})
	baseline.free(); actual.free(); later_baseline.free()

func bank_burst(branch: String, owner: int) -> void:
	var b: Node2D = make("momentum_bank",branch,owner)
	var p: Dictionary = b.entity(owner)
	var r: Dictionary = b.roster.state(p)
	# Declared initial stock isolates ordinary accepted Burst+power accounting.
	r.bank = 100.0; p.momentum_charge = 100.0; p.vel = Vector2(180,0)
	var before: float = p.rpm
	var velocity_before: Vector2 = p.vel
	var push: float = 67.0+float(p.stats.grip)*3.0
	var heading: Vector2 = Vector2.RIGHT if branch == "flywheel_release" else Vector2.DOWN
	var fee: float = .024 if branch == "flywheel_release" else .016
	var ledger_before: Dictionary = b.continuous.economy.snapshot()
	b._attempt_burst(p,heading)
	check(near(before-float(p.rpm),.013+fee),branch+" ordinary Burst pays013 plus its separate exact branch fee for either owner")
	check(near(float(r.bank),0.0) and near(float(p.momentum_charge),0.0),branch+" actual Burst consumes the declared stock once")
	if branch == "flywheel_release":
		check(vector_near(p.vel,velocity_before+heading*(push+115.0)),"Flywheel actual launch retains ordinary Burst thrust and adds stored forward velocity")
	else:
		check(vector_near(p.vel,heading*202.0),"Countersteer uses PRE-Burst carried speed rather than silently banking ordinary Burst thrust")
	check(p.burst_time > 0.0 and p.cooldown > 0.0,branch+" branch activation goes through the canonical accepted Burst state")
	var ledger: Dictionary = b.continuous.economy.snapshot()
	if owner == 1:
		check(near(float(ledger.losses.burst)-float(ledger_before.losses.burst),.013) and near(float(ledger.losses.powers)-float(ledger_before.losses.powers),fee),branch+" player ledger separates ordinary Burst and branch spending")
	else:
		check(ledger.losses == ledger_before.losses,branch+" NPC spending cannot enter the player expense ledger")
	observations.append({"kind":"canonical_bank_burst","branch":branch,"owner":owner,"initial_stock":100.0,"declared_stock":true,"rpm_before":before,"rpm_after":p.rpm,"velocity_before":velocity_before,"velocity_after":p.vel,"ledger":ledger})
	b.free()
	if branch == "countersteer":
		b = make("momentum_bank",branch,owner); p = b.entity(owner); r = b.roster.state(p)
		r.bank = 100.0; p.momentum_charge = 100.0; p.vel = Vector2(180,0); before = p.rpm
		b._attempt_burst(p,Vector2.RIGHT)
		check(near(before-float(p.rpm),.013) and near(float(r.bank),100.0),"Straight Countersteer Burst pays ordinary cost and retains its stock without a mutation release")
		check(vector_near(p.vel,Vector2(180.0+push,0)) and int(b.roster.ecology.counters.get("countersteer",0)) == 0,"Straight Countersteer keeps canonical forward Burst motion and has no redirect proc")
		b.free()

func curve_control(p: Dictionary) -> Vector2:
	# Continuous sampled steering of an85-unit circle at133 units/s. This
	# computes controls from actual position/velocity; it never writes them.
	var radial: Vector2 = Vector2(p.pos).normalized() if Vector2(p.pos).length() > 1.0 else Vector2.RIGHT
	var route: Vector2 = Vector2(-radial.y,radial.x)*133.0+radial*(85.0-Vector2(p.pos).length())*2.0
	var thrust: Vector2 = (route-Vector2(p.vel))*4.0+route*.75-radial*(133.0*133.0/85.0)
	var available: float = (123.0+float(p.stats.grip)*17.0)*float(p.handling.get("acceleration",1.0))
	return thrust.limit_length(available)/available

func earned_perpetual() -> void:
	var b: Node2D = make("orbit_drive","perpetual_orbit")
	var p: Dictionary = b.entity(1); var t: Dictionary = b.entity(2)
	# Legal initial assembly/physical velocity, zero starting DRIVE. The rival
	# remains at centre under the existing explicitly neutral QA pilot policy.
	p.powers.append("high_gear"); p.power_ranks.high_gear = 2
	p.pos = Vector2(85,0); p.vel = Vector2(0,133); t.pos = Vector2.ZERO
	b.powers.setup(b); b.roster.setup(b)
	check(float(b.roster.state(p).orbit) == 0.0 and float(p.get("orbit_charge",0.0)) == 0.0,"Perpetual curve starts without declared or held DRIVE")
	var first_full: Dictionary = {}; var qualifying: int = 0; var samples: Array[Dictionary] = []
	var started: float = p.rpm; var elapsed_start: float = b.elapsed
	var ledger_start: Dictionary = b.continuous.economy.snapshot()
	for tick: int in range(360):
		b.fixture_step(curve_control(p))
		if float(p.get("orbit_charge",0.0)) >= 1.0 and bool(p.get("orbit_flow",false)) and Vector2(p.vel).length() > 80.0:
			qualifying += 1
			if first_full.is_empty(): first_full = {"tick":tick,"rpm":p.rpm,"ledger":b.continuous.economy.snapshot()}
		if tick%30 == 0: samples.append({"tick":tick,"pos":p.pos,"vel":p.vel,"rpm":p.rpm,"drive":p.get("orbit_charge",0.0),"flow":p.get("orbit_flow",false)})
		if b.battle_status != "battle": break
	var ledger: Dictionary = b.continuous.economy.snapshot()
	var earned: float = float(ledger.gains.get("orbit_drive",0.0))-float(ledger_start.gains.get("orbit_drive",0.0))
	check(not first_full.is_empty() and qualifying > 0,"Ordinary fixed-step steering earns full same-sign Perpetual flow from zero")
	check(earned > 0.0 and int(b.powers.counters.get("orbit_full_recovery",0)) > 0,"Real earned Perpetual flow produces actual source-accounted RPM recovery")
	check(earned <= .017*float(qualifying)/60.0+.000001 and earned <= .09+.026*(b.elapsed-elapsed_start)+.000001,"Earned Perpetual recovery stays below its rate and shared finite recovery bucket")
	check(b.hits == 0 and near(total(ledger.gains)-float(ledger.gains.get("orbit_drive",0.0)),0.0),"Isolated earned curve receives no combat/kill/other-power income")
	check(near(float(p.rpm)-started,(total(ledger.gains)-total(ledger_start.gains))-(total(ledger.losses)-total(ledger_start.losses))),"Actual movement costs and Perpetual recovery close the reserve ledger")
	if not first_full.is_empty():
		check(float(p.rpm) > float(first_full.rpm),"Sustaining earned full Perpetual flow raises actual RPM after ordinary movement costs")
		check(float(ledger.gains.orbit_drive) > float(first_full.ledger.gains.get("orbit_drive",0.0)),"Net rise includes newly earned Perpetual source income after the first full-flow stamp")
	else:
		check(false,"Missing full-flow stamp cannot claim a net actual RPM increase")
		check(false,"Missing full-flow stamp cannot claim a source-backed increase")
	check(float(p.rpm) <= 1.0 and b.battle_status == "battle" and str(p.outcome).is_empty(),"Earned flow remains capped without held survival outcomes")
	var idle_income: float = float(ledger.gains.get("orbit_drive",0.0))
	for tick: int in range(90): b.fixture_step(Vector2.ZERO)
	var idle: Dictionary = b.continuous.economy.snapshot()
	check(near(float(idle.gains.get("orbit_drive",0.0)),idle_income),"Releasing steering stops Perpetual income even when previously full")
	observations.append({"kind":"earned_perpetual_curve","initial_velocity_fixture":Vector2(0,133),"initial_drive":0.0,"ongoing_actor_resource_writes":false,
		"steps":360,"qualifying_full_frames":qualifying,"first_full":first_full,"samples":samples,"ledger_before":ledger_start,"ledger_after_curve":ledger,"ledger_after_idle":idle,"earned_orbit_rpm":earned})
	b.free()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	var normalized: String = output.replace("\\","/").to_lower()
	if not output.is_absolute_path() or FileAccess.file_exists(output) or not "/gyrobrothers-qa/003a.2/manifests/" in normalized: quit(2); return
	for owner: int in [1,2]:
		for family: String in Draft.NEW_PAIRS:
			for branch: String in Draft.NEW_PAIRS[family]: dead_owner(family,branch,owner)
		bank_burst("flywheel_release",owner); bank_burst("countersteer",owner)
	damper_solver(); earned_perpetual()
	var report: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	check(report != null,"Supplement creates only the requested fresh external003A.2 report")
	if report != null:
		report.store_string(JSON.stringify(Draft.portable({"checks":checks,"failures":failures,"observations":observations,
			"scope":"Live-battle dead owner boundaries for both ownerships and all eight mutations; actual Damper resolve_pair recoil/shock/activation-cost order plus a distinct accepted cooldown hit; canonical ordinary Burst plus Bank fees/retention from explicitly declared initial stock; Perpetual actual continuously sampled curve from zero DRIVE with source ledger/net reserve and idle cessation. No production changes, forced live outcomes or ongoing pose/velocity/reserve/charge writes in earned flow. Direct guard/stock/second-hit fixtures do not claim natural balance or NPC tactics."}),"\t"))
	print("MUTATION_SOLVER_CONTRACT_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
