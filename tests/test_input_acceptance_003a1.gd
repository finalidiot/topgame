extends SceneTree
## Normal Main, real GUI dispatch, real acquisition/READY/physics timers.
## Synthetic Godot events validate logical input; no physical-hardware claim.
## Only isolated ownership/wallet and one earned-XP event are labelled fixtures.
const Main = preload("res://scripts/main.gd")
const Collection = preload("res://scripts/collection_save.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const PAD: int = 3
var joy_device: int = PAD
var game: Node2D
var report_path: String = ""
var profiles_path: String = ""
var images_path: String = ""
var kind: String = "all"
var input_kind: String = "keyboard"
var checks: int = 0
var failures: int = 0
var rows: Array = []
var events: Array = []
var outcomes: Array = []
var caption: Label
var start_frame: int = 0
var phase: String = ""
var capture_group: String = "flow"

func _initialize() -> void: call_deferred("run")
func frame() -> int: return Engine.get_process_frames() - start_frame
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("INPUT_ACCEPTANCE_FAILURE ", input_kind, " ", message)
func wait_frames(count: int) -> void:
	for index: int in range(count):
		await process_frame
		if is_instance_valid(game) and frame() % 6 == 0: sample("tick")
func sample(label: String) -> void:
	rows.append({"frame":frame(),"group":capture_group,"input":input_kind,"phase":phase,"label":label,
		"screen":game.screen,"menu":game.menus.screen,"suspended":game._application_suspended,
		"backgrounded":game._application_backgrounded,"acquisition_remaining":game._acquisition_remaining,
		"battle_phase":game.battle.battle_status,"reentry_remaining":game.battle._reentry_remaining,
		"elapsed":game.battle.elapsed,"paused":game.battle.paused,"accept_held":Input.is_action_pressed("ui_accept"),
		"burst_held":Input.is_action_pressed("burst"),"burst_buffer":game.battle._burst_buffer})
func stage(name: String, hold: int = 0) -> void:
	phase = name
	var mapping: String = " A=EAST / B=SOUTH" if input_kind == "nintendo" else (" CROSS=SOUTH / CIRCLE=EAST" if input_kind == "playstation" else (" A=SOUTH / B=EAST" if input_kind == "xbox" else ""))
	if is_instance_valid(caption): caption.text = "LOGICAL INPUT: " + input_kind.to_upper() + mapping + " | " + name.replace("_", " ").to_upper()
	sample(name)
	print("INPUT_ACCEPTANCE_STAGE ", input_kind, " ", name, " frame=", frame())
	if not images_path.is_empty():
		await RenderingServer.frame_post_draw
		var pixels: Image = root.get_texture().get_image()
		check(pixels.get_size() == Vector2i(800,480), "Review pixels show the native800x480 product canvas")
		var path: String = images_path.path_join(capture_group + "_" + input_kind + "_" + name + ".png")
		check(not FileAccess.file_exists(path) and pixels.save_png(path) == OK,"Preserved fresh input screenshot")
	if hold > 0: await wait_frames(hold)
func descendants(node: Node) -> Array:
	var found: Array = []
	for child: Node in node.get_children():
		found.append(child)
		found.append_array(descendants(child))
	return found
func button(intent: String) -> Button:
	for node: Node in descendants(game.menus):
		if node is Button and node.is_visible_in_tree() and not node.disabled and str(node.get_meta("intent", "")) == intent: return node
	return null
func key(code: Key, down: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = down; event.echo = echo
	Input.parse_input_event(event)
	events.append({"frame":frame(),"input":input_kind,"type":"keyboard","key":code,"pressed":down,"echo":echo,"screen":game.screen})
func joy(code: JoyButton, down: bool, device: int = -1) -> void:
	var event := InputEventJoypadButton.new()
	var actual_device: int = joy_device if device < 0 else device
	event.device = actual_device; event.button_index = code; event.pressed = down
	Input.parse_input_event(event)
	events.append({"frame":frame(),"input":input_kind,"type":"logical_joypad","device":actual_device,"button":code,"pressed":down,"screen":game.screen})
func tap_key(code: Key) -> void:
	key(code,true); await wait_frames(2); key(code,false); await wait_frames(3)
func tap_joy(code: JoyButton, device: int = -1) -> void:
	joy(code,true,device); await wait_frames(2); joy(code,false,device); await wait_frames(3)
func pointer(target: Control, touch: bool) -> void:
	check(is_instance_valid(target),"Pointer target exists")
	if not is_instance_valid(target): return
	var point: Vector2 = target.get_global_rect().get_center()
	var target_intent: String = str(target.get_meta("intent", ""))
	check(Rect2(80,60,640,360).encloses(target.get_global_rect()),"Pointer target stays inside the centred native640x360 menu")
	check(Rect2(0,0,800,480).has_point(point),"Pointer target is on the product surface")
	if not touch:
		var motion := InputEventMouseMotion.new()
		motion.position = point; motion.global_position = point
		Input.parse_input_event(motion)
		await wait_frames(2)
	for down: bool in [true,false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.index = 4; event.position = point; event.pressed = down
			Input.parse_input_event(event)
		else:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.global_position = point; event.pressed = down
			Input.parse_input_event(event)
		events.append({"frame":frame(),"input":input_kind,"type":"screen_touch" if touch else "mouse","pressed":down,"position":[point.x,point.y],"intent":target_intent,"screen":game.screen})
		await wait_frames(3)
func navigate(target: Control) -> bool:
	if input_kind in ["mouse","touch"]: return is_instance_valid(target)
	check(is_instance_valid(target),"Requested focus target exists")
	if not is_instance_valid(target): return false
	var first: Control = root.gui_get_focus_owner()
	if first == target: return true
	var paths: Dictionary = {first:[]}
	var queue: Array = [first]
	while not queue.is_empty():
		var current: Control = queue.pop_front()
		if current == null: continue
		for side: int in range(4):
			var path: NodePath = current.get_focus_neighbor(side)
			var candidate: Control = current.get_node_or_null(path) if not path.is_empty() else null
			if candidate == null or paths.has(candidate): continue
			var route: Array = paths[current].duplicate(); route.append(side)
			paths[candidate] = route; queue.append(candidate)
	check(paths.has(target),"Actual focus graph reaches " + str(target.get_meta("intent",target.name)))
	if not paths.has(target): return false
	for side: int in paths[target]:
		if input_kind == "keyboard": await tap_key([KEY_LEFT,KEY_UP,KEY_RIGHT,KEY_DOWN][side])
		else: await tap_joy([JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN][side])
	check(root.gui_get_focus_owner() == target,"Real navigation reaches target")
	return root.gui_get_focus_owner() == target
func activate(target: Control) -> void:
	if not await navigate(target): return
	if input_kind in ["mouse","touch"]: await pointer(target,input_kind == "touch")
	elif input_kind == "keyboard": await tap_key(KEY_ENTER)
	else: await tap_joy(Bindings.confirm_button(input_kind))
func intent(name: String) -> void: await activate(button(name))
func back() -> void:
	if input_kind == "touch":
		game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		events.append({"frame":frame(),"input":input_kind,"type":"android_system_back_fixture","screen":game.screen})
		await wait_frames(3)
	elif input_kind == "keyboard": await tap_key(KEY_ESCAPE)
	elif input_kind == "mouse":
		var target: Control = button("resume") if game.screen == "pause" else button("main_menu")
		await activate(target)
	else: await tap_joy(Bindings.back_button(input_kind))
func wait_for(screen_name: String, phase_name: String = "", limit: int = 340) -> bool:
	for index: int in range(limit):
		if game.screen == screen_name and (phase_name.is_empty() or game.battle.battle_status == phase_name): return true
		await wait_frames(1)
	check(false,"Timed flow reached " + screen_name + "/" + phase_name + "; actual=" + game.screen + "/" + game.battle.battle_status)
	return false
func boot(profile: String) -> void:
	if is_instance_valid(game):
		game.sounds.muted = true
		for channel: AudioStreamPlayer in game.sounds.channels: channel.stop()
		game.queue_free(); await wait_frames(3)
	for action: String in ["ui_accept","ui_cancel","burst","brake","pause"]: Input.action_release(action)
	input_kind = "nintendo" if profile == "auto" else profile
	var path: String = profiles_path.path_join(profile + ".json")
	check(not FileAccess.file_exists(path),"Every input boots a fresh isolated profile")
	var fixture := Collection.new(path)
	fixture.load_save()
	check(fixture.initialize_starter("bastion").ok,"Labelled fixture owns a real Bastion assembly")
	var state: Dictionary = fixture._data.duplicate(true)
	state.progression.credits = 500
	check(fixture._commit(state,"qa_wallet_fixture").ok,"Labelled isolated wallet fixture permits genuine packet purchase")
	var cfg := ConfigFile.new()
	# The actual AUTO-device regression starts from legacy preferences with no
	# layout key, matching the user's existing profile without opening it.
	if profile == "auto": cfg.set_value("settings","muted",true)
	else: cfg.set_value("settings","controller_layout",profile if profile in ["xbox","nintendo","playstation"] else "auto")
	check(cfg.save(path + ".preferences.cfg") == OK,"Logical controller layout fixture uses real persisted Options")
	game = Main.new(); game.collection_path = path
	root.add_child(game)
	await wait_frames(5)
	check(not game.smoke_mode and game.screen == "title_gate","Normal boot keeps real input/focus/timer lifecycle")
	game.rng.seed = 421
	await stage("title_gate",25 if kind == "mapping" else 8)
	await intent("enter_frontend")
	check(game.screen == "title","The selected input confirms Press Start")
	await stage("hub",25 if kind == "mapping" else 5)
func earn_level() -> void:
	var event: Dictionary = {"kind":"elimination","encounter_id":str(game.run_context.current_encounter().id),
		"time":game.battle.elapsed,"entity_id":90003,"combatant_type":"full_top","reason":"spin_out","player_attributed":true}
	events.append({"frame":frame(),"input":input_kind,"type":"earned_xp_fixture","event":event})
	game._progression_events([event])
	check(game.screen == "level_up" and game.battle.paused,"Labelled earned-XP event enters the production paused draft")
	await wait_for("reward")
func flow(profile: String) -> void:
	capture_group = "flow"
	await boot(profile)
	await intent("start_run")
	check(game.screen == "reward","Same input opens the actual starting draft")
	await stage("starting_draft",18)
	await intent("choose_power")
	check(game.screen == "acquisition","Selection displays the genuine tuned mechanism")
	await stage("starting_tuned",8)
	await wait_for("battle","battle")
	await stage("starting_go",18)
	await earn_level()
	await stage("earned_draft",18)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game._application_suspended,"Focus-loss fixture suspends the acquisition owner")
	var previous_elapsed: float = game.battle.elapsed
	var accepted_events: int = events.size()
	await intent("choose_power")
	check(game.screen == "acquisition" and not game._application_suspended,"Same local input selects and clears desktop focus suspension")
	await stage("earned_tuned",8)
	await wait_for("battle","reentry")
	check(is_equal_approx(previous_elapsed,game.battle.elapsed),"Acquisition and READY preserve combat elapsed")
	await stage("ready",8)
	await wait_for("battle","battle")
	await stage("go",15)
	check(game.battle.elapsed > previous_elapsed and not game.battle.paused,"GO restarts real physics without any pointer rescue")
	var after_events: Array = events.slice(accepted_events)
	if profile not in ["mouse","touch"]:
		check(not after_events.any(func(event: Dictionary) -> bool: return event.type in ["mouse","screen_touch"]),"Keyboard/pad completion contains no pointer events")
	outcomes.append({"input":profile,"kind":"draft_completion","passed":game.screen == "battle" and game.battle.elapsed > previous_elapsed,"from_events":accepted_events,"to_events":events.size()})
func mapping(profile: String) -> void:
	capture_group = "mapping"
	await boot(profile)
	var accept := InputEventJoypadButton.new(); accept.device = PAD; accept.button_index = Bindings.confirm_button(profile); accept.pressed = true
	var cancel := InputEventJoypadButton.new(); cancel.device = PAD; cancel.button_index = Bindings.back_button(profile); cancel.pressed = true
	check(accept.is_action("ui_accept") and not accept.is_action("ui_cancel"),"Physical-layout Confirm is actually bound exclusively to accept")
	check(cancel.is_action("ui_cancel") and not cancel.is_action("ui_accept"),"Physical-layout Back is actually bound exclusively to cancel")
	check(FrontEnd.prompt(profile,"confirm") == ("CROSS" if profile == "playstation" else "A"),"Confirm text agrees with the physical-layout action")
	check(FrontEnd.prompt(profile,"back") == ("CIRCLE" if profile == "playstation" else "B"),"Back text agrees with the physical-layout action")
	await intent("settings")
	await stage("options_layout",25)
	check(game.settings.controller_layout == profile,"Persisted layout supports hardware that reports XInput")
	await back(); check(game.screen == "title","Physical-layout Back leaves Options")
	await intent("open_shop")
	await stage("shop",25)
	await intent("request_packet_purchase")
	await stage("dialog_cancel",22)
	check(game.screen == "packet_purchase","Confirm enters the packet purchase dialog")
	await back(); check(game.screen == "shop","Back cancels the purchase without spending")
	await intent("request_packet_purchase")
	await intent("confirm_packet_purchase")
	check(game.screen == "packet_open","Confirm purchases and opens the production packet")
	await stage("packet",25)
	await intent("packet_tear")
	for index: int in range(300):
		if game.menus._packet_view.phase == "RESULT": break
		await wait_frames(1)
	check(game.menus._packet_view.phase == "RESULT","The packet finishes with controller-only input")
	await stage("packet_result",25)
	await intent("packet_workshop")
	check(game.screen == "garage","Controller Confirm enters Workshop from the actual receipt")
	await stage("workshop",25)
	await back(); check(game.screen == "title","Controller Back returns to the hub")
	await intent("start_run")
	await stage("power_selection",20)
	await intent("choose_power")
	await wait_for("battle","battle")
	joy(JOY_BUTTON_A,true)
	await wait_frames(2)
	check(game.screen == "battle" and float(game.battle.player_entity().get("burst_time",0.0)) > 0.0,"The established south-button Burst performs real combat without also opening Pause")
	joy(JOY_BUTTON_A,false); await wait_frames(3)
	await tap_joy(JOY_BUTTON_START)
	check(game.screen == "pause","The dedicated controller MENU opens Pause during combat")
	await stage("pause",25)
	await back(); check(game.screen == "battle" and game.battle.battle_status == "reentry","Controller Back resumes Pause through READY")
	await stage("pause_ready",12)
	await wait_for("battle","battle")
	await stage("pause_go",20)
	outcomes.append({"input":profile,"kind":"menu_mapping","passed":game.screen == "battle","confirm_button":Bindings.confirm_button(profile),"back_button":Bindings.back_button(profile),"physical_hardware":"NOT VALIDATED; synthetic Godot logical events"})
func lifecycle() -> void:
	capture_group = "lifecycle"
	await boot("keyboard")
	await intent("settings")
	var layout_button: Control = null
	for node: Node in descendants(game.menus):
		if node is Button and str(node.get_meta("setting_key","")) == "controller_layout": layout_button = node
	await activate(layout_button)
	check(game.settings.controller_layout == "nintendo" and layout_button.text == "CONTROLLER: NINTENDO","The actual Options button selects the third-party controller type")
	var saved := ConfigFile.new()
	check(saved.load(game.preferences_path) == OK and saved.get_value("settings","controller_layout","") == "nintendo","Controller type persists through the ordinary isolated preference writer")
	input_kind = "nintendo"
	await back()
	check(game.screen == "title","The newly selected Nintendo B immediately performs Back")
	input_kind = "keyboard"
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var before: String = game.screen
	await tap_key(KEY_ENTER)
	check(game.screen == before and game._application_suspended and game.menus.input_suspended,"Actual OS background blocks UI and local-input recovery")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(game._application_suspended,"Focus alone cannot resume a truly backgrounded Android application")
	game._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not game._application_suspended and not game.menus.input_suspended,"Only OS resume releases true background suspension")
	await intent("start_run")
	await intent("choose_power")
	await wait_for("battle","battle")
	key(KEY_SPACE,true)
	await earn_level()
	var claim: String = game.run_context.pending_draft_id
	key(KEY_SPACE,true,true); await wait_frames(3)
	check(game.screen == "reward" and game.run_context.pending_draft_id == claim,"Held/echo Burst cannot pick a new draft")
	key(KEY_SPACE,false); await wait_frames(3)
	await intent("choose_power")
	await wait_for("battle","reentry")
	key(KEY_SPACE,true)
	await wait_for("battle","battle")
	check(game.battle._burst_buffer == 0.0 and game.battle._combat_needs_release,"Held READY Burst waits for a fresh release")
	key(KEY_SPACE,false); await wait_frames(2)
	check(not game.battle._combat_needs_release,"Released action clears the real combat barrier")
	key(KEY_SPACE,true); await wait_frames(2); key(KEY_SPACE,false)
	check(float(game.battle.player_entity().get("burst_time",0.0)) > 0.0,"A fresh combat press really Bursts after READY")

func auto_layout_lifecycle(connected: Array) -> void:
	var actual: Dictionary = {}
	for row: Dictionary in connected:
		if str(row.guid).to_lower() in FrontEnd.NINTENDO_XINPUT_GUID_OVERRIDES:
			actual = row
			break
	if actual.is_empty():
		outcomes.append({"kind":"known_device_auto","skipped":true,
			"reason":"No actual known wrapped-Switch device identity is available to this engine. Headless identity coverage is in controller_bindings; normal Main native AUTO review requires a connected device."})
		if kind == "auto": check(false,"Native AUTO review requires the actual known wrapped-Switch device")
		return
	capture_group = "auto"
	joy_device = int(actual.device)
	await boot("auto")
	var path: String = game.collection_path
	var preferences: String = game.preferences_path
	var saved := ConfigFile.new()
	check(saved.load(preferences) == OK and not saved.has_section_key("settings","controller_layout"),"AUTO fixture retains the real legacy missing-layout-key path")
	check(game.settings.controller_layout == "auto" and Bindings.profile(joy_device) == "nintendo","Normal Main AUTO detects the actual connected known GUID without a saved override")
	check(game.screen == "title" and game.menus.input_profile() == "nintendo","Logical printed-A event confirms Press Start with immediate Nintendo prompts")
	await intent("settings")
	var layout_button: Control = null
	for node: Node in descendants(game.menus):
		if node is Button and str(node.get_meta("setting_key","")) == "controller_layout": layout_button = node
	check(is_instance_valid(layout_button) and layout_button.text == "CONTROLLER: AUTO","Normal Options stays AUTO; no forced Nintendo preference is written")
	await back()
	check(game.screen == "title","Logical printed-B event immediately performs Back with AUTO detection")
	for connected_value: bool in [false,true]:
		# Exercise the actual production reconnect callback; this fixture does
		# not claim the human physically unplugged the device.
		game._controller_connection_changed(joy_device,connected_value)
		check(game.settings.controller_layout == "auto" and Bindings.profile(joy_device) == "nintendo","Reconnect callback retains AUTO and the known Nintendo identity")
	var east := InputEventJoypadButton.new(); east.device = joy_device; east.button_index = JOY_BUTTON_B; east.pressed = true
	var south := InputEventJoypadButton.new(); south.device = joy_device; south.button_index = JOY_BUTTON_A; south.pressed = true
	check(east.is_action("ui_accept") and not east.is_action("ui_cancel") and south.is_action("ui_cancel") and not south.is_action("ui_accept"),"AUTO reconnect retains east-A Confirm and south-B Back bindings")
	var preferences_hash: String = FileAccess.get_sha256(preferences)
	game.sounds.muted = true
	for channel: AudioStreamPlayer in game.sounds.channels: channel.stop()
	game.queue_free(); await wait_frames(3)
	game = Main.new(); game.collection_path = path; root.add_child(game); await wait_frames(5)
	check(game.screen == "title_gate" and game.settings.controller_layout == "auto" and Bindings.profile(joy_device) == "nintendo","Normal same-profile restart restores AUTO recognition without manufacturing a saved layout")
	check(FileAccess.get_sha256(preferences) == preferences_hash,"AUTO boot, navigation, callbacks and restart leave the legacy preference bytes unchanged")
	await intent("enter_frontend")
	check(game.screen == "title" and game.menus.input_profile() == "nintendo","Logical printed-A Confirm and Nintendo prompts work after the ordinary restart")
	outcomes.append({"kind":"known_device_auto","passed":game.screen == "title","device":actual,
		"controller_layout":"auto","preferences_key_missing":true,"preferences_sha256":preferences_hash,
		"scope":"Actual native device metadata and production Main; controlled logical GUI button events and callback fixtures. These are not new physical button presses or a physical reconnect test."})
	joy_device = PAD

func refuse_arguments(message: String) -> bool:
	printerr("DRIVER_ARGUMENTS_REFUSED ", message)
	quit(2)
	return false

func unsafe_main_argument(arg: String) -> bool:
	return arg in ["--smoke-test","--reset-collection","--qa-catalogue"] or arg.begins_with("--collection-path=") or arg.begins_with("--qa-assets-report=") or arg.begins_with("--practice=")

func guard_fixture_paths() -> bool:
	if not report_path.is_absolute_path() or not profiles_path.is_absolute_path():
		return refuse_arguments("Both --report and --profiles must be fresh absolute external QA paths; no Main or player profile was opened.")
	if FileAccess.file_exists(report_path) or DirAccess.dir_exists_absolute(profiles_path):
		return refuse_arguments("Existing report/profile paths are preserved; choose a new artifact identity.")
	var protected: Array[String] = [OS.get_user_data_dir(),ProjectSettings.globalize_path("res://")]
	for value: String in [report_path,profiles_path]:
		var normalized: String = value.replace("\\","/").simplify_path().to_lower().trim_suffix("/")
		for directory: String in protected:
			var prefix: String = directory.replace("\\","/").simplify_path().to_lower().trim_suffix("/")
			if normalized == prefix or normalized.begins_with(prefix + "/"):
				return refuse_arguments("QA paths must stay outside the game checkout and actual player data directory.")
	if not DirAccess.dir_exists_absolute(report_path.get_base_dir()):
		return refuse_arguments("The external report directory must exist before the driver starts.")
	return true

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg.begins_with("--profiles="): profiles_path = arg.trim_prefix("--profiles=")
		if arg.begins_with("--images="): images_path = arg.trim_prefix("--images=")
		if arg.begins_with("--kind="): kind = arg.trim_prefix("--kind=")
		if unsafe_main_argument(arg): refuse_arguments("Unsafe Main boot override refused before opening any profile."); return
	if kind not in ["all","flow","mapping","auto"]: refuse_arguments("Unknown input review kind."); return
	if not guard_fixture_paths(): return
	if kind == "all":
		for suffix: String in ["_mapping","_mapping_lifecycle"]:
			if DirAccess.dir_exists_absolute(profiles_path + suffix): refuse_arguments("Existing derived matrix profiles are preserved."); return
	DirAccess.make_dir_recursive_absolute(profiles_path)
	if not images_path.is_empty(): DirAccess.make_dir_recursive_absolute(images_path)
	root.size = Vector2i(800,480); root.content_scale_size = Vector2i(800,480)
	Input.use_accumulated_input = false
	start_frame = Engine.get_process_frames()
	var layer := CanvasLayer.new(); layer.layer = 100; root.add_child(layer)
	caption = Label.new(); caption.add_theme_font_override("font",FrontEnd.pixel_font()); caption.add_theme_font_size_override("font_size",10)
	caption.add_theme_color_override("font_color",Color("ffffcf")); caption.mouse_filter = Control.MOUSE_FILTER_IGNORE; caption.size = Vector2(800,10); caption.position = Vector2.ZERO; layer.add_child(caption)
	var connected: Array = []
	for device: int in Input.get_connected_joypads(): connected.append({"device":device,"name":Input.get_joy_name(device),"guid":Input.get_joy_guid(device),"info":Input.get_joy_info(device),"known":Input.is_joy_known(device)})
	check(FrontEnd.controller_profile_for("Adapter",{"vendor_id":0x057e}) == "nintendo","USB Nintendo identity survives database renaming")
	check(FrontEnd.controller_profile_for("Adapter",{"vendor_id":0x054c}) == "playstation","USB Sony identity survives database renaming")
	if kind in ["all","flow"]:
		for profile: String in ["mouse","keyboard","xbox","nintendo","playstation","touch"]: await flow(profile)
	if kind in ["all","mapping"]:
		if kind == "all": profiles_path = profiles_path.get_base_dir().path_join(profiles_path.get_file() + "_mapping")
		DirAccess.make_dir_recursive_absolute(profiles_path)
		for profile: String in ["xbox","nintendo","playstation"]:
			await mapping(profile)
	if kind == "all":
		profiles_path = profiles_path.get_base_dir().path_join(profiles_path.get_file() + "_lifecycle")
		DirAccess.make_dir_recursive_absolute(profiles_path)
		await lifecycle()
	if kind in ["all","auto"]: await auto_layout_lifecycle(connected)
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures == 0,"kind":kind,"movie_frames":frame(),"nominal_seconds":float(frame())/60.0,
		"scope":"Normal Main with actual Input.parse_input_event GUI dispatch and real timers/physics. Ownership/wallet, focus notifications, Android back notification, and earned-XP event are explicit QA fixtures. The optional native AUTO branch reads actual connected metadata and uses logical GUI events plus reconnect callbacks; it is not a new physical press or unplug test. Synthetic logical controller and touch coverage, not physical controller/phone acceptance. No synthetic mouse rescue.",
		"input_events":events,"rows":rows,"outcomes":outcomes,"connected_devices":connected},"\t")); file.close()
	print("INPUT_ACCEPTANCE_%s checks=%d failures=%d kind=%s report=%s" % ["PASS" if failures == 0 else "FAIL",checks,failures,kind,report_path])
	if is_instance_valid(game):
		game.sounds.muted = true
		for channel: AudioStreamPlayer in game.sounds.channels: channel.stop()
		game.queue_free()
	await wait_frames(8)
	# Fixed-fps diagnostics can outrun Dummy audio's native teardown callback.
	# Permit that callback to finish after all scene players have stopped.
	OS.delay_msec(150)
	quit(1 if failures else 0)
