extends "res://tests/observe_bastion_active_defence.gd"
## Edited native-speed excerpts. Each cut executes every skipped solver tick;
## every body, reserve, power recharge and outcome follows production rules.
const Music = preload("res://scripts/music.gd")
const Sound = preload("res://scripts/sound.gd")
var plan_path: String = ""
var frames_path: String = ""
var diagnostic: bool = false
var recording: bool = false
var movie_frames: int = 0
var movie_rows: Array[Dictionary] = []
var filmed_impacts: Array[Dictionary] = []
var cases: Dictionary = {}
var summaries: Array[Dictionary] = []
var sections: Array[Dictionary] = []
var saved_frames: Array[String] = []
var caption_layer: CanvasLayer
var labels: Array[Label] = []
var music: Node
var sounds: Node
var current_section: String = ""

func make_case(case: Dictionary) -> Dictionary:
	var b: Node2D = make_battle(int(case.seed),"bastion",str(case.stage))
	b.visible = false
	b.event_sfx.connect(func(kind: String) -> void:
		if recording and b.visible and not diagnostic: sounds.play_sound(kind); music.notify_cue(kind))
	b.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		if not recording or not b.visible: return
		if int(event.first_entity_id) != 1 and int(event.second_entity_id) != 1: return
		var row: Dictionary = event.duplicate(true)
		row.case_id = case.id; row.section = current_section; row.movie_frame = movie_frames
		row.player = player_reading(b)
		filmed_impacts.append(row))
	return {"configuration":case,"battle":b,"tick":0,"state":{},"handoff":{}}

func player_reading(b: Node2D) -> Dictionary:
	var p: Dictionary = b.player_entity()
	return {"time":b.elapsed,"rpm":p.rpm,"radius":Vector2(p.pos).length(),"speed":Vector2(p.vel).length(),"wobble":p.wobble,"position":p.pos,"velocity":p.vel,"mass":1.0/b.powers.inverse_mass(p),"powers":public_power_state(p),"losses":b.continuous.economy.losses.duplicate(),"gains":b.continuous.economy.gains.duplicate(),"power_procs":b.powers.counters.duplicate(),"defence":b.powers.defence.diagnostics(p)}

func one_tick(entry: Dictionary) -> Dictionary:
	var b: Node2D = entry.battle
	if entry.handoff.is_empty() and b.elapsed >= warmup:
		entry.handoff = {"time":b.elapsed,"player":player_reading(b),"battle":b.snapshot(),"power_runtime":b.powers._states.duplicate(true),"defence_runtime":b.powers.defence.states.duplicate(true),"roster_runtime":b.roster.states.duplicate(true),"rng":random_state(b)}
	var policy: String = str(entry.configuration.policy) if b.elapsed >= warmup else "warmup"
	var c: Dictionary = controls(b,policy,int(entry.tick),entry.state)
	b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
	entry.tick = int(entry.tick)+1
	return c

func advance_until(entry: Dictionary, target: float) -> void:
	recording = false
	var b: Node2D = entry.battle
	while b.battle_status == "battle" and b.elapsed < target and int(entry.tick) < 150000:
		one_tick(entry)

func caption(at: Vector2, color: Color = Color("e4ebd6")) -> Label:
	var label: Label = Label.new(); label.position = at; label.size = Vector2(624,18)
	label.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"))
	label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_color",color)
	caption_layer.add_child(label)
	return label

func frame(entry: Dictionary, section: Dictionary, c: Dictionary, first: bool) -> void:
	var b: Node2D = entry.battle; var p: Dictionary = b.player_entity()
	var census: Dictionary = b.continuous.census()
	var quota: float = float(p.get("anchor_recovery_remaining",0.0))
	labels[0].text = "003A.1 / "+str(section.title)
	labels[1].text = "%02d:%02d  RPM %.1f%%  CENTRE %.1f  FULL %d / SMALL %d" % [int(b.elapsed)/60,int(b.elapsed)%60,float(p.rpm)*100.0,Vector2(p.pos).length(),census.active_full,b.swarm.active_count()]
	labels[2].text = "ZERO INPUT / NO STEERING, BRAKE OR BURST" if entry.configuration.policy == "zero_input" else "STEER %.2f / BRAKE %s / %s" % [Vector2(c.direction).length(),"ON" if c.brake else "OFF",str(c.mode).replace("_"," ").to_upper()]
	labels[3].text = "DEAD CENTRE QUOTA %.1f%% / RELOAD %d%% / STORED SHOCK %.0f" % [quota*100.0,roundi(float(p.get("anchor_rearm_progress",0.0))*100.0),float(p.get("sink_charge",0.0))]
	if section.id == "04_heavy_reception":
		var earned: float = 0.0
		for source: String in ["elimination","elite","boss"]: earned += float(b.continuous.economy.gains.get(source,0.0))
		labels[3].text = "EFFECTIVE MASS %.1f / ATTRIBUTED RPM RECOVERED +%.1f%%" % [1.0/b.powers.inverse_mass(p),(earned-float(entry.film_earned_start))*100.0]
	labels[4].text = "LEGAL INVESTED "+str(entry.configuration.stage).to_upper()+" / REAL 6-MIN WARMUP / NATIVE SPEED"
	labels[5].text = "AUTOMATED DEFENCE / EVERY SKIPPED TICK SIMULATED / HUMAN FEEL AWAITS REVIEW"
	if b.battle_status == "finished": labels[2].text = "NATURAL "+str(b.last_result.get("reason","")).to_upper()+" / NO SCRIPTED OUTCOME"
	music.observe_run(b.continuous.snapshot(),p)
	b.queue_redraw()
	if first or movie_frames % 15 == 0:
		var row: Dictionary = player_reading(b)
		row.movie_frame = movie_frames; row.case_id = entry.configuration.id; row.section = section.id
		row.input = [c.direction.x,c.direction.y]; row.brake = c.brake; row.burst = c.burst; row.mode = c.mode
		movie_rows.append(row)
	if not diagnostic:
		await process_frame
		if first and not frames_path.is_empty():
			await RenderingServer.frame_post_draw
			var path: String = frames_path.path_join(str(section.id)+".png")
			root.get_texture().get_image().save_png(path); saved_frames.append(path)
	movie_frames += 1

func film(entry: Dictionary, section: Dictionary) -> void:
	var b: Node2D = entry.battle
	advance_until(entry,float(section.from))
	var start: Dictionary = player_reading(b)
	entry.film_earned_start = 0.0
	for source: String in ["elimination","elite","boss"]: entry.film_earned_start += float(b.continuous.economy.gains.get(source,0.0))
	var first_frame: int = movie_frames
	b.visible = true; recording = true; current_section = section.id
	while b.battle_status == "battle" and b.elapsed < float(section.to) and int(entry.tick) < 150000:
		var c: Dictionary = one_tick(entry)
		await frame(entry,section,c,movie_frames == first_frame)
	recording = false; b.visible = false
	sections.append({"configuration":section,"movie_start_frame":first_frame,"movie_end_frame":movie_frames,"start":start,"end":player_reading(b),"ended_naturally":b.battle_status == "finished","result":b.last_result.duplicate(true)})

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="): output = argument.trim_prefix("--manifest=")
		if argument.begins_with("--plan="): plan_path = argument.trim_prefix("--plan=")
		if argument.begins_with("--frames="): frames_path = argument.trim_prefix("--frames=")
		if argument == "--diagnostic": diagnostic = true
	if not output.is_absolute_path() or FileAccess.file_exists(output) or not plan_path.is_absolute_path():
		push_error("Fresh external manifest and external capture plan required"); quit(2); return
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if plan.get("sections",[]).size() != 5: push_error("Five declared review sections required"); quit(2); return
	opening_time = 0.0; warmup = 360.0; handling_override = {}
	root.size = Vector2i(640,360); root.content_scale_size = Vector2i(640,360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames_path.is_empty(): DirAccess.make_dir_recursive_absolute(frames_path)
	caption_layer = CanvasLayer.new(); caption_layer.layer = 30; root.add_child(caption_layer)
	for at: Vector2 in [Vector2(8,8),Vector2(8,25),Vector2(8,42),Vector2(8,59),Vector2(8,323),Vector2(8,340)]: labels.append(caption(at))
	sounds = Sound.new(); root.add_child(sounds)
	music = Music.new(); root.add_child(music); music.configure_playback(not diagnostic); music.set_context("run")
	for case: Dictionary in plan.cases: cases[case.id] = make_case(case)
	for section: Dictionary in plan.sections: await film(cases[section.case_id],section)
	for id: String in cases:
		var entry: Dictionary = cases[id]; var b: Node2D = entry.battle
		summaries.append({"configuration":entry.configuration,"simulation_ticks":entry.tick,"handoff":entry.handoff,"end":player_reading(b),"economy":b.continuous.economy.snapshot(),"director":b.continuous.director.history.duplicate(true),"result":b.last_result.duplicate(true)})
		b.free()
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Cannot preserve capture manifest"); quit(2); return
	file.store_string(JSON.stringify({"schema":"003a1-native-active-defence-review-v1","scope":"Five labelled native-speed excerpts from disclosed legal invested openings and real six-minute common warmup. No synthetic mature clock, live repositioning, quota/RPM refill, forced enemy, forced force or forced outcome. Cuts execute all skipped fixed solver ticks.","native_view":[640,360],"fps":60,"main_created":false,"collection_accessed":false,"warmup_seconds":warmup,"handling":Starters.HANDLING.bastion,"movie_frames":movie_frames,"nominal_seconds":float(movie_frames)/60.0,"sections":sections,"cases":summaries,"rows":movie_rows,"filmed_impacts":filmed_impacts,"feature_frames":saved_frames,"plan":plan_path},"\t")); file.close()
	music.configure_playback(false); music.free(); sounds.free(); caption_layer.free()
	if not diagnostic: await process_frame; await process_frame
	print("BASTION_ACTIVE_DEFENCE_CAPTURE_PASS movie_frames=%d sections=%d" % [movie_frames,sections.size()])
	quit(0)
