extends SceneTree
## Deliberate initial collision pose fixtures, labelled on every native scene.
## All impact events use the canonical full-top pair solver; authored playback
## and direction filtering are never edited or called directly by this capture.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Parts = preload("res://scripts/parts.gd")
const Physical = preload("res://scripts/part_physics.gd")
const Beasts = preload("res://scripts/beast_manifestations.gd")
const Sound = preload("res://scripts/sound.gd")
const IDENTITIES: Array[Dictionary] = [{"id":"black_arrow","blade":"smash","name":"BLACK ARROW"},{"id":"iron_bull","blade":"hammerfall","name":"IRON BULL"},{"id":"stone_tortoise","blade":"guard","name":"STONE TORTOISE"},{"id":"coil_dragon","blade":"balance","name":"COIL DRAGON"}]
const SLOWDOWN: int = 3
const SHOW_TICKS: int = 144
var output: String = ""
var frames: String = ""
var mode: String = "final"
var diagnostic: bool = false
var failures: Array[String] = []
var sounds: Node
var movie_frame: int = 0

static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Rect2: return {"position":portable(value.position),"size":portable(value.size)}
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = portable(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(portable(item))
		return result
	return value

static func screen_input(world: Vector2) -> Vector2:
	return Vector2(world.x-world.y,(world.x+world.y)*0.5).normalized()

func caption(text: String, position: Vector2, colour: Color = Color("e4ebd6")) -> Label:
	var label: Label = Label.new()
	label.text = text; label.position = position
	label.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"))
	label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_color",colour)
	root.add_child(label)
	return label

func player_beast(b: Node2D) -> Dictionary:
	for item: Dictionary in b.beast_presentation_snapshot().active:
		if int(item.owner_entity_id)==1: return item
	return {}

func present(b: Node2D, repeats: int = SLOWDOWN) -> void:
	if diagnostic: return
	for _repeat: int in range(repeats):
		b.queue_redraw(); await process_frame; movie_frame += 1

func capture_image(name: String) -> String:
	if diagnostic or frames.is_empty(): return ""
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.resize(640,360,Image.INTERPOLATE_NEAREST)
	var safe_name: String = name.replace("/","-").replace("\\","-")
	var path: String = frames.path_join(safe_name+".png")
	assert(not FileAccess.file_exists(path) and image.save_png(path)==OK)
	return path

func make_battle(identity: Dictionary) -> Node2D:
	var b: Node2D = Battle.new()
	root.add_child(b); b.set_process(false); b.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1,421)
	descriptor.opponent_build = {"blade":"hammerfall","ratchet":"ballast","bit":"tripod"}
	descriptor.player_power_ids = []; descriptor.player_power_ranks = {}; descriptor.player_power_mutations = {}
	descriptor.starter_id = "custom"
	b.begin_run({"blade":identity.blade,"ratchet":"ballast","bit":"tripod"},descriptor,421)
	b.screen_shake_enabled = false
	b.event_sfx.connect(func(kind: String) -> void:
		if not diagnostic: sounds.play_sound(kind))
	var launch: int = 0
	while b.battle_status != "battle" and launch < 400: b.test_step(Battle.FIXED_DT); launch += 1
	assert(b.battle_status=="battle")
	return b

func staged_contact(b: Node2D, target_score: float) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var other: Dictionary = b.entity(2)
	assert(b._is_live(p) and b._is_live(other))
	# These declared positions/velocities define the pose fixture. There is no
	# hit/severity/beast-state injection; resolve_pair computes all real values.
	p.pos = Vector2(-8,0); other.pos = Vector2(8,0)
	var inv_sum: float = b.powers.inverse_mass(p)+b.powers.inverse_mass(other)
	var a_contact: Dictionary = Physical.contact_profile(p,Vector2.RIGHT,Vector2.RIGHT*200,b.elapsed,2)
	var c_contact: Dictionary = Physical.contact_profile(other,Vector2.LEFT,Vector2.LEFT*200,b.elapsed,1)
	var factor: float = clampf(sqrt(float(a_contact.attack)*float(c_contact.attack)),0.70,1.30) if Physical.active(p) or Physical.active(other) else 1.0
	# Solve J*closing=score using the canonical J equation; fixture placement
	# then lets the actual solver accept and report its unmodified physical hit.
	var closing: float = maxf(1.0,(-19.0+sqrt(19.0*19.0+4.0*1.70*target_score*inv_sum/factor))/(2.0*1.70))
	assert(closing<=960.0,"Capture fixture must retain canonical <=480 speed per body")
	p.vel = Vector2.RIGHT*closing*0.5; other.vel = Vector2.LEFT*closing*0.5
	var accepted: Array[Dictionary] = []
	var listener: Callable = func(event: Dictionary) -> void: accepted.append(event.duplicate(true))
	b.full_top_impact_accepted.connect(listener)
	b.resolve_pair(1,2)
	b.full_top_impact_accepted.disconnect(listener)
	assert(accepted.size()==1)
	return accepted[0]

func run_case(identity: Dictionary, name: String, target_multiplier: float, turn: String = "steady", followup: bool = false) -> Dictionary:
	var b: Node2D = make_battle(identity)
	var labels: Array[Label] = [caption("003A / "+str(identity.name)+" / "+name,Vector2(12,12)),caption("DECLARED COLLISION POSE FIXTURE / CANONICAL PHYSICAL SOLVER",Vector2(12,30),Color("bcc8c9")),caption("ACTUAL IMPACT / AUTHORED MOTION",Vector2(12,56),Color("e8c481")),caption("NATIVE 640x360 / INTEGER NEAREST / 1/3 SPEED / NO SAVE ACCESS",Vector2(12,342),Color("b2bcc0"))]
	var start_frame: int = movie_frame
	await present(b,30)
	var actual: Dictionary = staged_contact(b,Beasts.EXTREME_IMPACT_SCORE*target_multiplier)
	var expect: bool = target_multiplier>=1.0
	if (not player_beast(b).is_empty()) != expect: failures.append("Initial qualification wrong for "+name)
	var features: Dictionary = {}
	var rows: Array[Dictionary] = []
	var phases: Array[String] = []
	var instance: int = int(player_beast(b).get("instance_id",0))
	var second_contact: Dictionary = {}
	var before_followup_spawns: int = 0
	for tick: int in range(SHOW_TICKS):
		var time: float = float(tick)*Battle.FIXED_DT
		var direction: Vector2 = Vector2.LEFT
		var steering_note: String = "STEADY FACING / COMPLETE AUTHORED MOTION"
		var brake: bool = tick<48
		var turn_time: float = 100.0
		if turn=="early": turn_time=0.08
		elif turn=="upside": turn_time=0.44
		elif turn=="late": turn_time=0.98
		elif turn=="rapid": turn_time=0.12
		if time>=turn_time:
			direction = Vector2.RIGHT if turn!="rapid" or int(floor(time/0.15))%2==0 else Vector2.LEFT
			steering_note = "MEANINGFUL TURN / TIMELINE CONTINUES" if turn!="rapid" else "RAPID LEFT/RIGHT / TIMELINE CONTINUES"
		if time>1.15:
			direction = -Vector2(b.player_entity().pos).normalized(); brake=true
		if followup and tick==53:
			before_followup_spawns = b.beast_presentation_snapshot().spawned
			second_contact = staged_contact(b,Beasts.EXTREME_IMPACT_SCORE*0.10)
			if b.beast_presentation_snapshot().spawned!=before_followup_spawns: failures.append("Ordinary follow-up spawned a duplicate giant")
		b.test_step(Battle.FIXED_DT,screen_input(direction),false,brake)
		var item: Dictionary = player_beast(b)
		var geometry: Dictionary = b.beasts.draw_geometry_for(item) if not item.is_empty() else {}
		var phase: String = str(item.get("phase",""))
		var frame: int = b.beasts.frame_for(str(identity.id),phase,float(item.get("phase_age",0.0))) if not item.is_empty() else -1
		if not phase.is_empty() and phase not in phases: phases.append(phase)
		labels[2].text = steering_note+" / "+phase.to_upper() if not phase.is_empty() else ("RESOLVED / ORDINARY PHYSICAL PLAY" if expect else "ORDINARY IMPACT FX / NO BEAST")
		if followup and tick>=53 and tick<75: labels[2].text="NEXT ORDINARY COLLISION / NO NEW BEAST"
		rows.append({"tick":tick,"time":b.elapsed,"input":direction,"brake":brake,"position":b.player_entity().pos,"velocity":b.player_entity().vel,"beast":item.duplicate(true),"frame":frame,"geometry":geometry,"live":b.beast_presentation_snapshot().count})
		await present(b)
		var feature: String = phase
		if phase=="travel" and frame==6: feature="travel_inverted"
		if not feature.is_empty() and not features.has(feature):
			features[feature]={"path":await capture_image(str(identity.id)+"_"+name.to_lower().replace(" ","_")+"_"+feature),"tick":tick,"frame":frame,"phase":phase,"beast":item.duplicate(true),"geometry":geometry}
	if expect and phases != ["prepare","travel","strike","recovery"]: failures.append("Full authored phases missing for "+name+": "+str(phases))
	if expect and not player_beast(b).is_empty(): failures.append("No valid terminal state for "+name)
	if b.beast_presentation_snapshot().peak_live>1: failures.append("Overlapping giants for "+name)
	var row: Dictionary = {"identity":identity,"case":name,"turn_policy":turn,"target_multiplier":target_multiplier,"fixture":"Deliberate canonical bounded initial collision pose/velocity; no injected impact/animation/beast state.","actual_impact":actual,"followup_impact":second_contact,"movie_frame_start":start_frame,"movie_frame_end":movie_frame,"instance_id":instance,"phases":phases,"feature_frames":features,"rows":rows,"presentation":b.beast_presentation_snapshot()}
	for label: Label in labels: label.free()
	b.free()
	print("BEAST_EXTREME_CAPTURE ",identity.id," ",name," J=",snappedf(float(actual.impulse),0.01)," phases=",phases)
	return row

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frames=arg.trim_prefix("--frames=")
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
		if arg=="--diagnostic": diagnostic=true
	assert(output.is_absolute_path() and not FileAccess.file_exists(output) and is_finite(Beasts.EXTREME_IMPACT_SCORE))
	root.size=Vector2i(1280,720); root.content_scale_size=Vector2i(640,360)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames.is_empty(): DirAccess.make_dir_recursive_absolute(frames)
	sounds=Sound.new(); root.add_child(sounds)
	var runs: Array[Dictionary] = []
	if mode=="ladder":
		runs.append(await run_case(IDENTITIES[0],"NORMAL CONTACT",0.08))
		runs.append(await run_case(IDENTITIES[0],"STRONG CONTACT",0.40))
		runs.append(await run_case(IDENTITIES[0],"VERY HARD CONTACT",0.78))
		runs.append(await run_case(IDENTITIES[0],"EXTREME CONTACT",1.45,"upside",true))
	elif mode=="completion":
		for policy: String in ["steady","early","upside","late","rapid"]: runs.append(await run_case(IDENTITIES[0],"SOMERSAULT "+policy.to_upper(),1.45,policy))
	else:
		for identity: Dictionary in IDENTITIES: runs.append(await run_case(identity,"HUGE CONTACT / COMPLETE RESOLUTION",1.45,"upside"))
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	assert(file!=null)
	file.store_string(JSON.stringify(portable({"mode":mode,"diagnostic":diagnostic,"native_view":[640,360],"fps":60,"slowdown":SLOWDOWN,"movie_frames":movie_frame,"collection_opened":false,"main_created":false,"scope":"Explicit deliberate collision pose fixtures use canonical physical full-top solver and production authored frame playback. Normal mapped steering/Brake changes direction. No powers, outcomes, RPM, animation state or impact scores injected; no player profile opened. This is visual/contract evidence, not natural collision frequency or human feel acceptance.","runs":runs,"failures":failures}),"\t")); file.close()
	print("BEAST_EXTREME_CAPTURE_", "PASS" if failures.is_empty() else "FAIL"," mode=",mode," runs=",runs.size())
	quit(0 if failures.is_empty() else 1)
