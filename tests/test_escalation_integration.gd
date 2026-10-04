extends SceneTree
## Controlled XP fixtures exercise real claims and mapped gamepad navigation.
## This is UI/state evidence; it does not measure physical-controller feel.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass

const Powers = preload("res://scripts/run_powers.gd")
const Parts = preload("res://scripts/parts.gd")
const PAD: int = 3
var game: QuietMain
var checks: int = 0
var failures: int = 0
var sequence: int = 0
var event_time: float = 0.0
var captures: String = ""

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _settle() -> void:
	game.battle.set_physics_process(false)
	await process_frame
	game.battle.set_physics_process(false)
	await process_frame

func _button(index: JoyButton, pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = PAD
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)

func _tap(index: JoyButton) -> void:
	_button(index, true)
	await _settle()
	_button(index, false)
	await _settle()

func _axis(amount: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = PAD
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = amount
	Input.parse_input_event(event)

func _body_state() -> Dictionary:
	var result: Dictionary = {}
	for id: int in game.battle.snapshot().entities:
		var fighter: Dictionary = game.battle.entity(id)
		var body: Dictionary = {}
		for field: String in ["pos", "vel", "rpm", "wobble", "cooldown", "phase", "second_wind_used", "anchor_charge", "stored_force"]:
			body[field] = fighter.get(field)
		result[id] = body
	result["elapsed"] = game.battle.elapsed
	result["power_time"] = game.battle.powers.time
	result["schedule"] = game.battle.swarm.schedule.duplicate(true)
	return result

func _earn_offer() -> void:
	var guard: int = 0
	while game.run_context.pending_offer.is_empty() and not game.run_context.progression_snapshot().maxed and guard < 30:
		guard += 1
		sequence += 1
		event_time += 1.3
		game._progression_events([{"kind":"collision", "encounter_id":game.run_context.current_encounter().id,
			"time":event_time, "event_id":"mutation-ui/%d" % sequence,
			"first_entity_id":1, "second_entity_id":2, "severity":0.9, "player_attributed":true}])
	game._process(0.19)
	check(game.screen == "reward", "Earned investment safely opens its stored offer")

func _claim(power_id: String) -> void:
	game._action("choose_power", {"encounter_id":game.run_context.pending_draft_id,"power_id":power_id,"run_seed":game.run_context.run_seed})
	if game.screen == "mutation":
		game._action("choose_mutation", {"encounter_id":game.run_context.pending_draft_id,"branch_id":game.run_context.pending_mutation_offer[0],"run_seed":game.run_context.run_seed})
	game._process(1.1)
	game.battle.set_physics_process(false)

func _prepare_target(power_id: String) -> void:
	game._clear_run()
	game.run_context.start(Parts.DEFAULT_BUILD, 421, "custom")
	game.mode = "run"
	game._draft_resume_origin = "starting"
	game._show_reward()
	event_time = 0.0
	for _investment: int in range(13):
		var chosen: String = power_id if power_id in game.run_context.pending_offer else game.run_context.pending_offer[0]
		_claim(chosen)
		if int(game.run_context.power_ranks.get(power_id, 0)) >= 2: break
		_earn_offer()
	check(int(game.run_context.power_ranks.get(power_id, 0)) == 2, "Repeated real claims reach rank II for " + power_id)
	game.battle.battle_status = "battle"
	_earn_offer()
	for _investment: int in range(13):
		if power_id in game.run_context.pending_offer: break
		_claim(game.run_context.pending_offer[0])
		_earn_offer()
	check(power_id in game.run_context.pending_offer, "An owned rank II power reappears as a mutation offer")

func _hide_hud() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F2
	event.pressed = true
	game._unhandled_input(event)
	check(not game.menus.visible, "F2 hides only the combat presentation for inspection")

func _test_hidden_hud_transitions() -> void:
	game._start_build_practice("runaway")
	game.battle.set_physics_process(false)
	_hide_hud()
	game._round_finished({"won":false,"reason":"spin_out","duration":5.0})
	await _settle()
	check(game.screen == "result" and game.menus.visible, "Results restore visibility after HUD-free combat")
	await _tap(JOY_BUTTON_A)
	check(game.screen == "battle" and game._practice_branch == "runaway", "Visible result Confirm restarts the same practice build")
	_prepare_target("redline")
	_claim(game.run_context.pending_offer[0])
	game.battle.battle_status = "battle"
	_hide_hud()
	_earn_offer()
	check(game.menus.visible, "An earned choice restores visibility after HUD-free combat")

func _nodes(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in parent.get_children():
		result.append(child)
		result.append_array(_nodes(child))
	return result

func _check_layout() -> void:
	for node: Node in _nodes(game.menus):
		if node is Label:
			check(Rect2(0,0,640,360).encloses(node.get_global_rect()), "Text stays in native viewport: " + node.text)
			var font: Font = node.get_theme_font("font")
			var font_size: int = node.get_theme_font_size("font_size")
			if node.autowrap_mode == TextServer.AUTOWRAP_OFF:
				check(font.get_string_size(node.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= node.size.x + 0.1, "Unwrapped text fits: " + node.text)
			var height: float = 0.0
			for line: int in range(node.get_line_count()): height += node.get_line_height(line)
			height += maxi(0, node.get_line_count()-1) * node.get_theme_constant("line_spacing")
			check(height <= node.size.y + 0.1, "Shaped text lines fit: " + node.text)

func _capture(name: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(frame != null and not frame.is_empty(), "Rendered " + name)
	if frame != null: check(frame.save_png(captures.path_join(name + ".png")) == OK, "Saved " + name)

func _test_branch(power_id: String, branch_id: String) -> void:
	_prepare_target(power_id)
	await _settle()
	for _move: int in range(3):
		if game.menus.focused_power_id() == power_id: break
		await _tap(JOY_BUTTON_DPAD_RIGHT)
	check(game.menus.focused_power_id() == power_id, "D-pad reaches owned mutation offer")
	var body: Dictionary = _body_state()
	var runtime: Object = game.battle.powers
	var draft_id: String = game.run_context.pending_draft_id
	_button(JOY_BUTTON_A, true)
	await _settle()
	check(game.screen == "mutation" and game.battle.paused, "Mapped Confirm opens dedicated mutation event")
	check(game.run_context.pending_draft_id == draft_id and int(game.run_context.power_ranks[power_id]) == 2, "Opening branches does not consume or prematurely upgrade")
	check(game.menus._accept_needs_release, "Held draft Confirm is gated on mutation screen")
	game._process(10.0)
	game.battle.test_step(0.25, Vector2.RIGHT, true, true)
	check(game.screen == "mutation" and _body_state() == body, "Waiting and combat inputs preserve exact encounter during mutation")
	_button(JOY_BUTTON_A, false)
	await _settle()
	check(game.screen == "mutation", "Release of old Confirm cannot commit a branch")
	var branches: Array = game.run_context.pending_mutation_offer
	check(branches == Powers.mutation_choices(power_id), "Only the two valid branches appear")
	var cards: Array[Button] = []
	for node: Node in _nodes(game.menus):
		if node is Button: cards.append(node)
	check(cards.size() == 2 and cards[0].size.x > 192, "Mutation uses two larger opposing cards")
	_check_layout()
	await _capture("mutation-" + power_id)
	await _tap(JOY_BUTTON_DPAD_LEFT)
	check(game.menus.focused_power_id() == str(branches[1]), "D-pad wraps through opposing mutation branches")
	_axis(0.9)
	await _settle()
	var focused: String = game.menus.focused_power_id()
	_axis(0.8)
	await _settle()
	check(game.menus.focused_power_id() == focused, "Held analogue input moves once on mutation screen")
	_axis(0.0)
	await _settle()
	if focused != branch_id: await _tap(JOY_BUTTON_DPAD_RIGHT)
	check(game.menus.focused_power_id() == branch_id, "Controller reaches requested branch " + branch_id)
	await _tap(JOY_BUTTON_START)
	check(game.screen == "pause" and game.pause_origin == "mutation", "Start opens pause over a pending mutation")
	await _tap(JOY_BUTTON_START)
	check(game.screen == "mutation" and game.menus.focused_power_id() == branch_id, "Resume restores branches and chosen focus")
	_button(JOY_BUTTON_A, true)
	await _settle()
	check(game.screen == "acquisition" and game.run_context.power_mutations.get(power_id) == branch_id, "Confirm commits the selected mutually exclusive branch")
	check(int(game.battle.player_entity().power_ranks.get(power_id, 0)) == 3 and game.battle.player_entity().power_mutations.get(power_id) == branch_id, "Mutation is installed immediately in the same combatant")
	check(game.battle.powers == runtime and _body_state() == body, "Transformation retains runtime, positions, spin and timers")
	_check_layout()
	await _capture("acquired-" + branch_id)
	_button(JOY_BUTTON_A, false)
	await _settle()
	game._action("choose_mutation", {"encounter_id":draft_id,"branch_id":branches[1] if branch_id == branches[0] else branches[0],"run_seed":game.run_context.run_seed})
	check(game.run_context.power_mutations.get(power_id) == branch_id, "Stale opposing branch cannot acquire a duplicate mutation")
	game._process(1.1)
	check(game.screen == "battle" and not game.battle.paused and _body_state() == body, "Acquisition returns to the exact same live encounter")
	game.battle.set_physics_process(false)
	game.battle.test_step(1.0/60.0)
	check(game.battle.elapsed > float(body.elapsed), "Combat continues with chosen mutation after resume")

func _run() -> void:
	root.size = Vector2i(640,360)
	root.content_scale_size = Vector2i(640,360)
	Input.use_accumulated_input = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): captures = argument.trim_prefix("--capture-dir=")
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	game = QuietMain.new()
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	await _settle()
	for power_id: String in Powers.VERTICAL_IDS:
		for branch_id: String in Powers.mutation_choices(power_id):
			await _test_branch(power_id, branch_id)
		game.menus.show_acquisition(power_id, "RETURN TO COMBAT", 2)
		await _settle()
		_check_layout()
		await _capture("tuned-" + power_id)
	game.menus.show_reward(Powers.VERTICAL_IDS, Powers.ACTIVE_IDS, 1, "visual/ranks", 421, "", {"power_ranks":{"redline":1,"dead_centre":2,"afterimage":0},"resume_label":"RETURN TO COMBAT"})
	await _settle()
	_check_layout()
	await _capture("mixed-investment-draft")
	game.menus.show_hud({"is_run":true,"owned_power_ids":Powers.ACTIVE_IDS,"power_ranks":{"redline":3,"dead_centre":3,"afterimage":3},"power_mutations":{"redline":"runaway","dead_centre":"bulwark","afterimage":"ghost_circuit"},"level":13,"progression_max":true})
	await _settle()
	for index: int in range(7): check(game.menus._hud["power_%d" % index].visible, "Seven-power build keeps HUD slot %d visible" % index)
	check(game.menus._hud.has("power_7"), "An eighth future power has a HUD slot")
	_check_layout()
	await _capture("seven-power-hud")
	for branch_id: String in ["runaway","breakneck","bulwark","counterweight","ghost_circuit","slipstream","hybrid"]:
		game._start_build_practice(branch_id)
		game.battle.set_physics_process(false)
		check(game.run_context.status == "empty" and game.mode == "duel", "Practice does not create earned progression")
		check(game.battle.player_entity().powers.size() == 7, "Practice equips a full seven-power comparison machine")
		if branch_id != "hybrid":
			var power_id: String = Powers.get_mutation(branch_id).power_id
			check(game.battle.player_entity().power_mutations.get(power_id) == branch_id, "Practice installs requested mutation " + branch_id)
		else:
			check(game.battle.player_entity().power_mutations.size() == 3, "Hybrid practice combines three defining branches")
		game._pause()
		game._action("rematch")
		game.battle.set_physics_process(false)
		check(game._practice_branch == branch_id and game.screen == "battle", "Practice Restart repeats the same comparison build")
	await _test_hidden_hud_transitions()
	print("ESCALATION_INTEGRATION_%s checks=%d failures=%d synthetic_gamepad=3 physical_hardware=NOT_TESTED" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	game.free()
	quit(1 if failures else 0)
