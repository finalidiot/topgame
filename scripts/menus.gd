extends Control
## Native 640 x 360 menu and HUD layer. Only emits intent; the game owns state.

signal action(name: String, value: Variant)
signal focus_sound(kind: String)

const Preview = preload("res://scripts/top_preview.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Starters = preload("res://scripts/starters.gd")
const BeastManifestations = preload("res://scripts/beast_manifestations.gd")
const INK: Color = FrontEnd.INK
const PANEL: Color = FrontEnd.PANEL
const BORDER: Color = FrontEnd.BORDER
const TEXT: Color = FrontEnd.TEXT
const MUTED: Color = FrontEnd.MUTED
const BLUE: Color = FrontEnd.BLUE
const ORANGE: Color = FrontEnd.ORANGE
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
var _part_scrolls: Dictionary = {}
var _catalogue_metadata: Label
var _catalogue_description: Label
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
var _collection_snapshot: Dictionary = {}
var _ownership_elapsed: float = 0.0
var _ownership_flash: ColorRect
var _ownership_note: Label
var _rpm_overdrive: bool = false
var _rpm_heat: float = 0.0
var _appearance_elapsed: float = 0.0
var _input_profile: String = "keyboard"
var _ui_owner_device: int = -1
var _prompt_labels: Dictionary = {}
var _prompt_glyphs: Dictionary = {}
var _catalogue_category: String = "blade"
var _catalogue_tabs: Dictionary = {}
var _catalogue_groups: Dictionary = {}
var _catalogue_footer: Array = []
var _catalogue_practice: bool = false
var _part_texture_cache: Dictionary = {}
var _equipped_slot_labels: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	theme = _make_theme()

func _process(_delta: float) -> void:
	if screen != "hud" and is_instance_valid(_content):
		_appearance_elapsed = minf(0.08, _appearance_elapsed + _delta)
		_content.modulate.a = 0.65 + _appearance_elapsed / 0.08 * 0.35
	_menu_clock += _delta
	_animate_cards()
	_animate_power_art(_delta)
	if screen == "hud": _animate_rpm_meter()
	if screen == "starter_owned":
		_ownership_elapsed += _delta
		if is_instance_valid(_ownership_flash): _ownership_flash.color.a = maxf(0.0, 0.14 - _ownership_elapsed * 0.3)
		if is_instance_valid(_ownership_note): _ownership_note.modulate.a = minf(1.0, _ownership_elapsed * 2.0)
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
	if screen != "hud":
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			if _ui_owner_device >= 0 and event.device != _ui_owner_device:
				get_viewport().set_input_as_handled()
				return
			if (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) >= 0.55):
				_note_input_profile(FrontEnd.controller_profile(event.device))
		elif (event is InputEventKey and event.pressed) or event is InputEventMouseButton:
			_note_input_profile("keyboard")
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
	return FrontEnd.make_theme()

func _box(fill: Color, outline: Color, border_width: int = 1) -> StyleBoxFlat:
	return FrontEnd.plate(fill, outline, border_width)

func _clear(next_screen: String, dim: bool = true) -> void:
	screen = next_screen
	_appearance_elapsed = 0.0
	_prompt_labels.clear()
	_prompt_glyphs.clear()
	_catalogue_tabs.clear()
	_catalogue_groups.clear()
	_catalogue_footer.clear()
	_equipped_slot_labels.clear()
	# F2 can hide combat HUD for the visual checkpoint. Required choices and
	# results must restore their own visibility when combat ends or pauses.
	if next_screen != "hud": visible = true
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
	_part_scrolls.clear()
	_catalogue_metadata = null
	_catalogue_description = null
	_stat_bars.clear()
	_stat_numbers.clear()
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)
	if dim:
		var backdrop: Control = FrontEnd.new()
		backdrop.screen_id = next_screen
		_content.add_child(backdrop)

func _focus_rows(rows: Array, first: Control = null) -> void:
	# Explicit links make every control reachable even across the workshop's
	# unequal rows and the settings slider. Keep tab traversal equivalent.
	var controls: Array[Control] = []
	for row_index: int in range(rows.size()):
		var row: Array = rows[row_index]
		for column: int in range(row.size()):
			var control: Control = row[column]
			controls.append(control)
			if not control.has_meta("frontend_focus_hooks"):
				control.set_meta("frontend_focus_hooks", true)
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
	var center_x: float = origin.get_global_rect().get_center().x
	var distance: float = INF
	for candidate: Control in candidates:
		var candidate_distance: float = absf(candidate.get_global_rect().get_center().x - center_x)
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
	var pixel_size: int = FrontEnd.font_size(font_size)
	var face: Font = get_theme_font("font")
	while pixel_size > 10:
		var maximum: float = 0
		for line: String in value.split("\n"): maximum = maxf(maximum, face.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, pixel_size).x)
		if maximum <= area.size.x and face.get_height(pixel_size) <= area.size.y: break
		pixel_size -= 10
	node.add_theme_font_size_override("font_size", pixel_size)
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
		node.set_meta("intent", intent)
		if payload != null: node.set_meta("payload", payload)
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

func set_ui_input_owner(device: int = -1) -> void:
	# Default remains shared single-player input. This seam scopes future menu
	# ownership without changing combat bindings or inventing a second player.
	_ui_owner_device = device

func input_profile() -> String:
	return _input_profile

func _note_input_profile(profile: String) -> void:
	if profile == _input_profile: return
	_input_profile = profile
	for purpose: String in _prompt_labels:
		var label: Label = _prompt_labels[purpose]
		if is_instance_valid(label): label.text = FrontEnd.prompt(profile, purpose) + (" CONFIRM" if purpose == "confirm" else (" BACK" if purpose == "back" else ""))
		var glyph: TextureRect = _prompt_glyphs.get(purpose)
		if is_instance_valid(glyph): glyph.texture = FrontEnd.glyph(profile, purpose)

func _input_footer(y: float = 333.0) -> void:
	for index: int in range(2):
		var purpose: String = "confirm" if index == 0 else "back"
		var x: float = 22.0 + index * 222.0
		var glyph: TextureRect = TextureRect.new()
		glyph.texture = FrontEnd.glyph(_input_profile, purpose)
		glyph.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.position = Vector2(x, y - 1)
		glyph.size = Vector2(16, 16)
		_content.add_child(glyph)
		_prompt_glyphs[purpose] = glyph
		_prompt_labels[purpose] = _label(_content, FrontEnd.prompt(_input_profile, purpose) + (" CONFIRM" if purpose == "confirm" else " BACK"), Rect2(x + 22, y, 196, 14), 10, MUTED)

func _part_image(parent: Node, category: String, id: String, area: Rect2) -> void:
	var path: String = "res://assets/top/parts/%s/%s.png" % [{"blade":"blades", "ratchet":"ratchets", "bit":"bits"}[category], id]
	if not _part_texture_cache.has(path):
		var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if texture == null: return
		var image: Image = texture.get_image()
		if image.is_compressed(): image.decompress()
		var crop: AtlasTexture = AtlasTexture.new()
		crop.atlas = texture
		crop.region = image.get_used_rect()
		_part_texture_cache[path] = crop
	var texture: Texture2D = _part_texture_cache[path]
	var multiple: int = 2 if category == "bit" else 1
	var dimensions: Vector2 = texture.get_size() * multiple
	var sprite: TextureRect = TextureRect.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.position = (area.position + (area.size - dimensions) * 0.5).round()
	sprite.size = dimensions
	parent.add_child(sprite)

func _build_station(collection_mode: bool) -> void:
	_panel(_content, Rect2(16, 62, 220, 245), Color("18242c"), BORDER)
	_label(_content, "EQUIPPED MACHINE" if collection_mode else "PRACTICE MACHINE", Rect2(27, 70, 154, 16), 10, BLUE)
	_preview = _new_preview(Rect2(22, 86, 208, 108), 3.0)
	if collection_mode: _set_preview_build_identity(_preview, _build)
	_assembly_name = _label(_content, PartCatalog.title(_build), Rect2(25, 195, 202, 21), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_assembly_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for index: int in range(3):
		var category: String = ["blade", "ratchet", "bit"][index]
		var name: String = str(PartCatalog.PARTS[category].get(str(_build.get(category, "")), {}).get("name", "EMPTY"))
		_label(_content, category.to_upper(), Rect2(26, 218 + index * 14, 51, 13), 10, MUTED)
		_equipped_slot_labels[category] = _label(_content, name, Rect2(79, 218 + index * 14, 147, 13), 10, TEXT)
	var stat_ids: Array[String] = ["power", "stamina", "grip", "speed", "stability", "mass"]
	var stat_names: Array[String] = ["POWER", "STAMINA", "GRIP", "SPEED", "STABILITY", "MASS"]
	for index: int in range(6):
		var column: int = index % 2
		var row: int = index / 2
		var x: float = 26 + column * 101
		var y: float = 260 + row * 15
		_label(_content, stat_names[index], Rect2(x, y, 63, 10), 10, MUTED)
		_stat_numbers[stat_ids[index]] = _label(_content, "", Rect2(x + 63, y, 28, 10), 10, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		_stat_bars[stat_ids[index]] = _bar(_content, Rect2(x, y + 11, 91, 2), ORANGE if index == 0 else BLUE)

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
	var run_button: Button = _button(_content, "CONTINUOUS RUN", Rect2(30, 143, 268, 31), "start_run")
	var garage_button: Button = _button(_content, "CUSTOMIZE TOP", Rect2(30, 182, 268, 31), "customize")
	var help_button: Button = _button(_content, "HOW TO PLAY", Rect2(30, 221, 128, 31), "help")
	var settings_button: Button = _button(_content, "SETTINGS", Rect2(168, 221, 130, 31), "settings")
	var quit_button: Button = _button(_content, "QUIT", Rect2(30, 260, 268, 28), "quit")
	_panel(_content, Rect2(324, 104, 286, 211))
	_label(_content, "YOUR LOADOUT", Rect2(339, 114, 255, 16), 10, BLUE)
	_new_preview(Rect2(358, 127, 218, 148), 3.0)
	_label(_content, PartCatalog.title(_build), Rect2(334, 264, 266, 23), 12, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var total_parts: int = PartCatalog.BLADE_IDS.size() + PartCatalog.RATCHET_IDS.size() + PartCatalog.BIT_IDS.size()
	var total_assemblies: int = PartCatalog.BLADE_IDS.size() * PartCatalog.RATCHET_IDS.size() * PartCatalog.BIT_IDS.size()
	_label(_content, "%d PARTS  /  %d ASSEMBLIES" % [total_parts, total_assemblies], Rect2(334, 287, 266, 15), 9, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "Steer. Time your burst. Stay in the dish.", Rect2(30, 303, 285, 28), 11, MUTED)
	_label(_content, "KEYBOARD + GAMEPAD    /    STEER   BURST   BRAKE   PAUSE    /    CONTROLS IN HOW TO PLAY", Rect2(30, 333, 582, 16), 9, MUTED)
	_focus_rows([[first], [run_button], [garage_button], [help_button, settings_button], [quit_button]])

## Production collection flow is separate from the unrestricted prototype UI
## below. These screens emit intent; ownership is only changed by the save API.
func show_collection_title(build: Dictionary, settings: Dictionary, initialized: bool) -> void:
	_build = build.duplicate()
	_settings = settings.duplicate()
	_clear("collection_title")
	_label(_content, "SPINNING METAL", Rect2(22, 16, 594, 37), 30)
	_label(_content, "THE WORKBENCH / ASSEMBLE A MACHINE. MAKE IT LAST.", Rect2(24, 55, 590, 17), 10, ORANGE)
	var begin: Button = _button(_content, "START RUN" if initialized else "BEGIN / CHOOSE FIRST TOP", Rect2(24, 94, 286, 34), "start_run" if initialized else "begin_collection", null, true)
	var workshop: Button = _button(_content, "WORKSHOP", Rect2(24, 136, 286, 32), "open_workshop")
	var modes: Button = _button(_content, "PLAY MODES", Rect2(24, 176, 286, 32), "play_modes")
	var options: Button = _button(_content, "OPTIONS", Rect2(24, 216, 138, 32), "settings")
	var help: Button = _button(_content, "HOW TO PLAY", Rect2(172, 216, 138, 32), "help")
	var quit_button: Button = _button(_content, "EXIT", Rect2(24, 256, 286, 30), "quit")
	_panel(_content, Rect2(338, 94, 280, 212), Color("18242c"))
	if initialized and _complete_build(_build):
		_label(_content, "YOUR EQUIPPED MACHINE", Rect2(350, 104, 256, 18), 10, BLUE)
		var preview: Preview = _new_preview(Rect2(346, 126, 264, 126), 4.0)
		_set_preview_build_identity(preview, _build)
		var name: Label = _label(_content, PartCatalog.title(_build), Rect2(350, 258, 256, 23), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label(_content, "PERMANENT PARTS / TEMPORARY POWERS", Rect2(350, 286, 256, 13), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_label(_content, "YOUR FIRST MACHINE" if not initialized else "ASSEMBLY INCOMPLETE", Rect2(350, 104, 256, 26), 20, BLUE, HORIZONTAL_ALIGNMENT_CENTER)
		for index: int in range(3):
			var starter: Dictionary = Starters.get_starter(Starters.IDS[index])
			var preview: Preview = Preview.new()
			preview.position = Vector2(345 + index * 88, 141)
			preview.size = Vector2(88, 89)
			preview.preview_scale = 2
			preview.set_build(starter.assembly)
			preview.set_identity(starter.id, starter.accent)
			_content.add_child(preview)
		var invitation: Label = _label(_content, "Three personalities. One first choice.\nBuild your collection from here." if not initialized else "Inspect your owned parts\nin the Workshop.", Rect2(350, 239, 256, 33), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		invitation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label(_content, "0 OWNED PARTS" if not initialized else "SAVED COLLECTION", Rect2(350, 284, 256, 17), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "Your Run ends. Your collection stays.", Rect2(24, 295, 286, 19), 10, MUTED)
	_input_footer()
	_focus_rows([[begin], [workshop], [modes], [options, help], [quit_button]])

func show_title_gate(initialized: bool = false) -> void:
	_clear("title_gate")
	_label(_content, "SPINNING", Rect2(24, 34, 368, 51), 50)
	_label(_content, "METAL", Rect2(24, 86, 368, 51), 50, ORANGE)
	_rect(_content, Rect2(27, 144, 241, 3), ORANGE)
	_label(_content, "PHYSICAL TOPS. HARD CONTACT.", Rect2(27, 160, 324, 19), 10, TEXT)
	_label(_content, "Build your machine.\nKeep it spinning.", Rect2(27, 185, 302, 39), 10, MUTED)
	_build = Starters.build_for("breaker")
	# Put the physical contact/shadow on the authored service tray at (450,226).
	var preview: Preview = _new_preview(Rect2(310, 73, 280, 178), 4)
	var starter: Dictionary = Starters.get_starter("breaker")
	preview.set_identity("breaker", starter.accent)
	var enter: Button = _button(_content, "PRESS START", Rect2(27, 256, 286, 36), "enter_frontend", null, true)
	_label(_content, "CONTINUE YOUR COLLECTION" if initialized else "CHOOSE YOUR FIRST MACHINE", Rect2(29, 300, 348, 19), 10, BLUE)
	_input_footer()
	_focus_rows([[enter]])

func show_play_modes(build: Dictionary) -> void:
	_build = build.duplicate()
	_clear("play_modes")
	_header("PLAY MODES", "Your owned collection and practice builds remain separate.")
	_panel(_content, Rect2(22, 70, 288, 230))
	_panel(_content, Rect2(330, 70, 288, 230))
	_label(_content, "QUICK DUEL", Rect2(38, 84, 256, 31), 20, BLUE)
	_label(_content, "One rival. One exchange.\nTest your steering, Burst and brake.\nNo collection rewards or purchases.", Rect2(38, 129, 256, 73), 10, TEXT)
	var duel: Button = _button(_content, "LAUNCH QUICK DUEL", Rect2(38, 250, 256, 32), "quick_duel", null, true)
	_label(_content, "PRACTICE GARAGE", Rect2(346, 84, 256, 31), 20, ORANGE)
	_label(_content, "Try every catalogue component.\nBuild and inspect a different top.\nPractice never grants owned parts.", Rect2(346, 129, 256, 73), 10, TEXT)
	var garage: Button = _button(_content, "PRACTICE GARAGE", Rect2(346, 250, 256, 32), "practice_garage")
	var back: Button = _button(_content, "BACK TO WORKBENCH", Rect2(22, 320, 232, 28), "main_menu")
	_focus_rows([[duel, garage], [back]])

func show_starter_ceremony(focus_id: String = "breaker") -> void:
	_clear("starter_ceremony")
	_header("YOUR FIRST MACHINE", "This choice starts your permanent collection. Take a look before you decide.")
	var cards: Array[Button] = []
	var selected: Control
	for index: int in range(Starters.IDS.size()):
		var id: String = Starters.IDS[index]
		var data: Dictionary = Starters.get_starter(id)
		var color: Color = data.accent
		var card: Button = _button(_content, "", Rect2(22 + index * 202, 68, 192, 240), "select_first_starter", id)
		card.set_meta("starter_id", id)
		card.tooltip_text = str(data.name) + " / " + PartCatalog.title(data.assembly)
		_style_card(card, color)
		_rect(card, Rect2(11, 12, 3, 18), color)
		_label(card, str(data.name), Rect2(21, 7, 159, 27), 23, color)
		var preview: Preview = Preview.new()
		preview.position = Vector2(11, 34)
		preview.size = Vector2(170, 138)
		preview.preview_scale = 4.0
		preview.set_build(data.assembly)
		preview.set_identity(id, color)
		card.add_child(preview)
		_label(card, _ceremony_role(id), Rect2(11, 172, 170, 16), 10, color, HORIZONTAL_ALIGNMENT_CENTER)
		var copy: Label = _label(card, _ceremony_copy(id), Rect2(12, 192, 168, 31), 11, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_theme_constant_override("line_spacing", -1)
		_label(card, "CHOOSE AS FIRST TOP", Rect2(12, 223, 168, 15), 10, color, HORIZONTAL_ALIGNMENT_CENTER)
		cards.append(card)
		if id == focus_id: selected = card
	_label(_content, "LEFT / RIGHT  INSPECT     CONFIRM  CHOOSE", Rect2(22, 326, 450, 18), 10, MUTED)
	var back: Button = _button(_content, "BACK", Rect2(510, 321, 108, 27), "main_menu")
	_focus_rows([cards, [back]], selected)

func show_starter_confirmation(starter_id: String) -> void:
	var data: Dictionary = Starters.get_starter(starter_id)
	if data.is_empty(): return
	_build = data.assembly.duplicate()
	_clear("starter_confirm")
	_header("MAKE IT YOURS", "Your first choice stays in your collection history. Your future build can change.")
	_starter_ownership_stage(data, false)
	var back: Button = _button(_content, "BACK / KEEP LOOKING", Rect2(22, 319, 256, 29), "back_to_starters", starter_id)
	var confirm: Button = _button(_content, "CHOOSE " + str(data.name), Rect2(294, 319, 324, 29), "confirm_first_starter", starter_id, true)
	_focus_rows([[back, confirm]], confirm)

func show_starter_owned(starter_id: String) -> void:
	var data: Dictionary = Starters.get_starter(starter_id)
	if data.is_empty(): return
	_build = data.assembly.duplicate()
	_clear("starter_owned")
	_ownership_elapsed = 0.0
	_header(str(data.name) + " IS YOURS", "Your first machine. Three owned parts. A collection that starts here.")
	_starter_ownership_stage(data, true)
	_ownership_note = _label(_content, "PERMANENTLY ADDED TO YOUR COLLECTION", Rect2(22, 310, 382, 27), 11, data.accent)
	var continue_button: Button = _button(_content, "ENTER WORKSHOP", Rect2(426, 319, 192, 29), "finish_ownership", null, true)
	_focus_rows([[continue_button]])
	_ownership_flash = _rect(_content, Rect2(0, 3, 640, 354), Color(data.accent.r, data.accent.g, data.accent.b, 0.14))

func _starter_ownership_stage(data: Dictionary, owned: bool) -> void:
	_panel(_content, Rect2(22, 65, 256, 241), Color("172737"), data.accent)
	_label(_content, "YOUR FIRST TOP" if owned else "ONE COMPLETE STARTING MACHINE", Rect2(36, 76, 228, 17), 10, data.accent, HORIZONTAL_ALIGNMENT_CENTER)
	var preview: Preview = _new_preview(Rect2(33, 94, 234, 183), 4.0)
	preview.set_identity(str(data.id), data.accent)
	_label(_content, _ceremony_role(str(data.id)), Rect2(36, 276, 228, 19), 11, data.accent, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, str(data.name), Rect2(300, 67, 308, 35), 28, data.accent)
	_label(_content, _ceremony_copy(str(data.id)), Rect2(301, 106, 306, 42), 13)
	_label(_content, "THESE PARTS ARE YOURS" if owned else "YOU WILL OWN THESE THREE PARTS", Rect2(301, 157, 306, 17), 11, MUTED)
	for index: int in range(3):
		var category: String = ["blade", "ratchet", "bit"][index]
		var id: String = str(data.assembly[category])
		var y: float = 181 + index * 29
		_rect(_content, Rect2(301, y + 2, 3, 17), data.accent)
		_label(_content, category.to_upper(), Rect2(312, y, 91, 22), 11, MUTED)
		_label(_content, str(PartCatalog.PARTS[category][id].name), Rect2(411, y, 197, 22), 13, TEXT)
	_label(_content, "Other parts can join your collection later.", Rect2(301, 274, 306, 26), 11, MUTED)

func _ceremony_role(id: String) -> String:
	return {"breaker":"AGGRESSIVE / FAST / UNSTABLE", "bastion":"HEAVY / CONTROLLED / DURABLE", "vane":"MOBILE / PRECISE / MOMENTUM"}.get(id, "CUSTOM MACHINE")

func _ceremony_copy(id: String) -> String:
	return {"breaker":"Hits hard. Burns hot.\nLives dangerously.", "bastion":"Plants itself. Takes the hit.\nKeeps spinning.", "vane":"Carries momentum.\nRewards precise control."}.get(id, "Build it your way.")

func show_collection_workshop(build: Dictionary, snapshot: Dictionary) -> void:
	_build = build.duplicate()
	_collection_snapshot = snapshot.duplicate(true)
	_catalogue_practice = false
	_clear("collection_workshop")
	_header("TOP WORKSHOP", "Owned parts build your machine. Run powers never enter your collection.")
	_build_station(true)
	var total_owned: int = 0
	for category: String in ["blade", "ratchet", "bit"]: total_owned += _collection_owned(category).size()
	_label(_content, "%d / 31" % total_owned, Rect2(181, 70, 45, 16), 10, ORANGE, HORIZONTAL_ALIGNMENT_RIGHT)
	_create_workshop_catalogue()
	var back: Button = _button(_content, "WORKBENCH", Rect2(16, 321, 118, 28), "main_menu")
	var practice: Button = _button(_content, "QUICK DUEL / PRACTICE", Rect2(144, 321, 228, 28), "quick_duel")
	var launch: Button = _button(_content, "LAUNCH OWNED TOP", Rect2(382, 321, 242, 28), "launch_owned_run", null, true)
	launch.disabled = not _owned_build_is_complete()
	_catalogue_footer = [back, practice, launch] if not launch.disabled else [back, practice]
	_refresh_garage()
	_show_catalogue_category(_catalogue_category, false)
	_catalogue_navigation(launch if not launch.disabled else back)
	_catalogue_navigation.call_deferred(launch if not launch.disabled else back)

func _create_catalogue_inspector() -> void:
	_catalogue_metadata = _label(_content, "", Rect2(254, 249, 362, 16), 10, BLUE)
	_catalogue_description = _label(_content, "", Rect2(254, 266, 362, 39), 10, TEXT)
	_catalogue_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_catalogue_description.add_theme_constant_override("line_spacing", 0)
	_catalogue_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP

func _create_workshop_catalogue() -> void:
	_panel(_content, Rect2(246, 62, 378, 245), Color("17232b"), BORDER)
	_create_catalogue_inspector()
	for index: int in range(3):
		var category: String = ["blade", "ratchet", "bit"][index]
		var tab: Button = _button(_content, category.to_upper(), Rect2(254 + index * 122, 68, 116, 25))
		tab.set_meta("catalogue_tab", category)
		tab.set_meta("intent", "catalogue_tab")
		tab.set_meta("payload", category)
		tab.pressed.connect(func() -> void: _show_catalogue_category(category))
		_catalogue_tabs[category] = tab
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.position = Vector2(254, 98)
		scroll.size = Vector2(362, 146)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		scroll.follow_focus = true
		scroll.focus_mode = Control.FOCUS_NONE
		_content.add_child(scroll)
		_part_scrolls[category] = scroll
		_catalogue_groups[category] = scroll
		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 7)
		scroll.add_child(grid)
		_part_buttons[category] = {}
		_part_descriptions[category] = _catalogue_description
		var ids: Array = PartCatalog.PARTS[category].keys()
		for id: String in ids:
			var data: Dictionary = PartCatalog.PARTS[category][id]
			var owned: bool = _catalogue_practice or id in _collection_owned(category)
			var selected: bool = owned and str(_build.get(category, "")) == id
			var button: Button = _button(grid, "", Rect2(0, 0, 172, 44), "" if _catalogue_practice else ("equip_part" if owned else "inspect_locked_part"), {"category":category, "id":id})
			button.custom_minimum_size = Vector2(172, 44)
			button.set_meta("part_category", category)
			button.set_meta("part_id", id)
			button.set_meta("owned", owned and not _catalogue_practice)
			button.set_meta("locked", not owned)
			button.tooltip_text = "%s / %s / %s\n%s\n%s" % [str(data.name), category.to_upper(), str(data.get("rarity", "COMMON")), str(data.description), "PRACTICE" if _catalogue_practice else ("OWNED" if owned else "NOT OWNED")]
			if category == "blade": button.tooltip_text += "\nSPIRIT: " + BeastManifestations.display_name_for_blade(id)
			_part_image(button, category, id, Rect2(3, 3, 43, 38))
			var title: Label = _label(button, str(data.name), Rect2(50, 5, 117, 17), 10, TEXT if owned else MUTED)
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var status: Label = _label(button, "EQUIPPED" if selected else ("PRACTICE" if _catalogue_practice else ("OWNED" if owned else "NOT OWNED")), Rect2(50, 25, 117, 13), 10, ORANGE if selected else (BLUE if owned else MUTED))
			button.set_meta("status_label", status)
			button.add_theme_stylebox_override("normal", _box(Color("704c33") if selected else (Color("263640") if owned else Color("162129")), ORANGE if selected else BORDER))
			if _catalogue_practice: button.pressed.connect(func() -> void: _choose_part(category, id))
			button.focus_entered.connect(func() -> void:
				_reveal_catalogue_part(category, button)
				if _catalogue_practice: _describe_practice_part(category, id)
				else: _describe_collection_part(category, id))
			button.mouse_entered.connect(func() -> void:
				if _catalogue_practice: _describe_practice_part(category, id)
				else: _describe_collection_part(category, id))
			_part_buttons[category][id] = button

func _show_catalogue_category(category: String, focus_part: bool = true) -> void:
	if not _catalogue_groups.has(category): return
	_catalogue_category = category
	for id: String in _catalogue_groups:
		_catalogue_groups[id].visible = id == category
		_catalogue_tabs[id].add_theme_stylebox_override("normal", _box(Color("704c33") if id == category else Color("263640"), ORANGE if id == category else BORDER))
		for button: Button in _part_buttons[id].values(): button.focus_mode = Control.FOCUS_ALL if id == category else Control.FOCUS_NONE
	var selected: Button = _part_buttons[category].get(str(_build.get(category, ""))) as Button
	if selected == null: selected = _part_buttons[category].values()[0]
	if _catalogue_practice: _describe_practice_part(category, str(selected.get_meta("part_id")))
	else: _describe_collection_part(category, str(selected.get_meta("part_id")))
	_reveal_catalogue_part.call_deferred(category, selected)
	if not _catalogue_footer.is_empty():
		_catalogue_navigation(selected if focus_part else get_viewport().gui_get_focus_owner())
		_catalogue_navigation.call_deferred(selected if focus_part else get_viewport().gui_get_focus_owner())

func _catalogue_navigation(first: Control = null) -> void:
	if _catalogue_footer.is_empty() or not _part_buttons.has(_catalogue_category): return
	var rows: Array = [_catalogue_tabs.values()]
	var buttons: Array = _part_buttons[_catalogue_category].values()
	for index: int in range(0, buttons.size(), 2): rows.append(buttons.slice(index, mini(index + 2, buttons.size())))
	rows.append(_catalogue_footer)
	if first == null or not is_instance_valid(first) or not first.is_visible_in_tree(): first = _catalogue_tabs[_catalogue_category]
	_focus_rows(rows, first)

func _reveal_catalogue_part(category: String, button: Button) -> void:
	if not is_instance_valid(button) or not _part_scrolls.has(category): return
	var scroll: ScrollContainer = _part_scrolls[category]
	# Equip can replace the screen before a pending layout callback runs.
	if not scroll.is_ancestor_of(button): return
	scroll.ensure_control_visible(button)

func _describe_collection_part(category: String, id: String) -> void:
	if not _part_descriptions.has(category): return
	if not PartCatalog.PARTS[category].has(id): return
	var owned: bool = id in _collection_owned(category)
	var data: Dictionary = PartCatalog.PARTS[category][id]
	var ownership: String = "EQUIPPED" if owned and str(_build.get(category, "")) == id else ("OWNED" if owned else "NOT OWNED")
	_catalogue_metadata.text = "%s / %s / %s / %s" % [str(data.name), category.to_upper(), str(data.get("rarity", "COMMON")), ownership]
	_part_descriptions[category].text = str(data.description)
	_part_descriptions[category].add_theme_color_override("font_color", BLUE if owned else MUTED)

func inspect_locked_part(category: String, id: String) -> void:
	# Kept in-place so an attempted selection never changes layout or focus.
	if screen == "collection_workshop" and not id in _collection_owned(category):
		_describe_collection_part(category, id)

func focus_collection_part(category: String, id: String) -> void:
	if screen not in ["collection_workshop", "garage"] or not _part_buttons.has(category): return
	_show_catalogue_category(category, false)
	var button: Button = _part_buttons[category].get(id) as Button
	if button != null:
		_reveal_catalogue_part(category, button)
		_catalogue_navigation(button)
		_catalogue_navigation.call_deferred(button)

func _collection_owned(category: String) -> Array:
	var rows: Variant = _collection_snapshot.get("owned_parts", {})
	return rows.get(category, []) if rows is Dictionary else []

func _owned_build_is_complete() -> bool:
	if not _complete_build(_build): return false
	for category: String in ["blade", "ratchet", "bit"]:
		if not str(_build[category]) in _collection_owned(category): return false
	return bool(_collection_snapshot.get("can_launch", true))

func _complete_build(value: Dictionary) -> bool:
	for category: String in ["blade", "ratchet", "bit"]:
		if not PartCatalog.PARTS[category].has(str(value.get(category, ""))): return false
	return true

func _set_preview_build_identity(preview: Preview, value: Dictionary) -> void:
	# Historical starter ownership never gives a replacement assembly its skin.
	preview.set_collection_build(value)

func show_collection_error(message: String, return_intent: String = "open_workshop", allow_retry: bool = false) -> void:
	_clear("collection_error")
	_header("COLLECTION NEEDS ATTENTION", "Your collection has not been replaced.")
	_panel(_content, Rect2(80, 87, 480, 184))
	var note: Label = _label(_content, message, Rect2(102, 110, 436, 102), 13, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var back: Button = _button(_content, "BACK", Rect2(102 if allow_retry else 172, 228, 209 if allow_retry else 296, 29), return_intent)
	if allow_retry:
		var retry: Button = _button(_content, "RETRY", Rect2(329, 228, 209, 29), "retry_collection", null, true)
		_focus_rows([[back, retry]], retry)
	else:
		_focus_rows([[back]])

func show_garage(build: Dictionary, practice: bool = false) -> void:
	_build = build.duplicate()
	_catalogue_practice = true
	_clear("garage")
	_header("PRACTICE GARAGE", "Try every component. Practice never grants permanent ownership.")
	_build_station(false)
	_create_workshop_catalogue()
	var back: Button = _button(_content, "BACK", Rect2(16, 321, 118, 28), "main_menu")
	var duel: Button = _button(_content, "QUICK DUEL", Rect2(144, 321, 228, 28), "start_battle", "duel", true)
	var workshop: Button = _button(_content, "OWNED WORKSHOP", Rect2(382, 321, 242, 28), "open_workshop")
	_catalogue_footer = [back, duel, workshop]
	_refresh_garage()
	_show_catalogue_category(_catalogue_category, false)
	_catalogue_navigation(_part_buttons[_catalogue_category].get(str(_build.get(_catalogue_category, ""))))
	_catalogue_navigation.call_deferred(_part_buttons[_catalogue_category].get(str(_build.get(_catalogue_category, ""))))

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
		var strengths: Label = _label(card, str(data.strengths), Rect2(12, 173, 168, 23), 10, color)
		strengths.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var weakness: Label = _label(card, str(data.weakness), Rect2(12, 199, 168, 23), 10, MUTED)
		weakness.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label(card, "CONFIRM / LOCK IN", Rect2(12, 223, 168, 12), 10, TEXT)
		cards.append(card)
		if id == focus_id: selected = card
	_label(_content, "LEFT / RIGHT  CHOOSE      CONFIRM  LOCK IN", Rect2(22, 323, 384, 18), 9, MUTED)
	var custom: Button = _button(_content, "CUSTOM ASSEMBLY RUN", Rect2(426, 321, 192, 25), "custom_run")
	custom.add_theme_font_size_override("font_size", 10)
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

func _describe_practice_part(category: String, id: String) -> void:
	if not is_instance_valid(_catalogue_description): return
	var data: Dictionary = PartCatalog.PARTS[category][id]
	_catalogue_metadata.text = "%s / %s / %s / PRACTICE" % [str(data.name), category.to_upper(), str(data.get("rarity", "COMMON"))]
	_catalogue_description.text = str(data.description)

func _choose_part(category: String, id: String) -> void:
	_build[category] = id
	_refresh_garage()
	_describe_practice_part(category, id)
	action.emit("build_changed", _build.duplicate())

func _refresh_garage() -> void:
	var complete: bool = _catalogue_practice or _owned_build_is_complete()
	_preview.visible = complete
	_preview.set_build(_build)
	_assembly_name.text = PartCatalog.title(_build) if complete else "ASSEMBLY INCOMPLETE"
	for category: String in _equipped_slot_labels:
		_equipped_slot_labels[category].text = str(PartCatalog.PARTS[category].get(str(_build.get(category, "")), {}).get("name", "EMPTY"))
	for category: String in _part_buttons:
		for id: String in _part_buttons[category]:
			var button: Button = _part_buttons[category][id]
			var owned: bool = _catalogue_practice or id in _collection_owned(category)
			var selected: bool = owned and str(_build.get(category, "")) == id
			button.add_theme_stylebox_override("normal", _box(Color("704c33") if selected else (Color("263640") if owned else Color("162129")), ORANGE if selected else BORDER))
			var status: Label = button.get_meta("status_label", null) as Label
			if status != null:
				status.text = "EQUIPPED" if selected else ("PRACTICE" if _catalogue_practice else ("OWNED" if owned else "NOT OWNED"))
				status.add_theme_color_override("font_color", ORANGE if selected else (BLUE if owned else MUTED))
	var stats: Dictionary = PartCatalog.derive(_build)
	for stat: String in _stat_bars:
		var amount: float = float(stats.get(stat, 5.0))
		_stat_bars[stat].value = clampf(amount / 10.0, 0.0, 1.0) if complete else 0
		_stat_numbers[stat].text = "%.1f" % amount if complete else "--"

func show_help() -> void:
	_clear("help")
	_header("HOW TO PLAY", "Physical movement. Permanent parts. A Run that keeps pushing back.")
	_panel(_content, Rect2(22, 65, 279, 237))
	_panel(_content, Rect2(313, 65, 305, 237))
	_label(_content, "CONTROL YOUR TOP", Rect2(37, 77, 249, 20), 20, BLUE)
	var actions: Array[String] = ["steer", "burst", "brake", "pause"]
	var titles: Array[String] = ["STEER / FOLLOW THE SCREEN", "BURST / COMMIT TO A HIT", "BRAKE / LOAD OR CHANGE LINE", "PAUSE / OPTIONS AND RESUME"]
	for index: int in range(actions.size()):
		var purpose: String = actions[index]
		var y: float = 109 + index * 39
		_label(_content, titles[index], Rect2(37, y, 250, 14), 10, TEXT)
		_prompt_labels[purpose] = _label(_content, FrontEnd.prompt(_input_profile, purpose), Rect2(37, y + 15, 250, 14), 10, BLUE)
	_label(_content, "Burst and steering spend spin.\nBrake to shape your next contact.", Rect2(37, 272, 250, 26), 10, MUTED)
	_label(_content, "BUILD A LASTING RUN", Rect2(329, 77, 271, 20), 20, ORANGE)
	var run_copy: Label = _label(_content, "CHOOSE A TOP\nYour three first parts stay owned.\n\nSURVIVE AND INVEST\nCollide with rivals. Earn XP.\nChoose powers, ranks and mutations.\n\nREROLL A DRAFT\nCollect charges on the arena floor.\nSpend a charge for a fresh offer.\n\nKEEP YOUR COLLECTION\nA lost Run ends temporary powers.\nOwned parts and your build remain.", Rect2(329, 106, 273, 165), 10, TEXT)
	run_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_content, "DUEL: DRAIN SPIN OR FIND THE GATE.", Rect2(329, 281, 273, 16), 10, MUTED)
	var back: Button = _button(_content, "BACK TO WORKBENCH", Rect2(22, 318, 184, 28), "main_menu")
	var workshop: Button = _button(_content, "OWNED WORKSHOP", Rect2(218, 318, 184, 28), "open_workshop")
	var duel: Button = _button(_content, "QUICK DUEL", Rect2(414, 318, 204, 28), "quick_duel", null, true)
	_focus_rows([[back, workshop, duel]])

func show_settings(settings: Dictionary, return_intent: String = "main_menu", save_tools_allowed: bool = true) -> void:
	_settings = settings.duplicate()
	_clear("settings")
	_header("OPTIONS", "Changes apply immediately. Your collection is independent of these settings.")
	_panel(_content, Rect2(22, 65, 596, 128))
	_label(_content, "AUDIO", Rect2(34, 71, 116, 15), 10, ORANGE)
	var controls: Array = []
	for index: int in range(3):
		var key: String = ["volume", "music_volume", "sfx_volume"][index]
		var caption: String = ["MASTER", "MUSIC", "SFX"][index]
		var y: float = 91 + index * 22
		_label(_content, caption, Rect2(34, y, 112, 17), 10, TEXT)
		var value_label: Label = _label(_content, "%d%%" % roundi(float(_settings.get(key, 0.65)) * 100), Rect2(542, y, 64, 17), 10, BLUE, HORIZONTAL_ALIGNMENT_RIGHT)
		var slider: HSlider = HSlider.new()
		slider.name = {"volume":"VolumeSlider", "music_volume":"MusicVolumeSlider", "sfx_volume":"SfxVolumeSlider"}[key]
		slider.set_meta("setting_key", key)
		slider.position = Vector2(152, y + 1)
		slider.size = Vector2(374, 15)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.focus_mode = Control.FOCUS_ALL
		slider.value = float(_settings.get(key, 0.65))
		slider.value_changed.connect(func(value: float) -> void:
			_settings[key] = value
			value_label.text = "%d%%" % roundi(value * 100)
			action.emit("settings_changed", _settings.duplicate()))
		_content.add_child(slider)
		var outline: Panel = _panel(slider, Rect2(Vector2(-3, -3), slider.size + Vector2(6, 6)), Color(0, 0, 0, 0), ORANGE)
		outline.name = "FocusOutline"
		outline.add_theme_stylebox_override("panel", slider.get_theme_stylebox("focus"))
		outline.visible = false
		slider.focus_entered.connect(outline.show)
		slider.focus_exited.connect(outline.hide)
		controls.append([slider])
	var mute: Button = _toggle_setting("muted", "MUTE AUDIO", 161, false)
	controls.append([mute])
	_panel(_content, Rect2(22, 204, 596, 96))
	_label(_content, "DISPLAY / COMFORT", Rect2(34, 210, 310, 15), 10, ORANGE)
	var shake: Button = _toggle_setting("screen_shake", "SCREEN SHAKE", 234, true)
	var fullscreen: Button = _toggle_setting("fullscreen", "FULL SCREEN", 265, false)
	controls.append([shake])
	controls.append([fullscreen])
	var back: Button = _button(_content, "BACK", Rect2(22, 321, 134, 28), return_intent)
	var footer: Array = [back]
	if save_tools_allowed:
		footer.append(_button(_content, "SAVE / TESTING TOOLS", Rect2(405, 321, 213, 28), "save_tools"))
	else:
		_label(_content, "SAVE TOOLS LOCKED DURING A RUN", Rect2(237, 325, 381, 17), 10, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	controls.append(footer)
	_focus_rows(controls)

func _toggle_setting(key: String, title: String, y: float, fallback: bool) -> Button:
	_label(_content, title, Rect2(34, y, 410, 24), 10, TEXT)
	var button: Button = _button(_content, "ON" if bool(_settings.get(key, fallback)) else "OFF", Rect2(507, y, 99, 25))
	button.set_meta("setting_key", key)
	button.pressed.connect(func() -> void:
		_settings[key] = not bool(_settings.get(key, fallback))
		button.text = "ON" if _settings[key] else "OFF"
		action.emit("settings_changed", _settings.duplicate()))
	return button

func show_save_tools(snapshot: Dictionary, backups: Array = [], status: String = "", return_intent: String = "back_settings") -> void:
	_clear("save_tools")
	_header("SAVE / TESTING TOOLS", "Explicit local tools. Reset affects the collection, not audio or display settings.")
	_panel(_content, Rect2(22, 66, 596, 242))
	var owned: int = 0
	for category: String in ["blade", "ratchet", "bit"]: owned += snapshot.get("owned_parts", {}).get(category, []).size()
	_label(_content, "COLLECTION: %d OWNED PARTS" % owned, Rect2(38, 81, 556, 22), 20, BLUE)
	_label(_content, "VERIFIED LOCAL BACKUPS: %d" % backups.size(), Rect2(38, 116, 556, 18), 10, TEXT)
	var note: Label = _label(_content, status if not status.is_empty() else "Back up before testing a fresh first choice. Reset first preserves\nthe existing collection in a verified local archive.", Rect2(38, 145, 556, 48), 10, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var backup: Button = _button(_content, "BACK UP COLLECTION", Rect2(38, 211, 556, 31), "backup_collection")
	var reset: Button = _button(_content, "RESET COLLECTION...", Rect2(38, 255, 556, 31), "request_reset_collection")
	var back: Button = _button(_content, "BACK TO OPTIONS", Rect2(22, 321, 238, 28), return_intent)
	_focus_rows([[backup], [reset], [back]], back)

func show_reset_confirmation(snapshot: Dictionary = {}) -> void:
	_clear("reset_confirmation")
	_header("RESET THIS COLLECTION?", "Testing action / A second deliberate confirmation is required.")
	_panel(_content, Rect2(54, 75, 532, 222), Color("2c2524"), ORANGE)
	_label(_content, "YOUR CURRENT COLLECTION WILL BE ARCHIVED.", Rect2(72, 94, 496, 27), 10, ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	var message: Label = _label(_content, "The next start will ask you to choose a first machine again.\n\nOwned parts and the equipped assembly are reset.\nYour audio and display preferences stay as they are.\n\nCancel keeps your collection exactly as it is.", Rect2(76, 134, 488, 99), 10, TEXT)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cancel: Button = _button(_content, "CANCEL / KEEP COLLECTION", Rect2(76, 247, 237, 30), "cancel_reset_collection", null, true)
	var confirm: Button = _button(_content, "ARCHIVE AND RESET", Rect2(326, 247, 236, 30), "confirm_reset_collection", snapshot.get("reset_token", -1))
	_focus_rows([[cancel, confirm]], cancel)
	_input_footer()

func show_pause(is_run: bool = false) -> void:
	_clear("pause", false)
	_rect(_content, Rect2(0, 0, 640, 360), Color(0.02, 0.03, 0.04, 0.77))
	_panel(_content, Rect2(170, 35, 300, 289), Color("1c2933"), BORDER)
	_label(_content, "RUN PAUSED" if is_run else "DUEL PAUSED", Rect2(187, 50, 266, 31), 20, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "Take a breath. Your spin can wait.", Rect2(187, 88, 266, 17), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var resume: Button = _button(_content, "RESUME", Rect2(190, 119, 260, 31), "resume", null, true)
	var options: Button = _button(_content, "OPTIONS", Rect2(190, 158, 260, 29), "settings")
	var restart: Button = _button(_content, "RESTART RUN" if is_run else "RESTART DUEL", Rect2(190, 196, 260, 29), "restart_run" if is_run else "rematch")
	var rows: Array = [[resume], [options], [restart]]
	if is_run:
		rows.append([_button(_content, "END RUN", Rect2(190, 234, 260, 29), "end_run")])
		_label(_content, "ASSEMBLY LOCKED FOR THIS RUN", Rect2(187, 284, 266, 18), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var garage: Button = _button(_content, "WORKSHOP", Rect2(190, 234, 125, 29), "customize")
		var hub: Button = _button(_content, "WORKBENCH", Rect2(325, 234, 125, 29), "main_menu")
		rows.append([garage, hub])
		_label(_content, "DUEL ASSEMBLY / PRACTICE", Rect2(187, 284, 266, 18), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_focus_rows(rows)

func show_reward(offer: Array, owned: Array, slot: int, encounter_id: String, run_seed: int, focus_id: String = "", context: Dictionary = {}) -> void:
	_clear("reward")
	_header(str(context.get("title", "VICTORY  /  PICK A POWER")), str(context.get("subtitle", "Before the final" if slot == 7 else "Encounter %d cleared. Choose one to carry into the next battle." % slot)))
	_label(_content, "MAKE THE NEXT HIT COUNT  /  " + ("FINAL INVESTMENT IN THIS POOL" if offer.size() == 1 else "CHOOSE ONE. KEEP IT FOR THE RUN."), Rect2(24, 60, 592, 18), 10, ORANGE)
	var cards: Array[Button] = []
	var selected: Control
	var start_x: float = (640.0 - offer.size() * 192.0 - (offer.size() - 1) * 10.0) * 0.5
	for index: int in range(offer.size()):
		var id: String = str(offer[index])
		var power: Dictionary = Powers.get_offer(id, int(context.get("power_ranks", {}).get(id, 0)), str(context.get("power_mutations", {}).get(id, "")))
		if power.is_empty(): power = Powers.get_power(id)
		var payload: Dictionary = {"encounter_id":encounter_id, "power_id":id, "run_seed":run_seed}
		if context.has("rerolls"): payload["offer_revision"] = int(context.rerolls.revision)
		var card: Button = _button(_content, "", Rect2(start_x + index * 202, 92, 192, 185), "choose_power", payload)
		card.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		card.set_meta("power_id", id)
		card.tooltip_text = str(power.name) + ": " + str(power.description)
		var color: Color = _power_accent(id)
		_style_card(card, color)
		_label(card, str(power.get("offer_label", "NEW POWER")), Rect2(12, 5, 168, 13), 9, color)
		_power_art(card, id, Rect2(64, 19, 64, 64), card, power)
		_label(card, str(power.name), Rect2(12, 87, 168, 25), 16, TEXT)
		var description: Label = _label(card, str(power.get("card_copy", power.description)), Rect2(12, 112, 168, 48), 11, TEXT)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		description.add_theme_constant_override("line_spacing", -1)
		_label(card, "CONFIRM  /  " + ("CHOOSE BRANCH" if int(context.get("power_ranks", {}).get(id, 0)) == 2 else str(context.get("resume_label", "COLLECT"))), Rect2(12, 166, 168, 16), 9, color)
		cards.append(card)
		if id == focus_id: selected = card
	_label(_content, "POWER FAMILIES  %d / %d  /  FILL SLOTS, THEN DEVELOP YOUR POWERS" % [owned.size(),Powers.FAMILY_CAP], Rect2(24, 281, 592, 15), 9, MUTED)
	_power_labels(owned, 302)
	var rows: Array = [cards]
	if context.has("rerolls"):
		var rerolls: Dictionary = context.rerolls
		var reroll: Button = _button(_content, "REROLL  /  %d LEFT" % int(rerolls.charges), Rect2(437, 324, 179, 25), "reroll_power", {"encounter_id":encounter_id, "run_seed":run_seed, "offer_revision":int(rerolls.revision)})
		reroll.name = "RerollPower"
		reroll.add_theme_font_size_override("font_size", 10)
		reroll.disabled = not bool(rerolls.available)
		reroll.tooltip_text = "Spend one Run charge for a different offer. Drive through floor chips to collect more."
		if not reroll.disabled: rows.append([reroll])
		_label(_content, "CHOOSE / CONFIRM   DOWN: REROLL   PAUSE: RUN MENU", Rect2(24, 334, 402, 16), 8, MUTED)
	else:
		_label(_content, "D-PAD / STICK / ARROWS  CHOOSE     CONFIRM  COLLECT     BACK / PAUSE  RUN MENU", Rect2(24, 334, 592, 16), 9, MUTED)
	if not cards.is_empty(): _focus_rows(rows, selected)

func _power_accent(power_id: String) -> Color:
	return {"impact_wake":Color("f0a15c"), "second_wind":Color("83d89a"), "redline":Color("ef735d"), "iron_comet":Color("f2cc72"), "dead_centre":Color("e9c67b"), "afterimage":Color("67c9e7"), "chain_impact":Color("ce95ee")}.get(power_id, BLUE)

func show_mutation(power_id: String, branches: Array, draft_id: String, run_seed: int, focus_id: String = "") -> void:
	_clear("mutation")
	var color: Color = _power_accent(power_id)
	_rect(_content, Rect2(0, 0, 640, 4), color)
	_label(_content, "MUTATION AVAILABLE", Rect2(24, 12, 592, 32), 26, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, str(Powers.get_power(power_id).name).to_upper() + " III  /  CHOOSE HOW YOUR MACHINE CHANGES", Rect2(24, 46, 592, 17), 11, color, HORIZONTAL_ALIGNMENT_CENTER)
	var cards: Array[Button] = []
	var selected: Control
	# This event has exactly two valid, opposing branches, separate from drafts.
	for index: int in range(mini(2, branches.size())):
		var id: String = str(branches[index])
		if not id in Powers.mutation_choices(power_id): continue
		var branch: Dictionary = Powers.get_mutation(id)
		var card: Button = _button(_content, "", Rect2(28 + index * 318, 73, 266, 248), "choose_mutation", {"encounter_id":draft_id, "branch_id":id, "run_seed":run_seed})
		card.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		card.set_meta("power_id", id)
		card.tooltip_text = str(branch.name) + ": " + str(branch.description)
		_style_card(card, color)
		_label(card, "PERMANENT FOR THIS RUN", Rect2(13, 6, 240, 15), 9, color, HORIZONTAL_ALIGNMENT_CENTER)
		_power_art(card, power_id, Rect2(69, 23, 128, 128), card, branch)
		_label(card, str(branch.name).to_upper(), Rect2(13, 154, 240, 29), 22, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		var copy: Label = _label(card, str(branch.get("card_copy", branch.description)), Rect2(16, 186, 234, 39), 11, TEXT)
		copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		copy.add_theme_constant_override("line_spacing", -1)
		_label(card, "CONFIRM  /  TRANSFORM", Rect2(13, 227, 240, 16), 10, color, HORIZONTAL_ALIGNMENT_CENTER)
		cards.append(card)
		if id == focus_id: selected = card
	_label(_content, "VS", Rect2(300, 176, 40, 29), 16, color, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "BATTLE PAUSED   /   LEFT OR RIGHT TO CHOOSE   /   CONFIRM TO COMMIT", Rect2(24, 334, 592, 16), 9, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	if not cards.is_empty(): _focus_rows([cards], selected)

func focused_power_id() -> String:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return str(focused.get_meta("power_id", "")) if focused != null else ""

func _power_texture(power_id: String, metadata: Dictionary = {}) -> Texture2D:
	var power: Dictionary = Powers.get_power(power_id) if metadata.is_empty() else metadata
	var path: String = str(power.get("icon", ""))
	if path.is_empty() or not ResourceLoader.exists(path): return null
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = load(path)
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

func _power_art(parent: Node, power_id: String, area: Rect2, focused_card: Button = null, metadata: Dictionary = {}) -> TextureRect:
	var power: Dictionary = Powers.get_power(power_id) if metadata.is_empty() else metadata
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

func show_acquisition(power_id: String, resume_label: String = "RETURN TO COMBAT", rank: int = 1, mutation: String = "") -> void:
	_clear("acquisition", false)
	_rect(_content, Rect2(0, 0, 640, 360), Color(INK.r, INK.g, INK.b, 0.82))
	_panel(_content, Rect2(104, 67, 432, 226), PANEL, _power_accent(power_id))
	_rect(_content, Rect2(106, 69, 428, 2), _power_accent(power_id))
	var power: Dictionary = Powers.get_owned_power(power_id, rank, mutation)
	_acquisition_elapsed = 0.0
	_acquisition_icon = _power_art(_content, power_id, Rect2(256, 83, 128, 128), null, power)
	_label(_content, str(power.name).to_upper() + (" MUTATED" if rank == 3 else (" TUNED" if rank == 2 else " ACQUIRED")), Rect2(114, 222, 412, 32), 21, _power_accent(power_id), HORIZONTAL_ALIGNMENT_CENTER)
	if rank > 1:
		_label(_content, "MACHINE TRANSFORMED" if rank == 3 else "RANK II  /  MECHANISM TUNED", Rect2(114, 68, 412, 14), 9, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		_rect(_content, Rect2(104, 67, 3, 226), _power_accent(power_id))
		_rect(_content, Rect2(533, 67, 3, 226), _power_accent(power_id))
	_label(_content, "LOCKED IN  /  " + resume_label, Rect2(114, 263, 412, 18), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_acquisition_flash = _rect(_content, Rect2(105, 68, 430, 224), Color(_power_accent(power_id), 0.18))
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()

func _power_labels(ids: Array, y: float) -> void:
	var step: float = minf(101.0, 592.0 / maxf(1.0, float(ids.size())))
	for index: int in range(ids.size()):
		var power: Dictionary = Powers.get_power(str(ids[index]))
		var area: Rect2 = Rect2(roundf(24 + index * step), y, floorf(step) - 5, 20)
		_panel(_content, area, PANEL, BORDER)
		var name_label: Label = _label(_content, str(power.get("short_label",power.name)) if ids.size() > 7 else str(power.name), area, 9, BLUE, HORIZONTAL_ALIGNMENT_CENTER)
		name_label.tooltip_text = str(power.name)

func show_result(result: Dictionary) -> void:
	if bool(result.get("continuous_run", false)):
		_show_run_result(result)
		return
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

func _show_run_result(result: Dictionary) -> void:
	_clear("result")
	_header("RUN ENDED", "Your temporary powers end here. Your collection stays with you.")
	_panel(_content, Rect2(22, 65, 232, 242))
	_label(_content, "YOUR FINAL MACHINE", Rect2(35, 76, 208, 16), 10, BLUE)
	_build = result.get("build", Starters.build_for(str(result.get("starter_id", "breaker")))).duplicate()
	if not _complete_build(_build): _build = Starters.build_for("breaker")
	var preview: Preview = _new_preview(Rect2(28, 97, 220, 98), 3)
	_set_preview_build_identity(preview, _build)
	var machine: Label = _label(_content, PartCatalog.title(_build), Rect2(34, 200, 208, 26), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	machine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reason: String = str(result.get("reason", "spin_out")).replace("_", " ").to_upper()
	_label(_content, Starters.display_name(str(result.get("starter_id", "custom"))) + " / " + reason, Rect2(34, 239, 208, 27), 10, ORANGE, HORIZONTAL_ALIGNMENT_CENTER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_content, "SEED %d" % int(result.get("run_seed",0)), Rect2(34, 281, 208, 16), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_panel(_content, Rect2(269, 65, 349, 97))
	var seconds: int = floori(float(result.get("survival_time", 0.0)))
	_label(_content, "SURVIVED  %02d:%02d" % [seconds / 60, seconds % 60], Rect2(281, 76, 325, 25), 20, TEXT)
	_label(_content, "%d THREATS CLEARED / LEVEL %d" % [int(result.get("threats_cleared", 0)), int(result.get("level", 1))], Rect2(281, 109, 325, 16), 10, BLUE)
	var defeats: Label = _label(_content, "%d RIVALS / %d SMALL / %d ELITES / %d BOSSES" % [int(result.get("rivals_defeated", 0)), int(result.get("small_enemies_defeated", 0)),int(result.get("elites_defeated",0)),int(result.get("bosses_defeated",0))], Rect2(281, 134, 325, 23), 10, MUTED)
	defeats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel(_content, Rect2(269, 173, 349, 134))
	_label(_content, "FINAL INVESTMENTS", Rect2(281, 181, 325, 14), 10, ORANGE)
	var ids: Array = result.get("owned_power_ids", [])
	if ids.is_empty(): _label(_content, "No power was committed.", Rect2(281, 214, 325, 20), 10, MUTED)
	for index: int in range(ids.size()):
		var id: String = str(ids[index])
		var rank: int = int(result.get("power_ranks", {}).get(id, 1))
		var mutation: String = str(result.get("power_mutations", {}).get(id, ""))
		var data: Dictionary = Powers.get_owned_power(id, rank, mutation)
		var x: float = 281 + (index % 2) * 166
		var y: float = 202 + (index / 2) * 17
		_power_icon(_content, id, Rect2(x, y, 16, 16))
		_label(_content, ["Ⅰ", "Ⅱ", "Ⅲ"][clampi(rank - 1, 0, 2)], Rect2(x + 18, y, 7, 16), 10, ORANGE)
		var display_name: String = str(data.get("name", id)) if not mutation.is_empty() else str(Powers.get_power(id).get("name", id))
		var name: Label = _label(_content, display_name, Rect2(x + 28, y, 136, 16), 10, TEXT)
		name.tooltip_text = str(data.get("name", id)) + " / RANK %d" % rank + (" / " + mutation.replace("_", " ") if not mutation.is_empty() else "")
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var restart: Button = _button(_content, "RESTART RUN", Rect2(22, 321, 286, 28), "restart_run", null, true)
	var garage: Button = _button(_content, "WORKSHOP", Rect2(321, 321, 140, 28), "customize")
	var hub: Button = _button(_content, "WORKBENCH", Rect2(475, 321, 143, 28), "main_menu")
	_focus_rows([[restart, garage, hub]])

func show_hud(stats: Dictionary) -> void:
	if screen != "hud":
		_create_hud()
	var player_spin: float = float(stats.get("player_rpm", 1.0))
	var enemy_spin: float = float(stats.get("enemy_rpm", 1.0))
	_hud["player_bar"].value = clampf(player_spin, 0.0, 1.0)
	_hud["rpm_overflow"].value = maxf(0.0, player_spin - 1.0)
	_hud["rpm_overflow"].visible = player_spin > 1.0
	_hud["enemy_bar"].value = enemy_spin
	_hud["player_name"].text = str(stats.get("player_name", "YOUR TOP"))
	_hud["enemy_name"].text = str(stats.get("enemy_name", "RIVAL"))
	_hud["player_rpm"].text = "%d RPM" % int(stats.get("player_rpm_value", player_spin * 9000.0))
	_rpm_overdrive = bool(stats.get("redline_active", false)) or player_spin > 1.0
	_rpm_heat = clampf(float(stats.get("redline_heat", 0.0)), 0.0, 1.0)
	var recovery: float = float(stats.get("rpm_recovery",0.0))
	if player_spin > 1.0:
		_hud["player_rpm"].text += "  +%d%% OVERDRIVE" % roundi((player_spin - 1.0) * 100.0)
	elif _rpm_overdrive:
		_hud["player_rpm"].text += "  OVERDRIVE"
	elif recovery > 0.0:
		_hud["player_rpm"].text += "  +%d %s" % [int(recovery*9000),"SECOND WIND" if stats.get("rpm_recovery_source","") == "second_wind" else "RECLAIM"]
	elif player_spin < 0.25: _hud["player_rpm"].text += "  LOW SPIN"
	_hud["player_rpm"].modulate = Color("8be6aa") if recovery > 0.0 else (Color("ffb56b") if player_spin > 1.0 else (Color("ff7864") if player_spin < 0.25 else Color.WHITE))
	_animate_rpm_meter()
	_hud["rerolls"].visible = bool(stats.get("is_run", false))
	_hud["rerolls"].text = "REROLLS  %d" % int(stats.get("rerolls", 0))
	_hud["anchor"].visible = bool(stats.get("dead_centre_owned", false))
	if _hud["anchor"].visible:
		var charge: float = float(stats.get("dead_centre_charge", 0.0))
		var maturity: float = float(stats.get("dead_centre_maturity", 0.0))
		var recovering: float = float(stats.get("dead_centre_recovery_rate", 0.0))
		if float(stats.get("dead_centre_recovery_remaining", 1.0)) <= 0.0:
			_hud["anchor"].text = "MOVE OUT / REARM  %d%%" % roundi(float(stats.get("dead_centre_rearm_progress", 0.0)) * 100.0)
		elif not bool(stats.get("dead_centre_central_hold", false)):
			_hud["anchor"].text = "SEEK CENTRE / HOLD"
		elif maturity <= 0.0:
			_hud["anchor"].text = "ATTACHING  %d%%" % roundi(charge * 100.0)
		elif recovering > 0.0:
			_hud["anchor"].text = "ANCHORED  +%d RPM/s" % roundi(recovering * 9000.0)
		else:
			_hud["anchor"].text = "ANCHORED  %d%%" % roundi(maturity * 100.0)
	_hud["enemy_rpm"].text = "%d RPM" % int(stats.get("enemy_rpm_value", enemy_spin * 7000.0))
	var is_swarm: bool = bool(stats.get("is_swarm", false))
	_hud["enemy_bar"].visible = not is_swarm
	_hud["swarm_objective"].visible = is_swarm
	if is_swarm:
		_hud["enemy_name"].text = "AMMUNITION WAVES  %d / %d" % [int(stats.get("swarm_wave", 0)), int(stats.get("swarm_total_waves", 3))]
		_hud["swarm_objective"].text = "%d ACTIVE" % int(stats.get("swarm_active", 0))
		_hud["enemy_rpm"].text = "%d LEFT IN SCHEDULE" % int(stats.get("swarm_remaining", 24))
	var seconds: int = maxi(0, floori(float(stats.get("elapsed", 0.0)))) if bool(stats.get("continuous_run", false)) else maxi(0, ceili(float(stats.get("time_left", 90.0))))
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
	_hud.xp_label.text = "LV %d  /  NEXT INVESTMENT" % level if not progression_max else "LV %d  /  FULL BUILD" % level
	_hud.xp_label.add_theme_color_override("font_color", ORANGE if _xp_near else BLUE)
	_hud.xp_detail.text = "MAX" if progression_max else ("ALMOST THERE" if _xp_near else "%d / %d XP" % [int(xp), int(threshold)])
	_hud["round"].text = str(stats.get("run_label", "FOUNDRY EIGHT  /  DUEL"))
	if bool(stats.get("continuous_run", false)):
		var state: Dictionary = stats.run_state
		_hud["round"].text = "THREAT %d  /  %d CLEARED" % [int(state.threat_number), int(state.threats_cleared)]
		if str(state.phase) == "breathing":
			_hud["enemy_name"].text = "THREAT CLEARED"
			_hud["enemy_bar"].visible = false
			_hud["swarm_objective"].visible = false
			_hud["enemy_rpm"].text = "NEXT THREAT IN %.1f s" % maxf(0.0, float(state.next_at) - float(stats.elapsed))
	if bool(stats.get("continuous_run", false)) and bool(stats.run_state.get("director",false)):
		var state: Dictionary = stats.run_state
		var c: Dictionary = state.census
		var live_full: int = int(c.get("active_full",c.full))
		_hud["round"].text = "TIER %d  /  %d CLEARED  /  PRESSURE %.1f" % [int(state.limits.tier),int(state.threats_cleared),float(c.pressure)]
		_hud["director_callout"].text = str(state.callout)
		_hud["enemy_bar"].visible = live_full > 0
		_hud["swarm_objective"].visible = false
		_hud["enemy_name"].text = str(stats.enemy_name) if live_full > 0 else ("AMMUNITION WAVES" if bool(c.swarm) else "BREATHING ROOM")
		_hud["enemy_rpm"].text = "%d RIVALS / %d SMALL" % [live_full,int(c.small)]
		if bool(state.calm): _hud["enemy_rpm"].text += "  /  EASING"
	else:
		_hud["director_callout"].text = ""
	var ids: Array = stats.get("owned_power_ids", [])
	for index: int in range(Powers.ACTIVE_IDS.size()):
		var icon: TextureRect = _hud["power_%d" % index]
		var slot_x: float = 320.0-minf(float(ids.size()),float(Powers.ACTIVE_IDS.size()))*16.0+index*32.0
		_hud["power_panel_%d" % index].position.x = slot_x
		icon.position.x = slot_x+2.0
		_hud["power_rank_%d" % index].position.x = slot_x+18.0
		var id: String = str(ids[index]) if index < ids.size() else ""
		icon.visible = not id.is_empty()
		_hud["power_panel_%d" % index].visible = not id.is_empty()
		var rank: int = int(stats.get("power_ranks", {}).get(id, 1))
		var mutation: String = str(stats.get("power_mutations", {}).get(id, ""))
		var key: String = "%s/%d/%s" % [id, rank, mutation]
		if str(icon.get_meta("power_state", "")) != key:
			icon.set_meta("power_id", id)
			icon.set_meta("power_state", key)
			var power: Dictionary = Powers.get_owned_power(id, rank, mutation)
			icon.texture = _power_texture(id, power) if not id.is_empty() else null
			icon.tooltip_text = str(power.get("name", "")) + " / RANK " + str(rank)
		_hud["power_rank_%d" % index].text = ["", "Ⅰ", "Ⅱ", "Ⅲ"][clampi(rank, 0, 3)] if not id.is_empty() else ""
		_hud["power_rank_%d" % index].visible = not id.is_empty()
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
	# Normal reserve fills the whole bar. Earned overdrive builds a second
	# coloured layer over its top edge, without reserving a permanent gap.
	_hud["player_bar"].tooltip_text = "Full normal reserve: 9000 RPM. Extra RPM builds a pulsing layer over the top."
	_hud["rpm_overflow"] = _bar(_content, Rect2(22, 34, 202, 4), ORANGE)
	_hud["rpm_overflow"].max_value = 0.24
	_hud["rpm_overflow"].add_theme_stylebox_override("background", StyleBoxEmpty.new())
	_hud["rpm_overflow"].visible = false
	_hud["enemy_bar"] = _bar(_content, Rect2(416, 34, 202, 8), ORANGE)
	_hud["player_rpm"] = _label(_content, "", Rect2(22, 45, 202, 12), 9, MUTED)
	_hud["enemy_rpm"] = _label(_content, "", Rect2(416, 45, 202, 12), 9, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["anchor"] = _label(_content, "", Rect2(22, 65, 202, 13), 8, Color("dde3df"))
	_hud["rerolls"] = _label(_content, "", Rect2(22, 304, 128, 13), 9, BLUE)
	_hud["swarm_objective"] = _label(_content, "", Rect2(416, 30, 202, 14), 10, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_panel(_content, Rect2(268, 8, 104, 36), Color(0.035, 0.065, 0.095, 0.94))
	_hud["time"] = _label(_content, "01:30", Rect2(270, 11, 100, 28), 21, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var pause_button: Button = _button(_content, "PAUSE", Rect2(292, 49, 56, 21), "pause")
	pause_button.add_theme_font_size_override("font_size", 10)
	# Gameplay actions must never move HUD focus or make Confirm swallow Burst.
	# Gamepad/keyboard pause use the shared pause action; mouse keeps this button.
	pause_button.focus_mode = Control.FOCUS_NONE
	_hud["round"] = _label(_content, "", Rect2(175, 76, 290, 16), 9, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_hud["director_callout"] = _label(_content, "", Rect2(120, 96, 400, 22), 15, ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	_hud["announcement"] = _label(_content, "", Rect2(145, 130, 350, 64), 35, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hud["wobble"] = _label(_content, "", Rect2(185, 273, 270, 19), 11, ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	_hud["power_note"] = _label(_content, "", Rect2(22, 291, 594, 12), 8, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	for index: int in range(Powers.ACTIVE_IDS.size()):
		_hud["power_panel_%d" % index] = _panel(_content, Rect2(192 + index * 32, 303, 28, 20))
		var icon: TextureRect = _power_icon(_content, "", Rect2(194 + index * 32, 305, 16, 16))
		_hud["power_rank_%d" % index] = _label(_content, "", Rect2(210 + index * 32, 307, 9, 12), 7, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
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

func _animate_rpm_meter() -> void:
	if screen != "hud" or not _hud.has("player_bar"): return
	var pulse: float = 0.5 + sin(_menu_clock * (8.0 + _rpm_heat * 8.0)) * 0.5
	var color: Color = Color("ff632e").lerp(Color("ffb44b"), pulse) if _rpm_overdrive else BLUE
	var fill: StyleBoxFlat = _hud["rpm_overflow"].get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = color
	if _rpm_overdrive: _hud["player_rpm"].modulate = color
