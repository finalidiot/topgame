extends SceneTree
## New shell/settings/reset boundaries around unchanged permanent ownership.
const Main = preload("res://scripts/main.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var qa: String

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _battle_sound(_kind: String) -> void: pass

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func raw(path: String) -> PackedByteArray: return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
func game(path: String) -> QuietMain:
	var node: QuietMain = QuietMain.new()
	node.smoke_mode = true
	node.collection_path = path
	root.add_child(node)
	node.battle.set_physics_process(false)
	return node
func fixture(label: String) -> String: return qa.path_join("temp/presentation_flow_%s_%d_%d.json" % [label,OS.get_process_id(),Time.get_ticks_usec()])
func settle() -> void:
	await process_frame
	await process_frame

func run_state(context: RefCounted) -> Dictionary:
	return {"seed":context.run_seed,"status":context.status,"build":context.selected_build,"powers":context.owned_power_ids,"ranks":context.power_ranks,"mutations":context.power_mutations,"draft":context.pending_draft_id,"offer":context.pending_offer,"progression":context.progression_snapshot(),"rerolls":context.reroll_snapshot()}

func test_routing_settings_reset() -> void:
	var path: String = fixture("reset")
	var app: QuietMain = game(path)
	var invalid: Dictionary = app._validated_settings({"volume":NAN,"music_volume":"bad","sfx_volume":2.0,"muted":"false","screen_shake":false,"unrecognised":123})
	check(invalid.volume == 0.65 and invalid.music_volume == 0.55 and invalid.sfx_volume == 1.0, "Invalid/nonfinite volume data falls back safely and valid gains are bounded")
	check(not invalid.muted and not invalid.screen_shake and not invalid.has("unrecognised"), "Settings retain typed switches and discard unknown keys")
	app._title_gate()
	await settle()
	check(app.screen == "title_gate" and app.collection.owned_count() == 0 and not FileAccess.file_exists(path), "Title gate grants no permanent collection")
	app._action("enter_frontend")
	check(app.screen == "title", "Start enters the Run-focused hub")
	app._action("begin_collection")
	app._action("select_first_starter", "breaker")
	app._action("confirm_first_starter", "breaker")
	check(app.collection.owned_count() == 3 and app.collection.equipped_build() == Starters.build_for("breaker"), "Real first-save intents grant exactly one starter")
	app._ownership_remaining = 0.0
	app._action("finish_ownership")
	check(app.screen == "garage", "Ownership transition reaches the Workshop")
	var saved: PackedByteArray = raw(path)
	app._action("main_menu")
	app._action("play_modes")
	check(app.screen == "play_modes" and raw(path) == saved, "Play Modes is presentation routing without an ownership grant")
	app._action("settings")
	check(app.screen == "settings", "Options opens from Play Modes")
	app.smoke_mode = false # Writes only this explicitly isolated preference path.
	var preferences: Dictionary = {"volume":0.4,"music_volume":0.25,"sfx_volume":0.7,"muted":true,"screen_shake":false,"fullscreen":false}
	app._action("settings_changed", preferences)
	var config: ConfigFile = ConfigFile.new()
	check(config.load(path + ".preferences.cfg") == OK, "Options persist beside the isolated collection")
	for key: String in preferences:
		check(config.get_value("settings", key) == preferences[key], "Independent saved setting matches: " + key)
	check(raw(path) == saved, "Audio/options updates preserve collection bytes")
	var settings_bytes: PackedByteArray = raw(path + ".preferences.cfg")
	app._action("back_settings")
	check(app.screen == "play_modes", "Back returns to the origin of Options")
	app._action("settings")
	app._action("save_tools")
	check(app.screen == "save_tools", "Save Tools is a deliberate options route")
	app._action("confirm_reset_collection", 0)
	check(raw(path) == saved, "Confirmation cannot skip the reset request")
	app._action("request_reset_collection")
	check(app.screen == "reset_confirm" and raw(path) == saved, "Reset request shows confirmation without changing the save")
	var token: int = app._reset_token
	await settle()
	var focused: Control = root.gui_get_focus_owner()
	check(focused is Button and str(focused.get_meta("intent", "")) == "cancel_reset_collection", "The reset dialog defaults controller focus to Cancel")
	app._action("confirm_reset_collection", token + 0.5)
	app._action("confirm_reset_collection", token - 1)
	check(raw(path) == saved, "Fractional and stale reset requests are rejected")
	app._action("cancel_reset_collection")
	check(app.screen == "save_tools" and raw(path) == saved, "Cancel preserves all collection bytes")
	app._action("request_reset_collection")
	app._action("confirm_reset_collection", app._reset_token)
	check(app.screen == "starter_ceremony" and app.collection.owned_count() == 0 and not app.collection.is_initialized(), "Confirmed backed-up reset returns to genuine first-save ceremony")
	check(raw(path + ".preferences.cfg") == settings_bytes, "Collection reset retains every audio/display setting")
	check(not app.collection.last_backup_path.is_empty() and raw(app.collection.last_backup_path.path_join(path.get_file())) == saved, "UI reset preserves the exact original collection in its verified archive")
	app._action("select_first_starter", "bastion")
	app._action("confirm_first_starter", "bastion")
	check(app.collection.owned_count() == 3 and app.collection.equipped_build() == Starters.build_for("bastion"), "After reset, a different starter grants only its own three initial parts")
	check(not app.collection.owns_part("blade:smash"), "Earlier starter ownership is absent from the new active collection")
	evidence.append({"fixture":path,"backup":app.collection.last_backup_path,"fresh_starter":"bastion","owned":3,"settings_retained":true})
	app.queue_free(); await settle()
	var reloaded: QuietMain = game(path)
	check(reloaded.collection.owned_count() == 3 and reloaded.collection.starter_id == "bastion", "Restart loads genuine new ownership")
	reloaded.smoke_mode = false
	reloaded._load_preferences(); reloaded._apply_settings()
	for key: String in preferences: check(reloaded.settings[key] == preferences[key], "Options survive app restart: " + key)
	reloaded.queue_free(); await settle()

func test_pause_options_and_stale_reset() -> void:
	var path: String = fixture("pause")
	var app: QuietMain = game(path)
	app.collection.initialize_starter("bastion")
	app._garage(); app._start_run()
	check(app.screen == "reward", "Presentation retains the real opening Run draft")
	var offer: Array = app.run_context.pending_offer
	check(not offer.is_empty(), "Accepted draft produces a genuine offer")
	if offer.is_empty(): app.queue_free(); await settle(); return
	var row: Dictionary = {"encounter_id":app.run_context.pending_draft_id,"power_id":offer[0],"run_seed":app.run_context.run_seed,"offer_revision":app.run_context.reroll_snapshot().revision}
	app._action("choose_power", row)
	app._acquisition_remaining = 0.0; app._finish_acquisition()
	app.battle.set_physics_process(false)
	var combat: Dictionary = app.battle.player_entity().duplicate(true)
	var run: Dictionary = run_state(app.run_context)
	var saved: PackedByteArray = raw(path)
	app._pause(); app._action("settings")
	check(app.screen == "settings" and app.battle.paused, "An active Run opens Options only while paused")
	app._action("save_tools"); app._action("request_reset_collection"); app._action("confirm_reset_collection", app._reset_token)
	check(app.screen == "settings" and raw(path) == saved, "Run lock blocks reset and save-tool routes")
	check(app.battle.player_entity() == combat, "Paused options do not advance physical state")
	check(run_state(app.run_context) == run, "Options preserve Run XP/draft/seed state")
	app._action("back_settings")
	check(app.screen == "pause", "Back from Options returns to the pause panel")
	app._resume()
	check(app.screen == "battle" and not app.battle.paused, "Resume returns to the same battle")
	app._pause(); app._action("end_run"); app._action("settings"); app._action("save_tools"); app._action("request_reset_collection")
	var token: int = app._reset_token
	check(app.collection.grant_part("blade:hammerfall").ok, "Concurrent change fixture commits a legitimate new owned part")
	var changed: PackedByteArray = raw(path)
	app._action("confirm_reset_collection", token)
	check(app.screen == "save_tools" and raw(path) == changed and app.collection.owned_count() == 4, "A collection changed after confirmation opened is preserved instead of reset")
	app.queue_free(); await settle()

func run() -> void:
	var base: String = OS.get_environment("TOPGAME_QA_ROOT")
	if base.is_empty(): base = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	qa = base.path_join("002C.6")
	assert(DirAccess.make_dir_recursive_absolute(qa.path_join("temp")) == OK)
	var before: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]: before[suffix] = raw("user://collection.json" + suffix)
	# Await explicit test completion through sequential coroutines.
	await test_routing_settings_reset()
	await test_pause_options_and_stale_reset()
	for suffix: String in before: check(raw("user://collection.json" + suffix) == before[suffix], "Human collection remained unchanged throughout shell/reset testing")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var path: String = arg.trim_prefix("--report=")
			assert(not FileAccess.file_exists(path))
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"fixture_policy":"Unique external QA collections/preferences; physical battle is paused during options; no real profile reset"}, "\t")); file.close()
	print("PRESENTATION_FLOW_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
