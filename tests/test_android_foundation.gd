extends SceneTree
const Touch = preload("res://scripts/touch_controls.gd")
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Main = preload("res://scripts/main.gd")
const Shell = preload("res://scripts/mobile_shell.gd")
const ButtonScript = preload("res://scripts/touch_button.gd")
const AndroidQA = preload("res://scripts/android_qa.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
var checks: int = 0
var failures: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _init() -> void: call_deferred("run")
func touch(router, finger: int, point: Vector2, pressed: bool) -> bool:
	var event = InputEventScreenTouch.new()
	event.index = finger; event.position = point; event.pressed = pressed
	return router.handle_touch(event)
func drag(router, finger: int, point: Vector2) -> bool:
	var event = InputEventScreenDrag.new()
	event.index = finger; event.position = point
	return router.handle_touch(event)
func run() -> void:
	check(AndroidQA.request_seed(421)==421 and AndroidQA.request_seed(421.0)==421,"Device QA accepts actual parsed JSON integral seed numbers")
	for invalid: Variant in [421.5,INF,NAN,-1,"421",2147483648]: check(AndroidQA.request_seed(invalid)==0,"Malformed QA seed cannot alter the normal random Run")
	for safe: Rect2i in [Rect2i(0,0,1280,720),Rect2i(80,0,1760,1080),Rect2i(90,36,2220,1044),Rect2i(0,0,2560,1440),Rect2i(12,0,788,480)]:
		var fit: Rect2i = Shell.fit_surface(safe)
		check(safe.encloses(fit),"Phone native surface fits the complete cutout-safe rectangle")
		check(fit.size.x%640==0 and fit.size.y%360==0 and fit.size.x/640==fit.size.y/360,"Phone preserves aspect and whole raster scale")
	var holder = Control.new(); root.add_child(holder)
	var first = ButtonScript.new(); first.touch_targets=true; first.size=Vector2(100,28); first.position=Vector2(50,50); holder.add_child(first)
	var second = ButtonScript.new(); second.touch_targets=true; second.size=Vector2(100,28); second.position=Vector2(50,84); holder.add_child(second)
	check(first._has_point(Vector2(50,-7)),"Small menu caps have a minimum44nativepixel touch target")
	check(not first._has_point(Vector2(50,35)) and second._has_point(Vector2(50,1)),"Adjacent enlarged touch targets choose the nearest single control")
	holder.free()
	var router = Touch.new(); root.add_child(router); router.set_enabled(true)
	for point: Vector2 in [Vector2(100,120), Vector2(400,180), Vector2(580,100)]:
		check(touch(router,0,point,true),"Touch anywhere in gameplay owns a new origin")
		check(router.direction == Vector2.ZERO,"Initial touch is neutral")
		check(drag(router,0,point+Vector2(4,0)),"Steering drag stays owned")
		check(router.direction == Vector2.ZERO,"Circular deadzone prevents a jump")
		drag(router,0,point+Vector2(30,0))
		check(is_equal_approx(router.direction.length(),0.5),"Half travel preserves analogue magnitude")
		drag(router,0,point+Vector2(150,150))
		check(is_equal_approx(router.direction.length(),1.0),"Maximum radius bounds diagonal input")
		check(touch(router,0,point,false),"Release removes ownership")
		check(router.direction==Vector2.ZERO and router.steering_finger==-1,"Release immediately neutral")
	check(not touch(router,0,Vector2(320,30),true),"HUD never owns steering")
	touch(router,0,Vector2(150,180),true); drag(router,0,Vector2(185,160))
	var prepared: Vector2 = router.direction
	touch(router,3,Touch.BURST_RECT.get_center(),true)
	touch(router,8,Touch.BRAKE_RECT.get_center(),true)
	check(router.action_down("burst") and router.action_down("brake") and router.direction==prepared,"Three independent fingers preserve steering and both actions")
	drag(router,3,Vector2(100,100))
	check(router.action_down("burst") and router.steering_finger==0,"An action finger cannot steal steering")
	router.reset_actions()
	check(not router.action_down("burst") and not router.action_down("brake") and router.direction==prepared,"Reentry clears actions but preserves prepared steering")
	check(not touch(router,3,Touch.BURST_RECT.get_center(),true),"Held action requires release before acquiring again")
	touch(router,3,Vector2.ZERO,false)
	check(touch(router,3,Touch.BURST_RECT.get_center(),true),"A fresh action is accepted")
	router.set_enabled(false)
	check(router.owners.is_empty() and router.direction==Vector2.ZERO,"Menu transition clears all live fingers")
	check(not touch(router,9,Vector2(100,100),true),"Menus cannot steer the arena")
	var battle = Battle.new(); root.add_child(battle); battle.set_physics_process(false); battle.input_provider=router
	battle.begin_run({"blade":"guard","ratchet":"low","bit":"ball"}, Encounters.for_run_event(1,421),421)
	for i in range(190): battle.test_step(1.0/60.0)
	check(battle.battle_status=="battle","Initial launch uses actual countdown and launch")
	var player: Dictionary = battle.player_entity()
	var before: Dictionary = {"pos":player.pos,"vel":player.vel,"spin":player.rpm,"elapsed":battle.elapsed,"time":battle.powers.time}
	battle.begin_reentry()
	router.set_enabled(true); touch(router,1,Vector2(200,180),true); drag(router,1,Vector2(240,180))
	for i in range(74):
		battle.test_step(1.0/60.0,router.direction,true,true)
		check(battle.elapsed==before.elapsed and player.pos==before.pos and player.vel==before.vel and player.rpm==before.spin and battle.powers.time==before.time,"Reentry freezes physics, reserve, threats and powers while steering is prepared")
	check(battle.battle_status=="reentry" and router.direction.x>0,"Prepared direction waits for GO")
	for i in range(3): battle.test_step(1.0/60.0,router.direction)
	check(battle.battle_status=="battle","Resume countdown reaches GO")
	check(battle._burst_buffer==0,"Countdown action never becomes a buffered burst")
	battle.test_step(1.0/60.0,router.direction)
	check(battle.elapsed>before.elapsed,"Live simulation resumes after GO")
	var app = QuietMain.new(); app.smoke_mode=true; root.add_child(app)
	await process_frame
	check(app.settings.has("reduced_flashing"),"Reduced Flashing persists through validated settings")
	check(not app._validated_settings({"reduced_flashing":"bad"}).reduced_flashing,"Preference validates boolean comfort values")
	app._start_battle("duel")
	for i in range(190): app.battle.test_step(1.0/60.0)
	app._pause(); check(app.screen=="pause" and app.battle.paused,"Touch pause preserves the live battle")
	app._resume(); check(app.screen=="battle" and app.battle.battle_status=="reentry","Pause return has a safe countdown")
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(app.battle.paused and app._application_suspended,"Background freezes danger and music")
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not app.battle.paused and app.battle.battle_status=="reentry","Foreground restores through countdown")
	app._clear_run(); app.screen="packet_open"
	app.menus.show_packet_open({"kind":"standard","rows":[{"category":"blade","id":"guard"},{"category":"ratchet","id":"low"},{"category":"bit","id":"ball"}]},{"credits":0,"salvage":0})
	app.menus._packet_view.phase="CRINKLE"
	var seam_down = InputEventScreenTouch.new(); seam_down.index=4; seam_down.position=Vector2(280,180); seam_down.pressed=true
	app.menus._input(seam_down)
	var seam_drag = InputEventScreenDrag.new(); seam_drag.index=4; seam_drag.position=Vector2(330,180)
	app.menus._input(seam_drag)
	check(app.menus._packet_view.opening and app.menus._packet_view.phase=="TEAR","A delayed seam gesture opens an already crinkling packet through the production action")
	check(app.menus._packet_touch_index==-1,"A successful seam owns exactly one tear")
	app.free(); battle.free(); router.free()
	print("ANDROID_FOUNDATION_%s checks=%d failures=%d" % ["PASS" if failures==0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
