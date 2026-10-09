extends "res://tests/test_pickup_positions_003a1.gd"
## Every drop is an explicit isolated fixture. Motion between scene setup and
## collection is ordinary steering in the unchanged fixed Battle solver.
const Sound = preload("res://scripts/sound.gd")
var frames_path: String = ""
var diagnostic: bool = false
var movie_frames: int = 0
var phases: Array[Dictionary] = []
var capture_rows: Array[Dictionary] = []
var feature_frames: Dictionary = {}
var sound: Node

func observe(f: Dictionary, controls: Vector2, case_name: String, point_index: int, feature: String="") -> void:
	var b: Node2D = f.battle
	var pose: Dictionary = b.full_top_render_pose(b.player_entity())
	capture_rows.append({"movie_frame":movie_frames,"case":case_name,"point_index":point_index,"elapsed":b.elapsed,"input_screen":controls,
		"player_world":b.player_entity().pos,"player_floor_projected":Battle.project(b.player_entity().pos).round(),"player_height":b.player_entity().height,
		"render_pose":pose,"native_blade_bounds":f.tokens._visible_blade_bounds(b.player_entity()),"pickup":f.tokens.presentation_snapshot(),
		"collected":f.run.rerolls_collected,"rerolls":f.run.reroll_charges,"sound_counts":sound.played_counts.duplicate()})
	if not diagnostic:
		b.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		if not feature.is_empty() and not feature_frames.has(feature):
			var image: Image=root.get_texture().get_image()
			var path: String=frames_path.path_join(feature+".png")
			check(image.get_size()==Vector2i(640,360),"Native fixture remains exact640x360")
			check(image.save_png(path)==OK,"Native feature frame is saved")
			feature_frames[feature]={"path":path,"movie_frame":movie_frames}
	movie_frames+=1
func scene(point: Vector2, direction: Vector2, index: int) -> void:
	var offset: Vector2=Vector2(18,18)
	var f: Dictionary=fixture(point,point+offset-direction*45.0)
	f.battle.continuous=null;f.battle.player_entity().powers=[];f.battle.player_entity().power_ranks={}
	for fighter: Dictionary in f.battle.fighters:
		if fighter.entity_id!=f.battle.player_entity_id:fighter.outcome="fixture_retired";fighter.pos=Vector2(-1000,-1000)
	f.battle.event_sfx.connect(sound.play_sound)
	var name: String="point_%d_%s"%[index,"forward" if direction.x>0 else "reverse"]
	phases.append({"case":name,"point_index":index,"pickup_world":point,"offset":offset,"from_frame":movie_frames})
	for hold: int in range(24):await observe(f,Vector2.ZERO,name,index,name+"_before" if hold==0 else "")
	var path: Array[Vector2]=[f.battle.player_entity().pos]
	var minimum: float=INF
	var collection: Dictionary={}
	for tick: int in range(114):
		var before: Vector2=f.battle.player_entity().pos
		var controls: Vector2=route_input(f.battle,point+offset+direction*40.0)
		f.battle.test_step(Battle.FIXED_DT,controls)
		var after: Vector2=f.battle.player_entity().pos
		path.append(after)
		var closest: Vector2=Geometry2D.get_closest_point_to_segment(point,before,after)
		minimum=minf(minimum,closest.distance_to(point))
		if f.run.rerolls_collected==1 and collection.is_empty():
			collection={"movie_frame":movie_frames,"position_before":before,"position_after":after,"closest_world_sweep":closest,
				"world_distance":closest.distance_to(point),"render_pose":f.battle.full_top_render_pose(f.battle.player_entity()),"pickup":f.tokens.presentation_snapshot()}
		var flair: bool=not f.tokens.presentation_snapshot().collection_flairs.is_empty()
		await observe(f,controls,name,index,name+"_receipt" if flair else "")
	check(f.run.rerolls_collected==1 and f.tokens.items.is_empty(),"Actual steering collects point%d in both directions"%index)
	check(minimum>Pickups.COLLECT_RADIUS,"Film proves visible blade correspondence beyond old floor-only circle")
	phases[-1].to_frame=movie_frames;phases[-1].player_world_path=path;phases[-1].nearest_world_distance=minimum;phases[-1].collection=collection
	f.battle.free()
func capacity_scene() -> void:
	var f: Dictionary=fixture(Vector2(65,0),Vector2.ZERO,true)
	f.battle.continuous=null
	for fighter: Dictionary in f.battle.fighters:
		if fighter.entity_id!=f.battle.player_entity_id:fighter.outcome="fixture_retired";fighter.pos=Vector2(-1000,-1000)
	phases.append({"case":"wallet_full","from_frame":movie_frames,"point_index":1,"pickup_world":Vector2(65,0)})
	f.battle.elapsed+=Battle.FIXED_DT;f.tokens.update_simulation()
	check(f.tokens.items.is_empty() and f.run.rerolls_collected==0,"Capacity scene suppresses the impossible drop without payment")
	for hold: int in range(72):await observe(f,Vector2.ZERO,"wallet_full",1,"wallet_full" if hold==0 else "")
	phases[-1].to_frame=movie_frames
	f.battle.free()
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		if arg.begins_with("--frames="):frames_path=arg.trim_prefix("--frames=")
		if arg=="--diagnostic":diagnostic=true
	if report_path.is_empty():push_error("Fresh external --report is required");quit(2);return
	root.min_size=Vector2i(640,360);root.size=Vector2i(640,360);root.content_scale_size=Vector2i(640,360)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames_path.is_empty():DirAccess.make_dir_recursive_absolute(frames_path)
	sound=Sound.new();root.add_child(sound);sound.set_process(false)
	for index: int in range(POINTS.size()):
		for direction: Vector2 in [Vector2(1,-1).normalized(),Vector2(-1,1).normalized()]:await scene(POINTS[index],direction,index)
	await capacity_scene()
	var data: Dictionary={"task":"003A.1 enemy foundation pickup correction","mode":"native_actual_solver_position_fixtures","diagnostic":diagnostic,
		"native_view":[640,360],"movie_frames":movie_frames,"nominal_seconds":float(movie_frames)/60.0,"phases":phases,"rows":capture_rows,
		"feature_frames":feature_frames,"checks":checks,"failures":failures,"sound_counts":sound.played_counts.duplicate(),"radius":Pickups.COLLECT_RADIUS,
		"no_main_or_player_save_opened":true,"authenticity":"Explicit independent drop, starter, starting-pose and retired-opponent fixtures; no Main/drafts/director/human-input claim. Each of the16 visible-overlap traversals uses real fixed60Hz Battle motion and waypoint steering, no teleports or RPM refills inside a traversal. Battle fixed-tick collector executes; collector render process disabled. Production native arena/top/pickup art and Sound event route are rendered. All8 drops and both approach directions shown; separate final capacity scene has no payable drop. No player collection/preferences/backups are opened."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(portable(data),"\t"));file.close()
	for channel: AudioStreamPlayer in sound.channels:channel.stop()
	sound.free();await process_frame
	print("PICKUP_COLLECTION_FIX_CAPTURE_%s frames=%d checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",movie_frames,checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
