extends SceneTree
# Presentation-class UI regression tests use real keyboard input and shaped Label
# measurements. Pixel-level visual review remains part of the separate smoke test.

const Menus = preload("res://scripts/menus.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Parts = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")
const Presentation = preload("res://scripts/frontend_layout.gd")
const PRODUCT_RECT: Rect2 = Rect2(0, 0, 800, 480)
const MENU_RECT: Rect2 = Rect2(80, 60, 640, 360)

var checks: int = 0
var failures: int = 0
var actions: Array[Dictionary] = []
var menus: Control
var capture_dir: String = ""

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	root.size = Vector2i(800, 480)
	root.content_scale_size = Vector2i(800, 480)
	menus = Menus.new()
	root.add_child(menus)
	menus.action.connect(func(name: String, value: Variant) -> void:
		actions.append({"name":name, "value":value.duplicate(true) if value is Dictionary else value}))
	await process_frame
	check(root.get_visible_rect().size == PRODUCT_RECT.size, "UI tests run in the native 800x480 product viewport")
	await _test_reward_cards()
	await _test_starters()
	await _test_small_offers_and_acquisition()
	await _test_hud_cleanup()
	await _test_garage_assemblies()
	print("MENU_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	menus.queue_free()
	quit(1 if failures else 0)

func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	check(screenshot != null and not screenshot.is_empty(), "UI screenshot renders: "+name)
	if screenshot != null and not screenshot.is_empty():
		check(screenshot.save_png(capture_dir.path_join(name + ".png")) == OK, "UI screenshot saved: "+name)

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
	var screen_rect: Rect2 = PRODUCT_RECT if menus.screen == "hud" else menus._content.get_global_rect()
	var full_client: bool = menus.presentation_mode in ["frontend", "combat"] or (not menus.mobile_hud and Presentation.uses_run_overlay(menus.screen))
	check(menus._content.position == (Vector2.ZERO if full_client else MENU_RECT.position), "HUD/full-client pages and centered modals use their actual presentation origins")
	var parent: Node = label.get_parent()
	var clipped_strip: bool = false
	while parent != null:
		if parent is ScrollContainer:
			clipped_strip = true
			check(screen_rect.encloses(parent.get_global_rect()), "Catalogue scroll viewport stays inside the actual presentation root")
			break
		parent = parent.get_parent()
	if not clipped_strip: check(screen_rect.encloses(rect), "Label stays inside its actual presentation root or product HUD: %s %s" % [label.text, rect])
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
			check(_find_label(card, str(power.name).to_upper()) != null, "Card shows full power name: "+str(power.name))
			var expected_copy: String = str(Menus.AbilityInspection.describe(str(power.id), 0).get("what", power.get("card_copy", power.description)))
			check(_find_label(card, expected_copy) != null, "Card shows the concise mechanism description: "+str(power.name))
			check(menus.presentation_snapshot().safe_rect.encloses(card.get_global_rect()), "Reward card remains inside the actual full-client safe overlay")
			if index > 0:
				check(not card.get_global_rect().intersects(cards[index - 1].get_global_rect()), "Reward cards never overlap")
			var focus: StyleBoxTexture = card.get_theme_stylebox("focus") as StyleBoxTexture
			check(focus != null and focus.texture != null and focus.modulate_color.a > 0 and not focus.texture.get_image().is_invisible(), "Card has a visible authored focus frame")
		check(_find_label(menus, "FAMILIES %d/%d" % [owned.size(), Powers.FAMILY_CAP]) != null, "Draft retains the current family capacity beside the fixed inspection")
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

func _test_small_offers_and_acquisition() -> void:
	for count: int in [1, 2, 3]:
		var offer: Array = Powers.ACTIVE_IDS.slice(0, count)
		menus.show_reward(offer, [], 6, "run_slot_06", 123)
		await process_frame
		var cards: Array[Button] = _buttons(menus)
		check(cards.size() == count and root.gui_get_focus_owner() == cards[0], "Shrinking active pool has exactly its available cards and visible initial focus")
		for label: Label in _labels(menus): _check_label_fits(label)
		await _key(KEY_LEFT)
		check(root.gui_get_focus_owner() == cards.back(), "One/two/three-card draft focus wraps without a trap")
		var focus_id: String = menus.focused_power_id()
		menus.show_pause(true)
		menus.show_reward(offer, [], 6, "run_slot_06", 123, focus_id)
		await process_frame
		check(menus.focused_power_id() == focus_id, "Restored draft preserves the previously focused power")
		await _capture("draft-%d-cards" % count)
	for power_id: String in Powers.ACTIVE_IDS:
		menus.show_acquisition(power_id)
		await process_frame
		check(_find_label(menus, str(Powers.get_power(power_id).name).to_upper() + " ACQUIRED") != null, "Acquisition identifies the committed power")
		check(_buttons(menus).is_empty() and root.gui_get_focus_owner() == null, "Acquisition beat never introduces a confirmation trap")
		check(menus._acquisition_icon.texture != null, "Acquisition displays the power's authored icon")
		for label: Label in _labels(menus): _check_label_fits(label)
		await _capture("acquired-" + power_id)

func _test_hud_cleanup() -> void:
	var owned: Array = Powers.ACTIVE_IDS.duplicate()
	menus.show_hud({"is_run":true, "run_label":"THREAT 8", "owned_power_ids":owned, "status":"battle", "starter_id":"breaker", "level":4, "xp":44, "xp_threshold":50})
	await process_frame
	check(_find_label(menus, "THREAT 8") != null, "Run HUD shows current encounter progress")
	check(_find_label(menus, "BREAKER") != null, "Combat identifies the selected starter")
	check(menus._hud.xp_panel.visible and menus._hud.xp_bar.visible and menus._hud.xp_label.text == "LV 4  /  NEXT INVESTMENT", "Run level remains separate from RPM")
	check(menus._xp_near and menus._hud.xp_detail.text == "ALMOST THERE", "Near level state creates visible anticipation")
	menus._process(0.1)
	check(menus._hud.xp_bar.value > 0.0 and menus._hud.xp_bar.value < 0.88, "XP fill eases meaningful increments instead of jumping")
	for index: int in range(owned.size()):
		var icon: TextureRect = menus._hud["power_%d" % index]
		check(icon.visible and icon.get_meta("power_id") == owned[index] and icon.texture != null, "Run HUD displays authored owned-power icon")
		check(icon.size == Vector2(16, 16) and PRODUCT_RECT.encloses(icon.get_global_rect()), "HUD power stays native, compact, and on screen")
	menus.show_hud({"is_run":true, "is_swarm":true, "run_label":"THREAT 3", "owned_power_ids":owned, "swarm_wave":2, "swarm_total_waves":3, "swarm_active":11, "swarm_remaining":18, "starter_id":"breaker", "level":4, "xp":44, "xp_threshold":50})
	await process_frame
	check(not menus._hud.enemy_bar.visible and menus._hud.swarm_objective.visible, "Swarm replaces rival RPM bar with objective")
	check(_find_label(menus, "AMMUNITION WAVES  2 / 3") != null and _find_label(menus, "11 ACTIVE") != null and _find_label(menus, "18 LEFT IN SCHEDULE") != null, "Swarm HUD shows wave, active count, and remaining schedule")
	for label: Label in _labels(menus): _check_label_fits(label)
	await _capture("swarm-hud-six-powers")
	menus.show_hud({"is_run":true,"continuous_run":true,"elapsed":185.9,"status":"battle","starter_id":"bastion","run_state":{"threat_number":9,"threats_cleared":8,"phase":"breathing","next_at":187.0}})
	await process_frame
	check(menus._hud.time.text == "03:05" and menus._hud.round.text == "THREAT 9  /  8 CLEARED", "Continuous HUD shows elapsed survival with no finite denominator")
	check(menus._hud.enemy_name.text == "THREAT CLEARED" and not menus._hud.enemy_bar.visible, "Breathing acknowledgement keeps the arena and HUD visible")
	await _capture("continuous-breathing")
	menus.show_result({"continuous_run":true,"is_run":true,"reason":"spin_out","starter_id":"bastion","survival_time":475.0,"threats_cleared":13,"rivals_defeated":10,"small_enemies_defeated":44,"level":13,"owned_power_ids":owned,"power_ranks":{"redline":3,"dead_centre":3,"afterimage":3},"power_mutations":{"redline":"runaway","dead_centre":"counterweight","afterimage":"ghost_circuit"}})
	await process_frame
	check(_find_label(menus,"RUN ENDED") != null and _find_label(menus,"SURVIVED  07:55") != null, "Run loss has a survival result rather than a duel victory")
	for label: Label in _labels(menus): _check_label_fits(label)
	var routes: Array[String] = []
	for button: Button in _buttons(menus):
		if button.has_meta("intent"): routes.append(str(button.get_meta("intent")))
	check(routes == ["restart_run", "open_shop", "customize", "main_menu"] and root.gui_get_focus_owner().text == "RUN AGAIN", "Run loss focuses Run Again with Shop, Workshop and Workbench routes")
	await _capture("continuous-run-result")
	menus.show_hud({"is_run":true,"run_label":"THREAT 8","owned_power_ids":owned,"status":"battle"})
	var before: Node = menus._content
	menus.show_hud({"is_run":false, "run_label":"DUEL", "owned_power_ids":[], "status":"battle"})
	await process_frame
	check(menus._content == before, "HUD cleanup is tested on reused controls")
	check(_find_label(menus, "DUEL") != null and _find_label(menus, "THREAT 8") == null, "Quick Duel replaces Run progress label")
	for index: int in range(owned.size()):
		check(not menus._hud["power_%d" % index].visible, "Quick Duel clears stale power icons")
	check(menus._hud.enemy_bar.visible and not menus._hud.swarm_objective.visible, "Quick Duel restores rival information")
	check(_find_label(menus, "RUN POWERS") == null, "Quick Duel clears Run power notice")
	check(not menus._hud.xp_panel.visible and not menus._hud.xp_bar.visible, "Quick Duel clears Run progression")
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

func _test_starters() -> void:
	menus.show_starters()
	await process_frame
	var cards: Array[Button] = []
	for button: Button in _buttons(menus):
		if button.has_meta("starter_id"): cards.append(button)
	check(cards.size() == 3 and menus.focused_starter_id() == "breaker", "Three authored starters open with Breaker in focus")
	for index: int in range(cards.size()):
		var data: Dictionary = Starters.get_starter(Starters.IDS[index])
		check(_find_label(cards[index], data.name) != null and _find_label(cards[index], data.tagline) != null, "Starter identity and tagline are readable")
		var previews: Array[Node] = []
		for child: Node in cards[index].get_children():
			if child is Menus.Preview: previews.append(child)
		check(previews.size() == 1 and previews[0].build == data.assembly and previews[0].animated, "Starter preview uses its real authored assembly")
	for label: Label in _labels(menus): _check_label_fits(label)
	await _capture("three-starters")
	await _key(KEY_LEFT)
	check(menus.focused_starter_id() == "vane", "Starter focus wraps left to Vane")
	await _key(KEY_RIGHT)
	check(menus.focused_starter_id() == "breaker", "Starter focus wraps right to Breaker")
	for id: String in Starters.IDS:
		var before: int = actions.size()
		await _key(KEY_ENTER)
		check(actions.size() == before + 1 and actions.back() == {"name":"choose_starter", "value":id}, "Starter Confirm emits a stable ID exactly once")
		await _key(KEY_RIGHT)
	var last: String = menus.focused_starter_id()
	root.gui_get_focus_owner().release_focus()
	menus._process(0.01)
	check(menus.focused_starter_id() == last, "Lost menu focus restores the last focused starter")
	await _analogue(JOY_AXIS_LEFT_X, 0.9)
	var after: String = menus.focused_starter_id()
	for value: float in [0.89, 0.95, 0.7, -0.85]: await _analogue(JOY_AXIS_LEFT_X, value)
	check(menus.focused_starter_id() == after, "Held analogue excursion and direction jitter navigate only once")
	await _analogue(JOY_AXIS_LEFT_X, 0.0)
	await _analogue(JOY_AXIS_LEFT_X, 0.9)
	check(menus.focused_starter_id() != after, "Centred stick rearms a new deliberate navigation")
	await _analogue(JOY_AXIS_LEFT_X, 0.0)
	menus.show_reward(Powers.ACTIVE_IDS.slice(0, 3), [], 1, "start_draft", 42, "", {"title":"CHOOSE YOUR FIRST POWER", "subtitle":"Enter the arena already dangerous.", "resume_label":"LAUNCH"})
	await process_frame
	check(_find_label(menus, "CHOOSE YOUR FIRST POWER") != null, "Starting draft uses contextual copy")
	for label: Label in _labels(menus): _check_label_fits(label)
	await _capture("starting-power-draft")
	menus.show_level_up(2)
	await process_frame
	check(_find_label(menus, "LEVEL UP") != null and _buttons(menus).is_empty(), "Level completion hit has no extra confirmation")
	for label: Label in _labels(menus): _check_label_fits(label)
	await _capture("level-up-hit")

func _analogue(axis: JoyAxis, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await process_frame

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
	check(assemblies == Parts.BLADE_IDS.size() * Parts.RATCHET_IDS.size() * Parts.BIT_IDS.size(), "Every physical catalogue assembly remains selectable in the garage")

func _select_part(category: String, part_id: String) -> void:
	var button: Button = menus._part_buttons[category][part_id]
	menus.focus_collection_part(category, part_id)
	await process_frame
	var action_count: int = actions.size()
	await _key(KEY_ENTER)
	check(actions.size() == action_count + 1 and actions.back().name == "build_changed" and actions.back().value[category] == part_id, "Part button keyboard activation emits the selected part")
