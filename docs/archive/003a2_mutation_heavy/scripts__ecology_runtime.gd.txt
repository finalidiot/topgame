extends RefCounted
## Rank III transformations use real movement, wall reflection and accepted
## full-top contacts. No target scans, queued attacks or autonomous RPM income.
const Catalog = preload("res://scripts/run_powers.gd")
const FAMILIES: Array[String] = ["iron_comet", "orbit_drive", "momentum_bank", "crash_guard"]
const WALLBREAKER_SPEED: float = 160.0
const WALLBREAKER_SECONDS: float = 1.2
const RICOCHET_SPEED: float = 110.0
const CENTRIFUGE_SEVERITY: float = 0.45
const CENTRIFUGE_TANGENT: float = 70.0
const REACTIVE_SEVERITY: float = 0.60
const DAMPER_SEVERITY: float = 0.85
const DAMPER_FORCE: float = 80.0
const PERPETUAL_RECOVERY: float = 0.017
const CENTRIFUGE_RECOVERY: float = 0.007
var _host: WeakRef
var time: float = 0.0
var states: Dictionary = {}
var counters: Dictionary = {}

func setup(battle: Object) -> void:
	_host = weakref(battle)
	time = 0.0
	states.clear()
	counters.clear()

func host() -> Object: return _host.get_ref() if _host != null else null
func rank(f: Dictionary, family: String) -> int:
	return clampi(int(f.get("power_ranks",{}).get(family,1)),1,3) if family in f.get("powers",[]) else 0
func branch(f: Dictionary, family: String) -> String:
	if rank(f,family) != 3: return ""
	var selected: String = str(f.get("power_mutations",{}).get(family,""))
	return selected if selected in Catalog.MUTATION_BRANCHES.get(family,[]) else ""
func live(f: Dictionary) -> bool:
	return host() != null and not f.is_empty() and str(f.get("outcome", "")).is_empty() and f.get("combatant_type", "") == "full_top" and host().battle_status == "battle" and not host().paused and not host().powers._stopped
func owns(f: Dictionary) -> bool:
	for family: String in FAMILIES:
		if not branch(f, family).is_empty(): return true
	return false
func opposes(f: Dictionary, target: Dictionary) -> bool:
	return live(f) and live(target) and host().powers._opposes(f, target)
func state(f: Dictionary) -> Dictionary:
	var id: int = int(f.entity_id)
	if not states.has(id):
		states[id] = {"comet_until":0.0,"comet_ready":0.0,"comet_heading":Vector2.ZERO,"ricochets":0,
			"bank_until":0.0,"bank_ready":0.0,"bank_heading":Vector2.ZERO,"bank_release":0.0,
			"orbit_ready":0.0,"orbit_heading":Vector2(f.vel).normalized(),"orbit_sign":0.0,"orbit_broken":false,
			"reactive_force":0.0,"reactive_until":0.0,"reactive_ready":0.0,"reactive_contact":-1,
			"contact_serial":0,"damper_until":0.0,"damper_ready":0.0}
	return states[id]
func emit(kind: String, f: Dictionary, direction: Vector2 = Vector2.ZERO, target: Dictionary = {}, strength: float = 1.0) -> void:
	counters[kind] = int(counters.get(kind, 0)) + 1
	var aliases: Dictionary = {"wallbreaker_arm":"comet_charge","wallbreaker_hit":"comet_release","wallbreaker_miss":"crosscut",
		"ricochet_rebound":"comet_charge","ricochet_hit":"comet_release","ricochet_break":"orbit_drift",
		"centrifuge_hit":"crosscut","perpetual_break":"orbit_drift","flywheel_release":"momentum_release",
		"flywheel_hit":"comet_release","flywheel_miss":"crosscut","countersteer":"crosscut",
		"reactive_charge":"crash_guard","reactive_counter":"crosscut","damper_absorb":"crash_guard"}
	var cause: Dictionary = host().powers._owned_effect_cause(f, kind)
	host().powers._record(kind, int(f.entity_id), int(target.get("entity_id", 0)), int(cause.root_event_id))
	host().powers._fx(str(aliases.get(kind, kind)), f.pos, direction, strength,
		{"owner_entity_id":int(f.entity_id),"receiver_entity_ids":[] if target.is_empty() else [int(target.entity_id)],"rank":3,"ecology_kind":kind})
func push(f: Dictionary, target: Dictionary, velocity: Vector2, kind: String) -> void:
	if opposes(f, target): host().apply_power_impulse(target, velocity, host().powers._owned_effect_cause(f, kind))

func begin_tick(dt: float) -> void:
	time += dt
	var ids: Dictionary = {}
	for f: Dictionary in host()._ordered_fighters():
		if not owns(f) or not live(f): continue
		ids[int(f.entity_id)] = true
		var s: Dictionary = state(f)
		if float(s.comet_until) > 0.0 and time >= float(s.comet_until):
			if branch(f,"iron_comet") == "wallbreaker":
				host().spend_rpm(f,0.025,"powers")
				f.wobble = minf(1.0,float(f.wobble)+0.10)
				emit("wallbreaker_miss",f,s.comet_heading)
			s.comet_until = 0.0
			s.ricochets = 0
		if float(s.bank_until) > 0.0 and time >= float(s.bank_until):
			host().spend_rpm(f,0.016,"powers")
			f.wobble = minf(1.0,float(f.wobble)+0.10)
			emit("flywheel_miss",f,s.bank_heading)
			s.bank_until = 0.0
		if time >= float(s.reactive_until): s.reactive_force = 0.0
		if time < float(s.damper_until): host().spend_rpm(f,0.010*dt,"powers")
		_publish(f,s)
	for id: int in states.keys():
		if not ids.has(id): states.erase(id)

func _publish(f: Dictionary, s: Dictionary) -> void:
	if not branch(f,"iron_comet").is_empty():
		f["iron_comet_time"] = maxf(0.0,float(s.comet_until)-time)
		f["comet_time"] = f.iron_comet_time
		f["ricochet_count"] = int(s.ricochets)
		f["comet_heading"] = s.comet_heading
	f["ecology_commit_time"] = maxf(0.0,maxf(float(s.bank_until),float(s.comet_until) if branch(f,"iron_comet") == "wallbreaker" else 0.0)-time)
	f["ecology_heading"] = s.bank_heading if time < float(s.bank_until) else s.comet_heading
	f["reactive_force"] = float(s.reactive_force)
	f["reactive_time"] = maxf(0.0,float(s.reactive_until)-time)
	if branch(f,"crash_guard") == "reactive_plating": f["guard_time"] = f.reactive_time
	f["damper_time"] = maxf(0.0,float(s.damper_until)-time)
	f["momentum_capacity"] = bank_capacity(f)

func bank_capacity(f: Dictionary) -> float:
	if branch(f,"momentum_bank") == "flywheel_release": return 240.0
	return 95.0 if rank(f,"momentum_bank") == 1 else 150.0
func bank_leak(f: Dictionary) -> float: return 9.0 if branch(f,"momentum_bank") == "flywheel_release" else 7.0

func controls(f: Dictionary, direction: Vector2, braking: bool) -> Dictionary:
	var result: Dictionary = {"direction":direction,"braking":braking,"committed":false}
	if not owns(f) or not live(f): return result
	var s: Dictionary = states.get(int(f.entity_id),{})
	var heading: Vector2 = Vector2.ZERO
	if branch(f,"iron_comet") == "wallbreaker" and time < float(s.get("comet_until",0.0)): heading = s.comet_heading
	if time < float(s.get("bank_until",0.0)): heading = s.bank_heading
	if heading.length_squared() > 0.1:
		result.direction = (heading+direction*0.12).normalized()
		result.braking = false
		result.committed = true
	return result

func movement(f: Dictionary, m: Dictionary, _dt: float) -> Dictionary:
	if not owns(f) or not live(f): return m
	var s: Dictionary = state(f)
	var heading: Vector2 = Vector2.ZERO
	if time < float(s.comet_until) and branch(f,"iron_comet") == "wallbreaker": heading = s.comet_heading
	if time < float(s.bank_until): heading = s.bank_heading
	if heading.length_squared() > 0.1:
		# One control line wins simultaneous physical commitments: current Bank
		# release, then Comet rebound, then ordinary existing power steering.
		m.direction = m.get("ecology_direction",heading)
		m.braking = false
		m.speed = maxf(float(m.speed),1.6)
		m.acceleration = maxf(float(m.acceleration),1.4)
		# Downstream carve/storage reads the control that actually reaches the
		# solver. A physically disabled Brake cannot bank friction or drift.
		var roster_state: Dictionary = host().roster.state(f)
		roster_state.input = m.direction
		roster_state.braking = false
		roster_state.drift = false
		m.brake_drag_scale = 1.0
		f["drift_active"] = false
		f.impulse_time = maxf(float(f.get("impulse_time",0.0)),0.08)
	if branch(f,"orbit_drive") == "perpetual_orbit" and float(f.get("orbit_charge",0.0)) >= 1.0 and bool(f.get("orbit_flow",false)):
		m.drain = float(m.drain)*0.73
	if branch(f,"iron_comet") == "ricochet_engine" and int(s.ricochets) > 0:
		var speed: float = Vector2(f.vel).length()
		if bool(m.braking) or (speed > 1.0 and Vector2(m.direction).length() > 0.2 and Vector2(f.vel).normalized().dot(Vector2(m.direction).normalized()) < -0.2):
			s.ricochets = 0
			s.comet_until = 0.0
			emit("ricochet_break",f,Vector2(f.vel).normalized())
	if time < float(s.damper_until):
		m.acceleration = float(m.acceleration)*0.45
		m.speed = float(m.speed)*0.65
		m.drag = float(m.drag)+1.2
	_publish(f,s)
	return m

func velocity(f: Dictionary, before: Vector2, after: Vector2, dt: float, previous_drive: float = -1.0) -> Vector2:
	var orbit: String = branch(f,"orbit_drive")
	if orbit.is_empty() or not live(f): return after
	var s: Dictionary = state(f)
	var r: Dictionary = host().roster.state(f)
	var direction: Vector2 = r.input
	var turn: float = Vector2(s.orbit_heading).angle_to(after.normalized()) if Vector2(s.orbit_heading).length_squared() > 0.1 else 0.0
	var rate: float = absf(turn)/maxf(0.001,dt)
	var flowing: bool = after.length() > 80.0 and direction.length() > 0.2 and rate >= 0.12 and rate <= (2.4 if orbit == "perpetual_orbit" else 3.5)
	var reversing: bool = absf(turn) > 0.001 and float(s.orbit_sign) != 0.0 and signf(turn) != float(s.orbit_sign)
	var broken: bool = reversing or rate > 2.4 or (bool(r.braking) and not bool(r.drift)) or (direction.length() > 0.2 and after.normalized().dot(direction.normalized()) < -0.2)
	if orbit == "perpetual_orbit" and broken:
		var charge: float = previous_drive if previous_drive >= 0.0 else maxf(float(r.orbit),float(f.get("orbit_charge",0.0)))
		if not bool(s.orbit_broken) and charge > 0.05:
			host().spend_rpm(f,0.012*charge,"steering")
			after *= 0.90
			emit("perpetual_break",f,before.normalized())
		r.orbit = 0.0
		f.orbit_charge = 0.0
		flowing = false
		s.orbit_broken = true
	elif flowing:
		s.orbit_broken = false
		s.orbit_sign = signf(turn)
	f["orbit_flow"] = flowing and not reversing
	s.orbit_heading = after.normalized()
	return after

func burst(f: Dictionary, heading: Vector2, pre_velocity: Vector2) -> bool:
	var bank_branch: String = branch(f,"momentum_bank")
	if bank_branch.is_empty(): return false
	if not live(f): return true
	var s: Dictionary = state(f)
	var r: Dictionary = host().roster.state(f)
	var stored: float = float(r.bank)
	if time < float(s.bank_ready): return true
	if bank_branch == "flywheel_release" and stored >= 60.0:
		r.bank = 0.0
		f.momentum_charge = 0.0
		host().spend_rpm(f,0.014+stored*0.00010,"powers")
		f.vel = (Vector2(f.vel)+heading*stored*1.15).limit_length(480.0)
		f.impulse_time = maxf(float(f.get("impulse_time",0.0)),0.65)
		s.bank_heading = heading
		s.bank_release = stored
		s.bank_until = time+0.65
		s.bank_ready = time+1.2
		emit("flywheel_release",f,heading,{},stored/240.0)
	elif bank_branch == "countersteer" and stored >= 35.0 and pre_velocity.length() >= 40.0 and absf(pre_velocity.angle_to(heading)) >= PI/3.0:
		r.bank = 0.0
		f.momentum_charge = 0.0
		host().spend_rpm(f,0.010+stored*0.00006,"powers")
		f.vel = heading*minf(480.0,pre_velocity.length()+stored*0.22)
		f.impulse_time = maxf(float(f.get("impulse_time",0.0)),0.20)
		s.bank_ready = time+0.8
		emit("countersteer",f,heading,{},stored/150.0)
	_publish(f,s)
	return true

func wall_velocity(f: Dictionary, before: Vector2, after: Vector2, outward: float, normal: Vector2, _position: Vector2) -> Vector2:
	var comet: String = branch(f,"iron_comet")
	if comet.is_empty() or not live(f) or float(f.rpm) <= 0.13: return after
	var s: Dictionary = state(f)
	if time < float(s.comet_ready): return after
	if comet == "wallbreaker" and outward >= WALLBREAKER_SPEED:
		host().spend_rpm(f,0.018,"powers")
		s.comet_heading = after.normalized()
		s.comet_until = time+WALLBREAKER_SECONDS
		s.comet_ready = time+2.0
		after = after.normalized()*minf(480.0,maxf(after.length(),before.length()*0.85))
		f.impulse_time = maxf(float(f.get("impulse_time",0.0)),WALLBREAKER_SECONDS)
		emit("wallbreaker_arm",f,s.comet_heading)
	elif comet == "ricochet_engine" and outward >= RICOCHET_SPEED:
		var r: Dictionary = host().roster.state(f)
		var incidence: float = outward/maxf(1.0,before.length())
		if bool(r.braking) or Vector2(r.input).length() <= 0.2 or absf(Vector2(r.input).dot(normal.orthogonal())) < 0.25 or incidence < 0.2 or incidence > 0.85: return after
		host().spend_rpm(f,0.006,"powers")
		after = after.normalized()*minf(before.length()*0.94,after.length()*1.24)
		s.ricochets = mini(3,int(s.ricochets)+1)
		s.comet_heading = after.normalized()
		s.comet_until = time+3.0
		s.comet_ready = time+0.30
		f.impulse_time = maxf(float(f.get("impulse_time",0.0)),0.35)
		emit("ricochet_rebound",f,s.comet_heading,{},float(s.ricochets)/3.0)
	_publish(f,s)
	return after

## Called once for each accepted full-top collision before RPM loss. Retention
## scales only the solver's collision delta; carried motion is never removed.
func prepare_contact(f: Dictionary, target: Dictionary, severity: float, normal: Vector2, _own_before: Vector2, rival_before: Vector2, incoming_force: float) -> Dictionary:
	var result: Dictionary = {"recoil":1.0,"shock":1.0,"cost":0.0}
	if branch(f,"crash_guard").is_empty() or not opposes(f,target): return result
	var s: Dictionary = state(f)
	s.contact_serial = int(s.contact_serial)+1
	var incoming: bool = -rival_before.dot(normal) >= 45.0
	f["guard_heading"] = normal
	if branch(f,"crash_guard") == "reactive_plating" and incoming and severity >= REACTIVE_SEVERITY and incoming_force >= 55.0 and time >= float(s.reactive_ready):
		s.reactive_force = minf(100.0,incoming_force*0.32)
		s.reactive_until = time+0.75
		s.reactive_ready = time+3.0
		s.reactive_contact = s.contact_serial
		emit("reactive_charge",f,-normal,target,incoming_force/200.0)
	elif branch(f,"crash_guard") == "sacrificial_damper" and incoming and severity >= DAMPER_SEVERITY and incoming_force >= DAMPER_FORCE and time >= float(s.damper_ready) and float(f.rpm) > 0.13:
		s.damper_ready = time+7.0
		s.damper_until = time+1.4
		result = {"recoil":0.40,"shock":0.28,"cost":0.009}
		f.wobble = minf(1.0,float(f.wobble)+0.04)
		emit("damper_absorb",f,-normal,target,severity)
	_publish(f,s)
	return result

func collision_cost(f: Dictionary) -> float:
	if branch(f,"crash_guard") != "reactive_plating" or not live(f): return 1.0
	if time < float(state(f).reactive_until): return 0.65
	return 1.0

func contact(f: Dictionary, target: Dictionary, severity: float, normal: Vector2, incoming: Vector2) -> void:
	if not owns(f) or not opposes(f,target): return
	var s: Dictionary = state(f)
	var r: Dictionary = host().roster.state(f)
	var approach: float = incoming.dot(normal)
	var comet: String = branch(f,"iron_comet")
	if time < float(s.comet_until) and approach >= (45.0 if comet == "wallbreaker" else 25.0) and severity >= (0.45 if comet == "wallbreaker" else 0.30) and Vector2(s.comet_heading).dot(normal) >= 0.55:
		if comet == "wallbreaker":
			s.comet_until = 0.0
			push(f,target,normal*100.0,"wallbreaker_hit")
			f.vel = (Vector2(f.vel)-normal*45.0).limit_length(480.0)
			f.wobble = minf(1.0,float(f.wobble)+0.07)
			emit("wallbreaker_hit",f,normal,target)
		elif comet == "ricochet_engine" and int(s.ricochets) > 0:
			push(f,target,normal*(18.0+4.0*int(s.ricochets)),"ricochet_hit")
			s.ricochets = int(s.ricochets)-1
			if int(s.ricochets) == 0: s.comet_until = 0.0
			emit("ricochet_hit",f,normal,target)
	if branch(f,"orbit_drive") == "centrifuge" and float(r.orbit) >= 1.0 and bool(f.get("orbit_flow",false)) and time >= float(s.orbit_ready) and severity >= CENTRIFUGE_SEVERITY:
		var tangent: Vector2 = normal.orthogonal()
		var side_speed: float = incoming.dot(tangent)
		var side_input: float = Vector2(r.input).dot(tangent)
		if absf(side_speed) >= CENTRIFUGE_TANGENT and absf(side_input) >= 0.2 and signf(side_input) == signf(side_speed) and float(f.rpm) > 0.05:
			var shove: Vector2 = tangent*signf(side_speed)*minf(95.0,absf(side_speed)*0.45)
			r.orbit = 0.30
			f.orbit_charge = 0.30
			s.orbit_ready = time+1.3
			host().spend_rpm(f,0.012,"powers")
			push(f,target,shove,"centrifuge_hit")
			f.vel = (Vector2(f.vel)-shove*0.30).limit_length(480.0)
			f.wobble = minf(1.0,float(f.wobble)+0.04)
			emit("centrifuge_hit",f,shove.normalized(),target)
	if time < float(s.bank_until) and severity >= 0.60 and approach >= 70.0 and Vector2(s.bank_heading).dot(normal) >= 0.55:
		s.bank_until = 0.0
		f.vel = (Vector2(f.vel)-normal*float(s.bank_release)*0.18).limit_length(480.0)
		f.wobble = minf(1.0,float(f.wobble)+0.05)
		emit("flywheel_hit",f,normal,target)
	if branch(f,"crash_guard") == "reactive_plating" and float(s.reactive_force) > 0.0 and time < float(s.reactive_until) and int(s.reactive_contact) != int(s.contact_serial) and severity >= 0.25 and approach >= 25.0 and Vector2(r.input).dot(normal) >= 0.2 and float(f.rpm) > 0.05:
		var force: float = float(s.reactive_force)
		s.reactive_force = 0.0
		host().spend_rpm(f,0.010,"powers")
		push(f,target,normal*force,"reactive_counter")
		f.vel = (Vector2(f.vel)-normal*force*0.18).limit_length(480.0)
		emit("reactive_counter",f,normal,target,force/100.0)
	_publish(f,s)

func diagnostics(f: Dictionary) -> Dictionary:
	if f.is_empty() or not owns(f): return {}
	# Inspector reads during paused acquisition are pure; an unstarted new
	# mutation has no earned reserve and must not allocate mechanism state.
	var s: Dictionary = states.get(int(f.entity_id),{})
	return {"branches":f.get("power_mutations",{}).duplicate(true),"states":states.size(),"procs":counters.duplicate(),
		"comet_remaining":maxf(0.0,float(s.get("comet_until",0.0))-time),"ricochets":int(s.get("ricochets",0)),
		"bank":float(host().roster.states.get(int(f.entity_id),{}).get("bank",0.0)),"bank_capacity":bank_capacity(f),"commit_remaining":float(f.get("ecology_commit_time",0.0)),
		"orbit_flow":bool(f.get("orbit_flow",false)),"reactive_force":float(s.get("reactive_force",0.0)),"reactive_remaining":maxf(0.0,float(s.get("reactive_until",0.0))-time),
		"damper_remaining":maxf(0.0,float(s.get("damper_until",0.0))-time),"damper_ready_in":maxf(0.0,float(s.get("damper_ready",0.0))-time)}
