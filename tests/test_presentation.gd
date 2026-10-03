extends SceneTree
## Headless: asset/export and bounded audio contracts.
## With --capture-dir=<absolute path>: additionally render deterministic motion
## and a held 12-body stress fixture. This is not a human gameplay assessment.
const Visuals = preload("res://scripts/power_visuals.gd")
const Sound = preload("res://scripts/sound.gd")
const Battle = preload("res://scripts/battle.gd")
const MeasuredBattle = preload("res://tests/measured_presentation_battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
var checks: int = 0
var failures: Array[String] = []
var capture_dir: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)

func _run() -> void:
	for group: String in ["small_top", "effects", "icons"]:
		var meta: Dictionary = Visuals._meta(group)
		check(not meta.is_empty(), group + " manifest available")
		for tag: String in meta.tags:
			var span: Dictionary = meta.tags[tag]
			check(int(span.from) >= 0 and int(span.to) < int(meta.frame_count), group + ":" + tag + " frames in atlas")
			check(Visuals._frame(group, tag, 0.0) == int(span.from), group + ":" + tag + " first frame")
			check(Visuals._frame(group, tag, 99.0) == int(span.to), group + ":" + tag + " terminal frame")
	check(Visuals.SMALL.get_size() == Vector2(192, 24), "24px small-top canvas and 8 frames")
	check(Visuals.EFFECTS.get_size() == Vector2(1024, 768), "128px effects 48 frames")
	check(Visuals.icon_region("chain_impact") == Rect2(80, 0, 16, 16), "Six icon IDs map to dedicated regions")
	var fx_host: Node2D = Battle.new()
	fx_host.add_power_fx("second_wind",Vector2.ZERO)
	for index: int in range(40): fx_host.add_power_fx("chain_impact",Vector2(index,0))
	check(fx_host._power_fx.size()==32,"Power FX have a strict32-record cap")
	check(fx_host._power_fx[0].kind=="second_wind","Dense chains preserve the finite recovery sequence")
	fx_host.free()
	var recovery_fx: Array[Dictionary] = [{"kind": "second_wind", "owner_entity_id": 1, "phase": 2, "age": 0.25}]
	var pose: Dictionary = Visuals.recovery_pose({"entity_id": 1, "phase": 7}, recovery_fx)
	check(int(pose.phase) == 3 and float(pose.stance) == 4.0, "Recovery contracts the rig and nearly stops authored spin")
	check(Visuals.recovery_pose({"entity_id": 2, "phase": 7}, recovery_fx).is_empty(), "Recovery never changes an unrelated rig")
	recovery_fx[0].age = 0.35
	pose = Visuals.recovery_pose({"entity_id": 1, "phase": 7}, recovery_fx)
	check(int(pose.phase) == 7 and float(pose.stance) < 0.0, "Recovery releases into normal spin with an upright snap")
	var sound: Node = Sound.new()
	root.add_child(sound)
	AudioServer.set_bus_mute(0, true)
	for _i: int in range(24): sound.play_sound("small_hit")
	check(int(sound.played_counts.get("small_hit", 0)) == 1, "24 same-frame small contacts aggregate to one quiet cue")
	for _i: int in range(24): sound.play_sound("chain_impact")
	check(int(sound.played_counts.get("chain", 0)) == 1, "24 same-frame chain requests aggregate")
	for _i: int in range(12): sound.play_sound("second_wind")
	var before: int = int(sound.played_counts.get("wall", 0))
	sound.play_sound("wall")
	check(int(sound.played_counts.get("wall", 0)) == before, "Low importance audio cannot replace recovery")
	check(int(sound.audio_snapshot().active) <= 8 and sound.channels.size() == 8, "Eight-channel hard cap")
	for key: String in ["power_wake", "redline", "comet_charge", "comet_release", "second_wind", "chain", "wave", "afterimage", "acquire"]:
		check(Sound.SOUNDS[key].get_length() > 0.0 and Sound.SOUNDS[key].get_length() <= 0.57, key + " finite cue")
	for channel: AudioStreamPlayer in sound.channels:
		channel.stop()
	sound.free()
	# The Dummy audio backend still drains playback ownership on its mix tick.
	await create_timer(0.65).timeout
	await process_frame
	await process_frame
	if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(capture_dir)
		await capture_motion()
	print("PRESENTATION_TEST_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func save_frame(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(capture_dir.path_join(name + ".png"))

func make_battle() -> Node2D:
	var battle: Node2D = MeasuredBattle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_slot(3, 421)
	descriptor.player_power_ids = ["impact_wake", "second_wind", "redline", "iron_comet", "afterimage", "chain_impact"]
	battle.begin_encounter({"blade": "smash", "ratchet": "low", "bit": "flat"}, descriptor)
	battle.battle_status = "battle"
	return battle

func capture_motion() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(640, 360)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var battle: Node2D = make_battle()
	var saved: Dictionary = {}
	var frames: int = 0
	for tick: int in range(1900):
		var direction: Vector2 = Vector2(sin(tick * 0.023), cos(tick * 0.019))
		battle.test_step(Battle.FIXED_DT, direction, tick % 250 == 0, tick % 130 > 115)
		await process_frame
		for fx: Dictionary in battle._power_fx:
			var kind: String = str(fx.kind)
			if float(fx.age) >= 0.10 and not saved.has(kind):
				await save_frame("natural-" + kind + "-640")
				saved[kind] = true
		# 12 Hz movement sequence has no synthetic trigger or reset.
		if tick % 5 == 0:
			await save_frame("motion-%04d" % frames)
			frames += 1
		if battle.battle_status == "finished": break
	print("NATURAL_CAPTURE powers=", battle.powers.counters, " swarm=", battle.swarm.telemetry(), " result=", battle.last_result)
	battle.free()
	# Separate explicitly held population/effect stress fixture: never claim this
	# measures encounter success, natural proc frequency, or human feel.
	battle = make_battle()
	battle.swarm.schedule.clear()
	for i: int in range(12):
		battle.swarm.add_small(200 + i, Vector2(cos(i * TAU / 12.0), sin(i * TAU / 12.0)) * 64.0)
	var samples: Array[float] = []
	var frame_samples: Array[float] = []
	var before_frame: int = Time.get_ticks_usec()
	for tick: int in range(480):
		battle.battle_status = "battle"
		battle.swarm.enabled = true
		for f: Dictionary in battle.fighters:
			f.outcome = ""
			f.rpm = 1.0 if f.combatant_type == "full_top" else 0.22
			f.age = 0.0
			var angle: float = float(int(f.entity_id) - 200) * TAU / 12.0 + float(tick) * .015
			f.pos = Vector2.ZERO if f.combatant_type == "full_top" else Vector2(cos(angle), sin(angle)) * 60.0
		battle.player_entity().redline_time = 0.6
		battle.player_entity().iron_comet_time = 1.0
		if tick % 8 == 0:
			for i: int in range(4):
				battle.add_power_fx("chain_impact", Vector2(cos(i * 1.57 + tick), sin(i * 1.57 + tick)) * 43.0, Vector2.RIGHT, 1.0)
		var before: int = Time.get_ticks_usec()
		battle.test_step(Battle.FIXED_DT, Vector2(sin(tick * .12), cos(tick * .12)), tick % 250 == 0)
		var elapsed_ms: float = float(Time.get_ticks_usec() - before) / 1000.0
		for f: Dictionary in battle.fighters:
			f.outcome = ""
			f.rpm = 1.0 if f.combatant_type == "full_top" else 0.22
		await process_frame
		if tick == 60: battle.draw_samples.clear()
		if tick > 60:
			samples.append(elapsed_ms)
			frame_samples.append(float(Time.get_ticks_usec() - before_frame) / 1000.0)
		before_frame = Time.get_ticks_usec()
	check(battle.swarm.active_count() == 12, "Held dense fixture has twelve active bodies")
	for scale_factor: int in [1, 2, 3]:
		root.size = Vector2i(640, 360) * scale_factor
		battle.scale = Vector2.ONE * scale_factor
		battle.queue_redraw()
		await process_frame
		await save_frame("dense-held-%dx" % scale_factor)
	var report: Dictionary = {"scope": "Windows Godot compatibility renderer, native640, VSync disabled, held12-body fixture with repeated chain FX, no HUD; CPU draw submission excludes asynchronous GPU time; wall-frame includes harness; not a human playtest", "os": OS.get_name(), "processor": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(), "samples": samples.size(), "simulation_ms": stats(samples), "frame_wall_ms": stats(frame_samples), "draw_submission_ms": stats(battle.draw_samples), "render_draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "fx": battle._power_fx.size()}
	var file: FileAccess = FileAccess.open(capture_dir.path_join("render-benchmark.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("RENDER_BENCHMARK ", JSON.stringify(report))
	battle.free()

func stats(samples: Array[float]) -> Dictionary:
	samples.sort()
	return {"median": samples[samples.size() / 2], "p95": samples[int(samples.size() * .95)], "max": samples.back()}
