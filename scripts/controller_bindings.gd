extends RefCounted
## Godot normalises face buttons by position. Nintendo's printed A is east;
## Xbox A / PlayStation Cross are south. Bind menu intent per device, while
## leaving the established south-button combat Burst unchanged.
const FrontEnd = preload("res://scripts/front_end.gd")
static var layout: String = "auto"
static var _signature: String = ""

## -2 means irrelevant input; -1 means accepted keyboard, mouse or touch intent.
## Neutral releases/drift never steal control from another device.
static func control_device_for_event(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		if event.pressed and (event.is_action("ui_accept") or event.is_action("ui_cancel") or event.is_action("burst") or event.is_action("brake") or event.is_action("pause") or event.button_index in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]): return event.device
	elif event is InputEventJoypadMotion:
		if event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y] and absf(event.axis_value) >= 0.25: return event.device
		if event.axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT] and event.axis_value >= 0.35: return event.device
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			for action: String in ["move_left","move_right","move_up","move_down","burst","brake","pause","ui_accept","ui_cancel","ui_left","ui_right","ui_up","ui_down","draft_reroll"]:
				if event.is_action(action): return -1
	elif event is InputEventScreenTouch:
		if event.pressed: return -1
	elif event is InputEventScreenDrag:
		if event.relative.length_squared() > 0.0: return -1
	elif event is InputEventMouseButton:
		if event.pressed: return -1
	return -2

static func profile(device: int) -> String:
	return FrontEnd.controller_profile(device) if layout == "auto" else layout

static func confirm_button(profile_id: String) -> JoyButton:
	return JOY_BUTTON_B if profile_id == "nintendo" else JOY_BUTTON_A

static func back_button(profile_id: String) -> JoyButton:
	return JOY_BUTTON_A if profile_id == "nintendo" else JOY_BUTTON_B

static func reroll_button(_profile_id: String) -> JoyButton:
	return JOY_BUTTON_RIGHT_SHOULDER

static func configure(requested_layout: String = "auto") -> void:
	layout = requested_layout if requested_layout in ["auto", "xbox", "nintendo", "playstation"] else "auto"
	# Godot currently supports sixteen joypad slots. Include any reported slot
	# beyond that range, and retain generic defaults for unconnected slots so a
	# newly connected device has working navigation before its signal arrives.
	var devices: Array[int] = []
	for device: int in range(16): devices.append(device)
	for device: int in Input.get_connected_joypads():
		if device not in devices: devices.append(device)
	var profiles: Array = []
	for device: int in devices: profiles.append([device, profile(device)])
	var signature: String = JSON.stringify(profiles)
	if signature == _signature: return
	_signature = signature
	for action: String in ["ui_accept", "ui_cancel"]:
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton: InputMap.action_erase_event(action, event)
	for row: Array in profiles:
		for action: String in ["ui_accept", "ui_cancel"]:
			var event := InputEventJoypadButton.new()
			event.device = int(row[0])
			event.button_index = confirm_button(str(row[1])) if action == "ui_accept" else back_button(str(row[1]))
			InputMap.action_add_event(action, event)
