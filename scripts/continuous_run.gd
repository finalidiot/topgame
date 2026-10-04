extends RefCounted
## Task 002C.1 validation scaffolding. Owns threat lifecycle, not player physics.
const Encounters = preload("res://scripts/encounters.gd")
# Temporary testing economy. Scale net player reserve expenditure per fixed tick;
# no refill/heal at transitions. Replace this one setting in Task 002C.3.
const TUNING: Dictionary = {"player_rpm_loss_scale":0.12, "breathing_seconds":2.0, "corpse_seconds":0.65}
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

func setup(host: Node2D, seed_value: int) -> void:
	_host = weakref(host)
	run_seed = seed_value
	threat_number = int(host.encounter.slot)
	# First threat reserves the IDs already admitted by begin_encounter.
	for f: Dictionary in host.fighters: next_entity_id = maxi(next_entity_id, int(f.entity_id) + 1)
	for entry: Dictionary in host.swarm.schedule: next_entity_id = maxi(next_entity_id, int(entry.id) + 1)

func host() -> Node2D:
	return _host.get_ref()

func threat_elapsed() -> float:
	return maxf(0.0, host().elapsed - threat_started_at)

func apply_testing_rpm(previous_rpm: float) -> void:
	var player: Dictionary = host().player_entity()
	var spent: float = maxf(0.0, previous_rpm - float(player.rpm))
	player.rpm = float(player.rpm) + spent * (1.0 - float(TUNING.player_rpm_loss_scale))
	player.energy = player.rpm

func observe_outcomes() -> void:
	for f: Dictionary in host().fighters:
		if f.team_id != "hostile" or str(f.outcome).is_empty() or _counted.has(int(f.entity_id)): continue
		_counted[int(f.entity_id)] = true
		if f.outcome in ["ring_out", "spin_out", "impact"]:
			if f.combatant_type == "full_top": rivals_defeated += 1
			elif str(host().powers.cause_for(f).get("owner_id", "")) == "player": small_enemies_defeated += 1

func after_tick(dt: float) -> void:
	var b: Node2D = host()
	observe_outcomes()
	if b.paused or b.battle_status != "battle": return
	if phase == "active":
		var resolved: bool = b.swarm.clear() if b.swarm.enabled else not _has_hostiles()
		if resolved:
			phase = "breathing"
			next_at = b.elapsed + float(TUNING.breathing_seconds)
			threats_cleared += 1
			b.threat_cleared.emit({"id":b.encounter.id, "seed":b.encounter.seed, "run_seed":run_seed, "threat":threat_number})
	elif b.elapsed + 0.000001 >= next_at:
		_spawn_next()
	_cleanup(dt)

func _has_hostiles() -> bool:
	for f: Dictionary in host().fighters:
		if f.team_id == "hostile" and str(f.outcome).is_empty(): return true
	return false

func _spawn_next() -> void:
	var b: Node2D = host()
	var descriptor: Dictionary = Encounters.for_slot(threat_number + 1, run_seed)
	var position: Vector2 = Vector2.ZERO
	if descriptor.fixture_type != "swarm":
		# Pick the furthest safe entry deterministically, never on the player.
		var distance: float = -1.0
		for point: Vector2 in ENTRY_POINTS:
			var candidate: float = point.distance_to(b.player_entity().pos)
			if candidate > distance: distance = candidate; position = point
		if distance < 60.0: return
	descriptor["first_entity_id"] = next_entity_id
	next_entity_id += 24 if descriptor.fixture_type == "swarm" else 1
	threat_number += 1
	threat_started_at = b.elapsed
	phase = "active"
	_counted.clear()
	b.enter_threat(descriptor, position)
	b.threat_started.emit({"id":descriptor.id, "seed":descriptor.seed, "run_seed":run_seed, "threat":threat_number})

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
	for id: int in retired: b.remove_retired_enemy(id)
	b.powers.prune_retired_state()

func snapshot() -> Dictionary:
	return {"run_seed":run_seed, "survival_time":host().elapsed, "threat_number":threat_number,
		"phase":phase, "threats_cleared":threats_cleared, "rivals_defeated":rivals_defeated,
		"small_enemies_defeated":small_enemies_defeated, "next_at":next_at,
		"next_entity_id":next_entity_id, "threat_started_at":threat_started_at}
