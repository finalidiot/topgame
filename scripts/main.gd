extends Node2D

const BattleScript = preload("res://scripts/battle.gd")
const MenuScript = preload("res://scripts/menus.gd")
const SoundScript = preload("res://scripts/sound.gd")
const MusicScript = preload("res://scripts/music.gd")
const Catalog = preload("res://scripts/parts.gd")
const RunContext = preload("res://scripts/run_context.gd")
const Starters = preload("res://scripts/starters.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Collection = preload("res://scripts/collection_save.gd")
const PackageProbe = preload("res://scripts/parts_package_probe.gd")
const RunPickupScript = preload("res://scripts/run_pickups.gd")
const PacketEconomy = preload("res://scripts/packet_economy.gd")
const RunRewards = preload("res://scripts/run_rewards.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const AndroidQA = preload("res://scripts/android_qa.gd")

var build: Dictionary = {"blade":"balance", "ratchet":"mid", "bit":"ball"}
var settings: Dictionary = {"volume":0.65, "music_volume":0.55, "sfx_volume":1.0, "muted":false, "screen_shake":true, "fullscreen":false, "reduced_flashing":false}
var touch_controls: Node2D
var _application_suspended: bool = false
var _resume_after_foreground: bool = false
var _android_qa: Dictionary = {}
var _android_qa_clock: float = 0.0
var _android_qa_screen: String = ""
var mode: String = "duel"
var round_index: int = 0
var screen: String = "title"
var last_result: Dictionary = {}
var battle: Node2D
var menus: Control
var sounds: Node
var music: Node
var _settings_origin: String = "title"
var _reset_token: int = 0
var _reset_files: Dictionary = {}
var _save_tools_status: String = ""
var _reset_on_boot_dialog: bool = false
var reroll_pickups: Node2D
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var smoke_mode: bool = false
var review_audio: bool = false
## Tests/review captures override the path before entering the scene tree.
var collection_path: String = ""
var collection: RefCounted
var reset_collection_requested: bool = false
var _collection_reset_failed: bool = false
## Full catalogue access is only enabled for an explicitly isolated QA save.
var qa_catalogue_requested: bool = false
var qa_task_id: String = "002C.5.2"
var qa_catalogue_error: String = ""
var qa_assets_report: String = ""
var qa_assets_report_requested: bool = false
var preferences_path: String = "user://prototype.cfg"
var _ownership_remaining: float = 0.0
var _first_starter_focus: String = "breaker"
var _collection_retry: String = ""
var capture_dir: String = ""
var audit_actions: Array = []
var opponent_build: Dictionary = {}
var run_context = RunContext.new()
var pause_origin: String = "battle"
var _previous_run_seed: int = 0
var _acquisition_remaining: float = 0.0
var _acquired_power_id: String = ""
var _reward_focus_id: String = ""
var _mutation_focus_id: String = ""
var _draft_resume_origin: String = "starting"
var _level_up_remaining: float = 0.0
var _run_launched: bool = false
var _practice_branch: String = ""
var run_rewards = RunRewards.new()
var _run_reward_token: String = ""
var _pending_run_payout: Dictionary = {}
var _packet_purchase_token: int = 0
var _packet_product: String = ""
var _packet_request_id: String = ""
## In-process deterministic review injection. Refused outside fresh 003A QA paths.
var packet_rng_override: RandomNumberGenerator = null

func _process(delta: float) -> void:
	if not _android_qa.is_empty():
		_android_qa_clock -= delta
		if _android_qa_clock <= 0.0:
			_android_qa_clock = 0.25
			AndroidQA.report(self, _android_qa)
		var capture_state: String = screen+"_"+battle.battle_status if screen=="battle" else screen
		if capture_state != _android_qa_screen:
			_android_qa_screen = capture_state
			_capture("android_"+capture_state+"_%d" % Time.get_ticks_msec())
	if is_instance_valid(touch_controls): touch_controls.set_enabled(screen == "battle" and not _application_suspended and not battle.paused)
	if _application_suspended: return
	if is_instance_valid(music) and run_context.is_active() and screen in ["reward", "mutation", "acquisition", "level_up", "pause", "settings"]:
		music.set_paused(true)
	if screen == "starter_owned":
		_ownership_remaining -= delta
		if _ownership_remaining <= 0.0: _garage()
		return
	# Only the visible acquisition beat advances. Pause and End/Restart cannot
	# leave a delayed timer behind that could launch an unrelated encounter.
	if not run_context.is_active(): return
	if screen == "level_up":
		_level_up_remaining -= delta
		if _level_up_remaining <= 0.0: _show_reward()
	elif screen == "acquisition":
		_acquisition_remaining -= delta
		if _acquisition_remaining <= 0.0: _finish_acquisition()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	DisplayServer.window_set_title("Spinning Metal")
	rng.randomize()
	var practice_request: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--smoke-test": smoke_mode = true
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
		if argument.begins_with("--practice="): practice_request = argument.trim_prefix("--practice=")
		if argument.begins_with("--collection-path="): collection_path = argument.trim_prefix("--collection-path=")
		if argument == "--reset-collection": reset_collection_requested = true
		if argument == "--qa-catalogue": qa_catalogue_requested = true
		if argument.begins_with("--qa-task="): qa_task_id = argument.trim_prefix("--qa-task=")
		if argument.begins_with("--qa-assets-report="):
			qa_assets_report_requested = true
			qa_assets_report = argument.trim_prefix("--qa-assets-report=")
	qa_assets_report_requested = qa_assets_report_requested or not qa_assets_report.is_empty()
	_android_qa = AndroidQA.request()
	if not _android_qa.is_empty():
		collection_path = _android_qa.collection_path
		capture_dir = _android_qa.capture_dir
		DirAccess.make_dir_recursive_absolute(capture_dir)
	if smoke_mode: rng.seed = 7341
	if qa_catalogue_requested and not _is_isolated_catalogue_path(collection_path):
		qa_catalogue_error = "Catalogue QA requires an absolute --collection-path inside the configured GyroBrothers-QA/002C.5.2/temp folder. No parts were granted and your player save was not opened."
		collection_path = "user://test_collection/refused_qa_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
		reset_collection_requested = false
	if qa_assets_report_requested and (not qa_catalogue_requested or not qa_catalogue_error.is_empty() or not _is_isolated_assets_report(qa_assets_report)):
		qa_catalogue_error = "Package asset QA requires --qa-catalogue, an isolated QA collection, and a new absolute JSON report inside GyroBrothers-QA/002C.5.2/manifests. No player save was opened and no existing report was replaced."
		collection_path = "user://test_collection/refused_probe_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
		reset_collection_requested = false
	if collection_path.is_empty():
		collection_path = "user://test_collection/main_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()] if smoke_mode else "user://collection.json"
	if ProjectSettings.globalize_path(collection_path).replace("\\", "/").simplify_path().to_lower() != ProjectSettings.globalize_path(Collection.DEFAULT_PATH).replace("\\", "/").simplify_path().to_lower():
		preferences_path = collection_path + ".preferences.cfg"
	if not smoke_mode and qa_catalogue_error.is_empty(): _load_preferences()
	collection = Collection.new(collection_path)
	collection.load_save()
	if not qa_catalogue_error.is_empty(): collection.read_only = true
	if reset_collection_requested:
		# CLI resets of the real profile open the same confirmation as Options.
		# An explicitly isolated dev fixture can reset directly after backup.
		_reset_on_boot_dialog = _is_default_collection_path(collection_path)
		if not _reset_on_boot_dialog: _collection_reset_failed = not bool(collection.reset_collection(true).ok)
	if qa_catalogue_requested and qa_catalogue_error.is_empty(): _prepare_qa_catalogue()
	if collection.can_launch(): build = collection.equipped_build()
	battle = BattleScript.new()
	add_child(battle)
	battle.visible = false
	battle.set_physics_process(false)
	battle.round_finished.connect(_round_finished)
	battle.hud_updated.connect(_hud_updated)
	battle.event_sfx.connect(_battle_sound)
	battle.progression_events.connect(_progression_events)
	battle.threat_cleared.connect(_threat_cleared)
	battle.threat_started.connect(_threat_started)
	reroll_pickups = RunPickupScript.new()
	battle.add_child(reroll_pickups)
	battle.floor_pickups = reroll_pickups
	reroll_pickups.render_in_battle = true
	reroll_pickups.reroll_collected.connect(_reroll_collected)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	menus = MenuScript.new()
	layer.add_child(menus)
	menus.action.connect(_action)
	menus.focus_sound.connect(_battle_sound)
	touch_controls = TouchControls.new()
	layer.add_child(touch_controls)
	battle.input_provider = touch_controls
	sounds = SoundScript.new()
	add_child(sounds)
	music = MusicScript.new()
	music.configure_playback(not qa_assets_report_requested and not smoke_mode and DisplayServer.get_name() != "headless")
	add_child(music)
	_apply_settings()
	if smoke_mode or qa_assets_report_requested or qa_catalogue_requested or not practice_request.is_empty(): _title()
	else: _title_gate()
	if _reset_on_boot_dialog:
		_show_save_tools()
		_request_collection_reset()
	if _collection_reset_failed:
		_collection_error("The explicitly requested collection reset could not finish. Close other game instances and check the save folder before retrying.")
	if not qa_catalogue_error.is_empty(): _collection_error(qa_catalogue_error)
	if qa_assets_report_requested:
		if qa_catalogue_error.is_empty(): call_deferred("_run_qa_assets_probe")
		else: call_deferred("_finish_qa_assets_probe", {"ok":false, "error":qa_catalogue_error})
	elif smoke_mode: call_deferred("_smoke_test")
	elif qa_catalogue_requested and qa_catalogue_error.is_empty(): call_deferred("_garage")
	elif not practice_request.is_empty(): call_deferred("_start_build_practice", practice_request)
	if not _android_qa.is_empty(): call_deferred("_inspect_android_assets")

func _inspect_android_assets() -> void:
	if _android_qa.is_empty(): return
	var output: String = _android_qa.capture_dir.path_join("packaged_assets.json")
	if FileAccess.file_exists(output): return
	var result: Dictionary = PackageProbe.inspect(output)
	if bool(result.get("ok",false)): print("ANDROID_PACKAGED_ASSETS_PASS")
	else: push_error(str(result.get("error","Android package asset inspection failed")))

func _is_default_collection_path(path: String) -> bool:
	# Windows paths are case insensitive; spelling/casing must never bypass
	# the real profile's reset confirmation.
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().to_lower() == ProjectSettings.globalize_path(Collection.DEFAULT_PATH).replace("\\", "/").simplify_path().to_lower()

func _is_isolated_catalogue_path(path: String) -> bool:
	return _is_isolated_qa_path(path, "temp")

func _is_isolated_assets_report(path: String) -> bool:
	return _is_isolated_qa_path(path, "manifests") and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)

func _is_isolated_qa_path(path: String, folder: String) -> bool:
	# Require the designated external QA tree, never res://, user:// or a player
	# profile renamed in-place. Explicit TOPGAME_QA_ROOT remains supported.
	var normalized: String = path.replace("\\", "/").simplify_path()
	if not normalized.is_absolute_path() or path.begins_with("user://") or path.begins_with("res://"): return false
	var configured: String = OS.get_environment("TOPGAME_QA_ROOT")
	var project_folder: String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var qa_root: String = configured if not configured.is_empty() else project_folder.get_base_dir().path_join("GyroBrothers-QA")
	var task_pattern: RegEx = RegEx.create_from_string("^[0-9]{3}[A-Z](?:\\.[0-9]+)*$")
	if task_pattern.search(qa_task_id) == null: return false
	var allowed: String = qa_root.replace("\\", "/").simplify_path().path_join(qa_task_id + "/" + folder).to_lower() + "/"
	var repository: String = ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().to_lower().trim_suffix("/") + "/"
	var userdata: String = OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower().trim_suffix("/") + "/"
	var candidate: String = normalized.to_lower()
	return candidate.begins_with(allowed) and not candidate.begins_with(repository) and not candidate.begins_with(userdata) and candidate.get_extension() == "json"

func _run_qa_assets_probe() -> void:
	# Exported release templates omit the editor's --script entry point. This
	# compiled probe is reachable only through the scoped QA boot flags above.
	if not qa_catalogue_requested or not qa_catalogue_error.is_empty() or not _is_isolated_assets_report(qa_assets_report):
		_finish_qa_assets_probe({"ok":false, "error":"Package asset QA report path is no longer safe or already exists."})
		return
	_finish_qa_assets_probe(PackageProbe.inspect(qa_assets_report))

func _finish_qa_assets_probe(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		print("PACKAGED_PART_ASSETS_PASS textures=", int(result.get("textures", 0)))
	else:
		push_error(str(result.get("error", "Packaged part assets failed validation.")))
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)

func _prepare_qa_catalogue() -> void:
	if collection.read_only:
		qa_catalogue_error = "The isolated catalogue QA collection could not be read safely. Its files have been preserved. Choose a new QA filename."
		return
	if not collection.is_initialized():
		if not bool(collection.initialize_starter("breaker").ok):
			qa_catalogue_error = "Could not create the isolated catalogue QA collection. Your player save has not been opened."
			return
	for category: String in Collection.CATEGORIES:
		for id: String in Catalog.PARTS[category]:
			if not bool(collection.grant_part(category + ":" + id).ok):
				qa_catalogue_error = "Could not finish the isolated catalogue QA collection. Close other QA windows and choose a new QA filename."
				return
	DisplayServer.window_set_title("Spinning Metal — 002C.5.2 ISOLATED CATALOGUE QA")

## Optional isolated human checkpoint. Ordinary seeded Run offers are untouched.
## No progression, power procs, damage or victories are injected while playing.
func _start_build_practice(branch_id: String) -> void:
	var requested_power: String = branch_id.trim_suffix("_ii")
	if not Powers.MUTATIONS.has(branch_id) and branch_id != "hybrid" and requested_power not in Powers.ACTIVE_IDS: return
	_clear_run()
	_practice_branch = branch_id
	var power_id: String = str(Powers.get_mutation(branch_id).get("power_id", requested_power))
	var starter: String = {"redline":"breaker", "dead_centre":"bastion", "afterimage":"vane","high_gear":"vane","orbit_drive":"vane"}.get(power_id, "bastion")
	var descriptor: Dictionary = Encounters.for_slot(3 if power_id == "afterimage" else 5, 421)
	descriptor.player_power_ids = ["impact_wake","clutch","redline","iron_comet","dead_centre","afterimage","chain_impact"] if Powers.MUTATIONS.has(branch_id) or branch_id == "hybrid" else [power_id]
	if power_id in Powers.ACTIVE_IDS and power_id not in descriptor.player_power_ids: descriptor.player_power_ids.append(power_id)
	descriptor.ability_rebalance = true
	descriptor.player_power_ranks = {}
	descriptor.player_power_mutations = {}
	for id: String in descriptor.player_power_ids: descriptor.player_power_ranks[id] = 1
	if branch_id == "hybrid":
		for id: String in ["redline", "dead_centre", "afterimage"]: descriptor.player_power_ranks[id] = 3
		descriptor.player_power_mutations = {"redline":"runaway", "dead_centre":"counterweight", "afterimage":"slipstream"}
	elif Powers.MUTATIONS.has(branch_id):
		descriptor.player_power_ranks[power_id] = 3
		descriptor.player_power_mutations[power_id] = branch_id
	else: descriptor.player_power_ranks[power_id] = 2 if branch_id.ends_with("_ii") else 1
	descriptor.starter_id = starter
	mode = "duel"
	screen = "battle"
	last_result.clear()
	battle.visible = true
	battle.set_physics_process(true)
	battle.begin_encounter(Starters.build_for(starter), descriptor)
	_apply_settings()
	battle._emit_hud()
	music.set_context("run")
	music.observe_run({}, {})
	music.set_paused(false)

func _load_preferences() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(preferences_path) != OK: return
	for key: String in build:
		var value: String = str(cfg.get_value("build", key, build[key]))
		var legal: Array = Catalog.BLADE_IDS if key == "blade" else Catalog.RATCHET_IDS if key == "ratchet" else Catalog.BIT_IDS
		if value in legal: build[key] = value
	for key: String in settings:
		settings[key] = cfg.get_value("settings", key, settings[key])
	settings = _validated_settings(settings)

func _validated_settings(values: Dictionary) -> Dictionary:
	var result: Dictionary = {"volume":0.65,"music_volume":0.55,"sfx_volume":1.0,"muted":false,"screen_shake":true,"fullscreen":false,"reduced_flashing":false}
	for key: String in ["volume", "music_volume", "sfx_volume"]:
		var value: Variant = values.get(key, result[key])
		if (value is int or value is float) and is_finite(float(value)): result[key] = clampf(float(value), 0.0, 1.0)
	for key: String in ["muted", "screen_shake", "fullscreen", "reduced_flashing"]:
		if values.get(key) is bool: result[key] = values[key]
	return result

func _save_preferences() -> void:
	if smoke_mode or not qa_catalogue_error.is_empty(): return
	var cfg: ConfigFile = ConfigFile.new()
	for key: String in build: cfg.set_value("build", key, build[key])
	for key: String in settings: cfg.set_value("settings", key, settings[key])
	cfg.save(preferences_path)

func _apply_settings() -> void:
	sounds.apply_settings(settings)
	if is_instance_valid(music): music.apply_settings(settings)
	battle.screen_shake_enabled = bool(settings.screen_shake)
	battle.reduced_flashing = bool(settings.reduced_flashing)
	battle.presentation_quality = 0.6 if OS.has_feature("mobile") else 1.0
	reroll_pickups.reduced_flashing = bool(settings.reduced_flashing)
	menus.reduced_flashing = bool(settings.reduced_flashing)
	if not smoke_mode and not OS.has_feature("mobile"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)

func _hide_battle() -> void:
	battle.set_paused(true)
	battle.set_physics_process(false)
	battle.visible = false

func _title_gate() -> void:
	_hide_battle()
	screen = "title_gate"
	menus.show_title_gate(collection.is_initialized())
	music.set_context("title")
	music.set_paused(false)

func _title() -> void:
	if run_context.is_active(): return
	if not _pay_pending_run_payout(): return
	_clear_run()
	_hide_battle()
	if not collection.pending_packet().is_empty():
		_show_packet(true)
		return
	screen = "title"
	menus.show_collection_title(collection.equipped_build(), settings, collection.is_initialized())
	if is_instance_valid(music):
		music.set_context("title")
		music.set_paused(false)

func _garage() -> void:
	if run_context.is_active(): return
	if not _pay_pending_run_payout(): return
	if not collection.pending_packet().is_empty():
		_show_packet(true)
		return
	if not collection.is_initialized():
		_begin_collection()
		return
	_clear_run()
	_hide_battle()
	screen = "garage"
	if collection.can_launch(): build = collection.equipped_build()
	var snapshot: Dictionary = collection.snapshot()
	snapshot["build_identity"] = Starters.identity_for_build(collection.equipped_build())
	snapshot["isolated_catalogue_qa"] = qa_catalogue_requested
	menus.show_collection_workshop(collection.equipped_build(), snapshot)
	music.set_context("workshop")
	music.set_paused(false)

func _shop(status: String = "") -> void:
	if run_context.is_active(): return
	if not _pay_pending_run_payout():
		if str(last_result.get("payout_status", "")) != "balance_limit": return
		status = "Wallet full. Spend CREDITS to make room for your pending Run reward."
	if not collection.is_initialized():
		_begin_collection()
		return
	_clear_run()
	_hide_battle()
	if not collection.pending_packet().is_empty():
		_show_packet(true)
		return
	screen = "shop"
	menus.show_shop(collection.snapshot(), status)
	music.set_context("workshop")
	music.set_paused(false)

func _request_packet_purchase(kind: String) -> void:
	if screen != "shop" or run_context.is_active() or kind not in ["standard", "reclaimed"]: return
	if collection.read_only or not collection.pending_packet().is_empty(): return
	var wallet: Dictionary = collection.wallet()
	var unit: String = str(PacketEconomy.config().packets[kind].currency)
	if int(wallet[unit]) < PacketEconomy.packet_cost(kind): return
	_packet_purchase_token += 1
	_packet_product = kind
	_packet_request_id = collection.expected_packet_request_id()
	screen = "packet_purchase"
	menus.show_packet_purchase(kind, collection.snapshot(), _packet_purchase_token)

func _confirm_packet_purchase(token: Variant) -> void:
	if screen != "packet_purchase" or not token is int or int(token) != _packet_purchase_token: return
	if _packet_product not in ["standard", "reclaimed"] or run_context.is_active(): return
	var source: RandomNumberGenerator = null
	if packet_rng_override != null and (qa_task_id == "003A" or smoke_mode) and _is_isolated_qa_path(collection_path, "temp"):
		source = packet_rng_override
	var purchase: Dictionary = collection.purchase_packet(_packet_product, source, _packet_request_id)
	if not bool(purchase.ok):
		_shop("Purchase stopped: %s. Your balance was preserved." % str(purchase.status).replace("_", " "))
		return
	_show_packet(false)

func _show_packet(recovered: bool = false) -> void:
	var pending: Dictionary = collection.pending_packet()
	if pending.is_empty():
		_shop()
		return
	_hide_battle()
	var result: Dictionary = collection.finalize_packet(str(pending.id))
	if not bool(result.ok):
		_collection_error("Your purchased packet is safely saved. Opening stopped: %s. Reload to retry." % str(result.status).replace("_", " "), "packet")
		return
	screen = "packet_open"
	menus.show_packet_open(result.receipt, collection.snapshot(), recovered)
	music.set_context("workshop")
	music.set_paused(false)

func _leave_packet(route: String, kind: String = "") -> void:
	if screen != "packet_open" or not is_instance_valid(menus._packet_view) or menus._packet_view.phase != "RESULT": return
	var pending: Dictionary = collection.pending_packet()
	if pending.is_empty(): return
	if not _pay_pending_run_payout():
		if str(last_result.get("payout_status", "")) != "balance_limit": return
		route = "shop"
	var result: Dictionary = collection.acknowledge_packet(str(pending.id))
	if not bool(result.ok):
		_collection_error("Your acquired parts are saved. The receipt could not be closed. Reload to retry.", "packet")
		return
	match route:
		"workshop": _garage()
		"another":
			_shop()
			_request_packet_purchase(kind)
		"shop": _shop()
		_: _title()

func _practice_garage() -> void:
	if run_context.is_active(): return
	_clear_run()
	_hide_battle()
	screen = "practice_garage"
	menus.show_garage(build, true)
	music.set_context("workshop")
	music.set_paused(false)

func _show_settings() -> void:
	if _settings_origin != "pause": _hide_battle()
	screen = "settings"
	menus.show_settings(settings, "back_settings", not run_context.is_active())
	if _settings_origin == "pause": music.set_paused(true)

func _back_settings() -> void:
	if screen in ["save_tools", "reset_confirm"]:
		_show_settings()
	elif screen == "settings":
		match _settings_origin:
			"pause":
				screen = "pause"
				menus.show_pause(mode == "run")
			"garage": _garage()
			"play_modes":
				screen = "play_modes"
				menus.show_play_modes(build)
			_: _title()

func _collection_file_hashes() -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var path: String = collection_path + suffix
		result[suffix] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	return result

func _collection_backups() -> Array:
	var source: String = ProjectSettings.globalize_path(collection_path).replace("\\", "/").simplify_path()
	var folder: String = source.get_base_dir().path_join("collection-backups").path_join(source.get_file().get_basename())
	var result: Array = []
	if not DirAccess.dir_exists_absolute(folder): return result
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null: return result
	var entries: PackedStringArray = directory.get_directories()
	entries.sort()
	# Display metadata only. This page never silently restores/deletes archives.
	for index: int in range(maxi(0, entries.size() - 5), entries.size()):
		var manifest: String = folder.path_join(entries[index]).path_join("manifest.json")
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest)) if FileAccess.file_exists(manifest) else null
		if data is Dictionary and str(data.get("source", "")) == source:
			result.append({"name":entries[index],"created_utc":data.get("created_utc", ""),"path":folder.path_join(entries[index]),"file_count":data.get("files", []).size()})
	return result

func _show_save_tools() -> void:
	if run_context.is_active(): return
	screen = "save_tools"
	menus.show_save_tools(collection.snapshot(), _collection_backups(), _save_tools_status, "back_settings")

func _request_collection_reset() -> void:
	if screen != "save_tools" or run_context.is_active(): return
	_reset_token += 1
	_reset_files = _collection_file_hashes()
	var info: Dictionary = collection.snapshot()
	info["reset_token"] = _reset_token
	screen = "reset_confirm"
	menus.show_reset_confirmation(info)

func _confirm_collection_reset(token: Variant) -> void:
	if screen != "reset_confirm" or run_context.is_active() or not (token is int or token is float) or float(token) != float(_reset_token): return
	if _collection_file_hashes() != _reset_files:
		_save_tools_status = "Collection changed in another window. Reset stopped."
		_show_save_tools()
		return
	var result: Dictionary = collection.reset_collection(true)
	_reset_token += 1
	if not bool(result.ok):
		_save_tools_status = "Reset stopped. The collection and verified backup were preserved."
		_show_save_tools()
		return
	# An explicit full progression reset also retires any verified, unpaid
	# session outcome; its old nonce cannot belong to the fresh collection.
	_pending_run_payout.clear()
	_run_reward_token = ""
	_clear_run()
	last_result.clear()
	_save_tools_status = "Collection reset. Verified backup retained; options unchanged."
	_begin_collection()

func _collection_error(message: String, retry: String = "") -> void:
	_collection_retry = retry
	screen = "collection_error"
	menus.show_collection_error(message, "main_menu", not retry.is_empty())

func _begin_collection() -> void:
	if run_context.is_active(): return
	if collection.read_only:
		_collection_error("Collection could not be safely loaded. Your save has been preserved. See the checkpoint reset instructions.")
		return
	if collection.is_initialized():
		_garage()
		return
	_clear_run()
	_hide_battle()
	screen = "starter_ceremony"
	menus.show_starter_ceremony(_first_starter_focus)
	music.set_context("workshop")
	music.set_paused(false)

func _confirm_first_starter(starter_id: String) -> void:
	if screen != "starter_confirm" or starter_id != _first_starter_focus: return
	var result: Dictionary = collection.initialize_starter(starter_id)
	if not bool(result.ok):
		_collection_error("Could not save your first machine. Nothing was granted. Please retry.", "starter")
		return
	build = collection.equipped_build()
	screen = "starter_owned"
	_ownership_remaining = 1.4
	menus.show_starter_owned(starter_id)
	_battle_sound("acquire")

func _equip_collection_part(value: Dictionary) -> void:
	if screen != "garage": return
	var selected: Dictionary = collection.equipped_build()
	selected[str(value.get("category", ""))] = str(value.get("id", ""))
	var result: Dictionary = collection.equip_build(selected)
	if bool(result.ok):
		_garage()
		menus.focus_collection_part(str(value.get("category", "")), str(value.get("id", "")))
	elif str(result.status) in ["write_failed", "stale_save", "read_only"]:
		_collection_error("Could not save the assembly. The collection has been preserved. Retry reloads the latest saved machine.", "workshop")

func _opponent() -> Dictionary:
	var rivals: Array = [
		{"blade":"smash", "ratchet":"low", "bit":"flat"},
		{"blade":"guard", "ratchet":"mid", "bit":"needle"},
		{"blade":"hook", "ratchet":"mid", "bit":"rubber"},
		{"blade":"balance", "ratchet":"high", "bit":"ball"}
	]
	return rivals[rng.randi_range(0, rivals.size()-1)].duplicate()

func _start_battle(selected_mode: String = "duel", next: bool = false, replay: bool = false) -> void:
	if selected_mode == "run":
		if not run_context.is_active(): _start_run()
		return
	if run_context.is_active(): return
	_clear_run()
	mode = "duel"
	round_index = 0
	if not replay or opponent_build.is_empty(): opponent_build = _opponent()
	last_result.clear()
	screen = "battle"
	battle.visible = true
	battle.set_physics_process(true)
	battle.set_paused(false)
	battle.begin(build.duplicate(), opponent_build.duplicate(), 1, 7341 if smoke_mode else rng.randi())
	_apply_settings()
	battle._emit_hud()
	music.set_context("run")
	music.observe_run({}, {})
	music.set_paused(false)

func _clear_run() -> void:
	if _pending_run_payout.is_empty():
		if not _run_reward_token.is_empty(): collection.abort_reward_run(_run_reward_token)
		_run_reward_token = ""
	run_rewards.abort()
	if is_instance_valid(reroll_pickups): reroll_pickups.clear()
	_run_launched = false
	_practice_branch = ""
	_acquisition_remaining = 0.0
	_acquired_power_id = ""
	_reward_focus_id = ""
	_mutation_focus_id = ""
	_level_up_remaining = 0.0
	_draft_resume_origin = "starting"
	run_context.clear()
	mode = "duel"
	round_index = 0
	pause_origin = "battle"

func _start_run() -> void:
	if run_context.is_active(): return
	if not collection.pending_packet().is_empty():
		_show_packet(true)
		return
	if not collection.is_initialized():
		_begin_collection()
		return
	if not collection.can_launch():
		_collection_error("This collection has no complete owned assembly. Your known parts are preserved. See the checkpoint recovery instructions.")
		return
	_restart_run()

func _restart_run() -> void:
	if not collection.can_launch(): return
	if not _pay_pending_run_payout(): return
	if not _run_reward_token.is_empty(): collection.abort_reward_run(_run_reward_token)
	_run_reward_token = ""
	run_rewards.abort()
	_run_launched = false
	# Entropy is sampled only here, never from menu duration or encounter timing.
	var selected: Dictionary = collection.equipped_build()
	var identity: String = Starters.identity_for_build(selected)
	var fresh_seed: int = rng.randi()
	while fresh_seed == 0 or fresh_seed == _previous_run_seed:
		fresh_seed = rng.randi()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--run-seed=") and argument.trim_prefix("--run-seed=").is_valid_int():
			fresh_seed = int(argument.trim_prefix("--run-seed="))
	if not _android_qa.is_empty() and int(_android_qa.run_seed) > 0: fresh_seed = int(_android_qa.run_seed)
	_previous_run_seed = fresh_seed
	_acquisition_remaining = 0.0
	_level_up_remaining = 0.0
	_acquired_power_id = ""
	_reward_focus_id = ""
	_draft_resume_origin = "starting"
	run_context.start(selected, fresh_seed, identity)
	reroll_pickups.clear()
	mode = "run"
	_hide_battle()
	_show_reward()
	music.set_context("run")
	music.observe_run({}, {})
	music.set_paused(true)

func _launch_run_encounter() -> void:
	if not run_context.is_active() or _run_launched: return
	var eligible: bool = not smoke_mode and not qa_catalogue_requested and _practice_branch.is_empty()
	if eligible:
		var started: Dictionary = collection.begin_reward_run()
		if not bool(started.ok):
			_clear_run()
			_collection_error("The Run could not start because its reward record could not be saved. Your collection is preserved.", "workshop")
			return
		_run_reward_token = str(started.run_id)
	run_rewards.start(run_context.run_seed, _run_reward_token if eligible else "fixture", eligible)
	_run_launched = true
	_acquisition_remaining = 0.0
	_acquired_power_id = ""
	_reward_focus_id = ""
	var encounter: Dictionary = run_context.current_encounter()
	mode = "run"
	round_index = run_context.slot - 1
	opponent_build = encounter.opponent_build.duplicate(true)
	last_result.clear()
	screen = "battle"
	battle.visible = true
	battle.set_physics_process(true)
	battle.begin_run(run_context.selected_build, encounter, run_context.run_seed)
	reroll_pickups.setup(battle, run_context)
	_apply_settings()
	battle._emit_hud()

func _show_reward() -> void:
	if not run_context.is_active() or run_context.pending_offer.is_empty(): return
	screen = "reward"
	battle.set_paused(true)
	var starting: bool = run_context.pending_draft_kind == "starting"
	var context: Dictionary = {"title":"CHOOSE YOUR FIRST POWER" if starting else "LEVEL %d / CHOOSE A POWER" % run_context.pending_draft_level,
		"subtitle":"Enter the arena already dangerous." if starting else "Battle paused. Add a power or invest in one you own.",
		"resume_label":_acquisition_prompt(), "power_ranks":run_context.power_ranks, "power_mutations":run_context.power_mutations,
		"rerolls":run_context.reroll_snapshot()}
	menus.show_reward(run_context.pending_offer, run_context.owned_power_ids, run_context.slot, run_context.pending_draft_id, run_context.run_seed, _reward_focus_id, context)

func _show_mutation(announce: bool = true) -> void:
	if run_context.pending_mutation_power.is_empty(): return
	screen = "mutation"
	battle.set_paused(true)
	menus.show_mutation(run_context.pending_mutation_power, run_context.pending_mutation_offer, run_context.pending_draft_id, run_context.run_seed, _mutation_focus_id)
	if announce and not smoke_mode: sounds.play_sound("mutation_available")

func _show_acquisition(power_id: String) -> void:
	screen = "acquisition"
	_acquired_power_id = power_id
	var rank: int = int(run_context.power_ranks.get(power_id, 1))
	var mutation: String = str(run_context.power_mutations.get(power_id, ""))
	_acquisition_remaining = 1.0 if rank == 3 else (0.70 if rank == 2 else 0.5)
	menus.show_acquisition(power_id, _acquisition_prompt(), rank, mutation)
	if not smoke_mode: sounds.play_sound("mutation_select" if rank == 3 else ("rank_up" if rank == 2 else "acquire"))

func _acquisition_prompt() -> String:
	return "LAUNCH" if _draft_resume_origin == "starting" else "RETURN TO COMBAT"

func _threat_cleared(summary: Dictionary) -> void:
	if mode != "run" or not run_context.is_active() or battle.continuous == null: return
	if summary != battle.continuous.last_clear or int(summary.get("run_seed",-1)) != run_context.run_seed: return
	run_rewards.observe_clear(summary)
	reroll_pickups.notify_clear(summary)
	battle._emit_hud()

func _reroll_collected(_id: String) -> void:
	if screen == "battle" and mode == "run" and run_context.is_active(): battle._emit_hud()

func _threat_started(summary: Dictionary) -> void:
	if mode != "run" or not run_context.is_active() or battle.continuous == null: return
	if summary != battle.continuous.last_entry or int(summary.get("run_seed",-1)) != run_context.run_seed: return
	if run_context.admit_event(int(summary.threat)): battle._emit_hud()

func _finish_acquisition() -> void:
	if not run_context.pending_offer.is_empty():
		_reward_focus_id = ""
		_show_reward()
	elif _draft_resume_origin == "starting":
		_launch_run_encounter()
	else:
		screen = "battle"
		battle.begin_reentry()
		battle._emit_hud()
		if not smoke_mode: sounds.play_sound("resume")

func _progression_events(events: Array) -> void:
	if mode != "run" or screen != "battle" or not run_context.is_active(): return
	if battle.battle_status == "finished" and not bool(battle.last_result.get("won", false)): return
	var before: Dictionary = run_context.progression_snapshot()
	for event: Dictionary in events: run_context.award_xp(event)
	var after: Dictionary = run_context.progression_snapshot()
	if battle.continuous != null: battle.continuous.progression_level = run_context.level
	if not run_context.pending_offer.is_empty():
		_draft_resume_origin = "battle"
		_reward_focus_id = ""
		screen = "level_up"
		_level_up_remaining = 0.18
		battle.set_paused(true)
		menus.show_level_up(run_context.pending_draft_level)
		if not smoke_mode: sounds.play_sound("level_up")
	elif int(before.level) == int(after.level) and float(before.fraction) < 0.8 and float(after.fraction) >= 0.8 and not bool(after.maxed):
		if not smoke_mode: sounds.play_sound("near_level")
	else:
		battle._emit_hud()

func _hud_updated(stats: Dictionary) -> void:
	if screen != "battle": return
	if is_instance_valid(music):
		music.set_context("run")
		music.set_paused(false)
	stats = stats.duplicate()
	stats["run_label"] = "THREAT %d" % run_context.slot if mode == "run" else "DUEL"
	stats["owned_power_ids"] = run_context.owned_power_ids if mode == "run" else []
	stats["power_ranks"] = run_context.power_ranks if mode == "run" else {}
	stats["power_mutations"] = run_context.power_mutations if mode == "run" else {}
	stats["is_run"] = mode == "run"
	stats["rerolls"] = run_context.reroll_charges if mode == "run" else 0
	if not _practice_branch.is_empty():
		stats["run_label"] = "BUILD PRACTICE / " + _practice_branch.replace("_", " ").to_upper()
		stats["owned_power_ids"] = battle.player_entity().get("powers", [])
		stats["power_ranks"] = battle.player_entity().get("power_ranks", {})
		stats["power_mutations"] = battle.player_entity().get("power_mutations", {})
	if mode == "run":
		var progress: Dictionary = run_context.progression_snapshot()
		stats["starter_id"] = run_context.starter_id
		stats["level"] = progress.level
		stats["xp"] = progress.xp
		stats["xp_threshold"] = progress.threshold
		stats["progression_max"] = progress.maxed
	if is_instance_valid(music): music.observe_run(stats.get("run_state", {}), stats)
	menus.show_hud(stats)

func _round_finished(result: Dictionary) -> void:
	if screen != "battle": return
	if mode == "run":
		# Only the live session's actual loss may end a Run. Stale ordinary
		# victories/results cannot terminate a later threat or a restarted Run.
		if battle.continuous == null or battle.battle_status != "finished" or result != battle.last_result: return
		if not bool(result.get("continuous_run", false)) or bool(result.get("won", true)): return
		if int(result.get("run_seed", -1)) != run_context.run_seed or str(battle.player_entity().outcome).is_empty(): return
		if not run_context.fail_run(): return
	screen = "result"
	battle.set_paused(true)
	music.set_context("result")
	music.set_paused(false)
	last_result = result.duplicate(true)
	if not smoke_mode: sounds.play_sound("win" if bool(result.get("won", false)) else "loss")
	last_result["is_run"] = mode == "run"
	last_result["next_available"] = false
	if mode == "run":
		last_result["title"] = "RUN ENDED"
		last_result["level"] = run_context.level
		last_result["owned_power_ids"] = run_context.owned_power_ids
		last_result["power_ranks"] = run_context.power_ranks
		last_result["power_mutations"] = run_context.power_mutations
		last_result["starter_id"] = run_context.starter_id
		last_result["build"] = run_context.selected_build
		last_result["director_version"] = "task002c2-v1"
		last_result["rpm_economy"] = battle.continuous.economy.snapshot()
		last_result["director_history"] = battle.continuous.director.history.duplicate(true)
		last_result["investments"] = run_context.committed_rewards
		last_result["rerolls"] = run_context.reroll_snapshot()
		last_result["credits_earned"] = 0
		last_result["wallet_credits"] = collection.credits
		var reward: Dictionary = run_rewards.finalize(result)
		if bool(reward.ok) and not _run_reward_token.is_empty():
			_pending_run_payout = reward.outcome.duplicate(true)
			_pay_pending_run_payout()
		last_result["reward_accounting"] = run_rewards.snapshot()
		if not smoke_mode:
			var diagnostic_path: String = "user://last_run_director.json" if preferences_path == "user://prototype.cfg" else collection_path + ".last_run_director.json"
			var diagnostic: FileAccess = FileAccess.open(diagnostic_path,FileAccess.WRITE)
			if diagnostic != null: diagnostic.store_string(JSON.stringify(last_result,"\t"))
	menus.show_result(last_result)

func _pay_pending_run_payout() -> bool:
	if _pending_run_payout.is_empty(): return true
	# Keep the verified outcome while a transient write failure is retried. Never
	# call finalize twice, discard the nonce on navigation, or infer a new reward.
	if collection.read_only:
		var loaded: Dictionary = collection.load_save()
		if not bool(loaded.ok):
			last_result.payout_pending = true
			last_result.payout_detail = "CREDITS not saved. Close other game instances and use RETRY CREDITS."
			return false
	var paid: Dictionary = collection.pay_run_reward(_run_reward_token, _pending_run_payout)
	if not bool(paid.ok):
		last_result.payout_pending = true
		last_result.payout_status = str(paid.status)
		last_result.payout_detail = "CREDITS not saved: %s. Use RETRY CREDITS before leaving Results." % str(paid.status).replace("_", " ")
		return false
	last_result.credits_earned = int(paid.credits_earned)
	last_result.wallet_credits = collection.credits
	last_result.payout_pending = false
	last_result.payout_status = str(paid.status)
	var rules: Dictionary = PacketEconomy.config().reward
	last_result.payout_detail = "%d CREDITS per player-cleared threat +%d per elite +%d per boss. Maximum %d per Run." % [int(rules.threat_clear), int(rules.elite_clear), int(rules.boss_clear), int(rules.max_run_payout)]
	_pending_run_payout.clear()
	_run_reward_token = ""
	return true

func _battle_sound(kind: String) -> void:
	# Read-only packaged inspection exits immediately after boot. Starting a
	# focus cue there leaves a native WAV playback alive at headless shutdown.
	if qa_assets_report_requested: return
	if is_instance_valid(music): music.notify_cue(kind)
	if not smoke_mode or review_audio: sounds.play_sound(kind)

func _action(name: String, value: Variant = null) -> void:
	audit_actions.append(name)
	# All build/menu routes respect the lock, including stale UI signals.
	if run_context.is_active() and name in ["quick_duel", "start_battle", "start_run", "customize", "build_changed", "help", "settings", "main_menu", "rematch", "begin_collection", "open_workshop", "open_shop", "inspect_shop_product", "request_packet_purchase", "confirm_packet_purchase", "practice_garage", "equip_part", "launch_owned_run", "select_first_starter", "confirm_first_starter", "finish_ownership", "play_modes", "save_tools", "backup_collection", "request_reset_collection", "confirm_reset_collection"]:
		if not (name == "settings" and screen == "pause"): return
	_battle_sound("ui")
	match name:
		"enter_frontend":
			if screen == "title_gate": _title()
		"play_modes":
			if not run_context.is_active():
				_hide_battle()
				screen = "play_modes"
				menus.show_play_modes(build)
				music.set_context("title")
		"save_tools":
			if screen == "settings": _show_save_tools()
		"backup_collection":
			if screen == "save_tools":
				var result: Dictionary = collection.backup_collection()
				_save_tools_status = "Verified backup saved. Options were retained." if bool(result.ok) and not str(result.get("backup_directory", "")).is_empty() else ("No saved collection to back up." if bool(result.ok) else "Backup stopped. Your collection was preserved.")
				_show_save_tools()
		"request_reset_collection": _request_collection_reset()
		"confirm_reset_collection": _confirm_collection_reset(value)
		"cancel_reset_collection":
			if screen == "reset_confirm": _show_save_tools()
		"back_settings": _back_settings()
		"begin_collection": _begin_collection()
		"open_workshop": _garage()
		"open_shop": _shop()
		"inspect_shop_product":
			if screen == "shop": menus.select_shop_product(str(value))
		"request_packet_purchase": _request_packet_purchase(str(value))
		"confirm_packet_purchase": _confirm_packet_purchase(value)
		"cancel_packet_purchase":
			if screen == "packet_purchase": _shop()
		"packet_odds":
			if screen in ["shop", "packet_odds"]:
				var kind: String = "reclaimed" if screen == "shop" and menus.selected_shop_product() == "reclaimed" else "standard"
				screen = "packet_odds"
				menus.show_packet_odds(PacketEconomy.rarity_odds(kind, collection.owned_parts()))
		"packet_reclaimed_odds":
			if screen == "packet_odds": menus.show_packet_odds(PacketEconomy.rarity_odds("reclaimed", collection.owned_parts()))
		"packet_salvage_info":
			if screen == "packet_odds": menus.show_packet_salvage_info(PacketEconomy.config().duplicate_salvage, PacketEconomy.packet_cost("reclaimed"))
		"packet_tear":
			if screen == "packet_open": menus.tear_packet()
		"packet_skip":
			if screen == "packet_open": menus.skip_packet()
		"packet_workshop": _leave_packet("workshop")
		"packet_another": _leave_packet("another", str(value))
		"packet_shop": _leave_packet("shop")
		"packet_continue": _leave_packet("hub")
		"practice_garage": _practice_garage()
		"select_first_starter":
			if screen == "starter_ceremony" and str(value) in Starters.IDS and not collection.is_initialized():
				_first_starter_focus = str(value)
				screen = "starter_confirm"
				menus.show_starter_confirmation(_first_starter_focus)
		"back_to_starters":
			if screen == "starter_confirm": _begin_collection()
		"confirm_first_starter": _confirm_first_starter(str(value))
		"finish_ownership":
			if screen == "starter_owned" and _ownership_remaining <= 0.6: _garage()
		"equip_part":
			if value is Dictionary: _equip_collection_part(value)
		"inspect_locked_part":
			# A locked catalogue card is informational, never an equip/grant.
			if screen == "garage" and value is Dictionary:
				menus.inspect_locked_part(str(value.get("category", "")), str(value.get("id", "")))
		"launch_owned_run":
			if screen == "garage": _start_run()
		"retry_collection":
			if screen == "collection_error":
				collection.load_save()
				if _collection_retry == "starter":
					if collection.is_initialized(): _garage()
					elif collection.read_only: _begin_collection()
					else:
						screen = "starter_confirm"
						_confirm_first_starter(_first_starter_focus)
				elif _collection_retry == "workshop": _garage()
				elif _collection_retry == "packet": _show_packet(true)
		"start_run": _start_run()
		"retry_run_payout":
			if screen == "result":
				_pay_pending_run_payout()
				menus.show_result(last_result)
		"restart_run":
			if mode == "run" and screen in ["pause", "result"]: _restart_run()
		"end_run":
			if mode == "run":
				if not _pay_pending_run_payout(): return
				_clear_run()
				last_result.clear()
				_garage()
		"choose_power":
			if mode == "run" and screen == "reward" and value is Dictionary:
				if int(value.get("run_seed", -1)) != run_context.run_seed: return
				if int(value.get("offer_revision", 0)) != int(run_context.reroll_snapshot().revision): return
				if run_context.choose_power(str(value.get("encounter_id", "")), str(value.get("power_id", ""))):
					if not run_context.pending_mutation_power.is_empty():
						_mutation_focus_id = ""
						_show_mutation()
					else:
						if _draft_resume_origin == "battle": battle.acquire_run_power(str(value.power_id), int(run_context.power_ranks.get(str(value.power_id), 1)))
						if not smoke_mode: sounds.play_sound("card_select")
						_show_acquisition(str(value.power_id))
		"reroll_power":
			if mode == "run" and screen == "reward" and value is Dictionary:
				if int(value.get("run_seed", -1)) != run_context.run_seed: return
				if run_context.reroll_offer(str(value.get("encounter_id", "")), int(value.get("offer_revision", -1))):
					_reward_focus_id = ""
					_show_reward()
		"choose_mutation":
			if mode == "run" and screen == "mutation" and value is Dictionary:
				if int(value.get("run_seed", -1)) != run_context.run_seed: return
				var power_id: String = run_context.pending_mutation_power
				if run_context.choose_mutation(str(value.get("encounter_id", "")), str(value.get("branch_id", ""))):
					if _draft_resume_origin == "battle": battle.acquire_run_power(power_id, 3, str(run_context.power_mutations.get(power_id, "")))
					_show_acquisition(power_id)
		"quick_duel": _start_battle("duel")
		"start_battle": _start_battle(str(value) if value != null else "duel")
		"customize": _garage()
		"help":
			_hide_battle()
			screen = "help"
			menus.show_help()
		"settings":
			_settings_origin = screen if screen in ["pause", "garage", "play_modes", "title"] else "title"
			_show_settings()
		"main_menu": _title()
		"build_changed":
			if screen == "practice_garage" and value is Dictionary:
				build = Catalog.validate_build(value)
				_save_preferences()
		"settings_changed":
			if value is Dictionary:
				settings.merge(value, true)
				settings = _validated_settings(settings)
				_apply_settings()
				_save_preferences()
		"pause": _pause()
		"resume": _resume()
		"rematch":
			if mode == "duel" and screen in ["pause", "result"]:
				if not _practice_branch.is_empty(): _start_build_practice(_practice_branch)
				else: _start_battle("duel", true, true)
		"quit": get_tree().quit()

func _pause() -> void:
	if screen != "battle" and not (run_context.is_active() and screen in ["reward", "mutation", "result", "acquisition", "level_up"]): return
	if screen == "reward": _reward_focus_id = menus.focused_power_id()
	if screen == "mutation": _mutation_focus_id = menus.focused_power_id()
	pause_origin = screen
	if is_instance_valid(touch_controls): touch_controls.clear()
	screen = "pause"
	battle.set_paused(true)
	menus.show_pause(mode == "run")
	music.set_paused(true)

func _resume() -> void:
	if screen != "pause": return
	screen = pause_origin
	if screen == "reward": _show_reward()
	elif screen == "mutation": _show_mutation(false)
	elif screen == "acquisition": menus.show_acquisition(_acquired_power_id, _acquisition_prompt(), int(run_context.power_ranks.get(_acquired_power_id, 1)), str(run_context.power_mutations.get(_acquired_power_id, "")))
	elif screen == "result": menus.show_result(last_result)
	elif screen == "level_up": menus.show_level_up(run_context.pending_draft_level)
	else:
		battle.begin_reentry()
		battle._emit_hud()
	music.set_paused(screen != "battle")

func _escape() -> void:
	if screen == "packet_open":
		if is_instance_valid(menus._packet_view) and menus._packet_view.phase == "RESULT": _leave_packet("shop")
		else: menus.skip_packet()
	elif screen in ["packet_purchase", "packet_odds"]: _shop()
	elif screen == "shop": _title()
	elif screen == "reset_confirm": _show_save_tools()
	elif screen in ["save_tools", "settings"]: _back_settings()
	elif screen == "title_gate": return
	elif screen == "pause": _resume()
	elif screen == "battle" or run_context.is_active(): _pause()
	elif screen == "starter_confirm": _begin_collection()
	elif screen == "starter_owned":
		if _ownership_remaining <= 0.6: _garage()
	else: _title()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2 and screen == "battle":
		menus.visible = not menus.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		menus.visible = true
		_escape()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fullscreen"):
		if screen == "battle": battle.begin_reentry()
		settings.fullscreen = not bool(settings.fullscreen)
		_apply_settings()
		_save_preferences()
		if screen == "settings": _show_settings()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if smoke_mode and what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN]: return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(menus):
		menus.visible = true
		_escape()
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if not is_instance_valid(battle): return
		_application_suspended = true
		_resume_after_foreground = screen == "battle"
		if is_instance_valid(touch_controls): touch_controls.clear()
		if _resume_after_foreground:
			battle.set_paused(true)
			music.set_paused(true)
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		if not _application_suspended or not is_instance_valid(battle): return
		_application_suspended = false
		if _resume_after_foreground and screen == "battle":
			battle.begin_reentry()
			music.set_paused(false)
		_resume_after_foreground = false

func _find_button(node: Node, text: String) -> Button:
	if node is Control and not node.is_visible_in_tree(): return null
	if node is Button and node.text.to_lower().contains(text.to_lower()): return node
	if node is Button:
		for child: Node in node.get_children():
			if child is Label and child.text.to_lower().contains(text.to_lower()): return node
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null: return found
	return null

func _capture(name: String) -> void:
	if capture_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(capture_dir.path_join(name+".png"))

func _smoke_test() -> void:
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	await get_tree().create_timer(0.3).timeout
	_title_gate()
	await _capture("01-title")
	_action("enter_frontend")
	await _capture("01a-workbench")
	_action("practice_garage")
	await get_tree().create_timer(0.15).timeout
	await _capture("02-garage")
	for pair: Array in [["blade", "HOOK"], ["ratchet", "HIGH"], ["bit", "RUBBER"]]:
		menus._catalogue_tabs[pair[0]].pressed.emit()
		await get_tree().process_frame
		var part_name: String = pair[1]
		var part_button: Button = _find_button(menus, part_name)
		assert(part_button != null, "Garage button present: "+part_name)
		part_button.pressed.emit()
	assert(build.blade == "hook" and build.ratchet == "high" and build.bit == "rubber")
	await get_tree().create_timer(0.15).timeout
	await _capture("03-custom-build")
	_action("help")
	await _capture("04-help")
	_action("settings")
	await _capture("05-settings")
	_action("quick_duel")
	await get_tree().create_timer(3.5).timeout
	await _capture("06-battle")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = true
	var before_position: Vector2 = battle.player_entity().pos
	Input.parse_input_event(key)
	await get_tree().create_timer(0.6).timeout
	key = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = false
	Input.parse_input_event(key)
	var after_position: Vector2 = battle.player_entity().pos
	print("INPUT_SMOKE screen_dx="+str((after_position.x-after_position.y)-(before_position.x-before_position.y)))
	await get_tree().create_timer(4.0).timeout
	await _capture("06b-live-battle")
	_pause()
	await _capture("07-pause")
	_resume()
	await get_tree().create_timer(0.15).timeout
	_round_finished({"won":true, "reason":"ring_out", "duration":28.4, "hits":9, "player_remaining":0.43, "enemy_remaining":0.0})
	await _capture("08-victory")
	_action("main_menu")
	_action("start_run")
	await _capture("09-starters")
	_action("select_first_starter", "breaker")
	await _capture("09a-confirm")
	_action("confirm_first_starter", "breaker")
	await _capture("09b-owned")
	await get_tree().create_timer(1.6).timeout
	assert(screen == "garage" and collection.owned_count() == 3)
	await _capture("09c-owned-workshop")
	_action("launch_owned_run")
	await _capture("10-starting-draft")
	var reroll_button: Button = menus._content.get_node("RerollPower")
	assert(not reroll_button.disabled and run_context.reroll_charges == 1)
	reroll_button.pressed.emit()
	assert(screen == "reward" and run_context.reroll_charges == 0 and int(run_context.reroll_snapshot().revision) == 1)
	await _capture("10a-rerolled-draft")
	_action("choose_power", {"encounter_id":run_context.pending_draft_id,"power_id":run_context.pending_offer[0],"run_seed":run_context.run_seed,"offer_revision":run_context.reroll_snapshot().revision})
	await _capture("11-starting-acquisition")
	await get_tree().create_timer(0.6).timeout
	for slot: int in range(1, 11):
		assert(run_context.slot == slot and screen == "battle")
		await _capture("run-%02d-hud" % slot)
		# Synthetic threshold fixtures exercise UI flow, never play balance.
		if not run_context.progression_snapshot().maxed:
			var contact_time: float = battle.elapsed
			var fixture_id: int = slot * 10000
			while run_context.pending_offer.is_empty():
				contact_time += 1.2
				fixture_id += 1
				run_context.award_xp({"kind":"collision","encounter_id":run_context.current_encounter().id,"event_id":fixture_id,"time":contact_time,"first_entity_id":1,"second_entity_id":2,"player_attributed":true,"severity":0.8})
			_progression_events([])
			await get_tree().create_timer(0.2).timeout
			await _capture("run-%02d-midbattle-draft" % slot)
			var offer: Array = run_context.pending_offer
			_pause()
			_resume()
			assert(offer == run_context.pending_offer)
			_action("choose_power", {"encounter_id":run_context.pending_draft_id,"power_id":offer[0],"run_seed":run_context.run_seed})
			if screen == "mutation":
				await _capture("run-%02d-mutation" % slot)
				_action("choose_mutation", {"encounter_id":run_context.pending_draft_id,"branch_id":run_context.pending_mutation_offer[0],"run_seed":run_context.run_seed})
			await _capture("run-%02d-acquired" % slot)
			await get_tree().create_timer(1.1).timeout
			assert(screen == "battle" and run_context.slot == slot)
		_smoke_clear_threat()
		await _capture("run-%02d-continuing" % slot)
		assert(screen == "battle" and run_context.is_active() and run_context.slot == slot + 1)
	assert(run_context.slot == 11)
	await _capture("run-past-eight")
	battle.player_entity().outcome = "spin_out"
	battle._check_result()
	battle._update_finish(3.0)
	assert(screen == "result" and run_context.status == "failed")
	_action("restart_run")
	_action("choose_power", {"encounter_id":run_context.pending_draft_id,"power_id":run_context.pending_offer[0],"run_seed":run_context.run_seed})
	await get_tree().create_timer(0.6).timeout
	battle.player_entity().outcome = "ring_out"
	battle._check_result()
	battle._update_finish(3.0)
	await _capture("run-failed")
	_action("restart_run")
	_pause()
	_action("end_run")
	assert(run_context.status == "empty" and screen == "garage")
	if not await _smoke_shop_progression(): return
	print("INTEGRATION_SMOKE_PASS actions="+str(audit_actions)+" continuous_threats=10 one_launch_per_run (flow fixtures)")
	get_tree().quit()

func _smoke_shop_require(condition: bool, description: String) -> bool:
	# Release exports remove assert expressions, so these checks must execute.
	if condition: return true
	push_error("SHOP_PROGRESSION_SMOKE_FAIL " + description)
	get_tree().quit(1)
	return false

func _smoke_shop_progression() -> bool:
	# Explicit packaged flow fixture. Real earned gameplay is captured separately.
	if not _smoke_shop_require(smoke_mode and _is_isolated_qa_path(collection_path, "temp"), "isolated boundary"): return false
	if not _smoke_shop_require(collection.owned_count() == 3 and collection.credits == 0, "starter wallet"): return false
	var started: Dictionary = collection.begin_reward_run()
	if not _smoke_shop_require(bool(started.ok), "fixture run nonce"): return false
	var outcome: Dictionary = {"reward_provenance":"earned-clear-v1", "reward_fixture":false, "aborted":false, "earned_threats_cleared":4, "earned_elites_cleared":0, "earned_bosses_cleared":0}
	var funded: Dictionary = collection.pay_run_reward(str(started.run_id), outcome)
	if not _smoke_shop_require(bool(funded.ok) and collection.credits == 48, "saved fixture funding"): return false
	packet_rng_override = RandomNumberGenerator.new()
	packet_rng_override.seed = 19
	print("SHOP_QA_FIXTURE isolated saved clear records and packet seed19 fund flow; not earned gameplay evidence")
	_action("open_shop")
	if not _smoke_shop_require(screen == "shop", "shop route"): return false
	await _capture("003a-shop")
	_action("packet_odds")
	if not _smoke_shop_require(screen == "packet_odds", "odds route"): return false
	await _capture("003a-odds")
	_action("open_shop")
	_action("request_packet_purchase", "standard")
	_action("confirm_packet_purchase", _packet_purchase_token)
	if not _smoke_shop_require(screen == "packet_open" and collection.credits == 0, "actual packet debit and route"): return false
	var receipt: Dictionary = collection.pending_packet()
	if not _smoke_shop_require(str(receipt.get("status", "")) == "resolved" and receipt.get("rows", []).size() == 3, "fixed resolved receipt"): return false
	_action("packet_tear")
	await get_tree().create_timer(2.5).timeout
	if not _smoke_shop_require(is_instance_valid(menus._packet_view) and menus._packet_view.phase == "RESULT", "physical result"): return false
	await _capture("003a-packet-result")
	_action("packet_workshop")
	if not _smoke_shop_require(screen == "garage" and collection.pending_packet().is_empty() and collection.owned_count() > 3, "acquired workshop route"): return false
	var new_equipped: bool = false
	for row: Dictionary in receipt.rows:
		if bool(row.new):
			_action("equip_part", {"category":row.category, "id":row.id})
			new_equipped = collection.equipped_build()[row.category] == row.id
			break
	if not _smoke_shop_require(new_equipped, "new design actually equipped"): return false
	await _capture("003a-acquired-workshop")
	_action("launch_owned_run")
	if not _smoke_shop_require(screen == "reward", "new machine launch"): return false
	_action("end_run")
	print("SHOP_PROGRESSION_SMOKE_PASS fixed_receipt=3 new_design_equipped=1 (flow fixture)")
	return true

func _smoke_clear_threat() -> void:
	# Controlled outcome fixture only; real combat is measured separately.
	battle.battle_status = "battle"
	battle._progression_contacted.clear()
	for f: Dictionary in battle.fighters:
		if f.team_id != "hostile": continue
		f.player_cause = {}
		f.outcome = "natural_retirement" if f.combatant_type == "small_top" else "spin_out"
	if battle.swarm.enabled:
		for entry: Dictionary in battle.swarm.schedule:
			if entry.state not in ["spawned", "cancelled"]:
				entry.state = "cancelled"
				battle.swarm.cancelled += 1
		battle.swarm.wave = battle.swarm.total_waves
	battle._check_result()
	battle._collect_progression_outcomes()
	battle.continuous.after_tick(0.0)
	battle.continuous._spawn_next()
