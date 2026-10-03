extends RefCounted
## Lightweight deterministic population. No parts, full AI, Burst, or stat derivation.
const Seeds = preload("res://scripts/seed_utils.gd")
const PORTS: Array[Vector2] = [Vector2(-143,-38), Vector2(-105,-112), Vector2(-36,-144), Vector2(38,-143), Vector2(112,105), Vector2(144,36), Vector2(36,144), Vector2(-38,143)]
const TELEGRAPH: float = 0.65
const LIFETIME: float = 9.0
const SMALL_RADIUS: float = 5.8
const IMPULSE_CAP: float = 400.0
var battle: Node2D
var enabled: bool = false
var active_cap: int = 12
var cleanup_time: float = 32.0
var schedule: Array[Dictionary] = []
var wave: int = 0
var total_waves: int = 3
var spawned: int = 0
var cancelled: int = 0
var retired: int = 0
var eliminated: int = 0
var peak_active: int = 0
var cleanup_used: bool = false
var contact_budget: float = 0.015
var budget_clock: float = 0.0

func setup(host: Node2D, descriptor: Dictionary) -> void:
	battle = host
	enabled = str(descriptor.get("fixture_type", "")) == "swarm" or (str(descriptor.get("type", "")) == "swarm" and not bool(descriptor.get("fixture", false)))
	schedule.clear()
	wave = 0
	spawned = 0
	cancelled = 0
	retired = 0
	eliminated = 0
	peak_active = 0
	cleanup_used = false
	contact_budget = 0.015
	budget_clock = 0.0
	if not enabled: return
	var parameters: Dictionary = descriptor.get("swarm_parameters", {})
	active_cap = clampi(int(parameters.get("active_cap",12)),1,12)
	cleanup_time = float(parameters.get("cleanup_time",32.0))
	var counts: Array = parameters.get("waves",[6,8,10])
	var times: Array = parameters.get("wave_times",[0.0,9.0,18.0])
	total_waves = counts.size()
	for w: int in range(counts.size()):
		for index: int in range(int(counts[w])):
			schedule.append({"id":schedule.size()+2,"wave":w+1,"due":float(times[w])+float(index)*0.12,"state":"waiting","port":-1,"ready":0.0})

func active_count() -> int:
	var count: int = 0
	for f: Dictionary in battle.fighters:
		if f.combatant_type == "small_top" and str(f.outcome).is_empty(): count += 1
	return count

func begin_tick(dt: float) -> void:
	budget_clock -= dt
	if budget_clock <= 0.0:
		contact_budget = 0.015
		budget_clock += 0.24
	for f: Dictionary in battle._ordered_fighters():
		if f.combatant_type != "small_top": continue
		if not str(f.outcome).is_empty():
			# Retired bodies no longer collide, but keep their final momentum for
			# the short authored breakup instead of freezing a lethal clean hit.
			if float(f.out_time) < 0.34:
				f.pos = Vector2(f.pos)+Vector2(f.vel)*dt*0.6
				f.vel = Vector2(f.vel)*exp(-5.0*dt)
			f.out_time += dt
			continue
		f.age += dt
		f.rpm = maxf(0.0, float(f.rpm) - (0.175 / 8.7) * dt)
		f.energy = f.rpm
		if float(f.age) >= LIFETIME or float(f.rpm) <= 0.045:
			retire(f, "natural_retirement")
	if not enabled: return
	if battle.elapsed >= cleanup_time:
		cleanup_used = true
		for f: Dictionary in battle._ordered_fighters():
			if f.combatant_type == "small_top" and str(f.outcome).is_empty(): retire(f,"cleanup")
		for entry: Dictionary in schedule:
			if entry.state not in ["spawned","cancelled"]:
				entry.state = "cancelled"
				cancelled += 1
		wave = total_waves
		return
	for entry: Dictionary in schedule:
		if entry.state in ["spawned","cancelled"] or battle.elapsed < float(entry.due): continue
		if int(entry.wave) > wave:
			wave = int(entry.wave)
			battle.event_sfx.emit("swarm_wave")
		if battle.elapsed > float(entry.due) + 2.0 + TELEGRAPH:
			entry.state = "cancelled"
			cancelled += 1
			continue
		if active_count() >= active_cap: continue
		if entry.state == "waiting":
			var port: int = safe_port(entry)
			if port < 0: continue
			entry.port = port
			entry.ready = battle.elapsed + TELEGRAPH
			entry.state = "telegraph"
		elif battle.elapsed >= float(entry.ready):
			if not port_safe(int(entry.port), int(entry.id)):
				entry.state = "waiting"
				entry.port = -1
				continue
			add_small(int(entry.id), PORTS[int(entry.port)], int(entry.wave))
			entry.state = "spawned"
			spawned += 1
	peak_active = maxi(peak_active,active_count())

func port_safe(port: int, entry_id: int) -> bool:
	var pos: Vector2 = PORTS[port]
	for f: Dictionary in battle._ordered_fighters():
		if not str(f.outcome).is_empty(): continue
		var clearance: float = 55.0 if str(f.owner_id) == "player" else float(f.radius)+SMALL_RADIUS+9.0
		if pos.distance_to(f.pos) < clearance: return false
	for entry: Dictionary in schedule:
		if int(entry.id) != entry_id and entry.state == "telegraph" and int(entry.port) == port: return false
	return true

func safe_port(entry: Dictionary) -> int:
	var start: int = (int(entry.id)*3+int(battle.seed_value)%PORTS.size())%PORTS.size()
	for offset: int in range(PORTS.size()):
		var port: int = (start+offset)%PORTS.size()
		if port_safe(port,int(entry.id)): return port
	return -1

func add_small(id: int, pos: Vector2, wave_index: int = 1) -> Dictionary:
	if not battle.entity(id).is_empty() or active_count() >= active_cap: return {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Seeds.derive(battle.seed_value,"small_ai:%d" % id)
	var f: Dictionary = {"entity_id":id,"team_id":"hostile","owner_id":"swarm","combatant_type":"small_top",
		"pos":pos,"vel":-pos.normalized()*70.0,"radius":SMALL_RADIUS,"mass":1.8,
		"rpm":0.22,"energy":0.22,"wobble":0.0,"outcome":"","out_time":0.0,"age":0.0,
		"phase":float(id%4),"impact_time":0.0,"impact_strength":0.0,"height":0.0,"height_vel":0.0,
		"ai_clock":float(id%7)*0.047,"ai_direction":-pos.normalized(),"impulse_time":0.0,
		"wave":wave_index,"powers":[],"name":"AMMUNITION","cooldown":0.0,"burst_time":0.0}
	battle._ai_rngs[id] = rng
	battle.fighters.append(f)
	return f

func decide(f: Dictionary, dt: float) -> void:
	f.ai_clock -= dt
	if float(f.ai_clock) > 0.0: return
	var rng: RandomNumberGenerator = battle._ai_rngs[int(f.entity_id)]
	f.ai_clock = rng.randf_range(0.25,0.35)
	var player: Dictionary = battle.player_entity()
	if player.is_empty(): return
	# Sample present position only; imperfect aim is retained until the next decision.
	var offset: Vector2 = Vector2(rng.randf_range(-16,16),rng.randf_range(-16,16))
	f.ai_direction = (Vector2(player.pos)+offset-Vector2(f.pos)).normalized()

func move(f: Dictionary, dt: float) -> void:
	var thrown: bool = float(f.impulse_time) > 0.0
	var velocity: Vector2 = f.vel
	velocity += Vector2(f.ai_direction) * (28.0 if thrown else 150.0) * dt
	velocity *= exp(-(0.65 if thrown else 0.9)*dt)
	f.vel = velocity.limit_length(IMPULSE_CAP if thrown else 118.0)
	f.pos = Vector2(f.pos)+Vector2(f.vel)*dt
	f.impulse_time = maxf(0.0,float(f.impulse_time)-dt)
	f.impact_time = maxf(0.0,float(f.impact_time)-dt)
	f.phase = fmod(float(f.phase)+dt*(8.0+float(f.rpm)*28.0),4.0)

func retire(f: Dictionary, reason: String) -> void:
	if not str(f.outcome).is_empty(): return
	f.outcome = reason
	f.out_time = 0.0
	if reason in ["natural_retirement","cleanup"]: retired += 1
	else: eliminated += 1
	battle.powers.eliminated(f,reason)

func account_outcomes() -> void:
	for f: Dictionary in battle._ordered_fighters():
		if f.combatant_type != "small_top": continue
		if f.outcome == "ring_out" and not bool(f.get("accounted",false)):
			f.accounted = true
			eliminated += 1
			battle.powers.eliminated(f,"ring_out")
		elif str(f.outcome).is_empty() and float(f.rpm) <= 0.045:
			retire(f,"impact")

func clear() -> bool:
	return enabled and wave == total_waves and spawned+cancelled == schedule.size() and active_count() == 0

func telemetry() -> Dictionary:
	return {"wave":wave,"total_waves":total_waves,"active":active_count(),"scheduled":schedule.size(),"spawned":spawned,
		"cancelled":cancelled,"retired":retired,"eliminated":eliminated,"remaining":schedule.size()-spawned-cancelled,
		"peak_active":peak_active,"cleanup_used":cleanup_used}
