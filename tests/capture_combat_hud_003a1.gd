extends SceneTree
## Native production Main/HUD; declared invested loadout and meter/crowd endpoints.
## Android cells are a desktop layout audit, never APK/physical-device acceptance.
const Starters = preload("res://scripts/starters.gd")
const Roles = preload("res://scripts/enemy_roles.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _battle_sound(_kind: String) -> void: pass
var game: QuietMain
var manifest: String = ""
var frames: String = ""
var profile: String = ""
var images: Dictionary = {}
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func capture(name: String) -> void:
	game.battle._emit_hud()
	game.top_status_bars.queue_redraw()
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	if pixels.get_size() != Vector2i(640, 360): failures.append("Non-native pixels " + name)
	var attached: Dictionary = game.top_status_bars.diagnostic_snapshot()
	for bar: Dictionary in attached.get("bars", []):
		var fighter: Dictionary = game.battle.entity(int(bar.id))
		var expected: Vector2 = game.battle.project(fighter.pos, float(fighter.height)).round() + game.battle.presentation_offset()
		if bar.contact != expected: failures.append("World RPM attachment differs from actual rig on " + name)
	var path: String = frames.path_join(name + ".png")
	if pixels.save_png(path) != OK: failures.append("Could not save " + path)
	images[name] = {"path": path, "native_view": [640, 360], "screen": game.screen,
		"runtime_power_state": game.battle.powers.public_state(game.battle.player_entity()),
		"layout": game.menus.combat_layout_snapshot(), "world_bars": game.top_status_bars.diagnostic_snapshot(),
		"android_layout_fixture": game.menus.mobile_hud, "physical_device_acceptance": false}

func endpoint(recharging: bool = false, crowded: bool = false) -> void:
	var b: Node2D = game.battle
	var p: Dictionary = b.player_entity()
	b._shake_time = 0
	p.pos = Vector2(40, 30) if recharging else Vector2.ZERO
	p.vel = Vector2(40, 0) if recharging else Vector2.ZERO
	p.rpm = 1.18; p.energy = p.rpm; p.wobble = 0.08
	p.anchor_charge = 0.12 if recharging else 1.0
	p.anchor_stress = 0.74 if recharging else 0.62
	p.anchor_venting = recharging
	p.anchor_load = 0.6
	p.anchor_recovery_progress = 0.4 if recharging else 1.0
	p.orbit_charge = 0.69; p.drift_active = false
	p.redline_heat = 0.58
	p.sink_charge = b.powers.defence.sink_capacity(p) * 0.6
	b.powers._state(p).anchor_overloaded = recharging
	b.powers._state(p).redline_until = b.powers.time + 2.0
	p.redline_time = 2.0
	var placements: Array[Vector2] = [Vector2(75, 20), Vector2(-42, -50), Vector2(38, -48), Vector2(-65, 70)]
	for index: int in range(b.fighters.size()):
		var f: Dictionary = b.fighters[index]
		if int(f.entity_id) == 1: continue
		f.pos = Vector2(3 + (index % 2) * 5, 2 + index * 4) if crowded else placements[(index - 1) % placements.size()]
		f.rpm = 0.86 - index * 0.12; f.energy = f.rpm; f.height = 0; f.outcome = ""; f.vel = Vector2.ZERO
	b.battle_status = "battle"; b.paused = false
	b.queue_redraw()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): manifest = arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frames = arg.trim_prefix("--frames=")
		if arg.begins_with("--profile="): profile = arg.trim_prefix("--profile=")
	var valid: bool = manifest.is_absolute_path() and frames.is_absolute_path() and profile.is_absolute_path()
	for path: String in [manifest, frames, profile]: valid = valid and path.replace("\\", "/").to_lower().contains("gyrobrothers-qa/003a.1/")
	if not valid or FileAccess.file_exists(manifest) or DirAccess.dir_exists_absolute(frames) or FileAccess.file_exists(profile):
		push_error("Fresh absolute 003A.1 manifest/frames/profile required; no player save opened"); quit(2); return
	DirAccess.make_dir_recursive_absolute(frames)
	root.size = Vector2i(640, 360); root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	game = QuietMain.new(); game.smoke_mode = true; game.collection_path = profile; root.add_child(game)
	game.set_process(false)
	var build: Dictionary = Starters.build_for("bastion")
	game.run_context.start(build, 7341, "bastion")
	game.run_context._owned_power_ids.assign(["dead_centre", "impact_sink", "redline", "orbit_drive"])
	game.run_context._power_ranks = {"dead_centre": 3, "impact_sink": 2, "redline": 3, "orbit_drive": 2}
	game.run_context._power_mutations = {"dead_centre": "bulwark", "redline": "runaway"}
	game.run_context._progression.level = 11
	game.run_context._progression.xp = 18
	game._launch_run_encounter(); game.battle.set_physics_process(false)
	for entry: Dictionary in [{"id": 31, "kind": "rival", "key": "flanker", "role": "flanker", "name": "RIVAL", "cost": 1.0},
		{"id": 32, "kind": "elite", "key": "ballast", "role": "bulwark", "name": "BALLAST", "cost": 1.5},
		{"id": 33, "kind": "boss", "key": "anvil", "role": "bulwark", "name": "ANVIL", "cost": 3.0}]:
		game.battle.add_full_top(Roles.BUILDS[str(entry.role)], int(entry.id), game.battle.HOSTILE_TEAM, "hud-fixture", Vector2.ZERO)
		entry.serial = int(entry.id); entry.tier_at_entry = 5
		Roles.configure(game.battle.entity(int(entry.id)), entry)
	game.battle.elapsed = 185
	game.battle.continuous.progression_level = 11
	game.touch_controls.show_controls = false
	endpoint(); await capture("windows_anchor_overdrive")
	endpoint(true); await capture("windows_anchor_recharging")
	endpoint(false, true); await capture("windows_crowd")
	endpoint(); game.battle._shake_time = 0.1; game.battle._shake_strength = 4; game.battle._shake_phase = 0.73
	await capture("windows_impact_shake")
	game.menus.mobile_hud = true; game.top_status_bars.mobile_layout = true
	game.touch_controls.show_controls = true; game.touch_controls.set_enabled(true)
	game.menus._clear("layout_audit", false)
	endpoint(); await capture("android_layout_anchor_overdrive")
	endpoint(true); await capture("android_layout_anchor_recharging")
	game._action("settings_changed", {"top_status_bars": false})
	endpoint(); await capture("android_layout_bars_off")
	game._action("settings_changed", {"top_status_bars": true})
	game._settings_origin = "pause"; game._show_settings()
	game.touch_controls.set_enabled(false) # Normal Main._process performs this on non-combat screens.
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var options: Image = root.get_texture().get_image()
	var options_path: String = frames.path_join("options_top_status_bars.png")
	options.save_png(options_path)
	images.options_top_status_bars = {"path": options_path, "native_view": [640, 360], "screen": "settings", "physical_device_acceptance": false}
	var file: FileAccess = FileAccess.open(manifest, FileAccess.WRITE)
	file.store_string(JSON.stringify({"images": images, "failures": failures, "profile": profile, "player_profile_writes": false,
		"scope": "Native production Main/HUD layout audit. Four-family legal invested loadout, meter endpoints, full rival/elite/boss crowd and reserve values are explicit presentation fixtures. Director pressure is the actual census of the fixture. This is not an earned survival, economy, Android APK or physical-device claim.",
		"android_scope": "Production mobile HUD + accepted touch rectangles rendered at native640x360 on Windows; no emulation/device claim."}, "\t"))
	file.close()
	print("COMBAT_HUD_CAPTURE_%s images=%d" % ["PASS" if failures.is_empty() else "FAIL", images.size()])
	game.free(); quit(0 if failures.is_empty() else 1)
