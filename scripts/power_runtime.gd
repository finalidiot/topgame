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

# Task 002C.5 migrates the continuous player; standalone accepted fixtures keep
# their prior contract. Practice/semantic hosts opt in through ability_rebalance.
const REDLINE_MOTION_QUOTA: float = 0.14
const MODERN_TRACE_LIMIT: int = 26
const MODERN_GHOST_TRACE_LIMIT: int = 40
const MODERN_DEEP_TRACE_LIMIT: int = 36
const ANCHOR_MATURITY_SECONDS: float = 6.0
const ANCHOR_RECOVERY_RADIUS: float = 58.0
const ANCHOR_REARM_RADIUS: float = 82.0
const ANCHOR_REARM_SECONDS: float = 1.25
const CIRCUIT_POINT_LIMIT: int = 224
const CIRCUIT_TARGET_LIMIT: int = 8

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
		fighter["anchor_hold_seconds"] = 0.0
		fighter["anchor_maturity"] = 0.0
		fighter["anchor_recovery_rate"] = 0.0
		fighter["anchor_central_hold"] = false
		fighter["anchor_pull_strength"] = 0.0
		fighter["anchor_pull_radius"] = 0.0
		fighter["anchor_feedback_enabled"] = false
		fighter["anchor_recovery_remaining"] = 0.20
		fighter["anchor_rearm_progress"] = 0.0
		fighter["anchor_hit_time"] = 0.0
		fighter["stored_force"] = 0.0
		fighter["runaway_heat"] = 0.0
		fighter["slipstream_time"] = 0.0
		fighter["redline_heading"] = Vector2.ZERO
		fighter["redline_active_rank"] = 0
		fighter["redline_active_mutation"] = ""
		fighter["redline_heat"] = 0.0
		fighter["redline_overcap"] = 0.0
		fighter["redline_commit_time"] = 0.0
		fighter["clutch_time"] = 0.0
		fighter["clutch_active"] = false
		fighter["clutch_recovery_time"] = 0.0
		fighter["ghost_preview"] = {}

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
			"anchor_gain_ready": 0.0, "anchor_gain_pending": 0.0,
			"anchor_gain_left": 0.20, "anchor_gain_capacity": 0.20, "anchor_rearm_seconds": 0.0,
			"slip_until": 0.0, "slip_ready": 0.0, "slip_inside": false,
			"circuit_ready": 0.0, "circuit_after": -1.0,
			"last_primary_cause": {},
			"motion_input": 0.0, "motion_speed": 0.0, "motion_rpm": float(fighter["rpm"]), "motion_braking": false,
			"redline_motion_left": 0.0, "redline_contact_ready": 0.0, "redline_targets": {},
			"redline_control": Vector2.ZERO, "redline_commit_until": 0.0, "redline_strike": 0.0,
			"redline_death_recorded": false,
			"overcap_announced": false, "heat_ready": 0.0, "circuit_surge_until": 0.0,
			"clutch_until": 0.0, "clutch_ready": 0.0, "clutch_armed": true, "clutch_hit_ready": 0.0,
			"clutch_targets": {}, "clutch_recovery_until": 0.0,
			"clutch_gain_left": 0.0,
			"trace_previous": Vector2(fighter["pos"]),
			"diagnostic": {"active_seconds": 0.0, "overcap_seconds": 0.0, "max_overcap": 0.0, "overcap_integral": 0.0, "heat_max": 0.0, "high_speed_contacts": 0, "failed_commitments": 0, "commitments": 0, "rpm_gained": 0.0, "rpm_spent": 0.0, "ring_outs_active": 0, "spin_outs_active": 0}}
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

func _fx(kind: String, position: Vector2, direction: Vector2 = Vector2.RIGHT, strength: float = 1.0, presentation: Dictionary = {}) -> void:
	if _host() != null and not _stopped:
		if not presentation.is_empty():
			# Real hosts accept explicit visual provenance. Retained semantic
			# mocks keep their four-argument FX hook and identical power behavior.
			for method: Dictionary in _host().get_method_list():
				if str(method.name) == "add_power_fx":
					if method.args.size() >= 5:
						_host().add_power_fx(kind, position, direction, strength, presentation)
						return
					break
		_host().add_power_fx(kind, position, direction, strength)

func begin_tick(dt: float) -> void:
	if _stopped:
		return
	time += dt
	for fighter: Dictionary in _fighters():
		var state: Dictionary = _state(fighter)
		fighter["anchor_hit_time"] = maxf(0.0, float(fighter.get("anchor_hit_time", 0.0)) - dt)
		var was_redline: bool = float(fighter.get("redline_time", 0.0)) > 0.0
		fighter["redline_time"] = maxf(0.0, float(state["redline_until"]) - time)
		fighter["iron_comet_time"] = maxf(0.0, float(state["comet_until"]) - time)
		fighter["comet_time"] = fighter["iron_comet_time"]
		fighter["slipstream_time"] = maxf(0.0, float(state["slip_until"]) - time)
		fighter["clutch_time"] = maxf(0.0, float(state.clutch_until) - time)
		fighter["clutch_active"] = _live(fighter) and float(fighter.clutch_time) > 0.0 and float(fighter.rpm) > 0.045 and float(fighter.rpm) <= 0.30
		fighter["clutch_recovery_time"] = maxf(0.0, float(state.clutch_recovery_until) - time)
		if was_redline and float(fighter["redline_time"]) <= 0.0 and _live(fighter):
			_end_redline(fighter)
		if _modern(fighter):
			_modern_tick(fighter, dt)
		elif _live(fighter) and redline_active(fighter) and active_redline_rank(fighter) >= 2:
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
	if not redline_active(fighter) or _modern(fighter): return reserve
	if active_redline_rank(fighter) == 1: return minf(1.15, reserve + 0.35)
	if active_redline_mutation(fighter) == "breakneck": return minf(1.65, reserve + 0.85)
	return minf(1.45 + float(fighter.get("runaway_heat", 0.0)) * 0.25, reserve + 0.55)

func attack_multiplier(fighter: Dictionary) -> float:
	if _modern(fighter):
		if not redline_active(fighter): return 1.0
		if float(_state(fighter)["redline_commit_until"]) > time: return 2.35
		if active_redline_rank(fighter) == 1: return 1.0
		return 1.25 + float(fighter.get("redline_heat", 0.0)) * (0.65 if active_redline_mutation(fighter) == "runaway" else 0.25)
	if not redline_active(fighter) or active_redline_rank(fighter) <= 1: return 1.0
	match active_redline_mutation(fighter):
		"breakneck": return 2.4 if not bool(_state(fighter)["redline_hit"]) else 1.0
		"runaway": return 1.25 + float(fighter.get("runaway_heat", 0.0)) * 0.85
	return 1.35

func _end_redline(fighter: Dictionary) -> void:
	if _modern(fighter):
		_modern_end_redline(fighter)
		return
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
	_fx(release_fx, fighter["pos"], state["redline_heading"], 1.0, {"owner_entity_id": int(fighter["entity_id"]), "beast_trigger": true})

## Called only after battle accepts Burst and pays its ordinary reserve cost.
func burst_started(fighter: Dictionary, heading: Vector2, pre_cost_rpm: float) -> void:
	if _stopped or not _live(fighter):
		return
	var state: Dictionary = _state(fighter)
	if mutation(fighter, "dead_centre") == "counterweight" and float(fighter.get("stored_force", 0.0)) >= 12.0:
		_release_counterweight(fighter, heading.normalized())
	if _has(fighter, "dead_centre"):
		_break_anchor(fighter)
	if _has(fighter, "redline") and _modern(fighter):
		_modern_burst(fighter, heading, pre_cost_rpm)
	elif _has(fighter, "redline") and pre_cost_rpm >= 0.35 and not redline_active(fighter):
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
		_fx("breakneck_charge" if branch == "breakneck" else ("runaway" if branch == "runaway" else ("redline_ii" if level >= 2 else "redline")), fighter["pos"], heading, 1.0, {"owner_entity_id": int(fighter["entity_id"]), "beast_trigger": true})
	if float(state["chain_until"]) > time:
		state["chain_until"] = 0.0
		var target: Dictionary = _host().entity(int(state["chain_target"]))
		if _live(target) and _opposes(fighter, target) and Vector2(fighter["pos"]).distance_to(target["pos"]) <= (56.0 if rank(fighter, "chain_impact") >= 2 else CHAIN_RADIUS):
			var normal: Vector2 = _outward(fighter["pos"], target["pos"], heading)
			_request(target, normal * (24.0 if rank(fighter, "chain_impact") >= 2 else 15.0), _power_cause(state["chain_cause"], "chain_burst", int(fighter["entity_id"])))
			_fx("chain_impact", fighter["pos"], normal, 1.0, {"owner_entity_id": int(fighter["entity_id"]), "receiver_entity_ids": [int(target["entity_id"])]})
			_record("chain_burst", int(fighter["entity_id"]), int(target["entity_id"]))

func wall_rebound(fighter: Dictionary, outward_speed: float, normal: Vector2, contact_pos: Vector2) -> void:
	if _stopped or not _live(fighter) or not _has(fighter, "iron_comet") or outward_speed < 110.0:
		return
	var state: Dictionary = _state(fighter)
	if time < float(state["comet_ready"]):
		return
	var lifetime: float = 2.8 if rank(fighter, "iron_comet") >= 2 else 2.0
	state["comet_until"] = time + lifetime
	state["comet_ready"] = time + (0.8 if rank(fighter, "iron_comet") >= 2 else 1.0)
	fighter["iron_comet_time"] = lifetime
	fighter["comet_time"] = lifetime
	_record("comet_charge", int(fighter["entity_id"]))
	_fx("comet_charge", contact_pos, -normal, 1.0, {"owner_entity_id": int(fighter["entity_id"]), "beast_trigger": true})

## Real movement and inverse mass are exposed to the canonical battle solver.
## No-power and Rank I Redline return neutral modifiers, preserving the baseline.
func movement_control(fighter: Dictionary, direction: Vector2, braking: bool, dt: float) -> Dictionary:
	var modifiers: Dictionary = {"direction": direction, "braking": braking, "acceleration": 1.0, "speed": 1.0, "drag": 0.0, "acceleration_limit": 365.0, "drain": 1.0, "recovery": 1.0, "braking_efficiency": 1.0}
	if _stopped: return modifiers
	var state: Dictionary = _state(fighter)
	state.motion_input = direction.length()
	state.motion_speed = Vector2(fighter.vel).length()
	state.motion_rpm = float(fighter.rpm)
	state.motion_braking = braking
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
		if _modern(fighter):
			_modern_anchor_movement(fighter, controlled, dt, modifiers)
	if _modern(fighter):
		_modern_movement(fighter, direction, braking, dt, modifiers)
	elif redline_active(fighter) and active_redline_rank(fighter) >= 2:
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
	_clutch_movement(fighter, direction, modifiers)
	if float(state["slip_until"]) > time:
		var deeper_crossing: bool = _modern(fighter) and mutation(fighter, "afterimage") != "slipstream"
		modifiers["acceleration"] = float(modifiers["acceleration"]) * (1.18 if deeper_crossing else 1.65)
		modifiers["speed"] = float(modifiers["speed"]) * (1.06 if deeper_crossing else 1.25)
		modifiers["acceleration_limit"] = maxf(float(modifiers["acceleration_limit"]), 420.0 if deeper_crossing else 540.0)
		modifiers["drain"] = float(modifiers["drain"]) * (0.82 if deeper_crossing else 0.55)
	return modifiers

func inverse_mass(fighter: Dictionary) -> float:
	var mass: float = maxf(0.01, float(fighter["mass"]))
	var charge: float = float(fighter.get("anchor_charge", 0.0)) if _has(fighter, "dead_centre") else 0.0
	var multiplier: float = 1.0 + charge * charge * (3.0 if rank(fighter, "dead_centre") <= 1 else 8.0)
	if mutation(fighter, "dead_centre") == "bulwark": multiplier = 1.0 + pow(charge, 4.0) * 80.0
	elif _modern(fighter) and charge > 0.0:
		multiplier = 1.0 + charge * charge * ((5.0 if rank(fighter, "dead_centre") <= 1 else 12.0) + float(fighter.get("anchor_maturity", 0.0)) * 3.0)
	return 1.0 / (mass * multiplier)

## The brace dissipates collision shock into its physical floor connection.
## Canonical solvers apply this to both full and small body RPM/wobble loss.
## It never removes contact damage, changes outgoing power or grants immunity.
func incoming_rpm_scale(fighter: Dictionary) -> float:
	if not _modern(fighter) or not _live(fighter) or not _has(fighter, "dead_centre"): return 1.0
	var charge: float = clampf(float(fighter.get("anchor_charge", 0.0)), 0.0, 1.0)
	var maturity: float = clampf(float(fighter.get("anchor_maturity", 0.0)), 0.0, 1.0)
	var defence: float = (0.26 if rank(fighter, "dead_centre") <= 1 else 0.36) + maturity * 0.10
	if mutation(fighter, "dead_centre") == "bulwark": defence = 0.45 + maturity * 0.10
	return clampf(1.0 - charge * charge * defence, 0.45, 1.0)

func _modern_anchor_movement(fighter: Dictionary, controlled: bool, dt: float, modifiers: Dictionary) -> void:
	var state: Dictionary = _state(fighter)
	fighter["anchor_feedback_enabled"] = true
	var level: int = rank(fighter, "dead_centre")
	var capacity: float = 0.20 if level <= 1 else 0.28
	# A genuine rank investment adds only its additional recovery capacity.
	# Dropping charge, taking a hit or bursting cannot mint another quota.
	if capacity > float(state.anchor_gain_capacity):
		state.anchor_gain_left = minf(capacity, float(state.anchor_gain_left) + capacity - float(state.anchor_gain_capacity))
		state.anchor_gain_capacity = capacity
	var deliberate_rotation: bool = _live(fighter) and Vector2(fighter.pos).length() >= ANCHOR_REARM_RADIUS and float(state.motion_input) >= 0.35 and float(state.motion_speed) >= 35.0 and not bool(state.motion_braking)
	state.anchor_rearm_seconds = minf(ANCHOR_REARM_SECONDS, float(state.anchor_rearm_seconds) + dt) if deliberate_rotation and float(state.anchor_gain_left) < capacity - 0.000001 else 0.0
	if float(state.anchor_rearm_seconds) >= ANCHOR_REARM_SECONDS - 0.000001:
		state.anchor_gain_left = capacity
		state.anchor_rearm_seconds = 0.0
		_record("anchor_rearm", int(fighter.entity_id))
	fighter["anchor_recovery_remaining"] = maxf(0.0, float(state.anchor_gain_left))
	fighter["anchor_rearm_progress"] = float(state.anchor_rearm_seconds) / ANCHOR_REARM_SECONDS
	var charge: float = clampf(float(fighter.get("anchor_charge", 0.0)), 0.0, 1.0)
	var full_hold: bool = _live(fighter) and float(fighter.rpm) > 0.045 and controlled and time >= float(state.anchor_lockout) and charge >= 0.70
	var hold: float = float(fighter.get("anchor_hold_seconds", 0.0))
	hold = minf(ANCHOR_MATURITY_SECONDS, hold + dt) if full_hold else maxf(0.0, hold - dt * 3.0)
	fighter["anchor_hold_seconds"] = hold
	fighter["anchor_maturity"] = hold / ANCHOR_MATURITY_SECONDS
	fighter["anchor_recovery_rate"] = 0.0
	var maturity: float = float(fighter.anchor_maturity)
	modifiers.drag = float(modifiers.drag) + charge * (2.0 + maturity * 4.0)
	modifiers.recovery = float(modifiers.recovery) * (1.0 + charge * (0.30 + maturity * 0.70))
	if charge > 0.0: fighter.wobble = maxf(0.0, float(fighter.wobble) - charge * maturity * dt * 0.16)
	# Centre sustain is earned by maintaining the central floor socket, not by
	# simply owning the power or parking near a wall. The below-full ceiling
	# leaves every rank damageable and never creates overclock reserve.
	var central: bool = Vector2(fighter.pos).length() <= ANCHOR_RECOVERY_RADIUS and Vector2(fighter.vel).length() <= 55.0
	fighter["anchor_central_hold"] = full_hold and central
	fighter["anchor_pull_strength"] = 0.0
	fighter["anchor_pull_radius"] = 0.0
	if full_hold and central: _anchor_pull(fighter, maturity, level, dt)
	var ceiling: float = 0.78 if level <= 1 else 0.86
	if mutation(fighter, "dead_centre") == "bulwark": ceiling = 0.90
	if not full_hold or not central or float(fighter.rpm) >= ceiling or float(state.anchor_gain_left) <= 0.000001:
		state.anchor_gain_pending = 0.0
		return
	var rate: float = lerpf(0.003 if level <= 1 else 0.004, 0.009 if level <= 1 else 0.012, maturity)
	fighter.anchor_recovery_rate = rate
	state.anchor_gain_pending = minf(0.012, float(state.anchor_gain_pending) + rate * dt)
	if time < float(state.anchor_gain_ready): return
	state.anchor_gain_ready = time + 0.50
	var gained: float = _gain(fighter, minf(float(state.anchor_gain_pending), minf(ceiling - float(fighter.rpm), float(state.anchor_gain_left))), "dead_centre")
	state.anchor_gain_pending = 0.0
	if gained > 0.0:
		state.anchor_gain_left = maxf(0.0, float(state.anchor_gain_left) - gained)
		fighter.anchor_recovery_remaining = state.anchor_gain_left
		fighter.energy = fighter.rpm
		_record("anchor_recover", int(fighter.entity_id))

## Sustained central lock bends nearby approaches toward the real floor socket.
## A dt-scaled velocity offer, finite radius, target budget and inward-speed
## ceiling prevent stacking into unlimited speed or freezing an attacking boss.
func _anchor_pull(owner: Dictionary, maturity: float, level: int, dt: float) -> void:
	var strength: float = lerpf(4.0, 32.0 if level <= 1 else 46.0, maturity)
	var radius: float = lerpf(44.0, 104.0 if level <= 1 else 124.0, maturity)
	owner["anchor_pull_strength"] = strength
	owner["anchor_pull_radius"] = radius
	var count: int = 0
	for target: Dictionary in _fighters():
		if count >= 16: break
		if not _live(target) or not _opposes(owner, target): continue
		var offset: Vector2 = Vector2(owner.pos) - Vector2(target.pos)
		var distance: float = offset.length()
		var socket: float = float(owner.get("radius", 12.0)) + float(target.get("radius", 12.0)) + 2.0
		if distance <= socket or distance >= radius: continue
		var inward: Vector2 = offset / distance
		var inward_speed: float = Vector2(target.vel).dot(inward)
		if inward_speed >= 120.0: continue
		var resistance: float = clampf(8.0 / maxf(1.0, float(target.get("mass", 8.0))), 0.35, 1.0)
		if str(target.get("enemy_kind", "")) == "boss": resistance *= 0.45
		var falloff: float = clampf((radius - distance) / maxf(1.0, radius - socket), 0.0, 1.0)
		var velocity: float = minf(maxf(0.0, 120.0 - inward_speed), strength * resistance * falloff * minf(dt, 0.10))
		_request(target, inward * velocity, _owned_effect_cause(owner, "dead_centre_pull"))
		count += 1

func _break_anchor(fighter: Dictionary) -> void:
	var state: Dictionary = _state(fighter)
	if float(fighter.get("anchor_charge", 0.0)) >= 0.25:
		_record("anchor_break", int(fighter["entity_id"]))
		_fx("anchor_break", fighter["pos"], Vector2(fighter["vel"]).normalized())
	fighter["anchor_charge"] = 0.0
	fighter["anchor_hold_seconds"] = 0.0
	fighter["anchor_maturity"] = 0.0
	fighter["anchor_recovery_rate"] = 0.0
	fighter["anchor_central_hold"] = false
	fighter["anchor_pull_strength"] = 0.0
	fighter["anchor_pull_radius"] = 0.0
	state["anchor_gain_pending"] = 0.0
	state["anchor_rearm_seconds"] = 0.0
	fighter["anchor_rearm_progress"] = 0.0
	state["anchor_announced"] = false
	state["anchor_lockout"] = time + 0.35

func _anchor_contact(owner: Dictionary, target: Dictionary, severity: float, normal: Vector2, position: Vector2, incoming_force: float, cause: Dictionary) -> void:
	var charge: float = float(owner.get("anchor_charge", 0.0))
	if not _has(owner, "dead_centre") or charge < 0.25: return
	var state: Dictionary = _state(owner)
	var branch: String = mutation(owner, "dead_centre")
	if _modern(owner) and severity >= 0.22:
		owner["anchor_hit_time"] = 0.32
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
		owner["wobble"] = maxf(0.0, float(owner["wobble"]) - (0.06 if _modern(owner) else 0.16))
		_record("bulwark_impact", int(owner["entity_id"]), int(target["entity_id"]))
		_fx("bulwark_impact", position, normal, severity)
	var threshold: float = 120.0 if rank(owner, "dead_centre") == 1 else (480.0 if branch == "bulwark" else 200.0)
	if _modern(owner): threshold = 220.0 if rank(owner, "dead_centre") == 1 else (600.0 if branch == "bulwark" else 330.0)
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
	if _modern(owner):
		_modern_contact(owner, target, severity, normal, position, recoil, cause)
	_clutch_contact(owner, target, severity, normal, position)
	var redline_branch: String = active_redline_mutation(owner)
	if not _modern(owner) and redline_active(owner) and redline_branch == "runaway" and severity >= 0.35 and time >= float(state["runaway_ready"]):
		state["runaway_ready"] = time + 0.20
		state["redline_until"] = minf(time + 1.25, float(state["redline_until"]) + 0.42)
		owner["redline_time"] = float(state["redline_until"]) - time
		owner["runaway_heat"] = minf(1.0, float(owner.get("runaway_heat", 0.0)) + 0.18 + severity * 0.08)
		_gain(owner,minf(0.034,0.012+severity*0.016),"runaway",_small(target))
		owner["energy"] = owner["rpm"]
		_request(target, normal * (24.0 + float(owner["runaway_heat"]) * 32.0), _power_cause(cause, "runaway", int(owner["entity_id"])))
		_record("runaway_hit", int(owner["entity_id"]), int(target["entity_id"]))
		_fx("runaway_hit", position, normal, float(owner["runaway_heat"]))
	if not _modern(owner) and redline_active(owner) and redline_branch == "breakneck" and severity >= 0.35 and not bool(state["redline_hit"]):
		_request(target, normal * (100.0 if _small(target) else 80.0), _power_cause(cause, "breakneck", int(owner["entity_id"])))
		_record("breakneck_impact", int(owner["entity_id"]), int(target["entity_id"]))
		_fx("breakneck_impact", position, normal, severity, {"owner_entity_id": int(owner["entity_id"]), "beast_trigger": true})
		state["redline_until"] = time
		owner["redline_time"] = 0.0
		state["redline_hit"] = true
		_end_redline(owner)
	if not _modern(owner) and redline_active(owner) and not bool(state["redline_hit"]) and redline_branch != "breakneck":
		state["redline_hit"] = true
		var heading: Vector2 = state["redline_heading"]
		var restore: float = maxf(0.0, -recoil.dot(heading)) * 0.20
		if restore > 0.0:
			_request(owner, heading * restore, _power_cause(cause, "redline_recoil", int(owner["entity_id"])))
	elif not _modern(owner) and redline_active(owner) and redline_branch == "runaway" and severity >= 0.35:
		var heading: Vector2 = state["redline_heading"]
		_request(owner, heading * maxf(0.0, -recoil.dot(heading)) * 0.35, _power_cause(cause, "redline_recoil", int(owner["entity_id"])))
	if _has(owner, "impact_wake") and severity >= 0.55 and time >= float(state["wake_ready"]):
		state["wake_ready"] = time + (1.05 if rank(owner, "impact_wake") >= 2 else 1.25)
		var secondary_count: int = 0
		for other: Dictionary in _fighters():
			if not _live(other) or not _opposes(owner, other) or int(other["entity_id"]) == int(target["entity_id"]):
				continue
			if Vector2(other["pos"]).distance_to(position) <= (68.0 if rank(owner, "impact_wake") >= 2 else WAKE_RADIUS):
				_request(other, _outward(position, other["pos"], normal) * ((80.0 if _small(other) else 25.0) if rank(owner, "impact_wake") >= 2 else (60.0 if _small(other) else 18.0)), _power_cause(cause, "impact_wake", int(owner["entity_id"])))
				secondary_count += 1
		if secondary_count == 0:
			_request(target, normal * ((48.0 if _small(target) else 18.0) if rank(owner, "impact_wake") >= 2 else (36.0 if _small(target) else 12.0)), _power_cause(cause, "impact_wake", int(owner["entity_id"])))
		_record("impact_wake", int(owner["entity_id"]), int(target["entity_id"]), event_id)
		_fx("impact_wake", position, normal, 1.0, {"owner_entity_id": int(owner["entity_id"]), "beast_trigger": true})
	if _has(owner, "iron_comet") and float(state["comet_until"]) > time:
		state["comet_until"] = 0.0
		owner["iron_comet_time"] = 0.0
		owner["comet_time"] = 0.0
		_request(target, normal * ((90.0 if _small(target) else 34.0) if rank(owner, "iron_comet") >= 2 else (75.0 if _small(target) else 25.0)), _power_cause(cause, "iron_comet", int(owner["entity_id"])))
		_record("comet_release", int(owner["entity_id"]), int(target["entity_id"]), event_id)
		_fx("comet_release", position, normal, 1.0, {"owner_entity_id": int(owner["entity_id"]), "beast_trigger": true})
	if _has(owner, "chain_impact") and not _small(target) and severity >= 0.60 and time >= float(state["chain_ready"]):
		state["chain_until"] = time + (3.0 if rank(owner, "chain_impact") >= 2 else 2.0)
		state["chain_ready"] = time + (1.65 if rank(owner, "chain_impact") >= 2 else 2.0)
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
		if branch == "slipstream" or (_modern(owner) and level >= 2 and branch.is_empty()): _cross_slipstream(owner)
		var path: Array = state["trace_path"]
		if path.is_empty() or Vector2(path.back()) != position:
			path.append(position)
		if path.size() > 16:
			path.pop_front()
		if Vector2(owner["vel"]).length() <= (112.0 if _modern(owner) else 180.0):
			state["trace_origin"] = position
			state["trace_path"] = [position]
		elif time >= float(state["trace_ready"]) and float(owner["rpm"]) >= (0.002 if level == 1 else 0.003) and (not _modern(owner) or Vector2(path.front()).distance_to(position) >= 6.0):
			state["trace_ready"] = time + (0.14 if _modern(owner) else 0.18)
			_spend(owner,(0.0008 if level == 1 else 0.0011) if _modern(owner) else (0.002 if level == 1 else 0.003))
			owner["energy"] = owner["rpm"]
			var start: Vector2 = path.front()
			var direction: Vector2 = _outward(start, position, Vector2(owner["vel"]).normalized())
			var lifetime: float = (3.4 if level == 1 else (6.0 if branch == "ghost_circuit" else 4.6)) if _modern(owner) else (TRACE_SECONDS if level == 1 else (5.0 if branch == "ghost_circuit" else 2.3))
			var trace: Dictionary = {"a": start, "b": position, "points": path.duplicate(), "direction": direction,
				"owner_entity_id": int(owner["entity_id"]), "owner_id": str(owner["owner_id"]), "team_id": str(owner["team_id"]),
				"rank": level, "mutation": branch, "energized": false, "extended_route": _modern(owner),
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
			var trace_limit: int = (MODERN_TRACE_LIMIT if _modern(owner) else MAX_TRACES) if level == 1 else ((MODERN_GHOST_TRACE_LIMIT if branch == "ghost_circuit" else MODERN_DEEP_TRACE_LIMIT) if _modern(owner) else MAX_ESCALATED_TRACES)
			if owned_count > trace_limit:
				for index: int in range(traces.size()):
					if int(traces[index]["owner_entity_id"]) == int(owner["entity_id"]):
						traces.remove_at(index)
						break
			while traces.size() > MAX_ALL_TRACES: traces.pop_front()
			_record("afterimage", int(owner["entity_id"]))
			_fx("afterimage" if level == 1 else "afterimage_ii", position, direction)
		# Closure is evaluated only after its closing movement has become a
		# paid, visible live trace. Low-speed returns cannot draw invisible chords.
		if branch == "ghost_circuit":
			if _modern(owner): _modern_circuit(owner, trace_emitted)
			elif trace_emitted: _close_circuit(owner)
		state["trace_previous"] = position
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
			var pressure: float = (50.0 if _small(target) else 18.0) if _modern(owner) else (40.0 if _small(target) else 12.0)
			if int(trace.get("rank", 1)) >= 2: pressure = (72.0 if _small(target) else 30.0) if _modern(owner) else (64.0 if _small(target) else 24.0)
			if _modern(owner): target["wobble"] = minf(1.0, float(target.get("wobble", 0.0)) + (0.015 if int(trace.get("rank", 1)) == 1 else 0.025))
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
	var nearest_distance: float = 22.0 if _modern(owner) else 18.0
	for trace: Dictionary in traces:
		if int(trace["owner_entity_id"]) != int(owner["entity_id"]) or time - float(trace["created_at"]) < 0.30: continue
		var nearest: Dictionary = _trace_nearest(trace, owner["pos"])
		if _modern(owner):
			var previous: Vector2 = state["trace_previous"]
			for index: int in range(maxi(1, trace["points"].size() - 1)):
				var crossing: Variant = Geometry2D.segment_intersects_segment(previous, owner["pos"], trace["points"][index], trace["points"][mini(index + 1, trace["points"].size() - 1)])
				if crossing != null: nearest = {"point": crossing, "distance": 0.0}
		if float(nearest["distance"]) <= nearest_distance:
			nearest_distance = float(nearest["distance"])
			crossed = trace
	var inside: bool = not crossed.is_empty()
	if inside and not bool(state["slip_inside"]) and time >= float(state["slip_ready"]) and Vector2(owner["vel"]).length() >= 70.0:
		var surge: bool = mutation(owner, "afterimage") == "slipstream"
		state["slip_ready"] = time + (0.9 if _modern(owner) else 0.75)
		state["slip_until"] = time + ((0.75 if surge else 0.30) if _modern(owner) else 0.70)
		owner["slipstream_time"] = (0.75 if surge else 0.30) if _modern(owner) else 0.70
		var heading: Vector2 = Vector2(owner["vel"]).normalized()
		owner["vel"] = (Vector2(owner["vel"]) + heading * ((90.0 if surge else 30.0) if _modern(owner) else 75.0)).limit_length(440.0)
		owner["impulse_time"] = 0.35
		owner["wobble"] = maxf(0.0, float(owner["wobble"]) - 0.16)
		if surge or not _modern(owner): _gain(owner,0.004 if _modern(owner) else 0.006,"slipstream")
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
	for fighter: Dictionary in _fighters():
		_clutch_recover(fighter)
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
	if _modern(fighter) and redline_active(fighter) and not bool(_state(fighter).redline_death_recorded) and reason in ["ring_out", "spin_out"]:
		var diagnostic: Dictionary = _state(fighter)["diagnostic"]
		_state(fighter).redline_death_recorded = true
		if reason == "ring_out": diagnostic["ring_outs_active"] += 1
		elif reason == "spin_out": diagnostic["spin_outs_active"] += 1
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
	var presentation_receivers: Array[int] = []
	for target: Dictionary in _fighters():
		if _live(target) and _opposes(owner, target) and Vector2(target["pos"]).distance_to(pulse["pos"]) <= (56.0 if rank(owner, "chain_impact") >= 2 else CHAIN_RADIUS):
			_request(target, _outward(pulse["pos"], target["pos"], Vector2.RIGHT) * ((82.0 if _small(target) else 24.0) if rank(owner, "chain_impact") >= 2 else (65.0 if _small(target) else 15.0)), cause)
			presentation_receivers.append(int(target["entity_id"]))
	_record("chain_impact", int(cause["owner_entity_id"]), int(cause["source_entity_id"]), int(cause["root_event_id"]), int(cause["generation"]))
	_fx("chain_impact", pulse["pos"], Vector2.RIGHT, float(cause["generation"]), {"owner_entity_id": int(cause["owner_entity_id"]), "receiver_entity_ids": presentation_receivers})

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
		for target_map: Dictionary in [state.trace_hits, state.redline_targets, state.clutch_targets]:
			for target: int in target_map.keys():
				if not ids.has(target): target_map.erase(target)
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
	var before: float = float(fighter.rpm)
	if _host().has_method("spend_rpm"): _host().spend_rpm(fighter,amount,"powers")
	else: fighter.rpm = maxf(0.0,float(fighter.rpm)-amount)
	if _modern(fighter) and redline_active(fighter): _state(fighter)["diagnostic"]["rpm_spent"] += maxf(0.0, before - float(fighter.rpm))

func _gain(fighter: Dictionary, amount: float, source: String, small: bool = false) -> float:
	var before: float = float(fighter.rpm)
	if _host().has_method("gain_rpm"): _host().gain_rpm(fighter,amount,source,small)
	else: fighter.rpm = minf(rpm_cap(fighter),float(fighter.rpm)+amount)
	var actual: float = maxf(0.0, float(fighter.rpm) - before)
	if _modern(fighter) and (source.begins_with("redline") or source == "runaway"):
		_state(fighter)["diagnostic"]["rpm_gained"] += actual
		_modern_overcap_event(fighter)
	return actual

func _run_player(fighter: Dictionary) -> bool:
	return _host().get("continuous") != null and int(fighter.entity_id) == int(_host().player_entity_id)

func _modern(fighter: Dictionary) -> bool:
	return _run_player(fighter) or _host().get("ability_rebalance") == true

## The real reserve is also the output. Only a live overclock can hold excess;
## expiry vents it through the same source-accounted spending path as heat.
func rpm_cap(fighter: Dictionary) -> float:
	if not _modern(fighter) or not _live(fighter) or not redline_active(fighter): return 1.0
	if active_redline_mutation(fighter) == "runaway": return 1.24
	return 1.12 if active_redline_rank(fighter) == 1 else 1.18

func diagnostics(fighter: Dictionary) -> Dictionary:
	var result: Dictionary = _state(fighter)["diagnostic"].duplicate(true)
	result["mean_overcap_active"] = float(result.overcap_integral) / maxf(0.00001, float(result.active_seconds))
	result["heat"] = float(fighter.get("redline_heat", 0.0))
	result["motion_quota_remaining"] = float(_state(fighter)["redline_motion_left"])
	result["clutch_active"] = bool(fighter.get("clutch_active", false))
	return result

func _modern_tick(fighter: Dictionary, dt: float) -> void:
	var state: Dictionary = _state(fighter)
	fighter["redline_commit_time"] = maxf(0.0, float(state.redline_commit_until) - time)
	fighter["clutch_time"] = maxf(0.0, float(state.clutch_until) - time)
	fighter["clutch_active"] = _live(fighter) and float(fighter.clutch_time) > 0.0 and float(fighter.rpm) > 0.045 and float(fighter.rpm) <= 0.30
	fighter["clutch_recovery_time"] = maxf(0.0, float(state.clutch_recovery_until) - time)
	if not _live(fighter):
		fighter["ghost_preview"] = {}
		return
	var heat: float = float(fighter.get("redline_heat", 0.0))
	if redline_active(fighter):
		_modern_overcap_event(fighter)
		var excess: float = maxf(0.0, float(fighter.rpm) - 1.0)
		var diagnostic: Dictionary = state.diagnostic
		diagnostic.active_seconds += dt
		diagnostic.overcap_seconds += dt if excess > 0.00001 else 0.0
		diagnostic.max_overcap = maxf(float(diagnostic.max_overcap), excess)
		diagnostic.overcap_integral += excess * dt
		_spend(fighter, (0.003 + heat * 0.006) * dt)
		if float(fighter.rpm) <= 0.13:
			state.redline_until = time
			fighter.redline_time = 0.0
			_end_redline(fighter)
		if float(state.motion_input) < 0.15 or bool(state.motion_braking) or float(state.motion_speed) < 100.0:
			heat = maxf(0.0, heat - dt * 0.20)
	else:
		heat = maxf(0.0, heat - dt * 0.32)
	fighter["redline_heat"] = heat
	fighter["runaway_heat"] = heat
	fighter["redline_overcap"] = maxf(0.0, float(fighter.rpm) - 1.0)
	state.diagnostic.heat_max = maxf(float(state.diagnostic.heat_max), heat)
	if heat >= 0.80 and time >= float(state.heat_ready) and redline_active(fighter):
		state.heat_ready = time + 2.0
		_fx("redline_heat", fighter.pos, Vector2(fighter.vel).normalized(), heat)
		_record("redline_heat", int(fighter.entity_id))
	if float(fighter.rpm) <= 1.0: state.overcap_announced = false

func _modern_overcap_event(fighter: Dictionary) -> void:
	fighter["redline_overcap"] = maxf(0.0, float(fighter.rpm) - 1.0)
	var state: Dictionary = _state(fighter)
	state.diagnostic.max_overcap = maxf(float(state.diagnostic.max_overcap), float(fighter.redline_overcap))
	if float(fighter.rpm) > 1.0 and not bool(state.overcap_announced):
		state.overcap_announced = true
		_record("redline_overcap", int(fighter.entity_id))
		_fx("redline_overcap", fighter.pos, Vector2(fighter.vel).normalized(), float(fighter.redline_overcap))

func _modern_burst(fighter: Dictionary, heading: Vector2, pre_cost_rpm: float) -> void:
	var state: Dictionary = _state(fighter)
	if redline_active(fighter):
		if active_redline_mutation(fighter) == "breakneck" and float(state.redline_commit_until) <= time and (float(fighter.get("redline_heat", 0.0)) >= 0.32 or pre_cost_rpm >= 1.025):
			var excess: float = maxf(0.0, pre_cost_rpm - 1.0)
			state.redline_strike = 0.08 + excess * 0.75
			_spend(fighter, float(state.redline_strike))
			state.redline_commit_until = time + 0.48
			state.redline_until = time + 0.48
			state.redline_heading = heading.normalized()
			state.redline_hit = false
			fighter.redline_time = 0.48
			fighter["redline_commit_time"] = 0.48
			fighter.vel = Vector2(fighter.vel) + heading.normalized() * 160.0
			state.diagnostic.commitments += 1
			_record("breakneck_commit", int(fighter.entity_id))
			_fx("breakneck_charge", fighter.pos, heading, 1.0, {"owner_entity_id": int(fighter.entity_id), "beast_trigger": true})
		return
	if pre_cost_rpm < 0.13: return
	var level: int = rank(fighter, "redline")
	var branch: String = mutation(fighter, "redline")
	state.redline_rank = level
	state.redline_mutation = branch
	state.redline_until = time + (4.8 if branch == "breakneck" else 3.2)
	state.redline_heading = heading.normalized()
	state.redline_control = heading.normalized()
	state.redline_hit = false
	state.breakneck_recovered = false
	state.redline_commit_until = 0.0
	state.redline_motion_left = REDLINE_MOTION_QUOTA
	fighter.redline_time = float(state.redline_until) - time
	fighter.redline_heading = heading.normalized()
	fighter.redline_active_rank = level
	fighter.redline_active_mutation = branch
	_spend(fighter, 0.025 if level == 1 else 0.045)
	fighter.wobble = minf(1.0, float(fighter.wobble) + (0.06 if level == 1 else 0.10))
	_record("redline", int(fighter.entity_id))
	_fx("runaway" if branch == "runaway" else ("redline_ii" if level >= 2 else "redline"), fighter.pos, heading)

func _modern_end_redline(fighter: Dictionary) -> void:
	var state: Dictionary = _state(fighter)
	var before: float = float(fighter.rpm)
	var committed: bool = float(state.redline_commit_until) > 0.0
	var branch: String = active_redline_mutation(fighter)
	if committed and branch == "breakneck" and not bool(state.breakneck_recovered):
		state.breakneck_recovered = true
		var missed: bool = not bool(state.redline_hit)
		_spend(fighter, 0.035 if missed else 0.015)
		fighter.wobble = minf(1.0, float(fighter.wobble) + (0.42 if missed else 0.28))
		fighter.vel = Vector2(fighter.vel) * (0.58 if missed else 0.72)
		fighter.burst_time = 0.0
		if missed:
			state.diagnostic.failed_commitments += 1
			_record("breakneck_miss", int(fighter.entity_id))
		_fx("breakneck_recovery", fighter.pos, state.redline_heading, 1.0, {"owner_entity_id": int(fighter.entity_id), "beast_trigger": true})
	else:
		_fx("redline_release", fighter.pos, state.redline_heading)
	# The cap changes only here. Never silently discard earned ledger reserve.
	var vent: float = maxf(0.0, float(fighter.rpm) - 1.0)
	if vent > 0.0:
		_spend(fighter, vent)
	state.diagnostic.rpm_spent += maxf(0.0, before - float(fighter.rpm))
	state.redline_motion_left = 0.0
	state.redline_commit_until = 0.0
	fighter.redline_commit_time = 0.0
	fighter.redline_overcap = 0.0
	fighter.redline_active_rank = 0
	fighter.redline_active_mutation = ""
	fighter.energy = fighter.rpm

func _modern_movement(fighter: Dictionary, direction: Vector2, braking: bool, dt: float, modifiers: Dictionary) -> void:
	var state: Dictionary = _state(fighter)
	state.motion_input = direction.length()
	state.motion_speed = Vector2(fighter.vel).length()
	state.motion_braking = braking
	if redline_active(fighter):
		var heat: float = float(fighter.get("redline_heat", 0.0))
		var committed: bool = float(state.redline_commit_until) > time
		var aggressive: bool = direction.length() >= 0.35 and float(state.motion_speed) >= 135.0 and not braking and Vector2(fighter.pos).length() < 170.0
		if aggressive and not committed:
			var gain: float = _gain(fighter, minf(float(state.redline_motion_left), 0.045 * dt), "redline_motion")
			state.redline_motion_left = maxf(0.0, float(state.redline_motion_left) - gain)
			heat = minf(1.0, heat + dt * (0.16 + maxf(0.0, float(fighter.rpm) - 1.0) * 0.8))
			fighter["redline_heat"] = heat
			fighter["runaway_heat"] = heat
			modifiers.drain = 0.72
		var unsafe: float = clampf(heat * 0.7 + maxf(0.0, float(fighter.rpm) - 1.0) * 2.0, 0.0, 1.0)
		modifiers.acceleration = float(modifiers.acceleration) * (1.12 if active_redline_rank(fighter) == 1 else 1.30) + heat * 0.28
		modifiers.speed = float(modifiers.speed) * (1.05 + heat * 0.16)
		modifiers.acceleration_limit = 470.0 + heat * 130.0
		modifiers.braking_efficiency = 1.0 - unsafe * 0.48
		modifiers.recovery = 1.0 - unsafe * 0.42
		if unsafe > 0.02 and direction.length() > 0.0:
			var previous: Vector2 = state.redline_control
			var assisted: Vector2 = previous.lerp(direction, clampf(dt * (24.0 - unsafe * 16.0), 0.0, 1.0))
			var lateral: Vector2 = Vector2(-direction.y, direction.x)
			modifiers.direction = (assisted + lateral * sin(time * 17.0) * unsafe * 0.12).limit_length(1.0)
			state.redline_control = assisted
			fighter.wobble = minf(1.0, float(fighter.wobble) + unsafe * dt * 0.09)
		else: state.redline_control = direction
		if committed:
			modifiers.direction = (Vector2(state.redline_heading) + direction * 0.08).normalized()
			modifiers.braking = false
			modifiers.acceleration = 2.4
			modifiers.speed = 1.55
			modifiers.acceleration_limit = 760.0
	if float(state.circuit_surge_until) > time: modifiers.drain = float(modifiers.drain) * 0.75

func _clutch_movement(fighter: Dictionary, direction: Vector2, modifiers: Dictionary) -> void:
	if bool(fighter.get("clutch_active", false)) and direction.length() >= 0.12 and direction.length() <= 0.8 and Vector2(fighter.pos).length() < 150.0:
		modifiers.drain = float(modifiers.drain) * (0.65 if rank(fighter, "clutch") == 1 else 0.52)
		modifiers.recovery = float(modifiers.recovery) * 1.22

func _modern_contact(owner: Dictionary, target: Dictionary, severity: float, normal: Vector2, position: Vector2, recoil: Vector2, cause: Dictionary) -> void:
	if not redline_active(owner): return
	var state: Dictionary = _state(owner)
	var branch: String = active_redline_mutation(owner)
	var active_play: bool = (float(state.redline_commit_until) > time and float(state.motion_speed) >= 100.0) or (float(state.motion_input) >= 0.15 and not bool(state.motion_braking) and float(state.motion_speed) >= 70.0)
	if severity < 0.35 or not active_play: return
	state.diagnostic.high_speed_contacts += 1
	if float(state.redline_commit_until) > time and not bool(state.redline_hit):
		state.redline_hit = true
		_request(target, normal * minf(100.0, 75.0 + float(state.redline_strike) * 100.0), _power_cause(cause, "breakneck", int(owner.entity_id)))
		_request(owner, -normal * minf(70.0, recoil.length() * 0.35 + 20.0), _power_cause(cause, "breakneck_recoil", int(owner.entity_id)))
		_record("breakneck_impact", int(owner.entity_id), int(target.entity_id))
		_fx("breakneck_impact", position, normal, severity, {"owner_entity_id": int(owner.entity_id), "beast_trigger": true})
		state.redline_until = time
		owner.redline_time = 0.0
		_end_redline(owner)
		return
	if time < float(state.redline_contact_ready) or time < float(state.redline_targets.get(int(target.entity_id), 0.0)): return
	state.redline_contact_ready = time + 0.65
	state.redline_targets[int(target.entity_id)] = time + 1.0
	var earned: float = minf(0.055, 0.015 + severity * 0.025)
	_gain(owner, earned, "runaway" if branch == "runaway" else "redline_contact", _small(target))
	owner.energy = owner.rpm
	owner.redline_heat = minf(1.0, float(owner.get("redline_heat", 0.0)) + 0.12 + severity * 0.045)
	owner.runaway_heat = owner.redline_heat
	if branch == "runaway":
		state.redline_until = minf(time + 3.2, float(state.redline_until) + 1.2)
		owner.redline_time = float(state.redline_until) - time
		state.redline_motion_left = minf(REDLINE_MOTION_QUOTA, float(state.redline_motion_left) + (0.01 if _small(target) else 0.025))
		_request(target, normal * (18.0 + float(owner.redline_heat) * 25.0), _power_cause(cause, "runaway", int(owner.entity_id)))
		_record("runaway_hit", int(owner.entity_id), int(target.entity_id))
		_fx("runaway_hit", position, normal, float(owner.redline_heat))
	else:
		var restore: float = maxf(0.0, -recoil.dot(Vector2(state.redline_heading))) * 0.20
		if restore > 0.0: _request(owner, Vector2(state.redline_heading) * restore, _power_cause(cause, "redline_recoil", int(owner.entity_id)))
	state.redline_hit = true

func _clutch_recover(fighter: Dictionary) -> void:
	if not _has(fighter, "clutch") or not _live(fighter): return
	var state: Dictionary = _state(fighter)
	var reserve: float = float(fighter.rpm)
	if reserve > 0.36 and time >= float(state.clutch_ready): state.clutch_armed = true
	if reserve <= 0.045 or reserve > 0.28 or not bool(state.clutch_armed) or time < float(state.clutch_ready): return
	state.clutch_armed = false
	var window: float = 6.0 if rank(fighter, "clutch") == 1 else 8.0
	state.clutch_until = time + window
	state.clutch_ready = time + 9.0
	state.clutch_gain_left = 0.09 if rank(fighter, "clutch") == 1 else 0.13
	fighter["clutch_time"] = window
	fighter["clutch_active"] = true
	_record("clutch_activate", int(fighter.entity_id))
	_fx("clutch_activate", fighter.pos, Vector2(fighter.vel).normalized())

func _clutch_contact(owner: Dictionary, target: Dictionary, severity: float, normal: Vector2, position: Vector2) -> void:
	if not _live(owner) or not _has(owner, "clutch") or not bool(owner.get("clutch_active", false)) or float(owner.rpm) <= 0.045 or _small(target) or severity < 0.22: return
	var state: Dictionary = _state(owner)
	# Normal reclamation resolves before semantic power hooks. Eligibility is
	# the dangerous spin at movement/contact approach, not its earned post-hit
	# reserve; otherwise the very hit that catches the top cancels Clutch.
	if float(state.motion_rpm) > 0.30 or float(state.motion_rpm) <= 0.045: return
	if float(state.motion_input) < 0.12 or float(state.motion_speed) < 25.0 or time < float(state.clutch_hit_ready) or time < float(state.clutch_targets.get(int(target.entity_id), 0.0)): return
	state.clutch_hit_ready = time + 0.7
	state.clutch_targets[int(target.entity_id)] = time + 1.4
	var gained: float = _gain(owner, minf(float(state.clutch_gain_left), 0.035 if rank(owner, "clutch") == 1 else 0.055), "clutch")
	if gained <= 0.0: return
	state.clutch_gain_left = maxf(0.0, float(state.clutch_gain_left) - gained)
	owner.energy = owner.rpm
	owner.wobble = maxf(0.0, float(owner.wobble) - 0.04)
	state.clutch_recovery_until = time + 0.8
	owner["clutch_recovery_time"] = 0.8
	_record("clutch_recover", int(owner.entity_id), int(target.entity_id))
	_fx("clutch_recover", position, normal, gained)

## Only a chronological, spatially connected paid route may offer a bridge.
## Preview includes its current connected movement buffer; activation waits
## until that movement is itself emitted as a paid visible trace.
func _modern_circuit(owner: Dictionary, trace_emitted: bool) -> void:
	var state: Dictionary = _state(owner)
	var was_preview: bool = not owner.get("ghost_preview", {}).is_empty()
	owner["ghost_preview"] = {}
	if time < float(state.circuit_ready) or Vector2(owner.vel).length() <= 112.0: return
	var route: Array[Vector2] = []
	var stamps: Array[float] = []
	for trace: Dictionary in traces:
		if int(trace.owner_entity_id) != int(owner.entity_id) or float(trace.created_at) <= float(state.circuit_after): continue
		if not route.is_empty() and route.back().distance_to(Vector2(trace.points[0])) > 26.0:
			route.clear()
			stamps.clear()
		for point: Vector2 in trace.points:
			if route.is_empty() or route.back().distance_to(point) >= 3.0:
				route.append(point)
				stamps.append(float(trace.created_at))
	var current: Array = state.trace_path
	if route.size() < 8 or current.is_empty() or route.back().distance_to(Vector2(current[0])) > 26.0: return
	for point: Vector2 in current:
		if route.back().distance_to(point) >= 3.0:
			route.append(point)
			stamps.append(time)
	while route.size() > CIRCUIT_POINT_LIMIT:
		route.pop_front()
		stamps.pop_front()
	if route.size() < 10 or route.back().distance_to(Vector2(owner.pos)) > 6.0: return
	var candidate: Dictionary = {}
	var best: float = 70.0
	for index: int in range(route.size() - 8):
		if time - stamps[index] < 0.85: continue
		var socket: Vector2 = Geometry2D.get_closest_point_to_segment(owner.pos, route[index], route[index + 1])
		var gap: float = socket.distance_to(Vector2(owner.pos))
		if gap > best: continue
		var polygon: PackedVector2Array = PackedVector2Array([socket])
		polygon.append_array(PackedVector2Array(route.slice(index + 1)))
		var perimeter: float = 0.0
		var signed_area: float = 0.0
		var bounds: Rect2 = Rect2(polygon[0], Vector2.ZERO)
		var center: Vector2 = Vector2.ZERO
		for vertex: int in range(polygon.size()):
			var next: Vector2 = polygon[(vertex + 1) % polygon.size()]
			perimeter += polygon[vertex].distance_to(next)
			signed_area += polygon[vertex].cross(next)
			bounds = bounds.expand(polygon[vertex])
			center += polygon[vertex]
		if perimeter < 180.0 or absf(signed_area) * 0.5 < 1300.0 or bounds.size.x < 32.0 or bounds.size.y < 32.0 or gap / perimeter > 0.22: continue
		best = gap
		candidate = {"socket": socket, "gap": gap, "polygon": polygon, "stamp": stamps[index], "center": center / float(polygon.size())}
	if candidate.is_empty(): return
	owner.ghost_preview = {"a": candidate.socket, "b": Vector2(owner.pos), "strength": clampf(1.0 - float(candidate.gap) / 70.0, 0.0, 1.0), "expires_at": time + 0.2}
	if not was_preview:
		_record("ghost_preview", int(owner.entity_id))
		_fx("ghost_preview", owner.pos, (Vector2(candidate.socket) - Vector2(owner.pos)).normalized())
	if not trace_emitted or float(candidate.gap) > 38.0: return
	state.circuit_ready = time + 3.5
	state.circuit_after = time
	state.circuit_surge_until = time + 0.8
	owner.ghost_preview = {}
	var assigned: bool = false
	for trace: Dictionary in traces:
		if int(trace.owner_entity_id) != int(owner.entity_id): continue
		trace.erase("circuit_points")
		if float(trace.created_at) >= float(candidate.stamp):
			trace.energized = true
			if not assigned:
				trace["circuit_points"] = candidate.polygon
				trace["presentation_circuit_age"] = 0.0
				assigned = true
	var affected: int = 0
	for target: Dictionary in _fighters():
		if affected >= CIRCUIT_TARGET_LIMIT: break
		if not _live(target) or not _opposes(owner, target) or not Geometry2D.is_point_in_polygon(target.pos, candidate.polygon): continue
		affected += 1
		_request(target, _outward(candidate.center, target.pos, Vector2(owner.vel).normalized()) * (110.0 if _small(target) else 88.0), _owned_effect_cause(owner, "ghost_circuit"))
		target.wobble = minf(1.0, float(target.get("wobble", 0.0)) + (0.20 if _small(target) else 0.12))
		_spend(target, 0.018 if _small(target) else 0.012)
		state.trace_hits[int(target.entity_id)] = time + 0.8
		_record("ghost_activation", int(owner.entity_id), int(target.entity_id))
	_record("ghost_closure", int(owner.entity_id))
	_fx("ghost_closure", owner.pos, Vector2(owner.vel).normalized())
	_fx("ghost_activation", candidate.center, Vector2(owner.vel).normalized())
