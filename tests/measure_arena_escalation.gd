extends SceneTree
## Explicit held stress fixtures only. No natural survival or gameplay claim.
const Battle = preload("res://tests/measured_presentation_battle.gd")
const Physics = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
var output: String = ""
var frames: String = ""
func _initialize() -> void: call_deferred("run")
func stats(values: Array[float]) -> Dictionary:
	values.sort()
	if values.is_empty():return {}
	return {"samples":values.size(),"median_ms":values[values.size()/2],"p95_ms":values[mini(values.size()-1,int(values.size()*0.95))],"max_ms":values.back()}
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
		if arg.begins_with("--frames="):frames=arg.trim_prefix("--frames=")
	if output.is_empty():push_error("External --report required");quit(2);return
	root.size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	if not frames.is_empty():DirAccess.make_dir_recursive_absolute(frames)
	var cases: Array[Dictionary]=[
		{"name":"early","time":30.0,"stress":false,"quality":1.0,"reduced":false},
		{"name":"mature","time":420.0,"stress":false,"quality":1.0,"reduced":false},
		{"name":"extreme_17_bodies_particles_beast","time":560.0,"stress":true,"quality":1.0,"reduced":false},
		{"name":"extreme_reduced_flashing","time":560.0,"stress":true,"quality":1.0,"reduced":true},
		{"name":"extreme_mobile_quality","time":560.0,"stress":true,"quality":0.60,"reduced":false}]
	var results: Array[Dictionary]=[]
	for scenario: Dictionary in cases:
		var b: Node2D=Battle.new();root.add_child(b);b.set_physics_process(false);b.set_process(false)
		var descriptor: Dictionary=Encounters.for_run_event(1,421)
		descriptor.player_power_ids=["dead_centre","clutch","crash_guard","iron_comet","momentum_bank","impact_wake","chain_impact"]
		descriptor.player_power_ranks={"dead_centre":3,"clutch":2,"crash_guard":2,"iron_comet":2,"momentum_bank":2,"impact_wake":2,"chain_impact":2}
		descriptor.player_power_mutations={"dead_centre":"bulwark"};descriptor.starter_id="bastion";descriptor.ability_rebalance=true
		b.begin_run(Starters.build_for("bastion"),descriptor,421);b.battle_status="battle";b.elapsed=float(scenario.time)
		b.reduced_flashing=bool(scenario.reduced);b.presentation_quality=float(scenario.quality)
		b.swarm.schedule.clear()
		if scenario.stress:
			for index: int in range(3):b.add_full_top({"blade":"hammerfall","ratchet":"mid","bit":"flat"},100+index,"hostile","held_%d"%index,Vector2.ZERO)
			for index: int in range(12):b.swarm.add_small(200+index,Vector2(cos(index*TAU/12.0),sin(index*TAU/12.0))*90.0)
			# Disclosed held-load fixture: one real canonical extreme collision
			# starts the single beast. Guard maturity is no longer a spawn hook.
			var source: Dictionary=b.player_entity();var target: Dictionary=b.entity(2)
			assert(not target.is_empty())
			source.pos=Vector2(-float(source.radius)*0.5,0);target.pos=Vector2(float(target.radius)*0.5,0)
			source.vel=Vector2(800,0);target.vel=Vector2(-800,0)
			b._resolve_pair_records(source,target)
			assert(b.beast_presentation_snapshot().active.size()==1)
		var cpu: Array[float]=[];var wall: Array[float]=[];var started: int=Time.get_ticks_usec()
		var peak_particles: int=0;var peak_fx: int=0;var peak_beasts: int=0;var peak_bodies: int=0;var peak_arena: int=0
		var caption: Label=Label.new();caption.text="HELD PROFILER FIXTURE / "+str(scenario.name).to_upper();caption.position=Vector2(12,58)
		caption.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"));caption.add_theme_font_size_override("font_size",10);root.add_child(caption)
		for tick: int in range(360):
			# Hold disclosed synthetic positions/reserves so the profiler measures
			# stable object load. Results cannot establish AI pressure or survival.
			b.battle_status="battle";b.paused=false
			for fighter: Dictionary in b.fighters:
				fighter.outcome="";fighter.rpm=1.0 if fighter.combatant_type=="full_top" else 0.22;fighter.age=0.0
				var id: int=int(fighter.entity_id)
				fighter.pos=Vector2.ZERO if id==1 else Vector2(cos(float(id)*2.4+tick*0.012),sin(float(id)*2.4+tick*0.012))*(90.0 if fighter.combatant_type=="small_top" else 110.0)
			if scenario.stress and tick%4==0:
				b._spawn_sparks(Vector2(330,177),Vector2.RIGHT,24,1.0)
				for index: int in range(8):b.add_power_fx(["comet_release","crash_guard","impact_wake","clutch_recover","momentum_release","counterweight_release","bulwark_impact","chain_impact"][index],Vector2(cos(index*TAU/8.0),sin(index*TAU/8.0))*50.0)
			var before: int=Time.get_ticks_usec();b.test_step(Physics.FIXED_DT,Vector2(sin(tick*0.05),cos(tick*0.05))*0.25,false,tick%90>60)
			var duration: float=float(Time.get_ticks_usec()-before)/1000.0
			var p: Dictionary=b.player_entity();p.outcome="";p.rpm=0.95;p.vel=Vector2(50,25)
			if scenario.stress:
				p.anchor_central_hold=true;p.anchor_hold_seconds=7.0;p.anchor_maturity=1.0;p.anchor_charge=1.0
				b.beasts.update(Physics.FIXED_DT)
			peak_bodies=maxi(peak_bodies,b.fighters.size());peak_particles=maxi(peak_particles,b._particles.size());peak_fx=maxi(peak_fx,b._power_fx.size());peak_beasts=maxi(peak_beasts,b.beast_presentation_snapshot().active.size())
			b.queue_redraw();await process_frame
			peak_arena=maxi(peak_arena,b.arena_presentation.actual_draw_calls)
			if tick==60:b.draw_samples.clear()
			if tick>60:cpu.append(duration);wall.append(float(Time.get_ticks_usec()-started)/1000.0)
			started=Time.get_ticks_usec()
		assert(peak_particles<=120 and peak_fx<=32 and peak_beasts<=1)
		assert(peak_arena<= (14 if float(scenario.quality)<0.75 else 17))
		if scenario.stress:assert(peak_beasts>=1)
		if not frames.is_empty():
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(frames.path_join(str(scenario.name)+".png"))
		results.append({"scenario":scenario,"simulation_ms":stats(cpu),"draw_submission_ms":stats(b.draw_samples),"frame_wall_ms":stats(wall),"peak_bodies":peak_bodies,"peak_particles":peak_particles,"peak_fx":peak_fx,"peak_beasts":peak_beasts,"peak_arena_draw_calls":peak_arena,"presentation":b.arena_presentation.last_snapshot.duplicate(true),"render_draw_calls_total":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		caption.free();b.free()
	var report: Dictionary={"scope":"Explicit held object/state stress fixtures, never natural Run survival/Director acceptance. Native640x360, VSyncdisabled. CPU draw submission excludes asynchronous GPU. Wall frames include harness. Desktop mobilequality renderer measurement is not Android physical device performance.","gpu":RenderingServer.get_video_adapter_name(),"processor":OS.get_processor_name(),"cases":results,"collection_opened":false,"maximum_cosmetic_nodes":0,"maximum_cosmetic_particles":0}
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("ARENA_PRESENTATION_BENCHMARK ",JSON.stringify(report));quit()
