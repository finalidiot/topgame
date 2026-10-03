extends Control
## Native 640 x 360 menu and HUD layer. Only emits intent; the game owns state.

signal action(name: String, value: Variant)
signal focus_sound(kind: String)

const Preview = preload("res://scripts/top_preview.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Starters = preload("res://scripts/starters.gd")
const INK: Color = Color("0b141e")
const PANEL: Color = Color("172737")
const BORDER: Color = Color("30495d")
const TEXT: Color = Color("e2eaf0")
const MUTED: Color = Color("95aabc")
const BLUE: Color = Color("67c9e7")
const ORANGE: Color = Color("f0a15c")
# Shared action language keeps HUD/menu prompts independent of controller glyphs.
# Platform glyph presentation can replace these hints without changing screens.
const INPUT_HINTS: Dictionary = {
	"steer": "LEFT STICK / WASD / ARROWS",
	"burst": "BOTTOM FACE / SPACE",
	"brake": "SHOULDER / TRIGGER / SHIFT",
	"pause": "MENU / ESC",
	"confirm": "BOTTOM FACE / ENTER",
	"back": "EAST FACE / ESC",
}

var screen: String = ""
var _content: Control
var _build: Dictionary = {"blade": "balance", "ratchet": "mid", "bit": "ball"}
var _settings: Dictionary = {}
var _preview: Preview
var _part_buttons: Dictionary = {}
var _part_descriptions: Dictionary = {}
var _stat_bars: Dictionary = {}
var _stat_numbers: Dictionary = {}
var _assembly_name: Label
var _hud: Dictionary = {}
var _run_active: bool = false
var _default_focus: Control
var _accept_needs_release: bool = false
var _acquisition_elapsed: float = 0.0
var _acquisition_icon: TextureRect
var _acquisition_flash: ColorRect
var _card_animations: Array[Dictionary] = []
var _art_animations: Array[Dictionary] = []
var _menu_clock: float = 0.0
var _axis_latches: Dictionary = {}
var _xp_target: float = 0.0
var _xp_display: float = 0.0
var _xp_last_level: int = 1
var _xp_near: bool = false
var _xp_flash: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	theme = _make_theme()

func _process(_delta: float) -> void:
	_menu_clock += _delta
	_animate_cards()
	_animate_power_art(_delta)
	if screen == "acquisition" and is_instance_valid(_acquisition_icon):
		_acquisition_elapsed += _delta
		_acquisition_icon.modulate.a = minf(1.0, 0.6 + _acquisition_elapsed * 5.0)
		_acquisition_icon.position.y = 83.0 - roundf(minf(2.0, _acquisition_elapsed * 15.0))
		if is_instance_valid(_acquisition_flash): _acquisition_flash.color.a = maxf(0.0, 0.18 - _acquisition_elapsed * 1.1)
	if screen == "hud" and _run_active:
		_xp_display = move_toward(_xp_display, _xp_target, _delta * 1.6)
		# Quantise the fill to native pixels, while easing meaningful XP increments.
		_hud.xp_bar.value = roundf(_xp_display * 354.0) / 354.0
		_xp_flash = maxf(0.0, _xp_flash - _delta * 2.5)
		_hud.xp_bar.modulate = Color(1.0, 1.0, 1.0, 1.0 if not _xp_near else (1.0 if int(_menu_clock * 7.0) % 2 == 0 else 0.65))
		_hud.xp_hit.color.a = _xp_flash * 0.32
	if _accept_needs_release and not Input.is_action_pressed("ui_accept"):
		_accept_needs_release = false
	if screen == "hud" or not is_instance_valid(_default_focus): return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or not _content.is_ancestor_of(focused):
		_default_focus.grab_focus()

func _input(event: InputEvent) -> void:
	# A result/draft may open while Burst/Confirm is held. Require its release
	# before any new screen can accept it, including keyboard echo events.
	if screen != "hud" and _accept_needs_release and event.is_action("ui_accept"):
		if event.is_action_released("ui_accept"):
			_accept_needs_release = Input.is_action_pressed("ui_accept")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		# Navigate exactly once per excursion. Jitter and a held stick cannot race
		# across cards, or advance focus when a draft replaces combat under it.
		var key: String = "%d:%d" % [event.device, event.axis]
		var value: float = event.axis_value
		if absf(value) < 0.28:
			_axis_latches.erase(key)
		elif absf(value) >= 0.55 and not _axis_latches.has(key):
			_axis_latches[key] = true
			if screen != "hud":
				var direction: String = ("left" if value < 0 else "right") if event.axis == JOY_AXIS_LEFT_X else ("top" if value < 0 else "bottom")
				_move_analogue_focus(direction)
		if screen != "hud": get_viewport().set_input_as_handled()

func _move_analogue_focus(direction: String) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null: return
	if focused is HSlider and direction in ["left", "right"]:
		focused.value += focused.step * (-1.0 if direction == "left" else 1.0)
		return
	var path: NodePath = focused.get("focus_neighbor_" + direction)
	var target: Control = focused.get_node_or_null(path) as Control
	if target != null: target.grab_focus()

func _make_theme() -> Theme:
	var value: Theme = Theme.new()
	value.default_font_size = 12
	value.set_color("font_color", "Label", TEXT)
	value.set_color("font_color", "Button", TEXT)
	value.set_color("font_hover_color", "Button", Color.WHITE)
	value.set_color("font_pressed_color", "Button", INK)
	value.set_color("font_focus_color", "Button", Color.WHITE)
	value.set_stylebox("normal", "Button", _box(Color("203548"), BORDER, 1))
	value.set_stylebox("hover", "Button", _box(Color("2e4b62"), BLUE, 1))
	value.set_stylebox("pressed", "Button", _box(BLUE, BLUE, 1))
	value.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ORANGE, 2))
	value.set_stylebox("disabled", "Button", _box(Color("152331"), BORDER, 1))
	value.set_stylebox("background", "ProgressBar", _box(Color("0e1924"), Color("23394c"), 1))
	value.set_stylebox("fill", "ProgressBar", _box(BLUE, BLUE, 0))
	value.set_stylebox("slider", "HSlider", _box(Color("30495d"), Color("30495d"), 0))
	value.set_stylebox("grabber_area", "HSlider", _box(BLUE, BLUE, 0))
	value.set_stylebox("focus", "HSlider", _box(Color(0, 0, 0, 0), ORANGE, 2))
	return value

func _box(fill: Color, outline: Color, border_width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(border_width)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style

func _clear(next_screen: String, dim: bool = true) -> void:
	screen = next_screen
	_default_focus = null
	_accept_needs_release = next_screen != "hud" and Input.is_action_pressed("ui_accept")
	_card_animations.clear()
	_art_animations.clear()
	for device: int in Input.get_connected_joypads():
		for axis: int in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			if absf(Input.get_joy_axis(device, axis)) >= 0.55: _axis_latches["%d:%d" % [device, axis]] = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_hud.clear()
	_part_buttons.clear()
	_part_descriptions.clear()
	_stat_bars.clear()
	_stat_numbers.clear()
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)
	if dim:
		_rect(_content, Rect2(0, 0, 640, 360), Color(INK.r, INK.g, INK.b, 0.97))
		_rect(_content, Rect2(0, 0, 640, 3), ORANGE)
		_rect(_content, Rect2(0, 357, 640, 3), Color("23394c"))

func _focus_rows(rows: Array, first: Control = null) -> void:
	# Explicit links make every control reachable even across the workshop's
	# unequal rows and the settings slider. Keep tab traversal equivalent.
	var controls: Array[Control] = []
	for row_index: int in range(rows.size()):
		var row: Array = rows[row_index]
		for column: int in range(row.size()):
			var control: Control = row[column]
			controls.append(control)
			control.focus_entered.connect(func() -> void: _default_focus = control)
			control.focus_entered.connect(func() -> void: focus_sound.emit("ui_focus"))
			control.focus_neighbor_left = control.get_path_to(row[(column + row.size() - 1) % row.size()])
			control.focus_neighbor_right = control.get_path_to(row[(column + 1) % row.size()])
			control.focus_neighbor_top = control.get_path_to(_nearest_control(control, rows[(row_index + rows.size() - 1) % rows.size()]))
			control.focus_neighbor_bottom = control.get_path_to(_nearest_control(control, rows[(row_index + 1) % rows.size()]))
	for index: int in range(controls.size()):
		controls[index].focus_next = controls[index].get_path_to(controls[(index + 1) % controls.size()])
		controls[index].focus_previous = controls[index].get_path_to(controls[(index + controls.size() - 1) % controls.size()])
	if controls.is_empty(): return
	_default_focus = first if first != null else controls[0]
	_default_focus.grab_focus()

func _nearest_control(origin: Control, candidates: Array) -> Control:
	var nearest: Control = candidates[0]
	var center_x: float = origin.position.x + origin.size.x * 0.5
	var distance: float = INF
	for candidate: Control in candidates:
		var candidate_distance: float = absf(candidate.position.x + candidate.size.x * 0.5 - center_x)
		if candidate_distance < distance:
			nearest = candidate
			distance = candidate_distance
	return nearest

func _rect(parent: Node, area: Rect2, color: Color) -> ColorRect:
	var node: ColorRect = ColorRect.new()
	node.position = area.position
	node.size = area.size
	node.color = color
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _panel(parent: Node, area: Rect2, fill: Color = PANEL, border: Color = BORDER) -> Panel:
	var node: Panel = Panel.new()
	node.position = area.position
	node.size = area.size
	node.add_theme_stylebox_override("panel", _box(fill, border, 1))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _label(parent: Node, value: String, area: Rect2, font_size: int = 12, color: Color = TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node: Label = Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.clip_text = true
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.position = area.position
	node.size = area.size
	return node

func _button(parent: Node, value: String, area: Rect2, intent: String = "", payload: Variant = null, primary: bool = false) -> Button:
	var node: Button = Button.new()
	node.text = value
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		node.add_theme_stylebox_override("normal", _box(Color("a85d35"), ORANGE, 1))
		node.add_theme_stylebox_override("hover", _box(Color("c77343"), Color("ffbd7e"), 1))
		node.add_theme_stylebox_override("pressed", _box(ORANGE, ORANGE, 1))
	if intent != "":
		node.pressed.connect(func() -> void: action.emit(intent, payload))
	parent.add_child(node)
	node.position = area.position
	node.size = area.size
	return node

func _bar(parent: Node, area: Rect2, color: Color = BLUE) -> ProgressBar:
	var node: ProgressBar = ProgressBar.new()
	node.max_value = 1.0
	node.step = 0.001
	node.show_percentage = false
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background: StyleBoxFlat = _box(Color("0e1924"), Color("23394c"), 1)
	var fill: StyleBoxFlat = _box(color, color, 0)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		background.set_content_margin(side, 0.0)
		fill.set_content_margin(side, 0.0)
	node.add_theme_stylebox_override("background", background)
	node.add_theme_stylebox_override("fill", fill)
	parent.add_child(node)
	node.position = area.position
	node.size = area.size
	return node

func _new_preview(area: Rect2, scale_factor: float = 3.0) -> Preview:
	var node: Preview = Preview.new()
	node.position = area.position
	node.size = area.size
	node.preview_scale = scale_factor
	_content.add_child(node)
	node.set_build(_build)
	return node

func _header(title: String, subtitle: String) -> void:
	_label(_content, title, Rect2(22, 12, 580, 26), 23)
	_label(_content, subtitle, Rect2(24, 38, 580, 16), 10, MUTED)

func show_title(build: Dictionary, settings: Dictionary) -> void:
	_build = build.duplicate()
	_settings = settings.duplicate()
	_clear("title")
	_label(_content, "SPINNING METAL", Rect2(28, 24, 565, 42), 32)
	_label(_content, "FOUNDRY EIGHT  /  PLAYABLE PROTOTYPE", Rect2(30, 65, 570, 16), 10, ORANGE)
	var first: Button = _button(_content, "QUICK DUEL", Rect2(30, 104, 268, 31), "quick_duel", null, true)
	var run_button: Button = _button(_content, "EIGHT-ENCOUNTER RUN", Rect2(30, 143, 268, 31), "start_run")
	var garage_button: Button = _button(_content, "CUSTOMIZE TOP", Rect2(30, 182, 268, 31), "customize")
	var help_button: Button = _button(_content, "HOW TO PLAY", Rect2(30, 221, 128, 31), "help")
	var settings_button: Button = _button(_content, "SETTINGS", Rect2(168, 221, 130, 31), "settings")
	var quit_button: Button = _button(_content, "QUIT", Rect2(30, 260, 268, 28), "quit")
	_panel(_content, Rect2(324, 104, 286, 211))
	_label(_content, "YOUR LOADOUT", Rect2(339, 114, 255, 16), 10, BLUE)
	_new_preview(Rect2(358, 127, 218, 148), 3.0)
	_label(_content, PartCatalog.title(_build), Rect2(334, 264, 266, 23), 12, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "11 PARTS  /  48 ASSEMBLIES", Rect2(334, 287, 266, 15), 9, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "Steer. Time your burst. Stay in the dish.", Rect2(30, 303, 285, 28), 11, MUTED)
	_label(_content, "KEYBOARD + GAMEPAD    /    STEER   BURST   BRAKE   PAUSE    /    CONTROLS IN HOW TO PLAY", Rect2(30, 333, 582, 16), 9, MUTED)
	_focus_rows([[first], [run_button], [garage_button], [help_button, settings_button], [quit_button]])

func show_garage(build: Dictionary) -> void:
	_build = build.duplicate()
	_clear("garage")
	_header("TOP WORKSHOP", "Choose a Blade, Ratchet and Bit. Every part changes how your top battles.")
	_panel(_content, Rect2(22, 62, 207, 244))
	_label(_content, "LIVE ASSEMBLY", Rect2(35, 72, 180, 16), 10, BLUE)
	_preview = _new_preview(Rect2(35, 86, 181, 126), 3.0)
	_assembly_name = _label(_content, "", Rect2(30, 207, 190, 18), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var stat_ids: Array[String] = ["power", "stamina", "grip", "speed", "stability", "mass"]
	var stat_names: Array[String] = ["IMPACT", "STAMINA", "GRIP", "SPEED", "STABILITY", "MASS"]
	for index in range(6):
		var column: int = index % 2
		var row: int = index / 2
		var x: float = 35.0 + column * 96.0
		var y: float = 231.0 + row * 23.0
		_label(_content, stat_names[index], Rect2(x, y, 65, 11), 8, MUTED)
		_stat_numbers[stat_ids[index]] = _label(_content, "", Rect2(x + 64, y, 17, 11), 8, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		_stat_bars[stat_ids[index]] = _bar(_content, Rect2(x, y + 13, 81, 4), ORANGE if index == 0 else BLUE)
	_panel(_content, Rect2(244, 62, 374, 244))
	_part_row("blade", "01   BLADE", PartCatalog.BLADE_IDS, 73)
	_part_row("ratchet", "02   RATCHET", PartCatalog.RATCHET_IDS, 147)
	_part_row("bit", "03   BIT", PartCatalog.BIT_IDS, 221)
	var back_button: Button = _button(_content, "BACK", Rect2(22, 319, 98, 27), "main_menu")
	var duel_button: Button = _button(_content, "QUICK DUEL", Rect2(131, 319, 200, 27), "start_battle", "duel", true)
	var run_button: Button = _button(_content, "EIGHT-ENCOUNTER RUN", Rect2(342, 319, 276, 27), "start_run")
	_refresh_garage()
	_focus_rows([_part_buttons["blade"].values(), _part_buttons["ratchet"].values(), _part_buttons["bit"].values(), [back_button, duel_button, run_button]], _part_buttons["blade"][_build.get("blade", "balance")])

func show_starters(focus_id: String = "breaker") -> void:
	_clear("starters")
	_header("CHOOSE YOUR STARTER", "Pick a fighting style. Choose a power. Make this run yours.")
	var cards: Array[Button] = []
	var selected: Control
	for index: int in range(Starters.IDS.size()):
		var id: String = Starters.IDS[index]
		var data: Dictionary = Starters.get_starter(id)
		var color: Color = data.accent
		var card: Button = _button(_content, "", Rect2(22 + index * 202, 70, 192, 236), "choose_starter", id)
		card.set_meta("starter_id", id)
		card.tooltip_text = data.name + " / " + PartCatalog.title(data.assembly)
		_style_card(card, color)
		_rect(card, Rect2(11, 11, 3, 18), color)
		_label(card, str(data.name), Rect2(21, 7, 159, 25), 21, color)
		var preview: Preview = Preview.new()
		preview.position = Vector2(15, 35)
		preview.size = Vector2(162, 111)
		preview.preview_scale = 3.0
		preview.set_build(data.assembly)
		preview.set_identity(id, color)
		card.add_child(preview)
		var tagline: Label = _label(card, str(data.tagline), Rect2(12, 142, 168, 29), 9, TEXT)
		tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tagline.add_theme_constant_override("line_spacing", -1)
		_label(card, str(data.strengths), Rect2(12, 178, 168, 16), 9, color)
		_label(card, str(data.weakness), Rect2(12, 195, 168, 15), 9, MUTED)
		_label(card, "CONFIRM  /  MAKE IT YOURS", Rect2(12, 216, 168, 14), 9, TEXT)
		cards.append(card)
		if id == focus_id: selected = card
	_label(_content, "LEFT / RIGHT  CHOOSE      CONFIRM  LOCK IN", Rect2(22, 323, 384, 18), 9, MUTED)
	var custom: Button = _button(_content, "CUSTOM ASSEMBLY RUN", Rect2(426, 321, 192, 25), "custom_run")
	custom.add_theme_font_size_override("font_size", 9)
	_focus_rows([cards, [custom]], selected)

func focused_starter_id() -> String:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return str(focused.get_meta("starter_id", "")) if focused != null else ""

func _style_card(card: Button, accent: Color) -> void:
	card.add_theme_stylebox_override("normal", _box(Color("172737"), Color("385266"), 1))
	card.add_theme_stylebox_override("hover", _box(Color("22364a"), accent, 1))
	card.add_theme_stylebox_override("pressed", _box(Color("294459"), accent, 2))
	card.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), accent, 2))
	_card_animations.append({"card":card, "position":card.position, "accent":accent, "focused":null})

func _animate_cards() -> void:
	for entry: Dictionary in _card_animations:
		var card: Button = entry.card
		if not is_instance_valid(card): continue
		var focused: bool = card.has_focus()
		if entry.focused == focused: continue
		entry.focused = focused
		card.position = entry.position + Vector2(0, -2 if focused else 0)
		card.add_theme_stylebox_override("normal", _box(Color("243b4d") if focused else Color("172737"), entry.accent if focused else Color("385266"), 1))

func _part_row(category: String, title: String, ids: Array, y: float) -> void:
	_label(_content, title, Rect2(256, y, 345, 15), 10, ORANGE)
	_part_buttons[category] = {}
	var width: float = (348.0 - 6.0 * (ids.size() - 1)) / ids.size()
	for index in range(ids.size()):
		var id: String = str(ids[index])
		var data: Dictionary = PartCatalog.PARTS[category][id]
		var button: Button = _button(_content, str(data.get("name", id.capitalize())), Rect2(256 + index * (width + 6), y + 19, width, 27))
		button.add_theme_font_size_override("font_size", 11)
		button.tooltip_text = str(data.get("description", ""))
		button.pressed.connect(func() -> void: _choose_part(category, id))
		_part_buttons[category][id] = button
	var description: Label = _label(_content, "", Rect2(256, y + 48, 348, 25), 9, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_constant_override("line_spacing", -1)
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	description.clip_text = true
	_part_descriptions[category] = description

func _choose_part(category: String, id: String) -> void:
	_build[category] = id
	_refresh_garage()
	action.emit("build_changed", _build.duplicate())

func _refresh_garage() -> void:
	_preview.set_build(_build)
	_assembly_name.text = PartCatalog.title(_build)
	for category in _part_buttons:
		for id in _part_buttons[category]:
			var button: Button = _part_buttons[category][id]
			var selected: bool = str(_build.get(category, "")) == str(id)
			button.add_theme_stylebox_override("normal", _box(Color("9b5a37") if selected else Color("203548"), ORANGE if selected else BORDER, 1))
			button.add_theme_color_override("font_color", Color.WHITE if selected else TEXT)
		_part_descriptions[category].text = str(PartCatalog.PARTS[category][_build[category]].get("description", ""))
	var stats: Dictionary = PartCatalog.derive(_build)
	for stat in _stat_bars:
		var amount: float = float(stats.get(stat, 5.0))
		_stat_bars[stat].value = clampf(amount / 10.0, 0.0, 1.0)
		_stat_numbers[stat].text = "%.1f" % amount

func show_help() -> void:
	_clear("help")
	_header("HOW TO PLAY", "A spinning-top duel in a fixed isometric arena.")
	_panel(_content, Rect2(22, 65, 279, 238))
	_panel(_content, Rect2(313, 65, 305, 238))
	_label(_content, "CONTROL YOUR TOP", Rect2(37, 78, 242, 18), 12, BLUE)
	_label(_content, "STEER", Rect2(37, 104, 246, 17), 11, TEXT)
	_label(_content, INPUT_HINTS.steer, Rect2(37, 122, 246, 16), 9, BLUE)
	_label(_content, "Movement follows the screen directions.", Rect2(37, 139, 246, 16), 9, MUTED)
	_label(_content, "BURST   /   Dash toward your steering", Rect2(37, 164, 246, 17), 10, TEXT)
	_label(_content, INPUT_HINTS.burst, Rect2(37, 181, 246, 16), 9, BLUE)
	_label(_content, "BRAKE   /   Line up a hit or avoid a gate", Rect2(37, 204, 246, 17), 10, TEXT)
	_label(_content, INPUT_HINTS.brake, Rect2(37, 221, 246, 16), 9, BLUE)
	_label(_content, "PAUSE   " + INPUT_HINTS.pause, Rect2(37, 247, 246, 14), 9, MUTED)
	_label(_content, "CONFIRM   " + INPUT_HINTS.confirm, Rect2(37, 263, 246, 14), 9, MUTED)
	_label(_content, "BACK   " + INPUT_HINTS.back, Rect2(37, 279, 246, 14), 9, MUTED)
	_label(_content, "WIN THE EXCHANGE", Rect2(329, 78, 272, 18), 12, ORANGE)
	_label(_content, "RING OUT", Rect2(329, 110, 268, 20), 12, TEXT)
	_label(_content, "Knock your rival through either orange side gate.\nThe remaining rim keeps tops inside.", Rect2(329, 133, 269, 39), 11, MUTED)
	_label(_content, "SPIN OUT", Rect2(329, 184, 268, 20), 12, TEXT)
	_label(_content, "Drain your rival's spin through collisions.\nSteering and bursts also spend your own spin.", Rect2(329, 207, 269, 39), 11, MUTED)
	_label(_content, "BUILD FOR YOUR STYLE", Rect2(329, 258, 268, 18), 10, BLUE)
	_label(_content, "Speed for pursuit. Grip for control. Mass for recoil.", Rect2(329, 278, 269, 17), 9, MUTED)
	var back_button: Button = _button(_content, "BACK TO MENU", Rect2(22, 318, 184, 28), "main_menu")
	var garage_button: Button = _button(_content, "CUSTOMIZE TOP", Rect2(218, 318, 184, 28), "customize")
	var duel_button: Button = _button(_content, "QUICK DUEL", Rect2(414, 318, 204, 28), "quick_duel", null, true)
	_focus_rows([[back_button, garage_button, duel_button]])

func show_settings(settings: Dictionary) -> void:
	_settings = settings.duplicate()
	_clear("settings")
	_header("SETTINGS", "Your top and preferences are saved automatically.")
	_panel(_content, Rect2(90, 71, 460, 229))
	_label(_content, "MASTER VOLUME", Rect2(111, 90, 230, 20), 12)
	var volume_label: Label = _label(_content, "%d%%" % roundi(float(_settings.get("volume", 0.75)) * 100.0), Rect2(453, 90, 72, 20), 12, BLUE, HORIZONTAL_ALIGNMENT_RIGHT)
	var slider: HSlider = HSlider.new()
	slider.position = Vector2(111, 122)
	slider.size = Vector2(413, 20)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.focus_mode = Control.FOCUS_ALL
	slider.value = float(_settings.get("volume", 0.75))
	slider.value_changed.connect(func(value: float) -> void:
		_settings["volume"] = value
		volume_label.text = "%d%%" % roundi(value * 100.0)
		action.emit("settings_changed", _settings.duplicate()))
	_content.add_child(slider)
	# HSlider does not draw the Button-style focus box itself. Draw a separate
	# outline so controller focus remains visible even without a mouse hover.
	var focus_outline: Panel = _panel(slider, Rect2(Vector2(-4, -4), slider.size + Vector2(8, 8)), Color(0, 0, 0, 0), ORANGE)
	focus_outline.name = "FocusOutline"
	focus_outline.add_theme_stylebox_override("panel", slider.get_theme_stylebox("focus"))
	focus_outline.visible = false
	slider.focus_entered.connect(focus_outline.show)
	slider.focus_exited.connect(focus_outline.hide)
	var mute_button: Button = _toggle_setting("muted", "MUTE AUDIO", 163, false)
	var shake_button: Button = _toggle_setting("screen_shake", "SCREEN SHAKE", 201, true)
	var fullscreen_button: Button = _toggle_setting("fullscreen", "FULL SCREEN", 239, false)
	_label(_content, "Pixel art uses nearest-neighbor scaling. 1280 × 720 recommended.", Rect2(90, 302, 460, 16), 9, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var back_button: Button = _button(_content, "BACK TO MENU", Rect2(226, 325, 188, 26), "main_menu")
	_focus_rows([[slider], [mute_button], [shake_button], [fullscreen_button], [back_button]])

func _toggle_setting(key: String, title: String, y: float, fallback: bool) -> Button:
	_label(_content, title, Rect2(111, y, 300, 24), 12)
	var button: Button = _button(_content, "ON" if bool(_settings.get(key, fallback)) else "OFF", Rect2(444, y, 81, 25))
	button.pressed.connect(func() -> void:
		_settings[key] = not bool(_settings.get(key, fallback))
		button.text = "ON" if _settings[key] else "OFF"
		action.emit("settings_changed", _settings.duplicate()))
	return button

func show_pause(is_run: bool = false) -> void:
	_clear("pause", false)
	_rect(_content, Rect2(0, 0, 640, 360), Color(0.02, 0.04, 0.065, 0.8))
	_panel(_content, Rect2(186, 48, 268, 268))
	_label(_content, "RUN PAUSED" if is_run else "DUEL PAUSED", Rect2(202, 66, 236, 31), 23, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "Take a breath. Your spin can wait.", Rect2(202, 101, 236, 17), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var resume_button: Button = _button(_content, "RESUME", Rect2(207, 135, 226, 31), "resume", null, true)
	var restart_button: Button = _button(_content, "RESTART RUN" if is_run else "RESTART DUEL", Rect2(207, 176, 226, 31), "restart_run" if is_run else "rematch")
	var focus_rows: Array = [[resume_button], [restart_button]]
	if is_run:
		focus_rows.append([_button(_content, "END RUN", Rect2(207, 217, 226, 31), "end_run")])
		_label(_content, "Assembly locked for this run", Rect2(202, 258, 236, 22), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		focus_rows.append([_button(_content, "CUSTOMIZE TOP", Rect2(207, 217, 226, 31), "customize")])
		focus_rows.append([_button(_content, "MAIN MENU", Rect2(207, 258, 226, 31), "main_menu")])
	_focus_rows(focus_rows)

func show_reward(offer: Array, owned: Array, slot: int, encounter_id: String, run_seed: int, focus_id: String = "", context: Dictionary = {}) -> void:
	_clear("reward")
	_header(str(context.get("title", "VICTORY  /  PICK A POWER")), str(context.get("subtitle", "Before the final" if slot == 7 else "Encounter %d cleared. Choose one to carry into the next battle." % slot)))
	_label(_content, "MAKE THE NEXT HIT COUNT  /  " + ("FINAL POWER IN THIS POOL" if offer.size() == 1 else "CHOOSE ONE. KEEP IT FOR THE RUN."), Rect2(24, 60, 592, 18), 10, ORANGE)
	var cards: Array[Button] = []
	var selected: Control
	var start_x: float = (640.0 - offer.size() * 192.0 - (offer.size() - 1) * 10.0) * 0.5
	for index: int in range(offer.size()):
		var id: String = str(offer[index])
		var power: Dictionary = Powers.get_power(id)
		var card: Button = _button(_content, "", Rect2(start_x + index * 202, 92, 192, 185), "choose_power", {"encounter_id":encounter_id, "power_id":id, "run_seed":run_seed})
		card.set_meta("power_id", id)
		card.tooltip_text = str(power.name) + ": " + str(power.description)
		var color: Color = _power_accent(id)
		_style_card(card, color)
		_label(card, str(power.get("category", "RUN POWER")), Rect2(12, 5, 168, 13), 9, color)
		_power_art(card, id, Rect2(64, 19, 64, 64), card)
		_label(card, str(power.name), Rect2(12, 87, 168, 25), 16, TEXT)
		var description: Label = _label(card, str(power.get("card_copy", power.description)), Rect2(12, 112, 168, 48), 11, TEXT)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		description.add_theme_constant_override("line_spacing", -1)
		_label(card, "CONFIRM  /  " + str(context.get("resume_label", "COLLECT")), Rect2(12, 166, 168, 16), 9, color)
		cards.append(card)
		if id == focus_id: selected = card
	_label(_content, "COLLECTED POWERS", Rect2(24, 281, 592, 15), 9, MUTED)
	_power_labels(owned, 302)
	_label(_content, "D-PAD / STICK / ARROWS  CHOOSE     CONFIRM  COLLECT     BACK / PAUSE  RUN MENU", Rect2(24, 334, 592, 16), 9, MUTED)
	if not cards.is_empty(): _focus_rows([cards], selected)

func _power_accent(power_id: String) -> Color:
	return {"impact_wake":Color("f0a15c"), "second_wind":Color("83d89a"), "redline":Color("ef735d"), "iron_comet":Color("f2cc72"), "afterimage":Color("67c9e7"), "chain_impact":Color("ce95ee")}.get(power_id, BLUE)

func focused_power_id() -> String:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return str(focused.get_meta("power_id", "")) if focused != null else ""

func _power_texture(power_id: String) -> Texture2D:
	var power: Dictionary = Powers.get_power(power_id)
	if not bool(power.get("active", false)) or not ResourceLoader.exists(Powers.ICON_SHEET): return null
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = load(Powers.ICON_SHEET)
	atlas.region = Rect2(int(power.icon_frame) * 16, 0, 16, 16)
	return atlas

func _power_icon(parent: Node, power_id: String, area: Rect2) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = _power_texture(power_id)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	icon.position = area.position
	icon.size = area.size
	return icon

func _power_art(parent: Node, power_id: String, area: Rect2, focused_card: Button = null) -> TextureRect:
	var power: Dictionary = Powers.get_power(power_id)
	var icon: TextureRect = _power_icon(parent, power_id, area)
	var path: String = str(power.get("card_texture", ""))
	if path.is_empty() or not ResourceLoader.exists(path): return icon
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = load(path)
	atlas.region = Rect2(0, int(power.get("card_row", 0)) * 64, 64, 64)
	icon.texture = atlas
	_art_animations.append({"icon":icon, "atlas":atlas, "power":power, "elapsed":0.0, "frame":0, "card":focused_card, "active":false})
	return icon

func _animate_power_art(delta: float) -> void:
	for entry: Dictionary in _art_animations:
		var icon: TextureRect = entry.icon
		if not is_instance_valid(icon): continue
		var card: Button = entry.card
		var active: bool = card == null or card.has_focus()
		if not active:
			entry.elapsed = 0.0
			entry.frame = int(entry.power.get("card_static_frame", 0))
		elif not entry.active:
			entry.elapsed = 0.0
			entry.frame = 0
		else:
			entry.elapsed += delta * 1000.0
			var durations: Array = entry.power.get("card_durations_ms", [120, 90, 70, 70, 100, 180])
			while entry.elapsed >= float(durations[int(entry.frame) % durations.size()]):
				entry.elapsed -= float(durations[int(entry.frame) % durations.size()])
				entry.frame = (int(entry.frame) + 1) % int(entry.power.get("card_frames", 6))
		entry.active = active
		(entry.atlas as AtlasTexture).region = Rect2(int(entry.frame) * 64, int(entry.power.get("card_row", 0)) * 64, 64, 64)

func show_level_up(level: int) -> void:
	_clear("level_up", false)
	_rect(_content, Rect2(0, 0, 640, 360), Color(INK.r, INK.g, INK.b, 0.28))
	_rect(_content, Rect2(0, 124, 640, 108), Color(INK.r, INK.g, INK.b, 0.9))
	_rect(_content, Rect2(0, 123, 640, 2), ORANGE)
	_rect(_content, Rect2(0, 231, 640, 2), ORANGE)
	_label(_content, "LEVEL UP", Rect2(110, 137, 420, 46), 37, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "LV %d  /  MORE POWER" % level, Rect2(110, 187, 420, 24), 15, ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()

func show_acquisition(power_id: String, resume_label: String = "RETURN TO COMBAT") -> void:
	_clear("acquisition", false)
	_rect(_content, Rect2(0, 0, 640, 360), Color(INK.r, INK.g, INK.b, 0.82))
	_panel(_content, Rect2(104, 67, 432, 226), PANEL, _power_accent(power_id))
	_rect(_content, Rect2(106, 69, 428, 2), _power_accent(power_id))
	var power: Dictionary = Powers.get_power(power_id)
	_acquisition_elapsed = 0.0
	_acquisition_icon = _power_art(_content, power_id, Rect2(256, 83, 128, 128))
	_label(_content, str(power.name).to_upper() + " ACQUIRED", Rect2(114, 222, 412, 32), 21, _power_accent(power_id), HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "LOCKED IN  /  " + resume_label, Rect2(114, 263, 412, 18), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_acquisition_flash = _rect(_content, Rect2(105, 68, 430, 224), Color(_power_accent(power_id), 0.18))
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()

func _power_labels(ids: Array, y: float) -> void:
	for index: int in range(ids.size()):
		var power: Dictionary = Powers.get_power(str(ids[index]))
		var area: Rect2 = Rect2(22 + index * 101, y, 96, 20)
		_panel(_content, area, PANEL, BORDER)
		_label(_content, str(power.name), area, 9, BLUE, HORIZONTAL_ALIGNMENT_CENTER)

func show_result(result: Dictionary) -> void:
	_clear("result", false)
	_rect(_content, Rect2(0, 0, 640, 360), Color(0.025, 0.045, 0.07, 0.87))
	_panel(_content, Rect2(121, 35, 398, 290))
	var won: bool = bool(result.get("won", false))
	var highlight: Color = BLUE if won else ORANGE
	_rect(_content, Rect2(122, 36, 396, 3), highlight)
	_label(_content, str(result.get("title", "VICTORY" if won else "DEFEAT")), Rect2(139, 49, 362, 36), 29, highlight, HORIZONTAL_ALIGNMENT_CENTER)
	var reason: String = str(result.get("reason", "spin_out"))
	var reason_text: String = "RING OUT" if reason == "ring_out" else ("SPIN OUT" if reason == "spin_out" else "TIME LIMIT")
	_label(_content, reason_text, Rect2(139, 86, 362, 22), 13, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var explanation: String = "Tune your build and try the exchange again."
	if won:
		explanation = "Your rival left the dish." if reason == "ring_out" else ("Your rival ran out of spin." if reason == "spin_out" else "You kept more spin when time ran out.")
	_label(_content, str(result.get("subtitle", explanation)), Rect2(139, 111, 362, 23), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_rect(_content, Rect2(149, 144, 342, 1), BORDER)
	_label(_content, "DUEL TIME", Rect2(149, 158, 102, 15), 9, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "HITS", Rect2(268, 158, 103, 15), 9, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "SPIN LEFT", Rect2(389, 158, 102, 15), 9, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "%.1f s" % float(result.get("duration", 0.0)), Rect2(149, 178, 102, 25), 18, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, str(result.get("hits", 0)), Rect2(268, 178, 103, 25), 18, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var remaining: float = float(result.get("player_remaining", 0.0))
	if remaining <= 1.0:
		remaining *= 100.0
	_label(_content, "%d%%" % roundi(remaining), Rect2(389, 178, 102, 25), 18, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var next_available: bool = bool(result.get("next_available", false))
	var is_run: bool = bool(result.get("is_run", false))
	var retry_text: String = "RESTART RUN" if is_run else "REMATCH"
	var primary: Button = _button(_content, "NEXT ENCOUNTER" if next_available else retry_text, Rect2(149, 222, 342, 31), "next_battle" if next_available else ("restart_run" if is_run else "rematch"), null, true)
	var focus_rows: Array = [[primary]]
	if is_run and next_available:
		focus_rows.append([_button(_content, "END RUN", Rect2(149, 268, 342, 28), "end_run")])
	else:
		var garage_button: Button = _button(_content, "GARAGE" if is_run else "CUSTOMIZE TOP", Rect2(149, 268, 166, 28), "customize")
		var menu_button: Button = _button(_content, "MAIN MENU", Rect2(325, 268, 166, 28), "main_menu")
		focus_rows.append([garage_button, menu_button])
	_focus_rows(focus_rows)

func show_hud(stats: Dictionary) -> void:
	if screen != "hud":
		_create_hud()
	var player_spin: float = float(stats.get("player_rpm", 1.0))
	var enemy_spin: float = float(stats.get("enemy_rpm", 1.0))
	_hud["player_bar"].value = player_spin
	_hud["enemy_bar"].value = enemy_spin
	_hud["player_name"].text = str(stats.get("player_name", "YOUR TOP"))
	_hud["enemy_name"].text = str(stats.get("enemy_name", "RIVAL"))
	_hud["player_rpm"].text = "%d RPM" % int(stats.get("player_rpm_value", player_spin * 7000.0))
	_hud["enemy_rpm"].text = "%d RPM" % int(stats.get("enemy_rpm_value", enemy_spin * 7000.0))
	var is_swarm: bool = bool(stats.get("is_swarm", false))
	_hud["enemy_bar"].visible = not is_swarm
	_hud["swarm_objective"].visible = is_swarm
	if is_swarm:
		_hud["enemy_name"].text = "AMMUNITION WAVES  %d / %d" % [int(stats.get("swarm_wave", 0)), int(stats.get("swarm_total_waves", 3))]
		_hud["swarm_objective"].text = "%d ACTIVE" % int(stats.get("swarm_active", 0))
		_hud["enemy_rpm"].text = "%d LEFT IN SCHEDULE" % int(stats.get("swarm_remaining", 24))
	var seconds: int = maxi(0, ceili(float(stats.get("time_left", 90.0))))
	_hud["time"].text = "%02d:%02d" % [seconds / 60, seconds % 60]
	var cooldown: float = float(stats.get("burst_cooldown", 0.0))
	var ready: bool = bool(stats.get("burst_ready", cooldown <= 0.0))
	var exhausted: bool = not ready and cooldown <= 0.0
	_hud["burst"].text = "BURST READY" if ready else ("LOW SPIN  /  BURST UNAVAILABLE" if exhausted else "BURST RECHARGING   %.1f s" % cooldown)
	_hud["burst"].add_theme_color_override("font_color", BLUE if ready else MUTED)
	_hud["burst_bar"].value = 1.0 if ready else (0.0 if exhausted else clampf(1.0 - cooldown / float(stats.get("burst_cooldown_max", 4.0)), 0.0, 1.0))
	var phase: String = str(stats.get("status", "battle"))
	var announcement: String = ""
	if phase == "countdown":
		announcement = str(stats.get("countdown", 3))
	elif phase == "launch":
		announcement = "LET IT RIP"
	_hud["announcement"].text = announcement
	_run_active = bool(stats.get("is_run", false))
	var starter_id: String = str(stats.get("starter_id", ""))
	if _run_active:
		_hud.player_name.text = Starters.display_name(starter_id)
		_hud.player_name.add_theme_color_override("font_color", Starters.get_starter(starter_id).get("accent", BLUE))
	else:
		_hud.player_name.add_theme_color_override("font_color", BLUE)
	_hud.xp_panel.visible = _run_active
	_hud.xp_bar.visible = _run_active
	_hud.xp_label.visible = _run_active
	_hud.xp_detail.visible = _run_active
	_hud.xp_hit.visible = _run_active
	_hud.controls.visible = not _run_active
	var level: int = int(stats.get("level", 1))
	var xp: float = float(stats.get("xp", 0))
	var threshold: float = maxf(1.0, float(stats.get("xp_threshold", 1)))
	var progression_max: bool = bool(stats.get("progression_max", false))
	_xp_target = 1.0 if progression_max else clampf(xp / threshold, 0.0, 1.0)
	if level != _xp_last_level:
		_xp_display = 0.0
		_xp_flash = 1.0
		_xp_last_level = level
	_xp_near = not progression_max and _xp_target >= 0.8
	_hud.xp_label.text = "LV %d  /  NEXT POWER" % level if not progression_max else "LV %d  /  FULL BUILD" % level
	_hud.xp_label.add_theme_color_override("font_color", ORANGE if _xp_near else BLUE)
	_hud.xp_detail.text = "MAX" if progression_max else ("ALMOST THERE" if _xp_near else "%d / %d XP" % [int(xp), int(threshold)])
	_hud["round"].text = str(stats.get("run_label", "FOUNDRY EIGHT  /  DUEL"))
	var ids: Array = stats.get("owned_power_ids", [])
	for index: int in range(6):
		var icon: TextureRect = _hud["power_%d" % index]
		var id: String = str(ids[index]) if index < ids.size() else ""
		icon.visible = not id.is_empty()
		_hud["power_panel_%d" % index].visible = not id.is_empty()
		if str(icon.get_meta("power_id", "")) != id:
			icon.set_meta("power_id", id)
			icon.texture = _power_texture(id) if not id.is_empty() else null
			icon.tooltip_text = str(Powers.get_power(id).get("name", ""))
	_hud["power_note"].text = "RUN POWERS" if not ids.is_empty() else ""
	_hud["wobble"].text = "LOW SPIN  /  KEEP CONTROL" if player_spin < 0.25 else ""

func _create_hud() -> void:
	_clear("hud", false)
	_xp_display = 0.0
	_panel(_content, Rect2(12, 8, 222, 55), Color(0.035, 0.065, 0.095, 0.94), Color("335a70"))
	_panel(_content, Rect2(406, 8, 222, 55), Color(0.035, 0.065, 0.095, 0.94), Color("73513b"))
	_hud["player_name"] = _label(_content, "YOUR TOP", Rect2(22, 13, 202, 17), 11, BLUE)
	_hud["enemy_name"] = _label(_content, "RIVAL", Rect2(416, 13, 202, 17), 11, ORANGE, HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["player_bar"] = _bar(_content, Rect2(22, 34, 202, 8), BLUE)
	_hud["enemy_bar"] = _bar(_content, Rect2(416, 34, 202, 8), ORANGE)
	_hud["player_rpm"] = _label(_content, "", Rect2(22, 45, 202, 12), 9, MUTED)
	_hud["enemy_rpm"] = _label(_content, "", Rect2(416, 45, 202, 12), 9, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["swarm_objective"] = _label(_content, "", Rect2(416, 30, 202, 14), 10, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_panel(_content, Rect2(268, 8, 104, 36), Color(0.035, 0.065, 0.095, 0.94))
	_hud["time"] = _label(_content, "01:30", Rect2(270, 11, 100, 28), 21, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var pause_button: Button = _button(_content, "PAUSE", Rect2(292, 49, 56, 21), "pause")
	pause_button.add_theme_font_size_override("font_size", 9)
	# Gameplay actions must never move HUD focus or make Confirm swallow Burst.
	# Gamepad/keyboard pause use the shared pause action; mouse keeps this button.
	pause_button.focus_mode = Control.FOCUS_NONE
	_hud["round"] = _label(_content, "", Rect2(175, 76, 290, 16), 9, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_hud["announcement"] = _label(_content, "", Rect2(145, 130, 350, 64), 35, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hud["wobble"] = _label(_content, "", Rect2(185, 273, 270, 19), 11, ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	_hud["power_note"] = _label(_content, "", Rect2(22, 291, 594, 12), 8, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	for index: int in range(6):
		_hud["power_panel_%d" % index] = _panel(_content, Rect2(238 + index * 28, 303, 24, 20))
		var icon: TextureRect = _power_icon(_content, "", Rect2(242 + index * 28, 305, 16, 16))
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		_hud["power_%d" % index] = icon
	_panel(_content, Rect2(12, 324, 224, 28), Color(0.035, 0.065, 0.095, 0.94))
	_hud["burst"] = _label(_content, "BURST READY", Rect2(23, 327, 203, 15), 10, BLUE)
	_hud["burst_bar"] = _bar(_content, Rect2(23, 345, 203, 3), BLUE)
	_hud["controls"] = _label(_content, "STEER    /    BURST    /    BRAKE    /    PAUSE", Rect2(276, 331, 340, 14), 9, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["xp_panel"] = _panel(_content, Rect2(252, 324, 376, 28), Color(0.035, 0.065, 0.095, 0.94), Color("477877"))
	_hud["xp_label"] = _label(_content, "LV 1  /  NEXT POWER", Rect2(261, 327, 232, 13), 9, BLUE)
	_hud["xp_detail"] = _label(_content, "0 / 1 XP", Rect2(496, 327, 122, 13), 9, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["xp_bar"] = _bar(_content, Rect2(261, 343, 354, 5), Color("83d89a"))
	_hud["xp_hit"] = _rect(_content, Rect2(252, 324, 376, 28), Color(1, 0.9, 0.6, 0))
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
