extends RefCounted
## Physical build tools. State belongs to one live top and advances only during
## battle ticks. The original parts and the Threat Director are never modified.
const SPEED_CLAMP: float = 480.0
var _host: WeakRef
var time: float = 0.0
var states: Dictionary = {}
var counters: Dictionary = {}

func setup(battle: Object) -> void:
	_host = weakref(battle)
	time = 0.0
	states.clear()
	counters.clear()

func host() -> Object: return _host.get_ref()
func has(f: Dictionary, id: String) -> bool: return id in f.get("powers", [])
func rank(f: Dictionary, id: String) -> int:
	return clampi(int(f.get("power_ranks", {}).get(id, 1)), 1, 3) if has(f,id) else 0
func branch(f: Dictionary, id: String) -> String:
	return str(f.get("power_mutations", {}).get(id, "")) if rank(f,id) == 3 else ""
func live(f: Dictionary) -> bool: return not f.is_empty() and str(f.get("outcome", "")).is_empty()
func state(f: Dictionary) -> Dictionary:
	var id: int = int(f.entity_id)
	if not states.has(id):
		states[id] = {"orbit":0.0,"turn_sign":0.0,"heading":Vector2(f.vel).normalized(),
			"guard_until":0.0,"guard_ready":0.0,"bank":0.0,"bank_fx":0.0,
			"hunt_target":0,"hunt_stacks":0,"hunt_until":0.0,"hunt_ready":0.0,
			"cross_ready":0.0,"input":Vector2.ZERO,"braking":false,"drift":false,
			"peak_speed":0.0,"distance":0.0,"drift_seconds":0.0,"orbit_seconds":0.0,
			"speed_samples":0,"speed_sum":0.0}
	return states[id]
func event(kind: String, f: Dictionary, direction: Vector2 = Vector2.ZERO, strength: float = 1.0) -> void:
	counters[kind] = int(counters.get(kind,0))+1
	host().add_power_fx(kind,f.pos,direction,strength)

func begin_tick(dt: float) -> void:
	time += dt
	var ids: Dictionary = {}
	for f: Dictionary in host()._ordered_fighters():
		ids[int(f.entity_id)] = true
		if not live(f): continue
		var s: Dictionary = state(f)
		s.bank = maxf(0.0,float(s.bank)-dt*7.0)
		if time > float(s.hunt_until): s.hunt_stacks = 0; s.hunt_target = 0
		f["guard_time"] = maxf(0.0,float(s.guard_until)-time)
		f["momentum_charge"] = s.bank
		f["hunt_stacks"] = s.hunt_stacks
		f["hunt_target"] = s.hunt_target
	for id: int in states.keys():
		if not ids.has(id): states.erase(id)

func movement(f: Dictionary, m: Dictionary, dt: float) -> Dictionary:
	if not live(f): return m
	var s: Dictionary = state(f)
	var direction: Vector2 = m.direction
	var braking: bool = bool(m.braking)
	var velocity: Vector2 = f.vel
	var speed: float = velocity.length()
	s.input = direction
	s.braking = braking
	s.drift = false
	var gear: int = rank(f,"high_gear")
	if gear > 0:
		var mutation: String = branch(f,"high_gear")
		var accel: float = 1.35 if gear == 1 else 1.55
		var ceiling: float = 1.27 if gear == 1 else 1.46
		if gear >= 2 and speed > 110.0 and direction.length() > 0.2 and absf(velocity.normalized().angle_to(direction.normalized())) < 1.2:
			m.drag = float(m.drag)-0.10
		if mutation == "terminal_velocity":
			accel = 1.95; ceiling = 1.82
			if speed > 90.0 and direction.length() > 0.2:
				var turn: float = absf(velocity.normalized().angle_to(direction.normalized()))
				host().spend_rpm(f, maxf(0.0,turn-0.50)*speed/230.0*0.0040*dt,"steering")
			if braking: host().spend_rpm(f,0.006*speed/230.0*dt,"braking")
		elif mutation == "flow_state":
			accel = 1.52; ceiling = 1.49
			m.drag = float(m.drag)-0.30
			if speed > 110.0 and direction.length() > 0.25 and not braking:
				m.drain = float(m.drain)*0.70
				# Steering changes the curve without deleting carried velocity.
				direction = velocity.normalized().lerp(direction.normalized(),0.68)*direction.length()
		m.acceleration = float(m.acceleration)*accel
		m.speed = float(m.speed)*ceiling
		m.acceleration_limit = maxf(float(m.acceleration_limit),430.0 if gear == 1 else 580.0)
		m.direction = direction
	if has(f,"orbit_drive"):
		var turn: float = velocity.normalized().angle_to(direction.normalized()) if speed > 1.0 and direction.length() > 0.1 else 0.0
		# Brake + lateral steering carves a slide. Forward inertia remains;
		# there is no auto-orbit or automatic correction away from the gates.
		s.drift = braking and speed >= 80.0 and absf(turn) >= 0.12 and absf(turn) < 2.25 and float(f.rpm) > 0.13
		m["brake_drag_scale"] = 0.08 if s.drift else 1.0
		if s.drift:
			m.acceleration = float(m.acceleration)*0.85
			m.drag = float(m.drag)-0.20
		var charge: float = float(s.orbit)
		m.speed = float(m.speed)*(1.0+charge*(0.12 if rank(f,"orbit_drive") == 1 else 0.20))
		m.acceleration = float(m.acceleration)*(1.0+charge*0.22)
		if speed > 80.0 and direction.length() > 0.2:
			m.drain = float(m.drain)*(1.0-charge*(0.20 if rank(f,"orbit_drive") == 1 else 0.32))
		f["orbit_charge"] = charge
		f["drift_active"] = s.drift
	if int(s.hunt_stacks) > 0 and has(f,"predator_line"):
		var target: Dictionary = host().entity(int(s.hunt_target))
		if live(target) and direction.length() > 0.2:
			var approach: Vector2 = (Vector2(target.pos)-Vector2(f.pos)).normalized()
			if direction.normalized().dot(approach) > 0.65 and Vector2(target.pos).distance_to(f.pos) < 160.0:
				m.acceleration = float(m.acceleration)*(1.0+float(s.hunt_stacks)*0.10)
	return m

func velocity(f: Dictionary, before: Vector2, after: Vector2, dt: float) -> Vector2:
	var s: Dictionary = state(f)
	var direction: Vector2 = s.input
	if has(f,"orbit_drive") and bool(s.drift) and after.length() > 30.0:
		var turn: float = after.normalized().angle_to(direction.normalized())
		var carving: float = clampf(turn,-1.10,1.10)*dt*(1.40 if rank(f,"orbit_drive") >= 2 else 1.10)
		after = after.rotated(carving)
		if float(s.orbit) < 0.05: event("orbit_drift",f,after.normalized())
	var heading: Vector2 = after.normalized()
	var previous: Vector2 = s.heading
	if has(f,"orbit_drive"):
		var turn: float = previous.angle_to(heading) if previous.length_squared() > 0.1 else 0.0
		var rate: float = absf(turn)/maxf(0.001,dt)
		var sign_turn: float = signf(turn)
		var flowing: bool = after.length() > 80.0 and direction.length() > 0.20 and rate >= 0.12 and rate <= 3.5
		if flowing:
			if float(s.turn_sign) != 0.0 and sign_turn != float(s.turn_sign): s.orbit = maxf(0.0,float(s.orbit)-0.65)
			s.turn_sign = sign_turn
			s.orbit = minf(1.0,float(s.orbit)+dt*(0.72 if s.drift else 0.42))
		else: s.orbit = maxf(0.0,float(s.orbit)-dt*0.75)
		if direction.length() > 0.1 and heading.dot(direction.normalized()) < -0.5: s.orbit = 0.0
		f["orbit_charge"] = s.orbit
		s.drift_seconds = float(s.drift_seconds)+(dt if s.drift else 0.0)
		s.orbit_seconds = float(s.orbit_seconds)+(dt if float(s.orbit) >= 0.50 else 0.0)
	if has(f,"momentum_bank") and bool(s.braking) and not bool(s.drift) and before.length() > 75.0 and float(f.rpm) > 0.13 and direction.length() > 0.08:
		var lost: float = maxf(0.0,before.length()-after.length())
		var cap: float = 95.0 if rank(f,"momentum_bank") == 1 else 150.0
		s.bank = minf(cap,float(s.bank)+lost*(0.62 if rank(f,"momentum_bank") == 1 else 0.85))
		f["momentum_charge"] = s.bank
		if lost > 0.2 and time >= float(s.bank_fx):
			s.bank_fx = time+0.6
			event("momentum_store",f,before.normalized(),float(s.bank)/cap)
	s.heading = heading
	if has(f,"high_gear") or has(f,"orbit_drive") or host().get("continuous") != null or host().get("ability_rebalance") == true: after = after.limit_length(SPEED_CLAMP)
	s.peak_speed = maxf(float(s.peak_speed),after.length())
	s.distance = float(s.distance)+after.length()*dt
	s.speed_sum = float(s.speed_sum)+after.length()
	s.speed_samples = int(s.speed_samples)+1
	return after.limit_length(SPEED_CLAMP) if has(f,"high_gear") or has(f,"orbit_drive") else after

func burst(f: Dictionary, heading: Vector2) -> void:
	var s: Dictionary = state(f)
	if has(f,"momentum_bank") and float(s.bank) >= 15.0:
		var bank: float = float(s.bank)
		s.bank = 0.0; f["momentum_charge"] = 0.0
		host().spend_rpm(f,0.009+bank*0.000065,"powers")
		f.vel = (Vector2(f.vel)+heading*bank).limit_length(SPEED_CLAMP)
		f.impulse_time = maxf(float(f.get("impulse_time",0.0)),0.45)
		event("momentum_release",f,heading,bank/150.0)
	if branch(f,"high_gear") == "terminal_velocity": event("high_gear_surge",f,heading)

func collision_cost(f: Dictionary) -> float:
	if has(f,"crash_guard") and time < float(state(f).guard_until):
		return 0.68 if rank(f,"crash_guard") == 1 else 0.48
	return 1.0

func attack_multiplier(f: Dictionary, target: Dictionary) -> float:
	if not has(f,"predator_line"): return 1.0
	var s: Dictionary = state(f)
	return 1.0+float(s.hunt_stacks)*(0.10 if rank(f,"predator_line") == 1 else 0.16) if int(target.entity_id) == int(s.hunt_target) and time <= float(s.hunt_until) else 1.0

func contact(first: Dictionary, second: Dictionary, severity: float, normal: Vector2, velocity_first: Vector2, velocity_second: Vector2) -> void:
	_contact(first,second,severity,normal,velocity_first)
	_contact(second,first,severity,-normal,velocity_second)
func _contact(f: Dictionary, target: Dictionary, severity: float, normal: Vector2, incoming: Vector2) -> void:
	if not live(f) or not live(target) or f.team_id == target.team_id or f.combatant_type == "small_top": return
	var s: Dictionary = state(f)
	if has(f,"crash_guard") and severity >= 0.45 and time >= float(s.guard_ready):
		s.guard_ready = time+3.0
		s.guard_until = time+(1.15 if rank(f,"crash_guard") == 1 else 1.65)
		f["guard_time"] = float(s.guard_until)-time
		event("crash_guard",f,-normal,severity)
	if has(f,"predator_line") and target.combatant_type == "full_top" and severity >= 0.32 and incoming.dot(normal) >= 25.0 and time >= float(s.hunt_ready):
		s.hunt_ready = time+0.65
		s.hunt_stacks = mini(3,int(s.hunt_stacks)+1) if int(s.hunt_target) == int(target.entity_id) else 1
		s.hunt_target = int(target.entity_id)
		s.hunt_until = time+(4.5 if rank(f,"predator_line") == 1 else 6.0)
		f["hunt_stacks"] = s.hunt_stacks; f["hunt_target"] = s.hunt_target
		event("predator_lock",f,normal,float(s.hunt_stacks)/3.0)
	if has(f,"crosscut") and severity >= 0.22 and incoming.length() >= 70.0 and time >= float(s.cross_ready):
		var tangent: Vector2 = Vector2(-normal.y,normal.x)
		var lateral_input: float = Vector2(s.input).dot(tangent)
		if absf(lateral_input) >= 0.25 and float(f.rpm) > 0.08:
			s.cross_ready = time+(1.25 if rank(f,"crosscut") == 1 else 0.85)
			host().spend_rpm(f,0.008 if rank(f,"crosscut") == 1 else 0.012,"powers")
			var cut: Vector2 = tangent*signf(lateral_input)*(38.0 if rank(f,"crosscut") == 1 else 62.0)
			host().apply_power_impulse(target,cut,host().powers._owned_effect_cause(f,"crosscut"))
			f.vel = (Vector2(f.vel)-cut*0.25).limit_length(SPEED_CLAMP)
			event("crosscut",f,cut.normalized())

func diagnostics(f: Dictionary) -> Dictionary:
	var s: Dictionary = state(f)
	return {"peak_speed":s.peak_speed,"mean_speed":float(s.speed_sum)/maxi(1,int(s.speed_samples)),"distance":s.distance,"drift_seconds":s.drift_seconds,"orbit_seconds":s.orbit_seconds,"procs":counters.duplicate(),"states":states.size()}
