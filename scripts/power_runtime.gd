extends RefCounted
class_name PowerRuntime

## Semantic hooks are called explicitly by battle's fixed tick; presentation
## never feeds back into this runtime. Requests cannot recursively emit contacts.
const WAKE_RADIUS: float = 52.0
const CHAIN_RADIUS: float = 42.0
const CAUSE_SECONDS: float = 1.0
const MAX_CHAIN_GENERATION: int = 2
const MAX_CHAIN_PULSES: int = 12
const MAX_TRACES: int = 3
const TRACE_SECONDS: float = 0.45

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
			"second_wind_used": false, "chain_until": 0.0, "chain_ready": 0.0,
			"chain_target": 0, "chain_cause": {}, "trace_ready": 0.0,
			"trace_origin": Vector2(fighter["pos"]), "trace_path": [Vector2(fighter["pos"])], "trace_hits": {},
			"last_primary_cause": {}}
	return _states[id]

func _has(fighter: Dictionary, power: String) -> bool:
	return power in fighter.get("powers", [])

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
		if was_redline and float(fighter["redline_time"]) <= 0.0 and _live(fighter):
			_fx("redline_release", fighter["pos"], state["redline_heading"])
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

func effective_rpm(fighter: Dictionary) -> float:
	var reserve: float = float(fighter["rpm"])
	return minf(1.15, reserve + 0.35) if redline_active(fighter) else reserve

## Called only after battle accepts Burst and pays its ordinary reserve cost.
func burst_started(fighter: Dictionary, heading: Vector2, pre_cost_rpm: float) -> void:
	if _stopped or not _live(fighter):
		return
	var state: Dictionary = _state(fighter)
	if _has(fighter, "redline") and pre_cost_rpm >= 0.35 and not redline_active(fighter):
		state["redline_until"] = time + 0.8
		state["redline_heading"] = heading.normalized()
		state["redline_hit"] = false
		fighter["redline_time"] = 0.8
		fighter["rpm"] = maxf(0.0, float(fighter["rpm"]) - 0.04)
		fighter["energy"] = fighter["rpm"]
		fighter["wobble"] = minf(1.0, float(fighter["wobble"]) + 0.10)
		_record("redline", int(fighter["entity_id"]))
		_fx("redline", fighter["pos"], heading)
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

## normal is first -> second; recoils are each body's physical velocity delta.
## Capture immutable causes before tagging either body, so storage order cannot
## let one inherited cause overwrite a competing newer cause in the same pair.
func accepted_contact(first: Dictionary, second: Dictionary, severity: float, normal: Vector2, contact_pos: Vector2, recoil_first: Vector2 = Vector2.ZERO, recoil_second: Vector2 = Vector2.ZERO) -> void:
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
	_contact_owner(first, second, severity, normal, contact_pos, recoil_first, event_id)
	_contact_owner(second, first, severity, -normal, contact_pos, recoil_second, event_id)

func _contact_owner(owner: Dictionary, target: Dictionary, severity: float, normal: Vector2, position: Vector2, recoil: Vector2, event_id: int) -> void:
	if _small(owner) or not _opposes(owner, target):
		return
	var state: Dictionary = _state(owner)
	var cause: Dictionary = _direct_cause(owner, event_id)
	if redline_active(owner) and not bool(state["redline_hit"]):
		state["redline_hit"] = true
		var heading: Vector2 = state["redline_heading"]
		var restore: float = maxf(0.0, -recoil.dot(heading)) * 0.20
		if restore > 0.0:
			_request(owner, heading * restore, _power_cause(cause, "redline_recoil", int(owner["entity_id"])))
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
		var position: Vector2 = owner["pos"]
		var path: Array = state["trace_path"]
		if path.is_empty() or Vector2(path.back()) != position:
			path.append(position)
		if path.size() > 16:
			path.pop_front()
		if Vector2(owner["vel"]).length() <= 180.0:
			state["trace_origin"] = position
			state["trace_path"] = [position]
		elif time >= float(state["trace_ready"]) and float(owner["rpm"]) >= 0.002:
			state["trace_ready"] = time + 0.18
			owner["rpm"] = maxf(0.0, float(owner["rpm"]) - 0.002)
			owner["energy"] = owner["rpm"]
			var start: Vector2 = path.front()
			var direction: Vector2 = _outward(start, position, Vector2(owner["vel"]).normalized())
			var trace: Dictionary = {"a": start, "b": position, "points": path.duplicate(), "direction": direction,
				"owner_entity_id": int(owner["entity_id"]), "owner_id": str(owner["owner_id"]), "team_id": str(owner["team_id"]),
				"created_at": time, "expires_at": time + TRACE_SECONDS, "life": TRACE_SECONDS, "max_life": TRACE_SECONDS,
				"cause": _owned_effect_cause(owner, "afterimage")}
			traces.append(trace)
			state["trace_origin"] = position
			state["trace_path"] = [position]
			var owned_count: int = 0
			for active: Dictionary in traces:
				if int(active["owner_entity_id"]) == int(owner["entity_id"]):
					owned_count += 1
			if owned_count > MAX_TRACES:
				for index: int in range(traces.size()):
					if int(traces[index]["owner_entity_id"]) == int(owner["entity_id"]):
						traces.remove_at(index)
						break
			_record("afterimage", int(owner["entity_id"]))
			_fx("afterimage", position, direction)
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
			if sqrt(nearest_distance) > 8.0 + float(target.get("radius", 0.0)):
				continue
			var lateral: Vector2 = Vector2(-direction.y, direction.x)
			if (Vector2(target["pos"]) - nearest).dot(lateral) < 0.0:
				lateral = -lateral
			hit_times[int(target["entity_id"])] = time + 0.6
			_request(target, lateral * (40.0 if _small(target) else 12.0), _power_cause(trace["cause"], "afterimage", int(owner["entity_id"])))
			_record("afterimage_hit", int(owner["entity_id"]), int(target["entity_id"]))

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
		fighter["rpm"] = minf(1.0, float(fighter["rpm"]) + minf(0.18, maxf(0.0, 0.40 - reserve)))
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
