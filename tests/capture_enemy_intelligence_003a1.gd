extends "res://tests/capture_impact_music_003a1.gd"
## Disclosed one-opponent Run scenarios. Every pilot decision, activation,
## contact and ring-out is produced by the ordinary fixed-tick Battle path.
const Roles = preload("res://scripts/enemy_roles.gd")
const Packages = preload("res://scripts/enemy_power_packages.gd")
const Encounters = preload("res://scripts/encounters.gd")
var actor_rows: Array[Dictionary] = []
var observed: Dictionary = {}
var dodge_at: int = -1
var first_commit: int = -1
var fixture: Dictionary = {}
var opponent: Dictionary = {}
var player_body: Dictionary = {}

func scenario(spec: Dictionary) -> Node2D:
	var b := Battle.new();root.add_child(b);b.set_process(false);b.set_physics_process(false)
	var descriptor: Dictionary=Encounters.for_run_event(1,421)
	descriptor.opponent_build=Roles.BUILDS[spec.role].duplicate(true)
	descriptor.player_power_ids=[];descriptor.player_power_ranks={};descriptor.player_power_mutations={}
	b.begin_run({"blade":"smash","ratchet":"high","bit":"flat"},descriptor,421)
	while b.battle_status!="battle":b.test_step(Battle.FIXED_DT)
	var e: Dictionary=b.entity(2);var p: Dictionary=b.player_entity()
	opponent=e;player_body=p
	var event: Dictionary={"key":spec.get("key",spec.role),"role":spec.role,"kind":spec.get("kind","rival"),"tier_at_entry":spec.get("tier",0),"name":str(spec.role).to_upper(),"serial":1,"cost":2.8}
	# Replace the opening opponent only at fixture initialization. Existing
	# handling is cleared before ordinary configure applies the selected role.
	e.mass=(3.8+float(e.stats.mass)*.56)*float(e.part_physics.mass);e.handling={}
	Roles.configure(e,event);Packages.apply(e,event)
	b.continuous.reward_fixture=true;b.continuous.director.next_decision=99999.;b.continuous.director.calm_until=99999.
	b.continuous.events[1]={"ids":[2],"swarm":false,"kind":event.kind,"key":event.key,"time":0.0}
	p.pos=spec.get("player_pos",Vector2(-4,0));e.pos=spec.get("enemy_pos",Vector2(28,0))
	p.vel=spec.get("player_velocity",Vector2.ZERO);e.vel=spec.get("enemy_velocity",Vector2.ZERO)
	p.trail=[];e.trail=[];e.ai_clock=0.0
	b.event_sfx.connect(cue);sound.grind_provider=b.grind_audio_snapshot
	observed={"states":{},"burst_starts":0,"brake_frames":0,"peak_anchor":0.0,"peak_sink":0.0,"redline_frames":0,"peak_orbit":0.0,"afterimage_frames":0,"contacts":[],"last_burst":false,"max_distance":p.pos.distance_to(e.pos),"min_distance":p.pos.distance_to(e.pos)}
	dodge_at=-1;first_commit=-1;fixture={"event":event,"player_build":p.build,"enemy_build":e.build,"package":Packages.for_event(event),"player_pos":p.pos,"enemy_pos":e.pos,"player_velocity":p.vel,"enemy_velocity":e.vel,"initial_rpm":{"player":p.rpm,"enemy":e.rpm},"admission_suspended":true,"reward_fixture":true}
	return b

func screen(world: Vector2) -> Vector2:
	return Vector2(world.x-world.y,(world.x+world.y)*.5).normalized()*minf(1.0,world.length())

func policy(b: Node2D,spec: Dictionary,tick: int) -> Dictionary:
	var p: Dictionary=player_body;var e: Dictionary=opponent
	var state: String=str(e.get("pilot",{}).get("state","assess"))
	var direction := Vector2.ZERO;var burst: bool=false;var brake: bool=false
	match str(spec.policy):
		"dodge":
			if state=="commit" and dodge_at<0:dodge_at=tick;first_commit=tick
			if dodge_at>=0 and tick-dodge_at<48:
				direction=Vector2(e.pilot.heading).orthogonal()*.95;burst=tick==dodge_at
			elif dodge_at>=0:brake=true
		"guard_hit":
			if tick<120:brake=true
			else:direction=(Vector2(e.pos)-Vector2(p.pos)).normalized()*.95;burst=tick==120
		"orbit_target":
			direction=(-Vector2(p.pos)*.025-Vector2(p.vel)*.004).limit_length(.45)
		"gate_outplay":
			if str(e.outcome).is_empty():direction=Vector2(1,-1).normalized()*.95;burst=tick==0
			else:direction=-Vector2(p.pos).normalized()*.65;brake=true
		_:direction=Vector2.ZERO
	return {"world_direction":direction,"screen_direction":screen(direction),"burst":burst,"brake":brake}

func state_caption(title: String,e: Dictionary) -> void:
	var state: String=str(e.get("pilot",{}).get("state","assess")).to_upper()
	if not str(e.outcome).is_empty():state=str(e.outcome).replace("_","-").to_upper()
	var power_names: String=", ".join(e.powers) if not e.powers.is_empty() else "NONE"
	captions(title+" / "+state,"LEGAL START FIXTURE / REAL PILOT + 60HZ PHYSICS / POWERS: "+power_names.to_upper())

func record(b: Node2D,spec: Dictionary,tick: int,control: Dictionary) -> String:
	var e: Dictionary=opponent;var p: Dictionary=player_body;var pilot: Dictionary=e.get("pilot",{})
	var state: String=str(pilot.get("state","assess"));var feature: String=""
	if not observed.states.has(state):observed.states[state]=tick;feature=str(spec.id)+"_"+state
	var bursting: bool=float(e.burst_time)>0.0
	if bursting and not observed.last_burst:
		observed.burst_starts+=1;feature=str(spec.id)+"_burst"
	observed.last_burst=bursting
	var braking: bool=str(e.outcome).is_empty() and b._ai_should_brake(e)
	if braking:observed.brake_frames+=1
	var public: Dictionary=b.powers.public_state(e)
	observed.peak_anchor=maxf(observed.peak_anchor,float(public.anchor.strength))
	observed.peak_sink=maxf(observed.peak_sink,float(public.sink.stored))
	observed.peak_orbit=maxf(observed.peak_orbit,float(public.orbit.drive))
	if public.redline.active:
		observed.redline_frames+=1
		if observed.redline_frames==1:feature=str(spec.id)+"_redline"
	for trace: Dictionary in b.powers.traces:
		if int(trace.get("owner_entity_id",0))==2:observed.afterimage_frames+=1;break
	var distance: float=Vector2(p.pos).distance_to(e.pos)
	observed.max_distance=maxf(observed.max_distance,distance);observed.min_distance=minf(observed.min_distance,distance)
	var impact: Dictionary=b.impact_feedback.snapshot()
	for event: Dictionary in impact.events:
		if event.has("collision_id") and not observed.contacts.has(event):observed.contacts.append(event.duplicate(true));feature=str(spec.id)+"_contact_%03d"%observed.contacts.size()
	if not str(e.outcome).is_empty() and not observed.has("outcome_tick"):observed.outcome_tick=tick;feature=str(spec.id)+"_outcome"
	if tick%6==0 or not feature.is_empty():
		actor_rows.append({"frame":movie_frames,"scene":spec.id,"tick":tick,"time":b.elapsed,"player_control":control,"player":{"pos":p.pos,"vel":p.vel,"rpm":p.rpm,"outcome":p.outcome},"enemy":{"pos":e.pos,"vel":e.vel,"rpm":e.rpm,"outcome":e.outcome,"burst_time":e.burst_time,"brake":braking,"pilot":Roles.decision_snapshot(e),"power_state":public},"power_audit":b.powers.counters.duplicate(true),"roster_counters":b.roster.counters.duplicate(true)})
	return feature

func play_scene(spec: Dictionary) -> void:
	var b: Node2D=scenario(spec);var e: Dictionary=b.entity(2)
	var title: String="003A.1 / "+str(spec.label)
	for tick: int in range(int(spec.frames)):
		var control: Dictionary=policy(b,spec,tick)
		b.test_step(Battle.FIXED_DT,control.screen_direction,control.burst,control.brake)
		var feature: String=record(b,spec,tick,control)
		if tick%15==0 or not feature.is_empty():state_caption(title,e)
		if tick==0 and feature.is_empty():feature=str(spec.id)+"_begin"
		if tick==int(spec.frames)-1:feature=str(spec.id)+"_end"
		await frame(b,str(spec.id),tick,feature)
	var row: Dictionary={"id":spec.id,"frames":spec.frames,"fixture":fixture.duplicate(true),"player_policy":spec.policy,"observed":observed.duplicate(true),"final_enemy_outcome":e.outcome,"final_player_outcome":b.player_entity().outcome,"final_enemy_rpm":e.rpm,"pilot":Roles.decision_snapshot(e),"power_diagnostics":b.powers.diagnostics(e),"balance_claim":false}
	row.observed.erase("last_burst");scenes.append(row)
	if spec.policy=="dodge" and (dodge_at<0 or not observed.states.has("recover") or not observed.states.has("follow_through")):failures.append(str(spec.id)+" lacked real commitment/dodge/follow-through/recovery")
	var major_hit: bool=false
	for event: Dictionary in observed.contacts:
		if event.tier in ["hard","extreme"]:major_hit=true
	if spec.policy=="guard_hit" and (not major_hit or observed.brake_frames==0 or not str(e.outcome).is_empty()):failures.append(str(spec.id)+" failed observed major guard hit survival")
	if spec.policy=="gate_outplay" and (e.outcome!="ring_out" or not str(b.player_entity().outcome).is_empty()):failures.append(str(spec.id)+" did not physically ring out while player survived")
	if mode=="powers":
		if spec.role=="hunter" and observed.redline_frames==0:failures.append(str(spec.id)+" did not activate assigned Redline")
		if spec.role=="bulwark" and (observed.peak_anchor<.25 or observed.peak_sink<=0):failures.append(str(spec.id)+" did not earn anchor/Sink state")
		if spec.role=="flanker" and observed.afterimage_frames==0:failures.append(str(spec.id)+" did not author an actual movement trace")
	sound.grind_provider=Callable();sound.set_grind_state({"active":false});b.free()

func showcase() -> void:
	if mode=="intelligence":
		await play_scene({"id":"hunter_dodge","label":"HUNTER / RUN-UP, COMMIT, PLAYER DODGE, RECOVER","role":"hunter","policy":"dodge","frames":840})
		await play_scene({"id":"bulwark_guard","label":"BULWARK / GROUND + INCOMING HIT + BRAKE","role":"bulwark","policy":"guard_hit","frames":480,"player_pos":Vector2(-100,0),"enemy_pos":Vector2(14,0)})
		await play_scene({"id":"flanker_angle","label":"FLANKER / PHYSICAL SIDE ANGLE","role":"flanker","policy":"orbit_target","frames":600,"player_pos":Vector2.ZERO,"enemy_pos":Vector2(78,0),"tier":2})
		await play_scene({"id":"harasser_poke","label":"HARASSER / POKE + WITHDRAWAL","role":"harasser","policy":"orbit_target","frames":600,"player_pos":Vector2.ZERO,"enemy_pos":Vector2(80,0)})
		for role: String in Roles.BUILDS:
			await play_scene({"id":role+"_outplay","label":role.to_upper()+" / PLAYER BURST OUTPLAY / LEGAL GATE START","role":role,"policy":"gate_outplay","frames":240,"player_pos":Vector2(104,-104),"enemy_pos":Vector2(126,-126),"player_velocity":Vector2(1,-1).normalized()*180.0})
	else:
		await play_scene({"id":"offensive","label":"OFFENSIVE / REDLINE + MOMENTUM BANK","role":"hunter","policy":"dodge","frames":720,"tier":2})
		await play_scene({"id":"defensive","label":"DEFENSIVE / DEAD CENTER + IMPACT SINK","role":"bulwark","policy":"guard_hit","frames":600,"player_pos":Vector2(-100,0),"enemy_pos":Vector2(14,0),"tier":2})
		await play_scene({"id":"mobile","label":"MOBILITY / ORBIT DRIVE + AFTERIMAGE","role":"flanker","policy":"orbit_target","frames":720,"player_pos":Vector2.ZERO,"enemy_pos":Vector2(78,0),"tier":2})
		await play_scene({"id":"elite_hotwire","label":"HOTWIRE ELITE / REAL BREAKNECK COMMITMENT","role":"hunter","key":"hotwire","kind":"elite","policy":"dodge","frames":600,"tier":3,"player_pos":Vector2.ZERO,"enemy_pos":Vector2(76,0)})

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="):frame_dir=arg.trim_prefix("--frames=")
		if arg=="--diagnostic":diagnostic=true
	if output.is_empty() or mode not in ["intelligence","powers"]:quit(2);return
	root.size=Vector2i(640,400);root.content_scale_size=Vector2i(640,400);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty():DirAccess.make_dir_recursive_absolute(frame_dir)
	sound=Sound.new();root.add_child(sound);sound.rng.seed=421;sound.apply_settings({"volume":.65,"sfx_volume":1.0})
	music=Music.new();root.add_child(music);music.configure_playback(not diagnostic);music.set_context("run")
	await showcase()
	if movie_frames!=(3480 if mode=="intelligence" else 2640):failures.append("Capture did not complete every declared native frame")
	music.configure_playback(false);sound.grind_provider=Callable();sound._grind_player.stop()
	for channel: AudioStreamPlayer in sound.channels:channel.stop();channel.stream=null
	for label: Label in labels:label.free()
	labels.clear()
	# Native mixer resources get a real silent release tail before destruction.
	# Every authored movie frame, including that tail, is declared in the report.
	var teardown_frames: int=0
	if diagnostic:await create_timer(.60).timeout
	else:
		for tick: int in range(36):await process_frame;movie_frames+=1;teardown_frames+=1
	music.free();sound.free();await process_frame
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(portable({"task":"003A.1 enemy native review","mode":mode,"diagnostic":diagnostic,"movie_frames":movie_frames,"teardown_frames":teardown_frames,"scenes":scenes,"rows":actor_rows,"features":features,"failures":failures,"native_gameplay":[640,360],"native_caption_canvas":[640,400],"main_created":false,"collection_opened":false,"authenticity":"Disclosed legal initial one-enemy Run fixtures; actual ordinary Battle fixed ticks, EnemyRoles pilot, economy, packages, power hooks and solver outcomes. Player script reacts to observable commitment. No initial power-state grants, AI intent injection, forced activation or forced outcomes. Director admissions suspended only to isolate opponent; no natural difficulty claim."}),"\t"));file.close()
	print("ENEMY_NATIVE_CAPTURE_%s frames=%d"%["PASS" if failures.is_empty() else "FAIL",movie_frames]);quit(0 if failures.is_empty() else 1)
