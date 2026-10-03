extends SceneTree
## HUD-free five-second visual diagnostic using the real fixed simulation.
## Builds and one initial pose are explicit setup fixtures. After setup only
## steering, Burst and brake inputs act: no path, hit, FX or outcome is injected.
## Captures and bot counters support visual inspection, not human feel acceptance.
const Battle = preload("res://tests/measured_presentation_battle.gd")
const Physics = preload("res://scripts/battle.gd")
const Starters = preload("res://scripts/starters.gd")
const Encounters = preload("res://scripts/encounters.gd")
const SECONDS: float = 5.0
const SCENARIOS: Array[Dictionary] = [
	{"id":"runaway-breaker", "starter":"breaker", "power":"redline", "branch":"runaway", "support":"impact_wake", "policy":"pursuit_burst", "defining_proc":"runaway_hit"},
	{"id":"bulwark-bastion", "starter":"bastion", "power":"dead_centre", "branch":"bulwark", "support":"second_wind", "policy":"centre_brake", "defining_proc":"bulwark_impact"},
	{"id":"ghost-circuit-vane", "starter":"vane", "power":"afterimage", "branch":"ghost_circuit", "support":"iron_comet", "policy":"orbit", "defining_proc":"ghost_closure"}
]

var capture_dir: String = ""
var report_path: String = "user://task002c-visual-playthrough.json"
var sequence_fps: int = 0
var checks: int = 0
var failures: int = 0
var report: Dictionary = {"scope":"Five active simulation seconds per HUD-free build. Explicit initial build/pose fixtures, then real movement/contact mechanics and normal rival AI. No injected procs, teleports, reserve refills, paths, FX or victories. This is bot/render evidence; build recognition and feel require human review.", "runs":[]}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		if argument.begins_with("--sequence-fps="): sequence_fps = clampi(int(argument.trim_prefix("--sequence-fps=")), 0, 60)
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _screen_direction(world: Vector2) -> Vector2:
	if world.length_squared() < 0.0001: return Vector2.ZERO
	return Vector2(world.x - world.y, (world.x + world.y) * 0.5).normalized() * minf(1.0, world.length())

func _controls(battle: Node2D, scenario: Dictionary) -> Dictionary:
	var player: Dictionary = battle.player_entity()
	var position: Vector2 = player.pos
	var desired: Vector2 = Vector2.ZERO
	var burst: bool = false
	var brake: bool = false
	match str(scenario.policy):
		"pursuit_burst":
			var target: Dictionary = battle._target_for(player)
			var distance: float = INF
			if not target.is_empty():
				var offset: Vector2 = Vector2(target.pos) - position
				distance = offset.length()
				desired = offset.normalized()
			if position.length() > 143.0:
				desired = -position.normalized()
				brake = position.length() > 153.0
			burst = float(player.cooldown) <= 0.0 and distance < 110.0 and not brake
		"centre_brake":
			desired = (-position * 0.025).limit_length(0.25)
			brake = true
		"orbit":
			var radial: Vector2 = position.normalized() if position.length() > 1.0 else Vector2.RIGHT
			var tangent: Vector2 = Vector2(-radial.y, radial.x)
			# Velocity feedback uses steering alone to draw a viable central orbit.
			var velocity: Vector2 = player.vel
			var route_velocity: Vector2 = tangent * 190.0 + radial * (132.0-position.length()) * 2.0
			var thrust: Vector2 = (route_velocity-velocity)*4.0 + route_velocity*0.75 - radial*(190.0*190.0/132.0)
			var available: float = (123.0+float(player.stats.grip)*17.0)*float(player.handling.get("acceleration",1.0))
			if float(player.burst_time) > 0.0: available *= 1.65
			desired = thrust.limit_length(available)/available
			burst = float(player.cooldown) <= 0.0 and position.length() < 145.0
	return {"direction":_screen_direction(desired), "burst":burst, "brake":brake}

func _initialise_fixture(battle: Node2D, scenario: Dictionary) -> void:
	var descriptor: Dictionary = Encounters.for_slot(1, 421)
	descriptor.starter_id = scenario.starter
	descriptor.player_power_ids = [scenario.power, scenario.support]
	descriptor["player_power_ranks"] = {str(scenario.power):3, str(scenario.support):1}
	descriptor["player_power_mutations"] = {str(scenario.power):scenario.branch}
	# Same ordinary duel, opponent parts, seed and physics for every build.
	battle.begin_encounter(Starters.build_for(str(scenario.starter)), descriptor)
	battle.battle_status = "battle"
	var player: Dictionary = battle.player_entity()
	if scenario.policy == "centre_brake":
		player.pos = Vector2.ZERO
		player.vel = Vector2.ZERO
	elif scenario.policy == "orbit":
		player.pos = Vector2(132.0, 0.0)
		player.vel = Vector2.ZERO
	# Normal opening pose for aggression; only countdown is omitted from these
	# five active seconds. The rival remains at the ordinary launch coordinates.
	battle.powers._state(player).trace_origin = player.pos
	battle.powers._state(player).trace_path = [Vector2(player.pos)]

func _sample(battle: Node2D) -> Dictionary:
	var player: Dictionary = battle.player_entity()
	return {"time":snappedf(battle.elapsed, 0.001), "position":[player.pos.x, player.pos.y],
		"speed":Vector2(player.vel).length(), "rpm":player.rpm, "wobble":player.wobble,
		"anchor":player.anchor_charge, "redline_seconds":player.redline_time,
		"runaway_heat":player.runaway_heat, "traces":battle.powers.traces.size(),
		"counters":battle.powers.counters.duplicate(), "hits":battle.hits}

func _capture(scenario_id: String, name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(frame != null and not frame.is_empty(), "HUD-free frame rendered")
	if frame != null:
		check(frame.save_png(capture_dir.path_join(scenario_id).path_join(name + ".png")) == OK, "HUD-free frame saved")

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return {"samples":sorted.size(), "median":sorted[sorted.size()/2], "p95":sorted[mini(sorted.size()-1, int(sorted.size()*0.95))], "max":sorted.back()}

func _play(scenario: Dictionary) -> Dictionary:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.screen_shake_enabled = true
	_initialise_fixture(battle, scenario)
	var record: Dictionary = scenario.duplicate(true)
	record["initial"] = _sample(battle)
	record["timeline"] = []
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir.path_join(str(scenario.id)))
	var cpu: Array[float] = []
	var frames: Array[float] = []
	var tick: int = 0
	var checkpoint: int = 0
	var next_sample: float = 0.1
	var next_sequence: float = 0.0
	var proc_capture_after: float = -1.0
	var proc_captured: bool = false
	var start_wall: int = Time.get_ticks_usec()
	var last_wall: int = start_wall
	while battle.elapsed + 0.000001 < SECONDS and tick < 420 and battle.battle_status != "finished":
		var input: Dictionary = _controls(battle, scenario)
		var before: int = Time.get_ticks_usec()
		battle.test_step(Physics.FIXED_DT, input.direction, bool(input.burst), bool(input.brake))
		cpu.append(float(Time.get_ticks_usec()-before)/1000.0)
		tick += 1
		if float(battle.elapsed) + 0.000001 >= next_sample:
			record.timeline.append(_sample(battle))
			next_sample += 0.1
		if DisplayServer.get_name() != "headless":
			await process_frame
			frames.append(float(Time.get_ticks_usec()-last_wall)/1000.0)
			last_wall = Time.get_ticks_usec()
		if checkpoint < 5 and battle.elapsed + 0.000001 >= 0.5 + float(checkpoint):
			await _capture(str(scenario.id), "at-%03d-ms" % roundi((0.5+float(checkpoint))*1000.0))
			checkpoint += 1
		if sequence_fps > 0 and battle.elapsed + 0.000001 >= next_sequence:
			await _capture(str(scenario.id), "sequence-%04d" % tick)
			next_sequence += 1.0/float(sequence_fps)
		if proc_capture_after < 0.0 and int(battle.powers.counters.get(str(scenario.defining_proc),0)) > 0:
			proc_capture_after = float(battle.elapsed) + 0.12
		if not proc_captured and proc_capture_after >= 0.0 and battle.elapsed >= proc_capture_after:
			await _capture(str(scenario.id), "natural-" + str(scenario.defining_proc))
			record["natural_proc_capture_seconds"] = battle.elapsed
			proc_captured = true
	check(tick < 420, "Five-second diagnostic has bounded execution")
	check(battle.elapsed + 0.000001 >= SECONDS or battle.battle_status == "finished", "Five active seconds complete or a natural result is honestly recorded")
	check(int(battle.powers.counters.get(str(scenario.defining_proc),0)) > 0, "Defining branch triggers through actual movement and contact: " + str(scenario.defining_proc))
	await _capture(str(scenario.id), "final-five-seconds")
	record["final"] = _sample(battle)
	record["result"] = battle.last_result.duplicate(true)
	record["active_seconds"] = battle.elapsed
	record["completed_five_seconds"] = battle.elapsed + 0.000001 >= SECONDS
	record["fixed_ticks"] = tick
	record["actual_proc_counters"] = battle.powers.counters.duplicate()
	record["actual_proc_events"] = battle.powers.events.duplicate(true)
	record["simulation_cpu_ms"] = _stats(cpu)
	record["draw_submission_cpu_ms"] = _stats(battle.draw_samples)
	record["render_harness_frame_ms"] = _stats(frames)
	record["harness_fixed_ticks_per_wall_second_including_png_saves"] = float(tick)*1000000.0/float(maxi(1, Time.get_ticks_usec()-start_wall))
	record["performance_scope"] = "Single HUD-free duel, measured CPU simulation/draw submission. Harness frame/rate includes waiting and capture overhead; excludes asynchronous GPU time and is not an end-user FPS claim."
	print("HUD_FREE_COMBAT ", scenario.id, " seconds=", battle.elapsed, " procs=", battle.powers.counters, " result=", battle.last_result)
	battle.free()
	return record

func _run() -> void:
	root.size = Vector2i(640,360)
	root.content_scale_size = Vector2i(640,360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	for scenario: Dictionary in SCENARIOS: report.runs.append(await _play(scenario))
	report["renderer"] = DisplayServer.get_name()
	report["gpu"] = RenderingServer.get_video_adapter_name()
	report["processor"] = OS.get_processor_name()
	report["capture_dir"] = capture_dir
	report["sequence_fps"] = sequence_fps
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	check(file != null, "Visual diagnostic report opens")
	if file != null: file.store_string(JSON.stringify(report,"\t"))
	print("ESCALATION_VISUAL_PLAYTHROUGH_%s checks=%d failures=%d report=%s" % ["PASS" if failures==0 else "FAIL",checks,failures,report_path])
	quit(1 if failures else 0)
