extends SceneTree
## Declared legal load/admission/pose/epoch fixtures, then real pilots/solver.
## The same observer runs accepted main with II equivalents and current III.
const Physics = preload("res://scripts/battle.gd")
const Director = preload("res://scripts/threat_director.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Starters = preload("res://scripts/starters.gd")
const Identity = preload("res://scripts/power_identity.gd")

class TimedBattle:
	extends "res://scripts/battle.gd"
	var draw_samples: Array[float] = []
	func _draw() -> void:
		var start: int = Time.get_ticks_usec()
		super._draw()
		draw_samples.append(float(Time.get_ticks_usec()-start)/1000.0)
		if draw_samples.size() > 1800: draw_samples.pop_front()

var output: String = ""
var label: String = "development"
var rendered: bool = false
var cleanup_only: bool = false
var horizon: int = 720
var seeds: Array[int] = [421,7341,2026]
var failures: Array[String] = []
var checks: int = 0
const NEW_PAIRS: Dictionary = {
	"iron_comet":["wallbreaker","ricochet_engine"],
	"orbit_drive":["centrifuge","perpetual_orbit"],
	"momentum_bank":["flywheel_release","countersteer"],
	"crash_guard":["reactive_plating","sacrificial_damper"]}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not message in failures: failures.append(message)
func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Array or value is PackedVector2Array:
		var array: Array = []
		for item: Variant in value: array.append(portable(item))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key: Variant in value: dictionary[str(key)] = portable(value[key])
		return dictionary
	return value
func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"samples":0}
	var sorted: Array[float] = values.duplicate(); sorted.sort()
	return {"samples":sorted.size(),"median_ms":sorted[sorted.size()/2],"p95_ms":sorted[mini(sorted.size()-1,ceili(sorted.size()*.95)-1)],"max_ms":sorted.back()}
func ecology(b: Node2D) -> Object: return b.roster.get("ecology")
func epoch(b: Node2D, time: float) -> void:
	b.elapsed = time; b.powers.time = time; b.roster.time = time; b.powers.defence.time = time
	if ecology(b) != null: ecology(b).time = time
func clocks_match(b: Node2D) -> bool:
	return is_equal_approx(b.elapsed,b.powers.time) and is_equal_approx(b.elapsed,b.roster.time) and is_equal_approx(b.elapsed,b.powers.defence.time) and (ecology(b)==null or is_equal_approx(b.elapsed,ecology(b).time))
func event_for(role: String, serial: int, clock: float) -> Dictionary:
	for definition: Dictionary in Director.EVENTS:
		if definition.key == role:
			var event: Dictionary = definition.duplicate(true)
			event.serial = serial; event.tier_at_entry = Director.tier_at(clock)
			return event
	return {}
func ownership(f: Dictionary, branches: Dictionary, support: Array[String]) -> void:
	var ids: Array[String] = []; var ranks: Dictionary = {}; var mutations: Dictionary = {}
	for family: String in branches:
		ids.append(family)
		var branch: String = str(branches[family])
		var legal: bool = branch in Powers.mutation_choices(family)
		ranks[family] = 3 if legal else 2
		if legal: mutations[family] = branch
	for family: String in support:
		if family in ids: continue
		ids.append(family); ranks[family] = 3 if family == "afterimage" else 2
		if family == "afterimage": mutations[family] = "ghost_circuit"
	check(ids.size() <= Powers.FAMILY_CAP, "Legal seven-family ownership fixture")
	for family: String in ids:
		check(not Powers.get_owned_power(family,int(ranks[family]),str(mutations.get(family,""))).is_empty(), "Legal current/baseline fixture form")
	f.powers = ids; f.power_ranks = ranks; f.power_mutations = mutations
func loadout(f: Dictionary, index: int) -> void:
	match index:
		0: ownership(f,{"orbit_drive":"centrifuge","momentum_bank":"countersteer"},["afterimage","high_gear","chain_impact","impact_sink"])
		1: ownership(f,{"iron_comet":"wallbreaker","crash_guard":"reactive_plating"},["high_gear"])
		2: ownership(f,{"iron_comet":"ricochet_engine","momentum_bank":"flywheel_release"},["orbit_drive","high_gear"])
		3: ownership(f,{"orbit_drive":"perpetual_orbit","crash_guard":"sacrificial_damper"},["afterimage"])
		4: ownership(f,{"momentum_bank":"flywheel_release"},["redline","impact_sink"])
		5: ownership(f,{"momentum_bank":"countersteer","crash_guard":"reactive_plating"},["redline","impact_sink"])
		6: ownership(f,{"orbit_drive":"centrifuge"},["afterimage","high_gear"])
func fixture(count: int, clock: float, seed_value: int) -> Node2D:
	var b: Node2D = TimedBattle.new(); root.add_child(b)
	b.set_process(false); b.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1,seed_value)
	descriptor.starter_id = "vane"
	b.begin_run(Starters.build_for("vane"),descriptor,seed_value)
	while b.battle_status != "battle": b.test_step(Physics.FIXED_DT)
	var names: Array[String] = ["hunter","flanker","harasser","hunter","bulwark","flanker"]
	for index: int in range(1,count):
		var event: Dictionary = event_for(names[index],index+1,clock)
		b.continuous.director.active[index+1] = {"time":clock,"kind":event.kind}
		b.continuous._admit(event,Vector2(110,0).rotated(TAU*index/count))
	var positions: Array[Vector2] = [Vector2(158,0),Vector2(-145,40),Vector2(0,-110),Vector2(0,110),Vector2(-95,-75),Vector2(95,75)]
	var velocities: Array[Vector2] = [Vector2(235,0),Vector2(-170,95),Vector2(185,0),Vector2(-185,0),Vector2(110,-135),Vector2(-110,135)]
	loadout(b.player_entity(),0)
	b.player_entity().pos = Vector2(-34,-14); b.player_entity().vel = Vector2(0,-175)
	for index: int in range(count):
		var f: Dictionary = b.entity(index+2)
		check(f.has("role") and f.combatant_type == "full_top", "Real full-top role pilot preserved")
		loadout(f,index+1); f.pos = positions[index]; f.vel = velocities[index]; f.ai_clock = 0.0
	b.powers.setup(b); b.roster.setup(b); epoch(b,clock)
	b.continuous.director.serial = count
	# Fixed-density load fixture, not natural Director progression. Only extra
	# admissions stop; existing pilots, outcomes and retirement remain ordinary.
	b.continuous.director.next_decision = 1e9; b.continuous.director.calm_until = 1e9
	b.continuous.reward_fixture = true
	check(clocks_match(b), "Initial Battle/Power/Roster/Defence/Ecology epochs agree")
	return b
func control(b: Node2D, tick: int) -> Dictionary:
	var radial: Vector2 = Vector2(b.player_entity().pos)-Vector2(-8,3)
	if radial.length()<1.0: radial=Vector2.LEFT
	var world: Vector2 = radial.normalized().orthogonal()*.86-radial.normalized()*clampf((radial.length()-52.0)/44.0,-.55,.65)
	return {"direction":Vector2(world.x-world.y,(world.x+world.y)*.5).limit_length(1.0),"burst":tick>0 and tick%210==0,"brake":tick%180>=155 and tick%180<165}
func physical(b: Node2D) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for f: Dictionary in b.fighters:
		var published: Dictionary = {}
		for key: String in ["orbit_charge","orbit_flow","momentum_charge","ecology_commit_time","ecology_heading","reactive_force","reactive_time","damper_time","comet_time","ricochet_count"]:published[key]=f.get(key,0.0)
		rows.append({"id":f.entity_id,"build":f.build.duplicate(true),"role":f.get("role","player"),"pos":f.pos,"vel":f.vel,"rpm":f.rpm,"outcome":f.outcome,"powers":f.powers.duplicate(),"ranks":f.power_ranks.duplicate(true),"mutations":f.power_mutations.duplicate(true),"pilot_state":f.get("pilot",{}).get("state",""),"published_power_state":published})
	return rows
func observe(b: Node2D) -> Dictionary:
	var active: int = 0; var powered: int = 0; var route_owners: Dictionary = {}
	var trace_points: int = 0; var circuit_points: int = 0; var target_entries: int = 0
	var active_ecology: int = 0; var commit: int = 0; var loaded: int = 0; var buckled: int = 0; var drive_peak: float = 0.0
	var pilot_states: Dictionary = {}; var ids: Array[int] = [];var pilot_history: int=0;var owner_fields: int=0
	for f: Dictionary in b.fighters:
		ids.append(int(f.entity_id))
		pilot_history=maxi(pilot_history,f.get("pilot",{}).get("history",[]).size())
		if f.owner_id != "player" and str(f.outcome).is_empty():
			active+=1
			if not f.powers.is_empty(): powered+=1
			var state: String = str(f.get("pilot",{}).get("state","")); pilot_states[state]=int(pilot_states.get(state,0))+1
		if str(f.outcome).is_empty():
			if float(f.get("ecology_commit_time",0.0))>0.0: commit+=1
			if float(f.get("momentum_charge",0.0))>0.0 or float(f.get("reactive_force",0.0))>0.0: loaded+=1
			if float(f.get("damper_time",0.0))>0.0: buckled+=1
			drive_peak=maxf(drive_peak,float(f.get("orbit_charge",0.0)))
	for trace: Dictionary in b.powers.traces:
		route_owners[int(trace.owner_entity_id)]=true
		trace_points=maxi(trace_points,trace.get("points",[]).size())
		circuit_points=maxi(circuit_points,trace.get("circuit_points",[]).size())
	for state: Dictionary in b.powers._states.values():
		for key: String in ["trace_hits","redline_targets","clutch_targets"]:target_entries+=state.get(key,{}).size()
	var e: Object = ecology(b)
	if e!=null:
		active_ecology=e.states.size()
		for state: Dictionary in e.states.values():owner_fields=maxi(owner_fields,state.size())
	var history_points: int = 0
	for history: Array in Identity.motion_history.values():history_points=maxi(history_points,history.size())
	var result: Dictionary = {"active_full_enemies":active,"powered_enemies":powered,"fighters":b.fighters.size(),
		"live_routes":b.powers.traces.size(),"route_owners":route_owners.size(),"trace_points":trace_points,"circuit_points":circuit_points,
		"particles":b._particles.size(),"fx":b._power_fx.size(),"power_events":b.powers.events.size(),"power_states":b.powers._states.size(),
		"roster_states":b.roster.states.size(),"defence_states":b.powers.defence.states.size(),"ecology_states":active_ecology,
		"target_entries":target_entries,"pilot_states":pilot_states,"pilot_history":pilot_history,"ecology_fields_per_owner":owner_fields,"committed_owners":commit,"loaded_owners":loaded,"buckled_owners":buckled,"drive_peak":drive_peak,
		"recovery_events":b.continuous.economy.recovery_events.size(),"enemy_buckets":b.continuous.economy.enemy_buckets.size(),
		"motion_owners":Identity.motion_history.size(),"motion_points":history_points,"static_memory_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))}
	check(result.live_routes<=72 and trace_points<=16 and circuit_points<=224,"Paid route geometry remains bounded")
	check(result.particles<=120 and result.fx<=32 and result.power_events<=256 and result.recovery_events<=128,"Effects/events/recovery history remains bounded")
	check(result.power_states<=b.fighters.size() and result.ecology_states<=b.fighters.size() and result.roster_states<=b.fighters.size()+1,"Owner state remains bounded by admitted bodies, with one-tick retirement allowance")
	check(result.motion_owners<=16 and result.motion_points<=10,"Rendered native movement history remains bounded")
	check(pilot_history<=12 and owner_fields<=20,"Pilot history and fixed ecology owner fields remain bounded")
	check(target_entries<=maxi(1,b.fighters.size()*b.fighters.size()*3),"Per-owner target maps remain bounded")
	for f: Dictionary in b.fighters:check(is_finite(float(f.rpm)) and Vector2(f.pos).is_finite() and Vector2(f.vel).is_finite(),"Finite physical state")
	return result
func play(count: int, seed_value: int) -> Dictionary:
	var clock: float = 280.0 if count==3 else (640.0 if count==4 else 880.0)
	var b: Node2D = fixture(count,clock,seed_value); var initial: Array[Dictionary] = physical(b)
	var cpu: Array[float] = []; var advancing: Array[float] = []; var dense_cpu: Array[float] = []; var walls: Array[float] = []
	var trace: Array[Dictionary] = []; var peaks: Dictionary = {}; var dense: int = 0; var dense_advancing: int = 0; var joint_routes: int = 0; var multi: int = 0; var state_frames: int = 0
	var commit_frames: int = 0; var loaded_frames: int = 0; var buckled_frames: int = 0; var advanced: int = 0; var held: int = 0; var frames: int = 0
	var last: int = Time.get_ticks_usec()
	for tick: int in range(horizon):
		if b.battle_status!="battle":break
		var input: Dictionary = control(b,tick); var before: float = b.elapsed
		var began: int = Time.get_ticks_usec(); b.test_step(Physics.FIXED_DT,input.direction,input.burst,input.brake)
		var ms: float = float(Time.get_ticks_usec()-began)/1000.0; frames+=1
		var advances: bool = b.elapsed>before
		if advances:advanced+=1
		else:held+=1
		check(clocks_match(b),"All live-combat clocks remain aligned, including real impact holds")
		var o: Dictionary = observe(b)
		if o.active_full_enemies==count:
			dense+=1
			if advances:dense_advancing+=1
			if o.route_owners>=2:joint_routes+=1
		if o.route_owners>=2:multi+=1
		if o.ecology_states>=2:state_frames+=1
		if o.committed_owners>0:commit_frames+=1
		if o.loaded_owners>0:loaded_frames+=1
		if o.buckled_owners>0:buckled_frames+=1
		if tick>=60:
			cpu.append(ms)
			if advances:advancing.append(ms)
			if o.active_full_enemies==count:dense_cpu.append(ms)
		for key: String in o:
			if o[key] is int or o[key] is float:peaks[key]=maxf(float(peaks.get(key,0.0)),float(o[key]))
		if tick%12==0:
			trace.append({"tick":tick,"elapsed":b.elapsed,"control":input,"physical":physical(b),"observation":o,
				"powers":b.powers.counters.duplicate(true),"roster":b.roster.counters.duplicate(true),"ecology":{} if ecology(b)==null else ecology(b).counters.duplicate(true)})
		if rendered:
			if tick==59:b.draw_samples.clear()
			b.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
			if tick>=60:walls.append(float(Time.get_ticks_usec()-last)/1000.0)
			last=Time.get_ticks_usec()
		elif tick%120==0:await process_frame
	check(dense_advancing>=120,"At least two advancing fixed seconds at requested full-top density")
	var result: Dictionary = {"seed":seed_value,"full_enemies_fixture":count,"initial_clock_fixture":clock,"initial":initial,"final":physical(b),
		"frames":frames,"advancing_frames":advanced,"impact_hold_frames":held,"requested_density_frames":dense,"requested_density_advancing_frames":dense_advancing,"density_with_multiple_routes_frames":joint_routes,"multiple_paid_route_frames":multi,
		"multiple_ecology_owner_frames":state_frames,"committed_owner_frames":commit_frames,"loaded_owner_frames":loaded_frames,"buckled_owner_frames":buckled_frames,
		"samples_ms":{"physics":cpu,"physics_advancing":advancing,"requested_density_physics":dense_cpu,"draw_submission":b.draw_samples.duplicate(),"frame_wall":walls},
		"physics_ms":stats(cpu),"draw_submission_ms":stats(b.draw_samples),"frame_wall_ms":stats(walls),"peaks":peaks,"trace":trace,"status":b.battle_status,
		"final_powers":b.powers.counters.duplicate(true),"final_roster":b.roster.counters.duplicate(true),"final_ecology":{} if ecology(b)==null else ecology(b).counters.duplicate(true),"clocks_synchronized":true}
	b.free();await process_frame
	return result
func cleanup_contract() -> Dictionary:
	var b: Node2D = fixture(1,280.0,421)
	# Separate untimed retention contract: each new ordinary admission starts
	# just inside the open gate with declared outward physical velocity. Its
	# actual solver outcome/corpse retirement is never forced or overwritten.
	b.player_entity().pos=Vector2.ZERO;b.player_entity().vel=Vector2.ZERO
	ownership(b.player_entity(),{},["impact_sink"])
	b.powers.setup(b);b.roster.setup(b);epoch(b,280.0)
	var rows: Array[Dictionary] = []; var peaks: Dictionary = {}
	for serial: int in range(1,65):
		var f: Dictionary
		if serial==1:f=b.entity(2)
		else:
			var event: Dictionary=event_for("hunter",serial,b.elapsed)
			b.continuous.director.active[serial]={"time":b.elapsed,"kind":event.kind}
			b.continuous._admit(event,Vector2(131,-131));f=b.entity(int(b.continuous.next_entity_id)-1)
		var branches: Dictionary = {}
		for family: String in NEW_PAIRS:branches[family]=NEW_PAIRS[family][serial%2]
		ownership(f,branches,["afterimage","impact_sink","gyro_lock"])
		f.pos=Vector2(131,-131);f.vel=Vector2(260,-260);f.ai_clock=0.0
		var id: int = int(f.entity_id); var outcome: String = ""; var ticks: int = 0
		for tick: int in range(240):
			if b.entity(id).is_empty():break
			b.test_step(Physics.FIXED_DT,Vector2.ZERO,false,false);ticks+=1
			if not b.entity(id).is_empty() and not str(b.entity(id).outcome).is_empty():outcome=str(b.entity(id).outcome)
			var o: Dictionary=observe(b)
			for key: String in ["fighters","power_states","roster_states","defence_states","ecology_states","power_events","fx","particles","enemy_buckets","target_entries"]:peaks[key]=maxi(int(peaks.get(key,0)),int(o[key]))
		check(outcome=="ring_out" and b.entity(id).is_empty(),"Near-gate actual solver ring-out retires its actor")
		# State modules prune on the next ordinary advancing tick.
		b.test_step(Physics.FIXED_DT,Vector2.ZERO,false,false)
		check(not b.powers._states.has(id) and not b.roster.states.has(id) and not b.powers.defence.states.has(id),"Removed owner's accepted power/roster/defence state is pruned")
		check(ecology(b)==null or not ecology(b).states.has(id),"Removed owner's new ecology state is pruned")
		check(not b.continuous.economy.enemy_buckets.has(id) and not b._ai_rngs.has(id),"Removed owner's gain bucket and AI stream are retired")
		rows.append({"serial":serial,"id":id,"outcome":outcome,"ordinary_ticks":ticks,"after":observe(b)})
	check(b.battle_status=="battle" and rows.size()==64,"Sixty-four real admissions/retirements share one still-live host")
	var result: Dictionary={"admissions":64,"rows":rows,"peaks":peaks,"final":observe(b),"timed_performance":false,
		"scope":"Separate untimed near-gate admission/initial-velocity fixture. Real pilots, ordinary fixed ticks, natural solver ring-outs and normal continuous cleanup; no outcomes/resources/procs injected. No sustained-combat or leak-free claim."}
	b.free();return result
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
		if arg.begins_with("--ticks="):horizon=int(arg.trim_prefix("--ticks="))
		if arg.begins_with("--seed="):seeds.assign([int(arg.trim_prefix("--seed="))])
		if arg=="--rendered":rendered=true
		if arg=="--cleanup-only":cleanup_only=true
	if not output.is_absolute_path() or FileAccess.file_exists(output):push_error("Fresh external --report required");quit(2);return
	root.min_size=Vector2i(640,360);root.size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	Engine.max_fps=0
	if rendered:DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_title("Spinning Metal — ECOLOGY PERFORMANCE ISOLATED QA")
	var cases: Array[Dictionary] = []; var cleanup: Dictionary = {}
	if cleanup_only:cleanup=cleanup_contract()
	else:
		for seed_value: int in seeds:
			for count: int in [3,4,5,6]:cases.append(await play(count,seed_value))
	var result: Dictionary={"label":label,"rendered":rendered,"seeds":seeds,"ticks_per_case":horizon,"processor":OS.get_processor_name(),
		"gpu":RenderingServer.get_video_adapter_name(),"cases":cases,"cleanup":cleanup,"checks":checks,"failures":failures,"main_created":false,"collection_opened":false,
		"scope":"Declared initial4/5/6 TOTAL full tops (3/4/5 enemies plus player), with7-total stress (6 enemies plus player), legal invested ownership/builds/poses/velocities and synchronized280/640/880 clock epochs. Accepted baseline uses selected four families at II; current uses legal III siblings. Real role pilots untouched; player policy reads present position only. Stores, DRIVE, commitments, collisions and procs must arise from ordinary fixed ticks; no ongoing holds/corrections. Extra Director admissions suspended for matched load, but deaths/retirement continue. All eight new branches are distributed across even4-total ownership fixtures; zero actual proc coverage remains visible. Standalone native640x360 Battle excludes Main/HUD/music. CPU draw submission excludes GPU completion; wall frame includes harness/read-only monitors. Not natural survival, physical Android, guaranteed FPS or long-duration leak evidence."}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(portable(result),"\t"));file.close()
	print("ECOLOGY_PERFORMANCE_%s checks=%d cases=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,cases.size()])
	quit(0 if failures.is_empty() else 1)
