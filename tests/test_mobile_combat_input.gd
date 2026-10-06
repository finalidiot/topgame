extends SceneTree
## Synthetic mapped events through the actual Main-owned input provider and
## unmodified live Battle solver. These tests do not claim physical hardware QA.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
const Battle = preload("res://scripts/battle.gd")
const Touch = preload("res://scripts/touch_controls.gd")
const BUILD: Dictionary = {"blade":"guard","ratchet":"low","bit":"ball"}
const PAD: int = 5
var checks: int = 0
var failures: Array[String] = []
var games: Array[QuietMain] = []
var before: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func snapshot(path: String) -> Dictionary:
	return {"exists":FileAccess.file_exists(path),"bytes":FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}
func key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = pressed
	Input.parse_input_event(event)
func pad(button: JoyButton, pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = PAD; event.button_index = button; event.pressed = pressed
	Input.parse_input_event(event)
func axis(which: JoyAxis, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = PAD; event.axis = which; event.axis_value = value
	Input.parse_input_event(event)
func touch(game: QuietMain, finger: int, point: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = finger; event.position = point; event.pressed = pressed
	game.touch_controls.handle_touch(event)
func drag(game: QuietMain, finger: int, point: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = finger; event.position = point
	game.touch_controls.handle_touch(event)
func neutral() -> void:
	for code: Key in [KEY_SPACE,KEY_SHIFT,KEY_A,KEY_D,KEY_W,KEY_S]: key(code,false)
	for button: JoyButton in [JOY_BUTTON_A,JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]: pad(button,false)
	axis(JOY_AXIS_LEFT_X,0.0); axis(JOY_AXIS_LEFT_Y,0.0)
	axis(JOY_AXIS_TRIGGER_LEFT,0.0); axis(JOY_AXIS_TRIGGER_RIGHT,0.0)
func make_game() -> QuietMain:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = "user://test_collection/mobile_provider_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()]
	root.add_child(game)
	game.set_process(false)
	game.battle.set_physics_process(false)
	games.append(game)
	check(game.battle.input_provider == game.touch_controls,"Actual Main connects its owned touch provider to live Battle")
	return game
func launch(game: QuietMain) -> void:
	neutral()
	game.touch_controls.set_enabled(false)
	for finger: int in game.touch_controls.blocked.keys(): touch(game,finger,Vector2.ZERO,false)
	game.screen = "battle"; game.mode = "duel"
	# Legal deterministic opening fixture, followed only by real control samples.
	game.battle.begin(BUILD,BUILD,1,6137)
	game.battle.set_physics_process(false)
	game._process(0.0)
	for tick: int in range(240):
		if game.battle.battle_status == "battle": break
		game.battle._physics_process(Battle.FIXED_DT)
	check(game.battle.battle_status == "battle" and game.touch_controls.enabled,"Normal launch completes with Main's provider enabled")
	game.battle._physics_process(Battle.FIXED_DT)
func ticks(game: QuietMain, count: int) -> void:
	for tick: int in range(count): game.battle._physics_process(Battle.FIXED_DT)
func check_fresh_burst(game: QuietMain, label: String) -> void:
	var player: Dictionary = game.battle.player_entity()
	var rpm: float = player.rpm
	var velocity: Vector2 = player.vel
	ticks(game,1)
	check(float(player.cooldown) > 3.9 and float(player.burst_time) > 0.39,label + " starts one actual cooldown and Burst window")
	check(float(player.rpm) < rpm - 0.01,label + " pays real RPM")
	check(Vector2(player.vel).distance_to(velocity) > 40.0,label + " applies the real physical impulse")
func check_hold_and_fresh(game: QuietMain, kind: String) -> void:
	var player: Dictionary = game.battle.player_entity()
	var previous: float = player.cooldown
	var unexpected: int = 0
	for tick: int in range(265):
		ticks(game,1)
		var now: float = player.cooldown
		if now > previous + 1.0: unexpected += 1
		previous = now
	check(game.battle.battle_status == "battle","Held " + kind + " test remains in actual live combat")
	check(unexpected == 0 and float(player.cooldown) <= 0.0,"Held " + kind + " never repeats after the full four-second cooldown")
	if kind == "keyboard": key(KEY_SPACE,false)
	elif kind == "gamepad": pad(JOY_BUTTON_A,false)
	else: touch(game,1,Touch.BURST_RECT.get_center(),false)
	ticks(game,1)
	check(float(player.cooldown) <= 0.0,"Releasing " + kind + " does not Burst")
	if kind == "keyboard": key(KEY_SPACE,true)
	elif kind == "gamepad": pad(JOY_BUTTON_A,true)
	else: touch(game,1,Touch.BURST_RECT.get_center(),true)
	ticks(game,1)
	check(float(player.cooldown) > 3.9,"A new " + kind + " activation after release starts exactly one fresh Burst")

func run() -> void:
	Input.use_accumulated_input = false
	for path: String in ["user://collection.json","user://collection.json.bak","user://prototype.cfg","user://last_run_director.json"]: before[path] = snapshot(path)
	var game: QuietMain = make_game()
	for kind: String in ["keyboard","gamepad","touch"]:
		launch(game)
		if kind == "keyboard": key(KEY_SPACE,true)
		elif kind == "gamepad": pad(JOY_BUTTON_A,true)
		else: touch(game,1,Touch.BURST_RECT.get_center(),true)
		check_fresh_burst(game,"Fresh " + kind + " through Main's touch provider")
		check_hold_and_fresh(game,kind)
	# Provider preserves keyboard/pad steering and Brake fallback, then switches
	# to owned touch steering while leaving the other action fingers independent.
	launch(game)
	key(KEY_D,true)
	check(Vector2(game.touch_controls.sample().direction) == Vector2.RIGHT,"Main provider preserves full keyboard steering")
	key(KEY_D,false); axis(JOY_AXIS_LEFT_X,0.6); axis(JOY_AXIS_LEFT_Y,-0.3)
	var analog: Vector2 = game.touch_controls.sample().direction
	check(analog.x > 0.0 and analog.y < 0.0 and analog.length() < 0.8 and is_equal_approx(analog.x/-analog.y,2.0),"Main provider preserves noncardinal analogue gamepad steering")
	neutral()
	touch(game,0,Vector2(180,180),true); drag(game,0,Vector2(206,193))
	var prepared: Vector2 = game.touch_controls.direction
	touch(game,1,Touch.BURST_RECT.get_center(),true); touch(game,2,Touch.BRAKE_RECT.get_center(),true)
	var controls: Dictionary = game.touch_controls.sample()
	check(controls.direction == prepared and controls.burst and controls.brake and game.touch_controls.owners.size() == 3,"Main provider simultaneously owns analogue steering, Burst and Brake")
	check_fresh_burst(game,"Simultaneous touch Burst and Brake")
	touch(game,1,Touch.BURST_RECT.get_center(),false)
	check(game.touch_controls.action_down("brake") and game.touch_controls.direction == prepared,"Releasing Burst preserves the other two owned fingers")
	touch(game,2,Touch.BRAKE_RECT.get_center(),false)
	key(KEY_SHIFT,true)
	check(bool(game.touch_controls.sample().brake),"Keyboard Brake remains available through Main provider")
	key(KEY_SHIFT,false); pad(JOY_BUTTON_RIGHT_SHOULDER,true)
	check(bool(game.touch_controls.sample().brake),"Gamepad Brake remains available through Main provider")
	neutral()
	# Actual Main pause/resume clears old contacts, preserves all solver state,
	# accepts preparation in the countdown and consumes no held action at GO.
	game._pause()
	check(game.screen == "pause" and game.battle.paused and game.touch_controls.owners.is_empty(),"Actual Main pause clears finger ownership and freezes live combat")
	touch(game,0,Vector2.ZERO,false)
	game._resume(); game._process(0.0)
	check(game.screen == "battle" and game.battle.battle_status == "reentry" and game.touch_controls.enabled,"Actual Main resume enables preparation during its real countdown")
	touch(game,0,Vector2(180,180),true); drag(game,0,Vector2(210,190))
	touch(game,1,Touch.BURST_RECT.get_center(),true); touch(game,2,Touch.BRAKE_RECT.get_center(),true)
	var player: Dictionary = game.battle.player_entity()
	var frozen: Dictionary = {"pos":player.pos,"vel":player.vel,"rpm":player.rpm,"elapsed":game.battle.elapsed,"power_time":game.battle.powers.time,"cooldown":player.cooldown}
	for tick: int in range(74):
		ticks(game,1)
		check(player.pos == frozen.pos and player.vel == frozen.vel and player.rpm == frozen.rpm and game.battle.elapsed == frozen.elapsed and game.battle.powers.time == frozen.power_time and player.cooldown == frozen.cooldown,"Prepared touch input cannot advance live physics or powers during reentry")
	check(game.battle.battle_status == "reentry" and not game.touch_controls.direction.is_zero_approx(),"Prepared analogue steering waits for GO")
	ticks(game,3)
	check(game.battle.battle_status == "battle" and game.battle._burst_buffer == 0.0,"Reentry reaches GO without converting held Burst into a buffered activation")
	var cooldown_before: float = player.cooldown
	ticks(game,1)
	check(float(player.cooldown) <= cooldown_before and game.battle.elapsed > frozen.elapsed,"Held countdown actions cannot create a new Burst on the first live tick")
	touch(game,1,Touch.BURST_RECT.get_center(),false); touch(game,2,Touch.BRAKE_RECT.get_center(),false)
	ticks(game,1)
	check(not game.battle._combat_needs_release,"Releasing both countdown actions arms the next real activation")
	# Cleanup releases all mapped synthetic input and only isolated fixture apps.
	neutral()
	for item: QuietMain in games: item.free()
	for path: String in before: check(snapshot(path) == before[path],"Main provider tests preserve the real player profile: " + path)
	print("MOBILE_COMBAT_INPUT_TEST_%s checks=%d failures=%d hardware=NOT_CLAIMED" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
