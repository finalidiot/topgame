extends SceneTree
## Pure policy stress complements actual Main/menu/input/native fixture evidence.
const Layout = preload("res://scripts/combat_hud_layout.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var observations: Array[Dictionary] = []
	for fixture: Dictionary in [
		{"size":Vector2i(1280,720),"safe":Rect2i(0,0,1280,720)},
		{"size":Vector2i(2160,1080),"safe":Rect2i(0,0,2160,1080)},
		{"size":Vector2i(2340,1080),"safe":Rect2i(0,0,2340,1080)},
		{"size":Vector2i(2400,1080),"safe":Rect2i(0,0,2400,1080)},
		{"size":Vector2i(2800,1080),"safe":Rect2i(96,20,2656,1012)},
		{"size":Vector2i(1280,720),"safe":Rect2i(64,30,1152,630)},
		{"size":Vector2i(600,360),"safe":Rect2i(20,16,560,310)},
		{"size":Vector2i(800,480),"safe":Rect2i(0,0,800,480)}]:
		var projection: Dictionary = Layout.mobile_canvas(fixture.size,fixture.safe)
		var layout: Dictionary = Layout.responsive(Vector2(projection.canvas_size),true,projection.safe_rect)
		var pixels: Rect2 = projection.presentation_pixels
		check(pixels.position==Vector2.ZERO and pixels.end.x>=fixture.size.x and pixels.end.y>=fixture.size.y,"Full physical coverage "+str(fixture.size))
		check(projection.clipped_overscan_pixels.x<float(projection.ui_scale)+0.001 and projection.clipped_overscan_pixels.y<float(projection.ui_scale)+0.001,"Only bounded raster overscan")
		check(layout.arena_rect.size.is_equal_approx(Vector2(640,360)*float(layout.arena_scale)),"Uniform canonical arena")
		for key: String in layout.regions:
			check(Rect2(layout.safe_rect).grow(0.01).encloses(layout.regions[key]),"Safe HUD region "+key+" "+str(fixture))
		for key: String in ["arena_rect","burst_rect","brake_rect","steering_rect"]:
			check(Rect2(layout.safe_rect).grow(0.01).encloses(layout[key]),"Safe physical interaction "+key)
		check(not Rect2(layout.burst_rect).intersects(layout.brake_rect),"Independent thumb buttons")
		check(not Rect2(layout.arena_rect).intersects(layout.burst_rect) and not Rect2(layout.arena_rect).intersects(layout.brake_rect),"Actions occupy a useful side rail")
		var menu: Rect2 = Rect2(layout.menu_origin,Vector2(640,360)*float(layout.menu_scale))
		check(Rect2(layout.safe_rect).grow(0.01).encloses(menu),"Whole authored menu fits safe area")
		check(layout.world_dimensions_changed==false,"No world coordinate changes")
		if layout.mobile_wide:
			for pair: Array in [["clock","pause"],["pause","state_left"],["state_left","impact"],["impact","power_note"],["power_note","powers"],["powers","rerolls"],["state_right","burst"],["burst","progress"],["progress","burst_button"],["burst_button","brake_button"]]:
				check(not Rect2(layout.regions[pair[0]]).intersects(layout.regions[pair[1]]),"Distinct side decision regions "+str(pair))
		observations.append({"fixture":fixture,"projection":projection,"layout":layout})
	var report: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
	if not report.is_empty():
		if not report.is_absolute_path() or not report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/") or FileAccess.file_exists(report): quit(2); return
		var file := FileAccess.open(report,FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"Pure presentation policy; native UI/simulation proof is separate."},"\t")); file.close()
	print("MOBILE_CANVAS_POLICY_003A2_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
