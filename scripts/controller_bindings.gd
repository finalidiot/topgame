extends RefCounted
## Godot normalises face buttons by position. Nintendo's printed A is east;
## Xbox A / PlayStation Cross are south. Bind menu intent per device, while
## leaving the established south-button combat Burst unchanged.
const FrontEnd = preload("res://scripts/front_end.gd")
static var layout: String = "auto"
static var _signature: String = ""

static func profile(device: int) -> String:
	return FrontEnd.controller_profile(device) if layout == "auto" else layout

static func confirm_button(profile_id: String) -> JoyButton:
	return JOY_BUTTON_B if profile_id == "nintendo" else JOY_BUTTON_A

static func back_button(profile_id: String) -> JoyButton:
	return JOY_BUTTON_A if profile_id == "nintendo" else JOY_BUTTON_B

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
