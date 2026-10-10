extends SceneTree
## Isolated paused native window fixture. Automated mode uses OS window APIs.
const Starters = preload("res://scripts/starters.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _battle_sound(_kind: String) -> void: pass
var game: QuietMain
var report: String = ""
var stop_file: String = ""
var snapshots: Array[Dictionary] = []
var last_state: String = ""
var baseline_world: String = ""
var clock: float = 0.0
var started: bool = false
var frames_dir: String = ""
var captured_frames: Array[Dictionary] = []
var automatic: bool = false
var sequence_phase: int = 0
var phase_started_msec: int = 0
var sequence_events: Array[Dictionary] = []
var restore_size: Vector2i
var restore_position: Vector2i
var restore_verified: bool = false
var capture_skipped_unfocused: int = 0
var capture_skipped_obscured: int = 0
const PHASES: Array[String] = ["normal_960x600", "normal_800x480", "larger_1280x800", "os_api_maximise", "os_api_restore", "normal_800x480_final"]

func capture_native_frame() -> void:
	if frames_dir.is_empty(): return
	if not DisplayServer.window_is_focused():
		capture_skipped_unfocused += 1
		return
	var reported_decorations: Rect2i = Rect2i(DisplayServer.window_get_position_with_decorations(),DisplayServer.window_get_size_with_decorations())
	var client_position: Vector2i = DisplayServer.window_get_position()
	var client_size: Vector2i = DisplayServer.window_get_size()
	# DWM decoration bounds include invisible side/bottom resize margins.
	# Capture the complete real native caption and client only; background
	# pixels beneath those invisible margins do not belong to this window.
	var outer: Rect2i = Rect2i(Vector2i(client_position.x,reported_decorations.position.y),Vector2i(client_size.x,client_position.y-reported_decorations.position.y+client_size.y))
	var monitor: Rect2i = Rect2i(DisplayServer.screen_get_position(),DisplayServer.screen_get_size())
	outer=outer.intersection(monitor)
	# Also restrict maximised capture to the usable monitor area.
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
		outer = outer.intersection(DisplayServer.screen_get_usable_rect())
	if not outer.has_area(): return
	var image: Image = DisplayServer.screen_get_image_rect(outer)
	if image == null: return
	# Window focus notifications can lag a newly raised QA window. Accept native
	# pixels only when this entire client matches our own rendered viewport.
	# This also prevents unrelated overlaid windows entering the review capture.
	var client_roi: Rect2i = Rect2i(client_position-outer.position,client_size)
	if not Rect2i(Vector2i.ZERO,image.get_size()).encloses(client_roi):
		capture_skipped_obscured += 1; return
	var visible_client: Image = image.get_region(client_roi)
	var own_client: Image = root.get_texture().get_image()
	visible_client.convert(Image.FORMAT_RGB8); own_client.convert(Image.FORMAT_RGB8)
	if visible_client.get_size() != own_client.get_size():
		capture_skipped_obscured += 1; return
	# The user's native cursor includes a measured ~120px halo; hardware cursor
	# pixels do not exist in the viewport readback. Exclude only its140px box
	# from comparison, preserving the actual cursor in the saved native image.
	var pointer: Vector2i = DisplayServer.mouse_get_position()-client_position
	var cursor_box: Rect2i = Rect2i(pointer-Vector2i(70,70),Vector2i(140,140)).intersection(Rect2i(Vector2i.ZERO,client_size))
	if cursor_box.has_area(): visible_client.blit_rect(own_client,cursor_box,cursor_box.position)
	# Native DWM composition rounds some channels by one8-bit level. Every
	# client pixel must remain within that measured tolerance; this is not an
	# average similarity gate that could permit an overlaid window.
	var metrics: Dictionary = visible_client.compute_image_metrics(own_client,false)
	if float(metrics.max) > 1.0:
		capture_skipped_obscured += 1; return
	var path: String = frames_dir.path_join("native_%05d.png" % captured_frames.size())
	if image.save_png(path) != OK: return
	captured_frames.append({"path":path,"time_msec":Time.get_ticks_msec(),"decorated_rect":outer,"reported_dwm_bounds":reported_decorations,"capture_bounds_policy":"Client width plus actual OS caption height; invisible DWM resize margins excluded","client_pixel_metrics":metrics,"hardware_cursor_comparison_exclusion":cursor_box,"mode":DisplayServer.window_get_mode(),"client_size":root.size,"phase":PHASES[sequence_phase] if automatic else "manual_native_window","phase_elapsed_msec":Time.get_ticks_msec()-phase_started_msec})

func advance_sequence() -> void:
	sequence_phase += 1
	if sequence_phase >= PHASES.size():
		sequence_phase = PHASES.size()-1
		write_report()
		quit()
		return
	match sequence_phase:
		1: DisplayServer.window_set_size(Vector2i(800,480))
		2: DisplayServer.window_set_size(Vector2i(1280,800))
		3:
			restore_size = DisplayServer.window_get_size()
			restore_position = DisplayServer.window_get_position()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		4: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		5: DisplayServer.window_set_size(Vector2i(800,480))
	phase_started_msec = Time.get_ticks_msec()
	sequence_events.append({"phase":PHASES[sequence_phase],"time_msec":phase_started_msec,"actuation":"DisplayServer OS API; no synthetic title-bar button claim"})

func _initialize() -> void: call_deferred("run")
func world_state() -> Array:
	var result: Array = []
	for fighter: Dictionary in game.battle._ordered_fighters():
		result.append({"entity_id":fighter.entity_id,"pos":fighter.pos,"vel":fighter.vel,"rpm":fighter.rpm,
			"wobble":fighter.wobble,"mass":fighter.mass,"radius":fighter.radius,"build":fighter.build,
			"cooldown":fighter.cooldown,"height":fighter.height,"outcome":fighter.outcome})
	return result
func write_report() -> void:
	var file: FileAccess = FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Real decorated Windows client capture; automatic sequence uses OS APIs for resize, Maximise and Restore. Legal initial four-power loadout with paused production world is a presentation fixture. Physical button and Android acceptance are not inferred from API actuation.",
		"snapshots":snapshots,"current":game.window_presentation_snapshot(),"world_unchanged":JSON.stringify(world_state())==baseline_world,
		"captured_frames":captured_frames,"capture_method":"Godot DisplayServer.screen_get_image_rect bounded to this foreground QA window including real OS decorations; never capture an unrelated window or desktop region.",
		"automatic_sequence":automatic,"sequence_events":sequence_events,"restore_size":restore_size,"restore_position":restore_position,"restore_verified":restore_verified,"capture_skipped_unfocused":capture_skipped_unfocused,"capture_skipped_obscured":capture_skipped_obscured,"native_client_pixel_guard":{"all_rgb_channels":true,"maximum_allowed_8bit_difference":1,"hardware_cursor_box":140,"reason":"Measured native DWM rounding; all client pixels outside the native cursor box compared with the owning viewport, overlaid windows rejected. Saved screenshots retain original cursor pixels."},
		"source_fixture_powers":["dead_centre","impact_sink","redline","orbit_drive"],"native_window_title":"Spinning Metal - WINDOW QA 003A.1"},"\t")); file.close()
func _process(dt: float) -> bool:
	if not started: return false
	clock+=dt
	if clock<0.1: return false
	clock=0.0
	if automatic and Time.get_ticks_msec()-phase_started_msec >= 3500:
		advance_sequence()
	game._refresh_window_presentation()
	if automatic and sequence_phase == 4 and Time.get_ticks_msec()-phase_started_msec >= 250:
		restore_verified = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_size() == restore_size and DisplayServer.window_get_position() == restore_position
	capture_native_frame()
	var current: Dictionary = game.window_presentation_snapshot()
	current["window_position"] = root.position
	var state: String = JSON.stringify(current)
	if state != last_state:
		last_state=state
		current["time_msec"] = Time.get_ticks_msec()
		current["hud"] = game.menus.combat_layout_snapshot()
		current["world_unchanged"] = JSON.stringify(world_state())==baseline_world
		snapshots.append(current)
		write_report()
	elif automatic:
		write_report()
	if FileAccess.file_exists(stop_file):
		write_report(); quit()
	return false
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
		if arg.begins_with("--stop-file="): stop_file=arg.trim_prefix("--stop-file=")
		if arg.begins_with("--frames="): frames_dir=arg.trim_prefix("--frames=")
		if arg == "--auto-sequence": automatic=true
	if not report.is_absolute_path() or FileAccess.file_exists(report) or not stop_file.is_absolute_path():
		push_error("Fresh absolute QA report and stop path required"); quit(2); return
	if not frames_dir.is_empty(): DirAccess.make_dir_recursive_absolute(frames_dir)
	root.size=Vector2i(960,600)
	game=QuietMain.new(); game.smoke_mode=true
	game.collection_path=report.get_base_dir().get_base_dir().path_join("temp/native_window_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	root.add_child(game)
	for frame: int in range(4): await process_frame
	game.run_context.start(Starters.build_for("bastion"),7341,"bastion")
	game.run_context._owned_power_ids.assign(["dead_centre","impact_sink","redline","orbit_drive"])
	game.run_context._power_ranks={"dead_centre":2,"impact_sink":2,"redline":2,"orbit_drive":2}
	game.mode="run"; game._launch_run_encounter()
	game.battle.set_physics_process(false); game.battle.paused=true; game.battle.battle_status="battle"
	game.battle.player_entity().anchor_stress=.46
	game.battle.player_entity().sink_charge=60.0
	game.battle.player_entity().redline_heat=.34
	game.battle.player_entity().orbit_drive=.52
	game.battle._emit_hud()
	DisplayServer.window_set_title("Spinning Metal - WINDOW QA 003A.1")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(960,600))
	baseline_world=JSON.stringify(world_state())
	phase_started_msec = Time.get_ticks_msec()
	sequence_events.append({"phase":PHASES[0] if automatic else "manual_native_window","time_msec":phase_started_msec,"actuation":"DisplayServer OS API initial ordinary decorated client"})
	started=true
	write_report()
