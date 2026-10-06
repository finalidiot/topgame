extends "res://tests/test_collection_ui.gd"
## Normal-boot front-end regression: all workflow transitions use real GUI input.
## Collection fixtures and reset archives live in external QA, never user://.
## The inherited navigation/click/key helpers use Input.parse_input_event.

const FrontEndSkin = preload("res://scripts/front_end.gd")
const SaveModel = preload("res://scripts/collection_save.gd")
var _qa_profiles: String = ""
var _active_profile: String = ""
var _player_files_before: Dictionary = {}

func _settle() -> void:
	# Unlike the collection-layout helper, leave real simulation enabled.
	await process_frame
	await process_frame

func _profile_hashes(path: String) -> Dictionary:
	var hashes: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		hashes[suffix] = FileAccess.get_sha256(path + suffix) if FileAccess.file_exists(path + suffix) else ""
	return hashes

func _player_files() -> Dictionary:
	return {"collection":_profile_hashes(SaveModel.DEFAULT_PATH),
		"preferences":FileAccess.get_sha256("user://prototype.cfg") if FileAccess.file_exists("user://prototype.cfg") else ""}

func _boot_profile(path: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	_active_profile = path
	game = QuietMain.new()
	game.collection_path = path
	root.add_child(game)
	await _settle()
	check(not game.smoke_mode, "The test exercises the ordinary boot path, including preference load/save")
	check(game.collection.save_path == path and path.begins_with(_qa_profiles + "/"), "Collection is scoped to the isolated external QA profile")
	check(game.preferences_path == path + ".preferences.cfg", "Options are scoped beside that isolated profile")
	check(game.screen == "title_gate" and game.menus.screen == "title_gate", "Normal boot opens Press Start before the workbench")
	check(not game.battle.visible and game.battle.paused and not game.battle.is_physics_processing(), "Title gate hides and stops battle simulation")
	_registered("menu")

func _fresh(label: String, initialized_fixture: bool = false) -> void:
	var path: String = _qa_profiles.path_join(label + ".json")
	check(not FileAccess.file_exists(path), "A fresh QA profile never replaces an existing file")
	if initialized_fixture:
		var fixture: SaveModel = SaveModel.new(path)
		fixture.load_save()
		check(bool(fixture.initialize_starter("breaker").ok), "The explicitly labelled fixture owns precisely Breaker's real parts")
	await _boot_profile(path)

func _registered(scope: String) -> void:
	check(FrontEndSkin.SCREEN_REGISTRY.has(game.menus.screen), "Visible screen has a front-end registry entry: " + game.menus.screen)
	check(str(FrontEndSkin.SCREEN_REGISTRY.get(game.menus.screen, {}).get("scope", "")) == scope, "Visible screen has the correct input/presentation scope")

func _slider(key: String) -> HSlider:
	for node: Node in _descendants(game.menus):
		if node is HSlider and str(node.get_meta("setting_key", "")) == key: return node
	return null

func _joy_device(device: int, button: JoyButton, pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)

func _tap_device(device: int, button: JoyButton) -> void:
	_joy_device(device, button, true)
	await _settle()
	_joy_device(device, button, false)
	await _settle()

func _enter_workbench() -> void:
	await _key_tap(KEY_ENTER)
	check(game.screen == "title" and game.menus.screen == "collection_title", "A deliberate Press Start reaches the collection workbench")
	_registered("menu")

func _test_gate_and_owner() -> void:
	await _fresh("normal-first-boot")
	check(not game.collection.is_initialized() and game.collection.owned_count() == 0, "Press Start grants no parts on a genuinely fresh profile")
	_check_layout("Normal title gate")
	await _capture("00-title-gate")
	var gate: Button = _button("enter_frontend")
	check(root.gui_get_focus_owner() == gate, "Press Start is the initial visible focus target")
	_joy(JOY_BUTTON_A, true)
	await _settle()
	check(game.screen == "title_gate", "Holding Confirm alone does not activate a release-mode Press Start")
	_key(KEY_ENTER, true)
	await _settle()
	_key(KEY_ENTER, false)
	await _settle()
	check(game.screen == "title" and game.menus._accept_needs_release, "Workbench consumes the title activation and waits for the held Confirm to release")
	_key(KEY_ENTER, true, true)
	await _settle()
	check(game.screen == "title" and not game.collection.is_initialized() and game.run_context.status == "empty", "Held/echo title Confirm cannot also begin first choice or launch a Run")
	_key(KEY_ENTER, false)
	_joy(JOY_BUTTON_A, false)
	await _settle()
	check(not game.menus._accept_needs_release, "Neutral input clears the workbench release barrier")
	_check_layout("Normal workbench")
	await _capture("01-workbench")
	game.menus.set_ui_input_owner(PAD)
	var focus_before: Control = root.gui_get_focus_owner()
	var profile_before: String = game.menus.input_profile()
	await _tap_device(PAD + 1, JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == focus_before, "A non-owner pad cannot navigate another owner's menu")
	await _tap_device(PAD + 1, JOY_BUTTON_A)
	check(game.screen == "title" and game.collection.owned_count() == 0, "A non-owner pad cannot accept a menu choice")
	check(game.menus.input_profile() == profile_before, "Filtered pad input cannot replace the owner's visible prompts")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == _button("open_workshop"), "The menu-owner pad still navigates through real D-pad events")
	check(game.menus.input_profile() == "gamepad", "A synthetic unnamed device gets truthful generic controller prompts")
	game.menus.set_ui_input_owner(-1)
	await _key_tap(KEY_SHIFT)
	check(game.menus.input_profile() == "keyboard", "Real keyboard input restores keyboard prompts")
	check(str(game.menus._prompt_labels.confirm.text).contains("ENTER"), "Visible prompt updates together with keyboard input context")

func _test_static_profiles() -> void:
	for profile: String in ["xbox", "nintendo", "playstation", "keyboard", "gamepad"]:
		check(not FrontEndSkin.prompt(profile, "confirm").is_empty() and not FrontEndSkin.prompt(profile, "back").is_empty(), "Every supported profile has an explicit confirm/back prompt: " + profile)
	check(FrontEndSkin.prompt("xbox", "confirm") == "A" and FrontEndSkin.prompt("xbox", "back") == "B", "Xbox prompts name the mapped physical south/east face buttons")
	check(FrontEndSkin.prompt("nintendo", "confirm") == "B" and FrontEndSkin.prompt("nintendo", "back") == "A", "Nintendo prompts name B/A without changing physical south/east bindings")
	check(FrontEndSkin.prompt("playstation", "confirm") == "CROSS" and FrontEndSkin.prompt("playstation", "back") == "CIRCLE", "PlayStation prompts identify Cross and Circle")
	check(FrontEndSkin.prompt("gamepad", "confirm") == "SOUTH BUTTON", "Unknown gamepads do not make an unsupported letter-label claim")
	check(FrontEndSkin.glyph("xbox", "confirm").region == Rect2(32, 0, 16, 16), "Xbox Confirm uses the authored A glyph")
	check(FrontEndSkin.glyph("xbox", "back").region == Rect2(48, 0, 16, 16), "Xbox Back uses the authored B glyph")
	check(FrontEndSkin.glyph("nintendo", "confirm").region == Rect2(48, 0, 16, 16), "Nintendo Confirm's B glyph agrees with its text")
	check(FrontEndSkin.glyph("nintendo", "back").region == Rect2(32, 0, 16, 16), "Nintendo Back's A glyph agrees with its text")
	for screen_id: String in ["title_gate", "collection_title", "play_modes", "collection_workshop", "settings", "save_tools", "reset_confirmation", "starter_ceremony", "starter_confirm", "starter_owned", "collection_error", "help", "reward", "mutation", "acquisition", "level_up", "pause", "result", "hud"]:
		check(FrontEndSkin.SCREEN_REGISTRY.has(screen_id), "Screen registry covers the existing game flow: " + screen_id)
	check(str(FrontEndSkin.SCREEN_REGISTRY.hud.scope) == "combat" and int(FrontEndSkin.SCREEN_REGISTRY.hud.background) == -1, "Combat HUD never receives a menu backdrop")

func _test_options_and_persistence() -> void:
	await _fresh("persistent-options", true)
	await _enter_workbench()
	var owned_before: Dictionary = game.collection.snapshot().duplicate(true)
	await _click(_button("settings"))
	check(game.screen == "settings" and game._settings_origin == "title", "Workbench Options remembers its return origin")
	_registered("menu")
	_check_layout("Three independent audio sliders")
	await _capture("02-options")
	for key: String in ["volume", "music_volume", "sfx_volume"]:
		var control: HSlider = _slider(key)
		check(control != null, "Each audio channel has its own focusable slider: " + key)
		if control == null: continue
		var settings_before: Dictionary = game.settings.duplicate(true)
		if await _navigate(control): await _key_tap(KEY_LEFT)
		check(is_equal_approx(float(game.settings[key]), float(settings_before[key]) - 0.05), "Real left input updates only the chosen slider by one native step: " + key)
		for other: String in ["volume", "music_volume", "sfx_volume"]:
			if other != key: check(game.settings[other] == settings_before[other], "Changing " + key + " preserves independent " + other)
		check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(float(game.settings.volume))), "Master volume applies to the actual Master bus")
		check(is_equal_approx(float(game.music.music_snapshot().music_volume), float(game.settings.music_volume)), "Music volume reaches the actual music mixer")
		check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(float(game.settings.sfx_volume))), "SFX volume applies to its separate actual bus")
	var persisted: Dictionary = game.settings.duplicate(true)
	check(FileAccess.file_exists(game.preferences_path), "Ordinary Options immediately writes the isolated preferences file")
	var cfg: ConfigFile = ConfigFile.new()
	check(cfg.load(game.preferences_path) == OK, "Persisted Options remain readable")
	for key: String in ["volume", "music_volume", "sfx_volume"]:
		check(is_equal_approx(float(cfg.get_value("settings", key, -1)), float(persisted[key])), "Persisted settings include independent " + key)
	check(game.collection.snapshot() == owned_before, "Options never modifies collection ownership or assembly")
	await _click(_button("back_settings"))
	check(game.screen == "title" and game.menus.screen == "collection_title", "Options Back returns to the originating workbench")
	var path: String = _active_profile
	await _boot_profile(path)
	check(game.settings == persisted, "Normal reboot loads all settings from the isolated preferences file")
	check(game.collection.snapshot() == owned_before, "Reboot also preserves the independent owned collection")
	await _enter_workbench()

func _reset_buttons() -> void:
	var cancel: Button = _button("cancel_reset_collection")
	var confirm: Button = _button("confirm_reset_collection")
	check(cancel != null and confirm != null, "Reset has separate explicit Cancel and Archive/Reset buttons")
	check(root.gui_get_focus_owner() == cancel, "Destructive confirmation defaults to Cancel / Keep Collection")
	if confirm != null:
		var token: Variant = confirm.get_meta("payload", null)
		check(token is int and int(token) == game._reset_token and int(token) > 0, "Actual confirmation metadata carries the current numeric reset token")
	_registered("menu")

func _test_save_tools_and_reset() -> void:
	var collection_before: Dictionary = game.collection.snapshot().duplicate(true)
	var files_before: Dictionary = _profile_hashes(_active_profile)
	var preferences_before: String = FileAccess.get_sha256(game.preferences_path)
	await _click(_button("settings"))
	await _click(_button("save_tools"))
	check(game.screen == "save_tools" and root.gui_get_focus_owner() == _button("back_settings"), "Save Tools enters safely with Back to Options in focus")
	_check_layout("Save Tools")
	await _capture("03-save-tools")
	await _click(_button("backup_collection"))
	check(_profile_hashes(_active_profile) == files_before and game.collection.snapshot() == collection_before, "Explicit Backup preserves the actual collection bytes and in-memory ownership")
	check(not game.collection.last_backup_path.is_empty(), "Explicit Backup records a verified local archive")
	var request: Button = _button("request_reset_collection")
	if await _navigate(request):
		_joy(JOY_BUTTON_A, true)
		await _settle()
		_key(KEY_ENTER, true)
		await _settle()
		_key(KEY_ENTER, false)
		await _settle()
	check(game.screen == "reset_confirm" and game.menus._accept_needs_release, "Opening reset while Confirm is held installs a release barrier on the new screen")
	_reset_buttons()
	_check_layout("Reset confirmation")
	await _capture("04-reset-default-cancel")
	var held_confirm: Button = _button("confirm_reset_collection")
	if await _navigate(held_confirm):
		_key(KEY_ENTER, true, true)
		await _settle()
		_key(KEY_ENTER, false)
		await _settle()
	check(game.screen == "reset_confirm" and _profile_hashes(_active_profile) == files_before, "Held/echo Confirm cannot reset even when focus deliberately moves to Archive/Reset")
	_joy(JOY_BUTTON_A, false)
	await _settle()
	check(game.screen == "reset_confirm" and not game.menus._accept_needs_release, "Releasing the old activation does not itself confirm reset")
	await _click(_button("cancel_reset_collection"))
	check(game.screen == "save_tools" and game.collection.snapshot() == collection_before and _profile_hashes(_active_profile) == files_before, "Pointer Cancel preserves every collection file and owned part")
	await _click(_button("request_reset_collection"))
	_reset_buttons()
	await _key_tap(KEY_ENTER)
	check(game.screen == "save_tools" and _profile_hashes(_active_profile) == files_before, "Default keyboard Confirm activates Cancel, not Reset")
	await _click(_button("request_reset_collection"))
	_reset_buttons()
	var token_before: int = game._reset_token
	await _click(_button("confirm_reset_collection"))
	check(game.screen == "starter_ceremony" and not game.collection.is_initialized() and game.collection.owned_count() == 0, "A separate deliberate Archive/Reset starts a genuinely fresh first choice")
	check(game._reset_token > token_before, "Successful reset invalidates the confirmation token")
	check(not FileAccess.file_exists(_active_profile), "Reset removed only the isolated collection after verified archive creation")
	check(FileAccess.get_sha256(game.preferences_path) == preferences_before, "Reset retains the actual persisted audio/display preferences byte-for-byte")
	var archive: String = game.collection.last_backup_path
	check(archive.begins_with(_qa_profiles + "/") and FileAccess.file_exists(archive.path_join("manifest.json")), "Reset archive and manifest remain inside the isolated QA tree")
	check(FileAccess.get_sha256(archive.path_join(_active_profile.get_file())) == str(files_before[""]), "Reset archive retains the exact previous collection bytes")
	check(game.run_context.status == "empty", "A testing reset cannot start or complete a Run")

func _test_changed_collection_guard() -> void:
	await _fresh("concurrent-save-guard", true)
	await _enter_workbench()
	await _click(_button("settings"))
	await _click(_button("save_tools"))
	await _click(_button("request_reset_collection"))
	_reset_buttons()
	# Explicitly labelled external fixture: simulate a second legitimate writer.
	var second_writer: SaveModel = SaveModel.new(_active_profile)
	second_writer.load_save()
	check(bool(second_writer.grant_part("blade:guard").ok), "Concurrent-save fixture makes a real unique ownership change")
	var changed: Dictionary = _profile_hashes(_active_profile)
	await _click(_button("confirm_reset_collection"))
	check(game.screen == "save_tools" and game._save_tools_status.contains("changed"), "Actual Confirm detects a collection changed since the confirmation opened")
	check(_profile_hashes(_active_profile) == changed, "Stopped reset preserves the concurrent writer's exact new files")
	var reader: SaveModel = SaveModel.new(_active_profile)
	reader.load_save()
	check(reader.owns_part("blade:guard") and reader.is_initialized(), "Stopped reset retains unique newer ownership")

func _run_state() -> Dictionary:
	var context: RunContext = game.run_context
	return {"seed":context.run_seed, "slot":context.slot, "status":context.status,
		"build":context.selected_build, "starter":context.starter_id,
		"owned":context.owned_power_ids, "ranks":context.power_ranks,
		"mutations":context.power_mutations, "offer":context.pending_offer,
		"draft":context.pending_draft_id, "kind":context.pending_draft_kind,
		"level":context.pending_draft_level, "pending_mutation":context.pending_mutation_power,
		"mutation_offer":context.pending_mutation_offer, "rerolls":context.reroll_snapshot(),
		"progression":context.progression_snapshot(), "results":context.committed_results,
		"rewards":context.committed_rewards}

func _test_pause_options_preserves_run() -> void:
	await _fresh("pause-run-options", true)
	await _enter_workbench()
	await _click(_button("start_run"))
	check(game.screen == "reward" and game.run_context.is_active(), "Real Start Run opens the genuine starting power draft")
	await _key_tap(KEY_RIGHT)
	var draft_focus: String = game.menus.focused_power_id()
	var draft_before: Dictionary = _run_state()
	check(not draft_focus.is_empty() and not str(draft_before.draft).is_empty(), "The paused-draft fixture contains an actual offered power and draft ID")
	await _key_tap(KEY_ESCAPE)
	check(game.screen == "pause" and game.pause_origin == "reward", "Real Escape pauses the starting draft without consuming it")
	await _click(_button("settings"))
	check(game.screen == "settings" and game._settings_origin == "pause", "Pause Options remembers its paused return origin")
	check(_button("save_tools") == null and _button("request_reset_collection") == null, "Collection Save Tools are unavailable throughout an active Run")
	check(game.battle.paused and bool(game.music.music_snapshot().paused), "Pause Options keeps simulation and Run music paused")
	check(_run_state() == draft_before, "Opening Options leaves the actual seed, offer, rank, RPM progression and draft ledger unchanged")
	await _click(_button("back_settings"))
	check(game.screen == "pause" and game.battle.paused, "Options Back returns to Pause without resuming the Run")
	await _click(_button("resume"))
	check(game.screen == "reward" and game.menus.focused_power_id() == draft_focus, "Resume restores the exact focused power card")
	check(_run_state() == draft_before, "Resume restores the exact unconsumed Run draft and ledger")
	await _key_tap(KEY_ENTER)
	check(game.screen == "acquisition", "Real card Confirm performs the implemented acquisition")
	await create_timer(1.6).timeout
	await _settle()
	check(game.screen == "battle" and game.battle.is_physics_processing() and not game.battle.paused, "The real acquisition timer launches live Run simulation")
	# The implemented 2.6-second countdown and 0.45-second launch must run;
	# do not jump the simulation or manufacture live elapsed/RPM for this check.
	var launch_deadline: int = Time.get_ticks_usec() + 4500000
	while game.screen == "battle" and game.battle.elapsed <= 0.0 and Time.get_ticks_usec() < launch_deadline:
		await create_timer(0.05).timeout
	check(game.battle.elapsed > 0.0, "Live physics has genuinely advanced before pause testing")
	await _key_tap(KEY_ESCAPE)
	check(game.screen == "pause" and game.pause_origin == "battle" and game.battle.paused, "Real Escape pauses actual running physics")
	var battle_before: Dictionary = game.battle.snapshot().duplicate(true)
	var run_before: Dictionary = _run_state()
	await _click(_button("settings"))
	await create_timer(0.12).timeout
	check(game.screen == "settings" and game.battle.is_physics_processing(), "The live battle process remains enabled; its real pause guard stops simulation")
	check(game.battle.snapshot() == battle_before, "Options does not advance actual entities, RPM, hits, elapsed time or outcome while paused")
	check(_run_state() == run_before, "Live Pause Options leaves the Run context and committed draft state unchanged")
	await _click(_button("back_settings"))
	await create_timer(0.08).timeout
	check(game.screen == "pause" and game.battle.snapshot() == battle_before, "Options Back preserves the still-stopped simulation")
	await _click(_button("resume"))
	await create_timer(0.08).timeout
	check(game.screen == "battle" and not game.battle.paused and game.battle.elapsed > float(battle_before.elapsed), "Deliberate Resume restarts the same actual simulation")
	check(game.run_context.run_seed == int(run_before.seed) and game.run_context.selected_build == run_before.build and game.run_context.owned_power_ids == run_before.owned, "Resume retains the same seed, assembled top and acquired power")
	check(not bool(game.music.music_snapshot().paused), "Actual resumed combat also resumes its Run music state")
	_registered("combat")

func _run() -> void:
	# Main consumes these global boot flags before its scene is ready. Reject
	# overrides before constructing Main so this test cannot accidentally open
	# a caller-supplied player profile or bypass its ordinary Press Start path.
	for boot_argument: String in OS.get_cmdline_user_args():
		if boot_argument in ["--smoke-test", "--reset-collection", "--qa-catalogue"] or boot_argument.begins_with("--collection-path=") or boot_argument.begins_with("--qa-assets-report=") or boot_argument.begins_with("--practice="):
			check(false, "Front-end tests require their own isolated profile and normal boot; conflicting boot flag refused")
			print("FRONT_END_TEST_REFUSED unsafe_boot_override")
			quit(1)
			return
	check(true, "No Main boot flags can override the test's isolated profiles")
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	Input.use_accumulated_input = false
	var configured: String = OS.get_environment("TOPGAME_QA_ROOT")
	var qa_root: String = configured if not configured.is_empty() else ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	_qa_profiles = qa_root.replace("\\", "/").simplify_path().path_join("002C.6/temp/front-end-profiles-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	check(_qa_profiles.is_absolute_path() and not _qa_profiles.begins_with(ProjectSettings.globalize_path("res://")) and not _qa_profiles.begins_with(OS.get_user_data_dir()), "QA profile root is an absolute external folder")
	if failures > 0:
		quit(1)
		return
	check(DirAccess.make_dir_recursive_absolute(_qa_profiles) == OK, "Created the explicit isolated test-profile directory")
	_player_files_before = _player_files()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	_test_static_profiles()
	await _test_gate_and_owner()
	await _test_options_and_persistence()
	await _test_save_tools_and_reset()
	await _test_changed_collection_guard()
	await _test_pause_options_preserves_run()
	if is_instance_valid(game):
		game.queue_free()
		await _settle()
	check(_player_files() == _player_files_before, "The actual human collection and preferences remained byte-for-byte unchanged")
	print("FRONT_END_TEST_%s checks=%d failures=%d synthetic_device=%d qa_profiles=%s" % ["PASS" if failures == 0 else "FAIL", checks, failures, PAD, _qa_profiles])
	quit(1 if failures else 0)
