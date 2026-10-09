extends "res://tests/capture_enemy_intelligence_003a1.gd"
## Real60Hz solver with declared starting assemblies/poses and steering policy.
## No held actor poses, forced traces, reserve edits, procs or outcomes.
const GhostFixture=preload("res://tests/ghost_physics_fixture_003a1.gd")
const Identity=preload("res://scripts/power_identity.gd")
var actor_samples: Array[Dictionary]=[]

func portable(value: Variant) -> Variant:
	if value is Vector2:return [value.x,value.y]
	if value is PackedVector2Array:
		var points: Array=[]
		for point: Vector2 in value:points.append([point.x,point.y])
		return points
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=portable(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(portable(item))
		return result
	return value

func actors(b: Node2D) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for actor: Dictionary in b.fighters:
		result.append({"id":actor.entity_id,"team":actor.team_id,"pos":actor.pos,"vel":actor.vel,"rpm":actor.rpm,"wobble":actor.wobble,"outcome":actor.outcome,"hunt_stacks":actor.get("hunt_stacks",0),"preview":actor.get("ghost_preview",{}),"advice":actor.get("ghost_route_advice",{})})
	return result

func ghost_scene(kind: String, closer: int) -> void:
	var b: Node2D=GhostFixture.create(root,kind,closer)
	b.event_sfx.connect(cue);sound.grind_provider=b.grind_audio_snapshot
	var id: String=kind+"_"+("player" if closer==1 else "enemy")
	var title: String=("PLAYER" if closer==1 else "ENEMY")+" / "+("CLOSES OWN CIRCUIT" if kind=="self" else "STEALS HOSTILE LIVE ROUTE")
	var last_closures: int=0;var pulse_at: int=-1;var immutable: Array[Dictionary]=[];var seen: Dictionary={};var source_paid: float=0.0;var closer_paid: float=0.0
	for tick: int in range(600):
		b.fixture_step()
		var count: int=int(b.powers.counters.get("ghost_closure",0));var feature: String=""
		if count>last_closures:feature=id+"_closure_%d"%count;pulse_at=tick+12
		elif tick==pulse_at:feature=id+"_current_%d"%count
		elif tick in [120,180,239,300,599]:feature=id+"_%04d"%tick
		last_closures=count
		for trace: Dictionary in b.powers.traces:
			if not seen.has(trace.cause.event_id):
				seen[trace.cause.event_id]=true
				immutable.append({"trace":trace,"owner":trace.owner_entity_id,"team":trace.team_id,"cause":trace.cause.duplicate(true),"points":trace.points.duplicate()})
				if int(trace.owner_entity_id)==closer:closer_paid+=float(trace.paid_rpm)
				else:source_paid+=float(trace.paid_rpm)
		var state: String="DRAW LIVE ROUTE" if kind=="self" or not b.source_released else ("PAID PHYSICAL BRIDGE" if count==0 else "CLOSER-OWNED PULSE / USED ROUTE GUARDED")
		captions("003A.1 GHOST / "+title,"LEGAL START / REAL STEERING + SOLVER / "+state+" / %d CLOSURES"%count)
		if tick%6==0 or not feature.is_empty():actor_samples.append({"scene":id,"frame":movie_frames,"tick":tick,"actors":actors(b),"controls":b.control_rows.back(),"traces":b.powers.traces.duplicate(true),"power_events":b.powers.events.duplicate(true),"effects":b._power_fx.duplicate(true),"diagnostics":b.powers.ghost_route_diagnostics()})
		await frame(b,id,tick,feature)
	var preserved: bool=true;var consumed: int=0
	for row: Dictionary in immutable:
		var trace: Dictionary=row.trace
		preserved=preserved and trace.owner_entity_id==row.owner and trace.team_id==row.team and trace.cause==row.cause and trace.points==row.points
		consumed+=trace.get("ghost_used_edges",[]).size()
	if last_closures==0 or int(b.powers.counters.get("ghost_activation",0))==0:failures.append(id+" did not physically close/affect enclosed hostile")
	if not preserved or consumed==0:failures.append(id+" provenance/consumption contract failed")
	if kind=="hijack" and int(b.powers.counters.get("ghost_hijack",0))!=1:failures.append(id+" did not produce exactly one paid hijack")
	scenes.append({"id":id,"frames":600,"source_id":b.source_id,"closer_id":closer,"builds":[b.entity(1).build,b.entity(2).build],"initial_fixture":"Vane both; AfterimageII source, GhostIII closer, HighGearII both. Self closer(85,0),vel(0,133),hostilecentre; hijack source(70,0),vel(0,126),closer(0,-125),stationary. Initial neutral NPC buttons/admissions suspended. Subsequent sampled observable-route steering only.","controls":"Canonical acceleration/drag/costs/collisions, no body/resource/trail writes after initialization. QA NPC steering override is disclosed; not a natural pilot/balance claim.","paid_rpm":{"source":source_paid,"closer":closer_paid},"trace_provenance_unchanged":preserved,"consumed_edge_intervals":consumed,"counters":b.powers.counters.duplicate(true),"events":b.powers.events.duplicate(true),"economy":b.continuous.economy.snapshot(),"balance_claim":false});b.free()

func predator_scene(reduced: bool) -> void:
	var spec: Dictionary={"id":"predator_reduced" if reduced else "predator_normal","role":"hunter","policy":"guard_hit","player_pos":Vector2(-38,0),"enemy_pos":Vector2(38,0),"player_velocity":Vector2(126,0),"enemy_velocity":Vector2(-90,0)}
	var b: Node2D=scenario(spec);b.reduced_flashing=reduced
	for actor: Dictionary in b.fighters:
		actor.powers.assign(["predator_line","high_gear"]);actor.power_ranks={"predator_line":2,"high_gear":2};actor.power_mutations={};actor.ability_rebalance=true
	b.powers.setup(b);b.roster.setup(b);Identity.reset_motion()
	var visible: int=0;var peak_stacks: int=0
	for tick: int in range(600):
		var p: Dictionary=b.player_entity();var e: Dictionary=b.entity(2)
		var desired: Vector2=(Vector2(e.pos)-Vector2(p.pos)).normalized()
		if tick>90:desired=(Vector2(e.pos)+Vector2(e.vel)*.12-Vector2(p.pos)).normalized()
		if Vector2(p.pos).length()>140.0:desired=-Vector2(p.pos).normalized()
		b.test_step(Battle.FIXED_DT,screen(desired),tick in [120,300,480],false)
		var plans: Array[Dictionary]=[]
		for actor: Dictionary in b.fighters:
			var target: Dictionary=b.entity(int(actor.get("hunt_target",0)))
			var plan: Dictionary=Identity.predator_plan(actor,target,b._visual_time);plans.append(plan)
			peak_stacks=maxi(peak_stacks,int(actor.get("hunt_stacks",0)))
			if bool(plan.active):visible+=1
		var feature: String=spec.id+"_earned_motion" if visible>0 and not features.has(spec.id+"_earned_motion") else (spec.id+"_%04d"%tick if tick in [120,180,300,450,599] else "")
		captions("003A.1 PREDATOR / "+("REDUCED FLASHING" if reduced else "WARM PURSUIT TICKS"),"ACTUAL CONTACT-EARNED HUNT / REAL HUNTER PILOT / SHORT MOTION CUE / %d STACKS"%peak_stacks)
		if tick%6==0 or not feature.is_empty():actor_samples.append({"scene":spec.id,"frame":movie_frames,"tick":tick,"actors":actors(b),"plans":plans,"counters":b.powers.counters.duplicate(true),"roster_counters":b.roster.counters.duplicate(true),"pilot":Roles.decision_snapshot(e)})
		await frame(b,spec.id,tick,feature)
	if visible==0 or peak_stacks==0:failures.append(spec.id+" did not earn Predator motion through real contacts")
	scenes.append({"id":spec.id,"frames":600,"reduced_flashing":reduced,"peak_contact_earned_stacks":peak_stacks,"active_motion_samples":visible,"initial_fixture":fixture,"power_override":"Both legal PredatorII+HighGearII starting ownership; ordinary Hunter pilot unchanged afterward.","counters":b.powers.counters.duplicate(true),"roster_counters":b.roster.counters.duplicate(true),"events":b.powers.events.duplicate(true),"balance_claim":false});b.free()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="):frame_dir=arg.trim_prefix("--frames=")
		if arg=="--diagnostic":diagnostic=true
	if output.is_empty() or mode not in ["ghost","predator"]:quit(2);return
	root.size=Vector2i(640,400);root.content_scale_size=Vector2i(640,400);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty():DirAccess.make_dir_recursive_absolute(frame_dir)
	sound=Sound.new();root.add_child(sound);sound.rng.seed=421;sound.apply_settings({"volume":.65,"sfx_volume":1.0})
	music=Music.new();root.add_child(music);music.configure_playback(not diagnostic);music.set_context("run")
	if not diagnostic:
		for tick: int in range(36):await process_frame;movie_frames+=1
	if mode=="ghost":
		for kind: String in ["self","hijack"]:
			for closer: int in [1,2]:await ghost_scene(kind,closer)
	else:
		for reduced: bool in [false,true]:await predator_scene(reduced)
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(portable({"mode":mode,"diagnostic":diagnostic,"movie_frames":movie_frames,"scenes":scenes,"actor_samples":actor_samples,"rows":rows,"features":features,"failures":failures,"native_gameplay":[640,360],"native_caption_canvas":[640,400],"main_created":false,"collection_opened":false,"authenticity":"Normal60FPS actual Battle fixed physics/costs/powers/contact/rendering. Legal initial fixture plus controls only afterward. Ghost NPC uses disclosed sampled steering; Predator NPC uses unchanged real Hunter pilot. No native body/route/charge/reserve/outcome writes after setup; no cinematic hold."}),"\t"));file.close()
	music.configure_playback(false)
	for channel: AudioStreamPlayer in sound.channels:channel.stop()
	music.free();sound.free()
	for label: Label in labels:label.free()
	labels.clear();await process_frame
	print("GHOST_PREDATOR_CAPTURE ",mode," frames=",movie_frames," failures=",failures);quit(0 if failures.is_empty() else 1)
