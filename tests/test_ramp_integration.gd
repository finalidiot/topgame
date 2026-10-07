extends SceneTree
## Deterministic integration fixtures test frozen live state and render menus.
## These controlled threshold/encounter fixtures are not pacing evidence.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass

var checks: int = 0
var failures: int = 0
var captures: String = ""
var game: QuietMain
const Physics = preload("res://scripts/battle.gd")

func _initialize() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _finish_reentry() -> void:
	var ticks: int = 0
	while game.battle.battle_status == "reentry" and ticks < 91:
		game.battle.test_step(Physics.FIXED_DT)
		ticks += 1
	check(game.battle.battle_status == "battle", "Actual ready ticks finish before the next live simulation step")

func frozen_state() -> Dictionary:
	var b = game.battle
	var snapshot: Dictionary = b.snapshot()
	snapshot.erase("paused")
	return {"snapshot":snapshot, "schedule":b.swarm.schedule.duplicate(true), "power_states":b.powers._states.duplicate(true), "power_clock":b.powers.time,
		"countdown":b._countdown, "launch":b._launch_time, "finish":b._finish_timer, "hit_stop":b._hit_stop, "accumulator":b._accumulator,
		"pair_cooldowns":b._pair_cooldowns.duplicate(true), "traces":b.powers.traces.duplicate(true), "events":b.powers.events.duplicate(true),
		"chain_queue":b.powers._next_tick_pulses.duplicate(true), "fx":b._power_fx.duplicate(true), "visual_time":b._visual_time}

func save_frame(label: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), "Rendered " + label)
	if image != null: check(image.save_png(captures.path_join(label + ".png")) == OK, "Saved " + label)

func choose() -> void:
	var chosen: String = game.run_context.pending_offer[0]
	for power_id: String in game.run_context.pending_offer:
		if not power_id in game.run_context.owned_power_ids:
			chosen = power_id
			break
	game._action("choose_power", {"encounter_id":game.run_context.pending_draft_id,"power_id":chosen,"run_seed":game.run_context.run_seed})
	if game.screen == "mutation":
		game._action("choose_mutation", {"encounter_id":game.run_context.pending_draft_id,"branch_id":game.run_context.pending_mutation_offer[0],"run_seed":game.run_context.run_seed})

func earn_level() -> void:
	var b = game.battle
	var time: float = b.elapsed
	var sequence: int = 10000 + game.run_context.level * 100
	while game.run_context.pending_offer.is_empty():
		time += 1.2
		sequence += 1
		game.run_context.award_xp({"kind":"collision","encounter_id":game.run_context.current_encounter().id,"event_id":sequence,"time":time,"first_entity_id":1,"second_entity_id":2,"player_attributed":true,"severity":0.8})
	game._progression_events([])

func _run() -> void:
	root.content_scale_size = Vector2i(640,360)
	root.size = Vector2i(640,360)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): captures = arg.trim_prefix("--capture-dir=")
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	game = QuietMain.new()
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	await save_frame("01-title-640")
	game._action("start_run")
	check(game.screen == "starter_ceremony", "Fresh collection opens first-save starter ceremony")
	await save_frame("02-starters-640")
	root.size = Vector2i(1280,720)
	await save_frame("02-starters-2x")
	root.size = Vector2i(640,360)
	game._action("select_first_starter","breaker")
	game._action("confirm_first_starter","breaker")
	game._process(1.5)
	game._action("launch_owned_run")
	check(game.screen == "reward" and not game.battle.visible, "Starting choice precedes first combat")
	check(game.run_context.pending_offer.size() == 3, "Starting choice has three distinct implemented powers")
	await save_frame("03-starting-cards-640")
	root.size = Vector2i(1280,720)
	await save_frame("03-starting-cards-2x")
	root.size = Vector2i(640,360)
	var initial_claim: String = game.run_context.pending_draft_id
	var initial_power: String = game.run_context.pending_offer[0]
	choose()
	game._action("choose_power",{"encounter_id":initial_claim,"power_id":initial_power,"run_seed":game.run_context.run_seed})
	check(game.run_context.owned_power_ids.size() == 1, "Starting draft commits once")
	await save_frame("04-acquisition-640")
	game._process(0.51)
	game.battle.set_physics_process(false)
	check(game.screen == "battle" and game.run_context.slot == 1, "Initial acquisition launches slot one")
	check(game.battle.player_entity().powers == game.run_context.owned_power_ids, "First encounter already has a power")
	game.battle.battle_status = "battle"
	game.battle.test_step(0.1,Vector2.RIGHT,true)
	var before: Dictionary = frozen_state()
	earn_level()
	check(game.screen == "level_up" and game.battle.paused, "Threshold safely pauses for completion hit")
	check(before == frozen_state(), "Opening earned draft changes no encounter state")
	game._process(0.19)
	check(game.screen == "reward", "Short completion hit opens immediate draft")
	await save_frame("05-midbattle-cards-640")
	game.battle.test_step(0.25,Vector2.LEFT,true,true)
	game._process(10.0)
	check(before == frozen_state(), "Timers, tops, RPM, causes and RNG-facing schedules remain frozen in choice")
	var offer: Array = game.run_context.pending_offer
	var focus: String = game.menus.focused_power_id()
	game._pause()
	game._resume()
	check(game.run_context.pending_offer == offer and game.menus.focused_power_id() == focus, "Reopening preserves offer and focused card")
	var runtime: Object = game.battle.powers
	choose()
	check(game.battle.powers == runtime and game.battle.powers._states == before.power_states, "Acquisition preserves live power runtime and spent recovery")
	check(game.run_context.owned_power_ids.size() == 2, "Earned power appended exactly once")
	game._process(0.51)
	_finish_reentry()
	check(game.screen == "battle" and not game.battle.paused and game.run_context.slot == 1, "Acquisition returns to the same encounter")
	check(game.battle.elapsed == before.snapshot.elapsed and game.battle.player_entity().pos == before.snapshot.player.pos and game.battle.player_entity().rpm == before.snapshot.player.rpm, "Exact position, spin and live time restored")
	check(game.battle.player_entity().powers == game.run_context.owned_power_ids, "New power becomes live in the same encounter")
	await save_frame("06-hud-640")
	root.size = Vector2i(1280,720)
	await save_frame("06-hud-2x")
	root.size = Vector2i(640,360)
	# Swarm fixture: preserve pending entry telegraph and all clocks in a draft.
	preload("res://tests/continuous_fixtures.gd").next_threat(game)
	preload("res://tests/continuous_fixtures.gd").next_threat(game)
	game.battle.set_physics_process(false)
	game.battle.battle_status = "battle"
	game.battle.test_step(0.25)
	game.battle.test_step(0.25)
	before = frozen_state()
	earn_level()
	game._process(0.19)
	for _tick: int in range(90): game.battle.test_step(1.0/60.0,Vector2.RIGHT,true,true)
	check(before == frozen_state(), "Swarm telegraph, wave scheduling and live timers are paused for every choice tick")
	choose()
	game._process(0.51)
	_finish_reentry()
	check(game.battle.swarm.schedule == before.schedule and game.battle.elapsed == before.snapshot.elapsed, "Swarm resumes at the exact scheduled moment")
	game.battle.test_step(1.0/60.0)
	check(game.battle.elapsed > before.snapshot.elapsed, "Swarm continues after selection")
	await save_frame("07-swarm-hud-640")
	# All six card artworks/copy, rendered as two sets of three.
	for row: int in range(2):
		var ids: Array = preload("res://scripts/run_powers.gd").ACTIVE_IDS.slice(row*3,row*3+3)
		game.menus.show_reward(ids,[],3,"visual_fixture",421,"",{"title":"RUN POWERS","subtitle":"Mechanical phenomena","resume_label":"RETURN TO COMBAT"})
		await save_frame("08-cards-%d-640" % row)
		root.size = Vector2i(1280,720)
		await save_frame("08-cards-%d-2x" % row)
		root.size = Vector2i(640,360)
	print("RAMP_INTEGRATION_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	game.free()
	quit(1 if failures else 0)
