extends "res://tests/test_rpm_playthrough.gd"
## Normal Main, owned starter, actual seeded clears, ordinary inputs/earned
## drafts. Only skipped warmup ticks are omitted; no pickup/position fixtures.
var game: QuietMain
var manifest_path: String = ""
var profile_path: String = ""
var frames_path: String = ""
var diagnostic: bool = false
var capture_seed: int = 421
var capture_starter: String = "vane"
var movie_frames: int = 0
var simulation_tick: int = 0
var recording: bool = false
var captures: Dictionary = {}
var rows: Array[Dictionary] = []
var clears: Array[Dictionary] = []
var collections: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var failures: Array[String] = []
var current_phase: String = "warmup"

static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value: out[str(key)]=portable(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value: out.append(portable(item))
		return out
	return value

static func approach(b: Node2D, point: Vector2, strength: float=1.0) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var offset: Vector2 = point-Vector2(p.pos)
	var desired: Vector2 = offset.limit_length(60.0)*2.2-Vector2(p.vel)*1.05
	var world: Vector2 = desired.limit_length(90.0)/90.0*strength
	return {"direction":Vector2(world.x-world.y,(world.x+world.y)*0.5).limit_length(1.0),"burst":false,"brake":offset.length()<25.0 and Vector2(p.vel).length()>42.0}

func step_game(controls: Dictionary) -> void:
	var b: Node2D = game.battle
	var before_position: Vector2 = b.player_entity().pos
	var before_items: Array[Dictionary] = game.reroll_pickups.items.duplicate(true)
	var before_collected: int = game.run_context.rerolls_collected
	b.test_step(Battle.FIXED_DT,controls.direction,controls.burst,controls.brake)
	game.reroll_pickups.update_simulation()
	if game.run_context.rerolls_collected>before_collected:
		for item: Dictionary in before_items:
			if game.reroll_pickups.items.any(func(value: Dictionary) -> bool: return value.id==item.id): continue
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(item.pos),before_position,Vector2(b.player_entity().pos))
			collections.append({"id":item.id,"pickup_position":item.pos,"time":b.elapsed,"movie_frame":movie_frames if recording else -1,"phase":current_phase,
				"actual_swept_gap":closest.distance_to(Vector2(item.pos)),"position_before":before_position,"position_after":b.player_entity().pos,
				"played_counts":game.sounds.played_counts.duplicate(),"pickup":game.reroll_pickups.presentation_snapshot()})
	if game.screen=="level_up": game._process(.2)
	while game.screen in ["reward","mutation"]: choose(game)
	simulation_tick += 1

func observe(controls: Dictionary, feature: String="") -> void:
	var b: Node2D = game.battle
	var pickup: Dictionary = game.reroll_pickups.presentation_snapshot()
	rows.append({"movie_frame":movie_frames,"phase":current_phase,"time":b.elapsed,"screen":game.screen,"battle_status":b.battle_status,
		"position":b.player_entity().pos,"rpm":b.player_entity().rpm,"input":controls,"pickup":pickup,"rerolls":game.run_context.reroll_charges,
		"collected":game.run_context.rerolls_collected,"sound_counts":game.sounds.played_counts.duplicate(),"hits":b.hits})
	if not diagnostic:
		b.queue_redraw();game.reroll_pickups.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		if not feature.is_empty() and not captures.has(feature):
			var image: Image = root.get_texture().get_image();image.resize(640,360,Image.INTERPOLATE_NEAREST)
			var path: String = frames_path.path_join(feature+".png")
			if image.save_png(path)!=OK:failures.append("Could not save native frame "+feature)
			captures[feature]={"path":path,"movie_frame":movie_frames,"pickup":pickup}
	movie_frames += 1

func await_drop() -> int:
	var ticks: int = 0
	while game.reroll_pickups.items.is_empty() and game.screen!="result" and ticks<60*150:
		step_game(Bot.input(game.battle,"hybrid",simulation_tick));ticks+=1
	return ticks

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): manifest_path=arg.trim_prefix("--manifest=")
		if arg.begins_with("--profile="): profile_path=arg.trim_prefix("--profile=")
		if arg.begins_with("--frames="): frames_path=arg.trim_prefix("--frames=")
		if arg.begins_with("--starter="): capture_starter=arg.trim_prefix("--starter=")
		if arg.begins_with("--run-seed="): capture_seed=int(arg.trim_prefix("--run-seed="))
		if arg=="--diagnostic":diagnostic=true
	if manifest_path.is_empty() or profile_path.is_empty() or capture_starter not in Starters.IDS:
		push_error("Supply fresh external --manifest and --profile; optional owned --starter");quit(2);return
	root.size=Vector2i(640,360);root.content_scale_size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames_path.is_empty():DirAccess.make_dir_recursive_absolute(frames_path)
	game=QuietMain.new();game.smoke_mode=true;game.collection_path=profile_path;root.add_child(game);game.set_process(false)
	if not bool(game.collection.initialize_starter(capture_starter).ok):failures.append("Fresh isolated owned starter could not initialize")
	game._start_run();opening_preference="iron_comet";choose(game)
	game.battle.set_process(false);game.battle.set_physics_process(false);game.reroll_pickups.set_process(false)
	game.battle.threat_cleared.connect(func(summary: Dictionary) -> void: clears.append(summary.duplicate(true)))
	var warmup: int = await_drop()
	if game.reroll_pickups.items.is_empty():failures.append("Real seeded combat did not earn a chip")
	var first: Dictionary = game.reroll_pickups.items[0].duplicate(true) if not game.reroll_pickups.items.is_empty() else {}
	var initial_collection: PackedByteArray = FileAccess.get_file_as_bytes(profile_path)
	recording=true;game.review_audio=not diagnostic
	game.music.configure_playback(not diagnostic);game.music.set_context("run");game.music.set_paused(false)
	current_phase="off_centre_approach";phases.append({"phase":current_phase,"from_frame":movie_frames})
	var collected_before: int = game.run_context.rerolls_collected
	if not first.is_empty():
		var offset: Vector2 = (Vector2(first.pos)-Vector2(game.battle.player_entity().pos)).normalized()
		var waypoint: Vector2 = Vector2(first.pos)+Vector2(-offset.y,offset.x)*16.0
		for tick: int in range(420):
			var controls: Dictionary = approach(game.battle,waypoint)
			step_game(controls)
			var flair: bool = not game.reroll_pickups.presentation_snapshot().collection_flairs.is_empty()
			await observe(controls,"approach" if tick==0 else ("collection_flair" if flair else ""))
			if game.run_context.rerolls_collected>collected_before or game.screen=="result":break
		if game.run_context.rerolls_collected<=collected_before:failures.append("Actual slightly off-centre controls did not collect")
		for hold: int in range(90):
			var controls: Dictionary = approach(game.battle,Vector2.ZERO,0.65);step_game(controls)
			var flairs: Array = game.reroll_pickups.presentation_snapshot().collection_flairs
			var peak: bool = flairs.any(func(flair: Dictionary) -> bool: return int(flair.frame)==2)
			await observe(controls,"collection_flair_peak" if peak else ("collected_floor" if hold==40 else ""))
	phases[-1].to_frame=movie_frames
	recording=false;game.review_audio=false;game.music.configure_playback(false)
	var between: int = await_drop()
	var second: Dictionary = game.reroll_pickups.items[0].duplicate(true) if not game.reroll_pickups.items.is_empty() else {}
	if second.is_empty():failures.append("Natural subsequent combat did not produce expiry chip")
	recording=true;game.review_audio=not diagnostic;game.music.configure_playback(not diagnostic)
	current_phase="hold_centre_expiry";phases.append({"phase":current_phase,"from_frame":movie_frames})
	var expired_before: int = game.reroll_pickups.expired_count
	var second_collected_before: int = game.run_context.rerolls_collected
	if not second.is_empty():
		for tick: int in range(1200):
			var controls: Dictionary = approach(game.battle,Vector2.ZERO,0.65);step_game(controls)
			var active: Array = game.reroll_pickups.presentation_snapshot().active
			var warning: bool = active.any(func(item: Dictionary) -> bool: return item.id==second.id and item.warning)
			await observe(controls,"expiry_warning" if warning else ("expired_floor" if game.reroll_pickups.expired_count>expired_before else ("left_on_floor" if tick==0 else "")))
			if game.reroll_pickups.expired_count>expired_before or game.screen=="result":break
		for hold: int in range(60):
			var controls: Dictionary=approach(game.battle,Vector2.ZERO,0.65);step_game(controls);await observe(controls)
	if game.reroll_pickups.expired_count<=expired_before:failures.append("Left chip did not expire during live centre hold")
	if game.run_context.rerolls_collected!=second_collected_before:failures.append("Expiry scene unexpectedly collected a chip")
	phases[-1].to_frame=movie_frames
	var profile_unchanged: bool = FileAccess.get_file_as_bytes(profile_path)==initial_collection
	if not profile_unchanged:failures.append("Review combat unexpectedly changed isolated collection")
	var report: Dictionary={"task":"003A.1","mode":"pickup_feel","main_created":true,"normal_main_floor_audio_routes":true,"native_view":[640,360],
		"starter":capture_starter,"build":Starters.build_for(capture_starter),"seed":capture_seed,"first_drop":first,"second_drop":second,"actual_clears":clears,
		"warmup_ticks_omitted":warmup,"between_scenes_ticks_omitted":between,"movie_frames":movie_frames,"nominal_seconds":float(movie_frames)/60.0,"rows":rows,
		"collections":collections,"phases":phases,"feature_frames":captures,"failures":failures,"diagnostic":diagnostic,
		"collected":game.run_context.rerolls_collected,"expired":game.reroll_pickups.expired_count,"sound_counts":game.sounds.played_counts.duplicate(),
		"isolated_profile":profile_path,"isolated_collection_unchanged_by_combat":profile_unchanged,"attraction_implemented":false,"radius_before":14,"radius_after":18,
		"final_time":game.battle.elapsed,"final_status":game.battle.battle_status,
		"authenticity":"Normal production Main owned-starter Run. Seeded offers, ordinary chosen drafts and actual cleared enemies produce drops. Off-centre pickup/centre-return inputs use the real fixed solver. Every omitted warmup tick executes. No pickup injection, teleport, reserve refill, protected player or forced outcome. Explicit isolated starter collection; smoke mode suppresses permanent reward/preferences writes, review_audio enables the unchanged ordinary sound route during recorded scenes. Captions are added below the game image, never over combat."}
	var output: FileAccess=FileAccess.open(manifest_path,FileAccess.WRITE)
	if output==null:push_error("Cannot save new external pickup manifest");quit(2);return
	output.store_string(JSON.stringify(portable(report),"\t"));output.close()
	game.music.configure_playback(false);game.review_audio=false
	for channel: AudioStreamPlayer in game.sounds.channels:channel.stop()
	game.free()
	await process_frame
	print("PICKUP_FEEL_CAPTURE_%s frames=%d collected=%d expired=%d" % ["PASS" if failures.is_empty() else "FAIL",movie_frames,report.collected,report.expired]);quit(0 if failures.is_empty() else 1)
