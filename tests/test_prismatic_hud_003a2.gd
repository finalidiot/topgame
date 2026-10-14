extends SceneTree
## Legal five-family fixtures exercise the actual state raster and safe transform.
## Native capture uses production Main/world with declared initial ownership.
const Menus = preload("res://scripts/menus.gd")
const Layout = preload("res://scripts/combat_hud_layout.gd")
const FAMILY_IDS: Array[String] = ["dead_centre","impact_sink","redline","orbit_drive","prismatic_current"]
const BUILD: Dictionary = {"blade":"lopsider","ratchet":"flywheel","bit":"needle"}
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
var report: String = ""
var images: String = ""
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var menus: Control

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for tick: int in range(3): await process_frame
func portable(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
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

func stats(emphasis: int) -> Dictionary:
	var bonuses: Array[String] = ["IMP +10","SPD +8","WBL -15","DRN -8"]
	return {"player_name":"CUSTOM","player_rpm":0.82,"player_rpm_value":7380,"enemy_name":"LIVE PRESSURE","status":"battle","is_run":true,"continuous_run":true,
		"elapsed":24.0,"level":11,"xp":35,"xp_threshold":120,"burst_cooldown":2.7,"rerolls":2,
		"owned_power_ids":FAMILY_IDS.duplicate(),"power_ranks":{"dead_centre":2,"impact_sink":2,"redline":2,"orbit_drive":2,"prismatic_current":2},
		"run_state":{"director":true,"threat_number":12,"threats_cleared":11,"phase":"active","next_at":27.0,"callout":"","calm":false,"census":{"full":3,"active_full":3,"small":5,"pressure":8.5},"limits":{"tier":2,"budget":12.0}},
		"power_state":{"anchor":{"owned":true,"strength":0.76,"stress":0.72,"safe_stress":0.3,"overload_stress":0.8},
			"sink":{"owned":true,"stored":115.0,"capacity":150.0,"ratio":115.0/150.0},
			"redline":{"owned":true,"active":true,"heat":0.7,"excess":0.0},"orbit":{"owned":true,"drive":0.9,"drifting":true},
			"base_powers":{"owned":true,"state":emphasis,"emphasis":["IMPACT","SPEED","WOBBLE","EFFICIENCY"][emphasis],"bonus_label":bonuses[emphasis],"remaining":5.6}}}

func layout_case(name: String, canvas: Vector2, mobile: bool, safe: Rect2) -> void:
	menus.mobile_hud = mobile
	menus.set_presentation_canvas(canvas,safe)
	var presentation: Dictionary = Layout.responsive(canvas,mobile,safe)
	for emphasis: int in range(4):
		var supplied: Dictionary = stats(emphasis)
		var before: Dictionary = supplied.duplicate(true)
		menus.show_hud(supplied)
		await settle()
		var raster: Dictionary = menus._hud.state_meters.diagnostic_snapshot()
		# The immutable pre-fix renderer has no rectangle diagnostic and paints
		# every row at66px. This explicit fallback lets the same regression case
		# record its real older overlap without patching historical production.
		if not raster.has("row_rects"):
			raster["legacy_geometry_reader"] = true
			raster["row_rects"] = {"left":[],"right":[]}
			for side: String in ["left","right"]:
				for index: int in range(raster.rows[side].size()):
					raster.row_rects[side].append(Rect2(raster[side]+Vector2(0,index*float(raster.row_height)),Vector2(raster.width,66)))
		check(raster.rows.left.size()==2 and raster.rows.right.size()==3,"All five legal owned meters are present: "+name)
		check(supplied==before and raster.state==supplied.power_state,"State raster reads do not alter timers/modifiers: "+name)
		check(raster.row_rects.right[2].size.y==36 and raster.row_rects.right[2].position.y==raster.right.y+144,"Only Prism has a compact third row at the existing cadence: "+name)
		var local: Dictionary = menus._hud_layout
		for side: String in ["left","right"]:
			var boxes: Array = raster.row_rects[side]
			check(boxes.size()==raster.rows[side].size(),"Diagnostic reports actual painted boxes: "+name)
			for index: int in range(boxes.size()):
				var box: Rect2 = boxes[index]
				var global_box: Rect2 = menus._hud.state_meters.get_global_transform()*box
				check(local.regions["state_"+side].encloses(box),"Painted meter fits its reserved native rail: "+name)
				check(safe.grow(.1).encloses(global_box),"Painted meter remains inside the actual safe surface: "+name)
				check(not global_box.intersects(presentation.arena_rect),"Five-meter raster remains outside the arena: "+name)
				for key: String in ["burst_panel","burst","xp_panel","pause_button","impact_confirmation"]:
					check(not global_box.intersects(menus._hud[key].get_global_rect()),"Painted state meter leaves permanent HUD control clear: "+name+" / "+key)
				if mobile:
					check(not global_box.intersects(presentation.burst_rect) and not global_box.intersects(presentation.brake_rect),"Painted state meter leaves both actual touch actions clear: "+name)
				if raster.rows[side][index].id!="prismatic_current":
					check(box.size.y==66 and box.position.y==raster[side].y+index*72,"Existing four full meters retain their raster geometry: "+name)
		var font: Font = menus._hud.state_meters.get_theme_default_font()
		for line: Array in [["PRISM",raster.width-24],[str(raster.rows.right[2].detail)+"%",raster.width-10]]:
			check(font.get_string_size(line[0],HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=line[1],"Actual Prismatic title and each bonus fit without clipped characters: "+name)
		check(float(raster.rows.right[2].bars[0].value)==0.7,"Thin Prism countdown preserves the actual remaining duration ratio: "+name)
		if emphasis==0: observations.append({"case":name,"presentation":presentation,"raster":raster})
	var four: Dictionary = stats(0)
	four.power_state.erase("base_powers")
	menus.show_hud(four)
	var original: Dictionary = menus._hud.state_meters.diagnostic_snapshot()
	check(original.rows.left.size()+original.rows.right.size()==4 and original.rows.left[0].status=="HIGH LOAD" and original.rows.right[0].active,"Original four meters retain their status and activation information: "+name)
	if not mobile:
		check(presentation.arena_rect==Rect2(80,60,640,360) and presentation.regions.burst==Rect2(86,450,224,28),"Native desktop arena and Burst meter positions remain exact")
	elif canvas==Vector2(800,480):
		check(presentation.arena_rect==Rect2(80,60,640,360) and presentation.burst_rect==Rect2(724,294,70,52) and presentation.brake_rect==Rect2(724,354,70,52),"Native mobile world and both touch rectangles remain exact")

func capture_production() -> void:
	if images.is_empty(): return
	menus.free()
	root.size=Vector2i(1200,480)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	var game := QuietMain.new()
	game.smoke_mode=true
	var profile_root: String = report.get_base_dir().get_base_dir().path_join("temp/prismatic_hud_"+report.get_file().get_basename())
	check(not DirAccess.dir_exists_absolute(profile_root),"Native capture has a fresh isolated profile")
	DirAccess.make_dir_recursive_absolute(profile_root)
	game.collection_path=profile_root.path_join("collection.json")
	game.preferences_path=profile_root.path_join("preferences.cfg")
	game.set_mobile_presentation(Vector2(1200,480),Rect2(24,8,1136,464))
	root.add_child(game)
	game.set_process(false)
	game.mode="run"
	game.run_context.start(BUILD,7341,"custom")
	game.run_context._owned_power_ids.assign(FAMILY_IDS)
	game.run_context._power_ranks={"dead_centre":2,"impact_sink":2,"redline":2,"orbit_drive":2,"prismatic_current":2}
	game.run_context._progression.level=11
	game._launch_run_encounter()
	game.battle.set_physics_process(false)
	# Advance the normal countdown with the actual solver, then hold this
	# initial legal loadout still only while obtaining review pixels.
	for tick: int in range(210): game.battle.test_step(game.battle.FIXED_DT,Vector2.ZERO,false,false)
	game.touch_controls.show_controls=true
	game.touch_controls.set_enabled(true)
	game.battle._emit_hud()
	game._refresh_window_presentation()
	check(game.combat_frame.visible and game.battle.battle_status=="battle","Native review captures the visible production arena after its real countdown")
	await settle()
	await RenderingServer.frame_post_draw
	var path: String = images.path_join("android_safe_five_meters.png")
	check(root.get_texture().get_image().save_png(path)==OK,"Production Main/world safe mobile five-meter native pixels captured")
	var actual: Dictionary = game.menus._hud.state_meters.diagnostic_snapshot()
	check(actual.rows.left.size()+actual.rows.right.size()==5 and game.combat_viewport.size==Vector2i(640,360),"Native production capture contains all five actual owned meters and canonical world")
	observations.append({"case":"native_production_mobile_capture","image":path,"source":"production Main / Battle / Menus / TouchControls","canvas_pixels":root.get_texture().get_image().get_size(),"presentation":game.window_presentation_snapshot(),"raster":actual,"declared_initial_ownership":FAMILY_IDS,"normal_solver_steps_before_capture":210,"gameplay_running":false,"earned_acquisition":false,"physical_android":false,"profile":profile_root})
	game.free()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
		if arg.begins_with("--images="): images=arg.trim_prefix("--images=")
	if not report.is_absolute_path() or FileAccess.file_exists(report): push_error("Fresh external report required"); quit(2); return
	if not images.is_empty():
		if DisplayServer.get_name()=="headless" or not images.is_absolute_path() or DirAccess.dir_exists_absolute(images): quit(2); return
		DirAccess.make_dir_recursive_absolute(images)
	root.size=Vector2i(1200,480)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	menus=Menus.new(); root.add_child(menus)
	await settle()
	for row: Array in [["native_desktop",Vector2(800,480),false,Rect2(0,0,800,480)],
		["native_mobile",Vector2(800,480),true,Rect2(0,0,800,480)],
		["wide_android_safe",Vector2(1200,480),true,Rect2(24,8,1136,464)],
		["narrow_mobile_safe",Vector2(720,432),true,Rect2(8,12,704,408)]]:
		await layout_case(row[0],row[1],row[2],row[3])
	await capture_production()
	var file: FileAccess=FileAccess.open(report,FileAccess.WRITE)
	check(file!=null,"Fresh read-only HUD report opens")
	if file!=null: file.store_string(JSON.stringify(portable({"checks":checks,"failures":failures,"observations":observations,"scope":"Actual painted five-meter geometry, font measures and public-state purity with all four Prismatic emphases. Native production Main/world capture uses declared legal initial ownership and paused physics; it is a Windows-rendered Android-layout fixture, not earned acquisition or phone device acceptance."}),"\t")); file.close()
	if is_instance_valid(menus): menus.free()
	print("PRISMATIC_HUD_003A2_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
