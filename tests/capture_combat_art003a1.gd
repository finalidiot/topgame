extends SceneTree
## Native presentation review. Power scenes are explicitly held visual-state
## fixtures; arena scenes use labelled clock offsets followed by real controls.
## No Main, collection, currency, preferences or player profile is opened.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Identity = preload("res://scripts/power_identity.gd")
const Defence = preload("res://scripts/defence_art.gd")
const Bot = preload("res://tests/rpm_bot.gd")
var mode: String = "powers"
var output: String = ""
var frame_dir: String = ""
var diagnostic: bool = false
var rows: Array[Dictionary] = []
var features: Dictionary = {}
var scenes: Array[Dictionary] = []
var failures: Array[String] = []
var movie_frames: int = 0
var labels: Array[Label] = []

static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is PackedVector2Array:
		var points: Array = []
		for point: Vector2 in value:points.append([point.x,point.y])
		return points
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:result[str(key)]=portable(value[key])
		return result
	if value is Array:
		var array: Array = []
		for item: Variant in value:array.append(portable(item))
		return array
	return value

func _initialize() -> void: call_deferred("run")
func captions(title: String, subtitle: String) -> void:
	for label: Label in labels:label.free()
	labels.clear()
	for item: Dictionary in [{"text":title,"pos":Vector2(8,362),"ink":Color("d8b36d")},{"text":subtitle,"pos":Vector2(8,377),"ink":Color("b2c5c9")}]:
		var label: Label = Label.new();label.text=item.text;label.position=item.pos
		label.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"));label.add_theme_font_size_override("font_size",9)
		label.add_theme_color_override("font_color",item.ink);root.add_child(label);labels.append(label)

func new_battle(family: String = "") -> Node2D:
	var b: Node2D = Battle.new();root.add_child(b);b.set_process(false);b.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1,2026)
	descriptor.starter_id="bastion" if family=="impact_sink" else "vane"
	descriptor.ability_rebalance=true
	if mode=="arena":
		descriptor.player_power_ids=["dead_centre","clutch","impact_sink","gyro_lock"]
		descriptor.player_power_ranks={"dead_centre":3,"clutch":2,"impact_sink":2,"gyro_lock":2}
		descriptor.player_power_mutations={"dead_centre":"bulwark"}
		descriptor.starter_id="bastion"
	elif not family.is_empty():
		descriptor.player_power_ids=[family];descriptor.player_power_ranks={family:2}
		if family=="ghost_circuit":descriptor.player_power_ids=["afterimage"];descriptor.player_power_ranks={"afterimage":3};descriptor.player_power_mutations={"afterimage":"ghost_circuit"}
	b.begin_run(Starters.build_for(str(descriptor.starter_id)),descriptor,2026)
	while b.battle_status!="battle":b.test_step(Battle.FIXED_DT)
	return b

func record(b: Node2D, scene: String, tick: int, feature: String = "") -> void:
	var p: Dictionary = b.player_entity()
	rows.append({"frame":movie_frames,"scene":scene,"tick":tick,"time":b.elapsed,"status":b.battle_status,"position":p.pos,"velocity":p.vel,"rpm":p.rpm,"hunt_stacks":p.get("hunt_stacks",0),"sink":Defence.sink_visual_state(p,b._visual_time),"native_arena":b.arena_presentation.last_snapshot.duplicate(true),"redline_time":p.get("redline_time",0.0),"heat":p.get("redline_heat",0.0),"traces":b.powers.traces.duplicate(true),"hits":b.hits})
	if not diagnostic:
		b.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		if not feature.is_empty() and not features.has(feature):
			var img: Image = root.get_texture().get_image().get_region(Rect2i(0,0,640,360))
			var path: String = frame_dir.path_join(feature+".png")
			if img.save_png(path)!=OK:failures.append("Could not save "+feature)
			features[feature]={"path":path,"movie_frame":movie_frames,"tick":tick}
	movie_frames+=1

func power_review() -> void:
	for family: String in ["redline","predator_line","impact_sink","ghost_circuit","afterimage"]:
		var b: Node2D = new_battle(family)
		b.continuous.pending.clear()
		var p: Dictionary = b.player_entity();p.pos=Vector2.ZERO;p.height=0.0
		var rival: Dictionary = b.entity(2);rival.pos=Vector2(65,-28);rival.height=0.0
		captions("003A.1 / "+family.to_upper().replace("_"," "),"LABELLED VISUAL STATE FIXTURE / NATIVE ART + REAL RENDERER / NO BALANCE CLAIM")
		var path: Array[Vector2] = [Vector2(-70,-25),Vector2(-25,-65),Vector2(35,-52),Vector2(68,-5),Vector2(28,50),Vector2(-35,53),Vector2(-70,-25)]
		Identity.reset_motion()
		for tick: int in range(360):
			var time: float = float(tick)/60.0;b._visual_time=time
			var feature: String = ""
			for index: int in range(b._power_fx.size()-1,-1,-1):
				b._power_fx[index].age+=Battle.FIXED_DT
				if float(b._power_fx[index].age)>=float(b._power_fx[index].duration):b._power_fx.remove_at(index)
			match family:
				"redline":
					p.vel=Vector2(210,-60);p.redline_time=6.0-time;p.redline_heat=clampf(time/5.0,0.0,1.0);p.rpm=1.04+p.redline_heat*.12
					if tick in [0,120,240]:b.add_power_fx("redline_ii",p.pos,p.vel.normalized())
					if tick==140:feature="redline_ring_and_motion"
				"predator_line":
					var angle: float = time*1.25
					p.pos=Vector2(cos(angle)*48,sin(angle)*36)
					p.vel=Vector2(-sin(angle)*160,cos(angle)*125);p.hunt_stacks=3;p.hunt_target=2
					rival.pos=Vector2(62*cos(angle+.35),42*sin(angle+.35))
					Identity.observe_motion(b.fighters,time)
					if tick==120:feature="predator_flow_turn"
				"impact_sink":
					p.sink_capacity=145.0;p.sink_charge=minf(145.0,time/3.0*145.0) if time<4.0 else 0.0
					if tick==240:b.add_power_fx("sink_vent",p.pos,Vector2.RIGHT)
					if tick==90:feature="sink_partial"
					if tick==210:feature="sink_full"
					if tick==246:feature="sink_vent"
				"ghost_circuit":
					p.pos=path[6];p.vel=Vector2(140,-20)
					b.powers.traces.clear()
					var charged: bool = tick>=90
					var trace: Dictionary = {"owner_entity_id":1,"a":path[0],"b":path[6],"points":path,"life":5.5,"max_life":6.0,"rank":3,"mutation":"ghost_circuit","energized":charged,"extended_route":true}
					if charged:trace.circuit_points=PackedVector2Array(path);trace.presentation_circuit_age=time-1.5
					b.powers.traces.append(trace)
					if tick==99:feature="ghost_physical_latch"
					if tick==180:feature="ghost_travelling_current"
				"afterimage":
					p.pos=Vector2(-50+fposmod(time*40.0,100.0),-10+sin(time*1.4)*36)
					p.vel=Vector2(120,cos(time*1.4)*70)
					var trail: Array[Vector2] = []
					for offset: int in range(6):trail.append(p.pos-Vector2(offset*12,offset*4))
					trail.reverse();b.powers.traces.clear()
					b.powers.traces.append({"owner_entity_id":1,"a":trail[0],"b":trail[5],"points":trail,"life":3.8,"max_life":4.6,"rank":2,"mutation":"","energized":false,"extended_route":true})
					if tick==180:feature="afterimage_live_route"
			await record(b,family,tick,feature)
		b.free();scenes.append({"family":family,"frames":360,"held_state_fixture":true,"balance_claim":false})

func arena_review() -> void:
	for scenario: Dictionary in [{"name":"EARLY","time":30.0,"reduced":false},{"name":"BUILDING","time":150.0,"reduced":false},{"name":"MID","time":270.0,"reduced":false},{"name":"LATE","time":450.0,"reduced":false},{"name":"EXTREME","time":580.0,"reduced":false},{"name":"EXTREME / REDUCED FLASHING","time":580.0,"reduced":true}]:
		var b: Node2D = new_battle();b.elapsed=scenario.time;b.reduced_flashing=scenario.reduced
		captions("003A.1 FOUNDRY EIGHT / "+scenario.name,"CLOCK-OFFSET + LEGAL INVESTED BUILD FIXTURE / REAL SOLVER + CONTROLS")
		var live: int = 0;var peak: int = 0
		for tick: int in range(360):
			var controls: Dictionary = Bot.input(b,"defensive",tick)
			b.test_step(Battle.FIXED_DT,controls.direction,controls.burst,controls.brake)
			await record(b,scenario.name,tick,scenario.name.to_lower().replace(" / ","_").replace(" ","_") if tick==120 else "")
			if b.battle_status=="battle":live+=1
			peak=maxi(peak,b.arena_presentation.actual_draw_calls)
		if live<120:failures.append("Arena fixture ended before useful combat observation: "+scenario.name)
		if peak>ArenaBudget():failures.append("Arena presentation draw budget exceeded")
		scenes.append({"stage":scenario.name,"clock_fixture":scenario.time,"frames":360,"live_frames":live,"hits":b.hits,"peak_arena_draw_calls":peak,"status":b.battle_status,"bosses_seen":int(b.continuous.census().get("bosses",0)),"balance_claim":false});b.free()

func ArenaBudget() -> int:return 17
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="):frame_dir=arg.trim_prefix("--frames=")
		if arg=="--diagnostic":diagnostic=true
	if output.is_empty() or mode not in ["powers","arena"]:push_error("Supply external --manifest and mode");quit(2);return
	root.size=Vector2i(640,400);root.content_scale_size=Vector2i(640,400);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty():DirAccess.make_dir_recursive_absolute(frame_dir)
	if mode=="powers":await power_review()
	else:await arena_review()
	var report: Dictionary = {"task":"003A.1 final combat art","mode":mode,"failures":failures,"scenes":scenes,"rows":rows,"features":features,"fps":60,"movie_frames":movie_frames,"native_gameplay":[640,360],"native_caption_canvas":[640,400],"main_created":false,"collection_opened":false,"diagnostic":diagnostic,"authenticity":"Powers are explicitly labelled held visual-state fixtures, drawn by real production renderers/native art. Arena stages are labelled presentation clock offsets with legal invested initial build and ordinary sampled controls through the real fixed solver. No natural power activation, survival or balance claim. No save/profile/preferences/currency opened."}
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Could not write review manifest");quit(2);return
	file.store_string(JSON.stringify(portable(report),"\t"));file.close()
	print("COMBAT_ART_CAPTURE_%s mode=%s frames=%d" % ["PASS" if failures.is_empty() else "FAIL",mode,movie_frames]);quit(0 if failures.is_empty() else 1)
