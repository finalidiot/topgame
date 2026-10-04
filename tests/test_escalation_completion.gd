extends SceneTree
## Controlled threat and attributed-XP fixtures verify full investment through
## real Main screens. They are state evidence, not combat or pacing evidence.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
const Parts = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")
var failures: int = 0
var checks: int = 0
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.run_context.start(Parts.DEFAULT_BUILD, 421)
	game.mode = "run"
	game._draft_resume_origin = "starting"
	game._show_reward()
	game._action("choose_power", {"encounter_id":game.run_context.pending_draft_id,"power_id":game.run_context.pending_offer[0],"run_seed":421})
	game._process(1.1)
	game.battle.set_physics_process(false)
	for _slot: int in range(1,8):
		preload("res://tests/continuous_fixtures.gd").next_threat(game)
	for id: int in range(100, 100 + int((132 + 84 * (Powers.investment_capacity() - 5)) / 3)):
		game.run_context.award_xp({"kind":"elimination","encounter_id":"run_slot_08","time":1.0,"entity_id":id,"combatant_type":"small_top","reason":"impact","player_attributed":true})
	game._progression_events([])
	game._process(0.2)
	check(game.screen == "reward" and game._draft_resume_origin == "battle", "Earned claims pause the same ongoing Run")
	var expected_elapsed: float = game.battle.elapsed
	var branches: int = 0
	while not game.run_context.pending_offer.is_empty():
		var claim: String = game.run_context.pending_draft_id
		game._action("choose_power", {"encounter_id":claim,"power_id":game.run_context.pending_offer[0],"run_seed":421})
		if game.screen == "mutation":
			branches += 1
			game._pause()
			check(game.screen == "pause" and game.battle.paused, "Mid-run branch can pause")
			game._resume()
			check(game.screen == "mutation" and game.run_context.pending_draft_id == claim, "Mid-run branch resumes same entitlement")
			game._action("choose_mutation", {"encounter_id":claim,"branch_id":game.run_context.pending_mutation_offer[0],"run_seed":421})
		check(game.screen == "acquisition", "Each mid-run claim has acquisition")
		game._process(1.1)
		check(game.battle.elapsed == expected_elapsed, "Earned choices never relaunch or advance simulation")
	var owned_flagships: int = 0
	for id: String in game.run_context.owned_power_ids:
		if id in Powers.VERTICAL_IDS: owned_flagships += 1
	check(branches == owned_flagships and game.screen == "battle" and game.run_context.is_active(), "Full investment resumes the live Run with every owned flagship mutation")
	preload("res://tests/continuous_fixtures.gd").next_threat(game)
	check(game.run_context.slot == 9 and game.last_result.is_empty(), "Full investment does not terminate at threat eight")
	check(game.run_context.committed_rewards.size() == game.run_context.available_investment_capacity() and game.run_context.owned_power_ids.size() == Powers.FAMILY_CAP, "Continuous Run retains every investment of its seven chosen families")
	print("ESCALATION_COMPLETION_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	game.free()
	quit(1 if failures else 0)
