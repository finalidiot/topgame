extends SceneTree
# Native-resolution UI regression tests use real keyboard input and shaped Label
# measurements. Pixel-level visual review remains part of the separate smoke test.

const Menus = preload("res://scripts/menus.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Parts = preload("res://scripts/parts.gd")
const NATIVE_RECT: Rect2 = Rect2(0, 0, 640, 360)

var checks: int = 0
var failures: int = 0
var actions: Array[Dictionary] = []
var menus: Control

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
	menus = Menus.new()
	root.add_child(menus)
	menus.action.connect(func(name: String, value: Variant) -> void:
		actions.append({"name":name, "value":value.duplicate(true) if value is Dictionary else value}))
	await process_frame
	check(root.get_visible_rect().size == Vector2(640, 360), "UI tests run in the native 640x360 viewport")
	await _test_reward_cards()
	await _test_hud_cleanup()
	await _test_garage_assemblies()
	print("MENU_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	menus.queue_free()
	quit(1 if failures else 0)

func _descendants(parent: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in parent.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found

func _labels(parent: Node) -> Array[Label]:
	var result: Array[Label] = []
	for node: Node in _descendants(parent):
		if node is Label: result.append(node)
	return result

func _buttons(parent: Node) -> Array[Button]:
	var result: Array[Button] = []
	for node: Node in _descendants(parent):
		if node is Button: result.append(node)
	return result

func _find_label(parent: Node, text: String) -> Label:
	for label: Label in _labels(parent):
		if label.text == text: return label
	return null

func _check_label_fits(label: Label) -> void:
	var rect: Rect2 = label.get_global_rect()
	check(NATIVE_RECT.encloses(rect), "Label stays inside native screen: %s %s" % [label.text, rect])
	if label.text.is_empty(): return
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		var widest_line: float = 0.0
		for line: String in label.text.split("\n"):
			widest_line = maxf(widest_line, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		check(widest_line <= label.size.x + 0.1, "Text width fits label: %s (%.1f <= %.1f)" % [label.text, widest_line, label.size.x])
	var line_height: float = 0.0
	for index: int in range(label.get_line_count()): line_height += label.get_line_height(index)
	line_height += maxi(0, label.get_line_count() - 1) * label.get_theme_constant("line_spacing")
	check(line_height <= label.size.y + 0.1, "All shaped lines fit label height: %s (%.1f <= %.1f)" % [label.text, line_height, label.size.y])
	check(label.get_visible_line_count() == label.get_line_count(), "No rendered line is clipped: "+label.text)
	if label.get_parent() is Button:
		check((label.get_parent() as Button).get_global_rect().encloses(rect), "Card text stays inside its card: "+label.text)
		check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Card label permits pointer activation of its button")

func _key(code: Key) -> void:
	var press: InputEventKey = InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release: InputEventKey = InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func _test_reward_cards() -> void:
	var seen: Dictionary = {}
	for group: int in range(4):
		var offer: Array = Powers.IDS.slice(group * 3, group * 3 + 3)
		var owned: Array[String] = []
		for offset: int in range(3, 9):
			owned.append(Powers.IDS[(group * 3 + offset) % Powers.IDS.size()])
		menus.show_reward(offer, owned, 7, "run_slot_07", 86420)
		await process_frame
		var cards: Array[Button] = _buttons(menus)
		check(cards.size() == 3, "Reward exposes exactly three selectable cards")
		check(root.gui_get_focus_owner() == cards[0], "First reward card receives keyboard focus")
		check(_find_label(menus, "Before the final") != null, "Last draft identifies the upcoming final encounter")
		for label: Label in _labels(menus): _check_label_fits(label)
		for index: int in range(cards.size()):
			var card: Button = cards[index]
			var power: Dictionary = Powers.get_power(str(offer[index]))
			seen[power.id] = true
			check(_find_label(card, str(power.name)) != null, "Card shows full power name: "+str(power.name))
			check(_find_label(card, str(power.description)) != null, "Card shows full description: "+str(power.name))
			check(NATIVE_RECT.encloses(card.get_global_rect()), "Reward card remains inside native viewport")
			if index > 0:
				check(not card.get_global_rect().intersects(cards[index - 1].get_global_rect()), "Reward cards never overlap")
			var focus: StyleBoxFlat = card.get_theme_stylebox("focus") as StyleBoxFlat
			var normal: StyleBoxFlat = card.get_theme_stylebox("normal") as StyleBoxFlat
			check(focus != null and focus.border_color.a > 0 and focus.border_color != normal.border_color and focus.get_border_width(SIDE_LEFT) >= 1, "Card has a visible distinct focus border")
		for power_id: String in owned:
			var label: Label = _find_label(menus, str(Powers.get_power(power_id).name))
			check(label != null and label.get_global_rect().position.y >= 300, "Collected power has a compact visible label: "+power_id)
		await _key(KEY_LEFT)
		check(root.gui_get_focus_owner() == cards[2], "Left key wraps first card to third")
		await _key(KEY_RIGHT)
		check(root.gui_get_focus_owner() == cards[0], "Right key wraps third card to first")
		for index: int in range(cards.size()):
			check(root.gui_get_focus_owner() == cards[index] and cards[index].has_focus(), "Keyboard focus reaches card %d" % index)
			var before: int = actions.size()
			await _key(KEY_ENTER)
			check(actions.size() == before + 1, "Enter emits exactly one reward action")
			if actions.size() == before + 1:
				check(actions.back() == {"name":"choose_power", "value":{"encounter_id":"run_slot_07", "power_id":offer[index], "run_seed":86420}}, "Activated card emits its bound encounter, seed, and power")
			await _key(KEY_RIGHT)
		check(root.gui_get_focus_owner() == cards[0], "Three right presses complete a focus cycle")
	check(seen.size() == 12, "Every power title and description has been measured")

func _test_hud_cleanup() -> void:
	var owned: Array = ["impact_wake", "second_wind", "chain_impact", "flywheel_cache", "dead_centre", "afterimage"]
	menus.show_hud({"is_run":true, "run_label":"RUN 8 / 8", "owned_power_ids":owned, "status":"battle"})
	await process_frame
	check(_find_label(menus, "RUN 8 / 8") != null, "Run HUD shows current encounter progress")
	for power_id: String in owned:
		var label: Label = _find_label(menus, str(Powers.get_power(power_id).name))
		check(label != null, "Run HUD displays owned power: "+power_id)
		if label != null: _check_label_fits(label)
	var before: Node = menus._content
	menus.show_hud({"is_run":false, "run_label":"DUEL", "owned_power_ids":[], "status":"battle"})
	await process_frame
	check(menus._content == before, "HUD cleanup is tested on reused controls")
	check(_find_label(menus, "DUEL") != null and _find_label(menus, "RUN 8 / 8") == null, "Quick Duel replaces Run progress label")
	for power_id: String in owned:
		check(_find_label(menus, str(Powers.get_power(power_id).name)) == null, "Quick Duel clears stale power label: "+power_id)
	check(_find_label(menus, "POWERS COLLECTED  /  EFFECTS INACTIVE") == null, "Quick Duel clears Run collection notice")
	var pause: Button = _buttons(menus)[0]
	check(pause.focus_mode == Control.FOCUS_NONE, "Gameplay HUD cannot capture steering/Confirm focus")
	var action_count: int = actions.size()
	await _key(KEY_RIGHT)
	await _key(KEY_SPACE)
	check(root.gui_get_focus_owner() == null and actions.size() == action_count, "Steering and Burst keys never activate the HUD pause button")
	var point: Vector2 = pause.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
		await process_frame
	check(actions.size() == action_count + 1 and actions.back().name == "pause", "Mouse still activates the HUD pause button")

func _test_garage_assemblies() -> void:
	menus.show_garage({"blade":"balance", "ratchet":"mid", "bit":"ball"})
	await process_frame
	var assemblies: int = 0
	for blade: String in Parts.BLADE_IDS:
		await _select_part("blade", blade)
		for ratchet: String in Parts.RATCHET_IDS:
			await _select_part("ratchet", ratchet)
			for bit: String in Parts.BIT_IDS:
				await _select_part("bit", bit)
				var build: Dictionary = {"blade":blade, "ratchet":ratchet, "bit":bit}
				assemblies += 1
				check(menus._preview.build == build and menus._assembly_name.text == Parts.title(build), "Garage preview/name follow keyboard assembly selection")
				var expected: Dictionary = Parts.derive(build)
				var stats_match: bool = true
				for stat: String in ["power", "stamina", "grip", "speed", "stability", "mass"]:
					stats_match = stats_match and menus._stat_numbers[stat].text == "%.1f" % float(expected[stat])
					stats_match = stats_match and absf(menus._stat_bars[stat].value - clampf(float(expected[stat]) / 10.0, 0.0, 1.0)) <= 0.001
				check(stats_match, "Garage refreshes all six visible stats for "+Parts.title(build))
	check(assemblies == 48, "All 48 physical assemblies remain selectable in the garage")

func _select_part(category: String, part_id: String) -> void:
	var button: Button = menus._part_buttons[category][part_id]
	button.grab_focus()
	var action_count: int = actions.size()
	await _key(KEY_ENTER)
	check(actions.size() == action_count + 1 and actions.back().name == "build_changed" and actions.back().value[category] == part_id, "Part button keyboard activation emits the selected part")
