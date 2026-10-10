extends SceneTree
## Raw native button inventory only: no synthetic events, collection or preferences.
const Front = preload("res://scripts/front_end.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
class PhysicalObserver extends Control:
	var report: String
	var label: Label
	var footer: Label
	var rows: Array=[]
	var devices: Array=[]
	var finished: bool=false
	var saw_press: bool=false
	func save(status: String) -> void:
		var file:=FileAccess.open(report,FileAccess.WRITE)
		file.store_string(JSON.stringify({"status":status,"devices":devices,"raw_button_events":rows,"right_shoulder_pressed":saw_press,"right_shoulder_released":finished,"collection_opened":false,"preferences_opened":false,"synthetic_events":0,"scope":"Actual native input observer; human must press the printed right shoulder. No input injection or player-profile access."},"\t"))
	func _input(event: InputEvent) -> void:
		if not event is InputEventJoypadButton: return
		rows.append({"device":event.device,"button_index":event.button_index,"pressed":event.pressed,"milliseconds":Time.get_ticks_msec(),"profile":Bindings.profile(event.device)})
		if event.button_index==JOY_BUTTON_RIGHT_SHOULDER:
			if event.pressed:
				saw_press=true
				label.text="RIGHT SHOULDER RECOGNISED"
				footer.text=Front.prompt(Bindings.profile(event.device),"reroll")+" / RELEASE TO FINISH"
			elif saw_press:
				finished=true
				footer.text=Front.prompt(Bindings.profile(event.device),"reroll")+" / REROLL VERIFIED"
				save("complete")
				get_tree().create_timer(1.5).timeout.connect(func() -> void: get_tree().quit())
		if not finished: save("pressed" if saw_press else "waiting")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var report: String=""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report=argument.trim_prefix("--report=")
	if not report.is_absolute_path() or not (report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/") or report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/")) or FileAccess.file_exists(report): quit(2); return
	root.size=Vector2i(800,480); root.content_scale_size=Vector2i(800,480)
	DisplayServer.window_set_title("Spinning Metal — Right Shoulder Check")
	var observer:=PhysicalObserver.new(); observer.report=report; observer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(observer)
	for device: int in Input.get_connected_joypads():
		observer.devices.append({"device":device,"name":Input.get_joy_name(device),"guid":Input.get_joy_guid(device),"profile":Bindings.profile(device),"expected_button":JOY_BUTTON_RIGHT_SHOULDER,"expected_prompt":Front.prompt(Bindings.profile(device),"reroll")})
	var background:=ColorRect.new(); background.color=Color("14232e"); background.size=Vector2(800,480); observer.add_child(background)
	var title:=Label.new(); title.text="REROLL / RIGHT SHOULDER CHECK"; title.position=Vector2(70,70); title.size=Vector2(660,40); title.add_theme_font_size_override("font_size",23); observer.add_child(title)
	observer.label=Label.new(); observer.label.text="PRESS AND RELEASE THE PRINTED R BUTTON"; observer.label.position=Vector2(70,180); observer.label.size=Vector2(660,60); observer.label.add_theme_font_size_override("font_size",20); observer.add_child(observer.label)
	observer.footer=Label.new(); observer.footer.text="Select this window first. Your player data is untouched."; observer.footer.position=Vector2(70,300); observer.footer.size=Vector2(660,60); observer.footer.add_theme_font_size_override("font_size",17); observer.add_child(observer.footer)
	observer.theme=Front.make_theme(); observer.save("waiting")
	print("PHYSICAL_BUMPER_READY ",report," devices=",observer.devices)
