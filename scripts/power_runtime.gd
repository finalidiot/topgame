extends RefCounted
class_name PowerRuntime

const PowerCatalog = preload("res://scripts/run_powers.gd")

## Semantic hooks are called explicitly by battle's fixed tick; presentation
## never feeds back into this runtime. Requests cannot recursively emit contacts.
const WAKE_RADIUS: float = 52.0
const CHAIN_RADIUS: float = 42.0
const CAUSE_SECONDS: float = 1.0
const MAX_CHAIN_GENERATION: int = 2
const MAX_CHAIN_PULSES: int = 12
const MAX_TRACES: int = 3
const TRACE_SECONDS: float = 0.45
const MAX_ESCALATED_TRACES: int = 28
const MAX_ALL_TRACES: int = 72
const MUTATIONS: Dictionary = PowerCatalog.MUTATION_BRANCHES

var traces: Array[Dictionary] = []
var events: Array[Dictionary] = []
var counters: Dictionary = {}
var time: float = 0.0
var _battle: WeakRef
var _states: Dictionary = {}
var _next_event_id: int = 0
var _requests: Array[Dictionary] = []
var _eliminations: Array[Dictionary] = []
var _next_tick_pulses: Array[Dictionary] = []
var _chain_counts: Dictionary = {}
var _eliminated_ids: Dictionary = {}
var _stopped: bool = false

func setup(battle: Object) -> void:
	_battle = weakref(battle)
	time = 0.0
	_next_event_id = 0
	_stopped = false
	_states.clear()
	traces.clear()
	events.clear()
	counters.clear()
	_requests.clear()
	_eliminations.clear()
	_next_tick_pulses.clear()
	_chain_counts.clear()
	_eliminated_ids.clear()
	for fighter: Dictionary in _fighters():
		_state(fighter)
		fighter["redline_time"] = 0.0
		fighter["iron_comet_time"] = 0.0
		fighter["comet_time"] = 0.0
		fighter["second_wind_used"] = false
		fighter["player_cause"] = {}
		fighter["anchor_charge"] = 0.0
		fighter["stored_force"] = 0.0
		fighter["runaway_heat"] = 0.0
		fighter["slipstream_time"] = 0.0
		fighter["redline_heading"] = Vector2.ZERO
		fighter["redline_active_rank"] = 0
		fighter["redline_active_mutation"] = ""

func _host() -> Object:
	return _battle.get_ref() if _battle != null else null

func _fighters() -> Array[Dictionary]:
	if _host() == null:
		return []
	return _host()._ordered_fighters()

func _state(fighter: Dictionary) -> Dictionary:
	var id: int = int(fighter["entity_id"])
	if not _states.has(id):
		_states[id] = {"wake_ready": 0.0, "comet_until": 0.0, "comet_ready": 0.0,
			"redline_until": 0.0, "redline_heading": Vector2.ZERO, "redline_hit": false,
			"redline_rank": 1, "redline_mutation": "",
			"second_wind_used": false, "chain_until": 0.0, "chain_ready": 0.0,
			"chain_target": 0, "chain_cause": {}, "trace_ready": 0.0,
			"trace_origin": Vector2(fighter["pos"]), "trace_path": [Vector2(fighter["pos"])], "trace_hits": {},
			"runaway_ready": 0.0, "breakneck_recovered": false,
			"anchor_announced": false, "anchor_fx_ready": 0.0, "anchor_lockout": 0.0,
			"slip_until": 0.0, "slip_ready": 0.0, "slip_inside": false,
			"circuit_ready": 0.0, "circuit_after": -1.0,
			"last_primary_cause": {}}
	return _states[id]

func _has(fighter: Dictionary, power: String) -> bool:
	return power in fighter.get("powers", [])

func rank(fighter: Dictionary, power: String) -> int:
	return clampi(int(fighter.get("power_ranks", {}).get(power, 1)), 1, 3) if _has(fighter, power) else 0

func mutation(fighter: Dictionary, power: String) -> String:
	var branch: String = str(fighter.get("power_mutations", {}).get(power, ""))
	return branch if rank(fighter, power) == 3 and branch in MUTATIONS.get(power, []) else ""

func _live(fighter: Dictionary) -> bool:
	return not fighter.is_empty() and str(fighter.get("outcome", "")).is_empty()

func _opposes(first: Dictionary, second: Dictionary) -> bool:
	return str(first.get("team_id", "neutral")) != str(second.get("team_id", "neutral")) and str(first.get("team_id", "neutral")) != "neutral" and str(second.get("team_id", "neutral")) != "neutral"

func _small(fighter: Dictionary) -> bool:
	return str(fighter.get("combatant_type", "")) == "small_top"

func _event() -> int:
	_next_event_id += 1
	return _next_event_id

func _record(kind: String, owner: int, target: int = 0, root: int = 0, generation: int = 0) -> void:
	counters[kind] = int(counters.get(kind, 0)) + 1
	events.append({"kind": kind, "time": time, "owner": owner, "target": target, "root": root, "generation": generation})
	# Useful diagnostics have a fixed memory budget, independent of effects quality.
	if events.size() > 256:
		events.pop_front()

func _fx(kind: String, position: Vector2, direction: Vector2 = Vector2.RIGHT, strength: float = 1.0) -> void:
	if _host() != null and not _stopped:
		_host().add_power_fx(kind, position, direction, strength)

func begin_tick(dt: float) -> void:
	if _stopped:
		return
	time += dt
	for fighter: Dictionary in _fighters():
		var state: Dictionary = _state(fighter)
		var was_redline: bool = float(fighter.get("redline_time", 0.0)) > 0.0
		fighter["redline_time"] = maxf(0.0, float(state["redline_until"]) - time)
		fighter["iron_comet_time"] = maxf(0.0, float(state["comet_until"]) - time)
		fighter["comet_time"] = fighter["iron_comet_time"]
		fighter["slipstream_time"] = maxf(0.0, float(state["slip_until"]) - time)
		if was_redline and float(fighter["redline_time"]) <= 0.0 and _live(fighter):
			_end_redline(fighter)
		if _live(fighter) and redline_active(fighter) and active_redline_rank(fighter) >= 2:
			var heat: float = float(fighter.get("runaway_heat", 0.0))
			var drain: float = 0.028 + heat * 0.048
			if _run_player(fighter): drain = float(_host().continuous.economy.TUNING.redline_drain)+heat*float(_host().continuous.economy.TUNING.redline_heat)
			_spend(fighter,drain*dt)
			fighter["energy"] = fighter["rpm"]
			fighter["wobble"] = minf(1.0, float(fighter["wobble"]) + (0.075 + heat * 0.13) * dt)
			if float(fighter["rpm"]) < 0.13:
				state["redline_until"] = time
				fighter["redline_time"] = 0.0
				_end_redline(fighter)
	for index: int in range(traces.size() - 1, -1, -1):
		traces[index]["life"] = maxf(0.0, float(traces[index]["expires_at"]) - time)
		if float(traces[index]["life"]) <= 0.0:
			traces.remove_at(index)
	var pulses: Array[Dictionary] = _next_tick_pulses.duplicate(true)
	_next_tick_pulses.clear()
	for pulse: Dictionary in pulses:
		_apply_pulse(pulse)
	flush_contact_powers()

func redline_active(fighter: Dictionary) -> bool:
	return not _stopped and float(_state(fighter)["redline_until"]) > time

## Investment updates ownership immediately. An overload already in progress
## retains its paid activation profile until expiry; the next Burst reads the
## new rank/branch without resetting existing timers, contacts or one-shots.
func active_redline_rank(fighter: Dictionary) -> int:
	return int(_state(fighter)["redline_rank"])

func active_redline_mutation(fighter: Dictionary) -> String:
	return str(_state(fighter)["redline_mutation"])

func effective_rpm(fighter: Dictionary) -> float:
	var reserve: float = float(fighter["rpm"])
	if not redline_active(fighter): return reserve
	if active_redline_rank(fighter) == 1: return minf(1.15, reserve + 0.35)
	if active_redline_mutation(fighter) == "breakneck": return minf(1.65, reserve + 0.85)
	return minf(1.45 + float(fighter.get("runaway_heat", 0.0)) * 0.25, reserve + 0.55)

func attack_multiplier(fighter: Dictionary) -> float:
	if not redline_active(fighter) or active_redline_rank(fighter) <= 1: return 1.0
	match active_redline_mutation(fighter):
		"breakneck": return 2.4 if not bool(_state(fighter)["redline_hit"]) else 1.0
		"runaway": return 1.25 + float(fighter.get("runaway_heat", 0.0)) * 0.85
	return 1.35

func _end_redline(fighter: Dictionary) -> void:
	var state: Dictionary = _state(fighter)
	var release_fx: String = "breakneck_recovery" if active_redline_mutation(fighter) == "breakneck" else "redline_release"
	if active_redline_mutation(fighter) == "breakneck" and not bool(state["breakneck_recovered"]):
		state["breakneck_recovered"] = true
		fighter["wobble"] = minf(1.0, float(fighter["wobble"]) + 0.32)
		_spend(fighter,0.025)
		fighter["energy"] = fighter["rpm"]
		fighter["vel"] = Vector2(fighter["vel"]) * 0.72
		fighter["burst_time"] = 0.0
	elif active_redline_mutation(fighter) == "runaway":
		fighter["wobble"] = minf(1.0, float(fighter["wobble"]) + float(fighter.get("runaway_heat", 0.0)) * 0.20)
	fighter["runaway_heat"] = 0.0
	fighter["redline_active_rank"] = 0
	fighter["redline_active_mutation"] = ""
	_fx(release_fx, fighter["pos"], state["redline_heading"])

## Called only after battle accepts Burst and pays its ordinary reserve cost.
func burst_started(fighter: Dictionary, heading: Vector2, pre_cost_rpm: float) -> void:
	if _stopped or not _live(fighter):
		return
	var state: Dictionary = _state(fighter)
	if mutation(fighter, "dead_centre") == "counterweight" and float(fighter.get("stored_force", 0.0)) >= 12.0:
		_release_counterweight(fighter, heading.normalized())
	if _has(fighter, "dead_centre"):
		_break_anchor(fighter)
	if _has(fighter, "redline") and pre_cost_rpm >= 0.35 and not redline_active(fighter):
		var level: int = rank(fighter, "redline")
		var branch: String = mutation(fighter, "redline")
		state["redline_rank"] = level
		state["redline_mutation"] = branch
		var duration: float = 0.8 if level == 1 else (0.36 if branch == "breakneck" else 1.1)
		state["redline_until"] = time + duration
		state["redline_heading"] = heading.normalized()
		state["redline_hit"] = false
		state["breakneck_recovered"] = false
		fighter["redline_heading"] = heading.normalized()
		fighter["redline_time"] = duration
		fighter["redline_active_rank"] = level
		fighter["redline_active_mutation"] = branch
		fighter["runaway_heat"] = 0.0
		var activation_cost: float = 0.04 if level == 1 else 0.075
		if _run_player(fighter): activation_cost = float(_host().continuous.economy.TUNING.redline_activation_1 if level == 1 else _host().continuous.economy.TUNING.redline_activation_2)
		_spend(fighter,activation_cost)
		fighter["energy"] = fighter["rpm"]
		fighter["wobble"] = minf(1.0, float(fighter["wobble"]) + (0.10 if level == 1 else 0.17))
		if level >= 2:
			fighter["vel"] = Vector2(fighter["vel"]) + heading.normalized() * (180.0 if branch == "breakneck" else 55.0)
		_record("redline", int(fighter["entity_id"]))
		_fx("breakneck_charge" if branch == "breakneck" else ("runaway" if branch == "runaway" else ("redline_ii" if level >= 2 else "redline")), fighter["pos"], heading)
	if float(state["chain_until"]) > time:
		state["chain_until"] = 0.0
		var target: Dictionary = _host().entity(int(state["chain_target"]))
		if _live(target) and _opposes(fighter, target) and Vector2(fighter["pos"]).distance_to(target["pos"]) <= CHAIN_RADIUS:
			var normal: Vector2 = _outward(fighter["pos"], target["pos"], heading)
			_request(target, normal * 15.0, _power_cause(state["chain_cause"], "chain_burst", int(fighter["entity_id"])))
			_fx("chain_impact", fighter["pos"], normal)
			_record("chain_burst", int(fighter["entity_id"]), int(target["entity_id"]))

func wall_rebound(fighter: Dictionary, outward_speed: float, normal: Vector2, contact_pos: Vector2) -> void:
	if _stopped or not _live(fighter) or not _has(fighter, "iron_comet") or outward_speed < 110.0:
		return
	var state: Dictionary = _state(fighter)
	if time < float(state["comet_ready"]):
		return
	state["comet_until"] = time + 2.0
	state["comet_ready"] = time + 1.0
	fighter["iron_comet_time"] = 2.0
	fighter["comet_time"] = 2.0
	_record("comet_charge", int(fighter["entity_id"]))
	_fx("comet_charge", contact_pos, -normal)

## Real movement and inverse mass are exposed to the canonical battle solver.
## No-power and Rank I Redline return neutral modifiers, preserving the baseline.
func movement_control(fighter: Dictionary, direction: Vector2, braking: bool, dt: float) -> Dictionary:
	var modifiers: Dictionary = {"direction": direction, "braking": braking, "acceleration": 1.0, "speed": 1.0, "drag": 0.0, "acceleration_limit": 365.0, "drain": 1.0}
	if _stopped: return modifiers
	var state: Dictionary = _state(fighter)
	if _has(fighter, "dead_centre"):
		var charge: float = float(fighter.get("anchor_charge", 0.0))
		var position: Vector2 = fighter["pos"]
		var speed: float = Vector2(fighter["vel"]).length()
		var controlled: bool = position.length() <= 115.0 and speed <= 85.0 and (braking or direction.length() <= 0.28) and float(fighter.get("burst_time", 0.0)) <= 0.0
		if controlled and time >= float(state["anchor_lockout"]):
			charge = minf(1.0, charge + dt / (1.10 if rank(fighter, "dead_centre") == 1 else 0.85))
		else:
			charge = maxf(0.0, charge - dt * (3.5 if direction.length() > 0.55 or speed > 130.0 else 1.8))
		if charge >= 0.70 and not bool(state["anchor_announced"]):
			state["anchor_announced"] = true
			_record("anchor", int(fighter["entity_id"]))
			_fx("anchor", fighter["pos"], Vector2.ZERO, float(rank(fighter, "dead_centre")))
		if charge < 0.25: state["anchor_announced"] = false
		fighter["anchor_charge"] = charge
		modifiers["drag"] = charge * (3.0 if rank(fighter, "dead_centre") == 1 else 7.0)
		if mutation(fighter, "dead_centre") == "bulwark": modifiers["drag"] = charge * 16.0
		if charge > 0.0:
			fighter["wobble"] = maxf(0.0, float(fighter["wobble"]) - charge * dt * (0.10 if rank(fighter, "dead_centre") == 1 else 0.23))
	if redline_active(fighter) and active_redline_rank(fighter) >= 2:
		var branch: String = active_redline_mutation(fighter)
		if branch == "breakneck":
			modifiers["direction"] = (Vector2(state["redline_heading"]) + direction * 0.12).normalized()
			modifiers["braking"] = false
			modifiers["acceleration"] = 2.5
			modifiers["speed"] = 1.50
			modifiers["acceleration_limit"] = 760.0
		else:
			var heat: float = float(fighter.get("runaway_heat", 0.0))
			modifiers["acceleration"] = 1.30 + heat * 0.70
			modifiers["speed"] = 1.15 + heat * 0.40
			modifiers["acceleration_limit"] = 470.0 + heat * 200.0
			if heat > 0.0:
				# Mechanical instability is deterministic and direction-relative.
				var sideways: Vector2 = Vector2(-direction.y, direction.x)
				modifiers["direction"] = (direction + sideways * sin(time * 17.0) * heat * 0.24).limit_length(1.0)
	if float(state["slip_until"]) > time:
		modifiers["acceleration"] = float(modifiers["acceleration"]) * 1.65
		modifiers["speed"] = float(modifiers["speed"]) * 1.25
		modifiers["acceleration_limit"] = maxf(float(modifiers["acceleration_limit"]), 540.0)
		modifiers["drain"] = 0.55
	return modifiers

func inverse_mass(fighter: Dictionary) -> float:
	var mass: float = maxf(0.01, float(fighter["mass"]))
	var charge: float = float(fighter.get("anchor_charge", 0.0)) if _has(fighter, "dead_centre") else 0.0
	var multiplier: float = 1.0 + charge * charge * (3.0 if rank(fighter, "dead_centre") <= 1 else 8.0)
	if mutation(fighter, "dead_centre") == "bulwark": multiplier = 1.0 + pow(charge, 4.0) * 80.0
	return 1.0 / (mass * multiplier)

func _break_anchor(fighter: Dictionary) -> void:
	var state: Dictionary = _state(fighter)
	if float(fighter.get("anchor_charge", 0.0)) >= 0.25:
		_record("anchor_break", int(fighter["entity_id"]))
		_fx("anchor_break", fighter["pos"], Vector2(fighter["vel"]).normalized())
	fighter["anchor_charge"] = 0.0
	state["anchor_announced"] = false
	state["anchor_lockout"] = time + 0.35

func _anchor_contact(owner: Dictionary, target: Dictionary, severity: float, normal: Vector2, position: Vector2, incoming_force: float, cause: Dictionary) -> void:
	var charge: float = float(owner.get("anchor_charge", 0.0))
	if not _has(owner, "dead_centre") or charge < 0.25: return
	var state: Dictionary = _state(owner)
	var branch: String = mutation(owner, "dead_centre")
	if branch == "counterweight":
		var before: float = float(owner.get("stored_force", 0.0))
		owner["stored_force"] = minf(150.0, before + incoming_force * charge * 0.42)
		if float(owner["stored_force"]) > before + 1.0 and time >= float(state["anchor_fx_ready"]):
			state["anchor_fx_ready"] = time + 0.24
			_record("counterweight_store", int(owner["entity_id"]), int(target["entity_id"]))
			_fx("counterweight_store", position, -normal, float(owner["stored_force"]) / 150.0)
	elif branch == "bulwark" and charge >= 0.70 and severity >= 0.35 and time >= float(state["anchor_fx_ready"]):
		state["anchor_fx_ready"] = time + 0.24
		_request(target, normal * minf(85.0, incoming_force * 0.34), _power_cause(cause, "bulwark", int(owner["entity_id"])))
		owner["height"] = 0.0
		owner["height_vel"] = 0.0
		owner["wobble"] = maxf(0.0, float(owner["wobble"]) - 0.16)
		_record("bulwark_impact", int(owner["entity_id"]), int(target["entity_id"]))
		_fx("bulwark_impact", position, normal, severity)
	var threshold: float = 120.0 if rank(owner, "dead_centre") == 1 else (480.0 if branch == "bulwark" else 200.0)
	if incoming_force > threshold:
		_break_anchor(owner)
	else:
		owner["anchor_charge"] = maxf(0.0, charge - incoming_force / threshold * (0.04 if branch == "bulwark" else 0.12))

func _release_counterweight(owner: Dictionary, heading: Vector2) -> void:
	var force: float = float(owner.get("stored_force", 0.0))
	owner["stored_force"] = 0.0
	if heading.length_squared() < 0.01: heading = Vector2.RIGHT
	owner["vel"] = Vector2(owner["vel"]) + heading * force
	owner["impulse_time"] = maxf(0.0, float(owner.get("impulse_time", 0.0))) + 0.35
	for target: Dictionary in _fighters():
		if not _live(target) or not _opposes(owner, target): continue
		var offset: Vector2 = Vector2(target["pos"]) - Vector2(owner["pos"])
		if offset.length() <= 72.0 and offset.normalized().dot(heading) >= 0.25:
			_request(target, heading * minf(100.0, force * 0.85), _owned_effect_cause(owner, "counterweight_release"))
	_record("counterweight_release", int(owner["entity_id"]))
	_fx("counterweight_release", owner["pos"], heading, force / 150.0)

func incoming_power_impulse(target: Dictionary, velocity: Vector2, cause: Dictionary) -> void:
	if _stopped or not _has(target, "dead_centre") or float(target.get("anchor_charge", 0.0)) < 0.25: return
	var source: Dictionary = _host().entity(int(cause.get("owner_entity_id", 0)))
	if not _live(source) or not _opposes(target, source): return
	# Use the offered incoming velocity before the floor brace absorbs it.
	# Reflected power force may store energy, but cannot recursively reflect.
	if mutation(target, "dead_centre") == "counterweight":
		_anchor_contact(target, source, velocity.length() / 220.0, -velocity.normalized(), target["pos"], velocity.length(), _direct_cause(target, _event()))

## normal is first -> second; recoils are each body's physical velocity delta.
## Capture immutable causes before tagging either body, so storage order cannot
## let one inherited cause overwrite a competing newer cause in the same pair.
func accepted_contact(first: Dictionary, second: Dictionary, severity: float, normal: Vector2, contact_pos: Vector2, recoil_first: Vector2 = Vector2.ZERO, recoil_second: Vector2 = Vector2.ZERO, incoming_first: float = -1.0, incoming_second: float = -1.0) -> void:
	if _stopped or not _live(first) or not _live(second):
		return
	var event_id: int = _event()
	var inherited: Dictionary = _latest(cause_for(first), cause_for(second))
	var direct: Dictionary = {}
	for candidate: Dictionary in [first, second]:
		if str(candidate.get("owner_id", "")) == "player" and not _small(candidate):
			direct = _direct_cause(candidate, event_id)
			_state(candidate)["last_primary_cause"] = direct.duplicate(true)
			break
	var contact_cause: Dictionary = direct if not direct.is_empty() else inherited
	if not contact_cause.is_empty():
		contact_cause = contact_cause.duplicate(true)
		contact_cause["event_id"] = event_id
		contact_cause["primary"] = not direct.is_empty()
		var first_cause: Dictionary = cause_for(first)
		var inherited_source: int = int(first["entity_id"]) if not first_cause.is_empty() and first_cause == inherited else int(second["entity_id"])
		contact_cause["source_entity_id"] = int(direct["source_entity_id"]) if not direct.is_empty() else inherited_source
		_tag(first, contact_cause)
		_tag(second, contact_cause)
	# Only the actual power owner's accepted primary contact can trigger a power.
	_contact_owner(first, second, severity, normal, contact_pos, recoil_first, event_id, incoming_first)
	_contact_owner(second, first, severity, -normal, contact_pos, recoil_second, event_id, incoming_second)

func _contact_owner(owner: Dictionary, target: Dictionary, severity: float, normal: Vector2, position: Vector2, recoil: Vector2, event_id: int, incoming_force: float = -1.0) -> void:
	if _small(owner) or not _opposes(owner, target):
		return
	var state: Dictionary = _state(owner)
	var cause: Dictionary = _direct_cause(owner, event_id)
	_anchor_contact(owner, target, severity, normal, position, recoil.length() if incoming_force < 0.0 else incoming_force, cause)
	var redline_branch: String = active_redline_mutation(owner)
	if redline_active(owner) and redline_branch == "runaway" and severity >= 0.35 and time >= float(state["runaway_ready"]):
		state["runaway_ready"] = time + 0.20
		state["redline_until"] = minf(time + 1.25, float(state["redline_until"]) + 0.42)
		owner["redline_time"] = float(state["redline_until"]) - time
		owner["runaway_heat"] = minf(1.0, float(owner.get("runaway_heat", 0.0)) + 0.18 + severity * 0.08)
		_gain(owner,minf(0.034,0.012+severity*0.016),"runaway",_small(target))
		owner["energy"] = owner["rpm"]
		_request(target, normal * (24.0 + float(owner["runaway_heat"]) * 32.0), _power_cause(cause, "runaway", int(owner["entity_id"])))
		_record("runaway_hit", int(owner["entity_id"]), int(target["entity_id"]))
		_fx("runaway_hit", position, normal, float(owner["runaway_heat"]))
	if redline_active(owner) and redline_branch == "breakneck" and severity >= 0.35 and not bool(state["redline_hit"]):
		_request(target, normal * (100.0 if _small(target) else 80.0), _power_cause(cause, "breakneck", int(owner["entity_id"])))
		_record("breakneck_impact", int(owner["entity_id"]), int(target["entity_id"]))
		_fx("breakneck_impact", position, normal, severity)
		state["redline_until"] = time
		owner["redline_time"] = 0.0
		state["redline_hit"] = true
		_end_redline(owner)
	if redline_active(owner) and not bool(state["redline_hit"]) and redline_branch != "breakneck":
		state["redline_hit"] = true
		var heading: Vector2 = state["redline_heading"]
		var restore: float = maxf(0.0, -recoil.dot(heading)) * 0.20
		if restore > 0.0:
			_request(owner, heading * restore, _power_cause(cause, "redline_recoil", int(owner["entity_id"])))
	elif redline_active(owner) and redline_branch == "runaway" and severity >= 0.35:
		var heading: Vector2 = state["redline_heading"]
		_request(owner, heading * maxf(0.0, -recoil.dot(heading)) * 0.35, _power_cause(cause, "redline_recoil", int(owner["entity_id"])))
	if _has(owner, "impact_wake") and severity >= 0.55 and time >= float(state["wake_ready"]):
		state["wake_ready"] = time + 1.25
		var secondary_count: int = 0
		for other: Dictionary in _fighters():
			if not _live(other) or not _opposes(owner, other) or int(other["entity_id"]) == int(target["entity_id"]):
				continue
			if Vector2(other["pos"]).distance_to(position) <= WAKE_RADIUS:
				_request(other, _outward(position, other["pos"], normal) * (60.0 if _small(other) else 18.0), _power_cause(cause, "impact_wake", int(owner["entity_id"])))
				secondary_count += 1
		if secondary_count == 0:
			_request(target, normal * (36.0 if _small(target) else 12.0), _power_cause(cause, "impact_wake", int(owner["entity_id"])))
		_record("impact_wake", int(owner["entity_id"]), int(target["entity_id"]), event_id)
		_fx("impact_wake", position, normal)
	if _has(owner, "iron_comet") and float(state["comet_until"]) > time:
		state["comet_until"] = 0.0
		owner["iron_comet_time"] = 0.0
		owner["comet_time"] = 0.0
		_request(target, normal * (75.0 if _small(target) else 25.0), _power_cause(cause, "iron_comet", int(owner["entity_id"])))
		_record("comet_release", int(owner["entity_id"]), int(target["entity_id"]), event_id)
		_fx("comet_release", position, normal)
	if _has(owner, "chain_impact") and not _small(target) and severity >= 0.60 and time >= float(state["chain_ready"]):
		state["chain_until"] = time + 2.0
		state["chain_ready"] = time + 2.0
		state["chain_target"] = int(target["entity_id"])
		state["chain_cause"] = cause
		_record("chain_prime", int(owner["entity_id"]), int(target["entity_id"]), event_id)

func after_movement() -> void:
	if _stopped:
		return
	for owner: Dictionary in _fighters():
		if not _live(owner) or not _has(owner, "afterimage"):
			continue
		var state: Dictionary = _state(owner)
		var level: int = rank(owner, "afterimage")
		var branch: String = mutation(owner, "afterimage")
		var trace_emitted: bool = false
		var position: Vector2 = owner["pos"]
		if branch == "slipstream": _cross_slipstream(owner)
		var path: Array = state["trace_path"]
		if path.is_empty() or Vector2(path.back()) != position:
			path.append(position)
		if path.size() > 16:
			path.pop_front()
		if Vector2(owner["vel"]).length() <= 180.0:
			state["trace_origin"] = position
			state["trace_path"] = [position]
		elif time >= float(state["trace_ready"]) and float(owner["rpm"]) >= (0.002 if level == 1 else 0.003):
			state["trace_ready"] = time + 0.18
			_spend(owner,0.002 if level == 1 else 0.003)
			owner["energy"] = owner["rpm"]
			var start: Vector2 = path.front()
			var direction: Vector2 = _outward(start, position, Vector2(owner["vel"]).normalized())
			var lifetime: float = TRACE_SECONDS if level == 1 else (5.0 if branch == "ghost_circuit" else 2.3)
			var trace: Dictionary = {"a": start, "b": position, "points": path.duplicate(), "direction": direction,
				"owner_entity_id": int(owner["entity_id"]), "owner_id": str(owner["owner_id"]), "team_id": str(owner["team_id"]),
				"rank": level, "mutation": branch, "energized": false,
				"created_at": time, "expires_at": time + lifetime, "life": lifetime, "max_life": lifetime,
				"cause": _owned_effect_cause(owner, "afterimage")}
			traces.append(trace)
			trace_emitted = true
			state["trace_origin"] = position
			state["trace_path"] = [position]
			var owned_count: int = 0
			for active: Dictionary in traces:
				if int(active["owner_entity_id"]) == int(owner["entity_id"]):
					owned_count += 1
			if owned_count > (MAX_TRACES if level == 1 else MAX_ESCALATED_TRACES):
				for index: int in range(traces.size()):
					if int(traces[index]["owner_entity_id"]) == int(owner["entity_id"]):
						traces.remove_at(index)
						break
			while traces.size() > MAX_ALL_TRACES: traces.pop_front()
			_record("afterimage", int(owner["entity_id"]))
			_fx("afterimage" if level == 1 else "afterimage_ii", position, direction)
		# Closure is evaluated only after its closing movement has become a
		# paid, visible live trace. Low-speed returns cannot draw invisible chords.
		if branch == "ghost_circuit" and trace_emitted: _close_circuit(owner)
	for trace: Dictionary in traces:
		var owner: Dictionary = _host().entity(int(trace["owner_entity_id"]))
		if not _live(owner):
			continue
		var hit_times: Dictionary = _state(owner)["trace_hits"]
		for target: Dictionary in _fighters():
			if not _live(target) or not _opposes(owner, target) or time < float(hit_times.get(int(target["entity_id"]), 0.0)):
				continue
			var nearest: Vector2 = trace["a"]
			var nearest_distance: float = INF
			var direction: Vector2 = trace["direction"]
			var path: Array = trace["points"]
			for index: int in range(maxi(1, path.size() - 1)):
				var start: Vector2 = path[index]
				var end: Vector2 = path[mini(index + 1, path.size() - 1)]
				var point: Vector2 = Geometry2D.get_closest_point_to_segment(target["pos"], start, end)
				var distance: float = point.distance_squared_to(target["pos"])
				if distance < nearest_distance:
					nearest_distance = distance
					nearest = point
					direction = _outward(start, end, trace["direction"])
			if sqrt(nearest_distance) > (8.0 if int(trace.get("rank", 1)) == 1 else 12.0) + float(target.get("radius", 0.0)):
				continue
			var lateral: Vector2 = Vector2(-direction.y, direction.x)
			if (Vector2(target["pos"]) - nearest).dot(lateral) < 0.0:
				lateral = -lateral
			hit_times[int(target["entity_id"])] = time + 0.6
			var pressure: float = 40.0 if _small(target) else 12.0
			if int(trace.get("rank", 1)) >= 2: pressure = 64.0 if _small(target) else 24.0
			if bool(trace.get("energized", false)) and str(trace.get("mutation", "")) == "ghost_circuit": pressure = 100.0 if _small(target) else 55.0
			_request(target, lateral * pressure, _power_cause(trace["cause"], "afterimage", int(owner["entity_id"])))
			_record("afterimage_hit", int(owner["entity_id"]), int(target["entity_id"]))

func _trace_nearest(trace: Dictionary, position: Vector2) -> Dictionary:
	var path: Array = trace.get("points", [trace["a"], trace["b"]])
	var nearest: Vector2 = path[0]
	var distance: float = INF
	for index: int in range(maxi(1, path.size() - 1)):
		var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(position, path[index], path[mini(index + 1, path.size() - 1)])
		var candidate_distance: float = candidate.distance_to(position)
		if candidate_distance < distance:
			nearest = candidate
			distance = candidate_distance
	return {"point": nearest, "distance": distance}

func _cross_slipstream(owner: Dictionary) -> void:
	var state: Dictionary = _state(owner)
	var crossed: Dictionary = {}
	var nearest_distance: float = 18.0
	for trace: Dictionary in traces:
		if int(trace["owner_entity_id"]) != int(owner["entity_id"]) or time - float(trace["created_at"]) < 0.30: continue
		var nearest: Dictionary = _trace_nearest(trace, owner["pos"])
		if float(nearest["distance"]) <= nearest_distance:
			nearest_distance = float(nearest["distance"])
			crossed = trace
	var inside: bool = not crossed.is_empty()
	if inside and not bool(state["slip_inside"]) and time >= float(state["slip_ready"]) and Vector2(owner["vel"]).length() >= 70.0:
		state["slip_ready"] = time + 0.75
		state["slip_until"] = time + 0.70
		owner["slipstream_time"] = 0.70
		var heading: Vector2 = Vector2(owner["vel"]).normalized()
		owner["vel"] = (Vector2(owner["vel"]) + heading * 75.0).limit_length(440.0)
		owner["impulse_time"] = 0.35
		owner["wobble"] = maxf(0.0, float(owner["wobble"]) - 0.16)
		_gain(owner,0.006,"slipstream")
		owner["energy"] = owner["rpm"]
		crossed["energized"] = true
		crossed["expires_at"] = minf(float(crossed["created_at"]) + 3.1, float(crossed["expires_at"]) + 0.5)
		crossed["life"] = float(crossed["expires_at"]) - time
		crossed["max_life"] = maxf(float(crossed["max_life"]), float(crossed["life"]))
		_record("slipstream_cross", int(owner["entity_id"]))
		_fx("slipstream_cross", owner["pos"], heading)
	state["slip_inside"] = inside

func _close_circuit(owner: Dictionary) -> void:
	var state: Dictionary = _state(owner)
	if time < float(state["circuit_ready"]) or Vector2(owner["vel"]).length() <= 180.0: return
	var route: Array[Vector2] = []
	var route_times: Array[float] = []
	for trace: Dictionary in traces:
		if int(trace["owner_entity_id"]) != int(owner["entity_id"]) or float(trace["created_at"]) <= float(state["circuit_after"]): continue
		if not route.is_empty() and Vector2(trace["points"][0]).distance_to(route.back()) > 28.0:
			route.clear()
			route_times.clear()
		for point: Vector2 in trace["points"]:
			if route.is_empty() or route.back().distance_to(point) >= 3.0:
				route.append(point)
				route_times.append(float(trace["created_at"]))
	# A circuit must contain genuinely live paid path, not just an unpaid
	# current movement buffer after the owner's reserve has run out.
	if route.size() < 8: return
	var current_path: Array = state["trace_path"]
	if current_path.is_empty() or route.back().distance_to(Vector2(current_path[0])) > 28.0: return
	# All closure geometry must be represented by the live paid path; tolerate
	# only the tiny point-filter distance at the latest emitted endpoint.
	if route.back().distance_to(Vector2(owner["pos"])) > 6.0: return
	for point: Vector2 in current_path:
		if route.is_empty() or route.back().distance_to(point) >= 3.0:
			route.append(point)
			route_times.append(time)
	while route.size() > 320:
		route.pop_front()
		route_times.pop_front()
	if route.size() < 10: return
	var position: Vector2 = owner["pos"]
	for start: int in range(route.size() - 8):
		if time - route_times[start] < 0.75 or route[start].distance_to(position) > 28.0: continue
		var polygon: PackedVector2Array = PackedVector2Array(route.slice(start))
		polygon.append(position)
		var length: float = 0.0
		var area: float = 0.0
		var center: Vector2 = Vector2.ZERO
		for index: int in range(polygon.size()):
			var next: Vector2 = polygon[(index + 1) % polygon.size()]
			length += polygon[index].distance_to(next)
			area += polygon[index].cross(next)
			center += polygon[index]
		if length < 125.0 or absf(area) * 0.5 < 650.0: continue
		center /= float(polygon.size())
		state["circuit_ready"] = time + 2.4
		state["circuit_after"] = time
		var field_assigned: bool = false
		for trace: Dictionary in traces:
			if int(trace["owner_entity_id"]) == int(owner["entity_id"]): trace.erase("circuit_points")
			if int(trace["owner_entity_id"]) == int(owner["entity_id"]) and float(trace["created_at"]) >= route_times[start]:
				trace["energized"] = true
				if not field_assigned:
					trace["circuit_points"] = polygon
					trace["presentation_circuit_age"] = 0.0
					field_assigned = true
		for target: Dictionary in _fighters():
			if _live(target) and _opposes(owner, target) and Geometry2D.is_point_in_polygon(target["pos"], polygon):
				_request(target, _outward(center, target["pos"], Vector2(owner["vel"]).normalized()) * (100.0 if _small(target) else 65.0), _owned_effect_cause(owner, "ghost_circuit"))
				_state(owner)["trace_hits"][int(target["entity_id"])] = time + 0.60
				_record("ghost_activation", int(owner["entity_id"]), int(target["entity_id"]))
		_record("ghost_closure", int(owner["entity_id"]))
		_fx("ghost_closure", position, Vector2(owner["vel"]).normalized())
		_fx("ghost_activation", center, Vector2(owner["vel"]).normalized())
		return

func recover() -> void:
	if _stopped:
		return
	var snapshots: Array[Dictionary] = []
	for fighter: Dictionary in _fighters():
		snapshots.append({"fighter": fighter, "rpm": float(fighter["rpm"]), "wobble": float(fighter.get("wobble", 0.0)), "outcome": str(fighter.get("outcome", ""))})
	for snapshot: Dictionary in snapshots:
		var fighter: Dictionary = snapshot["fighter"]
		var state: Dictionary = _state(fighter)
		if not str(snapshot["outcome"]).is_empty() or not _has(fighter, "second_wind") or bool(state["second_wind_used"]):
			continue
		var reserve: float = float(snapshot["rpm"])
		if reserve > 0.14 and not (float(snapshot["wobble"]) >= 0.75 and reserve <= 0.28):
			continue
		state["second_wind_used"] = true
		fighter["second_wind_used"] = true
		_gain(fighter,minf(0.18,maxf(0.0,0.40-reserve)),"second_wind")
		fighter["energy"] = fighter["rpm"]
		fighter["wobble"] = maxf(0.0, float(fighter["wobble"]) - 0.25)
		_record("second_wind", int(fighter["entity_id"]))
		_fx("second_wind", fighter["pos"], Vector2.RIGHT)

func cause_for(fighter: Dictionary) -> Dictionary:
	var cause: Dictionary = fighter.get("player_cause", {})
	return cause.duplicate(true) if not cause.is_empty() and float(cause.get("expires_at", 0.0)) >= time else {}

func _direct_cause(owner: Dictionary, event_id: int) -> Dictionary:
	return {"source_entity_id": int(owner["entity_id"]), "owner_entity_id": int(owner["entity_id"]),
		"owner_id": str(owner["owner_id"]), "team_id": str(owner["team_id"]),
		"root_event_id": event_id, "event_id": event_id, "generation": 0,
		"expires_at": time + CAUSE_SECONDS, "primary": true, "kind": "contact", "tagged_at": time}

func _power_cause(parent: Dictionary, kind: String, source_id: int) -> Dictionary:
	var cause: Dictionary = parent.duplicate(true)
	cause["source_entity_id"] = source_id
	cause["event_id"] = _event()
	cause["primary"] = false
	cause["kind"] = kind
	cause["tagged_at"] = time
	cause["expires_at"] = time + CAUSE_SECONDS
	return cause

func _owned_effect_cause(owner: Dictionary, kind: String) -> Dictionary:
	var parent: Dictionary = _state(owner)["last_primary_cause"]
	if parent.is_empty():
		# Before a first direct contact, autonomous traces share an owner root.
		# They cannot refresh a chain budget just because another segment appears.
		parent = _direct_cause(owner, -int(owner["entity_id"]))
	return _power_cause(parent, kind, int(owner["entity_id"]))

func _latest(first: Dictionary, second: Dictionary) -> Dictionary:
	if first.is_empty():
		return second
	if second.is_empty():
		return first
	var first_time: float = float(first.get("tagged_at", 0.0))
	var second_time: float = float(second.get("tagged_at", 0.0))
	if first_time != second_time:
		return first if first_time > second_time else second
	return first if int(first["event_id"]) >= int(second["event_id"]) else second

func _tag(target: Dictionary, cause: Dictionary) -> void:
	if not _small(target) or cause.is_empty() or str(cause.get("owner_id", "")) != "player":
		return
	var latest: Dictionary = _latest(cause_for(target), cause)
	target["player_cause"] = latest.duplicate(true)

func _request(target: Dictionary, delta_velocity: Vector2, cause: Dictionary) -> void:
	_requests.append({"target": int(target["entity_id"]), "velocity": delta_velocity, "cause": cause.duplicate(true)})

func flush_contact_powers() -> void:
	if _stopped:
		_requests.clear()
		return
	var pending: Array[Dictionary] = _requests.duplicate()
	_requests.clear()
	for request: Dictionary in pending:
		var target: Dictionary = _host().entity(int(request["target"]))
		if not _live(target):
			continue
		_tag(target, request["cause"])
		_host().apply_power_impulse(target, request["velocity"], request["cause"])

func eliminated(fighter: Dictionary, reason: String) -> void:
	if _host().get("continuous") != null and not is_same(_host().entity(int(fighter.entity_id)), fighter): return
	if _stopped or not _small(fighter) or _eliminated_ids.has(int(fighter["entity_id"])):
		return
	_eliminated_ids[int(fighter["entity_id"])] = true
	if reason in ["natural", "natural_retirement", "retired", "despawn", "cleanup", "timeout"]:
		return
	var cause: Dictionary = cause_for(fighter)
	if cause.is_empty() or str(cause.get("owner_id", "")) != "player":
		return
	var owner: Dictionary = _host().entity(int(cause["owner_entity_id"]))
	if not _live(owner) or not _has(owner, "chain_impact"):
		return
	_eliminations.append({"pos": Vector2(fighter["pos"]), "source": int(fighter["entity_id"]), "cause": cause})

## Called after recovery, terminal evaluation and objective/timeout evaluation.
func end_tick(terminal: bool) -> void:
	if terminal or _stopped:
		finish()
		return
	_eliminations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["source"]) < int(b["source"]))
	for eliminated_body: Dictionary in _eliminations:
		var cause: Dictionary = eliminated_body["cause"]
		var root: int = int(cause["root_event_id"])
		if int(cause["generation"]) >= MAX_CHAIN_GENERATION or int(_chain_counts.get(root, 0)) >= MAX_CHAIN_PULSES:
			continue
		_chain_counts[root] = int(_chain_counts.get(root, 0)) + 1
		var next_cause: Dictionary = _power_cause(cause, "chain_impact", int(eliminated_body["source"]))
		next_cause["generation"] = int(cause["generation"]) + 1
		_next_tick_pulses.append({"pos": eliminated_body["pos"], "cause": next_cause})
	_eliminations.clear()

func _apply_pulse(pulse: Dictionary) -> void:
	var cause: Dictionary = pulse["cause"]
	cause["tagged_at"] = time
	cause["expires_at"] = time + CAUSE_SECONDS
	var owner: Dictionary = _host().entity(int(cause["owner_entity_id"]))
	if not _live(owner):
		return
	for target: Dictionary in _fighters():
		if _live(target) and _opposes(owner, target) and Vector2(target["pos"]).distance_to(pulse["pos"]) <= CHAIN_RADIUS:
			_request(target, _outward(pulse["pos"], target["pos"], Vector2.RIGHT) * (65.0 if _small(target) else 15.0), cause)
	_record("chain_impact", int(cause["owner_entity_id"]), int(cause["source_entity_id"]), int(cause["root_event_id"]), int(cause["generation"]))
	_fx("chain_impact", pulse["pos"], Vector2.RIGHT, float(cause["generation"]))

func _outward(origin: Vector2, target: Vector2, fallback: Vector2) -> Vector2:
	var offset: Vector2 = target - origin
	return offset.normalized() if offset.length_squared() > 0.0001 else (fallback.normalized() if fallback.length_squared() > 0.0001 else Vector2.RIGHT)

func finish() -> void:
	_stopped = true
	_requests.clear()
	_next_tick_pulses.clear()
	_eliminations.clear()
	traces.clear()

## Continuous enemy retirement never resets the player's power state or traces.
## Forget only removed bodies and chain roots that no live effect can reference.
func prune_retired_state() -> void:
	var ids: Dictionary = {}
	var roots: Dictionary = {}
	for f: Dictionary in _fighters():
		ids[int(f.entity_id)] = true
		_keep_cause_root(roots, cause_for(f))
	for id: int in _states.keys():
		if not ids.has(id): _states.erase(id); continue
		var state: Dictionary = _states[id]
		_keep_cause_root(roots, state.last_primary_cause)
		_keep_cause_root(roots, state.chain_cause)
		for target: int in state.trace_hits.keys():
			if not ids.has(target): state.trace_hits.erase(target)
	for id: int in _eliminated_ids.keys():
		if not ids.has(id): _eliminated_ids.erase(id)
	for collection: Array in [traces, _requests, _eliminations, _next_tick_pulses]:
		for event: Dictionary in collection: _keep_cause_root(roots, event.get("cause", {}))
	for root: int in _chain_counts.keys():
		if not roots.has(root): _chain_counts.erase(root)

func _keep_cause_root(roots: Dictionary, cause: Dictionary) -> void:
	if not cause.is_empty(): roots[int(cause.get("root_event_id", 0))] = true

# Mock/standalone hosts retain the original power contract.
func _spend(fighter: Dictionary, amount: float) -> void:
	if _host().has_method("spend_rpm"): _host().spend_rpm(fighter,amount,"powers")
	else: fighter.rpm = maxf(0.0,float(fighter.rpm)-amount)

func _gain(fighter: Dictionary, amount: float, source: String, small: bool = false) -> void:
	if _host().has_method("gain_rpm"): _host().gain_rpm(fighter,amount,source,small)
	else: fighter.rpm = minf(1.0,float(fighter.rpm)+amount)

func _run_player(fighter: Dictionary) -> bool:
	return _host().get("continuous") != null and int(fighter.entity_id) == int(_host().player_entity_id)
