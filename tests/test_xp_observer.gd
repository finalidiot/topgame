extends SceneTree
## Observe real semantic hooks without modifying physical combat coefficients.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Parts = preload("res://scripts/parts.gd")
const Progression = preload("res://scripts/run_progression.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _battle(slot: int = 1) -> Node2D:
	var battle = Battle.new()
	battle.begin_encounter(Parts.DEFAULT_BUILD, Encounters.for_slot(slot, 421))
	battle.set_physics_process(false)
	battle.battle_status = "battle"
	return battle

func _kind_count(battle: Node2D, kind: String) -> int:
	var count: int = 0
	for event: Dictionary in battle._progression_queue:
		if str(event.kind) == kind: count += 1
	return count

func _run() -> void:
	_test_direct_attribution()
	_test_timeout_presentation()
	_test_power_attribution()
	_test_retirement_and_wave_credit()
	_test_no_passive_observer_xp()
	print("XP_OBSERVER_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)

func _test_direct_attribution() -> void:
	var b: Node2D = _battle()
	b._progression_contact(b.entity(1), b.entity(2), 0.08)
	b.entity(2).outcome = "spin_out"
	b._collect_progression_outcomes()
	check(_kind_count(b, "collision") == 1 and _kind_count(b, "elimination") == 0, "Meaningless contact cannot later credit a passive full-top retirement")
	var progression = Progression.new()
	progression.setup()
	for event: Dictionary in b._progression_queue: progression.record_event(event)
	check(progression.total_xp == 0, "Weak accepted contacts do not bypass XP severity gates")
	b.free()
	b = _battle()
	b._progression_contact(b.entity(2), b.entity(1), 0.8)
	b.entity(2).outcome = "ring_out"
	b._collect_progression_outcomes()
	check(_kind_count(b, "collision") == 1 and _kind_count(b, "elimination") == 1, "Meaningful player contact credits a real rival knockout")
	b._collect_progression_outcomes()
	check(_kind_count(b, "elimination") == 1, "Repeated outcome observation does not duplicate elimination XP")
	var event: Dictionary = b._progression_queue[1]
	check(event.encounter_id == "run_slot_01" and event.time == b.elapsed and event.event_id == 2, "Observer identity and timestamps come from deterministic combat state")
	b.free()

func _test_timeout_presentation() -> void:
	for reason: String in ["timeout", "draw"]:
		var b: Node2D = _battle()
		b._progression_contact(b.entity(1), b.entity(2), 0.8)
		b._finish(b.player_entity_id, reason)
		check(b.entity(2).outcome == "spin_out", "Legacy finish animation still renders a defeated top as spin-out")
		b._collect_progression_outcomes()
		check(_kind_count(b, "elimination") == 0 and _kind_count(b, "collision") == 1, "Timeout/draw cannot turn an animation outcome into a physical XP award")
		b.free()

func _test_power_attribution() -> void:
	var b: Node2D = _battle()
	var cause: Dictionary = {"owner_id":"player", "owner_entity_id":b.player_entity_id, "expires_at":2.0, "kind":"afterimage"}
	b.apply_power_impulse(b.entity(2), Vector2(10.0, 0.0), cause)
	check(Vector2(b.entity(2).vel).is_equal_approx(Vector2(10.0, 0.0)), "Observer attribution preserves the ordinary power impulse")
	check(b.entity(2).get("player_cause", {}).is_empty(), "Full-top credit does not alter small-top propagation state")
	b.entity(2).outcome = "ring_out"
	b._collect_progression_outcomes()
	check(_kind_count(b, "elimination") == 1, "Live player power impulse can credit a rival knockout before direct contact")
	b.free()
	for invalid: Dictionary in [
		{"owner_id":"rival", "owner_entity_id":1, "expires_at":2.0},
		{"owner_id":"player", "owner_entity_id":2, "expires_at":2.0},
		{"owner_id":"player", "owner_entity_id":1, "expires_at":-1.0}]:
		b = _battle()
		b.apply_power_impulse(b.entity(2), Vector2(10.0, 0.0), invalid)
		b.entity(2).outcome = "ring_out"
		b._collect_progression_outcomes()
		check(_kind_count(b, "elimination") == 0, "Rival, mismatched-owner and expired causes cannot award player elimination XP")
		b.free()

func _single_wave(b: Node2D) -> Dictionary:
	b.swarm.total_waves = 1
	b.swarm.wave = 1
	b.swarm.schedule.clear()
	b.swarm.schedule.append({"id":2, "wave":1, "state":"spawned"})
	return b.swarm.add_small(2, Vector2(80.0, 0.0), 1)

func _test_retirement_and_wave_credit() -> void:
	for reason: String in ["natural_retirement", "cleanup", "impact", "ring_out"]:
		var b: Node2D = _battle(3)
		var small: Dictionary = _single_wave(b)
		small.player_cause = {"owner_id":"player", "owner_entity_id":1, "expires_at":2.0}
		small.outcome = reason
		b._collect_progression_outcomes()
		var meaningful: bool = reason in ["impact", "ring_out"]
		check(_kind_count(b, "elimination") == (1 if meaningful else 0), "Only physical, attributed small-top elimination earns XP: %s" % reason)
		check(_kind_count(b, "wave_complete") == (1 if meaningful else 0), "Wave credit requires a physical player elimination: %s" % reason)
		b._collect_progression_outcomes()
		check(_kind_count(b, "wave_complete") == (1 if meaningful else 0), "Repeated complete-wave observation cannot reward twice")
		b.free()
	var b: Node2D = _battle(3)
	var small: Dictionary = _single_wave(b)
	small.player_cause = {"owner_id":"player", "owner_entity_id":1, "expires_at":-1.0}
	small.outcome = "ring_out"
	b._collect_progression_outcomes()
	check(b._progression_queue.is_empty(), "Expired propagation earns neither elimination nor completed-wave XP")
	b.free()

func _test_no_passive_observer_xp() -> void:
	var b: Node2D = _battle(3)
	# Keep the player safely outside the swarm's active population while the
	# actual finite scheduler and natural retirement rules resolve every wave.
	# This isolates observer behavior; it is not a gameplay survival fixture.
	b.player_entity().pos = Vector2.ZERO
	b.player_entity().rpm = 1.0
	var observed: Array[Dictionary] = []
	b.progression_events.connect(func(events: Array) -> void: observed.append_array(events))
	for tick: int in range(1980):
		b.elapsed = float(tick + 1) / 60.0
		b.powers.time = b.elapsed
		b.swarm.begin_tick(Battle.FIXED_DT)
		for fighter: Dictionary in b._ordered_fighters():
			if fighter.combatant_type == "small_top" and str(fighter.outcome).is_empty():
				b.swarm.decide(fighter, Battle.FIXED_DT)
				b.swarm.move(fighter, Battle.FIXED_DT)
		b._collect_progression_outcomes()
	check(b.swarm.clear() and b.swarm.retired == 24, "Actual finite swarm schedule retires all 24 tops without player contact")
	check(b._progression_queue.is_empty() and observed.is_empty(), "Passive natural retirement and scheduler completion produce zero XP events")
	b.free()
