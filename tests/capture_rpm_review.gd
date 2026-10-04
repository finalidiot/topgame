extends "res://tests/test_rpm_playthrough.gd"
## Offline movie replay. Fast-forward uses the same real ticks and earned drafts
## as diagnostics. Only controls are supplied; no reserve/outcome/state fixtures.
var capture_game: QuietMain
var capture_tick: int = 0
var capture_direction: Vector2 = Vector2.ZERO
var capture_brake: bool = false
var capture_start: float = 0.0
var capture_length: float = 16.0
var capture_starter: String = "breaker"
var capture_seed: int = 421
var recording: bool = false
var manifest: Dictionary = {"events":[]}
var manifest_path: String = ""

func step_replay() -> void:
	var b: Node2D = capture_game.battle
	var burst: bool = false
	if capture_tick % 12 == 0:
		var input: Dictionary = Bot.input(b,style,capture_tick)
		capture_direction = input.direction
		capture_brake = input.brake
		burst = input.burst
	b.test_step(Battle.FIXED_DT,capture_direction,burst,capture_brake)
	if capture_game.screen == "level_up": capture_game._process(0.2)
	while capture_game.screen == "reward": choose(capture_game)
	b.queue_redraw()
	capture_tick += 1

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--style="): style = arg.trim_prefix("--style=")
		if arg.begins_with("--starter="): capture_starter = arg.trim_prefix("--starter=")
		if arg.begins_with("--seed="): capture_seed = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--start="): capture_start = float(arg.trim_prefix("--start="))
		if arg.begins_with("--length="): capture_length = float(arg.trim_prefix("--length="))
		if arg.begins_with("--power="): override_power = arg.trim_prefix("--power=")
		if arg.begins_with("--manifest="): manifest_path = arg.trim_prefix("--manifest=")
	capture_game = QuietMain.new()
	capture_game.smoke_mode = true
	root.add_child(capture_game)
	capture_game.set_process(false)
	capture_game.run_context.start(Starters.build_for(capture_starter),capture_seed,capture_starter)
	capture_game.mode = "run"
	opening_preference = override_power if not override_power.is_empty() else {"aggressive":"redline","defensive":"dead_centre","hybrid":"afterimage"}[style]
	capture_game._show_reward()
	choose(capture_game)
	var b: Node2D = capture_game.battle
	b.set_physics_process(false)
	b.particles_enabled = true
	var player: Dictionary = b.player_entity()
	while b.elapsed < capture_start and b.battle_status != "finished": step_replay()
	assert(b.battle_status == "battle","Capture must reach selected window through natural combat")
	manifest.merge({"seed":capture_seed,"starter":capture_starter,"style":style,"starting_power":opening_preference,"start_time":b.elapsed,"start_tick":capture_tick,"before":b.continuous.economy.snapshot(),"authenticity":"Same sampled inputs, real director/physics/earned choices from one launch. No RPM edits, forced outcomes, teleports or protected player. Draft animations skipped."})
	# Main's smoke guard avoids preferences/log writes. Explicitly enable the
	# normal bounded gameplay audio for only the recorded window.
	b.event_sfx.connect(func(kind: String) -> void: capture_game.sounds.play_sound(kind))
	b.threat_cleared.connect(func(event: Dictionary) -> void: manifest.events.append({"type":"clear","time":b.elapsed,"event":event}))
	b.threat_started.connect(func(event: Dictionary) -> void: manifest.events.append({"type":"entry","time":b.elapsed,"event":event}))
	b._emit_hud()
	await process_frame
	for frame: int in range(int(capture_length*60.0)):
		step_replay()
		assert(is_same(player,b.player_entity()))
		await process_frame
	manifest["end_time"] = b.elapsed
	manifest["after"] = b.continuous.economy.snapshot()
	manifest["final_result"] = b.last_result
	if not manifest_path.is_empty():
		var file: FileAccess = FileAccess.open(manifest_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest,"\t"))
	print("AUTHENTIC_CAPTURE %s %s seed=%d %.2f to %.2f RPM %.3f to %.3f" % [style,capture_starter,capture_seed,manifest.start_time,b.elapsed,manifest.before.final_rpm,player.rpm])
	capture_game.free()
	quit()
