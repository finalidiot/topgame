extends SceneTree
# Synthetic gamepad regression coverage, including a nonzero device index.
# UI routes use Input.parse_input_event through Godot's normal GUI dispatch.
# Only combat results are fixtures; no UI action or button signal is invoked.

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void:
		pass

class RecordingBattle extends "res://scripts/battle.gd":
	var samples: Array[Dictionary] = []
	func test_step(_dt: float, direction: Vector2 = Vector2.ZERO, burst: bool = false, brake: bool = false) -> void:
		samples.append({"direction":direction, "burst":burst, "brake":brake})

const Parts = preload("res://scripts/parts.gd")
const Battle = preload("res://scripts/battle.gd")
const PAD: int = 3
const DEFAULT_BUILD: Dictionary = {"blade":"balance", "ratchet":"mid", "bit":"ball"}
const DRAFT_SLOTS: Array[int] = [1, 2, 3, 4, 6, 7]
const NAV_BUTTONS: Array[JoyButton] = [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN]
var checks: int = 0
var failures: int = 0
var game: QuietMain
var capture_dir: String = ""

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	Input.use_accumulated_input = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	_test_actions_and_combat()
	_test_live_combat()
	game = QuietMain.new()
	game.smoke_mode = true
	root.add_child(game)
	await _settle()
	await _test_title_garage_settings()
	await _test_quick_duel()
	await _test_run()
	print("CONTROLLER_TEST_%s checks=%d failures=%d synthetic_device=%d physical_hardware=NOT_TESTED" % ["PASS" if failures == 0 else "FAIL", checks, failures, PAD])
	game.queue_free()
	quit(1 if failures else 0)

func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), "Rendered controller smoke capture: "+name)
	if image != null and not image.is_empty():
		check(image.save_png(capture_dir.path_join(name+".png")) == OK, "Controller smoke capture saved: "+name)

func _joy_button(index: JoyButton, pressed: bool, device: int = PAD) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = device
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)

func _axis(axis: JoyAxis, value: float, device: int = PAD) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)

func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _settle() -> void:
	if is_instance_valid(game): game.battle.set_physics_process(false)
	await process_frame
	if is_instance_valid(game): game.battle.set_physics_process(false)
	await process_frame

func _tap(index: JoyButton) -> void:
	_joy_button(index, true)
	await _settle()
	_joy_button(index, false)
	await _settle()

func _stick_tap(axis: JoyAxis, amount: float) -> void:
	_axis(axis, amount)
	await _settle()
	_axis(axis, 0.0)
	await _settle()

func _sample(battle: RecordingBattle) -> Dictionary:
	battle._physics_process(1.0 / 60.0)
	return battle.samples.back()

func _test_actions_and_combat() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down", "burst", "brake", "pause", "ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_up", "ui_down"]:
		check(InputMap.has_action(action), "Named action exists: "+action)
		var joy_bindings: int = 0
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				joy_bindings += 1
				check(event.device == -1, "Gamepad action accepts every mapped device: "+action)
		check(joy_bindings > 0, "Action has a gamepad mapping: "+action)
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		check(InputMap.action_get_deadzone(action) >= 0.18 and InputMap.action_get_deadzone(action) <= 0.3, "Steering action has a useful drift deadzone: "+action)
	var battle: RecordingBattle = RecordingBattle.new()
	battle.begin(DEFAULT_BUILD, DEFAULT_BUILD, 1, 1903)
	_axis(JOY_AXIS_LEFT_X, 0.1)
	_axis(JOY_AXIS_LEFT_Y, -0.1)
	check(Vector2(_sample(battle).direction).is_zero_approx(), "Small stick drift produces no steering")
	_axis(JOY_AXIS_LEFT_X, 0.6)
	_axis(JOY_AXIS_LEFT_Y, -0.3)
	var analog: Vector2 = _sample(battle).direction
	check(analog.x > 0.0 and analog.y < 0.0 and is_equal_approx(analog.x / -analog.y, 2.0), "Analogue steering preserves noncardinal stick angle")
	check(analog.length() > 0.1 and analog.length() < 0.8, "Partial stick deflection preserves analogue magnitude")
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	check(Vector2(_sample(battle).direction).is_equal_approx(Vector2.RIGHT), "Full stick reaches full steering on device 3")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, -1.0, 6)
	check(Vector2(_sample(battle).direction).is_equal_approx(Vector2.UP), "Another nonzero gamepad device steers without device-specific logic")
	_axis(JOY_AXIS_LEFT_Y, 0.0, 6)
	_key(KEY_D, true)
	check(Vector2(_sample(battle).direction).is_equal_approx(Vector2.RIGHT), "Keyboard steering remains available after gamepad input")
	_key(KEY_W, true)
	check(Vector2(_sample(battle).direction).is_equal_approx(Vector2(1.0, -1.0).normalized()), "Keyboard diagonal remains normalized")
	_key(KEY_D, false)
	_key(KEY_W, false)
	_key(KEY_D, true)
	_axis(JOY_AXIS_LEFT_Y, -0.6)
	var mixed: Vector2 = _sample(battle).direction
	check(mixed.x > 0.0 and mixed.y < 0.0 and mixed.length() <= 1.0001, "Keyboard and stick can feed the shared steering actions together")
	_key(KEY_D, false)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_joy_button(JOY_BUTTON_A, true)
	battle.begin(DEFAULT_BUILD, DEFAULT_BUILD, 1, 1904)
	check(not bool(_sample(battle).burst), "A held during battle launch never leaks into Burst")
	_joy_button(JOY_BUTTON_A, false)
	check(not bool(_sample(battle).burst), "Releasing launch Confirm does not Burst")
	_joy_button(JOY_BUTTON_A, true)
	check(bool(_sample(battle).burst), "A fresh primary face button press Bursts")
	check(not bool(_sample(battle).burst), "Holding Burst does not repeat")
	battle.set_paused(true)
	var sample_count: int = battle.samples.size()
	battle._physics_process(1.0 / 60.0)
	check(battle.samples.size() == sample_count, "Paused combat never receives gameplay input")
	battle.set_paused(false)
	check(not bool(_sample(battle).burst), "A held while resuming does not leak into Burst")
	_joy_button(JOY_BUTTON_A, false)
	_sample(battle)
	_joy_button(JOY_BUTTON_A, true, 6)
	check(bool(_sample(battle).burst), "Fresh Burst works on another mapped device after resume")
	_joy_button(JOY_BUTTON_A, false, 6)
	_sample(battle)
	_key(KEY_SPACE, true)
	check(bool(_sample(battle).burst), "Keyboard Burst coexists with the gamepad")
	_key(KEY_SPACE, false)
	_sample(battle)
	for shoulder: JoyButton in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_joy_button(shoulder, true)
		check(bool(_sample(battle).brake), "Shoulder button brakes through shared action")
		_joy_button(shoulder, false)
		check(not bool(_sample(battle).brake), "Releasing shoulder clears brake")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.1)
	check(not bool(_sample(battle).brake), "Trigger noise does not brake")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	check(bool(_sample(battle).brake), "Right trigger provides an ergonomic brake action")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.9)
	check(bool(_sample(battle).brake), "Left trigger also provides an ergonomic brake action")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_key(KEY_SHIFT, true)
	check(bool(_sample(battle).brake), "Keyboard brake remains available")
	_key(KEY_SHIFT, false)
	check(not bool(_sample(battle).brake), "Releasing all brake controls clears the action")
	battle.free()

func _launch_live(battle: Node2D) -> void:
	battle.begin(DEFAULT_BUILD, DEFAULT_BUILD, 1, 6137)
	for tick: int in range(240):
		if battle.battle_status == "battle": break
		battle._physics_process(1.0 / 60.0)
	check(battle.battle_status == "battle", "Live controller fixture completes the normal launch countdown")

func _test_live_combat() -> void:
	# Compare identical seeded live simulations, including their normal launch.
	var controlled: Node2D = Battle.new()
	var coasting: Node2D = Battle.new()
	_launch_live(controlled)
	_launch_live(coasting)
	for tick: int in range(8): coasting._physics_process(1.0 / 60.0)
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_LEFT_Y, 0.35)
	for tick: int in range(8): controlled._physics_process(1.0 / 60.0)
	var steered_position: Vector2 = controlled.project(controlled.player_entity().pos)
	var coast_position: Vector2 = coasting.project(coasting.player_entity().pos)
	check(steered_position.x > coast_position.x + 0.1, "Real controller steering changes live position in the requested screen direction")
	var before_rpm: float = controlled.player_entity().rpm
	var before_velocity: Vector2 = controlled.player_entity().vel
	_joy_button(JOY_BUTTON_A, true)
	controlled._physics_process(1.0 / 60.0)
	_joy_button(JOY_BUTTON_A, false)
	check(float(controlled.player_entity().cooldown) > 3.9, "Real controller Burst starts the live cooldown")
	check(float(controlled.player_entity().rpm) < before_rpm - 0.01, "Real controller Burst pays its spin cost")
	check(Vector2(controlled.player_entity().vel).distance_to(before_velocity) > 40.0, "Real controller Burst applies a substantial live impulse")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_launch_live(controlled)
	_launch_live(coasting)
	for tick: int in range(8): coasting._physics_process(1.0 / 60.0)
	_joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	for tick: int in range(8): controlled._physics_process(1.0 / 60.0)
	_joy_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	check(Vector2(controlled.player_entity().vel).length() < Vector2(coasting.player_entity().vel).length(), "Real shoulder braking slows a live top relative to identical seeded coasting")
	controlled.free()
	coasting.free()

func _descendants(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in parent.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result

func _button(text: String) -> Button:
	for node: Node in _descendants(game.menus):
		if node is Button and node.text == text: return node
	return null

func _focus_is_visible(context: String) -> void:
	var focused: Control = root.gui_get_focus_owner()
	check(focused != null, context+": an initial control owns focus")
	if focused == null: return
	check(focused.is_visible_in_tree() and focused.focus_mode == Control.FOCUS_ALL, context+": focused control is visible and navigable")
	check(Rect2(Vector2.ZERO, Vector2(640, 360)).encloses(focused.get_global_rect()), context+": focused control is inside the viewport")
	var style: StyleBoxFlat = focused.get_theme_stylebox("focus") as StyleBoxFlat
	check(style != null and style.border_color.a > 0.0 and style.get_border_width(SIDE_LEFT) > 0, context+": focus has a visible border")

func _navigate(target: Control) -> bool:
	check(target != null, "Requested navigation target exists")
	if target == null: return false
	var origin: Control = root.gui_get_focus_owner()
	if origin == target: return true
	check(origin != null, "Menu navigation begins with visible focus")
	if origin == null: return false
	var frontier: Array[Control] = [origin]
	var paths: Dictionary = {origin:[]}
	while not frontier.is_empty() and not paths.has(target):
		var current: Control = frontier.pop_front()
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			# Sliders consume horizontal UI input to change their value.
			if current is Slider and side in [SIDE_LEFT, SIDE_RIGHT]: continue
			var next: Control = current.find_valid_focus_neighbor(side)
			if next == null or paths.has(next): continue
			var path: Array = paths[current].duplicate()
			path.append({"side":side, "control":next})
			paths[next] = path
			frontier.append(next)
	check(paths.has(target), "D-pad focus graph can reach "+str(target.name))
	if not paths.has(target): return false
	for step: Dictionary in paths[target]:
		await _tap(NAV_BUTTONS[int(step.side)])
		check(root.gui_get_focus_owner() == step.control, "Real D-pad event follows Godot's focus neighbor")
		if root.gui_get_focus_owner() != step.control: return false
	check(root.gui_get_focus_owner() == target, "Gamepad reaches the requested control")
	return root.gui_get_focus_owner() == target

func _activate(text: String) -> void:
	if await _navigate(_button(text)): await _tap(JOY_BUTTON_A)

func _test_title_garage_settings() -> void:
	check(game.screen == "title", "Fresh game opens title")
	_focus_is_visible("Title")
	check(root.gui_get_focus_owner() == _button("QUICK DUEL"), "Title defaults to Quick Duel")
	await _capture("01-controller-title")
	var initial: Control = root.gui_get_focus_owner()
	await _stick_tap(JOY_AXIS_LEFT_Y, 0.1)
	check(root.gui_get_focus_owner() == initial, "Stick drift never moves menu focus")
	await _stick_tap(JOY_AXIS_LEFT_Y, 0.9)
	check(root.gui_get_focus_owner() == _button("EIGHT-ENCOUNTER RUN"), "Left stick navigates the title")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == _button("CUSTOMIZE TOP"), "D-pad navigation coexists with stick navigation")
	await _tap(JOY_BUTTON_A)
	check(game.screen == "garage", "Controller Confirm opens garage")
	_focus_is_visible("Garage")
	for category: String in ["blade", "ratchet", "bit"]:
		for id: String in Parts.PARTS[category]:
			var part: Control = game.menus._part_buttons[category][id]
			if await _navigate(part): await _tap(JOY_BUTTON_A)
			check(game.build[category] == id, "Gamepad selects %s part %s" % [category, id])
	await _capture("02-controller-garage")
	var lost: Control = root.gui_get_focus_owner()
	lost.release_focus()
	await _settle()
	await _tap(JOY_BUTTON_DPAD_UP)
	_focus_is_visible("Recovered garage focus")
	await _tap(JOY_BUTTON_B)
	check(game.screen == "title", "Back returns from garage to title")
	await _activate("HOW TO PLAY")
	check(game.screen == "help", "Controller opens help")
	_focus_is_visible("Help")
	await _capture("03-controller-help")
	await _navigate(_button("QUICK DUEL"))
	await _tap(JOY_BUTTON_B)
	check(game.screen == "title", "Back closes help")
	await _activate("SETTINGS")
	check(game.screen == "settings", "Controller opens settings")
	_focus_is_visible("Settings")
	await _capture("04-controller-settings")
	var slider: HSlider
	var toggles: Array[Button] = []
	for node: Node in _descendants(game.menus):
		if node is HSlider: slider = node
		if node is Button and node.text in ["ON", "OFF"]: toggles.append(node)
	if await _navigate(slider):
		check(slider.get_node("FocusOutline").visible, "Focused volume slider displays its actual outline control")
		var volume: float = game.settings.volume
		await _tap(JOY_BUTTON_DPAD_LEFT)
		check(float(game.settings.volume) < volume, "Gamepad changes volume with slider focus")
		await _tap(JOY_BUTTON_DPAD_RIGHT)
		check(is_equal_approx(float(game.settings.volume), volume), "Slider supports both horizontal directions")
	var setting_keys: Array[String] = ["muted", "screen_shake", "fullscreen"]
	check(toggles.size() == setting_keys.size(), "All settings toggles are present")
	for index: int in range(mini(toggles.size(), setting_keys.size())):
		var before: bool = game.settings[setting_keys[index]]
		if await _navigate(toggles[index]): await _tap(JOY_BUTTON_A)
		check(not slider.get_node("FocusOutline").visible, "Volume focus outline hides when controller focus moves to a toggle")
		check(bool(game.settings[setting_keys[index]]) != before, "Controller toggles %s" % setting_keys[index])
	await _activate("BACK TO MENU")
	check(game.screen == "title", "Controller settings Back button returns to title")
	await _navigate(_button("HOW TO PLAY"))
	_key(KEY_ENTER, true)
	await _settle()
	_key(KEY_ENTER, false)
	await _settle()
	check(game.screen == "help", "Keyboard Confirm still works after controller navigation")
	_key(KEY_ESCAPE, true)
	await _settle()
	_key(KEY_ESCAPE, false)
	await _settle()
	check(game.screen == "title", "Keyboard Back still works after gamepad use")

func _test_quick_duel() -> void:
	await _activate("QUICK DUEL")
	check(game.screen == "battle" and game.mode == "duel", "Controller launches Quick Duel from title")
	await _capture("05-controller-duel")
	check(root.gui_get_focus_owner() == null, "Combat HUD does not retain a menu Confirm target")
	await _stick_tap(JOY_AXIS_LEFT_X, 0.9)
	check(root.gui_get_focus_owner() == null and game.screen == "battle", "Combat steering never moves focus to the HUD Pause button")
	_joy_button(JOY_BUTTON_A, true)
	_key(KEY_SPACE, true)
	await _settle()
	await _tap(JOY_BUTTON_START)
	check(game.screen == "pause" and game.battle.paused, "Start pauses Quick Duel")
	_focus_is_visible("Duel pause")
	await _capture("06-controller-pause")
	_joy_button(JOY_BUTTON_A, false)
	await _settle()
	check(game.screen == "pause", "Releasing a face button held before pause cannot activate Resume")
	check(game.menus._accept_needs_release, "Releasing one Confirm binding does not rearm while another binding is held")
	_key(KEY_SPACE, true, true)
	await _settle()
	check(game.screen == "pause", "A held keyboard echo cannot confirm a newly opened controller pause screen")
	_key(KEY_SPACE, false)
	await _settle()
	check(game.screen == "pause", "Releasing the remaining old Confirm does not activate Resume")
	var before: Dictionary = game.battle.snapshot()
	_axis(JOY_AXIS_LEFT_X, 0.9)
	_joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	game.battle._physics_process(1.0 / 60.0)
	check(game.battle.snapshot() == before, "Paused live battle ignores controller steering and brake")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_joy_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	await _tap(JOY_BUTTON_START)
	check(game.screen == "battle" and not game.battle.paused, "Start resumes Quick Duel")
	await _tap(JOY_BUTTON_B)
	check(game.screen == "pause" and game.battle.paused, "Back also opens the combat pause menu")
	await _tap(JOY_BUTTON_B)
	check(game.screen == "battle" and not game.battle.paused, "Back resumes the combat pause menu")
	await _tap(JOY_BUTTON_START)
	await _activate("RESUME")
	check(game.screen == "battle" and not game.battle.paused, "Controller Confirm resumes from the pause button")
	await _tap(JOY_BUTTON_START)
	await _activate("RESTART DUEL")
	check(game.screen == "battle" and game.battle.battle_status == "countdown", "Controller restarts Quick Duel")
	_result(true)
	await _settle()
	_focus_is_visible("Duel result")
	await _capture("07-controller-duel-result")
	await _activate("REMATCH")
	check(game.screen == "battle" and game.mode == "duel", "Controller selects result Rematch")
	_result(false)
	await _settle()
	await _activate("CUSTOMIZE TOP")
	check(game.screen == "garage", "Controller selects result customization")
	await _activate("QUICK DUEL")
	check(game.screen == "battle" and game.mode == "duel", "Controller launches Quick Duel from garage")
	await _tap(JOY_BUTTON_START)
	await _activate("MAIN MENU")
	check(game.screen == "title", "Controller leaves Quick Duel through pause menu")

func _result(won: bool) -> void:
	var result: Dictionary = {"won":won, "reason":"ring_out" if won else "spin_out", "duration":24.0, "hits":5}
	if game.mode == "run":
		var encounter: Dictionary = game.run_context.current_encounter()
		result.merge({"encounter_id":encounter.id, "seed":encounter.seed})
	game._round_finished(result)

func _test_run() -> void:
	await _activate("EIGHT-ENCOUNTER RUN")
	check(game.screen == "battle" and game.run_context.slot == 1, "Controller launches Run from title")
	var old_seed: int = game.run_context.run_seed
	await _tap(JOY_BUTTON_START)
	_focus_is_visible("Run pause")
	await _activate("RESTART RUN")
	check(game.screen == "battle" and game.run_context.slot == 1 and game.run_context.run_seed != old_seed, "Pause Restart Run resets to a fresh Run")
	_result(false)
	await _settle()
	check(game.screen == "result" and game.run_context.status == "failed", "Failure opens the Run result screen")
	_focus_is_visible("Run failure")
	await _capture("08-controller-run-failure")
	old_seed = game.run_context.run_seed
	await _activate("RESTART RUN")
	check(game.screen == "battle" and game.run_context.run_seed != old_seed, "Controller restarts a failed Run")
	for slot: int in range(1, 9):
		check(game.screen == "battle" and game.run_context.slot == slot, "Controller flow reaches Run encounter %d" % slot)
		if slot == 1 or slot == 8:
			_joy_button(JOY_BUTTON_A, true)
			await _settle()
		_result(true)
		await _settle()
		if slot == 1 or slot == 8:
			var original_screen: String = game.screen
			var original_seed: int = game.run_context.run_seed
			_joy_button(JOY_BUTTON_A, false)
			await _settle()
			check(game.screen == original_screen and game.run_context.slot == slot and game.run_context.run_seed == original_seed, "Held combat face button cannot confirm newly opened draft/completion")
		if slot in DRAFT_SLOTS:
			check(game.screen == "reward", "Controller flow opens draft after encounter %d" % slot)
			_focus_is_visible("Run power draft %d" % slot)
			var offer: Array = game.run_context.pending_offer.duplicate()
			var cards: Array[Button] = []
			for node: Node in _descendants(game.menus):
				if node is Button: cards.append(node)
			check(cards.size() == mini(3, 6 - game.run_context.owned_power_ids.size()) and root.gui_get_focus_owner() == cards[0], "Draft opens with its first real available card focused")
			for index: int in range(1, cards.size()):
				if index == 1: await _tap(JOY_BUTTON_DPAD_RIGHT)
				else: await _stick_tap(JOY_AXIS_LEFT_X, 0.9)
				check(root.gui_get_focus_owner() == cards[index], "Controller reaches each available draft card")
			await _tap(JOY_BUTTON_DPAD_RIGHT)
			check(root.gui_get_focus_owner() == cards[0], "Draft wraps safely with one, two, or three cards")
			var chosen_index: int = mini(1, cards.size() - 1)
			if chosen_index > 0: await _tap(JOY_BUTTON_DPAD_RIGHT)
			if slot == 1: await _capture("09-controller-draft-middle-focus")
			await _tap(JOY_BUTTON_B)
			check(game.screen == "pause" and game.pause_origin == "reward", "Controller Back opens draft overlay")
			_focus_is_visible("Draft overlay")
			if slot == 1: await _capture("10-controller-draft-overlay")
			check(game.run_context.pending_offer == offer, "Opening overlay retains stored offer")
			await _tap(JOY_BUTTON_B)
			check(game.screen == "reward" and game.run_context.pending_offer == offer, "Back resumes the identical stored offer")
			_focus_is_visible("Restored draft")
			check(game.menus.focused_power_id() == offer[chosen_index], "Draft reopening preserves the focused power")
			var owned_before: int = game.run_context.owned_power_ids.size()
			await _tap(JOY_BUTTON_A)
			check(game.screen == "acquisition" and game.run_context.slot == slot, "Confirm opens a brief acquisition beat before launch")
			check(game.run_context.owned_power_ids.size() == owned_before + 1 and game.run_context.owned_power_ids.back() == offer[chosen_index], "Confirm collects precisely the focused card")
			await _tap(JOY_BUTTON_A)
			check(game.run_context.owned_power_ids.size() == owned_before + 1 and game.run_context.slot == slot, "Repeated Confirm during feedback cannot acquire or advance twice")
			if slot == 1:
				await _capture("09b-controller-acquired")
				await _tap(JOY_BUTTON_B)
				check(game.screen == "pause" and game.pause_origin == "acquisition", "Controller can pause the acquisition beat")
				await _tap(JOY_BUTTON_B)
				check(game.screen == "acquisition", "Controller resumes the acquisition beat")
			await create_timer(0.7).timeout
			await _settle()
			check(game.screen == "battle" and game.run_context.slot == slot + 1, "Acquisition launches the next encounter without extra input")
			await _tap(JOY_BUTTON_A)
			check(game.run_context.owned_power_ids.size() == owned_before + 1 and game.run_context.slot == slot + 1, "Rapid repeated Confirm cannot acquire another power or skip an encounter")
		elif slot == 5:
			_focus_is_visible("Run intermediate result")
			check(game.screen == "result", "Encounter 5 opens a navigable result")
			await _tap(JOY_BUTTON_B)
			check(game.screen == "pause" and game.pause_origin == "result", "Back opens overlay from intermediate Run result")
			await _tap(JOY_BUTTON_B)
			check(game.screen == "result", "Back restores intermediate Run result")
			await _activate("NEXT ENCOUNTER")
			check(game.screen == "battle" and game.run_context.slot == 6, "Controller result Confirm advances to encounter 6")
		else:
			check(game.screen == "result" and game.run_context.status == "complete", "Controller flow completes all eight encounters")
			_focus_is_visible("Run completion")
			await _capture("11-controller-run-complete")
	check(game.run_context.owned_power_ids.size() == 6, "Completed controller Run collected six powers")
	old_seed = game.run_context.run_seed
	await _activate("RESTART RUN")
	check(game.screen == "battle" and game.run_context.slot == 1 and game.run_context.run_seed != old_seed, "Controller restarts a completed Run")
	_result(true)
	await _settle()
	check(game.screen == "reward", "Restarted Run reopens a draft before End Run, observed "+game.screen)
	await _tap(JOY_BUTTON_B)
	check(game.screen == "pause", "Back opens restarted Run draft overlay, observed "+game.screen)
	await _activate("END RUN")
	check(game.screen == "garage" and game.run_context.status == "empty", "Controller ends Run from draft overlay")
	_focus_is_visible("Garage after End Run")
	await _activate("EIGHT-ENCOUNTER RUN")
	check(game.screen == "battle" and game.run_context.slot == 1, "Controller launches Run from garage")
	await _tap(JOY_BUTTON_START)
	await _activate("END RUN")
	check(game.screen == "garage" and game.run_context.status == "empty", "Controller ends Run from battle pause")
	await _tap(JOY_BUTTON_B)
	check(game.screen == "title", "Controller returns to title after ending Run")
