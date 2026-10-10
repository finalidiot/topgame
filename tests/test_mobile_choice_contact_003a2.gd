extends SceneTree
## Actual root events through MobileShell/Main. Initial ownership/pending draft
## is a declared legal UI fixture; no natural acquisition or phone claim.
const Powers = preload("res://scripts/run_powers.gd")
class IsolatedShell extends "res://scripts/mobile_shell.gd":
	func _ready() -> void: pass
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
var checks: int = 0
var failures: Array[String] = []
var traces: Array[Dictionary] = []
var report: String = ""
var prefix: String = ""
var game: QuietMain
var shell: IsolatedShell
var fixture_number: int = 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func valid_paths() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
		if arg.begins_with("--profile-prefix="): prefix = arg.trim_prefix("--profile-prefix=")
		if arg.begins_with("--collection-path=") or arg in ["--smoke-test","--qa-catalogue","--reset-collection"]: return false
	var qa: String = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA/003A.2")
	if not OS.get_environment("TOPGAME_QA_ROOT").is_empty(): qa = OS.get_environment("TOPGAME_QA_ROOT").path_join("003A.2")
	for item: Array in [[report,"manifests"],[prefix,"temp"]]:
		var path: String = str(item[0]).replace("\\","/").simplify_path()
		var boundary: String = qa.replace("\\","/").simplify_path().path_join(str(item[1])).to_lower()+"/"
		if not path.is_absolute_path() or not path.to_lower().begins_with(boundary) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): return false
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	return true
func descendants(node: Node) -> Array:
	var result: Array = []
	for child: Node in node.get_children(): result.append(child); result.append_array(descendants(child))
	return result
func button(intent: String, power: String = "") -> Button:
	for node: Node in descendants(game.menus):
		if node is Button and node.is_visible_in_tree() and not node.disabled and str(node.get_meta("intent","")) == intent:
			if power.is_empty() or str(node.get_meta("power_id","")) == power: return node
	return null
func point(target: Button) -> Vector2:
	return shell.surface.get_global_transform_with_canvas()*target.get_global_rect().get_center()
func actions(name: String) -> int: return game.audit_actions.count(name)
func record(label: String) -> void:
	traces.append({"label":label,"screen":game.screen,"actions":game.audit_actions.duplicate(),"ranks":game.run_context.power_ranks,
		"mutations":game.run_context.power_mutations,"siblings":game.run_context.pending_mutation_offer})
func touch(position: Vector2, pressed: bool, index: int = 7, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position; event.index = index; event.pressed = pressed; event.canceled = canceled
	Input.parse_input_event(event); await settle()
func mouse(position: Vector2, pressed: bool, emulated: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
	Input.parse_input_event(event); await settle()
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = pressed
	Input.parse_input_event(event); await settle()
func pad(pressed: bool) -> void:
	var event := InputEventJoypadButton.new(); event.device = 0; event.button_index = JOY_BUTTON_A; event.pressed = pressed
	Input.parse_input_event(event); await settle()
func fixture() -> void:
	fixture_number += 1
	game._clear_run(); game.run_context.start(game.collection.equipped_build(),421,"vane")
	game.run_context._owned_power_ids.assign(["orbit_drive","afterimage","momentum_bank"])
	game.run_context._power_ranks = {"orbit_drive":2,"afterimage":1,"momentum_bank":1}
	game.run_context._pending_offer.assign(["orbit_drive","afterimage","momentum_bank"])
	game.run_context._draft_queue.assign([{"id":"draft/contact_fixture_%d" % fixture_number,"kind":"level","level":5}])
	game._draft_resume_origin = "starting"; game.mode = "run"; game._show_reward()
	game.audit_actions.clear(); await settle()
	check(game.screen=="reward" and button("choose_power","orbit_drive")!=null,"Declared eligible RankII fixture reaches actual power draft")
func upgrade(index: int = 7) -> Vector2:
	var target: Button = button("choose_power","orbit_drive")
	if target==null: return Vector2.ZERO
	var origin: Vector2 = point(target)
	await touch(origin,true,index)
	check(game.screen=="mutation" and game.menus.screen=="mutation","One real root touch opens the separate mutation screen")
	check(actions("choose_power")==1 and actions("choose_mutation")==0,"Upgrade touch emits exactly the parent intent")
	check(int(game.run_context.power_ranks.get("orbit_drive",0))==2 and game.run_context.power_mutations.is_empty(),"Parent touch does not commit RankIII or choose a sibling")
	var visible: Array = descendants(game.menus).filter(func(node: Node)->bool:return node is Button and node.is_visible_in_tree() and str(node.get_meta("intent",""))=="choose_mutation")
	check(visible.size()==2 and game.run_context.pending_mutation_offer==Powers.mutation_choices("orbit_drive"),"Both actual legal siblings remain visible and unclaimed")
	record("parent_press"); return origin
func claimed(label: String) -> void:
	check(game.screen=="acquisition" and actions("choose_mutation")==1,"Fresh %s commits exactly one sibling" % label)
	check(int(game.run_context.power_ranks.get("orbit_drive",0))==3 and game.run_context.power_mutations.size()==1,"Only the fresh choice persists RankIII")
	record(label)
func continuation_case() -> void:
	await fixture()
	var origin: Vector2 = await upgrade()
	var sibling: Button = button("choose_mutation")
	if sibling==null: return
	var destination: Vector2 = point(sibling)
	await mouse(destination,true,true); await mouse(destination,false,true)
	var drag := InputEventScreenDrag.new(); drag.index=7; drag.position=destination; drag.relative=destination-origin
	Input.parse_input_event(drag); await settle()
	await touch(destination,false)
	await mouse(destination,true,true); await mouse(destination,false,true)
	check(game.screen=="mutation" and actions("choose_mutation")==0,"Old contact drag, release and mouse echoes cannot claim the replacement screen")
	check(int(game.run_context.power_ranks.orbit_drive)==2,"Release/echo preserves RankII")
	record("release_and_echo")
	await touch(destination,true,8); await touch(destination,false,8)
	claimed("touch")
func cancellation_case() -> void:
	await fixture()
	var origin: Vector2 = await upgrade()
	var sibling: Button = button("choose_mutation")
	if sibling==null: return
	var destination: Vector2 = point(sibling)
	await touch(origin,false,7,true)
	await mouse(destination,true,true); await mouse(destination,false,true)
	check(game.screen=="mutation" and actions("choose_mutation")==0,"Canceled old contact and its mouse echo do not choose")
	await touch(destination,true,9); await touch(destination,false,9)
	claimed("post-cancel touch")
func explicit_order_case(mouse_first: bool) -> void:
	# Disable automatic emulation only in this declared event-order fixture;
	# both paired events still enter the real root and production shell.
	await fixture()
	Input.emulate_mouse_from_touch=false
	var target: Button=button("choose_power","orbit_drive")
	if target==null: Input.emulate_mouse_from_touch=true; return
	var origin: Vector2=point(target)
	if mouse_first:
		await mouse(origin,true,true); await touch(origin,true,21)
	else:
		await touch(origin,true,21); await mouse(origin,true,true)
	check(game.screen=="mutation" and actions("choose_power")==1 and actions("choose_mutation")==0,"Explicit %s paired root events accept only the parent" % ("mouse-first" if mouse_first else "raw-first"))
	check(int(game.run_context.power_ranks.orbit_drive)==2 and game.run_context.pending_mutation_offer.size()==2,"Both event orders preserve RankII and both visible siblings")
	await touch(origin,false,21); await mouse(origin,false,true)
	var sibling: Button=button("choose_mutation")
	if sibling==null: Input.emulate_mouse_from_touch=true; return
	var destination: Vector2=point(sibling)
	if mouse_first:
		await mouse(destination,true,true); await touch(destination,true,22)
	else:
		await touch(destination,true,22); await mouse(destination,true,true)
	await touch(destination,false,22); await mouse(destination,false,true)
	claimed("explicit %s fresh contact" % ("mouse-first" if mouse_first else "raw-first"))
	Input.emulate_mouse_from_touch=true
func suspended_case() -> void:
	await fixture()
	await upgrade()
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(game._application_backgrounded and game.menus.input_suspended,"Actual Main background notification suspends menu input")
	# Deliberately omit the old contact's release: Android may never deliver it.
	game._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not game._application_backgrounded and not game.menus.input_suspended,"Actual Main resume restores menu input")
	var sibling: Button = button("choose_mutation")
	if sibling==null: return
	var destination: Vector2 = point(sibling)
	await touch(destination,true,10); await touch(destination,false,10)
	claimed("post-resume touch without old release")
	await touch(destination,false,7,true)
func alternate_case(kind: String) -> void:
	await fixture()
	var origin: Vector2 = await upgrade()
	await touch(origin,false)
	var sibling: Button = button("choose_mutation")
	if sibling==null: return
	if kind=="mouse":
		var destination: Vector2 = point(sibling)
		await mouse(destination,true); await mouse(destination,false)
	elif kind=="keyboard":
		sibling.grab_focus(); await key(KEY_ENTER,true); await key(KEY_ENTER,false)
	else:
		sibling.grab_focus(); await pad(true); await pad(false)
	claimed(kind)
func reroll_and_pause_case() -> void:
	await fixture()
	check(game.run_context.collect_reroll_pickup("qa/contact/extra"),"Declared initial pickup gives a second legitimate reroll charge")
	game._show_reward(); await settle()
	var target: Button = button("reroll_power")
	check(target!=null,"Actual available reroll control exists")
	if target==null: return
	var origin: Vector2 = point(target)
	await touch(origin,true,12); await touch(origin,false,12)
	await mouse(origin,true,true); await mouse(origin,false,true)
	check(actions("reroll_power")==1 and game.run_context.rerolls_used==1,"A reroll replacement consumes once despite contact echoes")
	var next: Button = button("reroll_power")
	if next==null: return
	var next_origin: Vector2 = point(next)
	await touch(next_origin,true,13); await touch(next_origin,false,13)
	check(actions("reroll_power")==2 and game.run_context.rerolls_used==2,"Fresh second reroll remains available after replacement")
	for cycle: int in range(2):
		await key(KEY_ESCAPE,true); await key(KEY_ESCAPE,false)
		check(game.screen=="pause","Actual Escape opens the paused draft")
		var resume: Button = button("resume")
		if resume==null: return
		var destination: Vector2 = point(resume)
		await touch(destination,true,14+cycle); await touch(destination,false,14+cycle)
		check(game.screen=="reward","Fresh touch resumes the exact mandatory draft after pause")
	record("two_rerolls_two_pause_cycles")
func run() -> void:
	if not valid_paths(): push_error("Fresh absolute external003A.2 report/profile prefix required"); quit(2); return
	root.size=Vector2i(2340,1080); root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED; await settle()
	var path: String=prefix+".json"
	for suffix: String in ["",".bak",".tmp",".preferences.cfg"]: check(not FileAccess.file_exists(path+suffix),"Fresh isolated Main profile: "+suffix)
	game=QuietMain.new(); game.smoke_mode=true; game.qa_task_id="003A.2"; game.collection_path=path; game.settings.muted=true
	shell=IsolatedShell.new(); root.add_child(shell); shell.mount_mobile_surface(game); shell.set_process(false)
	shell.apply_display_layout(root.size,Rect2i(84,24,2208,1032)); game.set_process(false); game.battle.set_physics_process(false); await settle()
	check(game.collection.save_path==path and game.menus.mobile_hud,"Production mobile mount opens only the declared isolated profile")
	await continuation_case(); await cancellation_case(); await suspended_case()
	for kind: String in ["mouse","keyboard","controller"]: await alternate_case(kind)
	await explicit_order_case(false); await explicit_order_case(true)
	await reroll_and_pause_case()
	var file: FileAccess=FileAccess.open(report,FileAccess.WRITE); check(file!=null,"Fresh actual-root event report opens")
	if file!=null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"traces":traces,"profile":path,
			"scope":"Actual production Shell/Main root ScreenTouch, emulated/real mouse, keyboard/controller and lifecycle notifications on declared Windows cutout surface. Legal initial invested/pending draft; no physical phone or natural acquisition claim."},"\t")); file.close()
	print("MOBILE_CHOICE_CONTACT_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	shell.free(); quit(0 if failures.is_empty() else 1)
