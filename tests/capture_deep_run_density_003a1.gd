extends "res://tests/capture_impact_music_003a1.gd"
## Accelerated starting clocks + explicit initial admissions only. After setup,
## ordinary pilot decisions, controls, powers, costs, impacts and outcomes run.
const Director = preload("res://scripts/threat_director.gd")
const Encounters = preload("res://scripts/encounters.gd")
var density_rows: Array[Dictionary]=[]

func scenario(spec: Dictionary) -> Node2D:
	var b: Node2D=Battle.new();root.add_child(b);b.set_process(false);b.set_physics_process(false)
	var descriptor: Dictionary=Encounters.for_run_event(1,421)
	descriptor.starter_id="bastion";descriptor.player_power_ids=["dead_centre"];descriptor.player_power_ranks={"dead_centre":1};descriptor.player_power_mutations={}
	b.begin_run({"blade":"guard","ratchet":"low","bit":"ball"},descriptor,421)
	while b.battle_status!="battle":b.test_step(Battle.FIXED_DT)
	b.elapsed=float(spec.clock)
	b.player_entity().pos=Vector2(-7,9);b.player_entity().vel=Vector2.ZERO
	var count: int=int(spec.count)
	var start: Vector2=Vector2(98,0)
	b.entity(2).pos=start;b.entity(2).vel=Vector2.ZERO;b.entity(2).ai_clock=0.0
	var names: Array[String]=["hunter","flanker","bulwark","harasser","hunter","flanker"]
	for index: int in range(1,count):
		var event: Dictionary={}
		for definition: Dictionary in Director.EVENTS:
			if definition.key==names[index]:event=definition.duplicate(true);break
		event["serial"]=index+1;event["tier_at_entry"]=Director.tier_at(float(spec.clock))
		var position: Vector2=Vector2(98,0).rotated(TAU*float(index)/float(count))
		b.continuous.director.active[index+1]={"time":b.elapsed,"kind":event.kind}
		b.continuous._admit(event,position)
	b.continuous.director.serial=count
	# Admission is a declared census fixture. Calm blocks only new admissions,
	# while ordinary ongoing AI, economy, event outcomes/retirement keep running.
	b.continuous.director.next_decision=99999.0;b.continuous.director.calm_until=99999.0
	b.continuous.reward_fixture=true
	b.event_sfx.connect(cue);sound.grind_provider=b.grind_audio_snapshot
	return b

func control(b: Node2D,tick: int) -> Dictionary:
	var p: Dictionary=b.player_entity()
	var age: float=float(tick)/60.0
	var goal: Vector2=Vector2(50,-12).rotated(age*0.45)
	var world: Vector2=((goal-Vector2(p.pos))*0.024-Vector2(p.vel)*0.004).limit_length(0.66)
	var screen: Vector2=Vector2(world.x-world.y,(world.x+world.y)*0.5).limit_length(1.0)
	return {"direction":screen,"burst":tick==210 and float(p.rpm)>0.35,"brake":false}

func play(spec: Dictionary) -> void:
	var b: Node2D=scenario(spec)
	var initial: Dictionary=b.continuous.census().duplicate(true)
	var limit: Dictionary=Director.limits(float(spec.clock),1)
	var peak: int=int(initial.active_full);var live_frames: int=0
	if int(initial.active_full)!=int(spec.count) or int(initial.full)>int(limit.full) or initial.small!=0 or float(initial.pressure)>float(limit.budget):failures.append("Initial legal density fixture failed "+str(spec.id))
	for tick: int in range(360):
		var c: Dictionary=control(b,tick)
		b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		var census: Dictionary=b.continuous.census()
		peak=maxi(peak,int(census.active_full))
		if b.battle_status=="battle":live_frames+=1
		if tick%15==0:
			captions("003A.1 / %s / %s / FULL CAP %d / ACTIVE %d"%[spec.label,spec.time_label,int(limit.full),int(census.active_full)],"QA CLOCK + INITIAL ADMISSIONS / REAL AI + 60HZ PHYSICS / NOT NATURAL SURVIVAL")
			music.observe_run(b.continuous.snapshot(),{"player_rpm":float(b.player_entity().rpm)})
		if tick%6==0:density_rows.append({"frame":movie_frames,"scene":spec.id,"tick":tick,"time":b.elapsed,"census":census.duplicate(true),"player_control":c,"player_rpm":b.player_entity().rpm,"player_outcome":b.player_entity().outcome,"fighters":b.fighters.duplicate(true),"powers":b.powers.counters.duplicate(true)})
		await frame(b,spec.id,tick,str(spec.id)+"_begin" if tick==0 else (str(spec.id)+"_motion" if tick==120 else (str(spec.id)+"_end" if tick==359 else "")))
	scenes.append({"id":spec.id,"label":spec.label,"clock_fixture":spec.clock,"initial_admissions_fixture":spec.count,"initial_census":initial,"limits":limit,"peak_active_full":peak,"live_frames":live_frames,"final_census":b.continuous.census(),"final_player_rpm":b.player_entity().rpm,"final_player_outcome":b.player_entity().outcome,"starting_player_powers":{"dead_centre":1},"natural_survival_claim":false})
	if peak<int(spec.count) or live_frames<120:failures.append("Insufficient real live footage "+str(spec.id))
	sound.grind_provider=Callable();sound.set_grind_state({"active":false});b.free()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="):frame_dir=arg.trim_prefix("--frames=")
		if arg=="--diagnostic":diagnostic=true
	if output.is_empty():quit(2);return
	root.size=Vector2i(640,400);root.content_scale_size=Vector2i(640,400);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty():DirAccess.make_dir_recursive_absolute(frame_dir)
	sound=Sound.new();root.add_child(sound);sound.rng.seed=421;sound.apply_settings({"volume":0.65,"sfx_volume":1.0})
	music=Music.new();root.add_child(music);music.configure_playback(not diagnostic);music.set_context("run")
	for spec: Dictionary in [{"id":"early","label":"EARLY","time_label":"00:00","clock":0.0,"count":1},{"id":"mid","label":"MID","time_label":"01:20","clock":80.0,"count":3},{"id":"late","label":"LATE","time_label":"04:40","clock":280.0,"count":4},{"id":"deep","label":"VERY DEEP","time_label":"10:40","clock":640.0,"count":5},{"id":"absurd","label":"ABSURD","time_label":"14:40","clock":880.0,"count":6}]:await play(spec)
	music.configure_playback(false);sound.grind_provider=Callable();sound._grind_player.stop()
	for channel: AudioStreamPlayer in sound.channels:channel.stop();channel.stream=null
	for label: Label in labels:label.free()
	labels.clear()
	var tail: int=0
	if diagnostic:await create_timer(0.6).timeout
	else:
		for tick: int in range(36):await process_frame;movie_frames+=1;tail+=1
	music.free();sound.free();await process_frame
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(portable({"task":"003A.1 deep Run density native review","diagnostic":diagnostic,"movie_frames":movie_frames,"teardown_frames":tail,"scenes":scenes,"rows":density_rows,"features":features,"failures":failures,"main_created":false,"collection_opened":false,"native_gameplay":[640,360],"native_caption_canvas":[640,400],"authenticity":"Explicit accelerated STARTING clocks0/80/280/640/880 and initial1/3/4/5/6 ordinary-top admissions/poses. No later position changes, reserve refills, activation grants, forced outcomes or AI edits. Actual real60Hz controls/AI/powers/solver/outcomes afterward. Additional Director admission suspended solely for stable density isolation; independent real Director scheduling/cap study is separate. One legal player Dead CentreI ownership fixture initializes normally. No natural long-Run survival/draft/input claim."}),"\t"));file.close()
	print("DEEP_RUN_NATIVE_CAPTURE_%s frames=%d"%["PASS" if failures.is_empty() else "FAIL",movie_frames]);quit(0 if failures.is_empty() else 1)
