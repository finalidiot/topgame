extends RefCounted
class_name RunProgression

## All progression tuning lives here. Costs are incremental: the opening power
## is free, then five earned levels fill this slice's six functional power pool.
## No clock tick awards XP; combat supplies immutable events using live time.
const TUNING: Dictionary = {
	"level_costs": [18, 22, 36, 56, 84],
	"collision_min_severity": 0.22,
	"collision_heavy_severity": 0.50,
	"collision_xp": 2,
	"heavy_collision_xp": 4,
	"collision_pair_cooldown": 1.15,
	"collision_global_cooldown": 0.30,
	"full_elimination_xp": 18,
	"small_elimination_xp": 3,
	"wave_completion_xp": 6
}

var level: int = 1
var xp: int = 0
var total_xp: int = 0
var last_award: int = 0
var _tuning: Dictionary = TUNING.duplicate(true)
var _max_level: int = 6
var _seen_events: Dictionary = {}
var _seen_eliminations: Dictionary = {}
var _seen_waves: Dictionary = {}
var _pair_awards: Dictionary = {}
var _last_collision_awards: Dictionary = {}
var _last_event_times: Dictionary = {}

func setup(power_count: int = 6, tuning: Dictionary = {}) -> void:
	clear()
	_max_level = maxi(1, power_count)
	_tuning = TUNING.duplicate(true)
	_tuning.merge(tuning.duplicate(true), true)

func clear() -> void:
	level = 1
	xp = 0
	total_xp = 0
	last_award = 0
	_seen_events.clear()
	_seen_eliminations.clear()
	_seen_waves.clear()
	_pair_awards.clear()
	_last_collision_awards.clear()
	_last_event_times.clear()

func threshold() -> int:
	if is_maxed(): return 0
	var costs: Array = _tuning.level_costs
	if costs.is_empty(): return 1
	return maxi(1, int(costs[mini(level - 1, costs.size() - 1)]))

func is_maxed() -> bool:
	return level >= _max_level

func snapshot() -> Dictionary:
	var next_cost: int = threshold()
	return {"level":level, "xp":xp, "total_xp":total_xp,
		"threshold":next_cost, "fraction":1.0 if is_maxed() else float(xp) / float(next_cost),
		"maxed":is_maxed(), "earned_levels":level - 1, "last_award":last_award}

## Returns the levels newly crossed, in order. A large meaningful award retains
## its overflow and queues every entitlement; presentation does not consume RNG.
func record_event(event: Dictionary) -> Array[int]:
	last_award = 0
	var crossed: Array[int] = []
	if is_maxed(): return crossed
	var encounter_id: String = str(event.get("encounter_id", ""))
	var time: float = float(event.get("time", -1.0))
	if encounter_id.is_empty() or not is_finite(time) or time < 0.0: return crossed
	if time + 0.000001 < float(_last_event_times.get(encounter_id, -1.0)): return crossed
	var kind: String = str(event.get("kind", ""))
	if kind not in ["collision", "elimination", "wave_complete"]: return crossed
	if not _player_attributed(event, time): return crossed
	var identity: String = _event_key(event, encounter_id, kind, time)
	if identity.is_empty() or _seen_events.has(identity): return crossed
	_seen_events[identity] = true
	_last_event_times[encounter_id] = time
	last_award = _event_xp(event, encounter_id, kind, time)
	if last_award <= 0: return crossed
	total_xp += last_award
	xp += last_award
	while not is_maxed() and xp >= threshold():
		xp -= threshold()
		level += 1
		crossed.append(level)
	if is_maxed(): xp = 0
	return crossed

func _player_attributed(event: Dictionary, time: float) -> bool:
	if event.has("player_attributed"): return bool(event.player_attributed)
	var cause: Dictionary = event.get("cause", {})
	return str(cause.get("owner_id", "")) == "player" and float(cause.get("expires_at", -1.0)) >= time

func _event_key(event: Dictionary, encounter_id: String, kind: String, time: float) -> String:
	if event.has("event_id"):
		return "%s/event/%s" % [encounter_id, str(event.event_id)]
	match kind:
		"collision":
			var pair: String = _pair_key(event)
			return "" if pair.is_empty() else "%s/contact/%s/%d" % [encounter_id, pair, roundi(time * 1000000.0)]
		"elimination": return "%s/elimination/%d" % [encounter_id, int(event.get("entity_id", -1))]
		"wave_complete": return "%s/wave/%d" % [encounter_id, int(event.get("wave", -1))]
	return ""

func _pair_key(event: Dictionary) -> String:
	var first: int = int(event.get("first_entity_id", -1))
	var second: int = int(event.get("second_entity_id", -1))
	if first < 0 or second < 0 or first == second: return ""
	return "%d:%d" % [mini(first, second), maxi(first, second)]

func _event_xp(event: Dictionary, encounter_id: String, kind: String, time: float) -> int:
	match kind:
		"collision":
			var severity: float = float(event.get("severity", 0.0))
			var pair: String = _pair_key(event)
			if pair.is_empty() or not is_finite(severity) or severity < float(_tuning.collision_min_severity): return 0
			var pair_id: String = encounter_id + "/" + pair
			if time - float(_pair_awards.get(pair_id, -1000.0)) + 0.000001 < float(_tuning.collision_pair_cooldown): return 0
			if time - float(_last_collision_awards.get(encounter_id, -1000.0)) + 0.000001 < float(_tuning.collision_global_cooldown): return 0
			_pair_awards[pair_id] = time
			_last_collision_awards[encounter_id] = time
			return int(_tuning.heavy_collision_xp if severity > float(_tuning.collision_heavy_severity) else _tuning.collision_xp)
		"elimination":
			var combatant_type: String = str(event.get("combatant_type", ""))
			var reason: String = str(event.get("reason", ""))
			if reason not in ["ring_out", "spin_out"] and not (reason == "impact" and combatant_type == "small_top"): return 0
			var entity_id: int = int(event.get("entity_id", -1))
			var elimination_id: String = "%s/%d" % [encounter_id, entity_id]
			if entity_id < 0 or _seen_eliminations.has(elimination_id): return 0
			if combatant_type not in ["full_top", "small_top"]: return 0
			_seen_eliminations[elimination_id] = true
			return int(_tuning.small_elimination_xp if combatant_type == "small_top" else _tuning.full_elimination_xp)
		"wave_complete":
			var wave: int = int(event.get("wave", -1))
			var wave_id: String = "%s/%d" % [encounter_id, wave]
			if wave < 1 or _seen_waves.has(wave_id): return 0
			_seen_waves[wave_id] = true
			return int(_tuning.wave_completion_xp)
	return 0
