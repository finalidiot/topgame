extends "res://tests/observe_defence_pressure.gd"
## Edited chronological excerpts of the same production fixed-tick observation.
## Skipped footage still advances every intervening real solver tick; no clock
## jump, spawn injection, reserve refill or scripted death occurs.
var diagnostic: bool = false
var frames_path: String = ""
var movie_frames: int = 0
var capture_rows: Array[Dictionary] = []
var title_label: Label
var state_label: Label
var controls_label: Label
var footer_label: Label
var saved_frames: Array[String] = []
const Music = preload("res://scripts/music.gd")
const Sound = preload("res://scripts/sound.gd")
var music: Node
var sounds: Node
var recording: bool = false
var afk_end: float = 486.733333
var caption_layer: CanvasLayer

func make_battle(seed_value: int) -> Node2D:
	var b: Node2D = super.make_battle(seed_value)
	b.event_sfx.connect(func(kind: String) -> void:
		if recording and not diagnostic: sounds.play_sound(kind); music.notify_cue(kind))
	return b

func label_at(text: String, at: Vector2, width: float, color: Color = Color("e4ebd6")) -> Label:
	var label: Label = Label.new()
	label.text = text; label.position = at; label.size = Vector2(width,18)
	label.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"))
	label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_color",color)
	caption_layer.add_child(label)
	return label

func paint(b: Node2D, policy: String, heading: String, c: Dictionary) -> void:
	var p: Dictionary = b.player_entity()
	var census: Dictionary = b.continuous.census()
	if music != null: music.observe_run(b.continuous.snapshot(),b.player_entity())
	title_label.text = "003A DEFENCE PRESSURE / "+heading
	state_label.text = "%02d:%02d  SPIN %d%%  CENTRE %.1f  FULL %d  AMMO %d" % [int(b.elapsed)/60,int(b.elapsed)%60,int(float(p.rpm)*100.0),Vector2(p.pos).length(),census.active_full,b.swarm.active_count()]
	controls_label.text = "NO STEERING / NO BRAKE / NO BURST" if policy == "zero_input" else "FINE CENTRE CORRECTIONS / STEER %.2f" % Vector2(c.direction).length()
	if b.battle_status == "finished": controls_label.text = "NATURAL "+str(b.last_result.get("reason","")).to_upper()+" / NO SCRIPTED OUTCOME"
	footer_label.text = "INVESTED BASTION FIXTURE / AUTOMATED CONTROLS / REAL PHYSICS + DIRECTOR"
	b.queue_redraw()
	if capture_rows.size() < 10000:
		var committed: Array[int] = []
		for f: Dictionary in b.fighters:
			if f.get("role_attack_state","") == "committed" and str(f.outcome).is_empty(): committed.append(int(f.entity_id))
		capture_rows.append({"movie_frame":movie_frames,"policy":policy,"section":heading,"time":b.elapsed,"rpm":p.rpm,"radius":Vector2(p.pos).length(),"input":[c.direction.x,c.direction.y],"brake":c.brake,"burst":c.burst,"committed":committed,"hits":b.hits,"full":census.active_full,"small":b.swarm.active_count(),"status":b.battle_status})

func movie_frame(b: Node2D, policy: String, heading: String, c: Dictionary, feature: String = "") -> void:
	paint(b,policy,heading,c)
	if not diagnostic:
		await process_frame
		if not feature.is_empty() and not frames_path.is_empty():
			await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			image.resize(640,360,Image.INTERPOLATE_NEAREST)
			var path: String = frames_path.path_join(feature+".png")
			image.save_png(path)
			saved_frames.append(path)
	movie_frames += 1

func advance_until(b: Node2D, policy: String, target: float, tick: int) -> int:
	recording = false
	while b.battle_status == "battle" and b.elapsed < target and tick < 70000:
		var c: Dictionary = controls(b,policy,tick)
		b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		tick += 1
	return tick

func film_until(b: Node2D, policy: String, target: float, tick: int, heading: String, feature: String) -> int:
	recording = true
	var first: bool = true
	while b.battle_status == "battle" and b.elapsed < target and tick < 70000:
		var c: Dictionary = controls(b,policy,tick)
		b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		await movie_frame(b,policy,heading,c,feature if first else "")
		first = false
		tick += 1
	return tick

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): output = arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frames_path = arg.trim_prefix("--frames=")
		if arg == "--diagnostic": diagnostic = true
		if arg.begins_with("--afk-end="): afk_end = float(arg.trim_prefix("--afk-end="))
	if output.is_empty() or not output.is_absolute_path(): push_error("External manifest required"); quit(2); return
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(640,360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames_path.is_empty(): DirAccess.make_dir_recursive_absolute(frames_path)
	caption_layer = CanvasLayer.new(); caption_layer.layer = 30; root.add_child(caption_layer)
	title_label = label_at("",Vector2(12,12),616)
	state_label = label_at("",Vector2(12,30),616)
	controls_label = label_at("",Vector2(12,48),616,Color("79c9ed"))
	footer_label = label_at("",Vector2(12,340),616)
	sounds = Sound.new(); root.add_child(sounds)
	music = Music.new(); root.add_child(music)
	music.configure_playback(not diagnostic)
	music.set_context("run")
	var summaries: Array[Dictionary] = []
	var b: Node2D = make_battle(421)
	var tick: int = 0
	for section: Dictionary in [{"from":0.0,"to":12.0,"name":"EARLY / THE FORTRESS HOLDS","feature":"early"},{"from":180.0,"to":195.0,"name":"MID / REAL HEAVY STRIKES","feature":"mid"},{"from":360.0,"to":377.0,"name":"LATE / OVERLAPPING APPROACHES","feature":"late"},{"from":540.0,"to":563.0,"name":"EXTREME / ACTIVE CENTRE DEFENCE","feature":"extreme"},{"from":620.0,"to":638.0,"name":"TEN MINUTES / STILL HOLDING","feature":"ten_minutes"}]:
		tick = advance_until(b,"active_centre",float(section.from),tick)
		tick = await film_until(b,"active_centre",float(section.to),tick,str(section.name),str(section.feature))
		if b.battle_status != "battle": break
	summaries.append({"policy":"active_centre","seconds":b.elapsed,"reason":b.last_result.get("reason","observation_horizon"),"rpm":b.player_entity().rpm,"hits":b.hits,"simulation_ticks":tick,"economy":b.continuous.economy.snapshot(),"director":b.continuous.director.history.duplicate(true)})
	b.free()
	b = make_battle(421)
	tick = await film_until(b,"zero_input",6.0,0,"ZERO INPUT / SAME EXACT FORTRESS","zero_input_start")
	tick = advance_until(b,"zero_input",maxf(6.0,afk_end-18.0),tick)
	tick = await film_until(b,"zero_input",660.0,tick,"ZERO INPUT / RESERVE IS FINITE","zero_input_late")
	for hold: int in range(180): await movie_frame(b,"zero_input","AUTOMATED OBSERVATION / NATURAL OUTCOME",{"direction":Vector2.ZERO,"brake":false,"burst":false},"natural_outcome" if hold == 0 else "")
	summaries.append({"policy":"zero_input","seconds":b.elapsed,"reason":b.last_result.get("reason","observation_horizon"),"rpm":b.player_entity().rpm,"hits":b.hits,"simulation_ticks":tick,"economy":b.continuous.economy.snapshot(),"director":b.continuous.director.history.duplicate(true)})
	b.free()
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Cannot write manifest"); quit(2); return
	file.store_string(JSON.stringify({"scope":"Chronological automated real-physics footage from a declared invested Bastion Bulwark fixture. Initial centre placement only. Gaps simulate all intervening fixed ticks; no time jump, forced enemies, health refill or scripted defeat.","native_view":[640,360],"fps":60,"initial_build":Starters.build_for("bastion"),"initial_power_ids":POWER_IDS,"initial_ranks":RANKS,"director_investments":director_investments,"initial_mutation":{"dead_centre":branch},"main_created":false,"collection_accessed":false,"movie_frames":movie_frames,"nominal_seconds":float(movie_frames)/60.0,"summaries":summaries,"rows":capture_rows,"feature_frames":saved_frames},"\t"))
	file.close()
	print("DEFENCE_PRESSURE_CAPTURE_PASS movie_frames=%d active=%.2f afk=%.2f outcome=%s" % [movie_frames,summaries[0].seconds,summaries[1].seconds,summaries[1].reason])
	music.configure_playback(false)
	music.free(); sounds.free()
	title_label.free(); state_label.free(); controls_label.free(); footer_label.free()
	caption_layer.free()
	if not diagnostic:
		await process_frame
		await process_frame
	quit(0)
