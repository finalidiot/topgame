extends SceneTree
## Labelled opening builds/poses, followed exclusively by real controller inputs.
## Fast-forward still executes every real director/combat/RPM tick from launch.
const B=preload("res://tests/measured_presentation_battle.gd")
const Physics=preload("res://scripts/battle.gd")
const E=preload("res://scripts/encounters.gd")
const S=preload("res://scripts/starters.gd")
const Audio=preload("res://scripts/sound.gd")
const Bot=preload("res://tests/rpm_bot.gd")
var family: String="redline_overcap"
var output: String=""
var start: float=0.0
var length: float=18.0
var seed_id: int=421
var diagnostic: bool=false
var controller_tick: int=0
var out_dir: String=""
var requested_starter: String=""
var requested_mutation: String=""
var comeback_progress: Dictionary={"danger_at":-1.0,"recovery_peak":0.0}
var sampled_comeback: Dictionary={"direction":Vector2.ZERO,"burst":false,"brake":false}
func _initialize() -> void: call_deferred("run")
func screen(world: Vector2) -> Vector2:
	if world.length_squared()<.0001: return Vector2.ZERO
	return Vector2(world.x-world.y,(world.x+world.y)*.5).normalized()*minf(1.0,world.length())
func presets() -> Array[Dictionary]:
	match family:
		"redline_overcap": return [{"label":"REDLINE II / OVERCAP + HEAT","starter":"bastion","ranks":{"redline":2,"impact_wake":1,"predator_line":1},"mutations":{},"policy":"pursuit","seconds":length}]
		"redline_mutation": return [{"label":"BREAKNECK / SETUP -> COMMIT -> CONSEQUENCE","starter":"bastion","ranks":{"redline":3,"impact_wake":2},"mutations":{"redline":"breakneck"},"policy":"pursuit","seconds":length}]
		"speed_build": return [{"label":"BASELINE / SAME VANE + CONTROLLER","starter":"vane","ranks":{},"mutations":{},"policy":"orbit","seconds":8.0},{"label":"HIGH GEAR II + FLOW STATE / SAME CONTROLLER","starter":"vane","ranks":{"high_gear":3},"mutations":{"high_gear":"flow_state"},"policy":"orbit","seconds":10.0}]
		"ghost_circuit": return [{"label":"GHOST CIRCUIT / DRAW -> PREVIEW -> SNAP","starter":"vane","ranks":{"afterimage":3,"high_gear":1},"mutations":{"afterimage":"ghost_circuit"},"policy":"orbit","seconds":length}]
		"iron_comet": return [{"label":"IRON COMET II / BANK -> ROTOR CHARGE -> CONTACT","starter":"bastion","ranks":{"iron_comet":2,"high_gear":1,"impact_wake":1},"mutations":{},"policy":"wall","seconds":length}]
		"comeback": return [{"label":"CLUTCH II / REAL DANGER -> EARNED CATCH","starter":"bastion","ranks":{"clutch":2},"mutations":{},"policy":"exhaust_then_hunt","seconds":length}]
		"drift_carving": return [{"label":"FLOW STATE + ORBIT DRIVE / BRAKE -> CARVE -> RELEASE","starter":"vane","ranks":{"high_gear":3,"orbit_drive":2,"momentum_bank":2},"mutations":{"high_gear":"flow_state"},"policy":"orbit","seconds":length}]
		_: return [{"label":"COHERENT DEVELOPED BUILD / CARVE + ROUTE + FLOW","starter":"vane","ranks":{"high_gear":3,"orbit_drive":2,"afterimage":3,"clutch":2,"crash_guard":2},"mutations":{"high_gear":"flow_state","afterimage":"slipstream"},"policy":"orbit","seconds":length}]
func controls(b: Node2D,sc: Dictionary) -> Dictionary:
	var p: Dictionary=b.player_entity()
	var pos: Vector2=p.pos
	var desired: Vector2=Vector2.ZERO
	var brake: bool=false
	var burst: bool=false
	var policy: String=sc.policy
	if policy=="exhaust_then_hunt":
		# Verbatim sampling/controller policy from diagnose_ability_builds:
		# full launch, weak brake corrections until real danger, then aggression.
		if controller_tick%6!=0:
			sampled_comeback.burst=false
			return sampled_comeback
		if float(p.rpm)<=.28 and float(comeback_progress.danger_at)<0.0: comeback_progress.danger_at=b.elapsed
		var c: Dictionary=Bot.input(b,"aggressive",controller_tick)
		if float(comeback_progress.danger_at)<0.0:
			c.direction=screen((-pos-Vector2(p.vel)*.4).normalized()*.06);c.brake=true;c.burst=false
		else:
			c=Bot.input(b,"aggressive",controller_tick)
			comeback_progress.recovery_peak=maxf(float(comeback_progress.recovery_peak),float(p.rpm))
		if pos.length()>145.0: c.direction=screen(-pos.normalized()*.80);c.brake=true
		sampled_comeback=c
		return c
	if policy=="pursuit" or policy=="wall":
		var target: Dictionary=b._target_for(p)
		var distance: float=INF
		if not target.is_empty():
			var offset: Vector2=Vector2(target.pos)-pos
			distance=offset.length();desired=offset.normalized()
		if policy=="wall" and float(p.iron_comet_time)<=0.0 and int(b.powers.counters.get("comet_release",0))<2:
			desired=(Vector2(-182,-60)-pos).normalized()
		if pos.length()>155.0 and policy!="wall": desired=-pos.normalized();brake=pos.length()>170.0
		burst=float(p.cooldown)<=0.0 and distance<130.0 and not brake
		if policy=="wall" and float(p.iron_comet_time)<=0.0: burst=float(p.cooldown)<=0.0
	if policy=="orbit":
		var radial: Vector2=pos.normalized() if pos.length()>1.0 else Vector2.RIGHT
		var tangent: Vector2=Vector2(-radial.y,radial.x)
		var vel: Vector2=p.vel
		var radius: float=114.0
		var pace: float=155.0 if family=="ghost_circuit" else 190.0
		var route: Vector2=tangent*pace+radial*(radius-pos.length())*2.0
		var thrust: Vector2=(route-vel)*4.0+route*.75-radial*(pace*pace/radius)
		var available: float=(123.0+float(p.stats.grip)*17.0)*float(p.handling.get("acceleration",1.0))
		if float(p.burst_time)>0.0: available*=1.65
		desired=thrust.limit_length(available)/available
		burst=float(p.cooldown)<=0.0 and pos.length()<145.0 and family!="ghost_circuit"
		brake=family in ["late_build","drift_carving"] and controller_tick%180>135 and controller_tick%180<170
	return {"direction":screen(desired),"brake":brake,"burst":burst}
func sample(b: Node2D) -> Dictionary:
	var p: Dictionary=b.player_entity()
	return {"time":b.elapsed,"rpm":p.rpm,"speed":Vector2(p.vel).length(),"position":[p.pos.x,p.pos.y],"heat":p.get("redline_heat",0.0),"overcap":p.get("redline_overcap",0.0),"clutch_active":p.get("clutch_active",false),"wobble":p.wobble,"preview":not Dictionary(p.get("ghost_preview",{})).is_empty(),"drift_active":p.get("drift_active",false),"orbit_charge":p.get("orbit_charge",0.0),"fx":b._power_fx.size(),"counters":b.powers.counters.duplicate()}
func step(b: Node2D,sc: Dictionary) -> void:
	var input: Dictionary=controls(b,sc)
	b.test_step(Physics.FIXED_DT,input.direction,input.burst,input.brake)
	controller_tick+=1
func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var ordered: Array[float]=values.duplicate();ordered.sort()
	return {"samples":ordered.size(),"median":ordered[ordered.size()/2],"p95":ordered[mini(ordered.size()-1,int(ordered.size()*.95))],"max":ordered.back()}
func play(sc: Dictionary,sound: Node) -> Dictionary:
	var b=B.new();root.add_child(b);b.set_physics_process(false)
	var d: Dictionary=E.for_run_event(1,seed_id);d.starter_id=sc.starter;d.player_power_ids=sc.ranks.keys();d.player_power_ranks=sc.ranks;d.player_power_mutations=sc.mutations;d.ability_rebalance=true
	b.begin_run(S.build_for(sc.starter),d,seed_id);b.battle_status="battle"
	var p: Dictionary=b.player_entity()
	if sc.policy=="orbit":
		p.pos=Vector2(114,0);p.vel=Vector2.ZERO
		b.powers._state(p).trace_origin=p.pos;b.powers._state(p).trace_path=[Vector2(p.pos)]
	controller_tick=0
	comeback_progress={"danger_at":-1.0,"recovery_peak":0.0}
	sampled_comeback={"direction":Vector2.ZERO,"burst":false,"brake":false}
	var rows: Array[Dictionary]=[]
	var next_sample: float=0.0
	var frames: int=0
	while b.elapsed<start and b.battle_status!="finished" and frames<150000:
		step(b,sc);frames+=1
		if b.elapsed>=next_sample: rows.append(sample(b));next_sample+=.25
	if not diagnostic: b.event_sfx.connect(sound.play_sound)
	var label=Label.new();label.position=Vector2(12,8);label.add_theme_font_size_override("font_size",9);root.add_child(label)
	# Upper-bank Comet contact can reach the top edge. Keep its caption in
	# the empty footer outside the arena so charge and impact stay readable.
	if family=="iron_comet": label.position=Vector2(12,326)
	var before: Dictionary=b.continuous.economy.snapshot()
	var cpu: Array[float]=[]
	var wall: Array[float]=[]
	b.draw_samples.clear()
	var last_wall: int=Time.get_ticks_usec()
	for frame: int in range(int(float(sc.seconds)*60.0)):
		var began: int=Time.get_ticks_usec();step(b,sc);cpu.append(float(Time.get_ticks_usec()-began)/1000.0)
		label.text="%s\nOPENING BUILD / REAL COMBAT | RPM %d%%  SPEED %d  HEAT %d%%   %.1fs"%[sc.label,roundi(float(p.rpm)*100),roundi(Vector2(p.vel).length()),roundi(float(p.get("redline_heat",0.0))*100),b.elapsed]
		if family=="drift_carving":
			label.text="%s\nOPENING BUILD / INPUTS ONLY | RPM %d%%  SPEED %d  DRIFT %s  ORBIT %d%%  %.1fs"%[sc.label,roundi(float(p.rpm)*100),roundi(Vector2(p.vel).length()),"ACTIVE" if bool(p.get("drift_active",false)) else "READY",roundi(float(p.get("orbit_charge",0.0))*100),b.elapsed]
		label.modulate=Color("ffad79") if float(p.rpm)<.28 else Color("e2e8d5")
		assert(is_same(p,b.player_entity()))
		if b.elapsed>=next_sample: rows.append(sample(b));next_sample+=.25
		if not diagnostic:
			b.queue_redraw();await process_frame
			wall.append(float(Time.get_ticks_usec()-last_wall)/1000.0);last_wall=Time.get_ticks_usec()
			if not out_dir.is_empty() and frame%180==0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out_dir.path_join(family+"-%04d.png"%frame))
		if b.battle_status=="finished" and diagnostic: break
	var result: Dictionary={"preset":sc,"seed":seed_id,"before":before,"after":b.continuous.economy.snapshot(),"rows":rows,"procs":b.powers.counters.duplicate(),"events":b.powers.events.duplicate(true),"result":b.last_result,"active_seconds":b.elapsed,"comeback_progress":comeback_progress.duplicate(),"simulation_ms":stats(cpu),"draw_submission_ms":stats(b.draw_samples),"frame_wall_ms":stats(wall),"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name()}
	label.free();b.free()
	return result
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--family="): family=arg.trim_prefix("--family=")
		if arg.begins_with("--manifest="): output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--start="): start=float(arg.trim_prefix("--start="))
		if arg.begins_with("--length="): length=float(arg.trim_prefix("--length="))
		if arg.begins_with("--seed="): seed_id=int(arg.trim_prefix("--seed="))
		if arg.begins_with("--starter="): requested_starter=arg.trim_prefix("--starter=")
		if arg.begins_with("--mutation="): requested_mutation=arg.trim_prefix("--mutation=")
		if arg.begins_with("--frames="): out_dir=arg.trim_prefix("--frames=")
		if arg=="--diagnostic": diagnostic=true
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not out_dir.is_empty(): DirAccess.make_dir_recursive_absolute(out_dir)
	var sound=Audio.new();root.add_child(sound);sound.apply_settings({"volume":.65,"muted":diagnostic})
	var rows: Array[Dictionary]=[]
	for sc: Dictionary in presets():
		if not requested_starter.is_empty(): sc.starter=requested_starter
		if not requested_mutation.is_empty() and family=="redline_mutation": sc.mutations.redline=requested_mutation;sc.label="RUNAWAY / CONTACT -> SUSTAIN -> ESCALATE" if requested_mutation=="runaway" else sc.label
		rows.append(await play(sc,sound))
	var report: Dictionary={"family":family,"authenticity":"Explicit opening build (and central-orbit pose for movement comparisons), full launch reserve; only steering/Burst/brake after setup. Real continuous Threat Director, rivals, RPM costs/rewards. Fast-forward executes the same ticks. No reserve edits, forced procs or protected outcomes. Static QA excluded.","runs":rows}
	if not output.is_empty(): var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"))
	print("ROSTER_CAPTURE ",family," ",rows.map(func(r: Dictionary) -> Dictionary: return {"seconds":r.active_seconds,"procs":r.procs,"result":r.result}))
	quit()
