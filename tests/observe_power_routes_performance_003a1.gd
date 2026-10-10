extends SceneTree
## Initial clock/admission/ownership/pose fixtures; real fixed physics thereafter.
const Battle = preload("res://tests/measured_presentation_battle.gd")
const Physics = preload("res://scripts/battle.gd")
const Director = preload("res://scripts/threat_director.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Roles = preload("res://scripts/enemy_roles.gd")
const Starters = preload("res://scripts/starters.gd")
const MeasuredPowers = preload("res://tests/measured_power_routes_003a1.gd")
var output: String=""
var label: String="development"
var rendered: bool=false
var horizon: int=720
var seeds: Array[int]=[421,7341,2026]
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok and not message in failures:failures.append(message)
func stats(values: Array[float]) -> Dictionary:
	if values.is_empty():return {"samples":0}
	var sorted: Array[float]=values.duplicate();sorted.sort()
	return {"samples":sorted.size(),"median_ms":sorted[sorted.size()/2],"p95_ms":sorted[mini(sorted.size()-1,ceili(sorted.size()*.95)-1)],"max_ms":sorted.back(),"mean_ms":values.reduce(func(a: float,b: float) -> float:return a+b,0.0)/values.size()}
func portable(value: Variant) -> Variant:
	if value is Vector2:return [value.x,value.y]
	if value is Array:
		var result: Array=[]
		for entry: Variant in value:result.append(portable(entry))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=portable(value[key])
		return result
	return value

func event_for(role: String, serial: int, clock: float) -> Dictionary:
	for event: Dictionary in Director.EVENTS:
		if event.key==role:
			var copy: Dictionary=event.duplicate(true);copy["serial"]=serial;copy["tier_at_entry"]=Director.tier_at(clock);return copy
	return {}
func fixture(count: int, clock: float, seed_value: int) -> Node2D:
	var b: Node2D=Battle.new();root.add_child(b);b.set_process(false);b.set_physics_process(false)
	b.powers=MeasuredPowers.new()
	var descriptor: Dictionary=Encounters.for_run_event(1,seed_value)
	descriptor.starter_id="vane";descriptor.player_power_ids=["afterimage","orbit_drive","chain_impact"]
	descriptor.player_power_ranks={"afterimage":3,"orbit_drive":2,"chain_impact":2};descriptor.player_power_mutations={"afterimage":"ghost_circuit"}
	b.begin_run(Starters.build_for("vane"),descriptor,seed_value)
	while b.battle_status!="battle":b.test_step(Physics.FIXED_DT)
	b.elapsed=clock
	var names: Array[String]=["hunter","flanker","harasser","bulwark","hunter","flanker"]
	for index: int in range(1,count):
		var event: Dictionary=event_for(names[index],index+1,clock)
		b.continuous.director.active[index+1]={"time":clock,"kind":event.kind}
		b.continuous._admit(event,Vector2(104,0).rotated(TAU*index/count))
	# Explicit initial ownership fixture, after opening package initialization.
	# Every activation still needs ordinary motion, RPM, costs and geometry.
	b.entity(2).powers=["afterimage"];b.entity(2).power_ranks={"afterimage":3};b.entity(2).power_mutations={"afterimage":"ghost_circuit"}
	b.entity(3).powers=["afterimage"];b.entity(3).power_ranks={"afterimage":2};b.entity(3).power_mutations={}
	for index: int in range(count):
		var f: Dictionary=b.entity(index+2)
		f.pos=Vector2(104,0).rotated(TAU*index/count)
		f.vel=Vector2(f.pos).normalized().orthogonal()*180.0
		f.ai_clock=0.0
	b.player_entity().pos=Vector2(-34,-14);b.player_entity().vel=Vector2(0,-175)
	# Initialize normal semantic state against those declared starting poses;
	# the first paid route must not bridge the earlier launch position.
	b.powers.setup(b)
	# These are global live-combat clocks. Pilots compare paid-route advice
	# expiry against Battle.elapsed, so the declared mature starting offset
	# must also initialize the ordinary semantic/roster clocks once.
	b.powers.time=clock;b.roster.time=clock
	check(is_equal_approx(b.powers.time,b.elapsed) and is_equal_approx(b.roster.time,b.elapsed),"Initial live-combat clocks share the declared fixture epoch")
	b.continuous.director.serial=count
	b.continuous.director.next_decision=99999.0;b.continuous.director.calm_until=99999.0;b.continuous.reward_fixture=true
	return b
func control(b: Node2D, tick: int) -> Dictionary:
	var p: Dictionary=b.player_entity();var pos: Vector2=p.pos
	var radial: Vector2=pos-Vector2(-8,3)
	if radial.length()<1.0:radial=Vector2.LEFT
	var world: Vector2=radial.normalized().orthogonal()*.86-radial.normalized()*clampf((radial.length()-52.0)/44.0,-.55,.65)
	var screen: Vector2=Vector2(world.x-world.y,(world.x+world.y)*.5).limit_length(1.0)
	return {"direction":screen,"burst":tick>0 and tick%210==0,"brake":tick%180>=155 and tick%180<165}
func full_count(b: Node2D) -> int:
	var n: int=0
	for f: Dictionary in b.fighters:
		if f.owner_id!="player" and f.combatant_type=="full_top" and str(f.outcome).is_empty():n+=1
	return n
func observe(b: Node2D) -> Dictionary:
	var owners: Dictionary={};var ghost_owners: int=0;var point_peak: int=0;var consumed: int=0;var circuit_peak: int=0
	var npc_advice: Array[Dictionary]=[];var available: int=0;var safe_position_advice: int=0
	for f: Dictionary in b.fighters:
		if str(f.outcome).is_empty() and b.powers.mutation(f,"afterimage")=="ghost_circuit":ghost_owners+=1
		if f.owner_id=="player" or not str(f.outcome).is_empty():continue
		var hint: Dictionary=f.get("ghost_route_advice",{})
		if hint.is_empty():continue
		var current: bool=bool(hint.get("paid_visible_live",false)) and float(hint.get("expires_at",-1.0))>b.elapsed
		var pilot: Dictionary=f.get("pilot",{})
		var distance: float=Vector2(hint.point).distance_to(f.pos)
		var safe: bool=current and str(pilot.get("state",""))=="position" and float(pilot.get("clearance",0.0))>38.0 and float(f.rpm)>.22 and distance>3.0 and distance<90.0
		if current:available+=1
		if safe:safe_position_advice+=1
		npc_advice.append({"owner":f.entity_id,"hint":hint.duplicate(true),"current_at_battle_clock":current,"safe_position_opportunity":safe,"pilot_state":pilot.get("state","")})
	for trace: Dictionary in b.powers.traces:
		owners[int(trace.owner_entity_id)]=true
		point_peak=maxi(point_peak,trace.get("points",[]).size());consumed+=trace.get("ghost_used_edges",[]).size()
		circuit_peak=maxi(circuit_peak,trace.get("circuit_points",[]).size())
	var diagnostics: Dictionary=b.powers.ghost_route_diagnostics() if b.powers.has_method("ghost_route_diagnostics") else {}
	return {"active_full":full_count(b),"live_routes":b.powers.traces.size(),"route_owners":owners.keys(),"live_ghost_owners":ghost_owners,"trace_points_peak":point_peak,"circuit_points_peak":circuit_peak,"consumed_edge_intervals":consumed,"route_diagnostics":diagnostics,"npc_advice":npc_advice,"current_npc_advice":available,"safe_position_advice_opportunities":safe_position_advice,"clock_epoch":{"battle":b.elapsed,"powers":b.powers.time,"roster":b.roster.time},"particles":b._particles.size(),"fx":b._power_fx.size(),"power_events":b.powers.events.size(),"power_states":b.powers._states.size(),"static_memory_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))}
func play(count: int, seed_value: int) -> Dictionary:
	var clock: float=280.0 if count==4 else (640.0 if count==5 else 880.0)
	var b: Node2D=fixture(count,clock,seed_value)
	var initial: Array[Dictionary]=[]
	for f: Dictionary in b.fighters:initial.append({"id":f.entity_id,"build":f.build.duplicate(true),"role":f.get("role","player"),"pos":f.pos,"vel":f.vel,"rpm":f.rpm,"powers":f.powers.duplicate(),"ranks":f.power_ranks.duplicate(true),"mutations":f.power_mutations.duplicate(true)})
	var cpu: Array[float]=[];var dense_cpu: Array[float]=[];var routes_cpu: Array[float]=[];var walls: Array[float]=[]
	var advancing_cpu: Array[float]=[];var advancing_frames: int=0;var impact_hold_frames: int=0
	var power_movement: Array[float]=[];var power_circuit: Array[float]=[]
	var rows: Array[Dictionary]=[];var peaks: Dictionary={};var dense: int=0;var multi: int=0;var multi_dense: int=0;var search_steps: int=0;var max_builds_per_tick: int=0;var max_searches_per_tick: int=0
	var frames_run: int=0
	var advice_frames: int=0;var safe_advice_frames: int=0
	var last: int=Time.get_ticks_usec();var before_diag: Dictionary=b.powers.ghost_route_diagnostics() if b.powers.has_method("ghost_route_diagnostics") else {}
	for tick: int in range(horizon):
		if b.battle_status!="battle":break
		var c: Dictionary=control(b,tick)
		b.powers.reset_sample()
		var before_clock: float=b.elapsed
		var began: int=Time.get_ticks_usec();b.test_step(Physics.FIXED_DT,c.direction,c.burst,c.brake)
		frames_run+=1
		var ms: float=float(Time.get_ticks_usec()-began)/1000.0
		var advances: bool=b.elapsed>before_clock
		if advances:advancing_frames+=1
		else:impact_hold_frames+=1
		var o: Dictionary=observe(b)
		check(is_equal_approx(b.powers.time,b.elapsed) and is_equal_approx(b.roster.time,b.elapsed),"Semantic/roster clocks stay synchronized on real advancing and impact-hold frames")
		if o.current_npc_advice>0:advice_frames+=1
		if o.safe_position_advice_opportunities>0:safe_advice_frames+=1
		if o.active_full==count:dense+=1
		var multi_routes: bool=o.route_owners.size()>=3 and o.live_ghost_owners>=2
		if multi_routes:multi+=1
		if multi_routes and o.active_full==count:multi_dense+=1
		if tick>=60:
			cpu.append(ms)
			if advances:advancing_cpu.append(ms)
			power_movement.append(float(b.powers.movement_us)/1000.0);power_circuit.append(float(b.powers.circuit_us)/1000.0)
			if o.active_full==count:dense_cpu.append(ms)
			if multi_routes:routes_cpu.append(ms)
		for key: String in ["active_full","live_routes","live_ghost_owners","trace_points_peak","circuit_points_peak","consumed_edge_intervals","particles","fx","power_events","power_states","static_memory_bytes","objects","resources","draw_calls"]:peaks[key]=maxi(int(peaks.get(key,0)),int(o[key]))
		peaks.route_owners=maxi(int(peaks.get("route_owners",0)),o.route_owners.size())
		if not o.route_diagnostics.is_empty():
			var d: Dictionary=o.route_diagnostics
			var builds: int=int(d.index_builds)-int(before_diag.get("index_builds",0));var searches: int=int(d.searches)-int(before_diag.get("searches",0))
			max_builds_per_tick=maxi(max_builds_per_tick,builds);max_searches_per_tick=maxi(max_searches_per_tick,searches)
			if searches>0:search_steps+=1
			for key: String in ["indexed_routes","indexed_edges","candidate_edges"]:peaks[key]=maxi(int(peaks.get(key,0)),int(d[key]))
			check(builds<=2,"Only two Ghost owners can build/rebuild the index per tick")
			check(searches<=2,"Only two actual Ghost owners search per tick")
			before_diag=d.duplicate(true)
		check(o.live_routes<=72 and o.trace_points_peak<=16 and o.circuit_points_peak<=224,"Route/path geometry stays bounded")
		check(o.particles<=120 and o.fx<=32 and o.power_events<=256,"Cosmetic/events bounded")
		check(o.power_states<=count+1,"Per-owner runtime state bounded")
		for f: Dictionary in b.fighters:check(is_finite(float(f.rpm)) and Vector2(f.pos).is_finite() and Vector2(f.vel).is_finite(),"Finite physical state")
		if tick%12==0:rows.append({"tick":tick,"elapsed":b.elapsed,"observation":o,"control":c,"player_rpm":b.player_entity().rpm,"hits":b.hits,"powers":b.powers.counters.duplicate(true),"powers_after_movement_ms":float(b.powers.movement_us)/1000.0,"ghost_circuit_ms":float(b.powers.circuit_us)/1000.0})
		if rendered:
			if tick==59:b.draw_samples.clear()
			b.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
			if tick>=60:walls.append(float(Time.get_ticks_usec()-last)/1000.0)
			last=Time.get_ticks_usec()
		elif tick%120==0:await process_frame
	var final: Array[Dictionary]=[]
	for f: Dictionary in b.fighters:final.append({"id":f.entity_id,"pos":f.pos,"vel":f.vel,"rpm":f.rpm,"outcome":f.outcome,"pilot_state":f.get("pilot",{}).get("state","")})
	check(dense>=120,"At least two real seconds at requested full-top density")
	check(multi>=30,"At least half a second with three paid-route owners and two live Ghost owners")
	var result: Dictionary={"seed":seed_value,"full_enemies_fixture":count,"initial_clock_fixture":clock,"initial":initial,"physics_frames":frames_run,"full_density_frames":dense,"multiple_owner_route_frames":multi,"full_density_with_multiple_routes_frames":multi_dense,"simulation_ms":stats(cpu),"requested_density_simulation_ms":stats(dense_cpu),"multiple_owner_routes_simulation_ms":stats(routes_cpu),"draw_submission_ms":stats(b.draw_samples),"frame_wall_ms":stats(walls),"peaks":peaks,"search_steps":search_steps,"max_index_builds_per_tick":max_builds_per_tick,"max_owner_searches_per_tick":max_searches_per_tick,"final_powers":b.powers.counters.duplicate(true),"final_route_diagnostics":before_diag,"final":final,"trace":rows,"battle_status":b.battle_status,"natural_survival_claim":false}
	result["power_after_movement_ms"]=stats(power_movement);result["ghost_circuit_ms"]=stats(power_circuit)
	result["simulation_advancing_frames"]=advancing_frames;result["real_impact_hold_frames"]=impact_hold_frames
	result["current_npc_advice_frames"]=advice_frames;result["safe_position_advice_opportunity_frames"]=safe_advice_frames;result["clocks_synchronized"]=true
	result["samples_ms"]={"simulation":cpu,"simulation_advancing":advancing_cpu,"requested_density":dense_cpu,"multiple_routes":routes_cpu,"power_after_movement":power_movement,"ghost_circuit":power_circuit,"draw_submission":b.draw_samples.duplicate(),"frame_wall":walls}
	b.free();await process_frame
	return result
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
		if arg=="--rendered":rendered=true
		if arg.begins_with("--ticks="):horizon=int(arg.trim_prefix("--ticks="))
		if arg.begins_with("--seed="):seeds.assign([int(arg.trim_prefix("--seed="))])
	if output.is_empty() or FileAccess.file_exists(output):push_error("Fresh external --report required");quit(2);return
	# Standalone profiler surface is native640x360. This initial harness window
	# minimum avoids the Main800x480 chrome minimum clamping a smaller surface.
	root.min_size=Vector2i(640,360);root.size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	check(root.size==Vector2i(640,360),"Actual profiler viewport is native640x360")
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	Engine.max_fps=0
	if rendered:DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cases: Array[Dictionary]=[]
	for seed_value: int in seeds:
		for count: int in [4,5,6]:cases.append(await play(count,seed_value))
	var report: Dictionary={"label":label,"rendered":rendered,"seeds":seeds,"ticks_per_case":horizon,"native_view":[640,360],"processor":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),"cases":cases,"failures":failures,"main_created":false,"collection_opened":false,"scope":"Revision2 final-source clock-synchronized fixture: initial Battle/PowerRuntime/Roster epochs all280/640/880, then advance only by ordinary real fixed ticks. Seeded initial admissions/poses/velocities and legal invested power ownership are explicit load fixtures. Player GhostIII/OrbitII/ChainII, hostile GhostIII, separate hostile AfterimageII; other opponents use actual packages and all actual smart pilots. Initial5/6 counts deliberately exceed the baseline Director cap for matched physics load. Extra Director admissions suspended; no ongoing position/RPM/outcome/activation/advice holds. Real fixed60Hz AI/controls/costs/solver afterward. Nonexpired NPC advice and safe position opportunities are observed, never injected; opportunity counts do not claim every hint caused a decision. Native Windows standalone Battle without Main/HUD/music; CPU draw submission excludes asynchronous GPU; wall includes harness/read-only monitors, uncapped/VSyncoff. Not natural survival, human pressure or Android device performance."}
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(portable(report),"\t"));file.close()
	print("POWER_ROUTES_PERFORMANCE_%s cases=%d"%["PASS" if failures.is_empty() else "FAIL",cases.size()]);quit(0 if failures.is_empty() else 1)
