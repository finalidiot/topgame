extends "res://tests/observe_dead_centre_stress.gd"
## Edited native-speed excerpts. Each cut executes every skipped solver tick;
## every body, reserve, power recharge and outcome follows production rules.
const StateMeters = preload("res://scripts/power_state_meters.gd")
const Menus = preload("res://scripts/menus.gd")
var meters: Control
var hud_menu: Control
var full_hud: bool = false
var mapped_events: int = 0
var review_pointer_events: int = 0

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
	investments = 0
	for value: int in STAGES[str(case.stage)].ranks.values(): investments += value
	investments = maxi(1, investments)
	var b: Node2D = make_battle(int(case.seed),str(case.get("starter","bastion")),str(case.stage))
	b.visible = false
	b.hud_updated.connect(func(stats: Dictionary) -> void:
		if not full_hud or not recording or not b.visible: return
		var enriched: Dictionary = stats.duplicate(true)
		var p: Dictionary = b.player_entity()
		enriched.owned_power_ids = p.powers.duplicate()
		enriched.power_ranks = p.power_ranks.duplicate(true)
		enriched.power_mutations = p.power_mutations.duplicate(true)
		enriched.starter_id = p.starter_id
		enriched.is_run = true
		enriched.level = b.continuous.progression_level
		enriched.progression_max = true
		enriched.run_label = "QA / MAPPED INPUT"
		hud_menu.show_hud(enriched))
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
	return {"time":b.elapsed,"rpm":p.rpm,"radius":Vector2(p.pos).length(),"speed":Vector2(p.vel).length(),"wobble":p.wobble,"position":p.pos,"velocity":p.vel,"mass":1.0/b.powers.inverse_mass(p),"attack_multiplier":b.powers.attack_multiplier(p),"power_diagnostics":b.powers.diagnostics(p),"powers":public_power_state(p),"losses":b.continuous.economy.losses.duplicate(),"gains":b.continuous.economy.gains.duplicate(),"power_procs":b.powers.counters.duplicate(),"defence":b.powers.defence.diagnostics(p)}

func mapped_input(direction: Vector2, burst: bool, brake: bool) -> void:
	var magnitude: float = clampf(direction.length(),0.0,1.0)
	var raw: Vector2 = direction.normalized()*(0.22+0.78*magnitude) if magnitude > 0.0 else Vector2.ZERO
	for axis: int in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
		var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
		event.device = 29; event.axis = axis; event.axis_value = raw.x if axis == JOY_AXIS_LEFT_X else raw.y
		Input.parse_input_event(event); mapped_events += 1
	for value: Array in [[JOY_BUTTON_A,burst],[JOY_BUTTON_LEFT_SHOULDER,brake]]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 29; event.button_index = int(value[0]); event.pressed = bool(value[1])
		Input.parse_input_event(event); mapped_events += 1
	Input.flush_buffered_events()

func clear_review_pointer() -> void:
	# Real pointer input into blank upper-centre HUD space keeps the gamepad
	# review's meters visible. It does not modify the Inspector or simulation.
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(320, 92); motion.global_position = motion.position
	Input.parse_input_event(motion); Input.flush_buffered_events()
	review_pointer_events += 1

func controls(b: Node2D, policy: String, tick: int, state: Dictionary) -> Dictionary:
	if policy == "meters_demo": return meter_controls(b, tick, state)
	if policy not in ["anchor_redline","redline_attack"]: return super.controls(b,policy,tick,state)
	var p: Dictionary = b.player_entity()
	var position: Vector2 = p.pos
	var velocity: Vector2 = p.vel
	var stress: float = float(p.get("anchor_stress",0.0))
	if policy == "anchor_redline":
		if stress >= 0.55 or str(state.get("recharge","none")) != "none": return super.controls(b,"minimal_active",tick,state)
		var direction: Vector2 = (-position*0.9-velocity*0.35).normalized()*0.24
		if position.length() < 8.0 and velocity.length() < 4.0: direction = Vector2.RIGHT*0.20
		var burst: bool = b.elapsed >= float(state.get("burst_ready",3.0)) and float(p.cooldown) <= 0.0 and position.length() < 45.0
		if burst: state.burst_ready = b.elapsed+8.0
		var active: bool = b.powers.redline_active(p)
		var brake: bool = active and (float(p.get("anchor_charge",0.0)) < 0.75 or velocity.length() > 70.0)
		return {"direction":project_input(direction),"burst":burst,"brake":brake,"mode":"anchored_overclock" if active else "claim_centre"}
	var target: Dictionary = b._target_for(p)
	var offset: Vector2 = Vector2(target.pos)-position if not target.is_empty() else -position
	var direction: Vector2 = (offset+Vector2(target.get("vel",Vector2.ZERO))*0.10-velocity*0.10).normalized()*0.65
	if position.length() > 135.0: direction = -position.normalized()*0.65
	var burst: bool = float(p.cooldown) <= 0.0 and not target.is_empty() and offset.length() < 95.0 and b.elapsed >= float(state.get("burst_ready",1.0))
	if burst: state.burst_ready = b.elapsed+7.0
	return {"direction":project_input(direction),"burst":burst,"brake":false,"mode":"redline_attack"}

func meter_controls(b: Node2D, tick: int, state: Dictionary) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var pos: Vector2 = p.pos
	var vel: Vector2 = p.vel
	if b.elapsed < 16.0:
		var c: Dictionary = controls(b, "redline_attack", tick, state)
		c.brake = float(p.get("sink_charge",0.0)) >= 15.0 and fmod(b.elapsed,3.0) < 0.25
		c.mode = "overdrive_and_stored_force"
		return c
	if b.elapsed < 28.0:
		var radial: Vector2 = pos.normalized() if pos.length() > 1.0 else Vector2.RIGHT
		var tangent: Vector2 = radial.orthogonal()
		var desired: Vector2 = tangent * 150.0 + radial * (72.0 - pos.length()) * 2.5
		var direction: Vector2 = (desired - vel).normalized() * 0.85
		var angle: float = absf(vel.normalized().angle_to(direction.normalized()))
		return {"direction":project_input(direction),"burst":false,"brake":vel.length() > 82.0 and angle >= 0.12 and angle < 2.25,"mode":"carve_to_build_drive"}
	if b.elapsed < 32.0:
		return {"direction":project_input(vel.normalized() * 0.35),"burst":false,"brake":true,"mode":"slow_to_scrub_drive"}
	if float(p.get("anchor_stress",0.0)) >= 0.55 or str(state.get("recharge","none")) != "none":
		return super.controls(b, "minimal_active", tick, state)
	var direction: Vector2 = (-pos * 1.3 - vel * 0.45).normalized() * (0.65 if pos.length() > 20.0 else 0.24)
	if pos.length() < 8.0 and vel.length() < 5.0: direction = Vector2.ZERO
	return {"direction":project_input(direction),"burst":false,"brake":pos.length() < 55.0 and vel.length() > 25.0,"mode":"claim_centre_under_pressure"}

func one_tick(entry: Dictionary) -> Dictionary:
	var b: Node2D = entry.battle
	if entry.handoff.is_empty() and b.elapsed >= warmup:
		entry.handoff = {"time":b.elapsed,"player":player_reading(b),"battle":b.snapshot(),"power_runtime":b.powers._states.duplicate(true),"defence_runtime":b.powers.defence.states.duplicate(true),"roster_runtime":b.roster.states.duplicate(true),"rng":random_state(b)}
	var policy: String = str(entry.configuration.policy) if b.elapsed >= warmup else "warmup"
	var c: Dictionary = controls(b,policy,int(entry.tick),entry.state)
	mapped_input(c.direction,c.burst,c.brake)
	b._physics_process(Battle.FIXED_DT)
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
	meters.update_state(b.powers.public_state(p))
	if full_hud: b._emit_hud()
	if full_hud: clear_review_pointer()
	labels[0].text = "003A.1 / "+str(section.title)
	labels[1].text = "%02d:%02d  RPM %.1f%%  STEER %.2f / BRAKE %s / BURST %s" % [int(b.elapsed)/60,int(b.elapsed)%60,float(p.rpm)*100.0,Vector2(c.direction).length(),"ON" if c.brake else "OFF","ON" if c.burst else "OFF"]
	labels[2].text = str(c.mode).replace("_"," ").to_upper()+" / REAL CONTACTS + MAPPED CONTROLS / REVIEW PENDING"
	if full_hud:
		labels[0].text = str(section.get("hud_caption", section.title))
		labels[1].visible = false; labels[2].visible = false
	if b.battle_status == "finished": labels[2].text = "NATURAL "+str(b.last_result.get("reason","")).to_upper()+" / NO SCRIPTED OUTCOME"
	music.observe_run(b.continuous.snapshot(),p)
	b.queue_redraw()
	if first or movie_frames % 5 == 0:
		var row: Dictionary = player_reading(b)
		row.movie_frame = movie_frames; row.case_id = entry.configuration.id; row.section = section.id
		row.input = [c.direction.x,c.direction.y]; row.brake = c.brake; row.burst = c.burst; row.mode = c.mode
		row.meters = hud_menu._hud.state_meters.diagnostic_snapshot() if full_hud else meters.diagnostic_snapshot()
		movie_rows.append(row)
	if not diagnostic:
		await process_frame
		if (first or movie_frames % 300 == 0) and not frames_path.is_empty():
			await RenderingServer.frame_post_draw
			var path: String = frames_path.path_join(str(section.id)+"_%06d.png" % movie_frames)
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
	full_hud = bool(plan.get("show_hud",false))
	if plan.get("sections",[]).is_empty(): push_error("Declared real review sections required"); quit(2); return
	opening_time = 0.0; warmup = float(plan.get("warmup",504.0)); handling_override = {}
	root.size = Vector2i(640,360); root.content_scale_size = Vector2i(640,360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames_path.is_empty(): DirAccess.make_dir_recursive_absolute(frames_path)
	caption_layer = CanvasLayer.new(); caption_layer.layer = 30; root.add_child(caption_layer)
	for at: Vector2 in [Vector2(8,8),Vector2(8,25),Vector2(8,340)]: labels.append(caption(at))
	meters = StateMeters.new(); caption_layer.add_child(meters)
	if full_hud:
		meters.visible = false
		hud_menu = Menus.new(); caption_layer.add_child(hud_menu)
		labels[0].position = Vector2(240,96); labels[0].size = Vector2(160,32)
		labels[0].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		labels[0].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels[0].z_index = 5
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
	plan["review_pointer"] = {"native_position":[320,92],"actual_mouse_motion_events":review_pointer_events,"scope":"Actual pointer input over blank upper-centre HUD space; gameplay and Inspector state are never written."}
	file.store_string(JSON.stringify({"schema":"003a1-native-anchor-stress-review-v1","mapped_controller_events":mapped_events,"scope":"Labelled native-speed excerpts from disclosed legal invested openings and real common warmup. All observed controls enter the genuine InputMap and production _physics_process path; exact production StateMeters control renders authoritative runtime state. No synthetic mature clock, live repositioning, quota/RPM refill, forced enemy, forced force or forced outcome. Cuts execute all skipped fixed solver ticks.","full_production_hud":full_hud,"native_view":[640,360],"fps":60,"main_created":false,"collection_accessed":false,"warmup_seconds":warmup,"handling":Starters.HANDLING.bastion,"movie_frames":movie_frames,"nominal_seconds":float(movie_frames)/60.0,"sections":sections,"cases":summaries,"rows":movie_rows,"filmed_impacts":filmed_impacts,"feature_frames":saved_frames,"plan":plan_path},"\t")); file.close()
	music.configure_playback(false); music.free(); sounds.free(); caption_layer.free()
	if not diagnostic: await process_frame; await process_frame
	print("ANCHOR_STRESS_CAPTURE_PASS movie_frames=%d sections=%d" % [movie_frames,sections.size()])
	quit(0)
