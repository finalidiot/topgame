extends Node2D

const BattleScript = preload("res://scripts/battle.gd")
const MenuScript = preload("res://scripts/menus.gd")
const SoundScript = preload("res://scripts/sound.gd")
const Catalog = preload("res://scripts/parts.gd")
const RunContext = preload("res://scripts/run_context.gd")
const Starters = preload("res://scripts/starters.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Collection = preload("res://scripts/collection_save.gd")

var build: Dictionary = {"blade":"balance", "ratchet":"mid", "bit":"ball"}
var settings: Dictionary = {"volume":0.65, "muted":false, "screen_shake":true, "fullscreen":false}
var mode: String = "duel"
var round_index: int = 0
var screen: String = "title"
var last_result: Dictionary = {}
var battle: Node2D
var menus: Control
var sounds: Node
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var smoke_mode: bool = false
var review_audio: bool = false
## Tests/review captures override the path before entering the scene tree.
var collection_path: String = ""
var collection: RefCounted
var reset_collection_requested: bool = false
var _collection_reset_failed: bool = false
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

func _process(delta: float) -> void:
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
	rng.randomize()
	var practice_request: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--smoke-test": smoke_mode = true
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
		if argument.begins_with("--practice="): practice_request = argument.trim_prefix("--practice=")
		if argument.begins_with("--collection-path="): collection_path = argument.trim_prefix("--collection-path=")
		if argument == "--reset-collection": reset_collection_requested = true
	if smoke_mode: rng.seed = 7341
	if not smoke_mode: _load_preferences()
	if collection_path.is_empty():
		collection_path = "user://test_collection/main_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()] if smoke_mode else "user://collection.json"
	collection = Collection.new(collection_path)
	collection.load_save()
	if reset_collection_requested:
		_collection_reset_failed = not bool(collection.reset_collection(true).ok)
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
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	menus = MenuScript.new()
	layer.add_child(menus)
	menus.action.connect(_action)
	menus.focus_sound.connect(_battle_sound)
	sounds = SoundScript.new()
	add_child(sounds)
	_apply_settings()
	_title()
	if _collection_reset_failed:
		_collection_error("The explicitly requested collection reset could not finish. Close other game instances and check the save folder before retrying.")
	if smoke_mode: call_deferred("_smoke_test")
	elif not practice_request.is_empty(): call_deferred("_start_build_practice", practice_request)

## Optional isolated human checkpoint. Ordinary seeded Run offers are untouched.
## No progression, power procs, damage or victories are injected while playing.
func _start_build_practice(branch_id: String) -> void:
	if not Powers.MUTATIONS.has(branch_id) and branch_id != "hybrid": return
	_clear_run()
	_practice_branch = branch_id
	var power_id: String = str(Powers.get_mutation(branch_id).get("power_id", "dead_centre"))
	var starter: String = {"redline":"breaker", "dead_centre":"bastion", "afterimage":"vane"}.get(power_id, "bastion")
	var descriptor: Dictionary = Encounters.for_slot(3 if power_id == "afterimage" else 5, 421)
	descriptor.player_power_ids = Powers.ACTIVE_IDS.duplicate()
	descriptor.player_power_ranks = {}
	descriptor.player_power_mutations = {}
	for id: String in Powers.ACTIVE_IDS: descriptor.player_power_ranks[id] = 1
	if branch_id == "hybrid":
		for id: String in ["redline", "dead_centre", "afterimage"]: descriptor.player_power_ranks[id] = 3
		descriptor.player_power_mutations = {"redline":"runaway", "dead_centre":"counterweight", "afterimage":"slipstream"}
	else:
		descriptor.player_power_ranks[power_id] = 3
		descriptor.player_power_mutations[power_id] = branch_id
	descriptor.starter_id = starter
	mode = "duel"
	screen = "battle"
	last_result.clear()
	battle.visible = true
	battle.set_physics_process(true)
	battle.begin_encounter(Starters.build_for(starter), descriptor)
	_apply_settings()
	battle._emit_hud()

func _load_preferences() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load("user://prototype.cfg") != OK: return
	for key: String in build:
		var value: String = str(cfg.get_value("build", key, build[key]))
		var legal: Array = Catalog.BLADE_IDS if key == "blade" else Catalog.RATCHET_IDS if key == "ratchet" else Catalog.BIT_IDS
		if value in legal: build[key] = value
	for key: String in settings:
		settings[key] = cfg.get_value("settings", key, settings[key])
	settings.volume = clampf(float(settings.volume), 0.0, 1.0)

func _save_preferences() -> void:
	if smoke_mode: return
	var cfg: ConfigFile = ConfigFile.new()
	for key: String in build: cfg.set_value("build", key, build[key])
	for key: String in settings: cfg.set_value("settings", key, settings[key])
	cfg.save("user://prototype.cfg")

func _apply_settings() -> void:
	sounds.apply_settings(settings)
	battle.screen_shake_enabled = bool(settings.screen_shake)
	if not smoke_mode:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)

func _hide_battle() -> void:
	battle.set_paused(true)
	battle.set_physics_process(false)
	battle.visible = false

func _title() -> void:
	if run_context.is_active(): return
	_clear_run()
	_hide_battle()
	screen = "title"
	menus.show_collection_title(collection.equipped_build(), settings, collection.is_initialized())

func _garage() -> void:
	if run_context.is_active(): return
	if not collection.is_initialized():
		_begin_collection()
		return
	_clear_run()
	_hide_battle()
	screen = "garage"
	if collection.can_launch(): build = collection.equipped_build()
	var snapshot: Dictionary = collection.snapshot()
	snapshot["build_identity"] = Starters.identity_for_build(collection.equipped_build())
	menus.show_collection_workshop(collection.equipped_build(), snapshot)

func _practice_garage() -> void:
	if run_context.is_active(): return
	_clear_run()
	_hide_battle()
	screen = "practice_garage"
	menus.show_garage(build, true)

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

func _clear_run() -> void:
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
	if not collection.is_initialized():
		_begin_collection()
		return
	if not collection.can_launch():
		_collection_error("This collection has no complete owned assembly. Your known parts are preserved. See the checkpoint recovery instructions.")
		return
	_restart_run()

func _restart_run() -> void:
	if not collection.can_launch(): return
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
	_previous_run_seed = fresh_seed
	_acquisition_remaining = 0.0
	_level_up_remaining = 0.0
	_acquired_power_id = ""
	_reward_focus_id = ""
	_draft_resume_origin = "starting"
	run_context.start(selected, fresh_seed, identity)
	mode = "run"
	_hide_battle()
	_show_reward()

func _launch_run_encounter() -> void:
	if not run_context.is_active() or _run_launched: return
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
	_apply_settings()
	battle._emit_hud()

func _show_reward() -> void:
	if not run_context.is_active() or run_context.pending_offer.is_empty(): return
	screen = "reward"
	battle.set_paused(true)
	var starting: bool = run_context.pending_draft_kind == "starting"
	var context: Dictionary = {"title":"CHOOSE YOUR FIRST POWER" if starting else "LEVEL %d / CHOOSE A POWER" % run_context.pending_draft_level,
		"subtitle":"Enter the arena already dangerous." if starting else "Battle paused. Add a power or invest in one you own.",
		"resume_label":_acquisition_prompt(), "power_ranks":run_context.power_ranks, "power_mutations":run_context.power_mutations}
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
	battle._emit_hud()

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
		battle.set_paused(false)
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
	stats = stats.duplicate()
	stats["run_label"] = "THREAT %d" % run_context.slot if mode == "run" else "DUEL"
	stats["owned_power_ids"] = run_context.owned_power_ids if mode == "run" else []
	stats["power_ranks"] = run_context.power_ranks if mode == "run" else {}
	stats["power_mutations"] = run_context.power_mutations if mode == "run" else {}
	stats["is_run"] = mode == "run"
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
		if not smoke_mode:
			var diagnostic: FileAccess = FileAccess.open("user://last_run_director.json",FileAccess.WRITE)
			if diagnostic != null: diagnostic.store_string(JSON.stringify(last_result,"\t"))
	menus.show_result(last_result)

func _battle_sound(kind: String) -> void:
	if not smoke_mode or review_audio: sounds.play_sound(kind)

func _action(name: String, value: Variant = null) -> void:
	audit_actions.append(name)
	# All build/menu routes respect the lock, including stale UI signals.
	if run_context.is_active() and name in ["quick_duel", "start_battle", "start_run", "customize", "build_changed", "help", "settings", "main_menu", "rematch", "begin_collection", "open_workshop", "practice_garage", "equip_part", "launch_owned_run", "select_first_starter", "confirm_first_starter", "finish_ownership"]: return
	_battle_sound("ui")
	match name:
		"begin_collection": _begin_collection()
		"open_workshop": _garage()
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
		"start_run": _start_run()
		"restart_run":
			if mode == "run" and screen in ["pause", "result"]: _restart_run()
		"end_run":
			if mode == "run":
				_clear_run()
				last_result.clear()
				_garage()
		"choose_power":
			if mode == "run" and screen == "reward" and value is Dictionary:
				if int(value.get("run_seed", -1)) != run_context.run_seed: return
				if run_context.choose_power(str(value.get("encounter_id", "")), str(value.get("power_id", ""))):
					if not run_context.pending_mutation_power.is_empty():
						_mutation_focus_id = ""
						_show_mutation()
					else:
						if _draft_resume_origin == "battle": battle.acquire_run_power(str(value.power_id), int(run_context.power_ranks.get(str(value.power_id), 1)))
						if not smoke_mode: sounds.play_sound("card_select")
						_show_acquisition(str(value.power_id))
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
			_hide_battle()
			screen = "settings"
			menus.show_settings(settings)
		"main_menu": _title()
		"build_changed":
			if screen == "practice_garage" and value is Dictionary:
				build = Catalog.validate_build(value)
				_save_preferences()
		"settings_changed":
			if value is Dictionary:
				settings.merge(value, true)
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
	screen = "pause"
	battle.set_paused(true)
	menus.show_pause(mode == "run")

func _resume() -> void:
	if screen != "pause": return
	screen = pause_origin
	if screen == "reward": _show_reward()
	elif screen == "mutation": _show_mutation(false)
	elif screen == "acquisition": menus.show_acquisition(_acquired_power_id, _acquisition_prompt(), int(run_context.power_ranks.get(_acquired_power_id, 1)), str(run_context.power_mutations.get(_acquired_power_id, "")))
	elif screen == "result": menus.show_result(last_result)
	elif screen == "level_up": menus.show_level_up(run_context.pending_draft_level)
	else:
		battle.set_paused(false)
		battle._emit_hud()

func _escape() -> void:
	if screen == "pause": _resume()
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
		settings.fullscreen = not bool(settings.fullscreen)
		_apply_settings()
		_save_preferences()
		if screen == "settings": menus.show_settings(settings)
		get_viewport().set_input_as_handled()

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text.to_lower().contains(text.to_lower()): return node
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
	await _capture("01-title")
	_action("practice_garage")
	await get_tree().create_timer(0.15).timeout
	await _capture("02-garage")
	for part_name: String in ["HOOK", "HIGH", "RUBBER"]:
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
	_action("choose_power", {"encounter_id":run_context.pending_draft_id,"power_id":run_context.pending_offer[0],"run_seed":run_context.run_seed})
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
	print("INTEGRATION_SMOKE_PASS actions="+str(audit_actions)+" continuous_threats=10 one_launch_per_run (flow fixtures)")
	get_tree().quit()

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
