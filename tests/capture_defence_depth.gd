extends SceneTree
## Explicit legal opening rank/pose fixtures, followed by mapped controller
## events only. Every charge, hit, vent and reserve change uses ordinary Battle.
const Battle = preload("res://tests/measured_presentation_battle.gd")
const Physics = preload("res://scripts/battle.gd")
const Catalog = preload("res://scripts/run_powers.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Sound = preload("res://scripts/sound.gd")
const CASES: Array[Dictionary] = [
	{"family":"gyro_lock","rank":2,"branch":"","label":"GYRO LOCK II / SMOOTH STEERING EARNS MOVING DEFENCE"},
	{"family":"gyro_lock","rank":3,"branch":"keel","label":"KEEL / SLOW CONTROL TRADES SPEED FOR HEAVIER FOOTING"},
	{"family":"gyro_lock","rank":3,"branch":"flywheel","label":"FLYWHEEL / CARRY A LOCK THROUGH CONTROLLED CURVES"},
	{"family":"impact_sink","rank":2,"branch":"","label":"IMPACT SINK II / CATCH RECOIL - FRESH BRAKE TO RECOVER"},
	{"family":"impact_sink","rank":3,"branch":"shock_bleed","label":"SHOCK BLEED / ACCEPTED FORCE PAYS FOR A SPIN CATCH"},
	{"family":"impact_sink","rank":3,"branch":"return_spring","label":"RETURN SPRING / BRAKE SPENDS SHOCK ON A COUNTER PULSE"},
	{"family":"anchor_exchange","rank":2,"branch":"","label":"ANCHOR EXCHANGE II / HOLD BRAKE - PAY SPIN FOR FOOTING"},
	{"family":"anchor_exchange","rank":3,"branch":"deep_footing","label":"DEEP FOOTING / ALMOST STOP - HOLD AN EXTREME BRACE"},
	{"family":"anchor_exchange","rank":3,"branch":"slip_anchor","label":"SLIP ANCHOR / RELEASE BRAKE - CARRY A BRIEF PAID BRACE"}]
var diagnostic: bool = false
var output: String = ""
var frames: String = ""
var duration: float = 12.0
var event_count: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x, value.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = portable(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(portable(item))
		return result
	return value

func mapped_input(direction: Vector2, brake: bool) -> void:
	var magnitude: float = clampf(direction.length(), 0.0, 1.0)
	var raw: Vector2 = direction.normalized() * (0.22 + 0.78 * magnitude) if magnitude > 0.0 else Vector2.ZERO
	for axis: int in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
		event.device = 19; event.axis = axis; event.axis_value = raw.x if axis == JOY_AXIS_LEFT_X else raw.y
		Input.parse_input_event(event); event_count += 1
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = 19; event.button_index = JOY_BUTTON_LEFT_SHOULDER; event.pressed = brake
	Input.parse_input_event(event); event_count += 1
	Input.flush_buffered_events()

static func screen(world: Vector2) -> Vector2:
	return Vector2(world.x - world.y, (world.x + world.y) * 0.5).normalized() * minf(1.0, world.length())

func controls(b: Node2D, c: Dictionary, tick: int) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var position: Vector2 = p.pos
	var velocity: Vector2 = p.vel
	var direction: Vector2 = Vector2.ZERO
	var brake: bool = false
	if c.family == "gyro_lock":
		var radial: Vector2 = position.normalized() if position.length() > 1.0 else Vector2.RIGHT
		var tangent: Vector2 = Vector2(-radial.y, radial.x)
		var pace: float = 63.0 if c.branch == "keel" else (95.0 if c.branch == "flywheel" else 78.0)
		var radius: float = 69.0
		var desired: Vector2 = tangent * pace + radial * (radius - position.length()) * 2.0
		var thrust: Vector2 = (desired - velocity) * 3.0 + desired * 0.7 - radial * pace * pace / radius
		var available: float = (123.0 + float(p.stats.grip) * 17.0) * float(p.handling.get("acceleration", 1.0))
		direction = thrust.limit_length(available) / available
		# End with a deliberate reversal. The live runtime must actually clear
		# its lock; this is not a preselected visual pose or forced power proc.
		if float(tick) / 60.0 >= duration - 1.5: direction = -velocity.normalized() * 0.7
	elif c.family == "impact_sink":
		direction = (-position - velocity * 0.25).limit_length(130.0) / 200.0
		brake = float(p.get("sink_charge", 0.0)) >= 20.0 and tick % 45 < 16
	else:
		direction = (-position - velocity * 0.45).limit_length(90.0) / 160.0
		brake = tick % 330 < 235
		if not brake: direction = (Vector2(48, 0) - position - velocity * 0.25).limit_length(100.0) / 160.0
	return {"direction":screen(direction),"brake":brake}

func sample(b: Node2D) -> Dictionary:
	var p: Dictionary = b.player_entity()
	return {"seconds":b.elapsed,"rpm":p.rpm,"position":p.pos,"velocity":p.vel,"wobble":p.wobble,
		"gyro_charge":p.get("gyro_charge",0.0),"sink_charge":p.get("sink_charge",0.0),
		"exchange_charge":p.get("exchange_charge",0.0),"exchange_carry":p.get("exchange_carry",0.0),
		"defence":b.powers.defence.diagnostics(p),"fx":b._power_fx.size(),"live_enemies":b.continuous.census()}

func caption(text: String, at: Vector2) -> Label:
	var label: Label = Label.new()
	label.text = text; label.position = at
	label.add_theme_font_override("font", load("res://assets/ui/foundry_small.fnt"))
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("e7e5ca"))
	root.add_child(label)
	return label

static func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var ordered: Array[float] = values.duplicate(); ordered.sort()
	return {"samples":ordered.size(),"median":ordered[ordered.size()/2],"p95":ordered[mini(ordered.size()-1,int(ordered.size()*0.95))],"max":ordered.back()}

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): output = arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frames = arg.trim_prefix("--frames=")
		if arg.begins_with("--duration="): duration = float(arg.trim_prefix("--duration="))
		if arg == "--diagnostic": diagnostic = true
	if output.is_empty(): push_error("External --manifest required"); quit(2); return
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames.is_empty(): DirAccess.make_dir_recursive_absolute(frames)
	var sound: Node = Sound.new(); root.add_child(sound)
	var reports: Array[Dictionary] = []
	for c: Dictionary in CASES:
		var b: Node2D = Battle.new(); root.add_child(b); b.set_physics_process(false)
		var d: Dictionary = Encounters.for_run_event(1, 421)
		d.starter_id = "bastion"; d.player_power_ids = [c.family]
		d.player_power_ranks = {c.family:c.rank}; d.player_power_mutations = {c.family:c.branch} if not str(c.branch).is_empty() else {}
		b.begin_run(Starters.build_for("bastion"), d, 421)
		# Deliberate opening pose is explicit fixture data. No fighter is
		# repositioned, granted reserve or assigned power state after this point.
		b.player_entity().pos = Vector2(69, 0) if c.family == "gyro_lock" else Vector2.ZERO
		mapped_input(Vector2.ZERO, false)
		while b.battle_status != "battle": b._physics_process(Physics.FIXED_DT)
		b.event_sfx.connect(sound.play_sound)
		var labels: Array[Label] = [caption(str(c.label), Vector2(8, 8)),caption("LEGAL OPENING BUILD / MAPPED PAD EVENTS / REAL DIRECTOR + PHYSICS", Vector2(8, 25)),caption("",Vector2(8, 326))]
		var rows: Array[Dictionary] = []
		var costs: Array[float] = []
		var maximum: Dictionary = {"gyro":0.0,"sink":0.0,"brace":0.0,"carry":0.0,"fx":0}
		for tick: int in range(int(duration * 60.0)):
			var input: Dictionary = controls(b, c, tick)
			mapped_input(input.direction, input.brake)
			var began: int = Time.get_ticks_usec()
			b._physics_process(Physics.FIXED_DT)
			costs.append(float(Time.get_ticks_usec() - began) / 1000.0)
			var p: Dictionary = b.player_entity()
			maximum.gyro = maxf(float(maximum.gyro),float(p.get("gyro_charge",0.0)))
			maximum.sink = maxf(float(maximum.sink),float(p.get("sink_charge",0.0)))
			maximum.brace = maxf(float(maximum.brace),float(p.get("exchange_charge",0.0)))
			maximum.carry = maxf(float(maximum.carry),float(p.get("exchange_carry",0.0)))
			maximum.fx = maxi(int(maximum.fx),b._power_fx.size())
			labels[2].text = "RPM %d%%  GYRO %d%%  STORED SHOCK %d  BRACE %d%%  BRAKE %s" % [roundi(float(p.rpm)*100),roundi(float(p.get("gyro_charge",0.0))*100),roundi(float(p.get("sink_charge",0.0))),roundi(float(p.get("exchange_charge",0.0))*100),"HELD" if input.brake else "RELEASED"]
			if tick % 15 == 0:
				var row: Dictionary = sample(b); row["intent"] = input; rows.append(row)
			if not diagnostic:
				b.queue_redraw(); await process_frame
				if not frames.is_empty() and tick in [150,300,450,600]:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(frames.path_join("%s_%s_%04d.png" % [c.family, c.branch if not str(c.branch).is_empty() else "ii",tick]))
			if b.battle_status == "finished": break
		var tool_state: Dictionary = b.powers.defence.diagnostics(b.player_entity())
		if c.family == "gyro_lock" and float(maximum.gyro) < 0.65: failures.append(str(c.label) + ": moving lock did not actually develop")
		if c.family == "impact_sink" and (float(maximum.sink) < 15.0 or int(tool_state.get("vents",0)) == 0): failures.append(str(c.label) + ": accepted shock plus deliberate vent not actually demonstrated")
		if c.family == "anchor_exchange" and float(maximum.brace) < 0.95: failures.append(str(c.label) + ": paid brace not actually developed")
		if c.branch == "slip_anchor" and float(maximum.carry) < 0.20: failures.append("Slip Anchor did not show an actual released carry")
		reports.append({"case":c,"rows":rows,"maxima":maximum,"procs":b.powers.defence.counters.duplicate(),"tool_state":tool_state,"ledger":b.continuous.economy.snapshot(),"result":b.last_result,"seconds":b.elapsed,"simulation_ms":stats(costs),"draw_submission_ms":stats(b.draw_samples)})
		for label: Label in labels: label.free()
		b.free()
	mapped_input(Vector2.ZERO, false)
	var report: Dictionary = {"scope":"Legal opening rank/pose fixtures followed only by mapped controller input; actual Director, collisions, bounded power state and spin ledger; no save/profile writes","controller_events":event_count,"cases":reports,"failures":failures,"passed":failures.is_empty(),"native_size":[640,360],"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(portable(report)))
	print("DEFENCE_SHOWCASE_%s events=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",event_count,JSON.stringify(failures)])
	sound.free()
	quit(0 if failures.is_empty() else 1)
