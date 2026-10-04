extends "res://tests/test_collection_ui.gd"
## QA movie of the real first-save UI. Fresh isolated save, actual mapped input,
## normal confirmation/safe-write/ownership timer. No inventory fixture or grant.
var manifest_path: String = ""
var report: Dictionary = {"authenticity":"A genuinely missing isolated collection file. Every choice is normal device-3 GUI input; the real confirmation and safe-write API create only the chosen components. No fabricated owned state, rewards or Run progression.","stages":[]}

func _stage(frame: int, name: String) -> void:
	report.stages.append({"time":float(frame)/60.0,"stage":name,"screen":game.screen,"focus_starter":game.menus.focused_starter_id(),"collection":game.collection.snapshot()})

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="): manifest_path = argument.trim_prefix("--manifest=")
	# Capture native pixels. Encode with nearest-neighbour 2x scaling afterwards;
	# PNG MovieMaker output also avoids an intermediate MJPEG compression pass.
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	Input.use_accumulated_input = false
	# Set up directly rather than the UI suite's native-resolution assertions.
	var path: String = "user://task003a-tests/mobile-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert(not FileAccess.file_exists(path), "Review must begin with a missing collection")
	game = QuietMain.new()
	game.smoke_mode = true
	game.review_audio = true
	game.collection_path = path
	root.add_child(game)
	game.set_process(false)
	game.battle.set_physics_process(false)
	report["isolated_save_path"] = ProjectSettings.globalize_path(path)
	report["starting_owned_parts"] = game.collection.owned_count()
	assert(game.collection.owned_count() == 0 and game.screen == "title")
	_stage(0, "empty-title")
	for frame: int in range(1560):
		match frame:
			120, 780, 900: _joy(JOY_BUTTON_A, true)
			122, 782, 902: _joy(JOY_BUTTON_A, false)
			300, 480: _joy(JOY_BUTTON_DPAD_RIGHT, true)
			302, 482: _joy(JOY_BUTTON_DPAD_RIGHT, false)
			660: _joy(JOY_BUTTON_DPAD_LEFT, true)
			662: _joy(JOY_BUTTON_DPAD_LEFT, false)
			125:
				assert(game.screen == "starter_ceremony" and game.menus.focused_starter_id() == "breaker")
				_stage(frame, "breaker-inspection")
			305:
				assert(game.menus.focused_starter_id() == "bastion")
				_stage(frame, "bastion-inspection")
			485:
				assert(game.menus.focused_starter_id() == "vane")
				_stage(frame, "vane-inspection")
			665:
				assert(game.menus.focused_starter_id() == "bastion")
				_stage(frame, "return-to-bastion")
			785:
				assert(game.screen == "starter_confirm" and game.collection.owned_count() == 0)
				_stage(frame, "unconfirmed-first-choice")
			905:
				assert(game.screen == "starter_owned" and game.collection.starter_id == "bastion" and game.collection.owned_count() == 3)
				_stage(frame, "bastion-is-yours")
			1100:
				assert(game.screen == "garage" and game.build == Starters.build_for("bastion"))
				_stage(frame, "owned-workshop")
			1140:
				var before: Dictionary = game.collection.snapshot().duplicate(true)
				if await _navigate(game.menus._part_buttons.blade.hook): await _tap(JOY_BUTTON_A)
				assert(game.screen == "garage" and game.collection.snapshot() == before)
				_stage(frame, "unowned-hook-inspection")
			1320:
				if await _navigate(game.menus._part_buttons.blade.guard): await _tap(JOY_BUTTON_A)
				assert(game.build == Starters.build_for("bastion") and game.collection.owned_count() == 3)
				_stage(frame, "owned-bastion-equipped")
		game._process(1.0/60.0)
		await process_frame
	assert(game.collection.owned_count() == 3 and game.collection.starter_id == "bastion")
	report["final_collection"] = game.collection.snapshot()
	report["nominal_seconds"] = 26.0
	report["input_checks"] = checks
	report["input_failures"] = failures
	if not manifest_path.is_empty():
		var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("STARTER_CEREMONY_CAPTURE_%s owned=%d starter=%s nominal_seconds=26 actual_gui_input=true" % ["PASS" if failures == 0 else "FAIL", game.collection.owned_count(), game.collection.starter_id])
	game.free()
	quit(1 if failures else 0)
