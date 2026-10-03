extends SceneTree
# Integration coverage for the original title/garage/duel flow and the eight-slot Run.
# Results are controlled fixtures; physical combat outcomes remain covered in test_prototype.

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void:
		pass

var failures: int = 0
var checks: int = 0
const DRAFT_SLOTS: Array[int] = [1, 2, 3, 4, 6, 7]
const SELECTED_BUILD: Dictionary = {"blade":"guard", "ratchet":"low", "bit":"needle"}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _state(game: QuietMain) -> Dictionary:
	var context = game.run_context
	return {
		"slot":context.slot, "seed":context.run_seed, "build":context.selected_build.duplicate(true),
		"powers":context.owned_power_ids.duplicate(), "offer":context.pending_offer.duplicate(),
		"results":context.committed_results.duplicate(true), "rewards":context.committed_rewards.duplicate(true),
		"status":context.status
	}

func _result(game: QuietMain, won: bool = true) -> Dictionary:
	var encounter: Dictionary = game.run_context.current_encounter()
	return {"won":won, "reason":"ring_out" if won else "spin_out", "duration":29.0, "hits":8,
		"encounter_id":encounter.id, "seed":encounter.seed}

func _choice(game: QuietMain, power_id: String) -> Dictionary:
	return {"encounter_id":game.run_context.current_encounter().id,
		"power_id":power_id, "run_seed":game.run_context.run_seed}

func _check_reset(game: QuietMain, previous_seed: int, message: String) -> void:
	check(game.screen == "battle" and game.run_context.slot == 1 and game.run_context.status == "active", message+": starts slot 1")
	check(game.run_context.run_seed != previous_seed, message+": gets a fresh seed")
	check(game.run_context.owned_power_ids.is_empty() and game.run_context.pending_offer.is_empty(), message+": clears powers and draft")
	check(game.run_context.committed_results.is_empty() and game.run_context.committed_rewards.is_empty(), message+": clears commitments")
	check(game.run_context.selected_build == SELECTED_BUILD and game.battle.player_entity().build == SELECTED_BUILD, message+": keeps selected assembly")

func _check_cleared(game: QuietMain, message: String) -> void:
	check(game.run_context.status == "empty", message+": no active/terminal Run remains")
	check(game.run_context.owned_power_ids.is_empty() and game.run_context.pending_offer.is_empty(), message+": clears Run powers and offer")
	check(game.run_context.committed_results.is_empty() and game.run_context.committed_rewards.is_empty(), message+": clears Run commitments")
	check(not game.battle.visible and game.battle.paused, message+": hides and stops battle")

func _run() -> void:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	root.add_child(game)
	check(game.screen == "title", "Fresh game enters title")
	game._action("customize")
	check(game.screen == "garage", "Title customization enters garage")
	var submitted_build: Dictionary = SELECTED_BUILD.duplicate()
	game._action("build_changed", submitted_build)
	submitted_build.blade = "smash"
	check(game.build == SELECTED_BUILD, "Build selection does not retain the menu's mutable dictionary")
	game._action("start_battle", "run")
	check(game.mode == "run" and game.run_context.slot == 1 and game.run_context.status == "active", "Run begins at slot 1")
	check(game.run_context.selected_build == SELECTED_BUILD, "Run locks the chosen assembly")
	var first_result: Dictionary = _result(game)
	_test_complete_run(game)
	var completed_seed: int = game.run_context.run_seed
	game._action("restart_run")
	_check_reset(game, completed_seed, "Restart completed Run")
	var fresh_state: Dictionary = _state(game)
	game._round_finished(first_result)
	check(_state(game) == fresh_state and game.screen == "battle", "Prior Run result is rejected even when slot ID matches")
	_test_failure_restart(game)
	_test_explicit_exit(game)
	_test_quick_duel(game)
	print("FLOW_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.queue_free()
	quit(1 if failures else 0)

func _test_complete_run(game: QuietMain) -> void:
	var observed_drafts: Array[int] = []
	var previous_result: Dictionary = {}
	var previous_choice: Dictionary = {}
	for slot_number: int in range(1, 9):
		check(game.screen == "battle" and game.run_context.slot == slot_number, "Expected Run slot %d" % slot_number)
		check(game.run_context.current_encounter().id == "run_slot_%02d" % slot_number, "Stable encounter identity for slot %d" % slot_number)
		var player: Dictionary = game.battle.player_entity()
		check(player.build == SELECTED_BUILD, "Locked physical parts reach slot %d" % slot_number)
		check(is_equal_approx(player.rpm, 1.0) and is_zero_approx(player.wobble) and is_zero_approx(player.cooldown), "Slot %d resets RPM, wobble, and Burst cooldown" % slot_number)
		if slot_number == 8:
			check(game.run_context.owned_power_ids.size() == 6, "Player enters slot 8 with six owned powers")
		var before: Dictionary = _state(game)
		for action_name: String in ["customize", "main_menu", "quick_duel", "start_run", "rematch"]:
			game._action(action_name)
			check(game.screen == "battle" and _state(game) == before, "Active Run rejects %s in slot %d" % [action_name, slot_number])
		game._action("build_changed", {"blade":"smash", "ratchet":"high", "bit":"flat"})
		check(game.build == SELECTED_BUILD and _state(game) == before, "Physical assembly cannot change mid-Run")
		game._escape()
		check(game.screen == "pause" and game.battle.paused and game.pause_origin == "battle", "Battle Escape pauses Run")
		var paused_snapshot: Dictionary = game.battle.snapshot()
		game.battle.test_step(1.0 / 60.0, Vector2.RIGHT, true, true)
		check(_state(game) == before and game.battle.snapshot() == paused_snapshot, "Pause preserves Run state and stops simulated input")
		game._escape()
		check(game.screen == "battle" and not game.battle.paused and _state(game) == before, "Escape resumes the same Run encounter")
		if not previous_result.is_empty():
			game._round_finished(previous_result)
			game._action("choose_power", previous_choice)
			check(game.screen == "battle" and _state(game) == before, "Stale result and reward cannot affect a later slot")
		var result: Dictionary = _result(game)
		var invalid: Dictionary = result.duplicate()
		invalid.encounter_id = "not_this_encounter"
		game._round_finished(invalid)
		invalid = result.duplicate()
		invalid.seed = int(result.seed) + 1
		game._round_finished(invalid)
		game._round_finished({"won":true, "reason":"ring_out"})
		check(_state(game) == before and game.screen == "battle", "Unbound or mismatched result cannot commit a Run encounter")
		# Damage the outgoing fixture so the next launch's reset is meaningful.
		player.rpm = 0.25
		player.wobble = 0.6
		player.cooldown = 2.0
		game._round_finished(result)
		check(game.run_context.committed_results.size() == slot_number, "Encounter result commits once for slot %d" % slot_number)
		var committed: Dictionary = _state(game)
		var committed_screen: String = game.screen
		game._round_finished(result)
		check(_state(game) == committed and game.screen == committed_screen, "Duplicate result cannot commit twice")
		previous_result = result
		if slot_number in DRAFT_SLOTS:
			observed_drafts.append(slot_number)
			check(game.screen == "reward", "Win opens draft after slot %d" % slot_number)
			var offer: Array = game.run_context.pending_offer.duplicate()
			check(offer.size() == 3, "Draft offers three cards")
			var unique: Dictionary = {}
			for power_id: String in offer:
				unique[power_id] = true
				check(not power_id in game.run_context.owned_power_ids, "Draft never offers an owned power")
			check(unique.size() == 3, "Three draft cards are distinct")
			game._action("next_battle")
			game._action("choose_power", _choice(game, "not_an_offered_power"))
			var wrong_choice: Dictionary = _choice(game, str(offer[0]))
			wrong_choice.run_seed = int(wrong_choice.run_seed) + 1
			game._action("choose_power", wrong_choice)
			wrong_choice = _choice(game, str(offer[0]))
			wrong_choice.encounter_id = "not_this_encounter"
			game._action("choose_power", wrong_choice)
			check(game.screen == "reward" and _state(game) == committed, "Draft rejects skipped, invalid, wrong-Run, and wrong-encounter choices")
			game._escape()
			check(game.screen == "pause" and game.pause_origin == "reward", "Reward Escape opens Run overlay")
			check(_state(game) == committed, "Opening reward overlay preserves offer and Run state")
			game._escape()
			check(game.screen == "reward" and game.run_context.pending_offer == offer, "Closing overlay restores the exact pending offer")
			game._pause()
			game._resume()
			check(game.screen == "reward" and _state(game) == committed, "Repeated reward reopening never rerolls")
			var choice: Dictionary = _choice(game, str(offer[0]))
			game._action("choose_power", choice)
			check(game.screen == "battle" and game.run_context.slot == slot_number + 1, "One card choice launches next encounter")
			check(game.run_context.owned_power_ids.size() == observed_drafts.size() and str(offer[0]) in game.run_context.owned_power_ids, "Choice persists exactly one power")
			check(game.run_context.committed_rewards.size() == observed_drafts.size() and game.run_context.pending_offer.is_empty(), "Choice commits and clears pending offer")
			var after_choice: Dictionary = _state(game)
			game._action("choose_power", choice)
			game._round_finished(result)
			check(_state(game) == after_choice and game.screen == "battle", "Double card click and reentrant result cannot grant or advance twice")
			previous_choice = choice
		elif slot_number == 5:
			check(game.screen == "result" and game.run_context.pending_offer.is_empty(), "Slot 5 win has no draft")
			check(game.last_result.next_available, "Slot 5 win allows Continue")
			game._escape()
			check(game.screen == "pause" and game.pause_origin == "result" and _state(game) == committed, "Result overlay preserves active Run")
			game._escape()
			check(game.screen == "result" and _state(game) == committed, "Result overlay resumes without advancing")
			game._action("next_battle")
			check(game.run_context.slot == 6 and game.screen == "battle", "Slot 5 Continue launches slot 6")
			var after_continue: Dictionary = _state(game)
			game._action("next_battle")
			check(_state(game) == after_continue, "Double Continue cannot skip a slot")
		else:
			check(game.screen == "result" and game.run_context.status == "complete", "Slot 8 victory completes Run")
			check(game.run_context.pending_offer.is_empty() and not game.last_result.next_available, "Completed Run has no final draft or ninth encounter")
			game._action("next_battle")
			game._action("rematch")
			check(_state(game) == committed and game.screen == "result", "Completion cannot replay only final encounter or advance")
	check(observed_drafts == DRAFT_SLOTS, "Draft schedule is exactly 1, 2, 3, 4, 6, 7")
	var owned_unique: Dictionary = {}
	for power_id: String in game.run_context.owned_power_ids: owned_unique[power_id] = true
	check(owned_unique.size() == 6 and game.run_context.committed_rewards.size() == 6, "Completed Run owns exactly six distinct powers from six rewards")

func _test_failure_restart(game: QuietMain) -> void:
	# Retain rewards before losing to exercise failure cleanup with real Run progress.
	for _slot: int in range(2):
		game._round_finished(_result(game))
		game._action("choose_power", _choice(game, str(game.run_context.pending_offer[0])))
	check(game.run_context.slot == 3 and game.run_context.owned_power_ids.size() == 2, "Failure fixture has prior progress")
	game._round_finished(_result(game, false))
	check(game.screen == "result" and game.run_context.status == "failed", "Losing ends Run")
	check(not game.last_result.next_available and game.run_context.pending_offer.is_empty(), "Loss grants no advancement or draft")
	var failed_state: Dictionary = _state(game)
	game._action("next_battle")
	game._action("rematch")
	check(game.screen == "result" and _state(game) == failed_state, "Lost Run cannot advance or retry only the lost encounter")
	var failed_seed: int = game.run_context.run_seed
	game._action("restart_run")
	_check_reset(game, failed_seed, "Restart failed Run")
	game._round_finished(_result(game))
	check(game.screen == "reward", "Restart can earn a new draft")
	var reward_seed: int = game.run_context.run_seed
	game._escape()
	game._action("restart_run")
	_check_reset(game, reward_seed, "Restart from pending reward overlay")

func _test_explicit_exit(game: QuietMain) -> void:
	game._round_finished(_result(game))
	game._escape()
	game._action("end_run")
	check(game.screen == "garage", "Explicit End Run from reward overlay returns to garage")
	_check_cleared(game, "End Run from reward")
	game._action("start_run")
	check(game.screen == "battle" and game.run_context.slot == 1, "Garage starts a fresh Run")
	game._escape()
	game._action("end_run")
	check(game.screen == "garage", "Explicit End Run from battle overlay returns to garage")
	_check_cleared(game, "End Run from battle")
	game._action("start_run")
	game._round_finished(_result(game, false))
	game._action("customize")
	check(game.screen == "garage", "Failed Run can return to garage")
	_check_cleared(game, "Leave failed Run")
	game._action("start_run")
	for slot_number: int in range(1, 9):
		game._round_finished(_result(game))
		if slot_number in DRAFT_SLOTS:
			game._action("choose_power", _choice(game, str(game.run_context.pending_offer[0])))
		elif slot_number == 5:
			game._action("next_battle")
	check(game.run_context.status == "complete", "Return-to-title fixture completes Run")
	game._action("main_menu")
	check(game.screen == "title", "Completed Run can return to title")
	_check_cleared(game, "Leave completed Run")

func _test_quick_duel(game: QuietMain) -> void:
	game.last_result = {"title":"RUN COMPLETE"}
	game._action("quick_duel")
	check(game.mode == "duel" and game.screen == "battle", "Quick Duel launches after Run")
	check(game.last_result.is_empty(), "New duel clears previous result")
	check(game.battle.player_entity().build == SELECTED_BUILD, "Quick Duel keeps chosen physical assembly")
	check(game.run_context.status == "empty", "Quick Duel does not create a Run")
	var duel_opponent: Dictionary = game.opponent_build.duplicate()
	game._pause()
	check(game.screen == "pause" and game.battle.paused, "Quick Duel pause stops battle")
	game._resume()
	check(game.screen == "battle" and not game.battle.paused, "Quick Duel resume restores battle")
	game._pause()
	game._action("rematch")
	check(game.mode == "duel" and game.screen == "battle" and game.opponent_build == duel_opponent, "Quick Duel restart preserves opponent")
	game._round_finished({"won":false, "reason":"timeout", "duration":60.0, "hits":12})
	check(game.screen == "result" and not game.last_result.next_available, "Quick Duel timeout result has no progression")
	game._action("rematch")
	check(game.screen == "battle" and game.opponent_build == duel_opponent, "Quick Duel retry keeps opponent after loss")
	game._round_finished({"won":true, "reason":"ring_out", "duration":29.0, "hits":8})
	check(game.screen == "result" and game.run_context.pending_offer.is_empty(), "Quick Duel victory never opens draft")
	game._action("rematch")
	check(game.screen == "battle" and game.opponent_build == duel_opponent, "Quick Duel rematch works after victory")
	game._action("main_menu")
	check(game.screen == "title" and not game.battle.visible, "Main menu hides Quick Duel")
