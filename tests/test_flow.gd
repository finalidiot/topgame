extends SceneTree
# Screen and ownership integration uses controlled result/XP fixtures. Actual
# combat pacing and power outcomes are separately measured by playthrough tests.

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void:
		pass

const Fixtures = preload("res://tests/continuous_fixtures.gd")
const SELECTED_BUILD: Dictionary = {"blade":"guard", "ratchet":"low", "bit":"needle"}
const Starters = preload("res://scripts/starters.gd")
const Physics = preload("res://scripts/battle.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _finish_reentry(game: QuietMain) -> void:
	var ticks: int = 0
	while game.battle.battle_status == "reentry" and ticks < 91:
		game.battle.test_step(Physics.FIXED_DT)
		ticks += 1
	check(game.battle.battle_status == "battle", "Ready buffer ends through actual fixed ticks before any live physics")

func _state(game: QuietMain) -> Dictionary:
	var context = game.run_context
	return {"slot":context.slot, "seed":context.run_seed, "build":context.selected_build,
		"powers":context.owned_power_ids, "offer":context.pending_offer,
		"ranks":context.power_ranks, "mutations":context.power_mutations,
		"mutation_power":context.pending_mutation_power, "mutation_offer":context.pending_mutation_offer,
		"draft":context.pending_draft_id, "kind":context.pending_draft_kind,
		"results":context.committed_results, "rewards":context.committed_rewards,
		"starter":context.starter_id, "progress":context.progression_snapshot(), "status":context.status}

func _result(game: QuietMain, won: bool = true) -> Dictionary:
	var encounter: Dictionary = game.run_context.current_encounter()
	return {"won":won, "reason":"ring_out" if won else "spin_out", "duration":29.0, "hits":8,
		"encounter_id":encounter.id, "seed":encounter.seed}

func _choice(game: QuietMain, power_id: String) -> Dictionary:
	return {"encounter_id":game.run_context.pending_draft_id,
		"power_id":power_id, "run_seed":game.run_context.run_seed}

func _claim(game: QuietMain) -> void:
	game._action("choose_power", _choice(game, str(game.run_context.pending_offer[0])))
	game._process(0.6)

func _start_custom(game: QuietMain) -> void:
	game._action("start_run")
	check(game.screen == "reward", "Owned assembly enters its opening power draft without another starter choice")
	check(game.screen == "reward" and game.run_context.pending_draft_kind == "starting", "Secondary custom Run also chooses a power before combat")
	_claim(game)
	check(game.screen == "battle" and game.run_context.owned_power_ids.size() == 1, "Opening acquisition launches already powered")

func _check_restart(game: QuietMain, old_seed: int, expected_starter: String = "custom") -> void:
	check(game.screen == "reward" and game.run_context.slot == 1 and game.run_context.status == "active", "Restart returns to opening power choice")
	check(game.run_context.run_seed != old_seed and game.run_context.starter_id == expected_starter, "Restart gives a fresh seed and keeps chosen identity")
	check(game.run_context.owned_power_ids.is_empty() and game.run_context.pending_offer.size() == 3, "Restart clears ownership and prepares three starting cards")
	check(game.run_context.level == 1 and game.run_context.xp == 0 and game.run_context.committed_results.is_empty() and game.run_context.committed_rewards.is_empty(), "Restart clears all XP and commitments")
	check(not game.battle.visible and game.battle.paused, "Restart safely hides previous combat during the opening draft")

func _check_cleared(game: QuietMain) -> void:
	check(game.run_context.status == "empty" and game.run_context.slot == 0, "Exit clears the Run")
	check(game.run_context.owned_power_ids.is_empty() and game.run_context.pending_offer.is_empty(), "Exit clears powers and offers")
	check(game.run_context.committed_results.is_empty() and game.run_context.committed_rewards.is_empty(), "Exit clears all claims and results")
	check(not game.battle.visible and game.battle.paused, "Exit hides and stops combat")

func _physical_state(game: QuietMain) -> Dictionary:
	var entities: Dictionary = {}
	for fighter: Dictionary in game.battle.fighters:
		var physical: Dictionary = fighter.duplicate(true)
		physical.erase("powers")
		physical.erase("power_ranks")
		physical.erase("power_mutations")
		entities[int(fighter.entity_id)] = physical
	return {"entities":entities, "elapsed":game.battle.elapsed, "status":game.battle.battle_status,
		"swarm":game.battle.swarm.telemetry(), "runtime":game.battle.powers._states.duplicate(true)}

func _earn_level(game: QuietMain) -> void:
	var events: Array[Dictionary] = []
	# Eight distinct credited small knockouts in one fixed tick are a plausible
	# chain/wave event batch. This is a controlled screen-flow fixture.
	for index: int in range(8):
		events.append({"kind":"elimination", "encounter_id":game.run_context.current_encounter().id,
			"time":game.battle.elapsed, "event_id":100000 + index,
			"entity_id":100000 + index, "combatant_type":"small_top", "reason":"impact", "player_attributed":true})
	game._progression_events(events)
	check(game.screen == "level_up" and game.battle.paused, "Earned threshold pauses immediately with a level-up hit")
	game._process(0.2)
	check(game.screen == "reward" and game.run_context.pending_draft_kind == "level", "Brief hit opens the earned draft")

func _run() -> void:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	root.add_child(game)
	check(game.screen == "title", "Fresh game enters title")
	check(game.collection.initialize_starter("bastion").ok, "Collection fixture initializes only Bastion")
	check(game.collection.grant_part("bit:needle").ok, "Fixture grants one future acquired part through public API")
	check(game.collection.equip_build(SELECTED_BUILD).ok, "Owned mixed build equips")
	game._action("practice_garage")
	check(game.screen == "practice_garage", "Unrestricted practice Garage remains available")
	var submitted: Dictionary = SELECTED_BUILD.duplicate()
	game._action("build_changed", submitted)
	submitted.blade = "smash"
	check(game.build == SELECTED_BUILD, "Garage selection copies its input")
	_test_opening(game)
	_test_midbattle_and_swarm(game)
	_test_failure_and_exit(game)
	_test_completion(game)
	_test_authored_starters(game)
	_test_quick_duel(game)
	print("FLOW_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.queue_free()
	quit(1 if failures else 0)

func _test_opening(game: QuietMain) -> void:
	game._action("start_battle", "run")
	check(game.screen == "reward", "Primary Run route uses the equipped collection immediately")
	check(game.run_context.selected_build == SELECTED_BUILD and game.run_context.starter_id == "custom", "Advanced custom route locks the existing assembly")
	var opening_state: Dictionary = _state(game)
	var offer: Array[String] = game.run_context.pending_offer
	game._round_finished(_result(game))
	game._action("next_battle")
	game._action("choose_power", _choice(game, "invalid"))
	var wrong: Dictionary = _choice(game, offer[0])
	wrong.run_seed = int(wrong.run_seed) + 1
	game._action("choose_power", wrong)
	check(game.screen == "reward" and _state(game) == opening_state, "Opening rejects combat results, skipped choices, and wrong-run input")
	game._escape()
	check(game.screen == "pause" and game.pause_origin == "reward", "Opening draft supports pause")
	game._process(2.0)
	check(_state(game) == opening_state, "Opening pause preserves the exact offer")
	game._escape()
	check(game.screen == "reward" and game.run_context.pending_offer == offer, "Opening resume restores cards without rerolling")
	var chosen: Dictionary = _choice(game, offer[0])
	game._action("choose_power", chosen)
	check(game.screen == "acquisition" and game.run_context.owned_power_ids == [offer[0]], "Opening choice has a short payoff")
	var acquired: Dictionary = _state(game)
	game._action("choose_power", chosen)
	game._pause()
	game._process(2.0)
	check(game.screen == "pause" and _state(game) == acquired, "Pause stops acquisition and repeated confirm acquires once")
	game._resume()
	game._process(0.6)
	check(game.screen == "battle" and game.run_context.slot == 1 and game.battle.player_entity().powers == [offer[0]], "First encounter receives the chosen power")
	check(game.battle.player_entity().build == SELECTED_BUILD, "Custom assembly reaches powered combat")
	var locked: Dictionary = _state(game)
	for name: String in ["customize", "main_menu", "quick_duel", "start_run", "rematch", "build_changed"]:
		game._action(name, {"blade":"smash", "ratchet":"high", "bit":"flat"})
		check(game.screen == "battle" and _state(game) == locked, "Active Run rejects stale route %s" % name)

func _test_midbattle_and_swarm(game: QuietMain) -> void:
	for _slot: int in range(2):
		Fixtures.next_threat(game)
		check(game.screen == "battle" and game.run_context.pending_offer.is_empty(), "Threat clear keeps combat live without fixed slot rewards")
	check(game.run_context.slot == 3 and game.battle.swarm.enabled, "Ammunition Waves remains slot three")
	for _step: int in range(360):
		game.battle.test_step(1.0 / 60.0)
		if game.battle.swarm.spawned >= 6: break
	check(game.battle.swarm.spawned == 6, "First authored wave enters combat before the draft")
	game.battle.test_set_entity_state(game.battle.player_entity_id, {"rpm":0.63, "wobble":0.41, "cooldown":1.7, "vel":Vector2(27.0, -12.0)})
	var physical: Dictionary = _physical_state(game)
	var runtime_id: int = game.battle.powers.get_instance_id()
	_earn_level(game)
	var pending: Dictionary = _state(game)
	var offer: Array[String] = game.run_context.pending_offer
	var choice: Dictionary = _choice(game, offer[0])
	game._action("next_battle")
	game._action("choose_power", {"encounter_id":"draft/start", "power_id":offer[0], "run_seed":game.run_context.run_seed})
	game._progression_events([{"kind":"wave_complete", "encounter_id":"run_slot_03", "time":900.0, "wave":1, "player_attributed":true}])
	check(_state(game) == pending, "Paused draft rejects advancement, stale claims, and combat XP leakage")
	game._escape()
	game.battle.test_step(1.0, Vector2.RIGHT, true, true)
	game._process(1.0)
	check(_physical_state(game) == physical and _state(game) == pending, "Card selection/pause cannot move tops, spend RPM, or consume wave timers")
	game._escape()
	check(game.screen == "reward" and game.run_context.pending_offer == offer, "Midbattle focus/offer survives reopening")
	game._action("choose_power", choice)
	check(game.screen == "acquisition" and offer[0] in game.battle.player_entity().powers, "Acquired power is attached to the same live encounter")
	check(game.battle.powers.get_instance_id() == runtime_id and _physical_state(game) == physical, "New ownership preserves positions, RPM, wobble, cooldown, waves, and all existing power state")
	var acquired: Dictionary = _state(game)
	game._action("choose_power", choice)
	game._pause()
	game._process(2.0)
	check(game.screen == "pause" and _state(game) == acquired and _physical_state(game) == physical, "Acquisition pause freezes live combat and ignores repeated confirm")
	game._resume()
	game._process(0.6)
	_finish_reentry(game)
	check(game.screen == "battle" and not game.battle.paused and game.run_context.slot == 3, "Acquisition resumes the same swarm instead of relaunching")
	check(_physical_state(game) == physical and game.battle.encounter.player_power_ids == game.run_context.owned_power_ids, "Resume preserves the exact encounter and applies the new power immediately")
	game.battle.test_step(1.0 / 60.0)
	check(game.battle.elapsed > float(physical.elapsed), "Wave simulation continues from the paused timestamp")

func _test_failure_and_exit(game: QuietMain) -> void:
	var stale_result: Dictionary = _result(game)
	Fixtures.defeat_player(game)
	check(game.screen == "result" and game.run_context.status == "failed" and not game.last_result.next_available, "Loss ends Run without advancement")
	var failed: Dictionary = _state(game)
	game._action("next_battle")
	game._action("rematch")
	check(_state(game) == failed, "Failure cannot replay only the lost encounter")
	var old_seed: int = game.run_context.run_seed
	game._action("restart_run")
	_check_restart(game, old_seed)
	_claim(game)
	var fresh: Dictionary = _state(game)
	game._round_finished(stale_result)
	check(game.screen == "battle" and _state(game) == fresh, "Old-run result cannot commit after restart")
	game._pause()
	game._action("end_run")
	check(game.screen == "garage", "End Run returns to Garage")
	_check_cleared(game)
	_start_custom(game)
	_earn_level(game)
	game._action("choose_power", _choice(game, game.run_context.pending_offer[0]))
	old_seed = game.run_context.run_seed
	game._pause()
	game._action("restart_run")
	game._process(2.0)
	_check_restart(game, old_seed)
	game._escape()
	game._action("end_run")
	game._process(2.0)
	check(game.screen == "garage", "End during opening/acquisition cancels delayed launch")
	_check_cleared(game)

func _test_completion(game: QuietMain) -> void:
	_start_custom(game)
	var player: Dictionary = game.battle.player_entity()
	var runtime_id: int = game.battle.powers.get_instance_id()
	for threat: int in range(1, 13):
		check(game.screen == "battle" and game.run_context.slot == threat, "Continuous sequence reaches threat %d" % threat)
		var before: Dictionary = _state(game)
		var result: Dictionary = _result(game)
		game._round_finished(result)
		game._round_finished({"won":false, "reason":"spin_out"})
		check(game.screen == "battle" and _state(game) == before, "Ordinary and unbound results cannot terminate a Run")
		Fixtures.next_threat(game)
		game._round_finished(result)
		game._action("next_battle")
		check(game.screen == "battle" and game.run_context.slot == threat + 1, "Automatic threat entry replaces Continue")
		check(is_same(player, game.battle.player_entity()) and runtime_id == game.battle.powers.get_instance_id(), "Same player and power runtime survive every threat")
	check(game.run_context.is_active() and game.run_context.slot == 13, "No fixed completion after the previous eight-encounter limit")
	Fixtures.defeat_player(game)
	check(game.screen == "result" and game.last_result.title == "RUN ENDED", "Only player loss opens a Run result")
	game._action("restart_run")
	_claim(game)
	game._pause()
	game._action("end_run")

func _test_authored_starters(game: QuietMain) -> void:
	for identity: String in Starters.IDS:
		game.collection.reset_collection(true)
		game.collection.initialize_starter(identity)
		game._action("start_run")
		check(game.run_context.starter_id == identity and game.run_context.selected_build == Starters.build_for(identity), "Authored starter locks identity and physical assembly")
		_claim(game)
		check(game.battle.player_entity().build == Starters.build_for(identity), "Authored assembly reaches the opening battle")
		check(game.battle.player_entity().starter_id == identity and game.battle.player_entity().powers.size() == 1, "Opening battle carries starter visuals and one power")
		var old_seed: int = game.run_context.run_seed
		game._pause()
		game._action("restart_run")
		_check_restart(game, old_seed, identity)
		game._escape()
		game._action("end_run")
		_check_cleared(game)
	game.collection.reset_collection(true)
	game.collection.initialize_starter("bastion")
	game.collection.grant_part("bit:needle")
	game.collection.equip_build(SELECTED_BUILD)
	game._garage()
	check(game.build == SELECTED_BUILD, "Collection API can equip an acquired mixed assembly independently of historical starter")

func _test_quick_duel(game: QuietMain) -> void:
	game.last_result = {"title":"RUN COMPLETE"}
	game._action("quick_duel")
	check(game.mode == "duel" and game.screen == "battle" and game.run_context.status == "empty", "Quick Duel remains independent of Run progression")
	check(game.last_result.is_empty() and game.battle.player_entity().build == SELECTED_BUILD, "Quick Duel keeps Garage assembly and clears previous result")
	var opponent: Dictionary = game.opponent_build.duplicate()
	game._pause()
	check(game.battle.paused and game.screen == "pause", "Quick Duel pauses")
	game._action("rematch")
	check(game.screen == "battle" and game.opponent_build == opponent, "Quick Duel restart preserves opponent")
	game._round_finished({"won":true, "reason":"ring_out", "duration":29.0, "hits":8})
	check(game.screen == "result" and game.run_context.pending_offer.is_empty(), "Quick Duel never opens a progression draft")
	game._action("rematch")
	check(game.screen == "battle" and game.opponent_build == opponent, "Quick Duel rematch still works")
