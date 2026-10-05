extends SceneTree
## Actual deterministic combat after a labelled, single-family opening build.
## No position, velocity, RPM, rival, cooldown or proc state is injected.
## Fast-forward executes the identical controls and every combat/director tick.
const B = preload("res://tests/measured_presentation_battle.gd")
const Physics = preload("res://scripts/battle.gd")
const E = preload("res://scripts/encounters.gd")
const S = preload("res://scripts/starters.gd")
const C = preload("res://scripts/run_powers.gd")
const Audio = preload("res://scripts/sound.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const BRANCH_FAMILIES: Dictionary = {"runaway":"redline","breakneck":"redline",
	"bulwark":"dead_centre","counterweight":"dead_centre",
	"ghost_circuit":"afterimage","slipstream":"afterimage",
	"terminal_velocity":"high_gear","flow_state":"high_gear"}
var selections: Array = ["impact_wake"]
var requested_starter: String = ""
var requested_branch: String = ""
var requested_policy: String = ""
var rank_value: int = 2
var seed_value: int = 421
var explicit_seed: bool = false
var start_time: float = 0.0
var clip_seconds: float = 8.0
var output: String = ""
var frame_dir: String = ""
var diagnostic: bool = false
var blind: bool = false
var tick: int = 0
var sampled: Dictionary = {}
var progress: Dictionary = {}
var events: Array[Dictionary] = []
var state_changes: Array[Dictionary] = []
var old_counts: Dictionary = {}
var old_active: Dictionary = {}
var peak: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func screen(world: Vector2) -> Vector2:
	if world.length_squared() < 0.000001: return Vector2.ZERO
	return Vector2(world.x-world.y,(world.x+world.y)*0.5).normalized()*minf(1.0,world.length())

func preset(selection: String) -> Dictionary:
	var family: String = str(BRANCH_FAMILIES.get(selection,selection))
	var branch: String = selection if BRANCH_FAMILIES.has(selection) else requested_branch
	assert(family in C.ACTIVE_IDS,"Unknown family: "+family)
	assert(branch.is_empty() or branch in C.MUTATION_BRANCHES.get(family,[]),"Unknown mutation: "+branch)
	var starter: String = "bastion" if family in ["redline","iron_comet","dead_centre","clutch","crash_guard"] else "breaker" if family in ["impact_wake","chain_impact","predator_line"] else "vane"
	var policy: String = "pursuit"
	match family:
		"iron_comet": policy = "wall"
		"dead_centre": policy = "anchor"
		"afterimage": policy = "route"
		"clutch": policy = "comeback"
		"high_gear": policy = "speed"
		"orbit_drive": policy = "drift"
		"momentum_bank": policy = "bank"
		"crosscut": policy = "shear"
	if branch == "slipstream": policy = "crossing"
	if not requested_starter.is_empty(): starter = requested_starter
	if not requested_policy.is_empty(): policy = requested_policy
	return {"selection":selection,"family":family,"starter":starter,"rank":3 if not branch.is_empty() else rank_value,
		"branch":branch,"policy":policy,"seed":7341 if family == "clutch" and not explicit_seed else seed_value,
		"label":selection.to_upper().replace("_"," ")+(" III" if not branch.is_empty() else " II" if rank_value == 2 else " I")}

func curve(b: Node2D, pace: float, radius: float) -> Vector2:
	var p: Dictionary = b.player_entity()
	var pos: Vector2 = p.pos
	var radial: Vector2 = pos.normalized() if pos.length() > 1.0 else Vector2.RIGHT
	var tangent: Vector2 = Vector2(-radial.y,radial.x)
	var route: Vector2 = tangent*pace+radial*(radius-pos.length())*2.0
	var force: Vector2 = (route-Vector2(p.vel))*4.0+route*0.75-radial*(pace*pace/radius)
	var available: float = (123.0+float(p.stats.grip)*17.0)*float(p.handling.get("acceleration",1.0))
	if float(p.burst_time) > 0.0: available *= 1.65
	return force.limit_length(available)/available

func controls(b: Node2D, sc: Dictionary) -> Dictionary:
	# The comeback policy exactly preserves the proven six-tick controller.
	if tick%6 != 0:
		sampled.burst = false
		return sampled
	var p: Dictionary = b.player_entity()
	var pos: Vector2 = p.pos
	var vel: Vector2 = p.vel
	var target: Dictionary = b._target_for(p)
	var distance: float = pos.distance_to(Vector2(target.pos)) if not target.is_empty() else INF
	var c: Dictionary = Bot.input(b,"aggressive",tick)
	match str(sc.policy):
		"comeback":
			if float(p.rpm) <= 0.28 and float(progress.danger_at) < 0.0: progress.danger_at = b.elapsed
			if float(progress.danger_at) < 0.0:
				c.direction = screen((-pos-vel*0.4).normalized()*0.06); c.brake = true; c.burst = false
			else: progress.recovery_peak = maxf(float(progress.recovery_peak),float(p.rpm))
			if pos.length() > 145.0: c.direction = screen(-pos.normalized()*0.8); c.brake = true
		"wall":
			if float(p.iron_comet_time) <= 0.0 and fmod(b.elapsed,9.0) < 3.0:
				c.direction = screen((Vector2(-182,-60)-pos).normalized()*0.95)
				c.brake = false; c.burst = float(p.cooldown) <= 0.0
		"anchor":
			c = Bot.input(b,"defensive",tick)
			c.direction = Vector2(c.direction).normalized()*0.23
			c.brake = vel.length() > 58.0
			c.burst = str(sc.branch) == "counterweight" and float(p.get("stored_force",0.0)) >= 35.0 and distance < 95.0 and float(p.cooldown) <= 0.0
		"route":
			c.direction = screen(curve(b,155.0,98.0)); c.burst = false; c.brake = false
		"crossing":
			# Retrace a genuinely paid diagonal route. The controller changes
			# its destination only; force, slowdown and crossing stay physical.
			var sign_lane: float = float(progress.get("lane_sign",1.0))
			if sign_lane > 0.0 and pos.x > 62.0: sign_lane = -1.0
			elif sign_lane < 0.0 and pos.x < -62.0: sign_lane = 1.0
			progress.lane_sign = sign_lane
			var goal: Vector2 = Vector2(85.0,32.0)*sign_lane
			var desired: Vector2 = ((goal-pos)*4.5-vel*0.55).normalized()*0.94
			c.direction = screen(desired); c.burst = false; c.brake = false
		"speed", "drift":
			c.direction = screen(curve(b,190.0 if sc.policy == "speed" else 150.0,110.0))
			c.burst = float(p.cooldown) <= 0.0 and pos.length() < 140.0
			c.brake = sc.policy == "drift" and fmod(b.elapsed,3.0) > 1.65 and fmod(b.elapsed,3.0) < 2.50
		"long_drift":
			# Labelled capture-only driver: build real speed, then hold brake
			# with lateral steering. Every slide/contact is ordinary physics.
			# No actor, position, velocity, reserve, cooldown or proc writes.
			var phase: float = fmod(b.elapsed,10.0)
			if phase < 2.0:
				c.direction = screen(curve(b,175.0,80.0)); c.brake = false
				c.burst = float(p.cooldown) <= 0.0 and pos.length() < 145.0
			elif phase < 6.5:
				c.direction = screen(vel.normalized().rotated(0.45)); c.brake = true
				c.burst = float(p.cooldown) <= 0.0 and vel.length() < 130.0
			else:
				c.direction = screen(curve(b,175.0,80.0)); c.brake = false; c.burst = false
		"bank":
			var phase: float = fmod(b.elapsed,5.0)
			if phase < 1.7:
				c.direction = screen(curve(b,180.0,90.0)); c.brake = false; c.burst = false
			elif phase < 2.6:
				c.direction = screen(vel.normalized()*0.32); c.brake = true; c.burst = false
			else:
				c.brake = false
				c.burst = float(p.cooldown) <= 0.0 and float(p.get("momentum_charge",0.0)) >= 15.0
		"shear":
			if not target.is_empty():
				var offset: Vector2 = Vector2(target.pos)-pos
				var side: float = 1.0 if fmod(b.elapsed,10.0) < 5.0 else -1.0
				c.direction = screen(offset.normalized().rotated(0.48*side)*0.92)
				c.burst = float(p.cooldown) <= 0.0 and distance < 100.0
				c.brake = false
	if str(sc.policy) not in ["wall","comeback"] and pos.length() > 150.0:
		c.direction = screen(-pos.normalized()*0.85); c.brake = pos.length() > 170.0
	sampled = c
	return c

func counters(b: Node2D) -> Dictionary:
	var result: Dictionary = b.powers.counters.duplicate()
	for kind: String in b.roster.counters: result[kind] = int(result.get(kind,0))+int(b.roster.counters[kind])
	return result

func active(p: Dictionary) -> Dictionary:
	return {"redline":float(p.get("redline_time",0.0)) > 0.0,"overcap":float(p.rpm) > 1.0,
		"heat":float(p.get("redline_heat",0.0)) >= 0.55,"comet":float(p.get("iron_comet_time",0.0)) > 0.0,
		"anchor":float(p.get("anchor_charge",0.0)) >= 0.70,"drift":bool(p.get("drift_active",false)),
		"bank":float(p.get("momentum_charge",0.0)) >= 15.0,"hunt":int(p.get("hunt_stacks",0)) > 0,
		"guard":float(p.get("guard_time",0.0)) > 0.0,"danger":bool(p.get("clutch_active",false)),
		"catch":float(p.get("clutch_recovery_time",0.0)) > 0.0,"preview":not Dictionary(p.get("ghost_preview",{})).is_empty()}

func record_tick(b: Node2D) -> void:
	var p: Dictionary = b.player_entity()
	var now: Dictionary = counters(b)
	var keys: Array = now.keys(); keys.sort()
	for kind: String in keys:
		if int(now[kind]) > int(old_counts.get(kind,0)) and events.size() < 768:
			events.append({"time":b.elapsed,"kind":kind,"count":now[kind],"rpm":p.rpm,"speed":Vector2(p.vel).length(),"position":[p.pos.x,p.pos.y],"live_entities":b.fighters.size()})
	old_counts = now
	var states: Dictionary = active(p)
	for key: String in states:
		if states[key] != old_active.get(key,false) and state_changes.size() < 768:
			state_changes.append({"time":b.elapsed,"state":key,"active":states[key],"rpm":p.rpm,"speed":Vector2(p.vel).length()})
	old_active = states
	for field: String in ["speed","rpm","heat","bank","orbit","hunt"]:
		var value: float = Vector2(p.vel).length() if field == "speed" else float(p.rpm) if field == "rpm" else float(p.get("redline_heat",0.0)) if field == "heat" else float(p.get("momentum_charge",0.0)) if field == "bank" else float(p.get("orbit_charge",0.0)) if field == "orbit" else float(p.get("hunt_stacks",0))
		peak[field] = maxf(float(peak.get(field,0.0)),value)

func step(b: Node2D, sc: Dictionary) -> void:
	var c: Dictionary = controls(b,sc)
	b.test_step(Physics.FIXED_DT,c.direction,c.burst,c.brake)
	tick += 1
	record_tick(b)

func sample(b: Node2D) -> Dictionary:
	var p: Dictionary = b.player_entity()
	return {"time":b.elapsed,"rpm":p.rpm,"speed":Vector2(p.vel).length(),"position":[p.pos.x,p.pos.y],
		"states":active(p),"counters":counters(b),"trace_count":b.powers.traces.size(),"fx":b._power_fx.size()}

func stop_audio(sound: Node) -> void:
	for channel: AudioStreamPlayer in sound.channels:
		channel.stop()
		channel.stream = null

func play(sc: Dictionary, sound: Node) -> Dictionary:
	var b = B.new(); root.add_child(b); b.set_physics_process(false)
	var d: Dictionary = E.for_run_event(1,int(sc.seed))
	d.starter_id = sc.starter; d.player_power_ids = [sc.family]; d.player_power_ranks = {sc.family:sc.rank}
	d.player_power_mutations = {sc.family:sc.branch} if not str(sc.branch).is_empty() else {}
	d.ability_rebalance = true
	b.begin_run(S.build_for(str(sc.starter)),d,int(sc.seed)); b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	assert(float(p.rpm) == 1.0,"Every scenario starts at full launch reserve")
	assert(p.powers == [sc.family],"Pure-family opening build")
	tick = 0; sampled = {"direction":Vector2.ZERO,"burst":false,"brake":false}
	progress = {"danger_at":-1.0,"recovery_peak":0.0}; events = []; state_changes = []; old_counts = {}; old_active = {}; peak = {}
	var rows: Array[Dictionary] = [sample(b)]
	var next_sample: float = 0.25
	while b.elapsed < start_time and b.battle_status != "finished":
		step(b,sc)
		if b.elapsed >= next_sample: rows.append(sample(b)); next_sample += 0.25
	var actual_start: float = b.elapsed
	var label: Label = null
	if not blind:
		label = Label.new(); label.position = Vector2(12,326); label.add_theme_font_size_override("font_size",9); root.add_child(label)
	if not diagnostic: b.event_sfx.connect(sound.play_sound)
	var start_events: Dictionary = counters(b)
	var captured: int = 0
	for frame: int in range(roundi(clip_seconds*60.0)):
		if b.battle_status == "finished": break
		step(b,sc); captured += 1
		assert(is_same(p,b.player_entity()),"Inputs cannot replace or relaunch the player")
		if label != null: label.text = "%s / CONTROLLED SINGLE-FAMILY OPENING BUILD\nFULL RESERVE AT LAUNCH / INPUTS ONLY / REAL DIRECTOR + CONTACTS / %.1fs"%[sc.label,b.elapsed]
		if b.elapsed >= next_sample: rows.append(sample(b)); next_sample += 0.25
		if not diagnostic:
			# Release mixer ownership during the existing last movie frame.
			# An extra cleanup await here would append unwanted capture frames.
			if frame + 1 == roundi(clip_seconds * 60.0) or b.battle_status == "finished": stop_audio(sound)
			b.queue_redraw(); await process_frame
			if not frame_dir.is_empty() and frame%30 == 0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(frame_dir.path_join(str(sc.selection)+"-%04d.png"%frame))
	var end_counts: Dictionary = counters(b)
	var window_counts: Dictionary = {}
	for kind: String in end_counts: window_counts[kind] = int(end_counts[kind])-int(start_events.get(kind,0))
	var result: Dictionary = {"preset":sc,"requested_start":start_time,"actual_start":actual_start,"capture_frames":captured,"capture_seconds":float(captured)/60.0,"elapsed":b.elapsed,
		"window_counters":window_counts,"total_counters":end_counts,"proc_moments":events.duplicate(true),"state_transitions":state_changes.duplicate(true),"peak":peak.duplicate(),
		"rows":rows,"progress":progress.duplicate(),"result":b.last_result.duplicate(true),"economy":b.continuous.economy.snapshot(),
		"power_diagnostics":b.powers.diagnostics(p),"roster_diagnostics":b.roster.diagnostics(p),"final_rpm":p.rpm}
	if label != null: label.free()
	b.free()
	return result

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--family="): selections = [arg.trim_prefix("--family=")]
		if arg.begins_with("--families="): selections = Array(arg.trim_prefix("--families=").split(","))
		if arg.begins_with("--mutation="): requested_branch = arg.trim_prefix("--mutation=")
		if arg.begins_with("--starter="): requested_starter = arg.trim_prefix("--starter=")
		if arg.begins_with("--policy="): requested_policy = arg.trim_prefix("--policy=")
		if arg.begins_with("--rank="): rank_value = clampi(int(arg.trim_prefix("--rank=")),1,2)
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed=")); explicit_seed = true
		if arg.begins_with("--start="): start_time = float(arg.trim_prefix("--start="))
		if arg.begins_with("--length="): clip_seconds = float(arg.trim_prefix("--length="))
		if arg.begins_with("--manifest="): output = arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frame_dir = arg.trim_prefix("--frames=")
		if arg == "--diagnostic": diagnostic = true
		if arg == "--blind": blind = true
	if selections == ["all"]: selections = Array(C.ACTIVE_IDS)
	if selections == ["mutations"]: selections = BRANCH_FAMILIES.keys()
	root.size = Vector2i(1280,720); root.content_scale_size = Vector2i(640,360); root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty(): DirAccess.make_dir_recursive_absolute(frame_dir)
	var sound = Audio.new(); root.add_child(sound); sound.apply_settings({"volume":0.65,"muted":diagnostic})
	var runs: Array[Dictionary] = []
	for selection: String in selections:
		var sc: Dictionary = preset(selection)
		var row: Dictionary = await play(sc,sound); runs.append(row)
		print("IDENTITY_MOTION ",selection," elapsed=",row.elapsed," captured=",row.capture_seconds," procs=",row.window_counters," peaks=",row.peak)
		if not output.is_empty():
			var report: Dictionary = {"authenticity":"Explicit single-family opening build at full reserve. Only steering, Burst and brake afterwards; no position/velocity/RPM/rival/proc/cooldown edits. Real continuous director, AI, contacts and RPM accounting. Warm-up executes identical ticks. Controlled builds are not claimed to be earned drafts.","blind":blind,"diagnostic":diagnostic,"runs":runs}
			var file: FileAccess = FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("IDENTITY_MOTION_DONE runs=",runs.size())
	stop_audio(sound)
	sound.free()
	quit()
