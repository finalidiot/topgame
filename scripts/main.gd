extends Node2D

const BattleScript = preload("res://scripts/battle.gd")
const MenuScript = preload("res://scripts/menus.gd")
const SoundScript = preload("res://scripts/sound.gd")
const Catalog = preload("res://scripts/parts.gd")

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

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rng.randomize()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--smoke-test": smoke_mode = true
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
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
	_hide_battle()
	screen = "title"
	menus.show_title(build, settings)

func _garage() -> void:
	_hide_battle()
	screen = "garage"
	menus.show_garage(build)

func _opponent() -> Dictionary:
	if mode == "gauntlet":
		return [
			{"blade":"smash", "ratchet":"low", "bit":"flat"},
			{"blade":"hook", "ratchet":"high", "bit":"rubber"},
			{"blade":"guard", "ratchet":"mid", "bit":"needle"}
		][mini(round_index, 2)].duplicate()
	var rivals: Array = [
		{"blade":"smash", "ratchet":"low", "bit":"flat"},
		{"blade":"guard", "ratchet":"mid", "bit":"needle"},
		{"blade":"hook", "ratchet":"mid", "bit":"rubber"},
		{"blade":"balance", "ratchet":"high", "bit":"ball"}
	]
	return rivals[rng.randi_range(0, rivals.size()-1)].duplicate()

func _start_battle(selected_mode: String = "duel", next: bool = false, replay: bool = false) -> void:
	mode = selected_mode
	if not next and not replay: round_index = 0
	if not replay or opponent_build.is_empty(): opponent_build = _opponent()
	last_result.clear()
	screen = "battle"
	battle.visible = true
	battle.set_physics_process(true)
	battle.set_paused(false)
	battle.begin(build.duplicate(), opponent_build.duplicate(), round_index+1 if mode == "gauntlet" else 1, 7341+round_index if smoke_mode else rng.randi())
	_apply_settings()
	menus.show_hud({"player_rpm":1.0, "enemy_rpm":1.0, "status":"countdown", "countdown":3, "player_name":Catalog.title(build), "enemy_name":"RIVAL", "time_left":60.0, "burst_ready":true, "burst_cooldown":0.0})

func _hud_updated(stats: Dictionary) -> void:
	if screen != "battle": return
	stats = stats.duplicate()
	stats["run_label"] = "DUEL" if mode == "duel" else "GAUNTLET %d / 3" % (round_index+1)
	menus.show_hud(stats)

func _round_finished(result: Dictionary) -> void:
	screen = "result"
	battle.set_paused(true)
	last_result = result.duplicate()
	if not smoke_mode: sounds.play_sound("win" if bool(result.get("won", false)) else "loss")
	last_result["next_available"] = bool(result.get("won", false)) and mode == "gauntlet" and round_index < 2
	last_result["run_label"] = "DUEL" if mode == "duel" else "GAUNTLET %d / 3" % (round_index+1)
	if mode == "gauntlet" and round_index == 2 and bool(result.get("won", false)):
		last_result["title"] = "GAUNTLET CLEARED"
	menus.show_result(last_result)

func _battle_sound(kind: String) -> void:
	if not smoke_mode: sounds.play_sound(kind)

func _action(name: String, value: Variant = null) -> void:
	audit_actions.append(name)
	if not smoke_mode: sounds.play_sound("ui")
	match name:
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
			if value is Dictionary:
				build = value.duplicate()
				_save_preferences()
		"settings_changed":
			if value is Dictionary:
				settings.merge(value, true)
				_apply_settings()
				_save_preferences()
		"pause": _pause()
		"resume": _resume()
		"rematch":
			if str(last_result.get("title", "")) == "GAUNTLET CLEARED": _start_battle(mode)
			else: _start_battle(mode, true, true)
		"next_battle":
			if bool(last_result.get("next_available", false)):
				round_index += 1
				_start_battle("gauntlet", true)
		"quit": get_tree().quit()

func _pause() -> void:
	if screen != "battle": return
	battle.set_paused(true)
	screen = "pause"
	menus.show_pause()

func _resume() -> void:
	if screen != "pause": return
	screen = "battle"
	battle.set_paused(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if screen == "battle": _pause()
			elif screen == "pause": _resume()
			else: _title()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F11:
			settings.fullscreen = not bool(settings.fullscreen)
			_apply_settings()
			_save_preferences()
			if screen == "settings": menus.show_settings(settings)

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
	_action("start_battle", "gauntlet")
	await get_tree().create_timer(3.5).timeout
	await _capture("06-battle")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = true
	var before_position: Vector2 = battle.fighters[0].pos
	Input.parse_input_event(key)
	await get_tree().create_timer(0.6).timeout
	key = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = false
	Input.parse_input_event(key)
	var after_position: Vector2 = battle.fighters[0].pos
	print("INPUT_SMOKE screen_dx="+str((after_position.x-after_position.y)-(before_position.x-before_position.y)))
	await get_tree().create_timer(4.0).timeout
	await _capture("06b-live-battle")
	_pause()
	await _capture("07-pause")
	_resume()
	await get_tree().create_timer(0.15).timeout
	_round_finished({"won":true, "reason":"ring_out", "duration":28.4, "hits":9, "player_remaining":0.43, "enemy_remaining":0.0})
	await _capture("08-victory")
	_action("next_battle")
	await get_tree().create_timer(0.1).timeout
	assert(round_index == 1)
	print("INTEGRATION_SMOKE_PASS actions="+str(audit_actions)+" gauntlet_round="+str(round_index))
	get_tree().quit()
