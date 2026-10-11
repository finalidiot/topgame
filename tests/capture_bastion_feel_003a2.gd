extends SceneTree
## Discovery and literal replay use actual canonical Run physics/AI/Director.
## Initial invested ownership is disclosed; no live actor/resource/effect edits.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Menus = preload("res://scripts/menus.gd")
const Music = preload("res://scripts/music.gd")
const Sound = preload("res://scripts/sound.gd")
class ObservedBattle extends "res://scripts/battle.gd":
	var delivered: Array[Dictionary]=[]
	func apply_power_impulse(target: Dictionary,offered: Vector2,cause: Dictionary) -> void:
		var before: Vector2=target.vel
		super.apply_power_impulse(target,offered,cause)
		if int(cause.get("owner_entity_id",0))==player_entity_id and str(cause.get("kind","")) in ["counterweight_release","return_spring"]:
			delivered.append({"time":elapsed,"target":target.entity_id,"offered":offered,"before_velocity":before,"after_velocity":target.vel,"actual_delta":Vector2(target.vel)-before,"cause":cause.duplicate(true)})
const LOADOUTS: Dictionary = {
	"naked":{"ranks":{},"mutations":{}},
	"counter":{"ranks":{"dead_centre":3,"anchor_exchange":2,"momentum_bank":2},"mutations":{"dead_centre":"counterweight"}},
	"sink":{"ranks":{"dead_centre":2,"impact_sink":3,"gyro_lock":1},"mutations":{"impact_sink":"return_spring"}},
	"mixed":{"ranks":{"dead_centre":2,"impact_sink":2,"momentum_bank":2,"iron_comet":2,"crosscut":1},"mutations":{}},
	"guard":{"ranks":{"crash_guard":2,"momentum_bank":2},"mutations":{}}
}
var report: String=""
var plan_path: String=""
var frames_path: String=""
var mode: String="discover"
var source_label: String=""
var checks: int=0
var failures: Array[String]=[]
var rows: Array[Dictionary]=[]
var rendered_sections: Array[Dictionary]=[]
var frame_count: int=0
var render_active: bool=false
var capture: Node2D
var arena: SubViewport
var arena_frame: TextureRect
var menus: Control
var caption_label: Label
var sounds: Node
var music: Node
var current_case: Dictionary={}
var impacts: Array[Dictionary]=[]
var seen_events: Dictionary={}
var events: Array[Dictionary]=[]
var before_tick: Dictionary={}
var audio_requests: Array[Dictionary]=[]

func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		if not message in failures: failures.append(message)
		push_error(message)
func portable(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Rect2 or value is Rect2i: return [value.position.x,value.position.y,value.size.x,value.size.y]
	if value is Color: return [value.r,value.g,value.b,value.a]
	if value is Dictionary:
		var result: Dictionary={};var keys: Array=value.keys()
		keys.sort_custom(func(a:Variant,b:Variant)->bool:return str(a)<str(b))
		for key: Variant in keys: result[str(key)]=portable(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result: Array=[]
		for item: Variant in value: result.append(portable(item))
		return result
	return value
func digest(value: Variant) -> String: return JSON.stringify(portable(value)).sha256_text()
func input_direction(world: Vector2) -> Vector2:
	return Vector2(world.x-world.y,(world.x+world.y)*.5).normalized()*minf(1,world.length())
func defaults() -> Array[Dictionary]:
	var output: Array[Dictionary]=[]
	for starter: String in ["bastion","breaker","vane"]:
		output.append({"id":starter+"_naked","seed":421717,"starter":starter,"loadout":"naked","policy":"movement","seconds":16})
	for seed_value: int in [421,7341,2026]:
		for loadout: String in ["counter","sink","mixed","guard"]:
			output.append({"id":loadout+"_"+str(seed_value),"seed":seed_value,"starter":"bastion","loadout":loadout,"policy":"active_defence","seconds":90})
	return output
func nearest_full() -> Dictionary:
	var player: Dictionary=capture.player_entity();var best: Dictionary={};var distance: float=INF
	for fighter: Dictionary in capture.fighters:
		if int(fighter.entity_id)==int(player.entity_id) or fighter.combatant_type!="full_top" or not str(fighter.outcome).is_empty() or fighter.team_id==player.team_id: continue
		var gap: float=Vector2(fighter.pos).distance_to(player.pos)
		if gap<distance: distance=gap;best=fighter
	return best
func observed_controls(configuration: Dictionary,tick: int,state: Dictionary) -> Dictionary:
	if capture.battle_status!="battle": return {"direction":Vector2.ZERO,"burst":false,"brake":false,"phase":"real_launch_countdown"}
	if int(state.get("sample_tick",-1))>tick:
		# Held steering/Brake are continuous. Burst is the production fresh edge.
		var held: Dictionary=state.control.duplicate()
		held.burst=false
		return held
	state.sample_tick=tick+8
	var player: Dictionary=capture.player_entity()
	var position: Vector2=player.pos;var velocity: Vector2=player.vel
	var radius: float=position.length();var speed: float=velocity.length()
	var direction: Vector2=Vector2.ZERO;var braking: bool=false;var bursting: bool=false;var phase: String="hold_and_read"
	var seconds: float=capture.elapsed
	if configuration.policy=="movement":
		var leg: int=int(seconds/2.0)%6
		var directions: Array[Vector2]=[Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2.ZERO,Vector2.RIGHT]
		direction=directions[leg]*.72
		braking=leg==4
		phase=["reposition_right","reverse_left","reposition_up","reverse_down","timed_brake","reposition_after_brake"][leg]
		if radius>140: direction=(-position-velocity*.35).normalized()*.8;phase="ordinary_edge_recovery"
	else:
		var target: Dictionary=nearest_full()
		var offset: Vector2=Vector2(target.pos)-position if not target.is_empty() else Vector2.ZERO
		var gap: float=offset.length()
		var approach: float=maxf(0,-(Vector2(target.vel)-velocity).dot(offset.normalized())) if not target.is_empty() else 0
		var anchor_stress: float=float(player.get("anchor_stress",0))
		var returning: bool=bool(state.get("returning",false))
		var relocating: bool=bool(state.get("relocating",false))
		if not relocating and (anchor_stress>.36 or (float(player.get("anchor_recovery_remaining",1))<.10 and seconds>12)):
			relocating=true;state.rearm_before=int(capture.powers.counters.get("anchor_rearm",0))
		if relocating and radius>86 and anchor_stress<.12 and int(capture.powers.counters.get("anchor_rearm",0))>int(state.get("rearm_before",0)): returning=true
		if returning and radius<30: relocating=false;returning=false
		if relocating:
			if returning: direction=(-position-velocity*.4).normalized()*.65;phase="return_and_rearm"
			elif radius<88: direction=(position.normalized() if radius>15 else Vector2.RIGHT)*.8;phase="leave_loaded_centre"
			else:
				var tangent: Vector2=Vector2(-position.y,position.x).normalized()
				direction=(tangent-position.normalized()*clampf((radius-98)/28,-.7,.7)).normalized()*.75
				phase="vent_and_rearm_outside"
		else:
			var correction: Vector2=-position-velocity*.4
			direction=correction.normalized()*minf(.30,correction.length()/100.0)
			if radius>65: direction=correction.normalized()*.68;phase="ordinary_centre_recovery"
			elif speed<55 and gap<90 and approach>40:
				braking=true;direction=offset.normalized()*.18;phase="read_incoming_and_brace"
			var force: float=float(player.get("stored_force",0))
			var bank: float=float(player.get("momentum_charge",0))
			if (force>=12 or bank>=15) and gap<92 and float(player.cooldown)<=0 and float(player.rpm)>.25:
				direction=offset.normalized()*.80;braking=false;bursting=true;phase="aimed_paid_burst_release"
			elif float(player.get("sink_charge",0))>=15 and gap<62 and speed<=120 and not bool(state.get("last_brake",false)):
				braking=true;direction=offset.normalized()*.22;phase="fresh_brake_earned_sink_vent"
			elif configuration.loadout in ["mixed","guard"] and not target.is_empty():
				direction=(offset-velocity*.3).normalized()*.65;phase="mixed_committed_approach"
				if speed>80 and gap<100 and float(player.cooldown)<=0 and float(player.rpm)>.35: bursting=true;phase="mixed_paid_burst"
		if radius>155: direction=(-position-velocity*.5).normalized()*.9;braking=speed>90;bursting=false;phase="ordinary_edge_recovery"
		state.relocating=relocating;state.returning=returning
	state.last_brake=braking
	var control: Dictionary={"direction":input_direction(direction),"burst":bursting,"brake":braking,"phase":phase}
	state.control=control
	return control
func simulation() -> Dictionary:
	return {"battle":capture.snapshot(),"power_time":capture.powers.time,"power_states":capture.powers._states.duplicate(true),
		"defence":capture.powers.defence.states.duplicate(true),"roster_time":capture.roster.time,"roster":capture.roster.states.duplicate(true),
		"events":capture.powers.events.duplicate(true),
		"traces":capture.powers.traces.duplicate(true),"economy":capture.continuous.economy.snapshot(),"director":capture.continuous.snapshot()}
func body_reading() -> Dictionary:
	var player: Dictionary=capture.player_entity()
	return {"position":player.pos,"velocity":player.vel,"rpm":player.rpm,"wobble":player.wobble,"stored_force":player.get("stored_force",0),"sink_charge":player.get("sink_charge",0),"momentum_charge":player.get("momentum_charge",0),"anchor_stress":player.get("anchor_stress",0),"defence":capture.powers.defence.diagnostics(player)}
func reading(tick: int,control: Dictionary) -> Dictionary:
	var player: Dictionary=capture.player_entity()
	return {"tick":tick,"time":capture.elapsed,"phase":control.phase,"position":player.pos,"velocity":player.vel,"rpm":player.rpm,"wobble":player.wobble,
		"radius":Vector2(player.pos).length(),"speed":Vector2(player.vel).length(),"anchor_charge":player.get("anchor_charge",0),"anchor_stress":player.get("anchor_stress",0),
		"anchor_rearm":player.get("anchor_rearm_progress",0),"anchor_remaining":player.get("anchor_recovery_remaining",0),"stored_force":player.get("stored_force",0),
		"sink_charge":player.get("sink_charge",0),"momentum_charge":player.get("momentum_charge",0),"power_procs":capture.powers.counters.duplicate(),
		"defence":capture.powers.defence.diagnostics(player),"roster_procs":capture.roster.counters.duplicate(),
		"economy":capture.continuous.economy.snapshot(),"simulation_sha256":digest(simulation())}
func hud(stats: Dictionary) -> void:
	if not is_instance_valid(menus): return
	var owned: Dictionary=LOADOUTS[str(current_case.loadout)]
	stats=stats.duplicate();stats.owned_power_ids=owned.ranks.keys();stats.power_ranks=owned.ranks;stats.power_mutations=owned.mutations
	stats.run_label="BASTION FEEL / DECLARED INITIAL LOADOUT";stats.is_run=true;stats.starter_id=current_case.starter
	stats.level=1+owned.ranks.values().reduce(func(sum_value:int,value:Variant)->int:return sum_value+int(value),0)
	stats.xp=0;stats.xp_threshold=1;stats.progression_max=true;stats.rerolls=0
	menus.show_hud(stats)
func create_case(configuration: Dictionary) -> Dictionary:
	current_case=configuration;impacts=[];seen_events={};events=[];audio_requests=[]
	arena=SubViewport.new();arena.size=Vector2i(640,360);arena.disable_3d=true;arena.gui_disable_input=true;arena.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(arena)
	arena_frame=TextureRect.new();arena_frame.position=Vector2(80,60);arena_frame.size=Vector2(640,360);arena_frame.texture=arena.get_texture();arena_frame.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;arena_frame.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(arena_frame)
	menus=Menus.new();root.add_child(menus);menus.set_presentation_canvas(Vector2(800,480))
	capture=ObservedBattle.new();arena.add_child(capture);capture.set_physics_process(false)
	# The normal Main connection, without collection or reward settlement.
	sounds.grind_provider=capture.grind_audio_snapshot
	capture.hud_updated.connect(hud)
	capture.full_top_impact_accepted.connect(func(event:Dictionary)->void:
		if int(event.first_entity_id)!=1 and int(event.second_entity_id)!=1: return
		var copy: Dictionary=event.duplicate(true);copy.player_state=reading(-1,{"phase":"accepted_real_contact"});impacts.append(copy))
	capture.event_sfx.connect(func(kind:String)->void:
		if render_active and mode=="native":
			var previous: int=int(sounds.played_counts.get(kind,0))
			sounds.play_sound(kind);music.notify_cue(kind)
			audio_requests.append({"time":capture.elapsed,"kind":kind,"played":int(sounds.played_counts.get(kind,0))>previous}))
	var loadout: Dictionary=LOADOUTS[str(configuration.loadout)]
	for id: String in loadout.ranks:
		var rank_value: int=int(loadout.ranks[id]);var branch: String=str(loadout.mutations.get(id,""))
		check(id in Powers.ACTIVE_IDS and rank_value>=1 and rank_value<=3,"Declared family/rank is legal")
		check((rank_value!=3 and branch.is_empty()) or branch in Powers.mutation_choices(id),"Declared Rank III sibling is legal")
	var descriptor: Dictionary=Encounters.for_run_event(1,int(configuration.seed))
	descriptor.starter_id=configuration.starter;descriptor.player_power_ids=loadout.ranks.keys();descriptor.player_power_ranks=loadout.ranks.duplicate(true);descriptor.player_power_mutations=loadout.mutations.duplicate(true)
	capture.begin_run(Starters.build_for(configuration.starter),descriptor,int(configuration.seed))
	# A disclosed initial investment prefix informs production Director pressure.
	# Actors, velocity, reserve and the real countdown retain normal initialization.
	capture.continuous.progression_level=1+loadout.ranks.values().reduce(func(sum_value:int,value:Variant)->int:return sum_value+int(value),0)
	return {"configuration":configuration,"descriptor":descriptor,"initial":simulation(),"initial_positions":capture.fighters.map(func(f:Dictionary)->Dictionary:return {"id":f.entity_id,"position":f.pos,"velocity":f.vel,"launch_velocity":f.launch_velocity}),"handling":capture.player_entity().handling.duplicate(true),"inputs":[],"trace":[],"events":[],"contacts":[],"ticks":0}
func observe_events(tick: int) -> void:
	for event: Dictionary in capture.powers.events:
		if int(event.owner)!=1: continue
		var key: String=digest(event)
		if seen_events.has(key): continue
		seen_events[key]=true
		var copy: Dictionary=event.duplicate(true);copy.tick=tick;copy.before_tick=before_tick.duplicate(true);copy.after_tick=body_reading();copy.player=reading(tick,{"phase":"real_power_event"});events.append(copy)
func destroy_case() -> void:
	arena.free();arena=null;arena_frame.free();arena_frame=null;menus.free();menus=null;capture=null
func one_case(configuration: Dictionary,literal: Array=[],stop_tick: int=-1,section: Dictionary={}) -> Dictionary:
	var output: Dictionary=create_case(configuration);var state: Dictionary={};var tick: int=0;var next_sample: int=0
	var limit: int=int(float(configuration.seconds)*60)+240
	if not literal.is_empty(): limit=literal.size()
	if stop_tick>=0: limit=mini(limit,stop_tick+1)
	while capture.battle_status!="finished" and tick<limit:
		var control: Dictionary
		if literal.is_empty(): control=observed_controls(configuration,tick,state)
		else:
			var input: Array=literal[tick]
			control={"direction":Vector2(float(input[0]),float(input[1])),"burst":bool(input[2]),"brake":bool(input[3]),"phase":str(input[4])}
		if tick==0: check(Vector2(control.direction).length()<=1.00001,"Recorded normalized player input stays legal")
		output.inputs.append([control.direction.x,control.direction.y,control.burst,control.brake,control.phase])
		var film_this_tick: bool=mode=="native" and tick>=int(section.from_tick) and tick<=int(section.to_tick)
		render_active=film_this_tick
		before_tick=body_reading()
		capture.test_step(Battle.FIXED_DT,control.direction,control.burst,control.brake)
		observe_events(tick)
		if tick>=next_sample or capture.battle_status=="finished": output.trace.append(reading(tick,control));next_sample=tick+15
		if film_this_tick:
			caption_label.text=source_label+" / "+str(section.title)+" / "+str(control.phase).replace("_"," ").to_upper()
			music.observe_run(capture.continuous.snapshot(),capture.player_entity())
			await process_frame
			await RenderingServer.frame_post_draw
			if tick==int(section.get("feature_tick",section.from_tick)) and not frames_path.is_empty():
				var image: Image=root.get_texture().get_image();var path: String=frames_path.path_join(str(section.id)+".png")
				check(image.get_size()==Vector2i(800,480) and image.save_png(path)==OK,"Actual native full-client film frame is800×480")
				section.feature_image={"path":path,"sha256":FileAccess.get_sha256(path)}
			frame_count+=1
		tick+=1
		if capture.battle_status=="battle" and capture.elapsed>=float(configuration.seconds): break
	output.ticks=tick;output.events=events.duplicate(true);output.contacts=impacts.duplicate(true)
	output.end=reading(tick,{"phase":"natural_end_or_horizon"});output.result=capture.last_result.duplicate(true);output.status=capture.battle_status
	output.delivered_counters=capture.delivered.duplicate(true)
	output.native_audio_requests=audio_requests.duplicate(true)
	output.director_history=capture.continuous.director.history.duplicate(true)
	output.input_sha256=digest(output.inputs)
	render_active=false
	destroy_case()
	return output
func validate_paths() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
		if arg.begins_with("--plan="): plan_path=arg.trim_prefix("--plan=")
		if arg.begins_with("--frames="): frames_path=arg.trim_prefix("--frames=")
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--source-label="): source_label=arg.trim_prefix("--source-label=")
	var qa: String=OS.get_environment("TOPGAME_QA_ROOT").path_join("003A.2").replace("\\","/").simplify_path()
	if OS.get_environment("TOPGAME_QA_ROOT").is_empty() or not report.is_absolute_path() or not report.replace("\\","/").to_lower().begins_with(qa.to_lower()+"/manifests/") or FileAccess.file_exists(report): return false
	if mode not in ["discover","replay","native"]: return false
	if mode!="discover" and (not plan_path.is_absolute_path() or not FileAccess.file_exists(plan_path)): return false
	if mode=="native":
		if DisplayServer.get_name()=="headless" or not frames_path.is_absolute_path() or DirAccess.dir_exists_absolute(frames_path): return false
		if not frames_path.replace("\\","/").to_lower().begins_with(qa.to_lower()+"/frames/"): return false
		DirAccess.make_dir_recursive_absolute(frames_path)
	return true
func run() -> void:
	check(validate_paths(),"Fresh explicit external QA paths required before runtime")
	if not failures.is_empty(): quit(2);return
	root.size=Vector2i(800,480);root.content_scale_size=Vector2i(800,480);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var layer:=CanvasLayer.new();layer.layer=40;root.add_child(layer)
	caption_label=Label.new();caption_label.position=Vector2(4,460);caption_label.size=Vector2(792,18);caption_label.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"));caption_label.add_theme_font_size_override("font_size",10);layer.add_child(caption_label)
	# Captions are placed in an external band, preserving the entire native HUD.
	caption_label.visible=false
	sounds=Sound.new();root.add_child(sounds);music=Music.new();root.add_child(music);music.configure_playback(mode=="native");music.set_context("run")
	if mode=="discover":
		for configuration: Dictionary in defaults(): rows.append(await one_case(configuration))
	else:
		var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(plan_path))
		check(plan.schema=="003a2-bastion-feel-plan-v1","Literal replay plan has declared schema")
		if mode=="replay":
			for entry: Dictionary in plan.cases: rows.append(await one_case(entry.configuration,entry.inputs))
		else:
			for section: Dictionary in plan.sections:
				var entry: Dictionary={}
				for candidate: Dictionary in plan.cases:
					if candidate.configuration.id==section.case_id: entry=candidate;break
				check(not entry.is_empty(),"Film section resolves a recorded real case")
				if entry.is_empty(): continue
				var first_frame: int=frame_count
				rows.append(await one_case(entry.configuration,entry.inputs,int(section.to_tick),section))
				section.movie_from=first_frame;section.movie_to=frame_count;rendered_sections.append(section)
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify(portable({"schema":"003a2-bastion-feel-capture-v1","mode":mode,"source_label":source_label,"checks":checks,"failures":failures,
		"cases":rows,"sections":rendered_sections,"movie_frames":frame_count,"native_view":[800,480],"combat_view":[640,360],"main_created":false,"collection_accessed":false,"permanent_rewards_settled":false,
		"scope":"Canonical Battle/Run AI/Director and real launch countdown. Disclosed legal initial invested ownership and progression level; normal actual initialization supplies every position/launch velocity/RPM. No live edits, actor holds, resource refill, forced damage/force/effects/enemies/outcomes. Discovery player policy reads current observed positions/velocities/own state only; replay consumes literal normalized per-tick inputs. Every skipped solver tick is executed before a cut. HUD shows the fixed initial investment fixture, not earned XP. Semantic events and accepted full-top collision records determine earned-effect coverage. Native-speed automated footage is pending human feel review, not physical hardware acceptance."}),"\t"));file.close()
	music.configure_playback(false);music.free();sounds.free();layer.free()
	if mode=="native": await process_frame;await process_frame
	print("BASTION_FEEL_003A2_%s cases=%d frames=%d" % ["PASS" if failures.is_empty() else "FAIL",rows.size(),frame_count])
	quit(0 if failures.is_empty() else 1)
