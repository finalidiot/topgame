extends SceneTree
## Declared initial ownership/pose fixtures; all subsequent movement, contacts,
## RPM, power state, admissions and outcomes belong to the canonical Battle.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Save = preload("res://scripts/collection_save.gd")
class StudyBattle:
	extends "res://scripts/battle.gd"
	var accepted_player_bursts: int=0
	var player_burst_procs: Dictionary={}
	func _attempt_burst(fighter: Dictionary,direction: Vector2) -> void:
		var owned: bool=int(fighter.entity_id)==1
		var before: float=float(continuous.economy.losses.burst) if owned else 0
		var counts: Dictionary={}
		if owned:
			counts={"power":powers.counters.duplicate(),"defence":powers.defence.counters.duplicate(),"roster":roster.counters.duplicate()}
		super._attempt_burst(fighter,direction) # Exactly one canonical hook; observation only.
		if not owned or float(continuous.economy.losses.burst)<=before:return
		accepted_player_bursts+=1
		var after: Dictionary={"power":powers.counters,"defence":powers.defence.counters,"roster":roster.counters}
		for family: String in after:
			for kind: String in after[family]:
				var delta: int=int(after[family][kind])-int(counts[family].get(kind,0))
				if delta>0:player_burst_procs[family+"/"+kind]=int(player_burst_procs.get(family+"/"+kind,0))+delta
var output: String = ""
var request: String = ""
var profile_prefix: String = ""
var checks: int = 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var profiles: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func project_input(world: Vector2) -> Vector2:
	return Vector2(world.x-world.y,(world.x+world.y)*.5).normalized()*minf(1.0,world.length())
func nearest(b: Node2D) -> Dictionary:
	var result: Dictionary = {}
	var distance: float = INF
	var p: Dictionary = b.player_entity()
	for f: Dictionary in b.fighters:
		if f.team_id==p.team_id or not str(f.outcome).is_empty(): continue
		var current: float = Vector2(f.pos).distance_to(p.pos)
		if current<distance: result=f; distance=current
	return result
func literal(policy: String, tick: int) -> Dictionary:
	var t: float = tick/60.0
	var world: Vector2 = Vector2.ZERO
	var brake: bool = false
	var burst: bool = false
	var mode: String = policy
	match policy:
		"response":
			if t>=.5 and t<2.5: world=Vector2.RIGHT
			elif t>=2.5 and t<3.0: world=Vector2.RIGHT*.2; brake=true
			elif t>=3.0 and t<4.5: world=Vector2.UP
			elif t>=4.5: world=Vector2.LEFT
		"cruise": world=Vector2.RIGHT.rotated(t*1.4)
		"cruise_uncapped": world=Vector2.RIGHT.rotated(t*2.4)
		"turn":
			if t>=.5 and t<1.5:world=Vector2.RIGHT
			elif t>=1.5 and t<3:world=Vector2.UP
			elif t>=3 and t<4.5:world=Vector2.LEFT
			elif t>=4.5:world=Vector2.DOWN
		"release":
			if t<3: world=Vector2.RIGHT*.2; brake=t>=2
			elif t<6: world=Vector2.RIGHT
			else: world=Vector2.UP
		"edge":
			world=Vector2(-1,1).normalized(); brake=t<.2; burst=tick==15
		"edge_stop":
			world=Vector2(-1,1).normalized() if t<1.2 else Vector2.ZERO
			brake=t<.2 or (t>=1.2 and t<2.2);burst=tick==15
		"shared_course":
			var phase: float=fmod(t,18)
			if phase<4: world=Vector2.RIGHT*.2; brake=phase>=3.4
			elif phase<8: world=Vector2.RIGHT.rotated((phase-4)*.45)*.8; burst=posmod(tick,1080)==255
			elif phase<12: world=Vector2.LEFT*.85
			elif phase<15: world=Vector2.DOWN.rotated((phase-12)*.8)*.7
			else: world=Vector2.UP*.4; brake=phase>=17.5
		"zero_input": pass
		"centre_hold": world=Vector2.RIGHT.rotated(t*.3)*.2; brake=fmod(t,8)>=7.6
	return {"direction":project_input(world),"world":world,"burst":burst,"brake":brake,"mode":mode}
func policy_input(b: Node2D, policy: String, tick: int, state: Dictionary) -> Dictionary:
	if policy in ["response","cruise","cruise_uncapped","turn","release","edge","edge_stop","shared_course","zero_input","centre_hold"]: return literal(policy,tick)
	if tick<int(state.get("next_sample",0)):
		var held: Dictionary=state.controls.duplicate()
		held.burst=false # A sampled press is one edge; held input is not15 presses.
		return held
	state.next_sample=tick+15
	var p: Dictionary=b.player_entity()
	var position: Vector2=p.pos
	var velocity: Vector2=p.vel
	var radius: float=position.length()
	var target: Dictionary=nearest(b)
	var heading: Vector2=(Vector2(target.pos)-position).normalized() if not target.is_empty() else Vector2.RIGHT
	var distance: float=position.distance_to(target.pos) if not target.is_empty() else INF
	var incoming: float=maxf(0,Vector2(target.vel).dot(-heading)) if not target.is_empty() else 0
	var world: Vector2=Vector2.ZERO
	var brake: bool=false
	var burst: bool=false
	var mode: String="rest"
	if policy=="minimal":
		if radius>8 or fmod(tick/60.0,2)<.75:
			world=(-position*.9-velocity*.35).normalized()*.24
			if world.length()<.01: world=Vector2.RIGHT.rotated(tick/200.0)*.24
			mode="small_correction"
	elif policy in ["pursuit","aggressive","edge_recovery"]:
		world=(Vector2(target.pos)+Vector2(target.vel)*.12-position).normalized() if not target.is_empty() else (-position).normalized()
		mode="pursuit"
		if radius>135: world=(-position-velocity*.35).normalized(); mode="edge_recovery"
		burst=policy!="pursuit" and distance<100 and b.elapsed>=float(state.get("burst_ready",0)) and float(p.cooldown)<=0
		if burst: state.burst_ready=b.elapsed+4.8
	else:
		var recovering: String=str(state.get("recovery","none"))
		if recovering=="none" and (float(p.get("anchor_stress",0))>.38 or (float(p.get("anchor_recovery_remaining",1))<.02 and float(p.rpm)<.78)):
			recovering="outward"; state.route_heading=position.normalized() if radius>8 else Vector2.RIGHT
		if recovering!="none" and float(p.get("anchor_stress",0))<=.30 and float(p.get("anchor_recovery_remaining",0))>=.19: recovering="return"
		if recovering=="return" and radius<=28: recovering="none"
		if recovering=="outward":
			world=Vector2(state.route_heading)*.7; mode="deliberate_release"
			if radius>=95: recovering="rotate"
		elif recovering=="rotate":
			world=(position.orthogonal().normalized()-position.normalized()*clampf((radius-98)/24.0,-.6,.6)).normalized()*.7; mode="outside_rearm"
		elif recovering=="return": world=(-position*.9-velocity*.35).normalized()*.55; mode="return_to_centre"
		else:
			world=(-position*.9-velocity*.35).normalized()*.24; mode="centre_correction"
			if world.length()<.01: world=Vector2.RIGHT*.2
			if radius>130: world=(-position-velocity*.35).normalized()*.85; mode="edge_recovery"
			if b.elapsed<float(state.get("brace_until",-1)): brake=true; mode="paid_brace"
			elif distance<65 and incoming>45 and velocity.length()<120 and b.elapsed>=float(state.get("brace_ready",0)):
				state.brace_until=b.elapsed+.5; state.brace_ready=b.elapsed+6; brake=true; mode="paid_brace"
			elif float(p.get("sink_charge",0))>=15 and velocity.length()<120 and b.elapsed>=float(state.get("brace_ready",0)):
				state.brace_until=b.elapsed+.25; state.brace_ready=b.elapsed+6; brake=true; mode="stored_force_vent"
			elif float(p.get("exchange_charge",0))>.2: world=heading*.65; mode="aimed_release"
			var stored: bool=float(p.get("stored_force",0))>=12 or float(p.get("momentum_charge",0))>=15
			burst=stored and distance<75 and not brake and b.elapsed>=float(state.get("burst_ready",0)) and float(p.cooldown)<=0
			if burst: world=heading*.7; state.burst_ready=b.elapsed+8; mode="stored_counter"
		state.recovery=recovering
	state.controls={"direction":project_input(world),"world":world,"burst":burst,"brake":brake,"mode":mode}
	return state.controls
func power_state(p: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key: String in ["anchor_charge","anchor_strength","anchor_stress","anchor_maturity","anchor_recovery_remaining","anchor_rearm_progress","stored_force","sink_charge","gyro_charge","exchange_charge","momentum_charge","orbit_charge","guard_time"]: result[key]=p.get(key,0)
	return result
func make_battle(c: Dictionary) -> Node2D:
	var b: Node2D=StudyBattle.new(); root.add_child(b); b.set_physics_process(false)
	var d: Dictionary=Encounters.for_run_event(1,int(c.seed))
	d.starter_id=c.starter; d.player_power_ids=c.ranks.keys(); d.player_power_ranks=c.ranks.duplicate(true); d.player_power_mutations=c.mutations.duplicate(true)
	b.begin_run(Starters.build_for(c.starter),d,int(c.seed))
	b.continuous.progression_level=maxi(1,int(c.investments)); b.continuous.reward_fixture=true
	b.battle_status="battle"
	var p: Dictionary=b.player_entity()
	p.pos=Vector2(112,-112) if c.policy in ["edge","edge_stop"] else Vector2.ZERO
	p.vel=Vector2(45,-45) if c.policy in ["edge","edge_stop"] else Vector2.ZERO
	b.entity(2).vel=b.entity(2).launch_velocity
	if float(c.acceleration)>0: p.handling.acceleration=float(c.acceleration)
	if c.lane=="solo":
		# Initial no-opponent/no-admission context only. Run economy and powers
		# remain actual; this lane cannot prove combat/Director balance.
		b.fighters.remove_at(1); b.continuous.events.clear(); b.continuous.pending.clear()
		b.continuous.director.active.clear(); b.continuous.director.next_decision=1.0e12
	return b
func observe(c: Dictionary) -> Dictionary:
	var b: Node2D=make_battle(c); var p: Dictionary=b.player_entity()
	var row: Dictionary=c.duplicate(true)
	row.merge({"initial_build":p.build.duplicate(true),"stats":p.stats.duplicate(true),"physical":p.part_physics.duplicate(true),"actual_handling":p.handling.duplicate(true),"base_mass":p.mass,"initial_rpm":p.rpm,"initial_pose":[p.pos.x,p.pos.y,p.vel.x,p.vel.y],"trace":[],"input_samples":[],"input_prefix_hashes":[],"contacts":[],"full_impacts":[],"contacts_count":0,"heavy_count":0,"centre_seconds":0.0,"input_seconds":0.0,"brake_seconds":0.0,"idle_seconds":0.0,"active_control_seconds":0.0,"accepted_burst_seconds":0.0,"player_semantic_procs":{},"burst_requests":0,"input_changes":0,"angular_input_changes":0,"movement_distance":0.0,"speed_integral":0.0,"wobble_integral":0.0,"radius_integral":0.0,"heading_error_integral":0.0,"heading_error_seconds":0.0,"anchor_hold_seconds":0.0,"anchor_stress_integral":0.0,"configured_speed_cap_full_reserve":(110+float(p.stats.speed)*13)*float(p.handling.speed),"configured_cap_samples":0,"steady_speeds":[],"cruise_window_boundary_free":true,"control_modes":{},"first_response_5":null,"first_response_50":null,"release_response_35":null,"turn_to_up_seconds":null,"edge_centre_seconds":null,"peak_speed":0.0,"peak_radius":Vector2(p.pos).length(),"peak_gate_coordinate":absf(Vector2(p.pos).x-Vector2(p.pos).y),"peak_full":0,"peak_small":0,"finite":true})
	b.contact_accepted.connect(func(a: int,z: int)->void:
		if a!=1 and z!=1:return
		row.contacts_count+=1
		if row.contacts.size()<256: row.contacts.append({"time":b.elapsed,"other":z if a==1 else a,"radius":Vector2(p.pos).length()}))
	b.full_top_impact_accepted.connect(func(event: Dictionary)->void:
		if int(event.first_entity_id)!=1 and int(event.second_entity_id)!=1:return
		if float(event.severity)>=.75:row.heavy_count+=1
		if row.full_impacts.size()<256:row.full_impacts.append(event.duplicate(true)))
	var state: Dictionary={}; var tick: int=0; var input_text: String=""; var previous: Vector2=Vector2.ZERO
	var event_overflow: bool=false
	var clocks_consistent: bool=true;var fixed_steps_consistent: bool=true
	row["unbraked_turn_to_up_seconds"]=null
	row["hostile_outcomes"]=[];var observed_outcomes: Dictionary={}
	var next_trace: float=0; var start_wall_loss: float=0; var last_world: Vector2=Vector2.ZERO
	while b.battle_status=="battle" and b.elapsed<float(c.horizon) and tick<int(float(c.horizon)*120+120):
		var controls: Dictionary=policy_input(b,str(c.policy),tick,state)
		var command: Vector2=controls.direction; var world: Vector2=controls.world
		input_text+=PackedVector2Array([command]).to_byte_array().hex_encode()+"%d%d;"%[int(controls.burst),int(controls.brake)]
		if tick%60==0:row.input_prefix_hashes.append({"ticks":tick+1,"sha256":input_text.sha256_text()})
		if command.distance_to(previous)>.08:row.input_changes+=1
		if last_world.length()>.1 and world.length()>.1 and absf(last_world.angle_to(world))>.15:row.angular_input_changes+=1
		previous=command;last_world=world
		if controls.burst:row.burst_requests+=1
		var before: float=b.elapsed;var position: Vector2=p.pos
		var event_count_before: int=0
		for count: int in b.powers.counters.values():event_count_before+=count
		b.test_step(Battle.FIXED_DT,command,controls.burst,controls.brake)
		var event_count_after: int=0
		for count: int in b.powers.counters.values():event_count_after+=count
		var added: int=event_count_after-event_count_before
		event_overflow=event_overflow or added>b.powers.events.size()
		for event: Dictionary in b.powers.events.slice(maxi(0,b.powers.events.size()-added)):
			if int(event.owner)==1:row.player_semantic_procs[event.kind]=int(row.player_semantic_procs.get(event.kind,0))+1
		var dt: float=b.elapsed-before; var speed: float=Vector2(p.vel).length();var radius: float=Vector2(p.pos).length()
		fixed_steps_consistent=fixed_steps_consistent and (absf(dt)<.000001 or absf(dt-Battle.FIXED_DT)<.000001)
		clocks_consistent=clocks_consistent and absf(b.powers.time-b.elapsed)<.000001 and absf(b.powers.defence.time-b.elapsed)<.000001 and absf(b.roster.time-b.elapsed)<.000001
		row.finite=row.finite and Vector2(p.pos).is_finite() and Vector2(p.vel).is_finite() and is_finite(float(p.rpm))
		row.movement_distance+=position.distance_to(p.pos);row.speed_integral+=speed*dt;row.radius_integral+=radius*dt;row.wobble_integral+=float(p.wobble)*dt
		row.anchor_stress_integral+=float(p.get("anchor_stress",0))*dt
		if radius<=58:row.centre_seconds+=dt
		if bool(p.get("anchor_central_hold",false)):row.anchor_hold_seconds+=dt
		if command.length()>.01:row.input_seconds+=dt
		if controls.brake:row.brake_seconds+=dt
		if command.length()<=.01 and not controls.brake and not controls.burst:row.idle_seconds+=dt
		else:row.active_control_seconds+=dt
		if float(p.burst_time)>0:row.accepted_burst_seconds+=dt
		row.control_modes[controls.mode]=float(row.control_modes.get(controls.mode,0))+dt
		row.peak_speed=maxf(row.peak_speed,speed);row.peak_radius=maxf(row.peak_radius,radius);row.peak_gate_coordinate=maxf(row.peak_gate_coordinate,absf(Vector2(p.pos).x-Vector2(p.pos).y))
		var census: Dictionary=b.continuous.census();row.peak_full=maxi(row.peak_full,int(census.full));row.peak_small=maxi(row.peak_small,int(census.small))
		for f: Dictionary in b.fighters:
			if f.team_id!="hostile" or str(f.outcome).is_empty() or observed_outcomes.has(int(f.entity_id)):continue
			observed_outcomes[int(f.entity_id)]=true
			row.hostile_outcomes.append({"entity_id":f.entity_id,"kind":f.get("enemy_kind",""),"role":f.get("role",""),"outcome":f.outcome,"observed_time":b.elapsed,"actual_power_cause":b.powers.cause_for(f).duplicate(true)})
		if world.length()>.1 and speed>5:row.heading_error_integral+=absf(world.angle_to(p.vel))*dt;row.heading_error_seconds+=dt
		var wall_t: float=tick/60.0
		if c.policy=="response" and wall_t>=.5:
			if row.first_response_5==null and speed>=5:row.first_response_5=wall_t+.016666667-.5
			if row.first_response_50==null and speed>=50:row.first_response_50=wall_t+.016666667-.5
			if wall_t>=3 and wall_t<4.5 and row.turn_to_up_seconds==null and speed>=5 and Vector2(p.vel).normalized().dot(Vector2.UP)>=.8:row.turn_to_up_seconds=wall_t+.016666667-3
		if c.policy=="release" and wall_t>=3 and row.release_response_35==null and speed>=35:row.release_response_35=wall_t+.016666667-3
		if c.policy=="turn" and wall_t>=1.5 and wall_t<3 and row.unbraked_turn_to_up_seconds==null and speed>=5 and Vector2(p.vel).normalized().dot(Vector2.UP)>=.8:row.unbraked_turn_to_up_seconds=wall_t+.016666667-1.5
		if c.policy in ["edge","edge_stop"] and row.edge_centre_seconds==null and radius<=58:row.edge_centre_seconds=b.elapsed
		if c.policy in ["cruise","cruise_uncapped"] and wall_t>=8:
			row.steady_speeds.append(speed)
			if tick==480:start_wall_loss=float(b.continuous.economy.losses.walls)
			if float(b.continuous.economy.losses.walls)>start_wall_loss+.000001:row.cruise_window_boundary_free=false
			if speed>=float(row.configured_speed_cap_full_reserve)*.98:row.configured_cap_samples+=1
		if b.elapsed>=next_trace or b.battle_status=="finished":
			row.trace.append({"simulation_time":b.elapsed,"fixed_step_calls":tick+1,"rpm":p.rpm,"wobble":p.wobble,"position":[p.pos.x,p.pos.y],"velocity":[p.vel.x,p.vel.y],"speed":speed,"radius":radius,"powers":power_state(p),"census":census,"mode":controls.mode,"economy":b.continuous.economy.snapshot(),"idle_seconds":row.idle_seconds,"burst_requests":row.burst_requests,"accepted_player_bursts":b.accepted_player_bursts})
			row.input_samples.append({"tick":tick,"screen_direction":[command.x,command.y],"burst":controls.burst,"brake":controls.brake,"mode":controls.mode});next_trace+=.5
		tick+=1
	var economy: Dictionary=b.continuous.economy.snapshot();var lost: float=0;var gained: float=0
	for value: float in economy.losses.values():lost+=value
	for value: float in economy.gains.values():gained+=value
	var duration: float=b.elapsed;var closure: float=absf(float(row.initial_rpm)-lost+gained-float(p.rpm))
	check(row.finite,"Finite actual physical states");check(closure<.000001,"Actual source RPM ledger closes")
	check(fixed_steps_consistent,"Every actual advancing step is60Hz; impact holds advance no physical clock")
	check(clocks_consistent,"Power/defence/roster clocks match actual battle throughout")
	check(not event_overflow,"Owner semantic event telemetry never drops per-tick additions")
	check(absf(float(row.idle_seconds)+float(row.active_control_seconds)-duration)<.000001,"True input-idle and active-control seconds partition advancing time")
	check(b.accepted_player_bursts==roundi(float(economy.losses.burst)/.013),"Observed accepted player Burst hooks match canonical source spend")
	check(p.powers.size()<=7,"Legal family cap preserved");check(float(p.rpm)>=0 and float(p.rpm)<=b.powers.rpm_cap(p)+.000001,"Actual reserve remains bounded")
	if c.policy=="zero_input":check(float(economy.gains.combat_reclamation)+float(economy.gains.elimination)+float(economy.gains.elite)+float(economy.gains.boss)==0,"No fabricated AFK contact or elimination income")
	var defeated: Dictionary={"ring_out":0,"spin_out":0,"impact":0}
	for f: Dictionary in b.fighters:
		if f.team_id=="hostile" and str(f.outcome) in defeated:defeated[f.outcome]+=1
	var steady: float=0
	for value: float in row.steady_speeds:steady+=value
	row.merge({"seconds":duration,"fixed_step_calls":tick,"input_sha256":input_text.sha256_text(),"reason":b.last_result.get("reason","observation_horizon"),"ended_naturally":b.battle_status=="finished","right_censored":b.battle_status!="finished","final_rpm":p.rpm,"final_wobble":p.wobble,"final_radius":Vector2(p.pos).length(),"mean_speed":float(row.speed_integral)/maxf(duration,.000001),"mean_radius":float(row.radius_integral)/maxf(duration,.000001),"mean_wobble":float(row.wobble_integral)/maxf(duration,.000001),"mean_heading_error_radians":float(row.heading_error_integral)/maxf(float(row.heading_error_seconds),.000001),"centre_fraction":float(row.centre_seconds)/maxf(duration,.000001),"active_input_fraction":float(row.input_seconds)/maxf(duration,.000001),"mean_anchor_stress":float(row.anchor_stress_integral)/maxf(duration,.000001),"steady_cruising_speed":steady/maxi(1,row.steady_speeds.size()),"steady_cruise_samples":row.steady_speeds.size(),"configured_cap_sample_fraction":float(row.configured_cap_samples)/maxi(1,row.steady_speeds.size()),"economy":economy,"ledger_closure_error":closure,"power_procs":b.powers.counters.duplicate(),"defence_procs":b.powers.defence.counters.duplicate(),"roster_procs":b.roster.counters.duplicate(),"final_defence":b.powers.defence.diagnostics(p),"enemy_defeats_in_final_roster":defeated,"rivals_defeated":b.continuous.rivals_defeated,"small_defeated":b.continuous.small_enemies_defeated,"player_outcome":p.outcome,"director_history":b.continuous.director.history.duplicate(true),"final_power_state":power_state(p)})
	row.erase("steady_speeds")
	if int(row.steady_cruise_samples)==0:row.steady_cruising_speed=null
	row["uncapped_steady_window"]=int(row.steady_cruise_samples)>0 and row.cruise_window_boundary_free and int(row.configured_cap_samples)==0
	row["actual_player_burst_activations"]=b.accepted_player_bursts
	row["player_burst_procs"]=b.player_burst_procs.duplicate()
	row["input_hash_encoding"]="Exact Vector2 packed-float bytes plus discrete Burst/Brake flags for every fixed-step call"
	row["idle_definition"]="No requested steering (length<=.01), Brake or Burst edge, integrated over actual advancing physics time; accepted ongoing Burst activity is separately measured."
	row["global_proc_scope"]="power_procs/defence_procs/roster_procs include all owners. player_semantic_procs uses canonical owner events; player_burst_procs captures synchronous deltas inside the actual player Burst hook."
	row["final_actor"]={"simulation_time":duration,"fixed_step_calls":tick,"rpm":p.rpm,"wobble":p.wobble,"position":[p.pos.x,p.pos.y],"velocity":[p.vel.x,p.vel.y],"powers":power_state(p),"economy":economy}
	row["hostile_ringouts_observed"]=row.hostile_outcomes.filter(func(event: Dictionary)->bool:return event.outcome=="ring_out").size()
	row["outcome_scope"]="All observed hostile outcomes, including natural expiry; not attributed player kills. Final-roster counts are separate and may omit retired corpses."
	print("BASTION_FEEL case=%s lane=%s acceleration=%.3f seconds=%.2f reason=%s speed=%.2f rpm=%.4f contacts=%d"%[c.case_id,c.lane,float(p.handling.acceleration),duration,row.reason,row.mean_speed,p.rpm,row.contacts_count])
	b.free();return row
func write_report() -> void:
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Cannot write fresh study report");quit(2);return
	file.store_string(JSON.stringify({"schema":"003a2-bastion-feel-observation-v3-telemetry","scope":"Declared legal initial ownership/pose plus optional initial acceleration-only experiment. Solo initializes no opponents/admissions but preserves canonical Run economy/power/motion hooks; it measures handling, not combat balance. Natural lane retains actual adaptive Director/enemies and never changes live actors, forces, RPM, damage or power stores. Literal inputs use fixed-step-call time; public-state policies may diverge between variants. Natural death censors observations honestly. Isolated collection ownership is saved once outside the battle; no Run payout is settled.","checks":checks,"failures":failures,"request":request,"profiles":profiles,"samples":samples},"\t"));file.close()
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
		if arg.begins_with("--request="):request=arg.trim_prefix("--request=")
		if arg.begins_with("--profile-prefix="):profile_prefix=arg.trim_prefix("--profile-prefix=")
	if not output.is_absolute_path() or FileAccess.file_exists(output) or not output.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/"):push_error("Fresh external003A.2 report required");quit(2);return
	if not request.is_absolute_path() or not profile_prefix.is_absolute_path() or not profile_prefix.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/temp/"):push_error("Explicit request and isolated profile prefix required");quit(2);return
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string(request))
	if not config is Dictionary or config.get("cases",[]).is_empty():push_error("Declared cases required");quit(2);return
	for c: Dictionary in config.cases:
		for key: String in ["starter","package","policy","ranks","mutations","acceleration","seed","lane","horizon","investments","case_id"]:
			if not c.has(key):push_error("Incomplete declared case: "+key);quit(2);return
		if not profiles.has(c.starter):
			var path: String=profile_prefix+"_"+c.starter+".json"
			if FileAccess.file_exists(path):push_error("Preserve existing QA collection");quit(2);return
			var save: RefCounted=Save.new(path);var initialized: Dictionary=save.initialize_starter(c.starter)
			check(bool(initialized.ok),"Fresh isolated canonical starter ownership");profiles[c.starter]={"path":path,"load_status":save.load_status,"initialized":initialized.ok}
		samples.append(observe(c));write_report()
	print("BASTION_FEEL_%s checks=%d failures=%d cases=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),samples.size()]);quit(0 if failures.is_empty() else 1)
