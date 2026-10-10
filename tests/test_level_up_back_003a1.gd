extends "res://tests/test_input_acceptance_003a1.gd"
## Printed Back is ignored by mandatory earned-choice screens, using real
## Main GUI dispatch/timers. Ownership and the earned XP event are fixtures.

func probe_back(expected: String) -> void:
	var claim: String = game.run_context.pending_draft_id
	var ranks: Dictionary = game.run_context.power_ranks
	var elapsed: float = game.battle.elapsed
	var focus: Control = root.gui_get_focus_owner()
	await back()
	check(game.screen == expected, "Printed Back remains on " + expected)
	check(game.run_context.pending_draft_id == claim and game.run_context.power_ranks == ranks, "Back preserves the pending claim and investment")
	check(is_equal_approx(game.battle.elapsed, elapsed) and game.battle.paused, "Back keeps choice combat paused")
	if is_instance_valid(focus): check(root.gui_get_focus_owner() == focus, "Back retains the current choice focus")

func flow(profile: String) -> void:
	if profile not in ["xbox", "nintendo", "playstation"]: return
	capture_group = "level_up_back"
	await boot(profile)
	await intent("start_run")
	await probe_back("reward")
	await intent("choose_power")
	await probe_back("acquisition")
	await wait_for("battle", "battle")
	var power_id: String = game.run_context.owned_power_ids[0]
	# A legal Rank II ownership fixture exercises the existing third-investment
	# mutation flow, without simulating a click or forcing a completion outcome.
	game.run_context._power_ranks[power_id] = 2
	game.battle.acquire_run_power(power_id, 2)
	events.append({"frame":frame(), "type":"rank_ii_ownership_fixture", "power_id":power_id})
	var event: Dictionary = {"kind":"elimination", "encounter_id":str(game.run_context.current_encounter().id),
		"time":game.battle.elapsed, "entity_id":90003, "combatant_type":"full_top", "reason":"spin_out", "player_attributed":true}
	events.append({"frame":frame(), "type":"earned_xp_fixture", "event":event})
	game._progression_events([event])
	check(game.screen == "level_up", "Actual XP event enters the brief level-up beat")
	var back_button: JoyButton = Bindings.back_button(profile)
	joy(back_button, true); await wait_frames(1)
	check(game.screen == "level_up", "Immediate held Back cannot interrupt the level-up beat")
	await wait_for("reward")
	check(game.screen != "pause", "Held Back crossing level-up to reward never opens Pause")
	joy(back_button, false); await wait_frames(2)
	await probe_back("reward")
	# Select the legal owned Rank II parent using the normal GUI. Deterministic
	# offer ownership is explicitly a fixture; claim validation remains live.
	game.run_context._pending_offer.assign([power_id])
	game._show_reward()
	await wait_frames(3)
	await intent("choose_power")
	check(game.screen == "mutation", "Real Rank III parent selection opens its mutation choice")
	await probe_back("mutation")
	await tap_joy(JOY_BUTTON_START)
	check(game.screen == "pause" and game.pause_origin == "mutation", "Explicit MENU still intentionally pauses the mutation flow")
	await back()
	check(game.screen == "mutation", "Printed Back resumes that explicit Pause to the exact choice")
	await intent("choose_mutation")
	check(game.screen == "acquisition", "Real branch selection enters the longer mutation acquisition")
	await probe_back("acquisition")
	var elapsed: float = game.battle.elapsed
	joy(back_button, true)
	await wait_for("battle", "reentry")
	check(game.screen == "battle" and is_equal_approx(game.battle.elapsed, elapsed), "Held Back reaches READY without ejecting or advancing combat")
	await wait_for("battle", "battle")
	check(game.screen == "battle", "Held Back crosses READY to GO without a replayed Pause")
	joy(back_button, false); await wait_frames(3)
	check(game.battle.elapsed > elapsed and not game.battle.paused, "GO resumes real combat after the choice")
	await tap_joy(JOY_BUTTON_START)
	check(game.screen == "pause", "Dedicated MENU remains available after GO")
	await back()
	check(game.screen == "battle", "Ordinary Pause Back retains its existing resume action")
	outcomes.append({"input":profile, "kind":"mandatory_choice_back", "passed":game.screen == "battle",
		"scope":"Real GUI logical events; no new physical-controller acceptance claim"})
