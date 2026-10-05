extends SceneTree
## Human-feedback regression: real solver turns, floor sparks and held input.
## No persistent profile is opened. Baseline disables only the new drift hook.
const Battle = preload("res://scripts/battle.gd")
const DT: float = 1.0 / 60.0
const BUILD: Dictionary = {"blade":"balance", "ratchet":"mid", "bit":"ball"}

class BaselineBattle extends "res://scripts/battle.gd":
	func _drift_strength(_fighter: Dictionary, _direction: Vector2, _velocity: Vector2, _braking: bool, _surface_grip: float = 1.0) -> float:
		return 0.0

class RecordingBattle extends "res://scripts/battle.gd":
	var samples: Array[Dictionary] = []
	func test_step(_dt: float, direction: Vector2 = Vector2.ZERO, burst: bool = false, brake: bool = false) -> void:
		samples.append({"direction":direction, "burst":burst, "brake":brake})

var checks: int = 0
var failures: Array[String] = []
var observations: Dictionary = {}
var report_path: String = ""

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func _new_battle(bit: String = "ball", baseline: bool = false) -> Node2D:
	var battle: Node2D = BaselineBattle.new() if baseline else Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.begin({"blade":"balance", "ratchet":"mid", "bit":bit}, BUILD, 1, 520531)
	battle.battle_status = "battle"
	var player: Dictionary = battle.player_entity()
	player.pos = Vector2.ZERO; player.vel = Vector2(180.0, 0.0); player.rpm = 0.80
	return battle

func _turn(bit: String, baseline: bool = false, particles: bool = true, braking: bool = false) -> Dictionary:
	var battle: Node2D = _new_battle(bit, baseline)
	battle.particles_enabled = particles
	var player: Dictionary = battle.player_entity()
	var mean_speed: float = 0.0
	for tick: int in range(42):
		battle._update_effects(DT)
		battle._update_fighter(player, Vector2.UP, braking, DT)
		mean_speed += Vector2(player.vel).length() / 42.0
		check(Vector2(player.vel).is_finite() and Vector2(player.pos).is_finite(), "Turn remains finite: "+bit)
		check(Vector2(player.vel).length() <= 480.001 and float(player.rpm) <= 1.0, "Turn never bypasses speed/RPM caps: "+bit)
	var result: Dictionary = {"speed":Vector2(player.vel).length(), "mean_speed":mean_speed,
		"x":Vector2(player.pos).x, "heading":Vector2(player.vel).angle(), "vx":Vector2(player.vel).x,
		"intensity":float(player.drift_intensity), "spark_clock":float(player.drift_spark_clock), "rpm":float(player.rpm), "position":player.pos,
		"velocity":player.vel, "wobble":float(player.wobble), "sparks":0}
	for particle: Dictionary in battle._particles:
		if particle.get("kind", "") == "drift": result.sparks += 1
	battle.free()
	return result

func _test_turns() -> void:
	for bit: String in ["ball", "skate", "claw", "chisel", "tripod", "freewheel", "groove"]:
		var baseline: Dictionary = _turn(bit, true)
		var drift: Dictionary = _turn(bit)
		observations[bit] = {"baseline":baseline, "drift":drift}
		check(float(drift.x) >= float(baseline.x), "Sideways turn travels farther than friction-only turn: "+bit)
		check(float(drift.mean_speed) >= float(baseline.mean_speed), "Turning retains momentum: "+bit)
		check(float(drift.heading) < -0.08, "Steering still bends actual velocity toward input: "+bit)
	var ball: Dictionary = observations.ball.drift
	var ball_base: Dictionary = observations.ball.baseline
	check(float(ball.x) > float(ball_base.x) * 1.04, "Baseline Ball has a measurable longer sweeping arc")
	check(float(ball.mean_speed) > float(ball_base.mean_speed) * 1.025, "Baseline Ball retains meaningful speed in a turn")
	check(float(observations.skate.drift.vx) > float(observations.chisel.drift.vx) * 2.0, "Skate still holds lateral drift while Chisel scrubs it")
	check(float(observations.tripod.drift.mean_speed) < float(observations.skate.drift.mean_speed), "Planted Tripod remains slower than Skate")
	var plain: Dictionary = _turn("ball", false, false)
	for field: String in ["rpm", "position", "velocity", "wobble", "intensity", "spark_clock"]:
		check(ball[field] == plain[field], "Disabling cosmetic sparks leaves solver exact: "+field)
	check(int(plain.sparks) == 0 and int(ball.sparks) > 0, "Particle preference only disables the sparks")
	var braked: Dictionary = _turn("ball", false, true, true)
	check(float(braked.speed) < float(ball.speed) * 0.25, "Braking decisively catches a drift")
	check(int(braked.sparks) == 0 and is_zero_approx(float(braked.intensity)), "Brake does not falsely report sideways drifting")

func _test_sparks() -> void:
	var battle: Node2D = _new_battle()
	var player: Dictionary = battle.player_entity()
	var enemy: Dictionary = battle.entity(2)
	for setup: Dictionary in [
		{"direction":Vector2.RIGHT, "speed":180.0, "height":0.0, "rpm":0.8, "brake":false},
		{"direction":Vector2.UP, "speed":30.0, "height":0.0, "rpm":0.8, "brake":false},
		{"direction":Vector2.ZERO, "speed":180.0, "height":0.0, "rpm":0.8, "brake":false},
		{"direction":Vector2.UP, "speed":180.0, "height":3.0, "rpm":0.8, "brake":false},
		{"direction":Vector2.UP, "speed":180.0, "height":0.0, "rpm":0.1, "brake":false},
		{"direction":Vector2.UP, "speed":180.0, "height":0.0, "rpm":0.8, "brake":true}]:
		player.height = setup.height; player.rpm = setup.rpm
		battle._update_drift_tip(player, setup.direction, Vector2(setup.speed, 0.0), setup.brake, 1.0, DT)
		check(battle._particles.is_empty(), "No floor sparks for non-skidding condition: "+str(setup))
	player.height = 0.0; player.rpm = 0.8
	enemy.height = 0.0; enemy.rpm = 0.8
	battle._update_drift_tip(enemy, Vector2.UP, Vector2(180.0, 0.0), false, 1.0, DT)
	check(battle._particles.is_empty(), "Opponent AI does not receive player drift feedback")
	var rng_state: int = battle._simulation_rng.state
	var floor_position: Vector2 = battle.project(player.pos).round()
	battle._update_drift_tip(player, Vector2.UP, Vector2(180.0, 0.0), false, 1.0, DT)
	check(battle._particles.size() in [2,3], "Genuine lateral skid emits a small bounded cluster")
	for spark: Dictionary in battle._particles:
		check(Vector2(spark.pos).distance_to(floor_position) <= 1.5, "Spark starts at physical bit/floor contact")
		check(Vector2(spark.vel).dot(Vector2(-1.0,-0.5)) > 0.0, "Spark trails behind actual movement")
		check(float(spark.life) >= 0.14 and float(spark.life) <= 0.24, "Individual spark stays brief and readable")
	check(battle._simulation_rng.state == rng_state, "Drift sparks never spend simulation RNG")
	for tick: int in range(1200):
		player.drift_spark_clock = 0.0
		battle._update_drift_tip(player, Vector2.UP, Vector2(180.0,0.0), false, 1.0, DT)
	check(battle._particles.size() <= 120, "Even forced rapid emissions stay within the shared FX bound")
	for tick: int in range(30): battle._update_effects(DT)
	check(battle._particles.is_empty(), "All drift particles expire after their skid")
	battle.free()

func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = pressed
	Input.parse_input_event(event)

func _sample(battle: RecordingBattle) -> Dictionary:
	battle._physics_process(DT)
	return battle.samples.back()

func _axis(value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = 3; event.axis = JOY_AXIS_LEFT_X; event.axis_value = value
	Input.parse_input_event(event)

func _test_resume() -> void:
	Input.use_accumulated_input = false
	var battle: RecordingBattle = RecordingBattle.new()
	battle.begin(BUILD, BUILD, 1, 520533)
	_key(KEY_D, true); _key(KEY_SPACE, true); _key(KEY_SHIFT, true)
	battle.set_paused(true)
	var count: int = battle.samples.size()
	battle._physics_process(DT)
	check(battle.samples.size() == count, "Paused draft consumes no movement samples")
	battle.set_paused(false)
	var held: Dictionary = _sample(battle)
	check(Vector2(held.direction).is_equal_approx(Vector2.RIGHT), "Held direction resumes immediately after selecting an ability")
	check(not held.burst and not held.brake, "Carried menu Confirm and Brake cannot become combat actions")
	_key(KEY_SPACE, false); _key(KEY_SHIFT, false)
	var released: Dictionary = _sample(battle)
	check(Vector2(released.direction).is_equal_approx(Vector2.RIGHT), "Button release does not require releasing steering")
	_key(KEY_SPACE, true)
	var fresh: Dictionary = _sample(battle)
	check(fresh.burst and Vector2(fresh.direction).is_equal_approx(Vector2.RIGHT), "Fresh Burst works while the same direction remains held")
	check(not bool(_sample(battle).burst), "Holding Burst still cannot repeat it")
	_key(KEY_SPACE, false)
	_sample(battle)
	battle.set_paused(true); battle.set_paused(false)
	check(Vector2(_sample(battle).direction).is_equal_approx(Vector2.RIGHT), "Ordinary pause also preserves continuous steering")
	_key(KEY_D, false)
	_axis(0.9)
	battle.set_paused(true); battle.set_paused(false)
	var analog: Dictionary = _sample(battle)
	check(Vector2(analog.direction).x > 0.70 and Vector2(analog.direction).x < 1.0, "Held analogue stick resumes with its actual partial magnitude")
	_key(KEY_SPACE, true)
	battle.set_paused(true); battle.set_paused(false)
	var analog_confirm: Dictionary = _sample(battle)
	check(Vector2(analog_confirm.direction).x > 0.70 and not analog_confirm.burst, "Held analogue steering works while carried Confirm is safely blocked")
	_key(KEY_SPACE, false)
	_sample(battle)
	_key(KEY_SPACE, true)
	check(bool(_sample(battle).burst), "Fresh Burst needs no neutral stick after analogue resume")
	_key(KEY_SPACE, false); _axis(0.0)
	battle.free()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
	_test_turns(); _test_sparks(); _test_resume()
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		check(file != null, "Explicit external QA report is writable")
		if file != null:
			file.store_string(JSON.stringify({"checks":checks, "failures":failures, "observations":observations}, "\t"))
	print("FEEDBACK_DRIFT_TEST_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
