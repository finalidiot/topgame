extends SceneTree

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void:
		pass

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	root.add_child(game)
	check(game.screen == "title", "Fresh game enters title")
	game._action("customize")
	game._action("build_changed", {"blade":"guard", "ratchet":"low", "bit":"needle"})
	game._action("start_battle", "gauntlet")
	check(game.round_index == 0 and game.opponent_build.blade == "smash", "Run begins against Smash")
	for round_number: int in range(3):
		check(game.screen == "battle" and game.round_index == round_number, "Expected run round")
		check(game.battle.fighters[0].build == game.build, "Chosen parts reach combat")
		var opponent: Dictionary = game.opponent_build.duplicate()
		game._pause()
		check(game.screen == "pause" and game.battle.paused, "Pause stops simulation")
		game._resume()
		check(game.screen == "battle" and not game.battle.paused, "Resume restores battle")
		game._action("rematch")
		check(game.round_index == round_number and game.opponent_build == opponent, "Restart keeps current opponent and round")
		game._round_finished({"won":false, "reason":"spin_out", "duration":31.0, "hits":12})
		check(not game.last_result.next_available, "Loss cannot advance run")
		game._action("next_battle")
		check(game.round_index == round_number, "Invalid advance is ignored")
		game._action("rematch")
		check(game.screen == "battle" and game.opponent_build == opponent, "Retry keeps run progress")
		game._round_finished({"won":true, "reason":"ring_out", "duration":29.0, "hits":8})
		if round_number < 2:
			check(game.last_result.next_available, "Win unlocks next rival")
			game._action("next_battle")
		else:
			check(game.last_result.get("title", "") == "GAUNTLET CLEARED", "Third win clears run")
	check(not game.last_result.next_available, "Completed run has no fourth round")
	game._action("rematch")
	check(game.round_index == 0 and game.screen == "battle", "Run again restarts full gauntlet")
	game.last_result = {"title":"GAUNTLET CLEARED"}
	game._action("quick_duel")
	check(game.last_result.is_empty(), "New battle clears previous result")
	var duel_opponent: Dictionary = game.opponent_build.duplicate()
	game._pause()
	game._action("rematch")
	check(game.mode == "duel" and game.opponent_build == duel_opponent, "Quick-duel restart preserves opponent after a completed run")
	game._action("main_menu")
	check(game.screen == "title" and not game.battle.visible, "Main menu hides battle")
	print("FLOW_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.queue_free()
	quit(1 if failures else 0)
