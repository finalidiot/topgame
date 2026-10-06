extends SceneTree
## Deterministic bounded cosmetic contracts; no live-pressure balance claim.
const Arena = preload("res://scripts/arena_presentation.gd")
var checks: int = 0
var failures: int = 0
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(Arena.stage_for(-1.0)==0 and Arena.stage_for(INF)==0,"Malformed cosmetic clocks stay in a safe quiet stage")
	for stage: int in range(5):
		var time: float = [0.0,90.0,210.0,390.0,540.0][stage]
		check(Arena.stage_for(time)==stage,"Exact elapsed-stage threshold is stable")
		var normal: Dictionary = Arena.presentation_snapshot(time,false,false,1.0)
		var safe: Dictionary = Arena.presentation_snapshot(time,false,true,1.0)
		var mobile: Dictionary = Arena.presentation_snapshot(time,false,false,0.60)
		check(normal.stage_id==stage and normal.stage==Arena.STAGES[stage],"Snapshot describes the same actual stage")
		check(safe.motion_rate==normal.motion_rate and safe.fixture_alpha==normal.fixture_alpha and safe.perimeter_active==normal.perimeter_active,"Reduced Flashing preserves escalation through machinery motion and warm lighting state")
		check(safe.spark_fixture_limit==0 and not safe.warning_animation,"Reduced Flashing removes grit sparks and pulsing warning lamps")
		check(mobile.maximum_draw_calls==14 and mobile.spark_fixture_limit<=2,"Android cosmetic work remains bounded below desktop")
		check(normal.maximum_draw_calls==17 and normal.spark_fixture_limit<=4 and normal.nodes_created==0 and normal.particles_created==0,"Maximum presentation allocates no live cosmetic objects")
		check(normal.gameplay_writes==0 and normal.floor_hazard_shapes==0 and normal.peripheral_only,"Decorative escalation creates no fake floor telegraphs or mechanics")
		check(normal==Arena.presentation_snapshot(time,false,false,1.0),"Repeated snapshot consumes no randomness and never drifts")
	check(Arena.stage_for(10.0,true)==4,"Actual boss pressure can request the extreme authored equipment state")
	for name: String in ["machinery","vent","display_panel","warning_bank","perimeter","sparks"]:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Arena.ROOT+name+".json"))
		check(meta.native_pixels and meta.presentation_only and meta.filter=="nearest","Runtime fixture keeps native authored nearest pixels")
		check(meta.layers.size()>=2 and not meta.tags.is_empty() and meta.pivot.size()==2,"Master metadata retains named layers, tags and floor/hardware pivots")
		for tag: String in meta.tags:
			var span: Dictionary = meta.tags[tag]
			var seen: Dictionary = {}
			for tick: int in range(500):
				var frame: int = Arena.frame_for(name,tag,float(tick)/60.0)
				check(frame>=int(span.from) and frame<=int(span.to),"Atlas animation stays inside its authored tag")
				seen[frame]=true
			check(seen.size()==int(span.to)-int(span.from)+1,"Authored frame timings expose every saved key")
			check(Arena.frame_for(name,tag,500.0,true)==int(span.from),"Accessible static key remains stable at any time")
	check(Arena.frame_for("machinery","not_a_tag",0.0)==-1,"Unknown fixture animation cannot read outside the atlas")
	var code: String = FileAccess.get_file_as_string("res://scripts/arena_presentation.gd")
	check(not "Random" in code and not "randf" in code and not "Timer.new" in code and not "add_child" in code,"Cosmetic logic never consumes simulation RNG or spawns background nodes")
	print("ARENA_ESCALATION_%s checks=%d failures=%d" % ["PASS" if failures==0 else "FAIL",checks,failures]);quit(1 if failures else 0)
