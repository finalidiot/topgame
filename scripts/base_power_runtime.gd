extends RefCounted
## Fresh scalar queries: no catalogue mutation and no RPM grants.
const Seeds = preload("res://scripts/seed_utils.gd")
const IDS: Array[String] = ["crimson_impact", "azure_stability", "emerald_endurance", "true_bearing", "last_stand", "prismatic_current"]
const STATES: Array[String] = ["IMPACT", "SPEED", "STABILITY", "EFFICIENCY"]
const PERIOD: float = 8.0
var states: Dictionary = {}
var seed_value: int = 0
var time: float = 0.0
var stopped: bool = false

func setup(seed: int) -> void:
	seed_value = seed
	time = 0.0
	stopped = false
	states.clear()

func rank(f: Dictionary, id: String) -> int:
	if stopped or not str(f.get("outcome", "")).is_empty() or id not in f.get("powers", []): return 0
	return clampi(int(f.get("power_ranks", {}).get(id, 1)), 1, 2)

func _state(f: Dictionary) -> Dictionary:
	var id: int = int(f.entity_id)
	if not states.has(id):
		var rng := RandomNumberGenerator.new()
		rng.seed = Seeds.derive(seed_value, "prismatic:%d" % id)
		states[id] = {"rng":rng, "emphasis":rng.randi_range(0, 3), "next":time + PERIOD, "changes":0}
	return states[id]

func register(f: Dictionary) -> void:
	if rank(f, "prismatic_current") > 0:
		var s: Dictionary = _state(f)
		f["prismatic_state"] = int(s.emphasis)

func begin_tick(fighters: Array[Dictionary], dt: float) -> void:
	if stopped: return
	time += maxf(0.0, dt)
	var live_ids: Dictionary = {}
	for f: Dictionary in fighters:
		if rank(f, "prismatic_current") == 0:
			f.erase("prismatic_state")
			continue
		live_ids[int(f.entity_id)] = true
		var s: Dictionary = _state(f)
		# Canonical fixed ticks cannot skip a period. Bound abnormal injected
		# deltas to one change and rebase: no backlog and no per-frame rerolls.
		if time + 0.000001 >= float(s.next):
			s.emphasis = (int(s.emphasis) + 1 + s.rng.randi_range(0, 2)) % 4
			s.next = time + PERIOD
			s.changes = int(s.changes) + 1
		f["prismatic_state"] = int(s.emphasis)
	for id: int in states.keys():
		if not live_ids.has(id): states.erase(id)

func emphasis(f: Dictionary) -> int:
	return int(states.get(int(f.entity_id), {}).get("emphasis", -1)) if rank(f, "prismatic_current") > 0 else -1

func attack(f: Dictionary) -> float:
	var crimson: int = rank(f, "crimson_impact")
	var prism: int = rank(f, "prismatic_current")
	var value: float = 1.0 if crimson == 0 else (1.08 if crimson == 1 else 1.14)
	if prism > 0 and emphasis(f) == 0: value *= 1.06 if prism == 1 else 1.10
	return clampf(value, 1.0, 1.30)

func displacement(f: Dictionary) -> float:
	var azure: int = rank(f, "azure_stability")
	return 1.0 if azure == 0 else (0.94 if azure == 1 else 0.89)

func wobble(f: Dictionary) -> float:
	var azure: int = rank(f, "azure_stability")
	var stand: int = rank(f, "last_stand")
	var prism: int = rank(f, "prismatic_current")
	var value: float = 1.0 if azure == 0 else (0.90 if azure == 1 else 0.82)
	if stand > 0 and float(f.get("rpm", 1.0)) < 0.35: value *= 0.86 if stand == 1 else 0.76
	if prism > 0 and emphasis(f) == 2: value *= 0.91 if prism == 1 else 0.85
	return clampf(value, 0.50, 1.0)

func movement(f: Dictionary, m: Dictionary) -> void:
	var emerald: int = rank(f, "emerald_endurance")
	var bearing: int = rank(f, "true_bearing")
	var prism: int = rank(f, "prismatic_current")
	var drain: float = 1.0 if emerald == 0 else (0.94 if emerald == 1 else 0.90)
	if prism > 0 and emphasis(f) == 3: drain *= 0.95 if prism == 1 else 0.92
	m.drain = float(m.drain) * clampf(drain, 0.80, 1.0)
	if bearing > 0: m.recovery = float(m.get("recovery", 1.0)) * (1.16 if bearing == 1 else 1.28)
	if prism > 0 and emphasis(f) == 1: m.speed = float(m.speed) * (1.05 if prism == 1 else 1.08)

func snapshot(f: Dictionary) -> Dictionary:
	var prism: int = rank(f, "prismatic_current")
	var result: Dictionary = {"owned":prism > 0, "attack":attack(f), "incoming_wobble":wobble(f), "displacement":displacement(f), "last_stand_active":rank(f, "last_stand") > 0 and float(f.get("rpm", 1.0)) < 0.35}
	if prism > 0 and states.has(int(f.entity_id)):
		var s: Dictionary = states[int(f.entity_id)]
		var bonus: Array = ["IMP +6", "SPD +5", "WBL -9", "DRN -5"] if prism == 1 else ["IMP +10", "SPD +8", "WBL -15", "DRN -8"]
		result.merge({"emphasis":STATES[int(s.emphasis)], "bonus_label":bonus[int(s.emphasis)], "state":int(s.emphasis), "remaining":maxf(0.0, float(s.next) - time), "changes":int(s.changes), "rng_state":str(s.rng.state)})
	return result

func finish(fighters: Array[Dictionary]) -> void:
	stopped = true
	states.clear()
	for f: Dictionary in fighters: f.erase("prismatic_state")
