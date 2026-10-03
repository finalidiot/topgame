extends Node2D

const BattleScript = preload("res://scripts/battle.gd")
const MenuScript = preload("res://scripts/menus.gd")
const SoundScript = preload("res://scripts/sound.gd")
const Catalog = preload("res://scripts/parts.gd")
const RunContext = preload("res://scripts/run_context.gd")

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
var capture_dir: String = ""
var audit_actions: Array = []
var opponent_build: Dictionary = {}
var run_context = RunContext.new()
var pause_origin: String = "battle"
var _previous_run_seed: int = 0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rng.randomize()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--smoke-test": smoke_mode = true
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	if smoke_mode: rng.seed = 7341
	if not smoke_mode: _load_preferences()
	battle = BattleScript.new()
	add_child(battle)
	battle.visible = false
	battle.set_physics_process(false)
	battle.round_finished.connect(_round_finished)
	battle.hud_updated.connect(_hud_updated)
	battle.event_sfx.connect(_battle_sound)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	menus = MenuScript.new()
	layer.add_child(menus)
	menus.action.connect(_action)
	sounds = SoundScript.new()
	add_child(sounds)
	_apply_settings()
	_title()
	if smoke_mode: call_deferred("_smoke_test")

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
	menus.show_title(build, settings)

func _garage() -> void:
	if run_context.is_active(): return
	_clear_run()
	_hide_battle()
	screen = "garage"
	menus.show_garage(build)

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
	run_context.clear()
	mode = "duel"
	round_index = 0
	pause_origin = "battle"

func _start_run() -> void:
	if run_context.is_active(): return
	_restart_run()

func _restart_run() -> void:
	# Entropy is sampled only here, never from menu duration or encounter timing.
	var selected: Dictionary = build if run_context.status == "empty" else run_context.selected_build
	var fresh_seed: int = rng.randi()
	while fresh_seed == 0 or fresh_seed == _previous_run_seed:
		fresh_seed = rng.randi()
	_previous_run_seed = fresh_seed
	run_context.start(selected, fresh_seed)
	_launch_run_encounter()

func _launch_run_encounter() -> void:
	if not run_context.is_active(): return
	var encounter: Dictionary = run_context.current_encounter()
	mode = "run"
	round_index = run_context.slot - 1
	opponent_build = encounter.opponent_build.duplicate(true)
	last_result.clear()
	screen = "battle"
	battle.visible = true
	battle.set_physics_process(true)
	battle.begin_encounter(run_context.selected_build, encounter)
	_apply_settings()
	battle._emit_hud()

func _show_reward() -> void:
	if not run_context.is_active() or run_context.pending_offer.is_empty(): return
	screen = "reward"
	battle.set_paused(true)
	menus.show_reward(run_context.pending_offer, run_context.owned_power_ids, run_context.slot, run_context.current_encounter().id, run_context.run_seed)

func _advance_run() -> void:
	if run_context.advance(): _launch_run_encounter()

func _hud_updated(stats: Dictionary) -> void:
	if screen != "battle": return
	stats = stats.duplicate()
	stats["run_label"] = "RUN %d / 8" % run_context.slot if mode == "run" else "DUEL"
	stats["owned_power_ids"] = run_context.owned_power_ids if mode == "run" else []
	stats["is_run"] = mode == "run"
	menus.show_hud(stats)

func _round_finished(result: Dictionary) -> void:
	if screen != "battle": return
	if mode == "run":
		var encounter: Dictionary = run_context.current_encounter()
		# Reject delayed results from an earlier slot or a discarded run.
		if result.get("encounter_id", "") != encounter.id or int(result.get("seed", -1)) != int(encounter.seed): return
		if not run_context.commit_result(encounter.id, bool(result.get("won", false))): return
	screen = "result"
	battle.set_paused(true)
	last_result = result.duplicate(true)
	if not smoke_mode: sounds.play_sound("win" if bool(result.get("won", false)) else "loss")
	last_result["is_run"] = mode == "run"
	last_result["next_available"] = mode == "run" and run_context.is_active() and run_context.pending_offer.is_empty()
	last_result["run_label"] = "RUN %d / 8" % run_context.slot if mode == "run" else "DUEL"
	if mode == "run":
		if not run_context.pending_offer.is_empty():
			_show_reward()
			return
		if run_context.status == "complete":
			last_result["title"] = "RUN CLEARED"
			last_result["subtitle"] = "Eight duels complete. Six powers collected."
		elif run_context.status == "failed":
			last_result["title"] = "RUN ENDED"
			last_result["subtitle"] = "Restart from encounter 1 with the same assembly."
	menus.show_result(last_result)

func _battle_sound(kind: String) -> void:
	if not smoke_mode: sounds.play_sound(kind)

func _action(name: String, value: Variant = null) -> void:
	audit_actions.append(name)
	# All build/menu routes respect the lock, including stale UI signals.
	if run_context.is_active() and name in ["quick_duel", "start_battle", "start_run", "customize", "build_changed", "help", "settings", "main_menu", "rematch"]: return
	if not smoke_mode: sounds.play_sound("ui")
	match name:
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
				if run_context.choose_power(str(value.get("encounter_id", "")), str(value.get("power_id", ""))): _advance_run()
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
			if screen == "garage" and value is Dictionary:
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
			if mode == "duel" and screen in ["pause", "result"]: _start_battle("duel", true, true)
		"next_battle":
			if mode == "run" and screen == "result" and bool(last_result.get("next_available", false)): _advance_run()
		"quit": get_tree().quit()

func _pause() -> void:
	if screen != "battle" and not (run_context.is_active() and screen in ["reward", "result"]): return
	pause_origin = screen
	screen = "pause"
	battle.set_paused(true)
	menus.show_pause(mode == "run")

func _resume() -> void:
	if screen != "pause": return
	screen = pause_origin
	if screen == "reward": _show_reward()
	elif screen == "result": menus.show_result(last_result)
	else:
		battle.set_paused(false)
		battle._emit_hud()

func _escape() -> void:
	if screen == "pause": _resume()
	elif screen == "battle" or run_context.is_active(): _pause()
	else: _title()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
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
	var button: Button = _find_button(menus, "custom")
	if button != null: button.pressed.emit()
	else: _action("customize")
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
	for slot: int in range(1, 9):
		assert(run_context.slot == slot)
		await _capture("run-%02d-hud" % slot)
		var encounter: Dictionary = run_context.current_encounter()
		_round_finished({"won":true, "reason":"ring_out", "duration":28.4, "hits":9, "player_remaining":0.43, "encounter_id":encounter.id, "seed":encounter.seed})
		if screen == "reward":
			await _capture("run-%02d-reward" % slot)
			var offer: Array = run_context.pending_offer
			_escape()
			await _capture("run-%02d-pause" % slot)
			_escape()
			assert(offer == run_context.pending_offer)
			var card: Button = get_viewport().gui_get_focus_owner() as Button
			assert(card != null)
			card.pressed.emit()
		elif slot == 5:
			await _capture("run-05-result")
			_action("next_battle")
	assert(run_context.status == "complete" and run_context.owned_power_ids.size() == 6)
	await _capture("run-complete")
	_action("restart_run")
	var failed_encounter: Dictionary = run_context.current_encounter()
	_round_finished({"won":false, "reason":"spin_out", "duration":30.0, "encounter_id":failed_encounter.id, "seed":failed_encounter.seed})
	await _capture("run-failed")
	_action("restart_run")
	_pause()
	await _capture("run-battle-pause")
	_action("end_run")
	assert(run_context.status == "empty" and screen == "garage")
	print("INTEGRATION_SMOKE_PASS actions="+str(audit_actions)+" run_slots=8 drafts=6 (flow fixtures)")
	get_tree().quit()
