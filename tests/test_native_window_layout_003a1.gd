extends SceneTree
## Real client-size/reflow contracts; OS button footage is captured separately.
const Layout = preload("res://scripts/combat_hud_layout.gd")
const Starters = preload("res://scripts/starters.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _battle_sound(_kind: String) -> void: pass
var game: QuietMain
var checks: int = 0
var failures: Array[String] = []
var report: String = ""
var native: bool = false
var observed: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func settle() -> void:
	for frame: int in range(4): await process_frame
func world_state() -> Array:
	var states: Array = []
	for fighter: Dictionary in game.battle._ordered_fighters():
		var state: Dictionary = {}
		for key: String in ["pos","vel","rpm","wobble","mass","radius","build","stats","height","cooldown","outcome","phase"]:
			state[key] = fighter[key]
		states.append(state)
	return states
func inspect_layout(label: String) -> void:
	game._refresh_window_presentation()
	await settle()
	var layout: Dictionary = game.window_presentation_snapshot()
	var hud: Dictionary = game.menus.combat_layout_snapshot()
	check(game.combat_viewport.size == Vector2i(640,360),label+": native world extent stays fixed")
	check(game.battle.project(Vector2.ZERO) == Vector2(320,165),label+": isometric camera stays fixed")
	check(game.combat_frame.scale == Vector2.ONE,label+": outer node does not distort its axes")
	check(is_equal_approx(game.combat_frame.size.x/640.0,game.combat_frame.size.y/360.0),label+": arena fits uniformly")
	check(game.combat_frame.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,label+": nearest pixels remain selected")
	check(game.combat_frame.get_rect() == layout.arena_rect,label+": actual frame uses calculated client extent")
	check(hud.play_region == layout.arena_rect,label+": HUD and arena share the same safe region")
	var canvas: Rect2 = Rect2(Vector2.ZERO,layout.canvas_size)
	for key: String in hud.regions:
		var rect: Rect2 = hud.regions[key]
		check(canvas.encloses(rect),label+": "+key+" stays in client presentation")
		check(not rect.intersects(layout.arena_rect),label+": "+key+" stays outside arena")
	for key: String in ["player_panel","enemy_panel","clock_panel","burst_panel","xp_panel","xp_hit","player_name","enemy_name","player_rpm","enemy_rpm","xp_label","xp_detail","rerolls","impact_confirmation"]:
		var rect: Rect2 = game.menus._hud[key].get_global_rect()
		check(canvas.encloses(rect),label+": actual "+key+" fits")
		check(not rect.intersects(layout.arena_rect),label+": actual "+key+" is combat-safe")
	var meters: Dictionary = game.menus._hud.state_meters.diagnostic_snapshot()
	check(meters.rows.left.size() == 2 and meters.rows.right.size() == 2,label+": all four power meters remain present")
	check(meters.left == layout.state_left and meters.right == layout.state_right,label+": state columns follow margins")
	check(meters.label_size >= 10,label+": labels retain readable size")
	var snapshot: Dictionary = {"label":label,"client_size":root.size,"layout":layout,"hud":hud,"meters":meters}
	if native:
		await RenderingServer.frame_post_draw
		var world_image: Image = game.combat_viewport.get_texture().get_image()
		var canvas_image: Image = root.get_texture().get_image()
		var ui_scale: float = float(layout.ui_policy.ui_scale)
		var physical_scale: float = ui_scale*float(layout.arena_scale)
		var physical_rect: Rect2 = Rect2(layout.arena_rect.position*ui_scale,layout.arena_rect.size*ui_scale)
		check(world_image.get_size() == Vector2i(640,360),label+": rendered native world stays fixed")
		if is_equal_approx(physical_scale,roundf(physical_scale)):
			var composite: Image = canvas_image.get_region(Rect2i(physical_rect))
			composite.resize(640,360,Image.INTERPOLATE_NEAREST)
			check(composite.get_data() == world_image.get_data(),label+": actual integer composite exactly matches native RGBA")
		var folder: String = report.get_base_dir().get_base_dir().path_join("frames/window_layout_contract_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
		DirAccess.make_dir_recursive_absolute(folder)
		var image_path: String = folder.path_join(label+".png")
		check(canvas_image.save_png(image_path) == OK,label+": actual client capture saved")
		snapshot["client_image"] = image_path
		snapshot["physical_arena_rect"] = physical_rect
	observed.append(snapshot)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
		if arg=="--native": native=true
	if not report.is_absolute_path() or FileAccess.file_exists(report) or not (report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/") or report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/")):
		push_error("A fresh isolated003A.1 report is required"); quit(2); return
	root.size = Vector2i(800,480)
	game = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = report.get_base_dir().get_base_dir().path_join("temp/window_contract_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	root.add_child(game)
	await settle()
	game.run_context.start(Starters.build_for("bastion"),7341,"bastion")
	game.run_context._owned_power_ids.assign(["dead_centre","impact_sink","redline","orbit_drive"])
	game.run_context._power_ranks={"dead_centre":2,"impact_sink":2,"redline":2,"orbit_drive":2}
	game.mode="run"; game._launch_run_encounter()
	game.battle.set_physics_process(false); game.battle.paused=true; game.battle.battle_status="battle"
	game.battle._emit_hud()
	var original_world: Array = world_state()
	var original_limit: float = game.battle.live_time_limit
	for extent: Vector2i in [Vector2i(800,480),Vector2i(960,600),Vector2i(1280,800),Vector2i(1600,960)]:
		root.size = extent
		await inspect_layout("window_%dx%d" % [extent.x,extent.y])
		check(world_state() == original_world,"Client resize cannot alter positions/velocity/RPM/build/geometry")
		check(game.battle.live_time_limit == original_limit,"Client resize cannot alter simulation time limit")
	check(observed[1].layout.arena_rect.size.x > observed[0].layout.arena_rect.size.x,"Extra client area grows the actual arena")
	check(observed[2].meters.right.x > observed[0].meters.right.x,"Wider client redistributes meters outward")
	check(Layout.desktop_canvas(Vector2i(3840,2160)).ui_scale == 2,"Large monitors spend extra area on arena rather than enormous HUD")
	check(not game._validated_settings({"fullscreen":true}).fullscreen,"Legacy fullscreen preference no longer changes desktop display mode")
	check(not InputMap.has_action("toggle_fullscreen"),"Retired fullscreen input is absent")
	if native:
		var before_size: Vector2i = root.size
		var before_position: Vector2i = root.position
		# OS API actuation verifies windowing contracts. Separately retained
		# human Maximise footage is not inferred from these automated calls.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		await inspect_layout("native_maximised")
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED,"Maximisation remains an OS maximised decorated window")
		check(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS),"Title bar/borders are retained")
		game._apply_settings(); await settle()
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED,"Changing an option cannot restore or replace maximisation")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await inspect_layout("native_restored")
		check(root.size == before_size and root.position == before_position,"OS restores previous bounds without a custom restore size")
		check(world_state() == original_world,"Native Maximise/Restore preserves the complete frozen world state")
	root.size=Vector2i(800,480); await inspect_layout("normal_restored_small")
	game.run_context.clear(); game._show_settings()
	for child: Node in game.menus._content.get_children():
		if child is Button: check(str(child.get_meta("setting_key","")) != "fullscreen","Options has no misleading fullscreen toggle")
	game._title()
	check(game.menus._content.position == Vector2(80,60),"Small normal window restores canonical menu composition")
	var mobile: Dictionary = Layout.responsive(Vector2(1600,960),true)
	check(mobile.canvas_size == Vector2(1600,960) and float(mobile.arena_scale)>1.0 and is_equal_approx(mobile.arena_rect.size.x/640.0,mobile.arena_rect.size.y/360.0),"Android expands independently while preserving a uniform canonical world")
	var file: FileAccess = FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"native":native,"observed":observed,"scope":"Client reflow and actual rendered/native OS API window contracts. Legal initial four-power loadout and paused world are disclosed presentation fixtures, not balance acceptance. Retained real human Maximise evidence is separate; automated Restore is OS API actuation."},"\t")); file.close()
	game.queue_free(); await settle()
	print("NATIVE_WINDOW_LAYOUT_003A1_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
