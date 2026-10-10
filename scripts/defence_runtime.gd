extends RefCounted
## Three active defence tools. All clocks advance with the fixed Battle tick;
## ownership, reserve costs and physical impulses stay in the canonical runtime.
const IDS: Array[String] = ["gyro_lock", "impact_sink", "anchor_exchange"]
const SINK_TARGET_LIMIT: int = 6
var _parent: WeakRef
var parent: Object:
	get: return _parent.get_ref() if _parent != null else null
var time: float = 0.0
var states: Dictionary = {}
var counters: Dictionary = {}

func setup(runtime: Object) -> void:
	_parent = weakref(runtime)
	time = 0.0
	states.clear()
	counters.clear()
	for f: Dictionary in parent._fighters():
		if not relevant(f): continue
		f["gyro_charge"] = 0.0
		f["sink_charge"] = 0.0
		f["sink_capacity"] = sink_capacity(f) if owns(f, "impact_sink") else 0.0
		f["exchange_charge"] = 0.0
		f["exchange_carry"] = 0.0

func owns(f: Dictionary, id: String) -> bool: return id in f.get("powers", [])
func rank(f: Dictionary, id: String) -> int: return parent.rank(f, id)
func branch(f: Dictionary, id: String) -> String: return parent.mutation(f, id)
func live(f: Dictionary) -> bool: return parent._live(f)
func relevant(f: Dictionary) -> bool:
	for id: String in IDS:
		if owns(f, id): return true
	return false

func state(f: Dictionary) -> Dictionary:
	var id: int = int(f.entity_id)
	if not states.has(id):
		states[id] = {"gyro":0.0, "heading":Vector2.ZERO, "gyro_ready":0.0,
			"sink":0.0, "sink_hit_ready":0.0, "sink_vent_ready":0.0,
			"sink_age":0.0, "braking":false, "brace":0.0, "carry_until":0.0,
			"carry":0.0, "fx_ready":0.0, "active_seconds":0.0,
			"absorbed_force":0.0, "vented_force":0.0, "rpm_recovered":0.0,
			"rpm_spent":0.0, "gyro_breaks":0, "vents":0}
	return states[id]

func event(kind: String, f: Dictionary, direction: Vector2 = Vector2.ZERO, strength: float = 1.0) -> void:
	counters[kind] = int(counters.get(kind, 0)) + 1
	parent._record(kind, int(f.entity_id))
	parent._fx(kind, f.pos, direction, strength, {"owner_entity_id":int(f.entity_id)})

func begin_tick(dt: float) -> void:
	time += dt
	var ids: Dictionary = {}
	for f: Dictionary in parent._fighters():
		if not relevant(f) or not live(f): continue
		ids[int(f.entity_id)] = true
		var s: Dictionary = state(f)
		# A reservoir has no passive recovery. Unspent shock eventually leaks
		# away as heat; it cannot mint another defensive charge or reserve.
		if float(s.sink) > 0.0:
			s.sink_age = float(s.sink_age) + dt
			if float(s.sink_age) > 4.0: s.sink = maxf(0.0, float(s.sink) - dt * 14.0)
		f["sink_charge"] = s.sink
		f["sink_capacity"] = sink_capacity(f)
		f["exchange_carry"] = float(s.carry) * clampf((float(s.carry_until) - time) / 0.35, 0.0, 1.0)
	for id: int in states.keys():
		if not ids.has(id): states.erase(id)

func sink_capacity(f: Dictionary) -> float: return 90.0 if rank(f, "impact_sink") <= 1 else 150.0

func movement(f: Dictionary, m: Dictionary, dt: float) -> void:
	if not relevant(f) or not live(f): return
	var s: Dictionary = state(f)
	var direction: Vector2 = m.direction
	var braking: bool = bool(m.braking)
	var speed: float = Vector2(f.vel).length()
	var bursting: bool = float(f.get("burst_time", 0.0)) > 0.0
	if owns(f, "gyro_lock"):
		var heading: Vector2 = direction.normalized()
		var previous: Vector2 = s.heading
		var rate: float = absf(previous.angle_to(heading)) / maxf(dt, 0.001) if previous.length_squared() > 0.1 and heading.length_squared() > 0.1 else 0.0
		var limit: float = 2.8 if branch(f, "gyro_lock") == "flywheel" else (1.25 if branch(f, "gyro_lock") == "keel" else 1.8)
		var controlled: bool = direction.length() >= 0.25 and speed >= 16.0 and speed <= (260.0 if branch(f, "gyro_lock") == "flywheel" else 205.0) and not braking and not bursting and rate <= limit and time >= float(s.gyro_ready)
		if controlled:
			var old: float = float(s.gyro)
			s.gyro = minf(1.0, old + dt / (1.7 if rank(f, "gyro_lock") == 1 else 1.25))
			if old < 0.70 and float(s.gyro) >= 0.70: event("gyro_lock_set", f, heading)
			s.active_seconds = float(s.active_seconds) + dt
		elif rate > limit * 1.5 or bursting:
			if float(s.gyro) > 0.2: event("gyro_lock_break", f, heading); s.gyro_breaks = int(s.gyro_breaks) + 1
			s.gyro = 0.0
		else: s.gyro = maxf(0.0, float(s.gyro) - dt * 2.0)
		s.heading = heading if direction.length() >= 0.10 else Vector2.ZERO
		f["gyro_charge"] = s.gyro
		if branch(f, "gyro_lock") == "keel" and float(s.gyro) > 0.0:
			m.speed = float(m.speed) * (1.0 - float(s.gyro) * 0.24)
			m.acceleration = float(m.acceleration) * (1.0 - float(s.gyro) * 0.12)
	if owns(f, "impact_sink") and braking and not bool(s.braking) and not bursting and speed <= 120.0 and float(s.sink) >= 15.0 and time >= float(s.sink_vent_ready):
		vent(f)
	if owns(f, "anchor_exchange"):
		var maximum_speed: float = 34.0 if branch(f, "anchor_exchange") == "deep_footing" else 78.0
		var eligible: bool = braking and speed < maximum_speed and float(f.rpm) > 0.08 and not bursting
		if eligible:
			var before: float = float(s.brace)
			s.brace = minf(1.0, before + dt / (0.42 if rank(f, "anchor_exchange") == 1 else 0.30))
			if before < 0.60 and float(s.brace) >= 0.60: event("exchange_set", f)
			var reserve: float = float(f.rpm)
			parent._spend(f, dt * float(s.brace) * (0.010 if branch(f, "anchor_exchange") == "deep_footing" else 0.0055))
			s.rpm_spent = float(s.rpm_spent) + maxf(0.0, reserve - float(f.rpm))
			m.acceleration = float(m.acceleration) * (1.0 - float(s.brace) * 0.72)
			m.speed = float(m.speed) * (1.0 - float(s.brace) * 0.56)
			m.drag = float(m.drag) + float(s.brace) * 2.5
		elif not braking and bool(s.braking):
			if float(s.brace) > 0.20:
				event("exchange_release", f, direction)
				# A charged, paid brace becomes a controlled release. Holding
				# Brake or tapping it without an aimed release cannot cool Stress.
				if direction.length() >= 0.35 and float(s.brace) >= 0.60:
					parent.vent_anchor_stress(f, float(s.brace) * (0.14 if branch(f, "anchor_exchange") == "deep_footing" else 0.10), "anchor_exchange")
				if branch(f, "anchor_exchange") == "slip_anchor":
					s.carry = float(s.brace) * 0.65
					s.carry_until = time + 0.35
			s.brace = 0.0
		else: s.brace = maxf(0.0, float(s.brace) - dt * 4.0)
		f["exchange_charge"] = s.brace
	s.braking = braking

func mass_multiplier(f: Dictionary) -> float:
	if not relevant(f) or not live(f): return 1.0
	var s: Dictionary = state(f)
	var multiplier: float = 1.0
	if owns(f, "gyro_lock"):
		var strength: float = 2.0 if rank(f, "gyro_lock") == 1 else 3.5
		if branch(f, "gyro_lock") == "keel": strength = 6.0
		multiplier *= 1.0 + float(s.gyro) * float(s.gyro) * strength
	if owns(f, "anchor_exchange"):
		var strength: float = 6.0 if rank(f, "anchor_exchange") == 1 else 10.0
		if branch(f, "anchor_exchange") == "deep_footing": strength = 20.0
		var carry: float = float(s.carry) * clampf((float(s.carry_until) - time) / 0.35, 0.0, 1.0)
		multiplier *= 1.0 + maxf(float(s.brace), carry) * strength
	return multiplier

func burst(f: Dictionary) -> void:
	if not relevant(f): return
	var s: Dictionary = state(f)
	if owns(f, "gyro_lock") and float(s.gyro) > 0.15: event("gyro_lock_break", f); s.gyro_breaks = int(s.gyro_breaks) + 1
	s.gyro = 0.0
	s.gyro_ready = time + 0.65
	s.brace = 0.0
	s.carry_until = time
	f["gyro_charge"] = 0.0
	f["exchange_charge"] = 0.0

func contact(f: Dictionary, target: Dictionary, severity: float, recoil: Vector2, incoming_force: float) -> void:
	if not live(f) or not owns(f, "impact_sink") or not parent._opposes(f, target) or parent._small(f): return
	var s: Dictionary = state(f)
	if severity < 0.40 or incoming_force < 55.0 or recoil.length() < 4.0 or time < float(s.sink_hit_ready): return
	var capacity: float = sink_capacity(f)
	var room: float = maxf(0.0, capacity - float(s.sink))
	if room < 4.0: return
	var fraction: float = 0.24 if rank(f, "impact_sink") == 1 else 0.36
	var absorbed: Vector2 = recoil * minf(fraction, room / maxf(0.001, recoil.length()))
	# This cancels only part of the actual incoming velocity change. It does
	# not teleport, refund impact RPM, invoke another collision or undo recoil.
	f.vel = Vector2(f.vel) - absorbed
	s.sink = minf(capacity, float(s.sink) + absorbed.length())
	s.sink_age = 0.0
	s.sink_hit_ready = time + 0.25
	s.absorbed_force = float(s.absorbed_force) + absorbed.length()
	f["sink_charge"] = s.sink
	event("sink_store", f, -recoil.normalized(), float(s.sink) / capacity)

func vent(f: Dictionary) -> void:
	var s: Dictionary = state(f)
	var stored: float = float(s.sink)
	s.sink = 0.0
	s.sink_age = 0.0
	s.sink_vent_ready = time + 1.5
	s.vents = int(s.vents) + 1
	s.vented_force = float(s.vented_force) + stored
	f["sink_charge"] = 0.0
	# The reservoir is emptied once by a fresh Brake edge; only accepted
	# stored force pays for this extra relief, never an empty/held Brake.
	parent.vent_anchor_stress(f, minf(0.24, stored * 0.0016), "impact_sink")
	if branch(f, "impact_sink") == "return_spring":
		var affected: int = 0
		for target: Dictionary in parent._fighters():
			if affected >= SINK_TARGET_LIMIT: break
			if not live(target) or not parent._opposes(f, target) or Vector2(target.pos).distance_to(f.pos) > 64.0: continue
			var heading: Vector2 = parent._outward(f.pos, target.pos, Vector2.RIGHT)
			parent._request(target, heading * minf(95.0, 25.0 + stored * 0.45), parent._owned_effect_cause(f, "return_spring"))
			affected += 1
		parent._spend(f, 0.008)
		event("sink_return", f, Vector2.ZERO, stored / sink_capacity(f))
	else:
		# Only stored accepted force pays for recovery. Nothing happens on an
		# empty Brake; holding Brake cannot repeatedly vent or mint reserve.
		var amount: float = minf(0.045 if branch(f, "impact_sink") == "shock_bleed" else 0.028, stored * (0.00035 if branch(f, "impact_sink") == "shock_bleed" else 0.00022))
		var recovered: float = parent._gain(f, amount, "impact_sink")
		s.rpm_recovered = float(s.rpm_recovered) + recovered
		f.wobble = maxf(0.0, float(f.wobble) - minf(0.35, stored * 0.002))
		event("sink_vent", f, Vector2.ZERO, stored / sink_capacity(f))

func diagnostics(f: Dictionary) -> Dictionary:
	return state(f).duplicate(true) if relevant(f) else {}

func finish() -> void:
	states.clear()
