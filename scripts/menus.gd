extends Control
## Native 640 x 360 menu and HUD layer. Only emits intent; the game owns state.

signal action(name: String, value: Variant)
signal focus_sound(kind: String)
signal input_engaged

const Preview = preload("res://scripts/top_preview.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const Powers = preload("res://scripts/run_powers.gd")
const AbilityCardStyle = preload("res://scripts/ability_card_style.gd")
const Starters = preload("res://scripts/starters.gd")
const BeastManifestations = preload("res://scripts/beast_manifestations.gd")
const PacketView = preload("res://scripts/packet_view.gd")
const PacketEconomy = preload("res://scripts/packet_economy.gd")
const ShopMerchant = preload("res://scripts/shop_merchant.gd")
const AbilityInspection = preload("res://scripts/ability_inspection.gd")
const CreditTransfer = preload("res://scripts/credit_transfer.gd")
const TouchButton = preload("res://scripts/touch_button.gd")
const ControllerBindings = preload("res://scripts/controller_bindings.gd")
const PowerStateMeters = preload("res://scripts/power_state_meters.gd")
const CombatLayout = preload("res://scripts/combat_hud_layout.gd")
const FrontendLayout = preload("res://scripts/frontend_layout.gd")
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
var _acquisition_home_y: float = 83.0
var _run_overlay_shade: ColorRect
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
var _packet_view: Control
var _packet_receipt: Dictionary = {}
var _packet_wallet: Dictionary = {}
var _packet_controls: Array[Control] = []
var _packet_note: Label
var _shop_kind: String = "standard"
var _shop_quantity: int = 1
var _shop_quantities: Dictionary = {"standard":1, "reclaimed":1}
var _shop_cards: Dictionary = {}
var _shop_quantity_hint: Label
var _shop_quantity_buttons: Array[Button] = []
var _shop_snapshot: Dictionary = {}
var _shop_detail: Control
var _shop_merchant: Control
var _shop_rows: Array[Button] = []
var _shop_scroll: ScrollContainer
var _shop_buy: Button
var _shop_odds: Button
var _shop_routes: Array[Button] = []
var _shop_reaction: String = "IDLE"
var _ability_inspector: Control
var _credit_transfer: Control
var _inspection_owned_state: Dictionary = {}
var reduced_flashing: bool = false
## Native layout audit may select the production mobile arrangement explicitly.
var mobile_hud: bool = OS.has_feature("mobile")
var _presentation_canvas: Vector2 = Vector2(800,480)
var _presentation_safe: Rect2 = Rect2()
var _presentation_background: Control
var _presentation_dimmed: bool = true
var _hud_layout: Dictionary = {}
var _presentation_mobile: bool = OS.has_feature("mobile")
var _packet_touch_index: int = -1
var _packet_touch_origin: Vector2 = Vector2.ZERO
var input_suspended: bool = false:
	set(value):
		input_suspended = value
		if value:
			_menu_touch_fingers.clear()
			_touch_transition_fingers.clear()
			_touch_mouse_continuation_blocked = false
			_last_ui_event_was_touch = false
			_last_ui_event_was_emulated_mouse = false
			_touch_transition_awaits_raw_contact = false
var _reroll_control: Button
var _reroll_needs_release: bool = false
var _menu_touch_fingers: Dictionary = {}
var _touch_transition_fingers: Dictionary = {}
var _touch_mouse_continuation_blocked: bool = false
var _last_ui_event_was_touch: bool = false
var _last_ui_event_was_emulated_mouse: bool = false
var _last_emulated_mouse_pressed: bool = false
var _touch_transition_awaits_raw_contact: bool = false
var presentation_mode: String = "frontend"
var _frontend_reflow_pending: bool = false
var _frontend_layout_revision: int = 0
var _frontend_layout: Dictionary = {}
var _frontend_result_kind: String = "result"
var _frontend_settings_nodes: Dictionary = {}

func _ready() -> void:
	if mobile_hud: _input_profile = "touch"
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
		_acquisition_icon.position.y = _acquisition_home_y - roundf(minf(2.0, _acquisition_elapsed * 15.0))
		if is_instance_valid(_acquisition_flash): _acquisition_flash.color.a = maxf(0.0, 0.18 - _acquisition_elapsed * 1.1)
	if screen == "hud" and _run_active:
		_xp_display = move_toward(_xp_display, _xp_target, _delta * 1.6)
		# Quantise the fill to native pixels, while easing meaningful XP increments.
		_hud.xp_bar.value = roundf(_xp_display * _hud.xp_bar.size.x) / _hud.xp_bar.size.x
		_xp_flash = maxf(0.0, _xp_flash - _delta * 2.5)
		_hud.xp_bar.modulate = Color(1.0, 1.0, 1.0, 1.0 if reduced_flashing or not _xp_near else (1.0 if int(_menu_clock * 7.0) % 2 == 0 else 0.65))
		_hud.xp_hit.color.a = _xp_flash * 0.32
	if _accept_needs_release and not Input.is_action_pressed("ui_accept"):
		_accept_needs_release = false
	if screen == "hud" or not is_instance_valid(_default_focus): return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or not _content.is_ancestor_of(focused):
		_default_focus.grab_focus()

func _input(event: InputEvent) -> void:
	if input_suspended:
		get_viewport().set_input_as_handled()
		return
	# A deliberate local interaction also owns the application lifecycle. UI
	# can receive a pad event after desktop focus loss; its timers must not
	# remain suspended until a mouse later restores the OS focus notification.
	var local_press: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed and not event.canceled)
	if event is InputEventJoypadButton and event.pressed and (_ui_owner_device < 0 or event.device == _ui_owner_device): local_press = true
	if local_press: input_engaged.emit()
	if mobile_hud and _fence_mobile_touch_continuation(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("draft_reroll"): _reroll_needs_release = false
	if screen in ["reward", "mutation"] and event.is_action_pressed("draft_reroll"):
		if event is InputEventKey and event.echo: return
		if event is InputEventJoypadButton and _ui_owner_device >= 0 and event.device != _ui_owner_device: return
		if event is InputEventJoypadButton: _note_input_profile(ControllerBindings.profile(event.device))
		elif event is InputEventKey: _note_input_profile("keyboard")
		if _reroll_needs_release:
			get_viewport().set_input_as_handled()
			return
		_reroll_needs_release = true
		if is_instance_valid(_reroll_control) and not _reroll_control.disabled: _reroll_control.pressed.emit()
		get_viewport().set_input_as_handled()
		return
	var local_point: Vector2 = _packet_view.get_global_transform_with_canvas().affine_inverse() * event.position if is_instance_valid(_packet_view) and (event is InputEventScreenTouch or event is InputEventScreenDrag) else Vector2.ZERO
	# Inverse component transforms introduce tiny float error at authored pouch
	# edges. Restore subpixel native coordinates before the unchanged bounds/gate.
	local_point=(local_point*1024.0).round()/1024.0
	if event is InputEventScreenTouch:
		_note_input_profile("touch")
		if (not event.pressed or event.canceled) and event.index == _packet_touch_index: _packet_touch_index = -1
		if screen == "packet_open" and is_instance_valid(_packet_view) and not _packet_view.opening and _packet_view.phase in ["SEALED", "CRINKLE"]:
			var packet_touch_rect: Rect2 = Rect2(100,72,440,205) if _packet_view._quantity>1 else Rect2(222,72,196,205)
			if event.pressed and packet_touch_rect.has_point(local_point):
				_packet_touch_index = event.index
				_packet_touch_origin = local_point
	if event is InputEventScreenDrag and screen == "packet_open" and is_instance_valid(_packet_view) and not _packet_view.opening and event.index == _packet_touch_index:
		if absf(local_point.x - _packet_touch_origin.x) >= 42.0:
			_packet_touch_index = -1
			action.emit("packet_tear", null)
			get_viewport().set_input_as_handled()
	if screen != "hud":
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			if _ui_owner_device >= 0 and event.device != _ui_owner_device:
				get_viewport().set_input_as_handled()
				return
			if (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) >= 0.55):
				_note_input_profile(ControllerBindings.profile(event.device))
		elif (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and not (mobile_hud and event.device == InputEvent.DEVICE_ID_EMULATION)):
			_note_input_profile("keyboard")
	# A result/draft may open while Burst/Confirm is held. Require its release
	# before any new screen can accept it, including keyboard echo events.
	if screen != "hud" and _accept_needs_release and event.is_action("ui_accept"):
		if event.is_action_released("ui_accept"):
			_accept_needs_release = Input.is_action_pressed("ui_accept")
		get_viewport().set_input_as_handled()
		return
	if screen == "shop" and (event is InputEventKey or event is InputEventJoypadButton):
		var shop_focus: Control = get_viewport().gui_get_focus_owner()
		if is_instance_valid(shop_focus) and shop_focus.has_meta("shop_product"):
			if event is InputEventKey and event.echo: return
			if str(shop_focus.get_meta("intent", "")) != "packet_odds" and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
				cycle_shop_quantity(-1 if event.is_action_pressed("ui_left") else 1)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("ui_accept") and str(shop_focus.get_meta("intent", "")) != "packet_odds":
				action.emit("request_packet_purchase", str(shop_focus.get_meta("shop_product")))
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
	if screen == "result" and is_instance_valid(_credit_transfer) and _credit_transfer.running and event.is_action_pressed("ui_accept"):
		if event is InputEventKey and event.echo: return
		_credit_transfer.finish()
		_accept_needs_release = true
		get_viewport().set_input_as_handled()

func _move_analogue_focus(direction: String) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null: return
	if screen == "shop" and focused.has_meta("shop_product") and str(focused.get_meta("intent", "")) != "packet_odds" and direction in ["left", "right"]:
		cycle_shop_quantity(-1 if direction == "left" else 1)
		return
	if focused is HSlider and direction in ["left", "right"]:
		focused.value += focused.step * (-1.0 if direction == "left" else 1.0)
		return
	var path: NodePath = focused.get("focus_neighbor_" + direction)
	var target: Control = focused.get_node_or_null(path) as Control
	if target != null: target.grab_focus()

func _fence_mobile_touch_continuation(event: InputEvent) -> bool:
	# A press may replace its own screen before the corresponding emulated
	# mouse/release finishes. That contact cannot act on the replacement screen.
	if event is InputEventScreenTouch:
		_last_ui_event_was_touch = true
		_last_ui_event_was_emulated_mouse = false
		if not event.pressed or event.canceled:
			_menu_touch_fingers.erase(event.index)
			_touch_transition_fingers.erase(event.index)
			_touch_transition_awaits_raw_contact = false
			return false
		# Godot may dispatch the emulated mouse press before its raw touch.
		# If that mouse already replaced the screen, this is the same contact.
		if _touch_transition_awaits_raw_contact:
			_touch_transition_awaits_raw_contact = false
			_menu_touch_fingers[event.index] = true
			_touch_transition_fingers[event.index] = true
			return true
		var inherited: bool = _menu_touch_fingers.has(event.index) or _touch_transition_fingers.has(event.index)
		if not inherited and _touch_transition_fingers.is_empty(): _touch_mouse_continuation_blocked = false
		_menu_touch_fingers[event.index] = true
		if inherited or not _touch_transition_fingers.is_empty():
			_touch_transition_fingers[event.index] = true
			return true
	elif event is InputEventScreenDrag:
		_last_ui_event_was_touch = true
		_last_ui_event_was_emulated_mouse = false
		return _touch_transition_fingers.has(event.index)
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		_last_ui_event_was_touch = event.device == InputEvent.DEVICE_ID_EMULATION
		_last_ui_event_was_emulated_mouse = _last_ui_event_was_touch
		_last_emulated_mouse_pressed = event is InputEventMouseButton and event.pressed
		return _last_ui_event_was_touch and _touch_mouse_continuation_blocked
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_last_ui_event_was_touch = false
		_last_ui_event_was_emulated_mouse = false
	return false

func _emit_menu_intent(intent: String, payload: Variant) -> void:
	if mobile_hud and _last_ui_event_was_touch and _touch_mouse_continuation_blocked: return
	action.emit(intent,payload)

func _make_theme() -> Theme:
	return FrontEnd.make_theme()

func _box(fill: Color, outline: Color, border_width: int = 1) -> StyleBox:
	return FrontEnd.plate(fill, outline, border_width)

func _clear(next_screen: String, dim: bool = true) -> void:
	if mobile_hud and (_last_ui_event_was_touch or not _menu_touch_fingers.is_empty()):
		_touch_transition_fingers = _menu_touch_fingers.duplicate()
		_touch_mouse_continuation_blocked = true
		_touch_transition_awaits_raw_contact = _last_ui_event_was_emulated_mouse and _last_emulated_mouse_pressed and _menu_touch_fingers.is_empty()
	_reroll_control = null
	_run_overlay_shade = null
	_acquisition_home_y = 83.0
	_reroll_needs_release = next_screen in ["reward", "mutation"] and Input.is_action_pressed("draft_reroll")
	screen = next_screen
	presentation_mode = FrontendLayout.presentation_class(next_screen)
	_frontend_layout.clear()
	_frontend_settings_nodes.clear()
	_frontend_result_kind = "result"
	_packet_touch_index = -1
	_appearance_elapsed = 0.0
	_prompt_labels.clear()
	_prompt_glyphs.clear()
	_catalogue_tabs.clear()
	_catalogue_groups.clear()
	_catalogue_footer.clear()
	_equipped_slot_labels.clear()
	_packet_view = null
	_presentation_background = null
	_presentation_dimmed = dim
	_packet_controls.clear()
	_shop_detail = null
	_shop_cards.clear()
	_shop_quantity_hint = null
	_shop_quantity_buttons.clear()
	_shop_merchant = null
	_shop_rows.clear()
	_shop_routes.clear()
	_shop_buy = null
	_shop_odds = null
	_shop_scroll = null
	_ability_inspector = null
	_credit_transfer = null
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
	if next_screen != "hud":
		_content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		var layout: Dictionary = CombatLayout.responsive(_presentation_canvas,mobile_hud,_presentation_safe)
		_content.position = layout.menu_origin
		_content.scale = Vector2.ONE*float(layout.get("menu_scale",1.0)) if mobile_hud else Vector2.ONE
		_content.size = Vector2(640,360)
		if presentation_mode=="frontend" and not mobile_hud:
			_content.position=Vector2.ZERO
			_content.scale=Vector2.ONE
			_content.size=_presentation_canvas
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)
	_content.child_entered_tree.connect(_schedule_frontend_reflow)
	if dim:
		if mobile_hud or presentation_mode=="frontend": _create_mobile_background()
		else:
			var backdrop: Control = FrontEnd.new()
			backdrop.screen_id = next_screen
			_content.add_child(backdrop)
	_schedule_frontend_reflow()
	if presentation_mode=="modal": call_deferred("_reflow_menu")

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
	if mobile_hud and parent == _content and screen != "hud" and area == Rect2(0,0,640,360):
		node.set_meta("mobile_full_canvas_overlay",true)
		_fit_mobile_overlay(node)
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
	var node: Button = TouchButton.new()
	node.touch_targets = mobile_hud
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
		node.pressed.connect(func() -> void: _emit_menu_intent(intent,payload))
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
	# Thin combat meters retain their native pixel geometry.
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color("0e1924")
	background.border_color = Color("23394c")
	background.set_border_width_all(1)
	background.anti_aliasing = false
	var fill: StyleBox = _box(color, color, 0)
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
	_refresh_reroll_prompt()
	_refresh_ability_prompts()
	for purpose: String in _prompt_labels:
		var label: Label = _prompt_labels[purpose]
		if is_instance_valid(label): label.text = FrontEnd.prompt(profile, purpose) + (" CONFIRM" if purpose == "confirm" else (" BACK" if purpose == "back" else ""))
		var glyph: TextureRect = _prompt_glyphs.get(purpose)
		if is_instance_valid(glyph): glyph.texture = FrontEnd.glyph(profile, purpose)
	_refresh_shop_prompt()

func _refresh_reroll_prompt() -> void:
	if not is_instance_valid(_reroll_control): return
	_reroll_control.text = "%s  REROLL / %d LEFT" % [FrontEnd.prompt(_input_profile, "reroll"), int(_reroll_control.get_meta("charges",0))]
	_reroll_control.tooltip_text = "Right bumper rerolls the current draft. Mutation preview returns to a fresh power draft."

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
func show_collection_title(build: Dictionary, settings: Dictionary, initialized: bool, snapshot: Dictionary = {}) -> void:
	_build = build.duplicate()
	_settings = settings.duplicate()
	_clear("collection_title")
	_label(_content, "SPINNING METAL", Rect2(22, 16, 594, 37), 30)
	_label(_content, "THE WORKBENCH / ASSEMBLE A MACHINE. MAKE IT LAST.", Rect2(24, 55, 590, 17), 10, ORANGE)
	var begin: Button = _button(_content, "START RUN" if initialized else "BEGIN / CHOOSE FIRST TOP", Rect2(24, 88, 286, 32), "start_run" if initialized else "begin_collection", null, true)
	var workshop: Button = _button(_content, "WORKSHOP", Rect2(24, 126, 286, 30), "open_workshop")
	var shop: Button = _button(_content, "PARTS SHOP", Rect2(24, 164, 286, 30), "open_shop")
	var modes: Button = _button(_content, "PLAY MODES", Rect2(24, 202, 286, 30), "play_modes")
	var options: Button = _button(_content, "OPTIONS", Rect2(24, 240, 138, 30), "settings")
	var help: Button = _button(_content, "HOW TO PLAY", Rect2(172, 240, 138, 30), "help")
	var quit_button: Button = _button(_content, "EXIT", Rect2(24, 278, 286, 28), "quit")
	_panel(_content, Rect2(338, 94, 280, 212), Color("18242c"))
	if initialized and _complete_build(_build):
		_label(_content, "YOUR EQUIPPED MACHINE", Rect2(350, 104, 256, 18), 10, BLUE)
		var preview: Preview = _new_preview(Rect2(346, 126, 264, 126), 4.0)
		_set_preview_build_identity(preview, _build)
		preview.set("show_station", true)
		var name: Label = _label(_content, PartCatalog.title(_build), Rect2(350, 258, 256, 23), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var owned_count: int=0
		for category: String in ["blade","ratchet","bit"]: owned_count+=snapshot.get("owned_parts",{}).get(category,[]).size()
		_label(_content, "%d CREDITS / %d SALVAGE\n%d OWNED PARTS / PERMANENT COLLECTION" % [int(snapshot.get("credits",0)),int(snapshot.get("salvage",0)),owned_count], Rect2(350,284,256,22),10,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
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
	_input_footer()
	_focus_rows([[begin], [workshop], [shop], [modes], [options, help], [quit_button]])

func _packet_image(parent: Node, kind: String, area: Rect2) -> void:
	var value: AtlasTexture = AtlasTexture.new()
	value.atlas = load("res://assets/ui/shop_003a/" + ("reclaimed_packet.png" if kind == "reclaimed" else "packet.png"))
	value.region = Rect2(0, 0, 96, 96)
	var sprite: TextureRect = TextureRect.new()
	sprite.texture = value
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.position = area.position
	sprite.size = area.size
	parent.add_child(sprite)

func _ui_image(parent: Node, path: String, area: Rect2) -> TextureRect:
	var node: TextureRect = TextureRect.new()
	node.texture = load(path) if ResourceLoader.exists(path) else null
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.position = area.position
	node.size = area.size
	return node

func selected_shop_product() -> String:
	return _shop_kind

func selected_shop_quantity(kind: String = "") -> int:
	return int(_shop_quantities.get(_shop_kind if kind.is_empty() else kind, 1))

func select_shop_quantity(value: Variant) -> void:
	var kind: String = _shop_kind
	var quantity: Variant = value
	if value is Dictionary:
		kind = str(value.get("kind", ""))
		quantity = value.get("quantity")
	if screen != "shop" or not _shop_quantities.has(kind) or not quantity is int or int(quantity) not in PacketEconomy.BATCH_QUANTITIES: return
	select_shop_product(kind)
	_shop_quantities[kind] = int(quantity)
	_shop_quantity = int(quantity)
	_refresh_shop_cards()

func cycle_shop_quantity(direction: int) -> void:
	if screen != "shop": return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused) or not focused.has_meta("shop_product"): return
	var kind: String = str(focused.get_meta("shop_product"))
	var quantities: Array = PacketEconomy.BATCH_QUANTITIES
	var index: int = (quantities.find(selected_shop_quantity(kind)) + direction + quantities.size()) % quantities.size()
	select_shop_quantity({"kind":kind,"quantity":quantities[index]})
	if str(focused.get_meta("intent", "")) == "packet_quantity":
		_shop_cards[kind].quantities[index].grab_focus()

func _refresh_shop_prompt() -> void:
	if screen == "shop" and is_instance_valid(_prompt_labels.get("confirm")):
		var focused: Control = get_viewport().gui_get_focus_owner()
		var info: bool = is_instance_valid(focused) and str(focused.get_meta("intent", "")) == "packet_odds"
		_prompt_labels.confirm.text = FrontEnd.prompt(_input_profile, "confirm") + (" INFO" if info else " BUY")
		if is_instance_valid(_shop_quantity_hint):
			_shop_quantity_hint.text = "TAP x1 / x3 / x5" if _input_profile == "touch" else ("D-PAD L/R QUANTITY" if _input_profile in ["xbox","nintendo","playstation"] else "LEFT/RIGHT QUANTITY")

func show_shop(snapshot: Dictionary, status: String = "") -> void:
	_clear("shop")
	_shop_snapshot = snapshot.duplicate(true)
	var catalogue_total: int = 0
	for category: String in PartCatalog.PARTS: catalogue_total += PartCatalog.PARTS[category].size()
	_header("FOUNDRY PARTS COUNTER", "CREDITS %d   /   SALVAGE %d   /   OWNED %d / %d" % [int(snapshot.get("credits", 0)), int(snapshot.get("salvage", 0)), int(snapshot.get("total_owned", 0)), catalogue_total])
	_panel(_content, Rect2(22, 65, 207, 238), Color("18242c"))
	_label(_content, "SORTED. SEALED. READY.", Rect2(33, 76, 185, 16), 10, ORANGE)
	_shop_merchant = ShopMerchant.new()
	_shop_merchant.position = Vector2(80, 106)
	_shop_merchant.size = Vector2(96, 128)
	_content.add_child(_shop_merchant)
	_shop_merchant.react(_shop_reaction)
	_shop_reaction = "IDLE"
	_ui_image(_content, "res://assets/ui/human_feedback003a/merchant_fixture.png", Rect2(29, 221, 192, 64))
	_label(_content, status if not status.is_empty() else "Threats pay CREDITS.", Rect2(34, 278, 184, 23), 10, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var products: Dictionary = PacketEconomy.config().packets
	if not products.has(_shop_kind): _shop_kind = str(products.keys()[0])
	_shop_routes.append(_button(_content, "WORKSHOP", Rect2(22, 310, 290, 26), "open_workshop"))
	_shop_routes.append(_button(_content, "BACK TO WORKSHOP" if str(snapshot.get("shop_return", "hub")) == "workshop" else "BACK TO HUB", Rect2(326, 310, 292, 26), "back_shop"))
	_input_footer(339)
	_shop_quantity_hint = _label(_content, "LEFT/RIGHT QUANTITY", Rect2(454, 339, 164, 14), 10, MUTED)
	_refresh_shop_prompt()
	_build_shop_detail()
	_shop_focus(_selected_shop_row())

func _selected_shop_row() -> Button:
	for row: Button in _shop_rows:
		if str(row.get_meta("shop_product", "")) == _shop_kind: return row
	return _shop_rows[0] if not _shop_rows.is_empty() else null

func select_shop_product(kind: String) -> void:
	if screen != "shop" or not PacketEconomy.config().packets.has(kind): return
	if kind == _shop_kind and is_instance_valid(_shop_buy): return
	_shop_kind = kind
	_shop_quantity = selected_shop_quantity(kind)
	if is_instance_valid(_shop_merchant): _shop_merchant.react("SELECT")
	_refresh_shop_cards()

func _shop_focus(first: Control) -> void:
	var rows: Array = []
	for kind: String in ["standard", "reclaimed"]:
		var card: Dictionary = _shop_cards[kind]
		rows.append([card.title])
		rows.append(card.quantities)
		var controls: Array = []
		if not card.buy.disabled: controls.append(card.buy)
		controls.append(card.odds)
		rows.append(controls)
	rows.append(_shop_routes)
	_focus_rows(rows, first)
	# These controls consume Left/Right as quantity. Expose their actual focus
	# behaviour too, so controller traversal never follows a misleading link.
	for kind: String in _shop_cards:
		var card: Dictionary = _shop_cards[kind]
		for control: Button in [card.title,card.buy]:
			control.focus_neighbor_left = control.get_path_to(control)
			control.focus_neighbor_right = control.get_path_to(control)
	_refresh_shop_cards()

func _build_shop_detail() -> void:
	_shop_detail = Control.new()
	_shop_detail.position = Vector2(245, 65)
	_shop_detail.size = Vector2(373, 238)
	_shop_detail.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(_shop_detail)
	for index: int in range(2):
		var kind: String = ["standard", "reclaimed"][index]
		var card: Control = Control.new()
		card.position = Vector2(0, index * 122)
		card.size = Vector2(373, 116)
		_shop_detail.add_child(card)
		var plate: Panel = _panel(card, Rect2(0, 0, 373, 116), Color("18242c"))
		_packet_image(card, kind, Rect2(6, 14, 96, 96))
		var title: Button = _button(card, "", Rect2(110, 3, 249, 21), "inspect_shop_product", kind)
		var price: Label = _label(card, "", Rect2(110, 26, 249, 24), 20, ORANGE)
		var quantities: Array[Button] = []
		for quantity_index: int in range(3):
			var quantity: int = PacketEconomy.BATCH_QUANTITIES[quantity_index]
			quantities.append(_button(card, "x%d" % quantity, Rect2(110 + quantity_index * 84, 53, 81, 24), "packet_quantity", {"kind":kind,"quantity":quantity}))
		var buy: Button = _button(card, "", Rect2(110, 82, 162, 24), "request_packet_purchase", kind)
		var odds: Button = _button(card, "INFO / ODDS", Rect2(278, 82, 81, 24), "packet_odds")
		_label(card, "UNOWNED IF ANY / UNCOMMON+ EACH" if kind == "reclaimed" else "3 PARTS / UNCOMMON+ EACH", Rect2(110, 105, 249, 11), 10, BLUE)
		_shop_cards[kind] = {"plate":plate,"title":title,"price":price,"quantities":quantities,"buy":buy,"odds":odds}
		_shop_rows.append(title)
		var controls: Array = quantities.duplicate()
		controls.append_array([title, buy, odds])
		for control: Button in controls:
			control.set_meta("shop_product", kind)
			control.focus_entered.connect(func() -> void: select_shop_product(kind))
			control.focus_entered.connect(_refresh_shop_prompt)
		for quantity_button: Button in quantities:
			quantity_button.focus_entered.connect(func() -> void: select_shop_quantity(quantity_button.get_meta("payload")))
		title.pressed.connect(func() -> void:
			if screen == "shop" and not _shop_cards[kind].buy.disabled: action.emit("request_packet_purchase", kind))
	_refresh_shop_cards()

func _refresh_shop_cards() -> void:
	if screen != "shop" or _shop_cards.is_empty(): return
	var focus_graph_changed: bool = false
	for kind: String in _shop_cards:
		var card: Dictionary = _shop_cards[kind]
		var quantity: int = selected_shop_quantity(kind)
		var product: Dictionary = PacketEconomy.config().packets[kind]
		var unit: String = str(product.currency).to_upper()
		var price: int = PacketEconomy.packet_cost(kind) * quantity
		var available: int = int(_shop_snapshot.get(str(product.currency), 0))
		var chosen: bool = kind == _shop_kind
		var quantity_control: Button = card.quantities[PacketEconomy.BATCH_QUANTITIES.find(quantity)]
		card.title.focus_neighbor_bottom = card.title.get_path_to(quantity_control)
		card.buy.focus_neighbor_top = card.buy.get_path_to(quantity_control)
		card.title.text = ("STANDARD" if kind == "standard" else "RECLAIMED") + " PARTS PACKET x%d" % quantity
		card.price.text = "%d %s" % [price, unit]
		card.plate.add_theme_stylebox_override("panel", _box(Color("263640") if chosen else Color("18242c"), ORANGE if chosen else BORDER))
		for index: int in range(3):
			card.quantities[index].add_theme_stylebox_override("normal", _box(Color("344853") if PacketEconomy.BATCH_QUANTITIES[index] == quantity else Color("263640"), ORANGE if PacketEconomy.BATCH_QUANTITIES[index] == quantity else BORDER))
		var enough: bool = available >= price and not bool(_shop_snapshot.get("read_only", false))
		var disabled: bool = not enough
		card.buy.text = "BUY / %d %s" % [price, unit] if enough else "NEED %d %s" % [maxi(0, price - available), unit]
		focus_graph_changed = focus_graph_changed or card.buy.disabled != disabled
		card.buy.disabled = disabled
		if chosen:
			_shop_quantity_buttons.assign(card.quantities)
			_shop_buy = card.buy
			_shop_odds = card.odds
	if focus_graph_changed:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if not is_instance_valid(focused) or not _content.is_ancestor_of(focused) or (focused is Button and focused.disabled): focused = _selected_shop_row()
		_shop_focus(focused)

func show_packet_purchase(kind: String, snapshot: Dictionary, token: int, quantity: int = 1) -> void:
	_clear("packet_purchase")
	_header("BUY PARTS PACKETS" if quantity > 1 else "BUY A PARTS PACKET", "Sealed hobby pouches. Three permanent component designs each.")
	_panel(_content, Rect2(98, 75, 444, 216), Color("18242c"))
	var attendant: Control = ShopMerchant.new()
	attendant.position = Vector2(110, 96)
	attendant.size = Vector2(96, 128)
	_content.add_child(attendant)
	attendant.react("PURCHASE")
	_packet_image(_content, kind, Rect2(176, 157, 48, 48))
	_label(_content, ("STANDARD PARTS PACKET" if kind == "standard" else "RECLAIMED PARTS PACKET") + " x%d" % quantity, Rect2(220, 100, 308, 23), 16, TEXT)
	var unit: String = "SALVAGE" if kind == "reclaimed" else "CREDITS"
	_label(_content, "%d %s / YOU HAVE %d" % [PacketEconomy.packet_cost(kind) * quantity, unit, int(snapshot.get(unit.to_lower(), 0))], Rect2(220, 133, 306, 18), 10, ORANGE)
	_label(_content, "1 Blade + 1 Ratchet + 1 Bit\nDuplicates recycle into SALVAGE.", Rect2(220, 162, 306, 35), 10, TEXT)
	_label(_content, "Your contents are saved before the seam tears.", Rect2(112, 214, 417, 17), 10, MUTED)
	var cancel: Button = _button(_content, "CANCEL", Rect2(112, 248, 184, 28), "cancel_packet_purchase")
	var confirm: Button = _button(_content, "BUY / %d %s" % [PacketEconomy.packet_cost(kind) * quantity, unit], Rect2(310, 248, 218, 28), "confirm_packet_purchase", token, true)
	_input_footer()
	_focus_rows([[cancel, confirm]], cancel)

func show_packet_odds(odds: Dictionary) -> void:
	_clear("packet_odds")
	var reclaimed: bool = str(odds.get("kind", "standard")) == "reclaimed"
	_header("RECLAIMED / REAL ODDS" if reclaimed else "PACKET INFO / REAL ODDS", "Reclaimed: one Blade, one Ratchet, one Bit. Uncommon+ and one unowned if any remain." if reclaimed else "Standard: one Blade, one Ratchet, one Bit. At least one Uncommon+.")
	_panel(_content, Rect2(22, 65, 596, 225), Color("18242c"))
	_label(_content, "RARITY", Rect2(36, 76, 132, 16), 10, MUTED)
	for column: int in range(3):
		var category: String = ["blade", "ratchet", "bit"][column]
		_label(_content, category.to_upper(), Rect2(183 + column * 140, 76, 130, 16), 10, BLUE, HORIZONTAL_ALIGNMENT_CENTER)
	for row: int in range(6):
		var rarity: String = PartCatalog.RARITIES[row]
		_label(_content, rarity, Rect2(36, 103 + row * 22, 132, 17), 10, _rarity_color(rarity))
		for column: int in range(3):
			var category: String = ["blade", "ratchet", "bit"][column]
			var chance: float = float(odds.get("categories", {}).get(category, {}).get(rarity, 0.0))
			_label(_content, "%.3f%%" % (chance * 100.0), Rect2(183 + column * 140, 103 + row * 22, 130, 17), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, "Final per-slot probabilities for your collection, including the unowned guarantee." if reclaimed else "Final per-slot probabilities, including the guarantee. Absent tiers show 0%.", Rect2(36, 241, 568, 17), 10, MUTED)
	_label(_content, "All packet designs owned: no NEW guarantee." if reclaimed and not bool(odds.get("new_guarantee", false)) else "Reclaimed: one unowned if any remain, plus Uncommon+. Other parts may duplicate.", Rect2(36, 262, 568, 17), 10, BLUE)
	var back: Button = _button(_content, "BACK TO SHOP", Rect2(22, 306, 184, 26), "open_shop", null, true)
	var alternate: Button = _button(_content, "STANDARD ODDS" if reclaimed else "RECLAIMED ODDS", Rect2(216, 306, 196, 26), "packet_odds" if reclaimed else "packet_reclaimed_odds")
	var salvage_info: Button = _button(_content, "RECYCLING VALUES", Rect2(422, 306, 196, 26), "packet_salvage_info")
	_input_footer(339)
	_focus_rows([[back, alternate, salvage_info]])

func show_packet_salvage_info(values: Dictionary, cost: int) -> void:
	_clear("packet_odds")
	_header("SALVAGE / RECLAIMED PARTS", "You unlock designs, not quantities. Every duplicate becomes SALVAGE.")
	_panel(_content, Rect2(22, 65, 596, 225), Color("18242c"))
	for index: int in range(6):
		var rarity: String = PartCatalog.RARITIES[index]
		_label(_content, "%s DUPLICATE" % rarity, Rect2(40, 80 + index * 28, 250, 17), 10, _rarity_color(rarity))
		_label(_content, "+%d SALVAGE" % int(values.get(rarity, 0)), Rect2(315, 80 + index * 28, 262, 17), 10, TEXT)
	_label(_content, "RECLAIMED PACKET / %d SALVAGE / AT LEAST ONE UNOWNED ELIGIBLE DESIGN" % cost, Rect2(40, 259, 562, 17), 10, BLUE)
	var back: Button = _button(_content, "BACK TO SHOP", Rect2(22, 306, 292, 26), "open_shop", null, true)
	var odds: Button = _button(_content, "STANDARD ODDS", Rect2(326, 306, 292, 26), "packet_odds")
	_input_footer(339)
	_focus_rows([[back, odds]])

func _rarity_color(rarity: String) -> Color:
	return {"TRASH":Color("a49a87"), "COMMON":TEXT, "UNCOMMON":Color("afc28d"), "RARE":BLUE, "EPIC":Color("b1a0c7"), "LEGENDARY":ORANGE}.get(rarity, TEXT)

func show_packet_open(receipt: Dictionary, snapshot: Dictionary, recovered: bool = false) -> void:
	_clear("packet_open")
	_packet_receipt = receipt.duplicate(true)
	_packet_wallet = snapshot.duplicate(true)
	_packet_view = PacketView.new()
	_packet_view.size = Vector2(640, 360)
	_content.add_child(_packet_view)
	_packet_view.cue.connect(func(kind: String) -> void: focus_sound.emit(kind))
	_packet_view.settled.connect(_show_packet_summary)
	_packet_view.presented.connect(func(cursor: int) -> void: action.emit("packet_progress", cursor))
	_header("PARTS ON THE WORKBENCH", "Your packet is saved. Tear the seam and see what came home.")
	_packet_note = _label(_content, "CRINKLE / TEAR / SPILL / INSPECT", Rect2(145, 281, 446, 17), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var tear: Button = _button(_content, "TEAR OPEN", Rect2(22, 309, 292, 27), "packet_tear", null, true)
	var skip: Button = _button(_content, "FAST OPEN ALL" if int(receipt.get("quantity", 1)) > 1 else "FAST OPEN", Rect2(326, 309, 292, 27), "packet_skip")
	tear.tooltip_text = "Confirm to tear. Hold Confirm to accelerate. Back resolves the saved results immediately."
	_packet_controls = [tear, skip]
	_input_footer(339)
	_focus_rows([[tear, skip]])
	_packet_view.configure(receipt, recovered)

func tear_packet() -> void:
	if screen != "packet_open" or not is_instance_valid(_packet_view): return
	_packet_view.tear()
	if is_instance_valid(_packet_note): _packet_note.text = "HOLD CONFIRM TO SPEED UP / BACK TO RESOLVE"
	if not _packet_controls.is_empty(): (_packet_controls[0] as Button).text = "OPENING / HOLD TO SPEED UP"

func skip_packet() -> void:
	if screen == "packet_open" and is_instance_valid(_packet_view): _packet_view.resolve()

func _show_bulk_part_labels(quantity: int) -> void:
	var new_count: int = 0
	for row: Dictionary in _packet_receipt.rows:
		if bool(row.new): new_count += 1
	var total: int = _packet_receipt.rows.size()
	_panel(_content, Rect2(48, 58, 544, 28), Color("18242c"))
	_label(_content, "%d PACKETS / %d PARTS / %d NEW / %d DUPLICATES / +%d SALVAGE" % [quantity, total, new_count, total - new_count, int(_packet_receipt.total_salvage)], Rect2(54, 65, 532, 16), 10, ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	var width: float = 596.0 / quantity
	for index: int in range(total):
		var row: Dictionary = _packet_receipt.rows[index]
		var packet: int = index / 3
		var category: int = index % 3
		var x: float = 22 + packet * width
		var y: float = 126 + category * 62
		var accent: Color = _rarity_color(str(row.rarity))
		_label(_content, str(PartCatalog.PARTS[row.category][row.id].name), Rect2(x + 2, y, width - 4, 12), 8, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		_label(_content, "NEW / " + str(row.rarity) if bool(row.new) else "DUPLICATE / +%d" % int(row.salvage), Rect2(x + 2, y + 13, width - 4, 12), 8, ORANGE if bool(row.new) else MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_rect(_content, Rect2(x + 8, y + 27, width - 16, 1), accent)
	focus_sound.emit("packet_new" if new_count > 0 else "packet_recycle")
	if new_count < total: focus_sound.emit("packet_recycle")
	if _shop_reaction == "RARE": focus_sound.emit("packet_rare")

func _show_packet_summary() -> void:
	if screen != "packet_open": return
	for row: Dictionary in _packet_receipt.get("rows", []):
		if str(row.get("rarity", "")) in ["RARE", "EPIC", "LEGENDARY"]: _shop_reaction = "RARE"
	for control: Control in _packet_controls:
		if is_instance_valid(control):
			control.get_parent().remove_child(control)
			control.queue_free()
	_packet_controls.clear()
	if is_instance_valid(_packet_note): _packet_note.visible = false
	var quantity: int = int(_packet_receipt.get("quantity", 1))
	if quantity > 1: _show_bulk_part_labels(quantity)
	for index: int in range(3 if quantity == 1 else 0):
		var row: Dictionary = _packet_receipt.rows[index]
		var x: float = 88 + index * 156
		var accent: Color = _rarity_color(str(row.rarity))
		_rect(_content, Rect2(x + 13, 212, 126, 1), accent)
		_label(_content, str(row.category).to_upper(), Rect2(x, 219, 152, 15), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_label(_content, str(PartCatalog.PARTS[row.category][row.id].name), Rect2(x, 237, 152, 17), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		_label(_content, str(row.rarity), Rect2(x, 257, 152, 16), 10, accent, HORIZONTAL_ALIGNMENT_CENTER)
		_panel(_content, Rect2(x + 5, 279, 142, 20), Color("263640"), ORANGE if bool(row.new) else BORDER)
		_label(_content, "NEW DESIGN" if bool(row.new) else "DUPLICATE / +%d SALVAGE" % int(row.salvage), Rect2(x + 6, 282, 140, 14), 10, ORANGE if bool(row.new) else MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		focus_sound.emit("packet_new" if bool(row.new) else "packet_recycle")
		if str(row.rarity) in ["RARE", "EPIC", "LEGENDARY"]: focus_sound.emit("packet_rare")
	var workshop: Button = _button(_content, "WORKSHOP", Rect2(22, 309, 174, 27), "packet_workshop", null, true)
	var price: int = PacketEconomy.packet_cost(str(_packet_receipt.kind))
	var unit: String = str(_packet_receipt.currency)
	var another: Button = _button(_content, "OPEN ANOTHER", Rect2(206, 309, 156, 27), "packet_another", str(_packet_receipt.kind))
	another.disabled = int(_packet_wallet.get(unit, 0)) < price
	var shop: Button = _button(_content, "SHOP", Rect2(372, 309, 110, 27), "packet_shop")
	var hub: Button = _button(_content, "CONTINUE", Rect2(492, 309, 126, 27), "packet_continue")
	var row_controls: Array = [workshop]
	if not another.disabled: row_controls.append(another)
	row_controls.append_array([shop, hub])
	_packet_controls.assign(row_controls)
	_accept_needs_release = Input.is_action_pressed("ui_accept")
	_focus_rows([row_controls], workshop)

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
	preview.set("show_station", true)
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
	var back: Button = _button(_content, "BACK TO HUB", Rect2(22, 320, 232, 28), "main_menu")
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
	_panel(_content, Rect2(294, 65, 324, 241), Color("18242c"))
	_label(_content, "YOUR FIRST TOP" if owned else "ONE COMPLETE STARTING MACHINE", Rect2(36, 76, 228, 17), 10, data.accent, HORIZONTAL_ALIGNMENT_CENTER)
	var preview: Preview = _new_preview(Rect2(33, 94, 234, 183), 4.0)
	preview.set_identity(str(data.id), data.accent)
	_label(_content, _ceremony_role(str(data.id)), Rect2(36, 276, 228, 19), 11, data.accent, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, str(data.name), Rect2(308, 77, 294, 30), 28, data.accent)
	_label(_content, _ceremony_copy(str(data.id)), Rect2(309, 113, 290, 37), 10)
	_label(_content, "THESE PARTS ARE YOURS" if owned else "YOU WILL OWN THESE THREE PARTS", Rect2(309, 158, 290, 17), 10, MUTED)
	for index: int in range(3):
		var category: String = ["blade", "ratchet", "bit"][index]
		var id: String = str(data.assembly[category])
		var y: float = 181 + index * 29
		_rect(_content, Rect2(309, y + 2, 3, 17), data.accent)
		_label(_content, category.to_upper(), Rect2(320, y, 83, 22), 10, MUTED)
		_label(_content, str(PartCatalog.PARTS[category][id].name), Rect2(411, y, 188, 22), 10, TEXT)
	_label(_content, "Other parts can join your collection later.", Rect2(309, 274, 290, 23), 10, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
	var back: Button = _button(_content, "BACK TO SHOP" if str(snapshot.get("workshop_return", "hub")) == "shop" else "BACK TO HUB", Rect2(16, 321, 142, 28), "back_workshop")
	var shop: Button = _button(_content, "SHOP", Rect2(166, 321, 72, 28), "open_shop")
	var practice: Button = _button(_content, "QUICK DUEL / PRACTICE", Rect2(246, 321, 158, 28), "quick_duel")
	var launch: Button = _button(_content, "LAUNCH OWNED TOP", Rect2(412, 321, 212, 28), "launch_owned_run", null, true)
	launch.disabled = not _owned_build_is_complete()
	_catalogue_footer = [back, shop, practice, launch] if not launch.disabled else [back, shop, practice]
	_refresh_garage()
	_show_catalogue_category(_catalogue_category, false)
	_catalogue_navigation(launch if not launch.disabled else back)
	_catalogue_navigation.call_deferred(launch if not launch.disabled else back)

func _create_catalogue_inspector() -> void:
	_catalogue_metadata = _label(_content, "", Rect2(254, 249, 362, 16), 10, BLUE)
	_catalogue_metadata.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var columns: int = 2
	if _part_scrolls.has(_catalogue_category) and _part_scrolls[_catalogue_category].get_child_count()>0:
		columns = maxi(1,int(_part_scrolls[_catalogue_category].get_child(0).columns))
	for index: int in range(0, buttons.size(), columns): rows.append(buttons.slice(index, mini(index + columns, buttons.size())))
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

func _style_card(card: Button, accent: Color, semantic: Dictionary = {}) -> void:
	var border: Color = semantic.get("border_color", Color("385266"))
	var width: int = int(semantic.get("border_width", 1))
	var focus_width: int = int(semantic.get("focus_width", 2))
	card.add_theme_stylebox_override("normal", _box(Color("172737"), border, width))
	card.add_theme_stylebox_override("hover", _box(Color("22364a"), accent, width))
	card.add_theme_stylebox_override("pressed", _box(Color("294459"), accent, maxi(2, width)))
	card.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), accent, focus_width))
	_card_animations.append({"card":card, "position":card.position, "accent":accent, "normal_border":border, "normal_width":width, "focused":null})

func _style_ability_card(card: Button, metadata: Dictionary) -> Dictionary:
	var style: Dictionary = Powers.get_card_tier_style(int(metadata.get("rank", 1)), str(metadata.get("mutation", "")))
	_style_card(card, style.accent_color, style)
	var frame := Panel.new()
	frame.name = "SemanticCardFrame"
	frame.size = card.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", AbilityCardStyle.frame_style(style))
	card.add_child(frame)
	_card_animations.back()["semantic_frame"] = frame
	_card_animations.back()["semantic_style"] = style
	card.set_meta("ability_tier", style.tier)
	card.set_meta("ability_badge", style.badge)
	card.set_meta("ability_rank", int(metadata.get("rank", 1)))
	return style

func _ability_badge(card: Button, style: Dictionary, area: Rect2, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var badge: Label = _label(card, str(style.badge), area, 10, style.accent_color, alignment)
	badge.name = "AbilityTierBadge"
	# One/two/three solid ticks also encode the investment without colour.
	for index: int in range(int(style.tier_marks)):
		_rect(card, Rect2(card.size.x - 9 - index * 4, area.position.y + 2, 2, 7), style.accent_color)
	return badge

func _ability_confirm(card: Button, style: Dictionary, area: Rect2, purpose: String, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var prompt: Label = _label(card, _ability_confirm_hint() + " / " + purpose, area, 10, style.accent_color, alignment)
	prompt.name = "AbilityCardConfirm"
	prompt.set_meta("confirmation", purpose)

func _ability_confirm_hint() -> String:
	# The card has one compact action line; the full help retains mouse wording.
	return FrontEnd.prompt(_input_profile, "confirm").split(" / ")[0].trim_suffix(" BUTTON")

func _refresh_ability_prompts() -> void:
	for entry: Dictionary in _card_animations:
		var card: Button = entry.card
		if not is_instance_valid(card): continue
		var prompt: Label = card.get_node_or_null("AbilityCardConfirm") as Label
		if prompt != null: prompt.text = _ability_confirm_hint() + " / " + str(prompt.get_meta("confirmation"))

func _animate_cards() -> void:
	for entry: Dictionary in _card_animations:
		var card: Button = entry.card
		if not is_instance_valid(card): continue
		var focused: bool = card.has_focus()
		if entry.focused == focused: continue
		entry.focused = focused
		card.position = entry.position + Vector2(0, -2 if focused else 0)
		card.add_theme_stylebox_override("normal", _box(Color("243b4d") if focused else Color("172737"), entry.accent if focused else entry.normal_border, int(entry.normal_width)))
		if entry.has("semantic_frame"):
			(entry.semantic_frame as Panel).add_theme_stylebox_override("panel", AbilityCardStyle.frame_style(entry.semantic_style, focused))

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
	var back: Button = _button(_content, "BACK TO HUB", Rect2(22, 318, 184, 28), "main_menu")
	var workshop: Button = _button(_content, "OWNED WORKSHOP", Rect2(218, 318, 184, 28), "open_workshop")
	var duel: Button = _button(_content, "QUICK DUEL", Rect2(414, 318, 204, 28), "quick_duel", null, true)
	_focus_rows([[back, workshop, duel]])

func show_settings(settings: Dictionary, return_intent: String = "main_menu", save_tools_allowed: bool = true) -> void:
	_settings = settings.duplicate()
	_clear("settings")
	_header("OPTIONS", "Changes apply immediately. Your collection is independent of these settings.")
	_frontend_settings_nodes["audio_panel"]=_panel(_content, Rect2(22, 65, 596, 123))
	_frontend_settings_nodes["audio_title"]=_label(_content, "AUDIO", Rect2(34, 71, 116, 15), 10, ORANGE)
	var controls: Array = []
	for index: int in range(3):
		var key: String = ["volume", "music_volume", "sfx_volume"][index]
		var caption: String = ["MASTER", "MUSIC", "SFX"][index]
		var y: float = 91 + index * 22
		_frontend_settings_nodes[key+"_label"]=_label(_content, caption, Rect2(34, y, 112, 17), 10, TEXT)
		var value_label: Label = _label(_content, "%d%%" % roundi(float(_settings.get(key, 0.65)) * 100), Rect2(542, y, 64, 17), 10, BLUE, HORIZONTAL_ALIGNMENT_RIGHT)
		_frontend_settings_nodes[key+"_value"]=value_label
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
		_frontend_settings_nodes[key+"_slider"]=slider
		var outline: Panel = _panel(slider, Rect2(Vector2(-3, -3), slider.size + Vector2(6, 6)), Color(0, 0, 0, 0), ORANGE)
		outline.name = "FocusOutline"
		outline.add_theme_stylebox_override("panel", slider.get_theme_stylebox("focus"))
		outline.visible = false
		slider.focus_entered.connect(outline.show)
		slider.focus_exited.connect(outline.hide)
		controls.append([slider])
	var mute: Button = _toggle_setting("muted", "MUTE AUDIO", 159, false)
	controls.append([mute])
	_frontend_settings_nodes["comfort_panel"]=_panel(_content, Rect2(22, 193, 596, 122))
	_frontend_settings_nodes["comfort_title"]=_label(_content, "DISPLAY / COMFORT", Rect2(34, 196, 310, 15), 10, ORANGE)
	var shake: Button = _toggle_setting("screen_shake", "SCREEN SHAKE", 215, true)
	controls.append([shake])
	var reduced: Button = _toggle_setting("reduced_flashing", "REDUCED FLASHING", 239, false)
	controls.append([reduced])
	controls.append([_toggle_setting("top_status_bars", "TOP STATUS BARS", 263, true,34,270), _toggle_setting("impact_numbers","IMPACT NUMBERS",263,false,336,270)])
	if mobile_hud: _label(_content, "LANDSCAPE / HOLD AND DRAG TO STEER", Rect2(34,291,562,20),10,MUTED)
	else: _frontend_settings_nodes["window_note"]=_label(_content,"WINDOW / USE WINDOWS MAXIMISE AND RESTORE",Rect2(34,291,562,20),10,MUTED)
	var back: Button = _button(_content, "BACK", Rect2(22, 321, 134, 28), return_intent)
	_frontend_settings_nodes["back"]=back
	var footer: Array = [back]
	var layout_button: Button = _button(_content, "CONTROLLER: " + str(_settings.get("controller_layout", "auto")).to_upper(), Rect2(166, 321, 228, 28))
	layout_button.set_meta("setting_key", "controller_layout")
	_frontend_settings_nodes["controller_button"]=layout_button
	layout_button.tooltip_text = "AUTO detects the controller. Choose NINTENDO when an adapter reports Xbox but your buttons are labelled A on the right and B below."
	layout_button.pressed.connect(func() -> void:
		var layouts: Array[String] = ["auto", "nintendo", "xbox", "playstation"]
		_settings["controller_layout"] = layouts[(layouts.find(str(_settings.get("controller_layout", "auto"))) + 1) % layouts.size()]
		layout_button.text = "CONTROLLER: " + str(_settings.controller_layout).to_upper()
		action.emit("settings_changed", _settings.duplicate()))
	footer.append(layout_button)
	if save_tools_allowed:
		var tools: Button=_button(_content, "SAVE / TESTING TOOLS", Rect2(405, 321, 213, 28), "save_tools")
		_frontend_settings_nodes["save_tools"]=tools
		footer.append(tools)
	controls.append(footer)
	_focus_rows(controls)
	if not mobile_hud:
		_frontend_settings_nodes["controls_panel"]=_panel(_content,Rect2(22,65,596,123))
		_content.move_child(_frontend_settings_nodes.controls_panel,0)
		_frontend_settings_nodes["controls_title"]=_label(_content,"CONTROLS",Rect2(34,71,400,20),20,ORANGE)
		_frontend_settings_nodes["controls_copy"]=_label(_content,"STEER / ARROWS OR LEFT STICK\nBURST / SPACE OR FACE BUTTON\nBRAKE / SHIFT OR SHOULDER\nPAUSE / ESC OR MENU",Rect2(34,96,540,80),10,TEXT)

func _toggle_setting(key: String, title: String, y: float, fallback: bool, x: float=34, width: float=572) -> Button:
	var caption: Label=_label(_content,title,Rect2(x,y,width-104,23),10,TEXT)
	var button: Button = _button(_content,"ON" if bool(_settings.get(key,fallback)) else "OFF",Rect2(x+width-80,y,80,23))
	button.set_meta("setting_key", key)
	_frontend_settings_nodes[key+"_label"]=caption
	_frontend_settings_nodes[key+"_button"]=button
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
	var powers: Array = _inspection_owned_state.get("ids", [])
	if is_run and not powers.is_empty():
		_panel(_content, Rect2(22, 35, 390, 289))
		_label(_content, "RUN PAUSED", Rect2(38, 48, 358, 31), 20, TEXT)
		_label(_content, "Your machine waits. Inspect your mechanisms.", Rect2(38, 86, 358, 17), 10, MUTED)
		var resume: Button = _button(_content, "RESUME", Rect2(38, 116, 182, 31), "resume", null, true)
		var options: Button = _button(_content, "OPTIONS", Rect2(38, 159, 182, 29), "settings")
		var restart: Button = _button(_content, "RESTART RUN", Rect2(38, 200, 182, 29), "restart_run")
		var end: Button = _button(_content, "END RUN", Rect2(38, 241, 182, 29), "end_run")
		_label(_content, "ASSEMBLY LOCKED", Rect2(38, 285, 182, 17), 10, MUTED)
		_label(_content, "RUN POWERS", Rect2(234, 99, 162, 14), 10, ORANGE)
		_create_power_inspector(Rect2(430, 65, 188, 242))
		var rows: Array = [[resume], [options], [restart], [end]]
		for index: int in range(mini(powers.size(), Powers.FAMILY_CAP)):
			var id: String = str(powers[index])
			var rank: int = int(_inspection_owned_state.get("ranks", {}).get(id, 1))
			var mutation: String = str(_inspection_owned_state.get("mutations", {}).get(id, ""))
			var data: Dictionary = Powers.get_owned_power(id, rank, mutation)
			var inspect: Button = _button(_content, "", Rect2(234, 116 + index * 27, 164, 24))
			_label(inspect, str(data.name), Rect2(8, 4, 148, 16), 10)
			_bind_power_inspection(inspect, id, rank, mutation)
			rows.append([inspect])
		_focus_rows(rows, resume)
		_ability_inspector.inspect(str(powers[0]), int(_inspection_owned_state.get("ranks", {}).get(powers[0], 1)), str(_inspection_owned_state.get("mutations", {}).get(powers[0], "")))
		return
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
		var hub: Button = _button(_content, "HUB", Rect2(325, 234, 125, 29), "main_menu")
		rows.append([garage, hub])
		_label(_content, "DUEL ASSEMBLY / PRACTICE", Rect2(187, 284, 266, 18), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_focus_rows(rows)

func _create_power_inspector(area: Rect2) -> void:
	_ability_inspector = AbilityInspection.new()
	_ability_inspector.position = area.position
	_ability_inspector.size = area.size
	_ability_inspector.visible = false
	_content.add_child(_ability_inspector)
	_ability_inspector.set_runtime_state(_inspection_owned_state.get("state", {}))

func _bind_power_inspection(control: Control, id: String, rank: int, mutation: String = "", branch_preview: bool = false, hide_on_exit: bool = false) -> void:
	control.tooltip_text = ""
	control.set_meta("inspection_power", id)
	control.set_meta("inspection_rank", rank)
	control.focus_entered.connect(func() -> void:
		if is_instance_valid(_ability_inspector): _ability_inspector.inspect(id, rank, mutation, branch_preview))
	control.mouse_entered.connect(func() -> void:
		if is_instance_valid(_ability_inspector): _ability_inspector.inspect(id, rank, mutation, branch_preview))
	if hide_on_exit:
		control.focus_exited.connect(func() -> void:
			if is_instance_valid(_ability_inspector): _ability_inspector.visible = false)
		control.mouse_exited.connect(func() -> void:
			if not control.has_focus() and is_instance_valid(_ability_inspector): _ability_inspector.visible = false)

func show_reward(offer: Array, owned: Array, slot: int, encounter_id: String, run_seed: int, focus_id: String = "", context: Dictionary = {}) -> void:
	_clear("reward")
	_header(str(context.get("title", "VICTORY / PICK A POWER")), str(context.get("subtitle", "Before the final" if slot == 7 else "Encounter %d cleared. Choose one for the Run." % slot)))
	_label(_content, "CHOOSE ONE / TAP READ FOR DETAILS" if mobile_hud else "CHOOSE ONE / FOCUS TO INSPECT", Rect2(24, 60, 390, 18), 10, ORANGE)
	_create_power_inspector(Rect2(430, 65, 188, 242))
	var cards: Array[Button] = []
	var selected: Control
	var start_x: float = 22 + (392.0 - offer.size() * 124.0 - (offer.size() - 1) * 10.0) * 0.5
	for index: int in range(offer.size()):
		var id: String = str(offer[index])
		var rank: int = int(context.get("power_ranks", {}).get(id, 0))
		var mutation: String = str(context.get("power_mutations", {}).get(id, ""))
		var power: Dictionary = Powers.get_offer(id, rank, mutation)
		if power.is_empty(): power = Powers.get_power(id)
		var payload: Dictionary = {"encounter_id":encounter_id, "power_id":id, "run_seed":run_seed}
		if context.has("rerolls"): payload["offer_revision"] = int(context.rerolls.revision)
		var card: Button = _button(_content, "", Rect2(start_x + index * 134, 86, 124, 202), "choose_power", payload)
		card.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		card.set_meta("power_id", id)
		_bind_power_inspection(card, id, rank, mutation)
		_touch_info(card, id, rank, mutation)
		var style: Dictionary = _style_ability_card(card, power)
		_ability_badge(card, style, Rect2(8, 5, 108, 13))
		_power_art(card, id, Rect2(30, 23, 64, 64), card, power)
		var power_name: Label = _label(card, str(power.name).to_upper(), Rect2(8, 91, 108, 22), 10, style.title_color)
		power_name.name = "AbilityCardTitle"
		if id == "anchor_exchange":
			power_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			power_name.add_theme_constant_override("line_spacing", 0)
			power_name.position.y = 89
			power_name.size.y = 28
		var reading: Dictionary = AbilityInspection.describe(id, rank, mutation)
		var description: Label = _label(card, str(reading.get("what" if rank == 0 else "next", power.get("card_copy", power.description))), Rect2(8, 120 if id=="anchor_exchange" else 116, 108, 57 if id=="anchor_exchange" else 61), 10, TEXT)
		description.name = "AbilityCardBody"
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_constant_override("line_spacing", 0)
		description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_ability_confirm(card, style, Rect2(8, 181, 108, 14), "CHOOSE" if rank == 2 else ("UPGRADE" if rank == 1 else "COLLECT"))
		cards.append(card)
		if id == focus_id: selected = card
	if not mobile_hud: _label(_content, "FAMILIES %d/%d" % [owned.size(), Powers.FAMILY_CAP], Rect2(24, 293, 390, 16), 10, MUTED)
	var rows: Array = [cards]
	if context.has("rerolls"):
		var rerolls: Dictionary = context.rerolls
		var reroll: Button = _button(_content, "REROLL / %d LEFT" % int(rerolls.charges), Rect2(437, 324, 179, 25), "reroll_power", {"encounter_id":encounter_id, "run_seed":run_seed, "offer_revision":int(rerolls.revision)})
		reroll.name = "RerollPower"
		reroll.add_theme_font_size_override("font_size", 10)
		reroll.disabled = not bool(rerolls.available)
		_reroll_control = reroll
		reroll.set_meta("charges",int(rerolls.charges))
		_refresh_reroll_prompt()
		if not reroll.disabled: rows.append([reroll])
		_label(_content, "TAP CARD TO CHOOSE / TAP REROLL" if mobile_hud else "CONFIRM: CHOOSE / MENU: PAUSE", Rect2(24, 334, 402, 16), 10, MUTED)
	else:
		_label(_content, "ARROWS / STICK: INSPECT  CONFIRM: COLLECT  MENU: PAUSE", Rect2(24, 334, 592, 16), 10, MUTED)
	if not cards.is_empty(): _focus_rows(rows, selected)

func show_mutation(power_id: String, branches: Array, draft_id: String, run_seed: int, focus_id: String = "", rerolls: Dictionary = {}) -> void:
	_clear("mutation")
	_header("MUTATION AVAILABLE", str(Powers.get_power(power_id).name).to_upper() + " III / CHOOSE HOW YOUR MACHINE CHANGES")
	_create_power_inspector(Rect2(430, 65, 188, 242))
	var cards: Array[Button] = []
	var selected: Control
	for index: int in range(mini(2, branches.size())):
		var id: String = str(branches[index])
		if not id in Powers.mutation_choices(power_id): continue
		var branch: Dictionary = Powers.get_mutation(id)
		var card: Button = _button(_content, "", Rect2(22 + index * 204, 68, 192, 239), "choose_mutation", {"encounter_id":draft_id, "branch_id":id, "run_seed":run_seed, "offer_revision":int(rerolls.get("revision",0))})
		card.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		card.set_meta("power_id", id)
		var style: Dictionary = _style_ability_card(card, branch)
		_bind_power_inspection(card, power_id, 2, id, true)
		_touch_info(card, power_id, 2, id, true)
		_ability_badge(card, style, Rect2(10, 6, 172, 15), HORIZONTAL_ALIGNMENT_CENTER)
		_power_art(card, power_id, Rect2(32, 25, 128, 128), card, branch)
		var title_size: int = 20
		while title_size > 14 and FrontEnd.pixel_font().get_string_size(str(branch.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 172: title_size -= 2
		var title: Label = _label(card, str(branch.name).to_upper(), Rect2(10, 157, 172, 23), title_size, style.title_color, HORIZONTAL_ALIGNMENT_CENTER)
		title.name = "AbilityCardTitle"
		var copy: Label = _label(card, str(branch.get("card_copy", branch.description)), Rect2(10, 184, 172, 33), 10, TEXT)
		copy.name = "AbilityCardBody"
		copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_theme_constant_override("line_spacing", 0)
		copy.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_ability_confirm(card, style, Rect2(10, 220, 172, 14), "TRANSFORM", HORIZONTAL_ALIGNMENT_CENTER)
		cards.append(card)
		if id == focus_id: selected = card
	var rows: Array = [cards]
	if not rerolls.is_empty():
		_reroll_control = _button(_content,"",Rect2(437,324,179,25),"reroll_mutation",{"encounter_id":draft_id,"run_seed":run_seed,"offer_revision":int(rerolls.revision)})
		_reroll_control.name = "RerollMutation"
		_reroll_control.add_theme_font_size_override("font_size",10)
		_reroll_control.disabled = not bool(rerolls.get("mutation_available",false))
		_reroll_control.set_meta("charges",int(rerolls.charges))
		_refresh_reroll_prompt()
		if not _reroll_control.disabled: rows.append([_reroll_control])
	_label(_content, "READ / CARD: COMMIT" if mobile_hud else "CONFIRM: MUTATE / REROLL: FRESH DRAFT", Rect2(437,309,179,14) if mobile_hud else Rect2(24,334,402,16),10,MUTED)
	if not cards.is_empty(): _focus_rows(rows, selected)

func focused_power_id() -> String:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return str(focused.get_meta("power_id", "")) if focused != null else ""

func _touch_info(card: Button, id: String, rank: int, mutation: String, branch_preview: bool = false) -> void:
	if not mobile_hud: return
	# A separate tap reads the complete guide without accepting a permanent choice.
	var info: Button = _button(_content, "READ", Rect2(card.position.x, 310 if branch_preview else 290, card.size.x, 44))
	info.name = "ReadPower_" + id
	info.pressed.connect(func() -> void:
		card.grab_focus()
		if is_instance_valid(_ability_inspector): _ability_inspector.inspect(id, rank, mutation, branch_preview))

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
	var style: Dictionary = Powers.get_card_tier_style(rank, mutation)
	_rect(_content, Rect2(0, 0, 640, 360), Color(INK.r, INK.g, INK.b, 0.82))
	_panel(_content, Rect2(104, 67, 432, 226), PANEL, style.border_color)
	_rect(_content, Rect2(106, 69, 428, 2), style.accent_color)
	var power: Dictionary = Powers.get_owned_power(power_id, rank, mutation)
	_acquisition_elapsed = 0.0
	_acquisition_icon = _power_art(_content, power_id, Rect2(256, 83, 128, 128), null, power)
	_acquisition_icon.set_meta("frontend_reference",Rect2(256,83,128,128))
	_label(_content, str(power.name).to_upper() + (" MUTATED" if rank == 3 else (" TUNED" if rank == 2 else " ACQUIRED")), Rect2(114, 222, 412, 32), 21, style.title_color, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_content, str(style.badge) + "  /  " + ("MACHINE TRANSFORMED" if rank == 3 else ("MECHANISM TUNED" if rank == 2 else "NEW FAMILY")), Rect2(114, 68, 412, 14), 9, style.accent_color, HORIZONTAL_ALIGNMENT_CENTER)
	if rank > 1:
		_rect(_content, Rect2(104, 67, 3, 226), style.accent_color)
		_rect(_content, Rect2(533, 67, 3, 226), style.accent_color)
	_label(_content, "LOCKED IN  /  " + resume_label, Rect2(114, 263, 412, 18), 10, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_acquisition_flash = _rect(_content, Rect2(105, 68, 430, 224), Color(style.accent_color, 0.18))
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()

func _power_labels(ids: Array, y: float) -> void:
	var step: float = minf(101.0, 592.0 / maxf(1.0, float(ids.size())))
	for index: int in range(mini(ids.size(), Powers.FAMILY_CAP)):
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
	_frontend_result_kind = "duel_result"
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
	_panel(_content, Rect2(269, 172, 349, 42), Color("263640"), BLUE)
	var earned: int = int(result.get("credits_earned", 0))
	var wallet: int = int(result.get("wallet_credits", 0))
	var pending: bool = bool(result.get("payout_pending", false))
	if pending:
		_label(_content, "CREDITS NOT SAVED / RETRY BELOW", Rect2(281, 184, 325, 16), 10, ORANGE)
	else:
		_credit_transfer = CreditTransfer.new()
		_credit_transfer.position = Vector2(269, 172)
		_credit_transfer.size = Vector2(349, 42)
		_credit_transfer.configure(earned, wallet)
		_credit_transfer.cue.connect(func(kind: String) -> void: focus_sound.emit(kind))
		_content.add_child(_credit_transfer)
	_panel(_content, Rect2(269, 223, 349, 84))
	_label(_content, "FINAL INVESTMENTS / FOCUS TO INSPECT", Rect2(281, 229, 325, 14), 10, ORANGE)
	var ids: Array = result.get("owned_power_ids", [])
	var investments: Array[Button] = []
	if ids.is_empty(): _label(_content, "No power was committed.", Rect2(281, 244, 325, 20), 10, MUTED)
	for index: int in range(mini(ids.size(), Powers.FAMILY_CAP)):
		var id: String = str(ids[index])
		var rank: int = int(result.get("power_ranks", {}).get(id, 1))
		var mutation: String = str(result.get("power_mutations", {}).get(id, ""))
		var data: Dictionary = Powers.get_owned_power(id, rank, mutation)
		var x: float = 281 + (index % 2) * 166
		var y: float = 244 + (index / 2) * 15
		var inspect: Button = _button(_content, "", Rect2(x, y, 163, 15))
		inspect.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		inspect.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		_power_icon(inspect, id, Rect2(0, 0, 14, 14))
		_label(inspect, ["I", "II", "III"][clampi(rank - 1, 0, 2)], Rect2(16, 0, 22, 15), 10, ORANGE)
		var display_name: String = str(data.get("name", id)) if not mutation.is_empty() else str(Powers.get_power(id).get("name", id))
		_label(inspect, display_name, Rect2(40, 0, 122, 15), 10, TEXT)
		investments.append(inspect)

	var restart: Button = _button(_content, "RETRY CREDITS" if pending else "RUN AGAIN", Rect2(22, 321, 186, 28), "retry_run_payout" if pending else "restart_run", null, true)
	var shop: Button = _button(_content, "SHOP" + (" / READY" if wallet >= PacketEconomy.packet_cost("standard") else ""), Rect2(218, 321, 112, 28), "open_shop")
	var garage: Button = _button(_content, "WORKSHOP", Rect2(340, 321, 126, 28), "customize")
	var hub: Button = _button(_content, "HUB", Rect2(476, 321, 142, 28), "main_menu")
	_create_power_inspector(Rect2(269, 65, 349, 242))
	for index: int in range(investments.size()):
		var id: String = str(ids[index])
		_bind_power_inspection(investments[index], id, int(result.get("power_ranks", {}).get(id, 1)), str(result.get("power_mutations", {}).get(id, "")), false, true)
	var rows: Array = []
	if not investments.is_empty(): rows.append(investments)
	rows.append([restart, shop, garage, hub])
	_focus_rows(rows, restart)

func show_hud(stats: Dictionary) -> void:
	_inspection_owned_state = {"ids":stats.get("owned_power_ids", []).duplicate(), "ranks":stats.get("power_ranks", {}).duplicate(), "mutations":stats.get("power_mutations", {}).duplicate(), "state":stats.get("power_state", {}).duplicate(true)}

	if screen != "hud":
		_create_hud()
	_hud["state_meters"].update_state(_inspection_owned_state.state)
	_hud["impact_confirmation"].text = str(stats.get("impact_confirmation",""))
	if is_instance_valid(_ability_inspector): _ability_inspector.set_runtime_state(_inspection_owned_state.state)
	var player_spin: float = float(stats.get("player_rpm", 1.0))
	var enemy_spin: float = float(stats.get("enemy_rpm", 1.0))
	_hud["player_bar"].value = clampf(player_spin, 0.0, 1.0)
	_hud["rpm_overflow"].value = maxf(0.0, player_spin - 1.0)
	_hud["rpm_overflow"].visible = player_spin > 1.0
	_hud["enemy_bar"].value = enemy_spin
	_hud["player_name"].text = str(stats.get("player_name", "YOUR TOP"))
	_hud["enemy_name"].text = str(stats.get("enemy_name", "RIVAL"))
	_hud["player_rpm"].text = "%d RPM" % int(stats.get("player_rpm_value", player_spin * 9000.0))
	_rpm_overdrive = bool(stats.get("overdrive_active", player_spin > 1.00001))
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
	elif phase == "reentry":
		announcement = "READY  %.1f" % float(stats.get("reentry_remaining", 1.25))
	elif phase == "launch":
		announcement = "LAUNCH"
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
	_hud.controls.visible = not _run_active and not mobile_hud
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
	_hud["round"].text = str(stats.get("run_label", "DUEL"))
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
		_hud["round"].text = "TIER %d / %d CLEARED" % [int(state.limits.tier),int(state.threats_cleared)]
		_hud["director_callout"].text = str(state.callout)
		_hud["enemy_bar"].visible = true
		_hud["enemy_bar"].value = clampf(float(c.pressure) / maxf(0.001, float(state.limits.budget)), 0.0, 1.0)
		_hud["enemy_bar"].tooltip_text = "Live threat pressure / Director budget. Includes rivals, small tops and reserved entrances."
		_hud["swarm_objective"].visible = false
		_hud["enemy_name"].text = "PRESSURE %.1f / %.1f" % [float(c.pressure), float(state.limits.budget)]
		_hud["enemy_rpm"].text = "%d RIVALS / %d SMALL" % [live_full,int(c.small)]
		if bool(state.calm): _hud["enemy_rpm"].text += "  /  EASING"
	else:
		_hud["director_callout"].text = ""
	var ids: Array = stats.get("owned_power_ids", [])
	for index: int in range(Powers.ACTIVE_IDS.size()):
		var icon: TextureRect = _hud["power_%d" % index]
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
			icon.tooltip_text = ""
			icon.set_meta("current_rank", rank)
			icon.set_meta("current_mutation", mutation)
		_hud["power_rank_%d" % index].text = str(rank) if not id.is_empty() else ""
		_hud["power_rank_%d" % index].visible = not id.is_empty()
	_hud["power_note"].text = "RUN POWERS" if not ids.is_empty() else ""
	_place_hud_power_slots(ids)
	_compact_mobile_hud_text(stats)

func _compact_mobile_hud_text(stats: Dictionary) -> void:
	var wide: bool = mobile_hud and bool(_hud_layout.get("mobile_wide",false))
	_hud["pressure_counts"].visible = wide and bool(stats.get("continuous_run",false)) and bool(stats.get("run_state",{}).get("director",false))
	if mobile_hud and bool(stats.get("continuous_run",false)) and bool(stats.get("run_state",{}).get("director",false)):
		_hud["round"].text = "T%d / %d CLEARED" % [int(stats.run_state.limits.tier),int(stats.run_state.threats_cleared)]
	if not wide: return
	_hud["player_rpm"].text = "%d RPM" % int(stats.get("player_rpm_value",float(stats.get("player_rpm",1.0))*9000.0))
	var cooldown: float = float(stats.get("burst_cooldown",0.0))
	var ready: bool = bool(stats.get("burst_ready",cooldown <= 0.0))
	_hud["burst"].text = "BURST READY" if ready else ("LOW SPIN" if cooldown <= 0.0 else "BURST %.1fs" % cooldown)
	if _run_active:
		var level: int = int(stats.get("level",1))
		_hud["xp_label"].text = "LV %d / %s" % [level,"MAX" if bool(stats.get("progression_max",false)) else "NEXT"]
	if _hud["pressure_counts"].visible:
		var state: Dictionary = stats.run_state
		var census: Dictionary = state.census
		_hud["enemy_name"].text = "PRESSURE"
		_hud["enemy_rpm"].text = "%.1f / %.1f" % [float(census.pressure),float(state.limits.budget)]
		_hud["pressure_counts"].text = "%dRIVALS/%dSMALL" % [int(census.get("active_full",census.full)),int(census.small)]

func _create_hud() -> void:
	_clear("hud", false)
	_xp_display = 0.0
	_hud["player_panel"] = _panel(_content,Rect2(86,6,248,48),Color("14232e"),Color("335a70"))
	_hud["enemy_panel"] = _panel(_content,Rect2(466,6,248,48),Color("14232e"),Color("73513b"))
	_hud["player_name"] = _label(_content,"YOUR TOP",Rect2(96,8,228,15),10,BLUE)
	_hud["enemy_name"] = _label(_content,"RIVAL",Rect2(476,8,228,15),10,ORANGE,HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["player_bar"] = _bar(_content,Rect2(96,26,228,7),BLUE)
	_hud["player_bar"].tooltip_text = "Normal reserve: 9000 RPM. OVERDRIVE means actual extra RPM."
	_hud["rpm_overflow"] = _bar(_content,Rect2(96,26,228,3),ORANGE)
	_hud["rpm_overflow"].max_value = 0.24
	_hud["rpm_overflow"].add_theme_stylebox_override("background",StyleBoxEmpty.new())
	_hud["rpm_overflow"].visible = false
	_hud["enemy_bar"] = _bar(_content,Rect2(476,26,228,7),ORANGE)
	_hud["player_rpm"] = _label(_content,"",Rect2(96,36,228,14),10,MUTED)
	_hud["enemy_rpm"] = _label(_content,"",Rect2(476,36,228,14),10,MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["pressure_counts"] = _label(_content,"",Rect2(466,56,248,10),10,MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["pressure_counts"].visible = false
	_hud["impact_confirmation"] = _label(_content,"",Rect2(6,248,68,68),10,ORANGE)
	_hud["impact_confirmation"].autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_hud["state_meters"] = PowerStateMeters.new()
	_content.add_child(_hud["state_meters"])
	_hud["rerolls"] = _label(_content,"",Rect2(6,425,74,24),10,BLUE)
	_hud["swarm_objective"] = _label(_content,"",Rect2(476,24,228,12),10,TEXT,HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["clock_panel"] = _panel(_content,Rect2(344,6,112,48),Color("14232e"))
	_hud["time"] = _label(_content,"01:30",Rect2(346,6,108,25),20,TEXT,HORIZONTAL_ALIGNMENT_CENTER)
	var pause_button: Button = _button(_content,"PAUSE",Rect2(6,8,68,24),"pause")
	_hud["pause_button"] = pause_button
	pause_button.add_theme_font_size_override("font_size",10)
	pause_button.focus_mode = Control.FOCUS_NONE
	_hud["round"] = _label(_content,"",Rect2(342,31,116,11),9,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	_hud["director_callout"] = _label(_content,"",Rect2(336,43,128,11),9,ORANGE,HORIZONTAL_ALIGNMENT_CENTER)
	_hud["announcement"] = _label(_content,"",Rect2(225,190,350,64),35,TEXT,HORIZONTAL_ALIGNMENT_CENTER)
	_hud["power_note"] = _label(_content,"",Rect2(86,424,136,18),10,MUTED)
	for index: int in range(Powers.ACTIVE_IDS.size()):
		_hud["power_panel_%d" % index] = _panel(_content,Rect2(272+index*32,424,28,22))
		var icon: TextureRect = _power_icon(_content,"",Rect2(274+index*32,427,16,16))
		_hud["power_rank_%d" % index] = _label(_content,"",Rect2(290+index*32,429,9,14),9,TEXT,HORIZONTAL_ALIGNMENT_CENTER)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		icon.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventScreenTouch and event.pressed:
				action.emit("pause",null)
				get_viewport().set_input_as_handled())
		_hud["power_%d" % index] = icon
	_hud["burst_panel"] = _panel(_content,Rect2(86,450,224,28),Color("14232e"))
	_hud["burst"] = _label(_content,"BURST READY",Rect2(97,452,203,16),10,BLUE)
	_hud["burst_bar"] = _bar(_content,Rect2(97,472,203,3),BLUE)
	_hud["controls"] = _label(_content,"STEER / BURST / BRAKE / PAUSE",Rect2(326,452,388,18),10,MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["xp_panel"] = _panel(_content,Rect2(326,450,388,28),Color("14232e"),Color("477877"))
	_hud["xp_label"] = _label(_content,"LV 1 / NEXT POWER",Rect2(336,452,230,15),10,BLUE)
	_hud["xp_detail"] = _label(_content,"0 / 1 XP",Rect2(574,452,130,15),10,TEXT,HORIZONTAL_ALIGNMENT_RIGHT)
	_hud["xp_bar"] = _bar(_content,Rect2(336,472,368,4),Color("83d89a"))
	_hud["xp_hit"] = _rect(_content,Rect2(326,450,388,28),Color(1,.9,.6,0))
	if mobile_hud: _hud["controls"].visible = false
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null: focus.release_focus()
	_create_power_inspector(Rect2(526,166,188,242))
	for index: int in range(Powers.ACTIVE_IDS.size()):
		var icon: Control = _hud["power_%d" % index]
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		icon.mouse_entered.connect(func() -> void: _inspect_hud_power(index))
		icon.mouse_exited.connect(func() -> void:
			if is_instance_valid(_ability_inspector) and screen == "hud": _ability_inspector.visible = false)
	_reflow_hud()

func set_presentation_canvas(canvas_size: Vector2, safe_rect: Rect2 = Rect2()) -> void:
	if _presentation_canvas == canvas_size and _presentation_safe == safe_rect and _presentation_mobile == mobile_hud: return
	var changed_mobile: bool = _presentation_mobile != mobile_hud
	_presentation_canvas = canvas_size
	_presentation_safe = safe_rect
	_presentation_mobile = mobile_hud
	if changed_mobile and mobile_hud: _note_input_profile("touch")
	if not is_instance_valid(_content): return
	if changed_mobile:
		for child: Node in _content.find_children("*","Button",true,false):
			if child.get_script() == TouchButton: child.touch_targets = mobile_hud
	if screen == "hud": _reflow_hud()
	else: _reflow_menu()

func _create_mobile_background() -> void:
	if (not mobile_hud and presentation_mode!="frontend") or not _presentation_dimmed or screen == "hud": return
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = load(FrontEnd.BACKGROUND_PATH)
	var frame: int = int(FrontEnd.SCREEN_REGISTRY.get(screen,{}).get("background",1))
	atlas.region = Rect2(maxi(0,frame)*640,0,640,360)
	var backdrop: TextureRect = TextureRect.new()
	backdrop.name = "FullCanvasMobileMenuBackground"
	backdrop.texture = atlas
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.size = _presentation_canvas
	add_child(backdrop)
	move_child(backdrop,0)
	_presentation_background = backdrop

func _fit_mobile_overlay(node: Control) -> void:
	# The existing dim rectangle covers the whole mobile canvas while the
	# authored interactive panel remains uniformly centred inside safe bounds.
	node.position = -_content.position / _content.scale
	node.size = _presentation_canvas / _content.scale

func _reflow_menu() -> void:
	if not is_instance_valid(_content) or screen == "hud": return
	if presentation_mode=="frontend":
		_reflow_frontend()
		return
	if not mobile_hud and FrontendLayout.uses_run_overlay(screen):
		_reflow_run_overlay()
		return
	if FrontendLayout.uses_run_overlay(screen): _restore_run_overlay_reference()
	_frontend_layout.clear()
	var layout: Dictionary = CombatLayout.responsive(_presentation_canvas,mobile_hud,_presentation_safe)
	_content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_content.position = layout.menu_origin
	_content.scale = Vector2.ONE*float(layout.get("menu_scale",1.0)) if mobile_hud else Vector2.ONE
	_content.size = Vector2(640,360)
	if not mobile_hud:
		var modal_scale: float = FrontendLayout.modal_scale(_presentation_canvas,screen)
		_content.scale = Vector2.ONE*modal_scale
		_content.position = (_presentation_canvas-_content.size*modal_scale)*.5
	var native_background: Control = null
	for child: Node in _content.get_children():
		if child.get_script() == FrontEnd:
			native_background = child
			child.visible = not mobile_hud
		if child is Control and child.has_meta("mobile_full_canvas_overlay"):
			_fit_mobile_overlay(child)
	if mobile_hud and _presentation_dimmed and not is_instance_valid(_presentation_background): _create_mobile_background()
	if is_instance_valid(_presentation_background):
		_presentation_background.visible = mobile_hud
		_presentation_background.position = Vector2.ZERO
		_presentation_background.size = _presentation_canvas
	if not mobile_hud and _presentation_dimmed and not is_instance_valid(native_background):
		var backdrop: Control = FrontEnd.new()
		backdrop.screen_id = screen
		_content.add_child(backdrop)
		_content.move_child(backdrop,0)

func _restore_run_overlay_reference() -> void:
	if is_instance_valid(_run_overlay_shade): _run_overlay_shade.visible=false
	for child: Node in _content.get_children():
		if not child is Control or not child.has_meta("run_overlay_transformed"): continue
		var reference: Rect2=child.get_meta("frontend_reference")
		child.position=reference.position
		child.size=reference.size
		child.scale=Vector2.ONE
		if child is Label or child is BaseButton: child.add_theme_font_size_override("font_size",int(child.get_meta("frontend_font",10)))
	for entry: Dictionary in _card_animations:
		if is_instance_valid(entry.card):
			entry.position=entry.card.position
			entry.card.position=entry.position+Vector2(0,-2 if entry.card.has_focus() else 0)
	_acquisition_home_y=83.0

func _reflow_run_overlay() -> void:
	_frontend_layout=FrontendLayout.run_overlay(_presentation_canvas,screen,_presentation_safe)
	_content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_content.position=Vector2.ZERO
	_content.scale=Vector2.ONE
	_content.size=_presentation_canvas
	var regions: Dictionary=_frontend_layout.regions
	var text_scale: float=float(_frontend_layout.text_scale)
	if _presentation_dimmed:
		if not is_instance_valid(_run_overlay_shade):
			_run_overlay_shade=ColorRect.new()
			_run_overlay_shade.name="RunOverlayShade"
			_run_overlay_shade.color=Color(INK.r,INK.g,INK.b,.80)
			_run_overlay_shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
			_content.add_child(_run_overlay_shade)
			_content.move_child(_run_overlay_shade,0)
		_run_overlay_shade.visible=true
		_run_overlay_shade.size=_presentation_canvas
	var cards: Array[Control]=[]
	for child: Node in _content.get_children():
		if child is Button and str(child.get_meta("intent","")) in ["choose_power","choose_mutation"]: cards.append(child)
	var gap: float=float(_frontend_layout.gap)
	var choices: Rect2=regions.choices
	var note_height: float=28 if not mobile_hud else 20
	var card_area: Rect2=Rect2(choices.position,Vector2(choices.size.x,maxf(1,choices.size.y-note_height)))
	var cell_width: float=(card_area.size.x-gap*maxi(0,cards.size()-1))/maxi(1,cards.size())
	for index: int in range(cards.size()):
		var card: Control=cards[index]
		var native: Rect2=_frontend_reference(card)
		var destination: Rect2=Rect2(card_area.position+Vector2(index*(cell_width+gap),0),Vector2(cell_width,card_area.size.y))
		var scalar: float=minf(destination.size.x/native.size.x,destination.size.y/native.size.y)
		card.position=destination.position+(destination.size-native.size*scalar)*.5
		card.size=native.size
		card.scale=Vector2.ONE*scalar
		card.set_meta("run_overlay_transformed",true)
	for child: Node in _content.get_children():
		if not child is Control or child==_run_overlay_shade or child in cards: continue
		if child.get_script()==FrontEnd:
			child.visible=false
			continue
		var reference: Rect2=_frontend_reference(child)
		var destination: Rect2=reference
		if reference.size.x>=639 and reference.size.y>=359:
			destination=Rect2(Vector2.ZERO,_presentation_canvas)
		elif screen=="level_up":
			var band: Rect2=regions.banner
			if child is Label:
				destination=Rect2(_frontend_layout.frame_rect.position.x,band.position.y+band.size.y*(.12 if reference.position.y<180 else .65),_frontend_layout.frame_rect.size.x,band.size.y*(.48 if reference.position.y<180 else .24))
			elif reference.size.y<=2: destination=Rect2(0,band.position.y-2 if reference.position.y<180 else band.end.y,_presentation_canvas.x,2)
			else: destination=band
		elif screen=="acquisition":
			destination=FrontendLayout.map_rect(reference,Rect2(104,67,432,226),regions.acquisition)
			if child==_acquisition_icon:
				var edge: float=minf(destination.size.x,destination.size.y)
				destination=Rect2(destination.position+(destination.size-Vector2.ONE*edge)*.5,Vector2.ONE*edge)
		elif child==_ability_inspector:
			destination=regions.inspector
		elif child==_reroll_control:
			destination=Rect2(regions.footer.end.x-minf(360,regions.footer.size.x*.29),regions.footer.position.y,minf(360,regions.footer.size.x*.29),regions.footer.size.y)
		elif reference.position.y>=309:
			destination=Rect2(regions.footer.position,Vector2(regions.footer.size.x*(.67 if is_instance_valid(_reroll_control) else 1.0),regions.footer.size.y))
		elif reference.position.y>=290:
			destination=Rect2(choices.position.x,choices.end.y-note_height,choices.size.x,note_height)
		elif reference.position.y<60:
			destination=Rect2(regions.header.position+Vector2(0,0 if reference.position.y<30 else regions.header.size.y*.60),Vector2(regions.header.size.x,regions.header.size.y*(.55 if reference.position.y<30 else .35)))
		else:
			destination=Rect2(choices.position.x,regions.header.end.y+2,choices.size.x,18)
		_frontend_fit_control(child,destination,text_scale)
		child.set_meta("run_overlay_transformed",true)
	if is_instance_valid(_acquisition_icon): _acquisition_home_y=_acquisition_icon.position.y
	for entry: Dictionary in _card_animations:
		if is_instance_valid(entry.card):
			entry.position=entry.card.position
			entry.card.position=entry.position+Vector2(0,-2 if entry.card.has_focus() else 0)
	_frontend_layout_revision+=1

func _schedule_frontend_reflow(_node: Node = null) -> void:
	if presentation_mode!="frontend" or _frontend_reflow_pending: return
	_frontend_reflow_pending=true
	call_deferred("_finish_frontend_reflow")

func _finish_frontend_reflow() -> void:
	if not _frontend_reflow_pending: return
	_frontend_reflow_pending=false
	if presentation_mode=="frontend" and is_instance_valid(_content): _reflow_frontend()

func _frontend_reference(node: Control) -> Rect2:
	if not node.has_meta("frontend_reference"):
		var area: Rect2=Rect2(node.position,node.size)
		for entry: Dictionary in _card_animations:
			if entry.card==node: area.position=entry.position
		node.set_meta("frontend_reference",area)
		node.set_meta("frontend_font",node.get_theme_font_size("font_size"))
	return node.get_meta("frontend_reference")

func _frontend_component(node: Control) -> bool:
	return node is Preview or node.get_script() in [ShopMerchant,PacketView,CreditTransfer,AbilityInspection]

func _frontend_fit_control(node: Control, destination: Rect2, text_scale: float) -> void:
	var reference: Rect2=_frontend_reference(node)
	if _frontend_component(node):
		var scalar: float=minf(destination.size.x/maxf(1,reference.size.x),destination.size.y/maxf(1,reference.size.y))
		node.position=destination.position+(destination.size-reference.size*scalar)*.5
		node.size=reference.size
		node.scale=Vector2.ONE*scalar
		return
	node.position=destination.position
	node.size=destination.size
	node.scale=Vector2.ONE
	if node is Label or node is BaseButton:
		var native_font: int=int(node.get_meta("frontend_font",10))
		var desired: int=maxi(10,roundi(native_font*text_scale))
		if not mobile_hud and not bool(_frontend_layout.get("compact",false)): desired=maxi(20,desired)
		var face: Font=node.get_theme_font("font")
		if node is Label:
			while desired>10:
				var measured: Vector2=face.get_multiline_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,destination.size.x if node.autowrap_mode!=TextServer.AUTOWRAP_OFF else -1,desired)
				if measured.x<=destination.size.x and measured.y<=destination.size.y: break
				desired-=1
		elif node is BaseButton:
			while desired>10 and (face.get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,desired).x>destination.size.x-12 or face.get_height(desired)>destination.size.y-8): desired-=1
		node.add_theme_font_size_override("font_size",desired)
	if node is TextureRect: node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var scale: Vector2=destination.size/Vector2(maxf(1,reference.size.x),maxf(1,reference.size.y))
	for child: Node in node.get_children():
		if child is Control and not node is Container:
			var child_reference: Rect2=_frontend_reference(child)
			_frontend_fit_control(child,Rect2(child_reference.position*scale,child_reference.size*scale),text_scale)

func _reflow_frontend() -> void:
	if not is_instance_valid(_content) or presentation_mode!="frontend": return
	_frontend_reflow_pending=false
	if mobile_hud:
		# Android retains its accepted authored safe panel, including all touch
		# coordinate transforms. Only the separate background spans the canvas.
		var mobile: Dictionary=CombatLayout.responsive(_presentation_canvas,true,_presentation_safe)
		_content.position=mobile.menu_origin
		_content.scale=Vector2.ONE*float(mobile.menu_scale)
		_content.size=Vector2(640,360)
		_frontend_layout={"safe_rect":mobile.safe_rect,"frame_rect":_content.get_global_rect(),"regions":{"frame":_content.get_global_rect()}}
		for child: Node in _content.get_children():
			if child.get_script()==FrontEnd: child.visible=false
			if child is Control and child.has_meta("mobile_full_canvas_overlay"): _fit_mobile_overlay(child)
		if is_instance_valid(_presentation_background): _presentation_background.size=_presentation_canvas
		_frontend_layout_revision+=1
		return
	var layout_id: String=_frontend_result_kind if screen=="result" else screen
	_frontend_layout=FrontendLayout.desktop(_presentation_canvas,layout_id,_presentation_safe)
	_content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_content.position=Vector2.ZERO
	_content.scale=Vector2.ONE
	_content.size=_presentation_canvas
	var references: Dictionary=FrontendLayout.reference_regions(layout_id)
	var regions: Dictionary=_frontend_layout.regions
	var text_scale: float=float(_frontend_layout.text_scale)
	for child: Node in _content.get_children():
		if not child is Control: continue
		if child.get_script()==FrontEnd:
			child.visible=false
			continue
		var reference: Rect2=_frontend_reference(child)
		var region: String=FrontendLayout.reference_region(layout_id,reference)
		var destination: Rect2
		if child==_packet_view:
			destination=regions.get("packet",regions.body)
		elif region=="background": destination=Rect2(Vector2.ZERO,_presentation_canvas)
		else:
			var source: Rect2=references.get(region,references.body)
			var target: Rect2=regions.get(region,regions.body)
			if region=="details" and not regions.has("details"): target=regions.catalogue
			destination=FrontendLayout.map_rect(reference,source,target)
		_frontend_fit_control(child,destination,text_scale)
	for entry: Dictionary in _card_animations:
		if is_instance_valid(entry.card): entry.position=entry.card.position
	if not mobile_hud and screen in ["collection_workshop","garage"]: _reflow_frontend_catalogue()
	if not mobile_hud and screen=="settings": _reflow_frontend_settings()
	if is_instance_valid(_presentation_background):
		_presentation_background.position=Vector2.ZERO
		_presentation_background.size=_presentation_canvas
	_frontend_layout_revision+=1

func _reflow_frontend_catalogue() -> void:
	var regions: Dictionary=_frontend_layout.regions
	var area: Rect2=regions.catalogue
	var inset: float=12
	var tabs_y: float=area.position.y+inset
	var tab_width: float=(area.size.x-inset*2-12)/3
	for index: int in range(3):
		var category: String=["blade","ratchet","bit"][index]
		_catalogue_tabs[category].position=Vector2(area.position.x+inset+index*(tab_width+6),tabs_y)
		_catalogue_tabs[category].size=Vector2(tab_width,36 if not _frontend_layout.compact else 25)
	var scroll_top: float=tabs_y+(48 if not _frontend_layout.compact else 34)
	var scroll_bottom: float=area.end.y-inset if regions.has("details") else area.end.y-112
	var columns: int=maxi(2,floori((area.size.x-inset*2)/220)) if not _frontend_layout.compact else 2
	for category: String in _part_scrolls:
		var scroll: ScrollContainer=_part_scrolls[category]
		scroll.position=Vector2(area.position.x+inset,scroll_top)
		scroll.size=Vector2(floorf(area.size.x-inset*2),floorf(maxf(44,scroll_bottom-scroll_top)))
		var grid: GridContainer=scroll.get_child(0)
		grid.columns=columns
		grid.add_theme_constant_override("h_separation",8)
		grid.add_theme_constant_override("v_separation",10)
		var cell: Vector2=Vector2(floorf((scroll.size.x-16-(columns-1)*8)/columns),44 if _frontend_layout.compact else 88)
		for control: Button in _part_buttons[category].values():
			control.custom_minimum_size=cell
			_frontend_fit_control(control,Rect2(control.position,cell),float(_frontend_layout.text_scale))
	var detail: Rect2=regions.get("details",Rect2(area.position.x+inset,area.end.y-106,area.size.x-inset*2,100))
	var metadata_height: float=minf(120,detail.size.y*.30) if regions.has("details") else 24
	_frontend_fit_control(_catalogue_metadata,Rect2(detail.position+Vector2(10,10),Vector2(detail.size.x-20,metadata_height)),float(_frontend_layout.text_scale))
	_frontend_fit_control(_catalogue_description,Rect2(detail.position+Vector2(10,metadata_height+22),Vector2(detail.size.x-20,detail.size.y-metadata_height-32)),float(_frontend_layout.text_scale))
	var focused: Control=get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_catalogue_navigation(focused)

func _reflow_frontend_settings() -> void:
	var regions: Dictionary=_frontend_layout.regions
	var compact: bool=bool(_frontend_layout.compact)
	var names: Array[String]=["controls_panel","controls_title","controls_copy"]
	for key: String in names:
		if _frontend_settings_nodes.has(key): _frontend_settings_nodes[key].visible=not compact
	if compact: return
	var text_scale: float=float(_frontend_layout.text_scale)
	var font: int=maxi(20,roundi(10*text_scale))
	var audio: Rect2=regions.audio
	var comfort: Rect2=regions.comfort
	var controls: Rect2=regions.controls
	var padding: float=18
	var section_font: int=mini(30,FrontEnd.font_size(roundi(20*text_scale)))
	for key: String in ["audio","comfort","controls"]:
		var area: Rect2=regions[key]
		_frontend_fit_control(_frontend_settings_nodes[key+"_panel"],area,text_scale)
		_frontend_fit_control(_frontend_settings_nodes[key+"_title"],Rect2(area.position+Vector2(padding,16),Vector2(area.size.x-padding*2,32)),text_scale)
		_frontend_settings_nodes[key+"_title"].add_theme_font_size_override("font_size",section_font)
	var row: float=minf(106,(audio.size.y-118)/3)
	for index: int in range(3):
		var key: String=["volume","music_volume","sfx_volume"][index]
		var origin: Vector2=audio.position+Vector2(padding,62+index*row)
		_frontend_fit_control(_frontend_settings_nodes[key+"_label"],Rect2(origin,Vector2(audio.size.x-padding*2-74,26)),text_scale)
		_frontend_fit_control(_frontend_settings_nodes[key+"_value"],Rect2(origin+Vector2(audio.size.x-padding*2-74,0),Vector2(74,26)),text_scale)
		var slider: HSlider=_frontend_settings_nodes[key+"_slider"]
		slider.position=origin+Vector2(0,34)
		slider.size=Vector2(audio.size.x-padding*2,24)
		slider.get_node("FocusOutline").position=Vector2(-3,-3)
		slider.get_node("FocusOutline").size=slider.size+Vector2(6,6)
	var mute_y: float=audio.end.y-52
	_frontend_fit_control(_frontend_settings_nodes.muted_label,Rect2(audio.position.x+padding,mute_y,audio.size.x-padding*2-94,32),text_scale)
	_frontend_fit_control(_frontend_settings_nodes.muted_button,Rect2(audio.end.x-padding-84,mute_y,84,32),text_scale)
	var comfort_row: float=minf(84,(comfort.size.y-66)/4)
	for index: int in range(4):
		var key: String=["screen_shake","reduced_flashing","top_status_bars","impact_numbers"][index]
		var y: float=comfort.position.y+58+index*comfort_row
		_frontend_fit_control(_frontend_settings_nodes[key+"_label"],Rect2(comfort.position.x+padding,y,comfort.size.x-padding*2-94,32),text_scale)
		_frontend_fit_control(_frontend_settings_nodes[key+"_button"],Rect2(comfort.end.x-padding-84,y,84,32),text_scale)
	var controller: Button=_frontend_settings_nodes.controller_button
	_frontend_fit_control(controller,Rect2(controls.position+Vector2(padding,56),Vector2(controls.size.x-padding*2,36)),text_scale)
	var copy: Label=_frontend_settings_nodes.controls_copy
	copy.vertical_alignment=VERTICAL_ALIGNMENT_TOP
	copy.text="STEER / ARROWS OR LEFT STICK\nBURST / SPACE OR FACE BUTTON\nBRAKE / SHIFT OR SHOULDER\nPAUSE / ESC OR MENU" if _frontend_layout.large else "STEER / ARROWS OR LEFT STICK\nBURST / SPACE  BRAKE / SHIFT\nPAUSE / ESC OR MENU"
	_frontend_fit_control(copy,Rect2(controls.position+Vector2(padding,104),Vector2(controls.size.x-padding*2,maxf(30,controls.size.y-(158 if _frontend_layout.large else 144)))),text_scale)
	var note: Label=_frontend_settings_nodes.window_note
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_frontend_fit_control(note,Rect2(controls.position+Vector2(padding,controls.size.y-(48 if _frontend_layout.large else 28)),Vector2(controls.size.x-padding*2,34 if _frontend_layout.large else 24)),text_scale)
	# The same existing controls move between panes; their focus owner and values
	# survive a resize. Refresh explicit links using the currently focused node.
	var focused: Control=get_viewport().gui_get_focus_owner()
	var footer: Array=[_frontend_settings_nodes.back]
	if _frontend_settings_nodes.has("save_tools"): footer.append(_frontend_settings_nodes.save_tools)
	_focus_rows([[_frontend_settings_nodes.volume_slider],[_frontend_settings_nodes.music_volume_slider],[_frontend_settings_nodes.sfx_volume_slider],[_frontend_settings_nodes.muted_button],[_frontend_settings_nodes.screen_shake_button],[_frontend_settings_nodes.reduced_flashing_button],[_frontend_settings_nodes.top_status_bars_button],[_frontend_settings_nodes.impact_numbers_button],[controller],footer],focused)

func presentation_snapshot() -> Dictionary:
	_finish_frontend_reflow()
	var panels: Array=[]
	if is_instance_valid(_content):
		for node: Node in _content.get_children():
			if node is Panel and node.is_visible_in_tree(): panels.append({"name":str(node.name),"rect":node.get_global_rect()})
	var focused: Control=get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return {"screen_id":screen,"presentation_class":presentation_mode,"presentation_policy":"run_overlay" if not mobile_hud and FrontendLayout.uses_run_overlay(screen) else presentation_mode,"canvas_size":_presentation_canvas,
		"safe_rect":_frontend_layout.get("safe_rect",_presentation_safe),"root_rect":_content.get_global_rect() if is_instance_valid(_content) else Rect2(),
		"root_scale":_content.scale if is_instance_valid(_content) else Vector2.ONE,
		"frame_rect":_frontend_layout.get("frame_rect",_content.get_global_rect() if is_instance_valid(_content) else Rect2()),
		"regions":_frontend_layout.get("regions",{}),"panels":panels,"focus":str(focused.name) if is_instance_valid(focused) else "",
		"content_instance_id":_content.get_instance_id() if is_instance_valid(_content) else 0,"layout_revision":_frontend_layout_revision}

func _place_hud_power_slots(ids: Array) -> void:
	if _hud.is_empty(): return
	var layout: Dictionary = _hud_layout
	var wide: bool = mobile_hud and bool(layout.get("mobile_wide",false))
	var power_area: Rect2 = layout.get("regions",{}).get("powers",Rect2(0,float(layout.get("powers_y",424)),640,22))
	var columns: int = maxi(1,int(layout.get("powers_columns",1)))
	var safe: Rect2 = layout.get("safe_rect",Rect2(Vector2.ZERO,_presentation_canvas))
	var centre: float = safe.get_center().x if mobile_hud else _presentation_canvas.x*0.5
	for index: int in range(Powers.ACTIVE_IDS.size()):
		var slot: Vector2 = Vector2(centre-minf(float(ids.size()),float(Powers.ACTIVE_IDS.size()))*16.0+index*32.0,float(layout.get("powers_y",424)))
		if wide: slot = power_area.position+Vector2((index%columns)*32,(index/columns)*24)
		_hud["power_panel_%d" % index].position = slot
		_hud["power_%d" % index].position = slot+Vector2(2,3)
		_hud["power_rank_%d" % index].position = slot+Vector2(18,5)

func _fit_hud(key: String, rect: Rect2) -> void:
	if not _hud.has(key): return
	var control: Control = _hud[key]
	control.position = rect.position
	control.size = rect.size

func _reflow_hud() -> void:
	if screen != "hud" or _hud.is_empty(): return
	var layout: Dictionary = CombatLayout.responsive(_presentation_canvas,mobile_hud,_presentation_safe)
	_hud_layout = layout
	if mobile_hud:
		_reflow_mobile_hud(layout)
		return
	var extent: Vector2 = layout.canvas_size
	_content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_content.position = Vector2.ZERO
	_content.scale = Vector2.ONE
	_content.size = extent
	var width: float = layout.top_width
	var right_x: float = layout.right_x
	_fit_hud("player_panel",layout.regions.player_reserve)
	_fit_hud("enemy_panel",layout.regions.pressure)
	for key: String in ["player_name","player_rpm","player_bar","rpm_overflow"]:
		var node: Control = _hud[key]
		node.position.x = 96
		node.size.x = width-20.0
	for key: String in ["enemy_name","enemy_rpm","enemy_bar","swarm_objective"]:
		var node: Control = _hud[key]
		node.position.x = right_x+10.0
		node.size.x = width-20.0
	_fit_hud("clock_panel",Rect2(extent.x*0.5-56.0,6,112,48))
	_fit_hud("time",Rect2(extent.x*0.5-54.0,6,108,25))
	_fit_hud("round",Rect2(extent.x*0.5-58.0,31,116,11))
	_fit_hud("director_callout",Rect2(extent.x*0.5-64.0,43,128,11))
	_fit_hud("announcement",Rect2(extent.x*0.5-175.0,layout.arena_rect.position.y+layout.arena_rect.size.y*0.36,350,64))
	_fit_hud("rerolls",Rect2(6,extent.y-55.0,74,24))
	_fit_hud("power_note",Rect2(86,layout.powers_y,136,18))
	for index: int in range(Powers.ACTIVE_IDS.size()):
		for prefix: String in ["power_panel_","power_","power_rank_"]:
			var node: Control = _hud[prefix+str(index)]
			var offset_y: float = 3.0 if prefix == "power_" else (5.0 if prefix == "power_rank_" else 0.0)
			node.position.y = layout.powers_y+offset_y
	_fit_hud("burst_panel",layout.regions.burst)
	_fit_hud("burst",Rect2(97,layout.bottom_y+2.0,layout.burst_width-21.0,16))
	_fit_hud("burst_bar",Rect2(97,layout.bottom_y+22.0,layout.burst_width-21.0,3))
	_fit_hud("controls",Rect2(layout.progress_x,layout.bottom_y+2.0,layout.progress_width,18))
	_fit_hud("xp_panel",layout.regions.progress)
	_fit_hud("xp_hit",layout.regions.progress)
	_fit_hud("xp_label",Rect2(layout.progress_x+10.0,layout.bottom_y+2.0,layout.progress_width-158.0,15))
	_fit_hud("xp_detail",Rect2(extent.x-226.0,layout.bottom_y+2.0,130,15))
	_fit_hud("xp_bar",Rect2(layout.progress_x+10.0,layout.bottom_y+22.0,layout.progress_width-20.0,4))
	_fit_hud("impact_confirmation",Rect2(6,layout.state_left.y+172.0,layout.state_width,68))
	_hud.state_meters.set_layout(layout)

func _reflow_mobile_hud(presentation: Dictionary) -> void:
	var layout: Dictionary = presentation.get("hud_layout",presentation)
	_hud_layout = layout
	var regions: Dictionary = layout.regions
	var safe: Rect2 = layout.get("safe_rect",Rect2(Vector2.ZERO,layout.canvas_size))
	var wide: bool = bool(layout.get("mobile_wide",false))
	_content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_content.position = presentation.get("hud_origin",Vector2.ZERO)
	_content.scale = Vector2.ONE*float(presentation.get("hud_scale",1.0))
	_content.size = layout.canvas_size
	_content.clip_contents = true
	for pair: Array in [["player_panel","player_reserve"],["enemy_panel","pressure"],["burst_panel","burst"],["xp_panel","progress"],["xp_hit","progress"]]:
		_fit_hud(pair[0],regions[pair[1]])
	for column: Array in [["player","player_reserve"],["enemy","pressure"]]:
		var area: Rect2 = regions[column[1]]
		var inner: float = maxf(1.0,area.size.x-20.0)
		_fit_hud(column[0]+"_name",Rect2(area.position+Vector2(10,2),Vector2(inner,15)))
		_fit_hud(column[0]+"_bar",Rect2(area.position+Vector2(10,20),Vector2(inner,7)))
		_fit_hud(column[0]+"_rpm",Rect2(area.position+Vector2(10,30),Vector2(inner,14)))
	var player: Rect2 = regions.player_reserve
	_fit_hud("rpm_overflow",Rect2(player.position+Vector2(10,20),Vector2(maxf(1.0,player.size.x-20.0),3)))
	var pressure: Rect2 = regions.pressure
	_fit_hud("swarm_objective",Rect2(pressure.position+Vector2(10,18),Vector2(maxf(1.0,pressure.size.x-20.0),12)))
	_fit_hud("pressure_counts",Rect2(Vector2(pressure.position.x,pressure.end.y+2.0),Vector2(pressure.size.x,10)))
	var clock: Rect2 = regions.clock
	var clock_width: float = minf(112.0,clock.size.x)
	_fit_hud("clock_panel",Rect2(Vector2(clock.get_center().x-clock_width*0.5,clock.position.y),Vector2(clock_width,48)))
	_fit_hud("time",Rect2(Vector2(clock.get_center().x-minf(108.0,clock.size.x)*0.5,clock.position.y),Vector2(minf(108.0,clock.size.x),25)))
	_fit_hud("round",Rect2(Vector2(clock.get_center().x-minf(116.0,clock.size.x)*0.5,clock.position.y+25),Vector2(minf(116.0,clock.size.x),11)))
	_fit_hud("director_callout",Rect2(Vector2(clock.get_center().x-clock.size.x*0.5,clock.position.y+37),Vector2(clock.size.x,11)))
	_fit_hud("pause_button",regions.get("pause",Rect2(safe.position+Vector2(6,8),Vector2(68,24))))
	_fit_hud("announcement",regions.get("announcement",Rect2(layout.arena_rect.get_center()-Vector2(175,32),Vector2(350,64))))
	_fit_hud("rerolls",regions.get("rerolls",Rect2(safe.position+Vector2(6,safe.size.y-55),Vector2(74,24))))
	_fit_hud("power_note",regions.get("power_note",Rect2(safe.position+Vector2(86,float(layout.powers_y)-safe.position.y),Vector2(136,18))))
	_place_hud_power_slots(_inspection_owned_state.get("ids",[]))
	var burst: Rect2 = regions.burst
	_fit_hud("burst",Rect2(burst.position+Vector2(11,2),Vector2(maxf(1.0,burst.size.x-21.0),16)))
	_fit_hud("burst_bar",Rect2(burst.position+Vector2(11,burst.size.y-6.0),Vector2(maxf(1.0,burst.size.x-21.0),3)))
	var progress: Rect2 = regions.progress
	if wide:
		_fit_hud("xp_label",Rect2(progress.position+Vector2(6,1),Vector2(maxf(1.0,progress.size.x-12.0),12)))
		_fit_hud("xp_detail",Rect2(progress.position+Vector2(6,13),Vector2(maxf(1.0,progress.size.x-12.0),10)))
	else:
		_fit_hud("xp_label",Rect2(progress.position+Vector2(10,2),Vector2(maxf(1.0,progress.size.x-158.0),15)))
		_fit_hud("xp_detail",Rect2(Vector2(progress.end.x-140.0,progress.position.y+2),Vector2(130,15)))
	_fit_hud("xp_bar",Rect2(progress.position+Vector2(10,progress.size.y-6.0),Vector2(maxf(1.0,progress.size.x-20.0),4)))
	_hud.controls.visible = false
	_fit_hud("impact_confirmation",regions.get("impact",Rect2(layout.state_left+Vector2(0,172),Vector2(layout.state_width,68))))
	_hud.state_meters.set_layout(layout)
	if is_instance_valid(_ability_inspector):
		_ability_inspector.position = Vector2(clampf(layout.arena_rect.end.x-194.0,safe.position.x,safe.end.x-188.0),clampf(safe.get_center().y-121.0,safe.position.y,safe.end.y-242.0))


func combat_layout_snapshot() -> Dictionary:
	var result: Dictionary = CombatLayout.snapshot(mobile_hud)
	var layout: Dictionary = CombatLayout.responsive(_presentation_canvas,mobile_hud,_presentation_safe)
	result["regions"] = layout.regions
	result["play_region"] = layout.arena_rect
	result["canvas_size"] = layout.canvas_size
	result["arena_scale"] = layout.arena_scale
	result["arena_origin"] = layout.arena_rect.position
	result["safe_rect"] = layout.get("safe_rect",Rect2(Vector2.ZERO,layout.canvas_size))
	result["menu_origin"] = layout.menu_origin
	result["menu_scale"] = layout.get("menu_scale",1.0)
	result["mobile_wide"] = layout.get("mobile_wide",false)
	if mobile_hud:
		result["native_view"] = [layout.canvas_size.x,layout.canvas_size.y]
		result["mobile_action_rail"] = layout.burst_rect.merge(layout.brake_rect)
		result["left_edge"] = Rect2(0,layout.arena_rect.position.y,layout.arena_rect.position.x,layout.arena_rect.size.y)
		result["right_edge"] = Rect2(layout.arena_rect.end.x,layout.arena_rect.position.y,layout.canvas_size.x-layout.arena_rect.end.x,layout.arena_rect.size.y)
	result["duplicate_anchor_label"] = _hud.has("anchor")
	result["temporary_announcements_live_combat"] = false
	result["hud_overlaps_arena"] = false
	return result

func _inspect_hud_power(index: int) -> void:
	if screen != "hud" or not is_instance_valid(_ability_inspector): return
	var icon: Control = _hud.get("power_%d" % index)
	if not is_instance_valid(icon) or not icon.visible: return
	_ability_inspector.inspect(str(icon.get_meta("power_id", "")), int(icon.get_meta("current_rank", 1)), str(icon.get_meta("current_mutation", "")))

func _animate_rpm_meter() -> void:
	if screen != "hud" or not _hud.has("player_bar"): return
	var pulse: float = 0.5 if reduced_flashing else 0.5 + sin(_menu_clock * (8.0 + _rpm_heat * 8.0)) * 0.5
	var color: Color = Color("ff632e").lerp(Color("ffb44b"), pulse) if _rpm_overdrive else BLUE
	var fill: StyleBoxFlat = _hud["rpm_overflow"].get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = color
	if _rpm_overdrive: _hud["player_rpm"].modulate = color
