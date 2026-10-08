extends SceneTree
## State-linked mechanical presentation and native artist metadata contracts.
const Identity = preload("res://scripts/power_identity.gd")
const Visuals = preload("res://scripts/power_visuals.gd")
const Defence = preload("res://scripts/defence_art.gd")
const Art = preload("res://scripts/combat_motion_art.gd")
const Arena = preload("res://scripts/arena_presentation.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(label)

func run() -> void:
	for family: String in ["venue_lights","power_motion","redline_ring"]:
		var m: Dictionary = Art.info(family)
		check(not m.is_empty() and m.layers.size()==3,"Native accents retain three editable component layers")
		var pivot: Vector2 = Vector2.ZERO if family=="venue_lights" else (Vector2(64,64) if family=="redline_ring" else Vector2(24,16))
		check(Vector2(m.pivot[0],m.pivot[1])==pivot,"Native attachment pivot agrees with venue or local socket")
		check(m.frame_count==m.durations_ms.size() and m.source.ends_with(".aseprite"),"Native frame timeline has one millisecond duration per key")
		var texture: Texture2D = load(str(m.texture))
		check(texture!=null and texture.get_width()==int(m.columns)*int(m.cell[0]),"Imported atlas has native cell dimensions")
		for tag: String in m.tags:
			var span: Dictionary = m.tags[tag]
			var seen: Dictionary = {}
			for tick: int in range(180):
				var key: int = Art.frame(family,tag,float(tick)/180.0,true)
				check(key>=int(span.from) and key<=int(span.to),"Native animation remains inside authored tag")
				seen[key]=true
			check(seen.size()==int(span.to)-int(span.from)+1,"Authored milliseconds expose every motion key")
		check(Art.frame(family,"unknown",0.0)==-1,"Unknown native tag cannot index unrelated art")
	for family: String in ["redline","afterimage"]:
		var cards: Dictionary = Identity.family_info(family).cards
		check(Vector2(cards.cell[0],cards.cell[1])==Vector2(64,64) and Vector2(cards.pivot[0],cards.pivot[1])==Vector2(32,32) and cards.frame_count==48,"Corrected cards preserve native size/pivot/four twelve-key stories")
		check(cards.layers.size()==(5 if family=="redline" else 6),"Corrected cards retain original editable layers")
		check(cards.durations_ms.size()==48 and cards.tags.size()==4,"Corrected cards retain complete millisecond timelines/tags")
	check(Identity.art("afterimage").card_texture.ends_with("afterimage_cards.png") and Identity.art("ghost_circuit").family=="afterimage","Afterimage and Ghost retain independent canonical identity mapping")
	check(Defence.art("impact_sink").family=="impact_sink","Impact Sink canonical name and family remain unchanged")
	var empty: Dictionary = Defence.sink_visual_state({"sink_charge":0.0,"sink_capacity":90.0},1.0)
	var half: Dictionary = Defence.sink_visual_state({"sink_charge":45.0,"sink_capacity":90.0},1.0)
	var full: Dictionary = Defence.sink_visual_state({"sink_charge":90.0,"sink_capacity":90.0},1.0)
	check(empty.state=="EMPTY" and half.state=="PARTIAL" and full.state=="FULL","Stored force controls empty/partial/full presentation")
	check(float(full.alpha)>float(half.alpha) and int(full.stage)>int(half.stage),"Loaded native structure is more developed than partial storage")
	var compress: Dictionary = Defence.sink_visual_state({"sink_charge":72.0,"sink_capacity":90.0},0.0)
	var release: Dictionary = Defence.sink_visual_state({"sink_charge":72.0,"sink_capacity":90.0},0.35)
	check(compress.stage!=release.stage and compress.alpha!=release.alpha,"Equal stored force animates components rather than holding a static key")
	var fighter: Dictionary = {"entity_id":1,"power_ranks":{"predator_line":2},"pos":Vector2.ZERO,"vel":Vector2(100,0),"hunt_stacks":3,"outcome":""}
	var target: Dictionary = {"entity_id":2,"pos":Vector2(80,0),"outcome":""}
	Identity.reset_motion()
	for tick: int in range(20):
		fighter.pos=Vector2(tick*3,tick%4)
		var before: Dictionary = fighter.duplicate(true)
		Identity.observe_motion([fighter,target],float(tick)*0.06)
		check(before==fighter,"Presentation history observes actors without writes")
		check(Identity.motion_history[1].size()<=Identity.MOTION_POINTS,"Motion history remains bounded")
	var plan: Dictionary = Identity.predator_plan(fighter,target,1.14)
	check(plan.active and plan.points.size()>2,"Active hunting uses recent actual motion samples")
	check(plan.points[plan.points.size()-1]==fighter.pos,"Pursuit wake attaches to actual latest top contact")
	check(plan.flow!=Identity.predator_plan(fighter,target,1.28).flow,"Hunting current advances along the motion lane")
	var state_before: Dictionary = Identity.motion_history.duplicate(true)
	Identity.observe_motion([fighter,target],1.14)
	check(Identity.motion_history==state_before,"Repeated paused timestamp never appends samples")
	fighter.vel=Vector2.ZERO
	check(not Identity.predator_plan(fighter,target,1.14).active,"Stationary top cannot display artificial hunting lines")
	fighter.vel=Vector2(100,0);fighter.pos=Vector2(150,140)
	Identity.observe_motion([fighter,target],1.20)
	check(Identity.motion_history[1].size()==1,"Teleport clears stale route samples")
	Identity.observe_motion([fighter,target],0.0)
	check(Identity.motion_history[1].size()==1 and Identity.motion_clock==0.0,"Clock rollback begins a fresh presentation route")
	fighter.outcome="spin_out";Identity.observe_motion([fighter,target],0.06)
	check(Identity.motion_history.is_empty(),"Retired top clears bounded presentation history")
	var owner_fixtures: Array[Dictionary] = []
	for id: int in range(30):owner_fixtures.append({"entity_id":id+10,"power_ranks":{"predator_line":1},"pos":Vector2(id,0),"outcome":""})
	Identity.observe_motion(owner_fixtures,0.12)
	check(Identity.motion_history.size()==Identity.MOTION_OWNERS,"Presentation owners remain bounded in dense combat")
	Identity.reset_motion()
	var path: PackedVector2Array = PackedVector2Array([Vector2(10,10),Vector2(70,10),Vector2(80,50),Vector2(20,60),Vector2(10,10)])
	var initial: Dictionary = Visuals.circuit_motion_plan(path,0.10)
	var moved: Dictionary = Visuals.circuit_motion_plan(path,0.30)
	check(initial.currents.size()==3 and moved.currents.size()==3,"Physical closure uses a bounded three travelling currents")
	check(initial.currents!=moved.currents,"Closed circuit currents travel along actual polygon")
	for current: Dictionary in moved.currents:
		var index: int = int(current.segment)
		check(Geometry2D.get_closest_point_to_segment(current.to,path[index],path[index+1]).distance_to(current.to)<0.001,"Current is on the true recorded circuit segment")
	check(Visuals.circuit_motion_plan(PackedVector2Array(),1.0).currents.is_empty(),"Invalid path generates no fictitious circuit")
	for stage: int in range(5):
		var snap: Dictionary = Arena.presentation_snapshot(float([0,90,210,390,540][stage]),false,true)
		check(snap.display_panel_draw_calls==0 and snap.warning_bank_draw_calls==0 and snap.pressure_source=="HUD Director census","No Director readout masquerades as venue machinery")
		check(snap.spark_fixture_limit==0 and snap.lighting_source.contains("native venue_lights"),"Reduced Flashing keeps steady authored venue colour without sparks")
	check(Visuals.redline_presentation("redline_ii").ring and Visuals.redline_presentation("redline_heat").particle_cels==0,"Redline preserves accepted expanding ring and suppresses fragment clouds")
	print("COMBAT_ART003A1_%s checks=%d failures=%d" % ["PASS" if failures==0 else "FAIL",checks,failures])
	quit(0 if failures==0 else 1)
