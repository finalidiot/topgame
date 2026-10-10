extends SceneTree
## RPM attachment, deterministic crowds, edge layout and isolated option migration.
const Bars = preload("res://scripts/top_status_bars.gd")
const Layout = preload("res://scripts/combat_hud_layout.gd")
const Meters = preload("res://scripts/power_state_meters.gd")
const Menus = preload("res://scripts/menus.gd")
const Save = preload("res://scripts/collection_save.gd")
const Touch = preload("res://scripts/touch_controls.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _battle_sound(_kind: String) -> void: pass
var checks: int = 0
var failures: Array[String] = []
var report: String = ""
var measurements: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func body(id: int, pos: Vector2, rpm: float = 1.0, kind: String = "rival") -> Dictionary:
	return {"entity_id": id, "pos": pos, "rpm": rpm, "height": 0.0, "outcome": "", "combatant_type": "full_top", "enemy_kind": kind}
func settle() -> void:
	await process_frame; await process_frame

func joy_tap(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = 7; event.button_index = button; event.pressed = true
	Input.parse_input_event(event); await settle()
	event = InputEventJoypadButton.new()
	event.device = 7; event.button_index = button; event.pressed = false
	Input.parse_input_event(event); await settle()

func navigate_status_option(app: Node2D, profile_id: String) -> bool:
	for press: int in range(16):
		var focused: Control = root.gui_get_focus_owner()
		if is_instance_valid(focused) and str(focused.get_meta("setting_key", "")) == "top_status_bars":
			check(Rect2(80,60,640,360).encloses(focused.get_global_rect()), "Focused status option stays visible inside native menu for " + profile_id)
			return true
		# The paired comfort row has Impact Numbers directly under the rightward
		# toggle column; a normal left press reaches Top Status Bars in that row.
		await joy_tap(JOY_BUTTON_DPAD_LEFT if is_instance_valid(focused) and str(focused.get_meta("setting_key", "")) == "impact_numbers" else JOY_BUTTON_DPAD_DOWN)
	check(false, "Controller can reach status option with ordinary D-pad traversal for " + profile_id)
	return false

func controller_options(app: Node2D) -> void:
	var evidence: Array[Dictionary] = []
	for profile_id: String in ["xbox", "nintendo", "playstation"]:
		app._action("settings_changed", {"controller_layout": profile_id, "top_status_bars": true})
		app._title(); app._action("settings"); await settle()
		check(app.menus.screen == "settings", "Options opens under controller layout " + profile_id)
		if await navigate_status_option(app, profile_id):
			await joy_tap(Bindings.confirm_button(profile_id))
			check(not app.settings.top_status_bars and not app.top_status_bars.visible, "Printed Confirm toggles status bars OFF for " + profile_id)
			await joy_tap(Bindings.confirm_button(profile_id))
			check(app.settings.top_status_bars and app.top_status_bars.visible, "Printed Confirm toggles status bars ON for " + profile_id)
		for node: Node in app.menus._content.get_children():
			if node is Button or node is HSlider: check(Rect2(80,60,640,360).encloses(node.get_global_rect()), "Options control stays within centred native menu for " + profile_id)
		await joy_tap(Bindings.back_button(profile_id))
		check(app.screen == "title", "Printed Back leaves Options without triggering Confirm for " + profile_id)
		evidence.append({"profile": profile_id, "confirm_button": Bindings.confirm_button(profile_id), "back_button": Bindings.back_button(profile_id), "synthetic_logical_device": 7, "physical_hardware": "Not tested by this fixture"})
	app._action("settings_changed", {"controller_layout": "nintendo"})
	measurements.controller_option_profiles = evidence

func attachment_and_crowds() -> void:
	var fighter: Dictionary = body(1, Vector2.ZERO, 0.62)
	var original: Dictionary = fighter.duplicate(true)
	var d: Dictionary = Bars.layout([fighter], 1)
	check(d.bars.size() == 1 and d.bars[0].rect == Rect2(303, 132, 34, 5), "Player reserve bar sits above stable native ground pivot")
	check(d.bars[0].value == 0.62 and not d.bars[0].overdrive, "Bar uses actual reserve rather than separate HP")
	check(fighter == original, "Attachment has no fighter mutation")
	check(Bars.layout([fighter], 1, false, Vector2(4, -2)).bars[0].rect == Rect2(307, 130, 34, 5), "Bar follows the canonical arena shake instead of floating against its rig")
	fighter.rpm = 1.24
	check(Bars.layout([fighter], 1).bars[0].value == 1.0 and Bars.layout([fighter], 1).bars[0].overdrive, "True overcap reserves fill normal bar and use a small upper edge")
	for offset: Vector2 in [Vector2(0.4, 0.2), Vector2(18, 21), Vector2(-23, 15)]:
		fighter.pos = offset
		var bar: Dictionary = Bars.layout([fighter], 1).bars[0]
		check(bar.contact == Vector2(320 + offset.x - offset.y, 165 + (offset.x + offset.y) * 0.5).round(), "Bar follows actual rounded projection without cosmetic wobble")
	fighter.pos = Vector2.ZERO; fighter.height = 8
	check(Bars.layout([fighter], 1).bars[0].contact == Vector2(320, 157), "Height attachment stays with lifted live top")
	var retired: Dictionary = body(2, Vector2.ZERO); retired.outcome = "ring_out"
	var small: Dictionary = body(3, Vector2.ZERO); small.combatant_type = "small_top"
	var dead: Dictionary = body(4, Vector2.ZERO, 0)
	var outside: Dictionary = body(5, Vector2(600, -600))
	var invalid: Dictionary = body(6, Vector2(NAN, 0))
	d = Bars.layout([retired, small, dead, outside, invalid], 1)
	check(d.bars.is_empty() and d.omitted.retired == 2 and d.omitted.small == 1 and d.omitted.offscreen == 2, "Retired, drained, small and offscreen bodies hide cleanly")
	var crowd: Array = [body(9, Vector2.ZERO), body(4, Vector2.ZERO, 0.2, "elite"), body(3, Vector2.ZERO, 0.75, "boss"), body(1, Vector2.ZERO, 0.9), body(2, Vector2.ZERO)]
	d = Bars.layout(crowd, 1)
	check(d.bars[0].id == 1 and d.bars[1].id == 3 and d.bars[1].boss and d.bars[1].rect.size == Bars.BOSS_SIZE, "Player and framed boss take deterministic presentation priority")
	for a: int in range(d.bars.size()):
		for b: int in range(a + 1, d.bars.size()): check(not d.bars[a].rect.grow(2).intersects(d.bars[b].rect), "Crowd uses separated upward lanes or omits a covered rival")
	crowd.reverse()
	check(Bars.layout(crowd, 1) == d, "Fighter array order cannot cause crowd-lane jitter")
	for mobile: bool in [false, true]:
		for x: int in range(-230, 231, 23):
			for y: int in range(-230, 231, 23):
				var state: Dictionary = Bars.layout([body(1, Vector2(x, y))], 1, mobile)
				for bar: Dictionary in state.bars:
					check(Layout.world_bar_allowed(bar.rect, mobile), "World bars do not cover reserved HUD or mobile action rail")
	var many: Array = []
	for id: int in range(40): many.append(body(id + 1, Vector2((id % 8) * 35 - 120, (id / 8) * 38 - 90)))
	check(Bars.layout(many, 1).bars.size() <= Bars.MAX_BARS, "Presentation remains bounded in artificial extreme crowd")
	check(d.gameplay_writes == 0 and not d.owns_timers and d.reduced_flashing_pulses == 0, "RPM bars have no gameplay or flashing budget")
	measurements.crowd = d

func edge_layout() -> void:
	check(not Touch.valid_gameplay_point(Vector2(100, 49)) and not Touch.valid_gameplay_point(Vector2(120, 442)), "Edge HUD cannot acquire a new Android steering finger")
	check(Touch.valid_gameplay_point(Vector2(100, 90)) and Touch.valid_gameplay_point(Vector2(400, 230)), "Hold-and-drag retains the open combat floor")
	for mobile: bool in [false, true]:
		var menus: Control = Menus.new(); menus.mobile_hud = mobile; root.add_child(menus)
		menus.show_hud({"player_rpm": 1.24, "redline_active": true, "is_run": true, "owned_power_ids": ["dead_centre", "impact_sink", "redline", "orbit_drive"], "power_state": {
			"anchor": {"owned": true, "strength": 0.8, "stress": 0.84, "overloaded": true, "recovering": true},
			"sink": {"owned": true, "stored": 150, "capacity": 150, "ratio": 1},
			"redline": {"owned": true, "active": true, "heat": 1, "excess": 0.24},
			"orbit": {"owned": true, "drive": 1, "drifting": true}}})
		var geometry: Dictionary = menus.combat_layout_snapshot()
		for rect: Rect2 in geometry.regions.values():
			check(not rect.intersects(geometry.play_region), "Permanent Windows/mobile HUD does not cut through reserved gameplay rectangle")
			check(Layout.VIEW.encloses(rect), "Permanent HUD stays in native viewport")
			if mobile: check(not rect.intersects(Layout.MOBILE_ACTION_RAIL), "Mobile HUD leaves accepted Burst/Brake rail unobstructed")
		check(not geometry.duplicate_anchor_label and not menus._hud.has("anchor"), "Anchor has one danger/recharge meter")
		var anchor: Dictionary = menus._hud.state_meters.diagnostic_snapshot().rows.left[0]
		check(anchor.status == "RECHARGE" and anchor.bars.size() == 1 and anchor.bars[0].value == 0.84, "Main Anchor bar communicates real overload/recharge through stress")
		check(menus._hud.state_meters.diagnostic_snapshot().rows.right[0].active, "Overdrive remains active and visible in owned state bank")
		menus.show_hud({"player_rpm": 0.9, "power_state": {"redline": {"owned": true, "active": false, "heat": 0.4}}})
		check(menus._hud.state_meters.diagnostic_snapshot().rows.right[0].text.begins_with("REDLINE"), "Owned Redline/heat row persists between Overdrive activations")
		measurements["android_layout" if mobile else "windows_layout"] = geometry
		menus.free()

func isolated_options() -> void:
	var task: String = report.get_base_dir().get_base_dir()
	var directory: String = task.path_join("temp/hud_options_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("collection.json")
	var save: RefCounted = Save.new(path); save.load_save()
	check(bool(save.initialize_starter("bastion").ok), "Isolated settings fixture preserves a genuine starter collection")
	var collection_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var backup_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path + ".bak") if FileAccess.file_exists(path + ".bak") else PackedByteArray()
	var config: ConfigFile = ConfigFile.new()
	config.set_value("settings", "controller_layout", "nintendo")
	config.set_value("settings", "music_volume", 0.25)
	config.save(path + ".preferences.cfg")
	var app: QuietMain = QuietMain.new(); app.collection_path = path; root.add_child(app); await settle()
	check(app.settings.top_status_bars and app.top_status_bars.enabled, "Existing preference files without key default status bars ON")
	check(app.settings.controller_layout == "nintendo" and app.settings.music_volume == 0.25, "Absent-key migration preserves human controller/music choices")
	check(app._validated_settings({"top_status_bars": "off"}).top_status_bars and app._validated_settings({"top_status_bars": 0}).top_status_bars, "Malformed status preference safely defaults to typed ON")
	check(not app._validated_settings({"top_status_bars": false}).top_status_bars, "Explicit OFF is respected")
	app._title(); app._action("settings")
	var button: Button = null
	for node: Node in app.menus._content.get_children():
		if node is Button and str(node.get_meta("setting_key", "")) == "top_status_bars": button = node
	check(is_instance_valid(button) and button.text == "ON", "Options contains actual TOP STATUS BARS toggle")
	button.pressed.emit()
	check(not app.settings.top_status_bars and not app.top_status_bars.enabled and not app.top_status_bars.visible, "Options OFF immediately hides live world bars")
	check(config.load(path + ".preferences.cfg") == OK and not bool(config.get_value("settings", "top_status_bars", true)), "OFF persists in isolated preferences")
	app.free(); await settle()
	app = QuietMain.new(); app.collection_path = path; root.add_child(app); await settle()
	check(not app.settings.top_status_bars and not app.top_status_bars.enabled, "OFF survives an ordinary restart")
	app._action("settings_changed", {"top_status_bars": true})
	check(app.top_status_bars.enabled and app.top_status_bars.visible, "ON immediately re-enables the same attached renderer")
	check(app.top_status_bars.get_parent() == app.battle and app.top_status_bars.host == app.battle and app.top_status_bars.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Renderer inherits battle placement and uses native nearest pixels")
	check(app.battle.has_method("presentation_offset"), "Production Battle exposes one canonical drawing offset for attached world UI")
	if app.battle.has_method("presentation_offset"):
		app.battle._shake_time = 0.1; app.battle._shake_strength = 4; app.battle._shake_phase = 0.73
		check(app.battle.presentation_offset() != Vector2.ZERO, "World attachment can read the actual live impact shake")
		app.battle.screen_shake_enabled = false
		check(app.battle.presentation_offset() == Vector2.ZERO, "Disabling Screen Shake also settles world status attachment")
	check(FileAccess.get_file_as_bytes(path) == collection_bytes, "Option changes preserve exact collection bytes")
	check((FileAccess.get_file_as_bytes(path + ".bak") if FileAccess.file_exists(path + ".bak") else PackedByteArray()) == backup_bytes, "Option changes preserve exact collection backup bytes")
	check(app.settings.controller_layout == "nintendo" and app.settings.music_volume == 0.25, "Live setting does not disturb accepted controller/audio choices")
	await controller_options(app)
	check(FileAccess.get_file_as_bytes(path) == collection_bytes and app.settings.music_volume == 0.25, "Controller option traversal preserves exact collection and audio preferences")
	measurements.option_profile = path
	app.free(); await settle()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	var valid: bool = report.is_absolute_path() and report.replace("\\", "/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/") and not FileAccess.file_exists(report)
	if not valid: push_error("Fresh absolute 003A.1 QA report required; no player profile opened"); quit(2); return
	root.size = Vector2i(800, 480); root.content_scale_size = Vector2i(800, 480)
	Input.use_accumulated_input = false
	attachment_and_crowds(); edge_layout(); await isolated_options()
	var file: FileAccess = FileAccess.open(report, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}, "\t"))
	print("COMBAT_HUD_003A1_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
