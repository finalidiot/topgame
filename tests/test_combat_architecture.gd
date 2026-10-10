extends SceneTree
## Godot --headless --path . --script res://tests/test_combat_architecture.gd
## Multi-top fixtures exercise infrastructure only; they are not Run content.
const Battle = preload("res://scripts/battle.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: " + label)

func _build(blade: String = "balance", ratchet: String = "mid", bit: String = "ball") -> Dictionary:
	return {"blade": blade, "ratchet": ratchet, "bit": bit}

func _battle() -> Node2D:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.begin(_build(), _build("hook", "low", "flat"), 1, 421)
	battle.battle_status = "battle"
	return battle

func _physical(battle: Node2D) -> Dictionary:
	var state: Dictionary = battle.snapshot()
	for fighter: Dictionary in state.entities.values():
		# Art phase may differ; all physical and AI state must remain identical.
		fighter.erase("phase")
	state.erase("player")
	state.erase("enemy")
	return state

func _run() -> void:
	_test_identity_and_order()
	_test_pairs()
	_test_overlap()
	_test_launch_ai_and_target()
	_test_results()
	_test_descriptor_reset()
	_test_cosmetic_independence()
	print("Combat architecture: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_identity_and_order() -> void:
	var forward: Node2D = _battle()
	var reversed: Node2D = _battle()
	for battle: Node2D in [forward, reversed]:
		battle.add_full_top(_build("guard"), 7, "hostile", "rival_2", Vector2(35, 70))
	reversed.fighters.reverse()
	_check(reversed.player_entity().entity_id == 1 and reversed.fighters[0].team_id == "hostile", "Player ownership survives reversed storage order")
	_check(not reversed.add_full_top(_build(), 1, "hostile", "duplicate", Vector2.ZERO), "Duplicate entity ID is rejected")
	var hud: Dictionary = {}
	reversed.hud_updated.connect(func(stats: Dictionary) -> void: hud.assign(stats))
	reversed._emit_hud()
	_check(hud.player_entity_id == 1 and hud.enemy_entity_id == 2, "HUD finds entities by identity")
	for frame: int in range(300):
		var direction: Vector2 = Vector2(sin(float(frame) * 0.09), cos(float(frame) * 0.11))
		forward.test_step(Battle.FIXED_DT, direction, frame % 160 == 0, frame % 80 > 65)
		reversed.test_step(Battle.FIXED_DT, direction, frame % 160 == 0, frame % 80 > 65)
	_check(_physical(forward) == _physical(reversed), "Recorded input, multiple AI, collision and physics ignore array order")
	_check(forward.entity(1).combatant_type == "full_top" and forward.entity(2).owner_id == "rival_1", "Combatant category and owner are explicit")
	forward.free()
	reversed.free()

func _prepare_pair(battle: Node2D, first: int, second: int, center: Vector2) -> void:
	battle.test_set_entity_state(first, {"pos": center - Vector2(10, 0), "vel": Vector2(120, 0), "rpm": 0.95})
	battle.test_set_entity_state(second, {"pos": center + Vector2(10, 0), "vel": Vector2(-120, 0), "rpm": 0.95})

func _test_pairs() -> void:
	var battle: Node2D = _battle()
	battle.add_full_top(_build("guard"), 8, "player", "ally", Vector2(10, 70))
	battle.add_full_top(_build("smash"), 19, "hostile", "rival_2", Vector2(30, 70))
	_prepare_pair(battle, 1, 2, Vector2(0, -65))
	_prepare_pair(battle, 8, 19, Vector2(0, 65))
	var bystander: Dictionary = battle.entity(8).duplicate(true)
	var accepted: Array = []
	var audio: Array[String] = []
	battle.contact_accepted.connect(func(first: int, second: int) -> void: accepted.append([first, second]))
	battle.event_sfx.connect(func(kind: String) -> void: audio.append(kind))
	battle.resolve_pair(2, 1)
	_check(battle.entity(8) == bystander, "Impact changes no bystander RPM, velocity, wobble or bounce")
	_check(accepted == [[1, 2]], "Accepted contact reports canonical entity IDs")
	var first_rpm: float = battle.entity(1).rpm
	battle.resolve_pair(19, 8)
	_check(battle.hits == 2 and battle.entity(8).rpm < 0.95 and battle.entity(19).rpm < 0.95, "Two independent pairs damage both sides on the same tick")
	var presentations: Array = battle.impact_feedback.snapshot().events
	_check(accepted == [[1, 2], [8, 19]] and audio.size() == 2 and presentations.size() == 2 and float(presentations[0].hold) > 0.0 and float(presentations[1].hold) == 0.0, "Every accepted pair gets sparks/audio intent while the secondary theatre cooldown prevents repeated holds")
	_check(battle.entity(1).rpm == first_rpm, "Second pair does not change the first pair")
	var prior_rpm: float = battle.entity(8).rpm
	battle.test_set_entity_state(8, {"pos": Vector2(-10, 65), "vel": Vector2(120, 0)})
	battle.test_set_entity_state(19, {"pos": Vector2(10, 65), "vel": Vector2(-120, 0)})
	battle.resolve_pair(8, 19)
	_check(battle.entity(8).rpm == prior_rpm and battle.hits == 2, "Repeated same-pair contact respects its damage cooldown")
	_check(battle.entity(8).vel.x < 0, "Pair cooldown retains the baseline separation and impulse response")
	# A pair sharing one participant also remains valid during another cooldown.
	battle.test_set_entity_state(1, {"pos": Vector2(-10, 0), "vel": Vector2(120, 0)})
	battle.test_set_entity_state(19, {"pos": Vector2(10, 0), "vel": Vector2(-120, 0)})
	battle.resolve_pair(1, 19)
	_check(battle.hits == 3 and battle.entity(1).rpm < first_rpm, "Shared participant does not turn pair cooldown into entity cooldown")
	battle.free()

func _test_overlap() -> void:
	var first: Node2D = _battle()
	var second: Node2D = _battle()
	second.fighters.reverse()
	for battle: Node2D in [first, second]:
		battle.test_set_entity_state(1, {"pos": Vector2.ZERO, "vel": Vector2(40, 0)})
		battle.test_set_entity_state(2, {"pos": Vector2.ZERO, "vel": Vector2(-40, 0)})
	first.resolve_pair(1, 2)
	second.resolve_pair(2, 1)
	_check(_physical(first) == _physical(second), "Exact-overlap normal is deterministic with reversed pair and array")
	_check(first.entity(1).pos.is_finite() and first.entity(2).pos.distance_to(first.entity(1).pos) > 24.0, "Exact overlap separates finite full tops")
	first.free()
	second.free()

func _test_launch_ai_and_target() -> void:
	var battle: Node2D = _battle()
	battle.add_full_top(_build("guard"), 7, "hostile", "rival_2", Vector2(15, 65), Vector2(-25, -30))
	battle.fighters.reverse()
	battle.battle_status = "launch"
	battle._launch_time = 0.44
	battle.test_step(Battle.FIXED_DT)
	_check(battle.entity(1).vel == Vector2(64, -26) and battle.entity(2).vel == Vector2(-64, 26) and battle.entity(7).vel == Vector2(-25, -30), "Every full top launches from its explicit spawn velocity")
	battle.test_step(Battle.FIXED_DT)
	_check(battle.entity(2).ai_direction.length() > 0.1 and battle.entity(7).ai_direction.length() > 0.1, "Each rival owns active AI steering state")
	_check(battle.entity(2).ai_clock != battle.entity(7).ai_clock, "Rivals use independent deterministic AI streams")
	_check(battle._target_for(battle.entity(7)).entity_id == 1, "AI targets an opposing team instead of adjacent array entry")
	battle.add_full_top(_build(), 33, "neutral", "environment", Vector2.ZERO)
	_check(battle._target_for(battle.entity(33)).is_empty(), "Neutral ownership does not accidentally target player")
	battle.test_set_entity_state(1, {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "cooldown": 0.0})
	battle.test_set_entity_state(2, {"pos": Vector2(90, 0)})
	battle.test_set_entity_state(7, {"pos": Vector2(0, 40)})
	battle._attempt_burst(battle.entity(1), Vector2.ZERO)
	_check(battle.entity(1).vel.y > 60.0 and absf(battle.entity(1).vel.x) < 0.001, "Zero-input Burst aims at the nearest opposing live entity")
	_check(battle.snapshot().entities.size() == 4, "Snapshot includes every entity by stable ID")
	battle.free()

func _test_results() -> void:
	var battle: Node2D = _battle()
	battle.add_full_top(_build(), 9, "hostile", "rival_2", Vector2(60, 60))
	battle.fighters.reverse()
	battle.test_set_entity_state(2, {"rpm": 0.02})
	battle._check_result()
	_check(battle.battle_status == "battle", "Eliminating one rival does not finish while its teammate survives")
	battle.test_set_entity_state(9, {"rpm": 0.02})
	battle._check_result()
	_check(battle.last_result.won and battle.last_result.winner_entity_id == 1 and battle.last_result.winner_team_id == "player", "Team elimination commits identity-based player victory")
	var committed: Dictionary = battle.last_result.duplicate(true)
	battle.test_set_entity_state(1, {"rpm": 0.0})
	battle._check_result()
	_check(battle.last_result == committed, "Result cannot commit twice")
	var notifications: Array = []
	battle.round_finished.connect(func(result: Dictionary) -> void: notifications.append(result))
	for frame: int in range(240):
		battle.test_step(Battle.FIXED_DT)
	_check(notifications.size() == 1, "Generalized result emits once after finish presentation")
	_prepare_pair(battle, 1, 2, Vector2.ZERO)
	battle.test_set_entity_state(1, {"outcome": ""})
	battle.test_set_entity_state(2, {"outcome": ""})
	var after_finish: Dictionary = battle.snapshot()
	battle.resolve_pair(1, 2)
	_check(battle.snapshot() == after_finish, "A late contact callback cannot mutate a finished encounter")
	battle.free()
	var timeout: Node2D = _battle()
	timeout.add_full_top(_build(), 9, "hostile", "rival_2", Vector2(60, 60))
	timeout.test_set_entity_state(1, {"rpm": 0.7})
	timeout.test_set_entity_state(2, {"rpm": 0.99, "outcome": "ring_out"})
	timeout.test_set_entity_state(9, {"rpm": 0.6})
	timeout.elapsed = 60.0
	timeout._check_result()
	_check(timeout.last_result.won and timeout.last_result.reason == "timeout", "Timeout never awards victory to an already eliminated high-RPM entity")
	timeout.free()
	var ring: Node2D = _battle()
	ring.fighters.reverse()
	ring.test_set_entity_state(1, {"pos": Vector2(140, -140), "vel": Vector2(60, -60)})
	ring.test_step(Battle.FIXED_DT)
	_check(not ring.last_result.won and ring.last_result.winner_entity_id == 2 and ring.last_result.reason == "ring_out", "Ring-out result ignores backing array order")
	ring.free()

func _test_descriptor_reset() -> void:
	var battle: Node2D = _battle()
	_prepare_pair(battle, 1, 2, Vector2.ZERO)
	battle.resolve_pair(1, 2)
	battle.begin_encounter(_build(), {"id": "fixture_4", "opponent_build": _build(), "seed": 12345, "difficulty": 2, "live_time_limit": 0.1, "run_power_ids": ["impact_wake"]})
	_check(battle.entity(1).rpm == 1.0 and battle.entity(1).wobble == 0.0 and battle.entity(1).cooldown == 0.0 and battle._pair_cooldowns.is_empty(), "New encounter resets RPM, wobble, Burst, cooldown and pair state")
	battle.battle_status = "battle"
	for frame: int in range(10):
		battle.test_step(Battle.FIXED_DT)
	_check(battle.last_result.reason == "timeout" and battle.last_result.encounter_id == "fixture_4" and battle.last_result.seed == 12345, "Encounter descriptor controls limit and tags committed result")
	battle.begin(_build(), _build(), 1, 12345)
	_check(battle.live_time_limit == 60.0 and battle.encounter.get("id", "").is_empty() and battle.fighters.size() == 2, "Quick Duel resets descriptor and remains an ordinary duel")
	battle.begin_encounter(_build(), {"opponent_build": _build(), "seed": 0})
	var zero_seed_state: Dictionary = battle.snapshot()
	battle.begin_encounter(_build(), {"opponent_build": _build(), "seed": 0})
	_check(battle.seed_value == 0 and battle.snapshot() == zero_seed_state, "Explicit seed zero is deterministic and never replaced by wall-clock timing")
	battle.free()

func _test_cosmetic_independence() -> void:
	var normal: Node2D = _battle()
	var altered: Node2D = _battle()
	altered.screen_shake_enabled = false
	var identical: bool = true
	var completed: bool = false
	for frame: int in range(5000):
		# Different particle counts, stream consumption and settings cannot move
		# a future AI decision or physical result even one fixed tick.
		altered._spawn_sparks(Vector2.ZERO, Vector2.RIGHT, frame % 11, 0.5)
		altered.particles_enabled = frame % 2 == 0
		var direction: Vector2 = Vector2(sin(float(frame) * 0.09), cos(float(frame) * 0.04))
		normal.test_step(Battle.FIXED_DT, direction, frame % 250 == 0, frame % 100 > 80)
		altered.test_step(Battle.FIXED_DT, direction, frame % 250 == 0, frame % 100 > 80)
		identical = identical and _physical(normal) == _physical(altered)
		if normal.battle_status == "finished":
			completed = true
			break
	_check(identical, "Cosmetic RNG consumption and reduced particles preserve every physical and AI tick")
	_check(completed and normal.last_result == altered.last_result, "Same seed and recorded input produce identical completed result with changed cosmetics")
	normal.free()
	altered.free()
