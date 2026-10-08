extends SceneTree
## Regression diagnosis: normal boot, actual controller GUI dispatch, injected
## application focus-loss lifecycle. This is not physical-device acceptance.
const Main = preload("res://scripts/main.gd")
const Collection = preload("res://scripts/collection_save.gd")
var game: Node2D
var output: String = ""
var rows: Array = []
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for index: int in range(count): await process_frame
func tap() -> void:
	for down: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 3
		event.button_index = JOY_BUTTON_A
		event.pressed = down
		Input.parse_input_event(event)
		await frames(3)
func state(label: String) -> void:
	rows.append({"label":label,"screen":game.screen,"ui":game.menus.screen,
		"suspended":game._application_suspended,"acquisition_remaining":game._acquisition_remaining,
		"battle_status":game.battle.battle_status,"paused":game.battle.paused,
		"window_focused":DisplayServer.window_is_focused() if DisplayServer.get_name() != "headless" else null})
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	assert(output.is_absolute_path() and not FileAccess.file_exists(output))
	var path: String = output.get_base_dir().get_base_dir().path_join("temp/probe-input-%d-%d.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	var fixture := Collection.new(path)
	fixture.load_save()
	assert(fixture.initialize_starter("bastion").ok)
	game = Main.new()
	game.collection_path = path
	root.add_child(game)
	await frames(4)
	game.sounds.muted = true
	await tap()
	await tap()
	assert(game.screen == "reward")
	state("draft_before_focus_loss")
	game._notification(Main.NOTIFICATION_APPLICATION_FOCUS_OUT)
	state("focus_loss_notification")
	await tap()
	assert(game.screen == "acquisition")
	state("controller_confirm_after_focus_loss")
	await create_timer(1.2).timeout
	state("after_real_timer_no_pointer")
	game._notification(Main.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(1.2).timeout
	state("after_focus_in_no_pointer")
	var devices: Array = []
	for id: int in Input.get_connected_joypads():
		devices.append({"id":id,"name":Input.get_joy_name(id),"guid":Input.get_joy_guid(id),"info":Input.get_joy_info(id),"known":Input.is_joy_known(id)})
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Injected focus-loss notification + actual logical controller GUI events; normal Main timers, no mouse input; not physical hardware acceptance", "rows":rows,"connected_devices":devices,"collection":path},"\t"))
	file.close()
	print("INPUT_SUSPENSION_PROBE ", JSON.stringify(rows))
	game.queue_free()
	await frames(3)
	quit()
