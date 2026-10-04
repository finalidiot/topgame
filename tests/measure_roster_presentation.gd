extends SceneTree
## Explicit held stress fixture. Never natural survival/proc/video evidence.
const B=preload("res://tests/measured_presentation_battle.gd")
const E=preload("res://scripts/encounters.gd")
const S=preload("res://scripts/starters.gd")
const Physics=preload("res://scripts/battle.gd")
var output: String=""
var frame_path: String=""
func _initialize() -> void: call_deferred("run")
func stats(values: Array[float]) -> Dictionary:
	values.sort();return {"samples":values.size(),"median":values[values.size()/2],"p95":values[mini(values.size()-1,int(values.size()*.95))],"max":values.back()}
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output=arg.trim_prefix("--report=")
		if arg.begins_with("--frame="): frame_path=arg.trim_prefix("--frame=")
	root.size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var b=B.new();root.add_child(b);b.set_physics_process(false)
	var d: Dictionary=E.for_run_event(1,7341)
	d.player_power_ids=["redline","high_gear","afterimage","iron_comet","orbit_drive","clutch","crash_guard"]
	d.player_power_ranks={"redline":3,"high_gear":3,"afterimage":3,"iron_comet":2,"orbit_drive":2,"clutch":2,"crash_guard":2}
	d.player_power_mutations={"redline":"runaway","high_gear":"flow_state","afterimage":"ghost_circuit"};d.ability_rebalance=true
	b.begin_run(S.build_for("vane"),d,7341);b.battle_status="battle"
	b.swarm.schedule.clear()
	for i: int in range(12): b.swarm.add_small(200+i,Vector2(cos(i*TAU/12.0),sin(i*TAU/12.0))*64.0)
	var cpu: Array[float]=[]
	var walls: Array[float]=[]
	var maximum_fx: int=0
	var before_frame: int=Time.get_ticks_usec()
	var label=Label.new();label.text="HELD FX STRESS / 7 POWERS + 12 SMALL BODIES";label.position=Vector2(12,8);label.add_theme_font_size_override("font_size",13);root.add_child(label)
	for tick: int in range(480):
		b.battle_status="battle";b.swarm.enabled=true
		for f: Dictionary in b.fighters:
			f.outcome="";f.rpm=1.0 if f.combatant_type=="full_top" else .22;f.age=0.0
			var angle: float=float(int(f.entity_id)-200)*TAU/12.0+float(tick)*.015
			f.pos=Vector2.ZERO if f.combatant_type=="full_top" else Vector2(cos(angle),sin(angle))*60.0
		if tick%4==0:
			for i: int in range(8):
				var kind: String=["comet_release","clutch_recover","redline_heat","high_gear_surge","momentum_release","crosscut","ghost_closure","crash_guard"][i]
				b.add_power_fx(kind,Vector2(cos(i*TAU/8.0+tick),sin(i*TAU/8.0+tick))*42.0)
		var began: int=Time.get_ticks_usec();b.test_step(Physics.FIXED_DT,Vector2(sin(tick*.12),cos(tick*.12)),tick%250==0,tick%90>65)
		var duration: float=float(Time.get_ticks_usec()-began)/1000.0
		var p: Dictionary=b.player_entity()
		# These clearly disclosed states exercise simultaneous authored draw paths.
		p.outcome="";p.rpm=1.18;p.redline_time=.6;p.redline_heat=.85;p.iron_comet_time=1.0;p.vel=Vector2(260,40);p.drift_active=true;p.orbit_charge=.8;p.guard_time=.7
		maximum_fx=maxi(maximum_fx,b._power_fx.size());assert(maximum_fx<=32)
		b.queue_redraw();await process_frame
		if tick==60: b.draw_samples.clear()
		if tick>60: cpu.append(duration);walls.append(float(Time.get_ticks_usec()-before_frame)/1000.0)
		before_frame=Time.get_ticks_usec()
	var result: Dictionary={"scope":"Explicit held12-small-body/seven-family/32-FX stress fixture with synthetic visual states, never natural gameplay or survival evidence. Native640x360, VSyncdisabled. CPU draw submission excludes asynchronous GPU; wall frame includes harness.","processor":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),"simulation_ms":stats(cpu),"draw_submission_ms":stats(b.draw_samples),"frame_wall_ms":stats(walls),"small_bodies":b.swarm.active_count(),"max_fx":maximum_fx,"cap_fx":32,"render_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	if not output.is_empty(): var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"))
	if not frame_path.is_empty():
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(frame_path)
	print("ROSTER_RENDER_BENCHMARK ",JSON.stringify(result))
	label.free();b.free();quit()
