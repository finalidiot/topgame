extends RefCounted
## Live event ownership/admission. The independent director chooses pressure.
const Director = preload("res://scripts/threat_director.gd")
const Roles = preload("res://scripts/enemy_roles.gd")
const Encounters = preload("res://scripts/encounters.gd")
const SpinEconomy = preload("res://scripts/spin_economy.gd")
const TUNING: Dictionary = {"corpse_seconds":0.65}
var economy = SpinEconomy.new()
const ENTRY_POINTS: Array[Vector2] = [Vector2(115,30), Vector2(-115,-30), Vector2(30,115), Vector2(-30,-115)]
var _host: WeakRef
var run_seed: int = 0
var threat_number: int = 1
var threat_started_at: float = 0.0
var phase: String = "active"
var next_at: float = 0.0
var next_entity_id: int = 3
var threats_cleared: int = 0
var rivals_defeated: int = 0
var small_enemies_defeated: int = 0
var _counted: Dictionary = {}
var progression_level: int = 1
var director = Director.new()
var events: Dictionary = {}
var pending: Dictionary = {}
var callout: String = ""
var callout_until: float = 0.0
var elites_defeated: int = 0
var bosses_defeated: int = 0
var last_entry: Dictionary = {}
var last_clear: Dictionary = {}

func setup(host: Node2D, seed_value: int) -> void:
	_host = weakref(host)
	economy.setup(host)
	run_seed = seed_value
	threat_number = int(host.encounter.slot)
	director.setup(seed_value)
	var opening: Dictionary = Director.EVENTS[0].duplicate(true)
	opening["serial"] = 1
	Roles.configure(host.entity(2),opening)
	events[1] = {"ids":[2],"swarm":false,"kind":"rival","key":"hunter","time":0.0}
	# First threat reserves the IDs already admitted by begin_encounter.
	for f: Dictionary in host.fighters: next_entity_id = maxi(next_entity_id, int(f.entity_id) + 1)
	for entry: Dictionary in host.swarm.schedule: next_entity_id = maxi(next_entity_id, int(entry.id) + 1)

func host() -> Node2D:
	return _host.get_ref()

func threat_elapsed() -> float:
	return maxf(0.0, host().elapsed - threat_started_at)

func observe_outcomes() -> void:
	if host().continuous != self: return
	for f: Dictionary in host().fighters:
		if f.team_id != "hostile" or str(f.outcome).is_empty() or _counted.has(int(f.entity_id)): continue
		_counted[int(f.entity_id)] = true
		if f.outcome in ["ring_out", "spin_out", "impact"]:
			if f.combatant_type == "full_top":
				rivals_defeated += 1
				if f.get("enemy_kind", "") == "elite": elites_defeated += 1
				if f.get("enemy_kind", "") == "boss":
					bosses_defeated += 1
					host().add_power_fx("boss_defeat",f.pos,f.vel)
			elif str(host().powers.cause_for(f).get("owner_id", "")) == "player": small_enemies_defeated += 1

func census() -> Dictionary:
	var c: Dictionary = {"pressure":0.0,"full":0,"small":0,"elites":0,"bosses":0,"total":1,"swarm":false}
	for f: Dictionary in host().fighters:
		if f.team_id != "hostile" or not str(f.outcome).is_empty(): continue
		if f.combatant_type == "small_top": c.small += 1
		else:
			c.full += 1
			c.pressure += float(f.get("pressure_cost",2.6))
			if f.get("enemy_kind","") == "elite": c.elites += 1
			if f.get("enemy_kind","") == "boss": c.bosses += 1
	c.swarm = host().swarm.enabled
	# Reserve the peak of scheduled waves, not merely their currently live bodies.
	var reserved_small: int = host().swarm.active_cap if c.swarm else int(c.small)
	c.pressure += float(reserved_small)*0.5
	c.total += int(c.full)+reserved_small
	c["active_full"] = c.full
	c["active_total"] = 1+int(c.full)+int(c.small)
	if not pending.is_empty():
		c.pressure += float(pending.cost)
		if pending.kind == "swarm":
			c.swarm = true
			c.total += int(pending.small_cap)
		else:
			c.full += 1
			c.total += 1
			if pending.kind == "elite": c.elites += 1
			if pending.kind == "boss": c.bosses += 1
	return c

func after_tick(dt: float) -> void:
	var b: Node2D = host()
	if b.paused or b.battle_status != "battle" or b.continuous != self: return
	observe_outcomes()
	for serial: int in events.keys():
		var event: Dictionary = events[serial]
		var resolved: bool = b.swarm.clear() if event.swarm else true
		for id: int in event.ids:
			var f: Dictionary = b.entity(id)
			if not f.is_empty() and str(f.outcome).is_empty(): resolved = false
		if not resolved: continue
		events.erase(serial)
		if event.swarm: b.swarm.enabled = false
		threats_cleared += 1
		director.cleared(serial,b.elapsed,events.is_empty() and pending.is_empty())
		last_clear = {"run_seed":run_seed,"threat":serial,"kind":event.kind,"key":event.key,"duration":b.elapsed-float(event.time)}
		if event.kind == "boss":
			callout = "BOSS TOPPLED"
			callout_until = b.elapsed+2.5
			b.event_sfx.emit("boss_payoff")
		b.threat_cleared.emit(last_clear.duplicate(true))
	_cleanup(dt)
	phase = "breathing" if events.is_empty() and pending.is_empty() else "active"
	next_at = maxf(director.calm_until,director.next_decision)
	if not pending.is_empty():
		if b.elapsed >= float(pending.ready_at): _admit_pending()
		return
	var event: Dictionary = director.decide(b.elapsed,census(),progression_level)
	if event.is_empty(): return
	pending = event
	pending["ready_at"] = b.elapsed+float(event.warning)
	pending["position"] = _safe_entry()
	if event.kind == "boss":
		callout = "INCOMING: "+str(event.name)
		callout_until = float(pending.ready_at)+2.5
		b.event_sfx.emit("boss_warning")
	elif event.kind == "elite":
		callout = str(event.name)
		callout_until = float(pending.ready_at)+1.8

func _safe_entry() -> Vector2:
	var best: Vector2 = Vector2.INF
	var distance: float = -1.0
	for point: Vector2 in ENTRY_POINTS:
		var score: float = point.distance_to(host().player_entity().pos)
		if score < 60.0: continue
		for f: Dictionary in host().fighters:
			if not str(f.outcome).is_empty(): continue
			if point.distance_to(f.pos) < float(f.radius)+30.0: score = -1.0; break
		if score > distance: distance = score; best = point
	return best

func _admit_pending() -> bool:
	var b: Node2D = host()
	if pending.is_empty() or b.continuous != self or b.battle_status != "battle" or b.paused: return false
	var position: Vector2 = pending.position
	# Recheck a moving arena after the warning. Unsafe ports wait; never teleport bodies.
	if pending.kind != "swarm":
		var safe: bool = position.is_finite() and position.distance_to(b.player_entity().pos) >= 60.0
		for f: Dictionary in b.fighters:
			if str(f.outcome).is_empty() and position.distance_to(f.pos) < float(f.radius)+30.0: safe = false
		if not safe:
			pending.position = _safe_entry()
			pending.ready_at = b.elapsed+0.65
			return false
	var event: Dictionary = pending.duplicate(true)
	pending.clear()
	_admit(event,position)
	return true

func _admit(event: Dictionary, position: Vector2, fixture_descriptor: Dictionary = {}) -> void:
	var b: Node2D = host()
	if b.continuous != self or b.battle_status != "battle" or b.paused: return
	threat_number += 1
	threat_started_at = b.elapsed
	var descriptor: Dictionary = Encounters.for_run_event(threat_number,run_seed) if fixture_descriptor.is_empty() else fixture_descriptor
	if fixture_descriptor.is_empty():
		descriptor.fixture_type = "swarm" if event.kind == "swarm" else "duel"
		descriptor.type = str(event.kind)
		descriptor.name = event.name
		descriptor.behavior_profile = event.role
		descriptor.opponent_build = Roles.BUILDS.get(event.role,Roles.BUILDS.hunter).duplicate(true)
		descriptor.swarm_parameters = {"waves":[6,8,10],"wave_times":[0.0,9.0,18.0],"active_cap":int(event.get("small_cap",10)),"cleanup_time":32.0} if event.kind == "swarm" else {}
	descriptor["first_entity_id"] = next_entity_id
	descriptor["director_event"] = event
	var ids: Array[int] = []
	var count: int = 24 if descriptor.fixture_type == "swarm" else 1
	for offset: int in range(count): ids.append(next_entity_id+offset)
	next_entity_id += count
	phase = "active"
	b.enter_threat(descriptor,position)
	if event.kind in ["boss","elite"]: b.add_power_fx(str(event.kind)+"_entry",position)
	events[int(event.serial)] = {"ids":ids,"swarm":descriptor.fixture_type == "swarm","kind":event.kind,"key":event.key,"time":b.elapsed}
	last_entry = {"id":descriptor.id,"seed":descriptor.seed,"run_seed":run_seed,"threat":threat_number,"kind":event.kind,"key":event.key}
	b.threat_started.emit(last_entry.duplicate(true))

func _spawn_next() -> void:
	# Explicit QA fixture seam used by legacy menu/controller tests and --smoke-test.
	# Production pacing calls only Director.decide -> warning -> _admit_pending.
	if not pending.is_empty():
		director.active.erase(int(pending.serial))
		pending.clear()
	var descriptor: Dictionary = Encounters.for_slot(threat_number+1,run_seed)
	var event: Dictionary = Director.EVENTS[0].duplicate(true)
	event.kind = "swarm" if descriptor.fixture_type == "swarm" else "rival"
	event["serial"] = threat_number+1
	event["small_cap"] = 12
	director.serial = int(event.serial)
	director.active[int(event.serial)] = {"time":host().elapsed,"kind":event.kind}
	director.next_decision = host().elapsed+12.0
	_admit(event,_safe_entry(),descriptor)

func _cleanup(dt: float) -> void:
	var b: Node2D = host()
	var retired: Array[int] = []
	for f: Dictionary in b.fighters:
		if f.team_id != "hostile" or str(f.outcome).is_empty(): continue
		if f.combatant_type == "full_top":
			f.out_time += dt
			f.pos = Vector2(f.pos) + Vector2(f.vel) * dt * 0.6
			f.vel = Vector2(f.vel) * exp(-5.0 * dt)
		if float(f.out_time) >= float(TUNING.corpse_seconds): retired.append(int(f.entity_id))
	for id: int in retired:
		b.remove_retired_enemy(id)
		_counted.erase(id)
	b.powers.prune_retired_state()

func snapshot() -> Dictionary:
	return {"run_seed":run_seed, "survival_time":host().elapsed, "threat_number":threat_number,
		"phase":phase, "threats_cleared":threats_cleared, "rivals_defeated":rivals_defeated,
		"small_enemies_defeated":small_enemies_defeated, "next_at":next_at,
		"next_entity_id":next_entity_id, "threat_started_at":threat_started_at,
		"director":true,"limits":Director.limits(host().elapsed,progression_level),
		"census":census(),"calm":director.draining or host().elapsed < director.calm_until,
		"callout":callout if host().elapsed < callout_until else "",
		"elites_defeated":elites_defeated,"bosses_defeated":bosses_defeated}
