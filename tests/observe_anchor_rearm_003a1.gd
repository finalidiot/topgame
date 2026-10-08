extends SceneTree
## Normal Main with a declared legal invested opening, followed exclusively by
## sampled mapped controls, real collisions and genuine Director/physics ticks.
const Main = preload("res://scripts/main.gd")
const Starters = preload("res://scripts/starters.gd")
const Battle = preload("res://scripts/battle.gd")
const Opening = preload("res://tests/observe_dead_centre_stress.gd")
const Runtime = preload("res://scripts/power_runtime.gd")
class QuietMain extends Main:
	func _smoke_test() -> void: pass

var report_path: String = ""
var profiles_path: String = ""
var plan_path: String = ""
var frames_path: String = ""
var diagnostic: bool = true
var mapped_events: int = 0
var frame_count: int = 0
var cases: Array[Dictionary] = []
var movie_rows: Array[Dictionary] = []
var movie_sections: Array[Dictionary] = []
var native_frames: Array[String] = []
var active_case: Dictionary = {}
var game: Node2D
var caption_layer: CanvasLayer
var heading: Label
var detail: Label

func _initialize() -> void: call_deferred("_run")

func project_input(world: Vector2) -> Vector2:
	return Vector2(world.x-world.y,(world.x+world.y)*0.5).normalized()*world.length()

func mapped_input(direction: Vector2, brake: bool = false) -> void:
	var magnitude: float = clampf(direction.length(),0.0,1.0)
	var raw: Vector2 = direction.normalized()*(0.22+0.78*magnitude) if magnitude > 0.0 else Vector2.ZERO
	for axis: int in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
		var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
		event.device = 29; event.axis = axis; event.axis_value = raw.x if axis == JOY_AXIS_LEFT_X else raw.y
		Input.parse_input_event(event); mapped_events += 1
	for value: Array in [[JOY_BUTTON_A,false],[JOY_BUTTON_LEFT_SHOULDER,brake]]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 29; event.button_index = int(value[0]); event.pressed = bool(value[1])
		Input.parse_input_event(event); mapped_events += 1
	Input.flush_buffered_events()

func player_reading() -> Dictionary:
	var b: Node2D = game.battle; var p: Dictionary = b.player_entity()
	return {"time":b.elapsed,"rpm":p.rpm,"rpm_loss_scale":b.powers.incoming_rpm_scale(p),"stress":p.anchor_stress,"charge":p.anchor_charge,"strength":p.anchor_strength,"maturity":p.anchor_maturity,"overloaded":p.get("anchor_overloaded",false),"recovery_progress":p.get("anchor_recovery_progress",0.0),"quota":p.anchor_recovery_remaining,"rearm_progress":p.anchor_rearm_progress,"venting":p.anchor_venting,"position":[p.pos.x,p.pos.y],"radius":Vector2(p.pos).length(),"speed":Vector2(p.vel).length(),"mass":1.0/b.powers.inverse_mass(p),"losses":b.continuous.economy.losses.duplicate(),"gains":b.continuous.economy.gains.duplicate(),"mode":active_case.get("mode","opening")}

func choose_earned() -> void:
	if game.screen == "level_up": game._process(0.2)
	while game.screen == "reward":
		var choice: String = str(game.run_context.pending_offer[0])
		for preferred: String in ["dead_centre","crash_guard","gyro_lock","impact_sink","anchor_exchange","clutch","momentum_bank"]:
			if preferred in game.run_context.pending_offer: choice = preferred; break
		var claim: String = game.run_context.pending_draft_id
		game._action("choose_power",{"encounter_id":claim,"power_id":choice,"run_seed":game.run_context.run_seed})
		if game.screen == "mutation": game._action("choose_mutation",{"encounter_id":claim,"branch_id":game.run_context.pending_mutation_offer[0],"run_seed":game.run_context.run_seed})
		game._process(1.1)

func controls() -> Dictionary:
	var b: Node2D = game.battle; var p: Dictionary = b.player_entity()
	var pos: Vector2 = p.pos; var vel: Vector2 = p.vel; var radius: float = pos.length()
	if b.battle_status != "battle": return {"direction":Vector2.ZERO,"brake":false}
	if b.elapsed < float(active_case.get("next_sample",-INF)): return active_case.input
	active_case.next_sample = b.elapsed+0.10
	var phase: String = str(active_case.get("phase","hold"))
	if phase == "hold" and (float(p.anchor_stress) >= float(active_case.configuration.get("release_at",0.80)) or (bool(p.get("anchor_overloaded",false)) and not bool(active_case.configuration.get("wait_full",false)))):
		phase = "release"
		active_case.release_start = player_reading()
		active_case.release_start.overload_time = float(active_case.get("latest_overload",{}).get("time",b.elapsed))
		active_case.heading = pos.normalized() if radius > 12.0 else Vector2.ONE.normalized()
	var quota_ready: bool = not bool(active_case.configuration.get("wait_quota",false)) or float(p.anchor_recovery_remaining) >= 0.19
	if phase in ["release","orbit"] and not bool(p.get("anchor_overloaded",false)) and float(p.anchor_stress) <= Runtime.ANCHOR_STRESS_REENGAGE and quota_ready:
		phase = "return"
		active_case.safe_start = player_reading()
	if phase == "return" and float(p.anchor_charge) >= 0.99 and float(p.anchor_strength) >= 0.99 and radius <= 58.0:
		active_case.replants.append({"release":active_case.release_start,"safe":active_case.safe_start,"replant":player_reading(),"release_to_safe_seconds":float(active_case.safe_start.time)-float(active_case.release_start.time),"release_to_full_replant_seconds":b.elapsed-float(active_case.release_start.time),"overload_to_safe_seconds":float(active_case.safe_start.time)-float(active_case.release_start.overload_time),"overload_to_full_replant_seconds":b.elapsed-float(active_case.release_start.overload_time)})
		phase = "hold"
	var direction: Vector2 = Vector2.ZERO
	var brake: bool = false
	var mode: String = "planted_under_real_pressure"
	var target_radius: float = float(active_case.configuration.get("vent_radius",100.0))
	if phase == "release":
		direction = Vector2(active_case.heading)*0.55
		if radius >= target_radius-8.0: phase = "orbit"
		mode = "release_and_reposition"
	elif phase == "orbit":
		var radial: Vector2 = pos.normalized()
		var target: Vector2 = radial.orthogonal()*95.0-radial*(radius-target_radius)*2.4
		direction = (target-vel).normalized()*0.55
		mode = "moving_recovery_window"
	elif phase == "return":
		direction = (-pos*1.5-vel*0.35).normalized()*(0.85 if radius > 45.0 else 0.24)
		if radius < 8.0 and vel.length() < 8.0: direction = Vector2.ZERO
		brake = radius < 45.0 and vel.length() > 45.0
		mode = "reclaiming_centre"
	else:
		direction = (-pos*1.2-vel*0.5).normalized()*0.24 if radius > 7.0 or vel.length() > 8.0 else Vector2.ZERO
		brake = radius < 80.0 and vel.length() > 48.0
		if bool(active_case.configuration.get("paid_sink",false)) and float(p.get("sink_charge",0.0)) >= 15.0 and float(p.anchor_stress) > 0.40 and b.elapsed >= float(active_case.get("sink_ready",0.0)):
			brake = true; active_case.sink_ready = b.elapsed+6.0
			mode = "paid_stored_force_brace"
	if radius >= 145.0:
		direction = (-pos*1.5-vel*0.65).normalized()*0.55
		brake = vel.dot(pos.normalized()) > 40.0 or vel.length() > 125.0
		mode = "ordinary_boundary_correction"
	if phase in ["release","orbit"] and bool(active_case.configuration.get("paid_after_overload",false)) and not bool(active_case.get("paid_release_used",false)) and float(p.get("sink_charge",0.0)) >= 15.0:
		brake = true; active_case.paid_release_used = true; mode = "paid_stored_force_release"
	active_case.phase = phase; active_case.mode = mode
	active_case.input = {"direction":project_input(direction),"brake":brake}
	return active_case.input

func one_tick() -> void:
	var b: Node2D = game.battle
	var input: Dictionary = controls()
	var was_overloaded: bool = bool(b.player_entity().get("anchor_overloaded",false))
	mapped_input(input.direction,input.brake)
	game._process(Battle.FIXED_DT)
	b._physics_process(Battle.FIXED_DT)
	choose_earned()
	var is_overloaded: bool = bool(b.player_entity().get("anchor_overloaded",false))
	if is_overloaded and not was_overloaded:
		active_case.latest_overload = player_reading()
		active_case.overloads.append(active_case.latest_overload.duplicate(true))
	if was_overloaded and not is_overloaded: active_case.safe_latch_events.append(player_reading())
	active_case.tick = int(active_case.tick)+1
	if b.elapsed >= float(active_case.get("next_trace",0.0)):
		active_case.trace.append(player_reading()); active_case.next_trace = b.elapsed+0.25
	b.queue_redraw()

func make_case(configuration: Dictionary) -> void:
	game = QuietMain.new(); game.smoke_mode = true
	game.collection_path = profiles_path.path_join(str(configuration.id)+".json")
	assert(not FileAccess.file_exists(game.collection_path),"Each normal Main uses a fresh isolated save")
	root.add_child(game); game.set_process(false)
	var ranks: Dictionary = Opening.STAGES[str(configuration.stage)].ranks.duplicate(true)
	var mutations: Dictionary = Opening.STAGES[str(configuration.stage)].mutations.duplicate(true)
	game.run_context.start(Starters.build_for("bastion"),int(configuration.seed),"bastion")
	game.run_context._owned_power_ids.assign(ranks.keys())
	game.run_context._power_ranks = ranks
	game.run_context._power_mutations = mutations
	game.run_context._draft_queue.clear(); game.run_context._pending_offer.clear()
	var investments: int = 0
	for value: int in ranks.values(): investments += value
	game.run_context._progression.level = investments
	game.mode = "run"; game._launch_run_encounter()
	game.battle.set_physics_process(false)
	game.battle.continuous.progression_level = investments
	active_case = {"configuration":configuration,"tick":0,"trace":[],"impacts":[],"replants":[],"opening_ranks":ranks.duplicate(true),"opening_mutations":mutations.duplicate(true),"opening_investments":investments,"mode":"opening","phase":"hold","overloads":[],"safe_latch_events":[],"shown":false}
	game.battle.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		if int(event.first_entity_id) != 1 and int(event.second_entity_id) != 1: return
		var row: Dictionary = event.duplicate(true); row.player = player_reading(); row.movie_frame = frame_count
		active_case.impacts.append(row))
	game.music.configure_playback(false)

func close_case() -> void:
	active_case.final = player_reading()
	active_case.result = game.battle.last_result.duplicate(true)
	active_case.economy = game.battle.continuous.economy.snapshot()
	active_case.power_diagnostics = game.battle.powers.diagnostics(game.battle.player_entity())
	cases.append(active_case.duplicate(true))
	mapped_input(Vector2.ZERO,false)
	game.free()

func label(at: Vector2) -> Label:
	var node: Label = Label.new(); node.position = at; node.size = Vector2(624,18)
	node.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt")); node.add_theme_font_size_override("font_size",10)
	node.add_theme_color_override("font_color",Color("e4ebd6")); caption_layer.add_child(node)
	return node

func frame(section: Dictionary) -> void:
	var b: Node2D = game.battle; var p: Dictionary = b.player_entity()
	# Review captions are encoded in a separate strip below the full gameplay
	# image. They must never cover the real Run power deck or XP footer.
	heading.visible = false; detail.visible = false
	# Keep the actual mouse over an empty HUD slot, never Inspector cards.
	var motion: InputEventMouseMotion = InputEventMouseMotion.new(); motion.position = Vector2(320,62); motion.global_position = motion.position
	Input.parse_input_event(motion); Input.flush_buffered_events()
	b._emit_hud()
	game.music.configure_playback(true); game.music.set_context("run"); game.music.set_paused(false)
	game.music.observe_run(b.continuous.snapshot(),p)
	if frame_count % 5 == 0:
		var reading: Dictionary = player_reading(); reading.movie_frame = frame_count; reading.section = section.id
		movie_rows.append(reading)
	await process_frame
	if not frames_path.is_empty() and frame_count % 180 == 0:
		await RenderingServer.frame_post_draw
		var path: String = frames_path.path_join(str(section.id)+"_%06d.png" % frame_count)
		root.get_texture().get_image().save_png(path); native_frames.append(path)
	frame_count += 1

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg.begins_with("--profiles="): profiles_path = arg.trim_prefix("--profiles=")
		if arg.begins_with("--plan="): plan_path = arg.trim_prefix("--plan=")
		if arg.begins_with("--frames="): frames_path = arg.trim_prefix("--frames=")
		if arg == "--film": diagnostic = false
	if not report_path.is_absolute_path() or FileAccess.file_exists(report_path) or not profiles_path.is_absolute_path() or DirAccess.dir_exists_absolute(profiles_path) or not plan_path.is_absolute_path():
		push_error("Fresh explicit external report/profiles and external plan required before Main boot"); quit(2); return
	DirAccess.make_dir_recursive_absolute(profiles_path)
	if not frames_path.is_empty(): DirAccess.make_dir_recursive_absolute(frames_path)
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	root.size = Vector2i(640,360); root.content_scale_size = Vector2i(640,360); root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	caption_layer = CanvasLayer.new(); caption_layer.layer = 30; root.add_child(caption_layer)
	heading = label(Vector2(8,340)); detail = label(Vector2(8,322))
	for configuration: Dictionary in plan.cases:
		make_case(configuration)
		game.battle.event_sfx.connect(func(kind: String) -> void:
			if not diagnostic and bool(active_case.shown): game.sounds.play_sound(kind))
		if diagnostic:
			while game.battle.battle_status != "finished" and game.battle.elapsed < float(configuration.get("horizon",600.0)) and int(active_case.tick) < 100000:
				one_tick()
		else:
			for section: Dictionary in plan.sections:
				if section.case_id != configuration.id: continue
				while game.battle.battle_status != "finished" and game.battle.elapsed < float(section.from): one_tick()
				var first_frame: int = frame_count; var start: Dictionary = player_reading()
				active_case.shown = true
				while game.battle.battle_status != "finished" and game.battle.elapsed < float(section.to):
					one_tick(); await frame(section)
				active_case.shown = false; game.music.configure_playback(false)
				movie_sections.append({"configuration":section,"first_frame":first_frame,"last_frame":frame_count,"start":start,"end":player_reading()})
		close_case()
	var result: Dictionary = {"schema":"003a1-anchor-rearm-physical-main-v1","scope":"Normal Main and actual mapped control dispatch. Legal invested power/level opening is a labelled fixture; all subsequent positions, RPM, collision forces, stress, vent and outcomes arise from the production solver and ordinary AI. No mature clock, live reset, forced contact or reserve edit. Earned drafts use ordinary Main claims. This is deterministic QA, not human acceptance.","main_created":true,"real_player_profile_accessed":false,"native_view":[640,360],"fixed_dt":Battle.FIXED_DT,"mapped_events":mapped_events,"movie_frames":frame_count,"movie_seconds":float(frame_count)/60.0,"movie_rows":movie_rows,"movie_sections":movie_sections,"native_frames":native_frames,"cases":cases,"tuning":{"overload_threshold":Runtime.ANCHOR_STRESS_OVERLOAD,"safe_threshold":Runtime.ANCHOR_STRESS_REENGAGE,"vent_rate":Runtime.ANCHOR_STRESS_VENT_RATE,"outside_vent_rate":Runtime.ANCHOR_STRESS_OUTSIDE_VENT_RATE,"minimum_meaningful_recovery_seconds":Runtime.ANCHOR_OVERLOAD_RECOVERY_SECONDS,"quota_rearm_seconds":Runtime.ANCHOR_REARM_SECONDS}}
	var file: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	if file == null: push_error("Cannot preserve timing evidence"); quit(2); return
	file.store_string(JSON.stringify(result,"\t")); file.close(); caption_layer.free()
	print("ANCHOR_REARM_MAIN_PASS cases=%d movie_frames=%d" % [cases.size(),frame_count])
	quit(0)
