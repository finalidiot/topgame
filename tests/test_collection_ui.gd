extends SceneTree
## Native 640x360 first-save UI, exercised through actual GUI input dispatch.
## Device 3 is synthetic controller coverage, not a physical-hardware claim.

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void:
		pass

const Starters = preload("res://scripts/starters.gd")
const Parts = preload("res://scripts/parts.gd")
const Preview = preload("res://scripts/top_preview.gd")
const NATIVE_RECT: Rect2 = Rect2(0, 0, 640, 360)
const PAD: int = 3
const NAV: Array[JoyButton] = [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN]
var checks: int = 0
var failures: int = 0
var game: QuietMain
var capture_dir: String = ""
var test_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _descendants(parent: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in parent.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found

func _button(intent: String, payload: String = "") -> Button:
	for node: Node in _descendants(game.menus):
		if not node is Button: continue
		var button: Button = node
		if button.has_meta("intent") and str(button.get_meta("intent")) == intent:
			if payload.is_empty() or str(button.get_meta("payload", "")) == payload: return button
		# Production controls also expose starter IDs; intent metadata is optional.
		if intent == "select_first_starter" and button.has_meta("starter_id") and str(button.get_meta("starter_id")) == payload: return button
	return null

func _button_text(text: String) -> Button:
	for node: Node in _descendants(game.menus):
		if node is Button and node.text == text: return node
	return null

func _labels() -> Array[Label]:
	var found: Array[Label] = []
	for node: Node in _descendants(game.menus):
		if node is Label: found.append(node)
	return found

func _check_layout(context: String) -> void:
	var native_rect: Rect2 = Rect2(game.menus._content.global_position, Vector2(640, 360))
	for node: Node in _descendants(game.menus):
		if node is Button and _scroll_ancestor(node) == null:
			check(native_rect.encloses(node.get_global_rect()), context+" button remains on the native screen: "+node.text)
	for label: Label in _labels():
		if not label.is_visible_in_tree(): continue
		if _scroll_ancestor(label) == null:
			check(native_rect.encloses(label.get_global_rect()), context+" label remains on screen: "+label.text)
		if label.text.is_empty(): continue
		var font: Font = label.get_theme_font("font")
		var size: int = label.get_theme_font_size("font_size")
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var width: float = 0.0
			for line: String in label.text.split("\n"): width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
			check(width <= label.size.x+0.1, context+" text fits its width: "+label.text)
		var height: float = 0.0
		for line: int in range(label.get_line_count()): height += label.get_line_height(line)
		height += maxi(0, label.get_line_count()-1)*label.get_theme_constant("line_spacing")
		check(height <= label.size.y+0.1, context+" shaped text fits its height: "+label.text)
		check(label.get_visible_line_count() == label.get_line_count(), context+" text is not clipped: "+label.text)
		if label.get_parent() is Button:
			check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Card text permits pointer activation")
			check(label.get_parent().get_global_rect().encloses(label.get_global_rect()), "Starter card text remains inside its focus target")

func _scroll_ancestor(node: Node) -> ScrollContainer:
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is ScrollContainer: return parent
		parent = parent.get_parent()
	return null

func _focus(context: String) -> void:
	var focused: Control = root.gui_get_focus_owner()
	check(focused != null and focused.is_visible_in_tree() and focused.focus_mode != Control.FOCUS_NONE, context+" has an obvious navigable focus target")
	if focused != null: check(Rect2(game.menus._content.global_position, Vector2(640, 360)).encloses(focused.get_global_rect()), context+" focus stays on screen")

func _joy(button: JoyButton, pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = PAD
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)

func _axis(axis: JoyAxis, amount: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = PAD
	event.axis = axis
	event.axis_value = amount
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

func _tap(button: JoyButton) -> void:
	_joy(button, true)
	await _settle()
	_joy(button, false)
	await _settle()

func _key_tap(code: Key) -> void:
	_key(code, true)
	await _settle()
	_key(code, false)
	await _settle()

func _stick(axis: JoyAxis, amount: float) -> void:
	_axis(axis, amount)
	await _settle()
	_axis(axis, 0.0)
	await _settle()

func _click(button: Button) -> void:
	check(button != null, "Requested pointer target exists")
	if button == null: return
	var scroll: ScrollContainer = _scroll_ancestor(button)
	if scroll != null:
		scroll.ensure_control_visible(button)
		await _settle()
	var center: Vector2 = button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	Input.parse_input_event(motion)
	await _settle()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = center
		event.global_position = center
		event.pressed = pressed
		Input.parse_input_event(event)
		await _settle()

func _navigate(target: Control) -> bool:
	check(target != null, "Controller navigation target exists")
	if target == null: return false
	var first: Control = root.gui_get_focus_owner()
	if first == target: return true
	var paths: Dictionary = {first:[]}
	var queue: Array[Control] = [first]
	while not queue.is_empty():
		var current: Control = queue.pop_front()
		if current == null: continue
		for side: int in range(4):
			var path: NodePath = current.get_focus_neighbor(side)
			var candidate: Control = current.get_node_or_null(path) if not path.is_empty() else null
			if candidate == null or paths.has(candidate): continue
			var route: Array = paths[current].duplicate()
			route.append(side)
			paths[candidate] = route
			queue.append(candidate)
	check(paths.has(target), "Focus graph reaches every requested collection control")
	if not paths.has(target): return false
	for side: int in paths[target]: await _tap(NAV[side])
	check(root.gui_get_focus_owner() == target, "Actual gamepad D-pad reaches the intended collection control")
	return root.gui_get_focus_owner() == target

func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), "Rendered collection UI screenshot: "+name)
	if image != null and not image.is_empty(): check(image.save_png(capture_dir.path_join(name+".png")) == OK, "Saved collection UI screenshot: "+name)

func _fresh(label: String, corrupt_fixture: bool = false) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	var path: String = "user://task003a-tests/ui-%d-%d-%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	test_paths.append(path)
	if corrupt_fixture:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string('{"schema_version":')
		file.close()
	game = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = path
	root.add_child(game)
	game.set_process(false)
	await _settle()
	check(game.screen == "title" and not game.collection.is_initialized(), "Isolated UI test starts genuinely fresh: "+label)
	_check_layout("Fresh title")
	_focus("Fresh title")

func _check_ceremony() -> void:
	check(game.screen == "starter_ceremony", "First-save Begin opens starter ceremony")
	var cards: Array[Button] = []
	for node: Node in _descendants(game.menus):
		if node is Button and node.has_meta("starter_id"): cards.append(node)
	check(cards.size() == 3, "All three first machines have distinct focusable cards")
	for card: Button in cards:
		var id: String = str(card.get_meta("starter_id"))
		var previews: Array[Node] = []
		for child: Node in card.get_children():
			if child is Preview: previews.append(child)
		check(previews.size() == 1, "Starter card has a dominant animated machine preview: "+id)
		if previews.size() == 1:
			check(previews[0].identity == id and previews[0].build == Starters.build_for(id), "Preview uses the actual silhouette, parts and motion identity: "+id)
			check(previews[0].animated and previews[0].preview_scale >= 3.0 and previews[0].texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Starter preview remains large, animated and pixel sharp")
			check(previews[0].mouse_filter == Control.MOUSE_FILTER_IGNORE, "Animated machine permits card mouse activation")
	check(game.collection.owned_count() == 0 and game.run_context.status == "empty", "Inspecting cards grants no parts and starts no Run")
	_check_layout("Starter ceremony")
	_focus("Starter ceremony")

func _check_workshop(starter: String) -> void:
	check(game.screen == "garage" and game.menus.screen == "collection_workshop", "Confirmed owner arrives in the persistent Workshop")
	check(game.collection.owned_count() == 3 and game.build == Starters.build_for(starter), "Workshop shows precisely the owned first machine")
	var owned_count: int = 0
	var locked_count: int = 0
	for category: String in ["blade", "ratchet", "bit"]:
		for id: String in Parts.PARTS[category]:
			var button: Button = game.menus._part_buttons[category][id]
			check(button != null, "Every expanded catalogue card is retained: "+category+":"+id)
			check(button.is_visible_in_tree() == (category == game.menus._catalogue_category), "Only the selected category is visible: "+category+":"+id)
			check(button.focus_mode == (Control.FOCUS_ALL if category == game.menus._catalogue_category else Control.FOCUS_NONE), "Inactive category cards cannot enter the focus graph")
			if game.collection.owns_part(category+":"+id): owned_count += 1
			else:
				locked_count += 1
				check(button.text.contains("NOT OWNED") or button.tooltip_text.contains("NOT OWNED") or bool(button.get_meta("locked", false)), "Unowned state is explicit: "+category+":"+id)
	var catalogue_count: int = Parts.BLADE_IDS.size() + Parts.RATCHET_IDS.size() + Parts.BIT_IDS.size()
	check(owned_count == 3 and locked_count == catalogue_count - 3, "Workshop distinguishes exactly three owned parts from the expanded locked catalogue")
	_check_layout("Collection Workshop")
	_focus("Collection Workshop")

func _test_controller() -> void:
	await _fresh("controller-breaker")
	await _tap(JOY_BUTTON_A)
	_check_ceremony()
	check(game.menus.focused_starter_id() == "breaker", "Breaker begins in focus")
	await _tap(JOY_BUTTON_DPAD_LEFT)
	check(game.menus.focused_starter_id() == "vane", "D-pad wraps left to Vane")
	await _stick(JOY_AXIS_LEFT_X, 0.9)
	check(game.menus.focused_starter_id() == "breaker", "Analogue navigation wraps back to Breaker")
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	check(game.menus.focused_starter_id() == "bastion", "Controller reaches planted Bastion")
	await _tap(JOY_BUTTON_DPAD_LEFT)
	await _capture("01-three-starters")
	_joy(JOY_BUTTON_A, true)
	await _settle()
	check(game.screen == "starter_ceremony" and game.collection.owned_count() == 0, "Holding a face button alone cannot acquire a starter")
	# Godot's Button activates on release. A second mapped Confirm can activate
	# while the controller binding is still held, reproducing cross-screen input.
	_key(KEY_ENTER, true)
	await _settle()
	_key(KEY_ENTER, false)
	await _settle()
	check(game.screen == "starter_confirm" and game.collection.owned_count() == 0, "A first deliberate activation opens reversible confirmation")
	_check_layout("Starter confirmation")
	_key(KEY_ENTER, true, true)
	await _settle()
	check(game.screen == "starter_confirm" and not game.collection.is_initialized(), "Held/echo Confirm cannot simultaneously make permanent ownership")
	_key(KEY_ENTER, false)
	_joy(JOY_BUTTON_A, false)
	await _settle()
	await _tap(JOY_BUTTON_B)
	check(game.screen == "starter_ceremony" and game.menus.focused_starter_id() == "breaker", "Controller Back preserves the unconfirmed inspection focus")
	await _tap(JOY_BUTTON_A)
	await _capture("02-confirmation")
	_joy(JOY_BUTTON_A, true)
	await _settle()
	_key(KEY_ENTER, true)
	await _settle()
	_key(KEY_ENTER, false)
	await _settle()
	check(game.screen == "starter_owned" and game.collection.starter_id == "breaker", "A separate deliberate Confirm owns the first machine")
	var owned: Dictionary = game.collection.snapshot().duplicate(true)
	_check_layout("Ownership moment")
	await _capture("03-first-ownership")
	_key(KEY_ENTER, true, true)
	await _settle()
	check(game.screen == "starter_owned" and game.collection.snapshot() == owned, "Held ownership Confirm cannot skip the acquisition beat or grant twice")
	_key(KEY_ENTER, false)
	_joy(JOY_BUTTON_A, false)
	await _settle()
	game._process(1.5)
	await _settle()
	_check_workshop("breaker")
	await _capture("04-owned-workshop")
	var locked: Button = game.menus._part_buttons.blade.guard
	if await _navigate(locked): await _tap(JOY_BUTTON_A)
	check(game.screen == "garage" and game.collection.snapshot() == owned and game.build.blade == "smash", "Locked controller inspection cannot equip or grant another blade")
	_check_layout("Locked part inspection")
	var owned_button: Button = game.menus._part_buttons.blade.smash
	if await _navigate(owned_button): await _tap(JOY_BUTTON_A)
	check(game.build == Starters.build_for("breaker"), "Owned part remains selectable")
	var run: Button = _button_text("LAUNCH OWNED TOP")
	if await _navigate(run): await _tap(JOY_BUTTON_A)
	check(game.screen == "reward" and game.run_context.selected_build == Starters.build_for("breaker"), "Controller launches owned machine directly into its temporary starting-power draft")
	check(game.run_context.owned_power_ids.is_empty(), "Launch confirmation cannot also choose a Run power")
	_focus("Owned Run starting draft")
	await _tap(JOY_BUTTON_A)
	game._process(1.2)
	await _settle()
	check(game.screen == "battle" and game.battle.player_entity().build == Starters.build_for("breaker"), "Controller can immediately launch the first owned machine")
	check(root.gui_get_focus_owner() == null, "Combat receives no stale Workshop/ceremony Confirm target")
	await _tap(JOY_BUTTON_START)
	check(game.screen == "pause", "Owned Run retains controller pause")
	var end: Button = _button_text("END RUN")
	if await _navigate(end): await _tap(JOY_BUTTON_A)
	_check_workshop("breaker")

func _test_keyboard() -> void:
	await _fresh("keyboard-bastion")
	await _key_tap(KEY_ENTER)
	_check_ceremony()
	await _key_tap(KEY_RIGHT)
	check(game.menus.focused_starter_id() == "bastion", "Keyboard inspects Bastion")
	await _key_tap(KEY_ENTER)
	check(game.screen == "starter_confirm" and not game.collection.is_initialized(), "Keyboard selection remains reversible")
	await _key_tap(KEY_ESCAPE)
	check(game.screen == "starter_ceremony" and game.menus.focused_starter_id() == "bastion", "Keyboard Back restores the selected card")
	await _key_tap(KEY_ENTER)
	await _key_tap(KEY_ENTER)
	check(game.screen == "starter_owned" and game.collection.starter_id == "bastion", "Two deliberate keyboard confirms create only Bastion ownership")
	game._process(1.5)
	await _settle()
	_check_workshop("bastion")
	await _key_tap(KEY_ESCAPE)
	check(game.screen == "title", "Keyboard Back returns from Workshop to title")
	await _key_tap(KEY_ENTER)
	check(game.screen == "reward" and game.collection.owned_count() == 3 and game.run_context.selected_build == Starters.build_for("bastion"), "Initialized hub launches the owned machine directly and skips the first-choice ceremony")

func _test_mouse() -> void:
	await _fresh("mouse-vane")
	var begin: Button = _button_text("BEGIN")
	if begin == null: begin = _button_text("BEGIN / CHOOSE FIRST TOP")
	await _click(begin)
	_check_ceremony()
	await _click(_button("select_first_starter", "vane"))
	check(game.screen == "starter_confirm" and game.collection.owned_count() == 0, "Mouse card selection does not irrevocably grant parts")
	var confirm: Button = _button_text("CHOOSE VANE")
	await _click(confirm)
	check(game.screen == "starter_owned" and game.collection.starter_id == "vane", "Mouse confirms the real Vane save")
	game._process(1.5)
	await _settle()
	_check_workshop("vane")
	var before: Dictionary = game.collection.snapshot().duplicate(true)
	await _click(game.menus._catalogue_tabs.bit)
	await _click(game.menus._part_buttons.bit.flat)
	check(game.collection.snapshot() == before and game.build.bit == "rubber", "Mouse cannot equip a visible unowned part")
	_check_layout("Mouse locked inspection")
	await _capture("05-vane-owned-workshop")

func _test_blocked_save_ui() -> void:
	await _fresh("blocked-save", true)
	check(game.collection.read_only and game.collection.owned_count() == 0, "Corrupt save UI preserves conservative empty read-only state")
	await _key_tap(KEY_ENTER)
	check(game.screen == "collection_error" and game.menus.screen == "collection_error", "Normal Begin explains a blocked save safely")
	_check_layout("Blocked collection message")
	_focus("Blocked collection message")
	await _capture("06-blocked-save-message")
	await _key_tap(KEY_ENTER)
	check(game.screen == "title" and game.collection.read_only, "Blocked-save Back returns to title without granting or overwriting parts")
	check(FileAccess.get_file_as_string(game.collection_path) == '{"schema_version":', "UI error handling preserves the damaged source file for recovery")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	root.size = Vector2i(800, 480)
	root.content_scale_size = Vector2i(800, 480)
	Input.use_accumulated_input = false
	await _test_controller()
	await _test_keyboard()
	await _test_mouse()
	await _test_blocked_save_ui()
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	for path: String in test_paths:
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("COLLECTION_UI_TEST_%s checks=%d failures=%d synthetic_device=%d all_starters=3" % ["PASS" if failures == 0 else "FAIL", checks, failures, PAD])
	quit(1 if failures else 0)
