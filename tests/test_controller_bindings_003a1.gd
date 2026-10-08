extends SceneTree
## Isolated logical mapping contracts and physical-observer event plumbing.
## No Main or player files are opened. Injected events are explicitly logical.
const Bindings = preload("res://scripts/controller_bindings.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const Probe = preload("res://tests/controller_physical_probe_003a1.gd")
var checks: int = 0
var failures: int = 0
var received: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	Input.use_accumulated_input = false
	var observer := Probe.NativeObserver.new()
	root.add_child(observer)
	observer.native_input.connect(func(event: InputEvent) -> void:
		if event is InputEventJoypadButton: received.append({"button":event.button_index,"pressed":event.pressed}))
	await process_frame
	for profile: String in ["xbox","nintendo","playstation","auto"]:
		Bindings.configure(profile)
		for device: int in [0,3,15]:
			var expected: String = Bindings.profile(device)
			var confirm: JoyButton = Bindings.confirm_button(expected)
			var back: JoyButton = Bindings.back_button(expected)
			check(confirm != back,"Each physical-layout intent has a separate face button")
			for row: Array in [[confirm,"ui_accept","ui_cancel"],[back,"ui_cancel","ui_accept"]]:
				var event := InputEventJoypadButton.new(); event.device = device; event.button_index = row[0]; event.pressed = true
				check(event.is_action(row[1]) and not event.is_action(row[2]),"Per-device menu actions agree with the selected layout")
				Input.parse_input_event(event)
				await process_frame
				check(Input.is_action_pressed(row[1]) and not Input.is_action_pressed(row[2]),"Input singleton held state follows the actual mapping")
				var release: InputEventJoypadButton = event.duplicate()
				release.pressed = false; Input.parse_input_event(release)
				await process_frame
				check(not Input.is_action_pressed(row[1]),"Actual release removes its held menu action")
		check(InputMap.action_get_events("ui_accept").any(func(event: InputEvent) -> bool: return event is InputEventKey and event.keycode == KEY_ENTER),"Controller remap preserves keyboard Enter")
		var burst := InputEventJoypadButton.new(); burst.device = 3; burst.button_index = JOY_BUTTON_A
		check(burst.is_action("burst"),"Controller menu type preserves the established south-button Burst")
	await process_frame
	check(received.size() == 48,"Physical observer's actual Node receives pressed/released joypad dispatch; SceneTree itself never owns _input")
	check(FrontEnd.controller_profile_for("XInput Controller",{"raw_name":"Xbox 360 Controller","vendor_id":"1118","product_id":"654"}) == "xbox","A Nintendo-layout XInput adapter cannot be identified from Xbox metadata")
	var wrapped_info: Dictionary = {"raw_name":"Xbox 360 Controller","vendor_id":"1118","product_id":"654"}
	var wrapped_guid: String = "0300fa675e0400008e02000010017801"
	check(FrontEnd.controller_profile_for("XInput Controller",wrapped_info,wrapped_guid) == "nintendo","The previously human-verified wrapped Switch identity is Nintendo in AUTO")
	check(FrontEnd.controller_profile_for("Xbox 360 Controller",wrapped_info,wrapped_guid.to_upper()) == "nintendo","Verified identity comparison is case independent")
	for unknown_guid: String in ["", "0300fa675e0400008e02000010017800", "0300fa675e0400008e02000010017801-extra", "030000005e0400008e02000000000000"]:
		check(FrontEnd.controller_profile_for("XInput Controller",wrapped_info,unknown_guid) == "xbox","Other or missing XInput identities preserve Xbox actions")
	check(Bindings.confirm_button(FrontEnd.controller_profile_for("XInput Controller",wrapped_info,wrapped_guid)) == JOY_BUTTON_B,"AUTO wrapped Switch confirms with printed east A")
	check(Bindings.back_button(FrontEnd.controller_profile_for("XInput Controller",wrapped_info,wrapped_guid)) == JOY_BUTTON_A,"AUTO wrapped Switch backs with printed south B")
	Bindings.configure("nintendo")
	check(Bindings.profile(0) == "nintendo","Explicit controller type resolves an adapter's ambiguous printed layout")
	check(FrontEnd.prompt("nintendo","confirm") == "A" and FrontEnd.glyph("nintendo","confirm").region == Rect2(32,0,16,16),"Nintendo A action, letter prompt, and authored glyph agree")
	check(FrontEnd.prompt("nintendo","back") == "B" and FrontEnd.glyph("nintendo","back").region == Rect2(48,0,16,16),"Nintendo B action, letter prompt, and authored glyph agree")
	Bindings.configure("auto")
	observer.queue_free(); await process_frame
	print("CONTROLLER_BINDINGS_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
