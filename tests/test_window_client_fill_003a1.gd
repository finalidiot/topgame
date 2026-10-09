extends SceneTree
## Read-only client/layout contracts; native pixel/window footage is separate.
const Layout = preload("res://scripts/combat_hud_layout.gd")
const Starters = preload("res://scripts/starters.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void:pass
	func _battle_sound(_kind: String) -> void:pass
var game: QuietMain
var checks: int=0
var failures: Array[String]=[]
var output: String=""
var observed: Array[Dictionary]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func settle() -> void:
	for tick: int in range(4):await process_frame
func world_state() -> Dictionary:
	var fighters: Array[Dictionary]=[]
	for f: Dictionary in game.battle._ordered_fighters():
		var row: Dictionary={}
		for key: String in ["entity_id","pos","vel","rpm","wobble","mass","radius","build","stats","part_physics","height","height_vel","cooldown","outcome","phase"]:row[key]=f[key]
		fighters.append(row.duplicate(true))
	return {"fighters":fighters,"elapsed":game.battle.elapsed,"live_time_limit":game.battle.live_time_limit,"seed":game.battle.seed_value,"hits":game.battle.hits,"projection":game.battle.project(Vector2.ZERO)}
func inspect(client: Vector2i, ui_scale: float) -> Dictionary:
	root.size=client;game._refresh_window_presentation();await settle()
	var label: String="%dx%d / UI%.1f"%[client.x,client.y,ui_scale]
	var view: Dictionary=game.window_presentation_snapshot()
	var hud: Dictionary=game.menus.combat_layout_snapshot()
	var canvas: Rect2=Rect2(Vector2.ZERO,view.canvas_size)
	check(is_equal_approx(float(view.ui_policy.ui_scale),ui_scale),label+": intended discrete UI scale")
	check(view.ui_policy.native_window_managed_by_os and not view.ui_policy.changes_window_mode,label+": OS owns window mode")
	check(root.content_scale_size==Vector2i(view.ui_policy.canvas_size),label+": actual content scale follows policy")
	check(root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,label+": root canvas stretch")
	check(root.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_EXPAND,label+": client expands logical presentation")
	check(root.content_scale_stretch==Window.CONTENT_SCALE_STRETCH_FRACTIONAL,label+": useful client area remains available")
	check(game.combat_viewport.size==Vector2i(640,360),label+": fixed native world")
	check(game.battle.project(Vector2.ZERO)==Vector2(320,165),label+": camera invariant")
	check(game.combat_frame.scale==Vector2.ONE,label+": uniform texture extent handles fit")
	check(is_equal_approx(game.combat_frame.size.x/640.0,game.combat_frame.size.y/360.0),label+": no aspect distortion")
	check(game.combat_frame.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,label+": nearest-neighbour world")
	check(game.combat_frame.get_rect()==view.arena_rect and hud.play_region==view.arena_rect,label+": actual frame/HUD agree")
	check(canvas.encloses(view.arena_rect),label+": complete play view is inside client")
	check(float(view.arena_scale)>=1.0,label+": native arena never shrinks")
	for key: String in hud.regions:
		var rect: Rect2=hud.regions[key]
		check(canvas.encloses(rect),label+": HUD region "+key+" fits")
		check(not rect.intersects(view.arena_rect),label+": HUD region "+key+" stays outside play")
	for key: String in ["player_panel","enemy_panel","clock_panel","burst_panel","xp_panel","xp_hit","player_name","enemy_name","player_rpm","enemy_rpm","xp_label","xp_detail","rerolls","impact_confirmation"]:
		var rect: Rect2=game.menus._hud[key].get_global_rect()
		check(canvas.encloses(rect),label+": actual "+key+" fits")
		check(not rect.intersects(view.arena_rect),label+": actual "+key+" stays outside play")
	var meters: Dictionary=game.menus._hud.state_meters.diagnostic_snapshot()
	check(meters.rows.left.size()==2 and meters.rows.right.size()==2,label+": four invested power meters survive")
	check(meters.left==view.state_left and meters.right==view.state_right,label+": meters reflow to margins")
	check(meters.label_size>=10,label+": native label size remains readable")
	check(game.presentation_surround!=null,label+": client background exists")
	var casing: Dictionary=game.presentation_surround.diagnostic_snapshot()
	check(casing.extent==view.canvas_size and casing.arena==view.arena_rect,label+": continuous casing covers presentation extent")
	check(casing.nearest_neighbour and not casing.input_interception and not casing.world_changes,label+": casing stays visual-only")
	check(game.presentation_surround.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,label+": authored casing remains nearest")
	check(game.presentation_surround.deck!=null and game.presentation_surround.casing!=null,label+": actual authored styles loaded")
	check(ResourceLoader.exists(casing.authored_texture) and FileAccess.file_exists(casing.native_master),label+": editable source/runtime pair exists")
	check(game.presentation_surround.get_index()<game.combat_frame.get_index(),label+": client surface sits behind actual play")
	var physical: Vector2=game.combat_frame.size*ui_scale
	var result: Dictionary={"client":client,"canvas":view.canvas_size,"ui_scale":ui_scale,"native_arena":game.combat_viewport.size,"physical_arena":physical,"physical_arena_area_fraction":physical.x*physical.y/(float(client.x)*float(client.y)),"layout":view,"casing":casing,"meters":meters}
	observed.append(result);return result
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	if not output.is_absolute_path() or FileAccess.file_exists(output) or not output.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/"):
		push_error("Fresh external003A.1 --report required");quit(2);return
	root.size=Vector2i(800,480)
	var native_mode: int=DisplayServer.window_get_mode();var native_borderless: bool=DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	game=QuietMain.new();game.smoke_mode=true
	game.collection_path=output.get_base_dir().get_base_dir().path_join("temp/window_client_fill_%d_%d.json"%[OS.get_process_id(),Time.get_ticks_usec()])
	root.add_child(game);await settle()
	game.run_context.start(Starters.build_for("bastion"),7341,"bastion")
	game.run_context._owned_power_ids.assign(["dead_centre","impact_sink","redline","orbit_drive"])
	game.run_context._power_ranks={"dead_centre":2,"impact_sink":2,"redline":2,"orbit_drive":2}
	game.mode="run";game._launch_run_encounter();game.battle.set_physics_process(false);game.battle.paused=true;game.battle.battle_status="battle";game.battle._emit_hud()
	var original: Dictionary=world_state()
	for spec: Dictionary in [{"size":Vector2i(800,480),"ui":1.0},{"size":Vector2i(960,600),"ui":1.0},{"size":Vector2i(1280,800),"ui":1.0},{"size":Vector2i(1920,1017),"ui":1.0},{"size":Vector2i(2560,1440),"ui":1.5},{"size":Vector2i(2561,1441),"ui":1.5},{"size":Vector2i(3840,2160),"ui":2.0}]:
		await inspect(spec.size,spec.ui)
		check(world_state()==original,"Every client size/UI scale preserves exact paused world state")
	var normal: Dictionary=observed[0];var maximised_hd: Dictionary=observed[3]
	check(maximised_hd.physical_arena.x>1500 and maximised_hd.physical_arena.y>=890,"HD maximisation expands actual play view substantially")
	check(maximised_hd.physical_arena.x*maximised_hd.physical_arena.y>1376.0*774.0*1.30,"HD actual arena area exceeds prior accepted runtime by over30%")
	check(maximised_hd.physical_arena_area_fraction>.72,"HD client prioritizes the actual arena")
	check(observed[4].physical_arena.x>maximised_hd.physical_arena.x and observed[6].physical_arena.x>observed[4].physical_arena.x,"Larger monitor scales still grow physical play")
	check(observed[3].meters.right.x>normal.meters.right.x,"HD margins move actual meters outward")
	await inspect(Vector2i(800,480),1.0)
	check(world_state()==original,"Restore retains exact world state")
	check(game.combat_frame.get_rect()==Layout.PLAY_REGION,"Small window restores native composition")
	check(DisplayServer.window_get_mode()==native_mode and DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)==native_borderless,"Read-only layout refresh never changes OS mode/borders")
	# The actual hosted SubViewport follows Android's native layout branch.
	var host: SubViewport=SubViewport.new();host.size=Vector2i(800,480);root.add_child(host)
	var mobile: QuietMain=QuietMain.new();mobile.smoke_mode=true
	mobile.collection_path=output.get_base_dir().get_base_dir().path_join("temp/window_client_mobile_%d_%d.json"%[OS.get_process_id(),Time.get_ticks_usec()])
	host.add_child(mobile);await settle();mobile._refresh_window_presentation();await settle()
	var mobile_layout: Dictionary=mobile.window_presentation_snapshot()
	check(mobile_layout.mobile_layout and mobile_layout.canvas_size==Vector2(800,480),"Actual hosted mobile branch stays800x480")
	check(mobile.combat_viewport.size==Vector2i(640,360) and mobile.combat_frame.get_rect()==Layout.PLAY_REGION,"Hosted mobile world stays native640x360 at80,60")
	check(mobile.presentation_surround==null,"Desktop casing does not enter hosted mobile layout")
	check(mobile_layout.ui_policy.ui_scale==1.0,"Hosted mobile UI ignores desktop1.5/2 thresholds")
	check(Layout.responsive(Vector2(3840,2160),true).arena_rect==Layout.PLAY_REGION,"Even large mobile hosts retain accepted logical play region")
	check(world_state()==original,"Hosted mobile construction cannot touch existing world")
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observed":observed,"hosted_mobile":mobile_layout,"isolated_collection":game.collection_path,"scope":"Headless actual Main/SubViewport/HUD/style/layout contracts with paused legal four-power ownership fixture, including UI1/1.5/2 and hosted800x480 mobile branch. No production writes, OS mode actuation or native pixel/physical Android acceptance claim; native client/window screenshots are separate."},"\t"));file.close()
	host.free();game.free();await settle()
	print("WINDOW_CLIENT_FILL_003A1_%s checks=%d"%["PASS" if failures.is_empty() else "FAIL",checks]);quit(0 if failures.is_empty() else 1)
