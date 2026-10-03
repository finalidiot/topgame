extends SceneTree
## Controlled result and attributed-XP fixtures verify the final queue through
## real Main screens. They are state evidence, not combat or pacing evidence.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
const Parts = preload("res://scripts/parts.gd")
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
		game.run_context.commit_result(game.run_context.current_encounter().id,true)
		game.run_context.advance()
		game._launch_run_encounter()
		game.battle.set_physics_process(false)
	for id: int in range(100,368):
		game.run_context.award_xp({"kind":"elimination","encounter_id":"run_slot_08","time":1.0,"entity_id":id,"combatant_type":"small_top","reason":"impact","player_attributed":true})
	var encounter: Dictionary = game.run_context.current_encounter()
	game._round_finished({"won":true,"reason":"ring_out","encounter_id":encounter.id,"seed":encounter.seed})
	check(game.screen == "reward" and game._draft_resume_origin == "result", "Final result opens queued earned claims")
	var expected_elapsed: float = game.battle.elapsed
	var branches: int = 0
	while not game.run_context.pending_offer.is_empty():
		var claim: String = game.run_context.pending_draft_id
		game._action("choose_power", {"encounter_id":claim,"power_id":game.run_context.pending_offer[0],"run_seed":421})
		if game.screen == "mutation":
			branches += 1
			game._pause()
			check(game.screen == "pause" and game.battle.paused, "Result-origin branch can pause")
			game._resume()
			check(game.screen == "mutation" and game.run_context.pending_draft_id == claim, "Result-origin branch resumes same entitlement")
			game._action("choose_mutation", {"encounter_id":claim,"branch_id":game.run_context.pending_mutation_offer[0],"run_seed":421})
		check(game.screen == "acquisition", "Each result-origin claim has acquisition")
		game._process(1.1)
		check(game.battle.paused and game.battle.elapsed == expected_elapsed, "Final earned choices never launch or advance combat")
	check(branches == 3 and game.screen == "result" and game.run_context.status == "complete", "Queued final claims return to complete result with three mutations")
	check(game.last_result.title == "RUN CLEARED" and not game.last_result.next_available, "Final result publishes correct completion state")
	check(game.run_context.committed_rewards.size() == 13 and game.run_context.owned_power_ids.size() == 7, "Final result retains all thirteen investments and seven powers")
	print("ESCALATION_COMPLETION_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	game.free()
	quit(1 if failures else 0)
