extends SceneTree
## The actual production Shell/Main path receives root-screen ScreenTouch/Drag.
## Display/cutout, initial Duel and isolated save are declared Windows fixtures;
## these checks establish projection/ownership, not physical Android acceptance.
const Shell = preload("res://scripts/mobile_shell.gd")
const Battle = preload("res://scripts/battle.gd")
const AndroidQA = preload("res://scripts/android_qa.gd")
class FixtureShell extends "res://scripts/mobile_shell.gd":
	var fixture_display: Vector2i = Vector2i(1920,1080)
	var fixture_safe: Rect2i = Rect2i(0,0,1920,1080)
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass
	func _fit() -> void: apply_display_layout(fixture_display,fixture_safe)
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
var report: String = ""
var profile: String = ""
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var events: Array[Dictionary] = []
var shell: FixtureShell
var game: QuietMain

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func settle() -> void:
	await process_frame; await process_frame; await process_frame
func screen_touch(index: int, point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index=index; event.position=shell.surface.get_global_transform_with_canvas()*point; event.pressed=down
	events.append({"type":"touch","index":index,"canvas":point,"screen":event.position,"pressed":down})
	Input.parse_input_event(event)
	await settle()
func screen_drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index=index; event.position=shell.surface.get_global_transform_with_canvas()*point
	events.append({"type":"drag","index":index,"canvas":point,"screen":event.position})
	Input.parse_input_event(event)
	await settle()
func layout(size: Vector2i, safe: Rect2i) -> void:
	shell.fixture_display=size; shell.fixture_safe=safe
	root.size=size
	shell.apply_display_layout(size,safe)
	await settle()
	game._process(0.0)
func live() -> void:
	game._start_battle("duel"); game.battle.set_physics_process(false)
	for i: int in range(240):
		if game.battle.battle_status=="battle": break
		game.battle.test_step(Battle.FIXED_DT)
	game._process(0.0)
	check(game.battle.battle_status=="battle" and game.touch_controls.enabled,"Declared Duel finishes actual countdown before projected contacts")
func pose() -> Dictionary:
	var player: Dictionary=game.battle.player_entity()
	return {"pos":player.pos,"vel":player.vel,"rpm":player.rpm,"elapsed":game.battle.elapsed,
		"power_time":game.battle.powers.time,"roster_time":game.battle.roster.time,"ecology_time":game.battle.roster.ecology.time}
func rect_matches(values: Array, actual: Rect2) -> bool:
	if values.size()!=4:return false
	var expected: Array=[actual.position.x,actual.position.y,actual.size.x,actual.size.y]
	for i: int in range(4):
		if absf(float(values[i])-float(expected[i]))>0.0001:return false
	return true
func capture_state(label: String) -> Dictionary:
	var folder: String=report.get_base_dir().path_join(report.get_file().get_basename()+"_"+label)
	AndroidQA.report(game,{"capture_dir":folder,"run_id":"000000000000000000000000000003a2"})
	var state: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("state.json")))
	check(state.canvas_size==[float(shell.game_view.size.x),float(shell.game_view.size.y)],"Actual QA state records the dynamic SubViewport canvas")
	check(rect_matches(state.arena_rect,Rect2(game.combat_frame.position,game.combat_frame.size)),"Actual QA state records the displayed arena rectangle within native float precision")
	var touch: Dictionary=game.touch_controls.layout_snapshot()
	check(rect_matches(state.action_bounds.burst,touch.burst_rect),"Actual QA Burst bounds match controller hit geometry within native float precision")
	state["fixture_state_path"]=folder.path_join("state.json")
	return state
func exercise(size: Vector2i,safe: Rect2i,label: String) -> void:
	await layout(size,safe)
	await live()
	var presentation: Dictionary=game.window_presentation_snapshot()
	var touch: Dictionary=game.touch_controls.layout_snapshot()
	check(touch.canvas_size==Vector2(shell.game_view.size) and touch.safe_rect==presentation.safe_rect and touch.arena_rect==presentation.arena_rect,"Main configures Touch with the same full-display safe presentation")
	check(game.combat_viewport.size==Vector2i(640,360),"World viewport remains canonical640x360")
	check(is_equal_approx(game.combat_frame.size.x/640.0,game.combat_frame.size.y/360.0),"World presentation uses one uniform scale")
	var start: Vector2=touch.steering_rect.get_center()
	await screen_touch(0,start,true)
	check(game.touch_controls.steering_finger==0 and game.touch_controls.origin.is_equal_approx(start),"Physical root touch projects to its exact configured origin")
	await screen_drag(0,start+Vector2(30,0))
	var prepared: Vector2=game.touch_controls.direction
	check(prepared.is_equal_approx(Vector2(0.5,0)),"Physical root drag retains canonical analogue magnitude")
	await screen_touch(1,touch.burst_rect.get_center(),true)
	await screen_touch(2,touch.brake_rect.get_center(),true)
	check(game.touch_controls.owners.size()==3 and game.touch_controls.action_down("burst") and game.touch_controls.action_down("brake") and game.touch_controls.direction.is_equal_approx(prepared),"Actual shell forwards steering/Burst/Brake as independent fingers")
	await screen_drag(1,start)
	check(game.touch_controls.steering_finger==0 and game.touch_controls.action_down("burst") and game.touch_controls.direction==prepared,"Projected action drag cannot become steering")
	var before: Dictionary=pose()
	game.battle._physics_process(Battle.FIXED_DT)
	check(game.battle.player_entity().cooldown>3.9 and float(game.battle.player_entity().rpm)<float(before.rpm)-0.01,"Projected Burst reaches actual solver and pays ordinary RPM")
	await screen_touch(1,touch.burst_rect.get_center(),false)
	check(game.touch_controls.action_down("brake") and game.touch_controls.direction==prepared,"Independent root release leaves steering and Brake owned")
	await screen_touch(2,touch.brake_rect.get_center(),false)
	await screen_touch(0,start+Vector2(30,0),false)
	check(game.touch_controls.owners.is_empty() and game.touch_controls.direction==Vector2.ZERO,"All projected releases restore neutral")
	if touch.safe_rect.position.x>0:
		await screen_touch(4,Vector2(touch.safe_rect.position.x*0.5,start.y),true)
		check(game.touch_controls.owners.is_empty(),"Physical cutout strip cannot acquire steering or actions")
		await screen_touch(4,Vector2.ZERO,false)
	observations.append({"label":label,"display":size,"physical_safe":safe,"shell":shell.layout_snapshot(),"presentation":presentation,"qa_state":capture_state(label)})
func rotation_and_pause() -> void:
	var touch: Dictionary=game.touch_controls.layout_snapshot()
	var start: Vector2=touch.steering_rect.get_center()
	await screen_touch(0,start,true); await screen_drag(0,start+Vector2(30,0))
	await screen_touch(1,touch.burst_rect.get_center(),true)
	var before: Dictionary=pose()
	await layout(Vector2i(1600,1200),Rect2i(32,20,1548,1160))
	check(pose()==before,"Resize/cutout configuration does not advance or alter actual body/resource clocks")
	check(game.touch_controls.owners.is_empty() and game.touch_controls.direction==Vector2.ZERO,"Actual shell resize cancels old coordinate ownership")
	touch=game.touch_controls.layout_snapshot(); start=touch.steering_rect.get_center()
	await screen_drag(0,start+Vector2(52,0)); await screen_touch(0,start,true); await screen_touch(1,touch.burst_rect.get_center(),true)
	check(game.touch_controls.owners.is_empty(),"Old projected contacts stay blocked until release after rotation")
	await screen_touch(0,start,false); await screen_touch(1,start,false)
	await screen_touch(0,start,true); await screen_drag(0,start+Vector2(30,0))
	check(game.touch_controls.direction.is_equal_approx(Vector2(0.5,0)),"Fresh contact restores steering in new physical projection")
	game._pause(); game._process(0.0)
	check(game.touch_controls.owners.is_empty() and not game.touch_controls.enabled,"Actual pause clears and disables touch")
	game._resume(); game._process(0.0)
	check(game.battle.battle_status=="reentry" and game.touch_controls.enabled,"Actual resume opens safe preparation countdown")
	await screen_touch(0,start,true)
	check(game.touch_controls.owners.is_empty(),"Pause-held steering cannot become a fresh resume contact")
	await screen_touch(0,start,false); await screen_touch(0,start,true); await screen_drag(0,start+Vector2(30,0))
	before=pose()
	for i: int in range(74):game.battle.test_step(Battle.FIXED_DT,game.touch_controls.direction,true,true)
	check(pose()==before and game.battle.battle_status=="reentry","Projected prepared steering leaves real simulation and resource clocks frozen before GO")
	for i: int in range(3):
		if game.battle.battle_status=="battle":break
		game.battle.test_step(Battle.FIXED_DT,game.touch_controls.direction)
	check(game.battle.battle_status=="battle" and game.battle._burst_buffer==0,"Fresh projected resume reaches GO without buffered action")
	await screen_touch(0,start,false)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
		if arg.begins_with("--profile="):profile=arg.trim_prefix("--profile=")
	if not report.is_absolute_path() or not report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/") or FileAccess.file_exists(report) or not profile.is_absolute_path() or not profile.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/temp/"):
		push_error("Fresh external003A.2 report/profile required");quit(1);return
	for suffix: String in ["",".bak",".preferences.cfg"]:
		if FileAccess.file_exists(profile+suffix):push_error("Existing profile preserved");quit(1);return
	shell=FixtureShell.new();root.add_child(shell)
	game=QuietMain.new();game.smoke_mode=true;game.collection_path=profile
	shell.mount_mobile_surface(game)
	await settle()
	for fixture: Array in [[Vector2i(1920,1080),Rect2i(0,0,1920,1080),"16_9"],
		[Vector2i(2408,1080),Rect2i(90,24,2298,1032),"wide_cutout"],
		[Vector2i(2560,1080),Rect2i(72,0,2448,1080),"ultrawide"],
		[Vector2i(1600,1200),Rect2i(0,0,1600,1200),"tablet"]]:await exercise(fixture[0],fixture[1],fixture[2])
	await rotation_and_pause()
	game._clear_run();shell.free();await settle()
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"task":"003A.2","checks":checks,"failures":failures,"observations":observations,"events":events,"scope":"Actual production Shell/Main/Touch with root ScreenTouch/Drag; declared display/cutout/initial Duel/isolated save and manually stepped physics. Windows synthetic-input proof, not Android device, APK/native acceptance or human feel."},"\t"))
	print("TOUCH_FULLSCREEN_PROJECTION_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
