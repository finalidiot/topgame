extends SceneTree
## Real Touch controller events in declared responsive canvas geometry. No save,
## actor/resource fixture or physical Android device is created by this test.
const Touch = preload("res://scripts/touch_controls.gd")
var checks: int = 0
var failures: Array[String] = []
var report: String = ""

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func press(control: Node, index: int, point: Vector2, down: bool, canceled: bool = false) -> bool:
	var event := InputEventScreenTouch.new()
	event.index = index; event.position = point; event.pressed = down; event.canceled = canceled
	return control.handle_touch(event)
func drag(control: Node, index: int, point: Vector2) -> bool:
	var event := InputEventScreenDrag.new()
	event.index = index; event.position = point
	return control.handle_touch(event)
func geometry(canvas: Vector2, safe: Rect2, scale: float) -> Dictionary:
	var arena := Rect2((canvas-Vector2(640,360)*scale)*0.5,Vector2(640,360)*scale)
	return {"canvas_size":canvas,"safe_rect":safe,"arena_rect":arena,
		"steering_rect":arena.intersection(safe),
		"burst_rect":Rect2(safe.end.x-76,safe.end.y-186,70,52),
		"brake_rect":Rect2(safe.end.x-76,safe.end.y-126,70,52)}
func exercise(layout: Dictionary) -> void:
	var control := Touch.new(); root.add_child(control); control.set_enabled(true)
	var actual: Dictionary = control.configure_layout(layout)
	check(actual==layout,"Controller publishes the exact configured canvas/safe/arena/action geometry")
	var start: Vector2 = Rect2(layout.steering_rect).get_center()
	check(press(control,0,start,true),"A fresh fullscreen arena contact acquires steering")
	check(control.origin==start and control.direction==Vector2.ZERO,"Origin is the actual contact, initially neutral")
	drag(control,0,start+Vector2(4,0))
	check(control.direction==Vector2.ZERO,"Responsive projection preserves the eight-unit deadzone")
	drag(control,0,start+Vector2(30,0))
	check(is_equal_approx(control.direction.length(),0.5),"Responsive controller preserves analogue half travel")
	var prepared: Vector2 = control.direction
	check(control.configure_layout(layout)==layout and control.direction==prepared and control.steering_finger==0,"Identical layout publication cannot cancel prepared steering")
	check(press(control,1,Rect2(layout.burst_rect).get_center(),true),"Configured right-margin Burst acquires its own finger")
	check(press(control,2,Rect2(layout.brake_rect).get_center(),true),"Configured right-margin Brake acquires its own finger")
	check(control.owners.size()==3 and control.action_down("burst") and control.action_down("brake") and control.direction==prepared,"Both opposite-thumb actions coexist with steering")
	drag(control,1,start)
	check(control.steering_finger==0 and control.direction==prepared and control.action_down("burst"),"Dragging an action finger cannot steal steering")
	check(not Touch.valid_gameplay_point(Rect2(layout.burst_rect).get_center(),layout) and not Touch.valid_gameplay_point(Rect2(layout.brake_rect).get_center(),layout),"Action bounds cannot acquire steering")
	control.reset_actions()
	check(control.steering_finger==0 and control.direction==prepared and not control.action_down("burst") and not control.action_down("brake"),"Reentry resets actions while keeping prepared steering")
	check(not press(control,1,Rect2(layout.burst_rect).get_center(),true),"Held pre-reentry action requires release")
	press(control,1,Vector2.ZERO,false); press(control,2,Vector2.ZERO,false)
	check(press(control,1,Rect2(layout.burst_rect).get_center(),true),"Fresh post-reentry action is accepted")
	var shifted: Dictionary = layout.duplicate(true)
	shifted.safe_rect = Rect2(Vector2(layout.safe_rect.position)+Vector2(1,0),Vector2(layout.safe_rect.size)-Vector2(1,0))
	shifted.steering_rect = Rect2(layout.arena_rect).intersection(Rect2(shifted.safe_rect))
	control.configure_layout(shifted)
	check(control.owners.is_empty() and control.steering_finger==-1 and control.direction==Vector2.ZERO,"Cutout/rotation geometry change cancels previous coordinates")
	check(not drag(control,0,start+Vector2(52,0)) and not press(control,0,start,true) and not press(control,1,Rect2(layout.burst_rect).get_center(),true),"Stale drag/press cannot retarget either steering or action")
	press(control,0,start,false); press(control,1,start,false)
	check(press(control,0,start,true),"A released finger can reacquire after geometry changes")
	press(control,0,start,true,true)
	check(control.owners.is_empty() and control.direction==Vector2.ZERO,"Canceled native contact releases ownership")
	var unsafe: Vector2 = Rect2(layout.safe_rect).position-Vector2(0.1,0.1)
	check(not press(control,4,unsafe,true),"A touch outside the safe canvas cannot own an action or steer")
	control.set_enabled(false)
	check(not press(control,4,start,true),"Paused/menu touch remains disabled")
	control.free()
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
	if not report.is_empty() and (not report.is_absolute_path() or not report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/") or FileAccess.file_exists(report)):
		push_error("Fresh external003A.2 manifest required"); quit(1); return
	check(Touch.valid_gameplay_point(Vector2(100,90)) and not Touch.valid_gameplay_point(Vector2(100,49)),"Unconfigured static callers retain exact historical800 geometry")
	for layout: Dictionary in [geometry(Vector2(854,480),Rect2(0,0,854,480),1.0),
		geometry(Vector2(1204,540),Rect2(24,0,1170,540),1.1),
		geometry(Vector2(1368,600),Rect2(40,12,1314,574),1.25),
		geometry(Vector2(960,720),Rect2(12,20,936,680),1.0)]: exercise(layout)
	if not report.is_empty():
		var file:=FileAccess.open(report,FileAccess.WRITE)
		file.store_string(JSON.stringify({"task":"003A.2","scope":"Actual Touch events with declared responsive geometry; no device or gameplay acceptance", "checks":checks,"failures":failures},"\t"))
	print("TOUCH_FULLSCREEN_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
