extends SceneTree
## Labelled legal initial-power fixture. After begin_encounter, only ordinary
## steering/Burst/brake and the real fixed-step solver generate every beast.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Parts = preload("res://scripts/parts.gd")
const Beasts = preload("res://scripts/beast_manifestations.gd")
const CASES: Array[Dictionary] = [
	{"identity":"black_arrow","blade":"smash","name":"BLACK ARROW"},
	{"identity":"iron_bull","blade":"hammerfall","name":"IRON BULL"},
	{"identity":"stone_tortoise","blade":"guard","name":"STONE TORTOISE"},
	{"identity":"coil_dragon","blade":"balance","name":"COIL DRAGON"}]
const SHOW_TICKS: int = 195
const SLOWDOWN: int = 3
const LEFT_START: int = 20
const RIGHT_START: int = 76
const SETTLED_START: int = 146
var diagnostic: bool = false
var output: String = ""
var frames: String = ""
var failures: Array[String] = []

static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
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

func player_beast(b: Node2D) -> Dictionary:
	for item: Dictionary in b.beast_presentation_snapshot().active:
		if int(item.owner_entity_id) == 1: return item
	return {}

func caption(text: String, position: Vector2, size: int) -> Label:
	var label: Label = Label.new()
	label.text = text; label.position = position
	label.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"))
	label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_color",Color("e4ebd6"))
	root.add_child(label)
	return label

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): output = arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frames = arg.trim_prefix("--frames=")
		if arg == "--diagnostic": diagnostic = true
	if output.is_empty(): push_error("External --manifest is required"); quit(2); return
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(640,360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames.is_empty(): DirAccess.make_dir_recursive_absolute(frames)
	var runs: Array[Dictionary] = []
	for index: int in range(CASES.size()):
		var s: Dictionary = CASES[index]
		var build: Dictionary = {"blade":s.blade,"ratchet":"mid","bit":"flat"}
		assert(Parts.validate_build(build) == build)
		var descriptor: Dictionary = Encounters.for_run_event(1,421)
		descriptor.ability_rebalance = true
		descriptor.player_power_ids = ["iron_comet"]
		descriptor.player_power_ranks = {"iron_comet":2}
		descriptor.player_power_mutations = {}
		descriptor.opponent_build = {"blade":"guard","ratchet":"mid","bit":"ball"}
		var b: Node2D = Battle.new()
		root.add_child(b); b.set_process(false); b.set_physics_process(false)
		b.begin_encounter(build,descriptor)
		var launch: int = 0
		while b.battle_status != "battle" and launch < 300:
			b.test_step(Battle.FIXED_DT); launch += 1
		var warmup: int = 0
		while player_beast(b).is_empty() and b.battle_status == "battle" and warmup < 900:
			var p: Dictionary = b.player_entity()
			b.test_step(Battle.FIXED_DT,screen_input(Vector2(0.0,145.0)-Vector2(p.pos)),float(p.cooldown)<=0.0 and float(p.pos.y)<115.0,false)
			warmup += 1
		var start: Dictionary = player_beast(b).duplicate(true)
		if start.is_empty(): failures.append("No actual wall-generated beast for "+str(s.identity))
		var labels: Array[Label] = [
			caption("003A BEAST DIRECTION RESPONSE / "+str(s.name),Vector2(12,14),12),
			caption("LEGAL INITIAL POWER FIXTURE / REAL STEERING + WALL REBOUND",Vector2(12,32),8),
			caption("STEADY TRAVEL",Vector2(12,58),11),
			caption("1/3 SPEED / AUTHORED FRAMES + TIMING / NATIVE MIRROR / NO SAVE WRITES",Vector2(12,342),7)]
		var rows: Array[Dictionary] = []
		var feature_frames: Dictionary = {}
		var left_frames: int = 0
		var right_frames: int = 0
		var live_frames: int = 0
		var response_frames: int = 0
		for tick: int in range(SHOW_TICKS):
			var intent: String = "STEADY TRAVEL" if tick < LEFT_START else ("LEFT TURN" if tick < RIGHT_START else ("RIGHT TURN" if tick < SETTLED_START else "SETTLED TRAVEL"))
			var heading: Vector2 = Vector2(start.get("direction",Vector2(0,-1))) if tick < LEFT_START else (Vector2.LEFT if tick < RIGHT_START else Vector2.UP)
			var brake: bool = tick in range(LEFT_START,LEFT_START+12) or tick in range(RIGHT_START,RIGHT_START+28)
			b.test_step(Battle.FIXED_DT,screen_input(heading),false,brake)
			var item: Dictionary = player_beast(b)
			var state: Dictionary = b.beast_presentation_snapshot()
			var mirror: bool = false
			if not item.is_empty():
				live_frames += 1
				var geometry: Dictionary = b.beasts.draw_geometry_for(item)
				mirror = bool(geometry.mirror)
				if mirror: left_frames += 1
				else: right_frames += 1
				if float(item.orientation_settle) > 0.0: response_frames += 1
			var phase: String = str(item.get("phase",""))
			labels[2].text = intent + (" / BEAST RESPONDING" if not item.is_empty() and float(item.orientation_settle)>0.0 else " / AUTHORED MOTION")
			if phase == "strike": labels[2].text = "REAL CONTACT / AUTHORED STRIKE"
			elif phase == "recovery": labels[2].text = "POWER RESOLVING / AUTHORED RECOVERY"
			elif item.is_empty(): labels[2].text = "RESOLVED / ORDINARY TRAVEL"
			rows.append({"tick":tick,"intent":intent,"time":b.elapsed,"position":b.player_entity().pos,"velocity":b.player_entity().vel,"input":heading,"brake":brake,"beast":item.duplicate(true),"mirror":mirror,"orientation":state.orientations.get(1,{}).duplicate(true)})
			if not diagnostic:
				for slow_tick: int in range(SLOWDOWN):
					b.queue_redraw(); await process_frame
					var feature: String = intent.to_lower().replace(" ","_")
					if phase in ["strike","recovery"]: feature = phase
					elif float(item.get("orientation_settle",0.0)) > 0.0: feature += "_response"
					elif int(item.get("orientation_responses",0)) > 0: feature += "_settled"
					if slow_tick == 0 and not frames.is_empty() and not item.is_empty() and not feature_frames.has(feature):
						await RenderingServer.frame_post_draw
						var image: Image = root.get_texture().get_image()
						image.resize(640,360,Image.INTERPOLATE_NEAREST)
						var path: String = frames.path_join(str(s.identity)+"_"+feature+".png")
						assert(image.save_png(path) == OK)
						feature_frames[feature] = {"path":path,"tick":tick,"beast":item.duplicate(true)}
		if left_frames < 4 or right_frames < 4: failures.append("Both actual beast facings not shown for "+str(s.identity))
		var proof: Dictionary = {"steady_travel":0,"left_response":0,"left_settled":0,"right_response":0,"right_settled":0,"near_stationary":0}
		for row: Dictionary in rows:
			var beast: Dictionary = row.beast
			if str(beast.get("phase","")) != "travel": continue
			var responses: int = int(beast.orientation_responses)
			var settling: bool = float(beast.orientation_settle)>0.0
			if responses == 0: proof.steady_travel += 1
			if responses == 1 and bool(row.mirror): proof.left_response += 1 if settling else 0; proof.left_settled += 0 if settling else 1
			if responses == 2 and not bool(row.mirror): proof.right_response += 1 if settling else 0; proof.right_settled += 0 if settling else 1
			if Vector2(row.velocity).length() < Beasts.ORIENTATION_MIN_SPEED: proof.near_stationary += 1
		if int(proof.steady_travel)<4 or int(proof.left_response)<6 or int(proof.left_settled)<20 or int(proof.right_response)<6 or int(proof.right_settled)<20:
			failures.append("Insufficient actual response/settled travel for "+str(s.identity))
		var summary: Dictionary = {"identity":s.identity,"build":build,"seed":421,"legal_initial_power_fixture":["iron_comet",2],"launch_ticks":launch,"warmup_ticks":warmup,"simulation_ticks":SHOW_TICKS,"movie_frames":SHOW_TICKS*SLOWDOWN,"start":start,"visible_frames":live_frames,"left_frames":left_frames,"right_frames":right_frames,"response_frames":response_frames,"proof":proof,"feature_frames":feature_frames,"power_events":b.powers.events.duplicate(true),"hits":b.hits,"rows":rows,"presentation":b.beast_presentation_snapshot()}
		runs.append(summary)
		print("DIRECTION_CAPTURE ",s.identity," warmup=",warmup," visible=",live_frames," left=",left_frames," right=",right_frames," response=",response_frames)
		for label: Label in labels: label.free()
		b.free()
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(portable({"runs":runs,"failures":failures,"diagnostic":diagnostic,"native_view":[640,360],"fps":60,"slowdown":SLOWDOWN,"collection_opened":false,"main_created":false,"authenticity":"Labelled legal initial Iron Comet rankII loadout for each native blade identity. Normal countdown and wall rebound produce the avatar; only normal controls then turn the actual player. No combat/contact/avatar/state injection after begin_encounter. Every simulation tick is held for three movie frames without altering solver or authored animation timing. No collection/preferences opened."}),"\t")); file.close()
	print("BEAST_DIRECTION_CAPTURE_%s runs=%d" % ["PASS" if failures.is_empty() else "FAIL",runs.size()])
	quit(0 if failures.is_empty() else 1)
