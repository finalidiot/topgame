extends SceneTree
## Real UI/input capture, isolated collections, production Main/music/physics.
## Metadata locates controls; only input events activate them. No screen/action,
## position/RPM/contact/director/outcome injection after normal boot.
const Main = preload("res://scripts/main.gd")
const Collection = preload("res://scripts/collection_save.gd")
const Parts = preload("res://scripts/parts.gd")
const Bot = preload("res://tests/rpm_bot.gd")
var game: Node2D
var output: String=""
var frames: String=""
var fixture_path: String=""
var fresh_path: String=""
var diagnostic: bool=false
var max_run_seconds: float=240.0
var seed: int=421
var sections: Array[Dictionary]=[]
var images: Dictionary={}
var input_events: Array[Dictionary]=[]
var rows: Array[Dictionary]=[]
var axis: Vector2=Vector2.ZERO
var burst_down: bool=false
var brake_down: bool=false
var raw_start: int=0
var fresh_proof: Dictionary={}
var phase: String=""
var phase_start: int=0
var high_start: int=-1
var prefix_end: int=0
var end_start: int=0
var result_snapshot: Dictionary={}

func _initialize() -> void: call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	quit(2)

func safe_path(path: String, folder: String) -> bool:
	var qa: String=OS.get_environment("TOPGAME_QA_ROOT")
	if qa.is_empty(): qa=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	var allowed: String=qa.replace("\\","/").simplify_path().path_join("002C.6/"+folder).to_lower()+"/"
	return path.is_absolute_path() and path.replace("\\","/").simplify_path().to_lower().begins_with(allowed)

func frame() -> int: return Engine.get_process_frames()-raw_start

func wait_frames(count: int) -> void:
	for i: int in range(count): await process_frame

func begin_section(name: String) -> void:
	if not phase.is_empty(): sections.append({"name":phase,"from_frame":phase_start,"to_frame":frame(),"seconds":float(frame()-phase_start)/60.0})
	phase=name;phase_start=frame()
	print("PRESENTATION_STAGE ",name," frame=",frame()," screen=",game.screen if is_instance_valid(game) else "none")

func image(name: String) -> void:
	if diagnostic: return
	await RenderingServer.frame_post_draw
	var pixels: Image=root.get_texture().get_image()
	assert(pixels.get_size()==Vector2i(640,360),"Native review uses640x360 without smoothing")
	var path: String=frames.path_join(name+".png")
	assert(not FileAccess.file_exists(path),"Capture outputs must be fresh")
	assert(pixels.save_png(path)==OK)
	images[name]={"path":path,"frame":frame(),"main_screen":game.screen,"menu_screen":game.menus.screen,"music":game.music.music_snapshot()}

func checkpoint(name: String, seconds: float=1.5) -> void:
	begin_section(name)
	await wait_frames(4)
	await image(name)
	await wait_frames(roundi(seconds*60.0))

func key(code: Key, pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)
	input_events.append({"frame":frame(),"type":"key","code":code,"pressed":pressed,"screen":game.screen})

func tap_key(code: Key) -> void:
	key(code,true);await wait_frames(2);key(code,false);await wait_frames(2)

func joy(button: JoyButton, pressed: bool) -> void:
	var event:=InputEventJoypadButton.new()
	event.device=0;event.button_index=button;event.pressed=pressed
	Input.parse_input_event(event)
	input_events.append({"frame":frame(),"type":"joy_button","button":button,"pressed":pressed,"screen":game.screen})

func tap_joy(button: JoyButton) -> void:
	joy(button,true);await wait_frames(2);joy(button,false);await wait_frames(2)

func motion(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=point;event.global_position=point
	Input.parse_input_event(event)

func mouse_button(point: Vector2, pressed: bool) -> void:
	var event:=InputEventMouseButton.new()
	event.position=point;event.global_position=point
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	Input.parse_input_event(event)

func click(control: Control) -> void:
	assert(is_instance_valid(control) and control.is_visible_in_tree(),"Only a real visible control is activated")
	var rect: Rect2=control.get_global_rect()
	var point: Vector2=rect.get_center()
	assert(Rect2(0,0,640,360).has_point(point),"Control must be on screen after real navigation")
	var description: Dictionary={"frame":frame(),"type":"gui_mouse_click","screen":game.screen,"control":str(control.name),"position":[point.x,point.y]}
	if control.has_meta("intent"): description.intent=control.get_meta("intent")
	if control.has_meta("payload"): description.payload=control.get_meta("payload")
	input_events.append(description)
	motion(point);await wait_frames(2);mouse_button(point,true);await wait_frames(2);mouse_button(point,false);await wait_frames(4)

func matching(node: Node, metadata: Dictionary) -> Control:
	if node is Control and node.is_visible_in_tree():
		var match_all: bool=true
		for name: String in metadata:
			if not node.has_meta(name) or node.get_meta(name)!=metadata[name]:match_all=false;break
		if match_all and (not node is BaseButton or not node.disabled):return node
	for child: Node in node.get_children():
		var found: Control=matching(child,metadata)
		if found!=null:return found
	return null

func intent(name: String) -> Control:
	var found: Control=matching(game.menus,{"intent":name})
	assert(found!=null,"Missing actual UI intent "+name+" at "+str(game.screen))
	return found

func click_intent(name: String) -> void: await click(intent(name))

func focus_by_tabs(control: Control) -> void:
	for attempt: int in range(100):
		if root.gui_get_focus_owner()==control:return
		await tap_key(KEY_TAB)
	assert(false,"Actual Tab navigation could not reach the requested control")

func equip(category: String, id: String) -> void:
	var tab: Control=matching(game.menus,{"catalogue_tab":category})
	assert(tab!=null)
	await click(tab)
	var card: Control=matching(game.menus,{"part_category":category,"part_id":id})
	assert(card!=null and bool(card.get_meta("owned",false)),"Only an owned fixture part can be equipped")
	await focus_by_tabs(card)
	await tap_key(KEY_ENTER)
	assert(game.collection.equipped_build()[category]==id,"Actual UI equipment choice must persist")
	await checkpoint("workshop_"+category,1.8)

func boot(path: String) -> void:
	game=Main.new()
	game.collection_path=path
	game.review_audio=not diagnostic
	root.add_child(game)
	await wait_frames(4)
	game.music.configure_playback(not diagnostic)
	assert(game.screen=="title_gate","Normal boot must show the real title gate")
	assert(game.preferences_path==path+".preferences.cfg","Every settings write is isolated")

func close_game() -> void:
	# Native audio release needs a mixer callback, not merely three artificial
	# fixed-FPS frames. This is shutdown only, after all captured evidence.
	game.music.configure_playback(false)
	for channel: AudioStreamPlayer in game.sounds.channels:channel.stop()
	OS.delay_msec(200)
	game.free()
	OS.delay_msec(100)
	await wait_frames(3)

func fresh_collection_proof() -> void:
	await boot(fresh_path)
	assert(not game.collection.is_initialized() and game.collection.owned_count()==0)
	await checkpoint("fresh_title_gate",0.5)
	await tap_key(KEY_ENTER)
	await click_intent("begin_collection")
	await checkpoint("fresh_ceremony",0.6)
	var card: Control=matching(game.menus,{"intent":"select_first_starter","starter_id":"breaker"})
	assert(card!=null)
	await click(card)
	await checkpoint("fresh_confirmation",0.6)
	await click_intent("confirm_first_starter")
	assert(game.collection.is_initialized() and game.collection.owned_count()==3,"A fresh normal save grants exactly one starter's3components")
	fresh_proof={"path":fresh_path,"owned_count":game.collection.owned_count(),"starter":game.collection.starter_id,"snapshot":game.collection.snapshot(),"preferences":game.preferences_path}
	await checkpoint("fresh_owned",0.8)
	await wait_frames(90)
	assert(game.screen=="garage")
	await checkpoint("fresh_workshop_three_parts",0.8)
	await close_game()

func seed_catalogue_fixture() -> void:
	var collection:=Collection.new(fixture_path)
	assert(not FileAccess.file_exists(fixture_path),"Catalogue fixture must be a new external file")
	collection.load_save()
	assert(bool(collection.initialize_starter("breaker").ok))
	for category: String in Collection.CATEGORIES:
		for id: String in Parts.PARTS[category]:assert(bool(collection.grant_part(category+":"+id).ok))
	assert(collection.owned_count()==31,"Explicit complete-catalogue QA fixture has31parts")

func controls(direction: Vector2, burst: bool, brake: bool) -> void:
	if direction.distance_to(axis)>0.01:
		for index: int in range(2):
			var event:=InputEventJoypadMotion.new()
			event.device=0;event.axis=JOY_AXIS_LEFT_X if index==0 else JOY_AXIS_LEFT_Y
			event.axis_value=direction.x if index==0 else direction.y
			Input.parse_input_event(event)
		axis=direction
		var observed: Vector2=Input.get_vector("move_left","move_right","move_up","move_down")
		input_events.append({"frame":frame(),"type":"joy_axes","requested":[direction.x,direction.y],"mapped":[observed.x,observed.y],"screen":game.screen})
	if burst!=burst_down:joy(JOY_BUTTON_A,burst);burst_down=burst
	if brake!=brake_down:joy(JOY_BUTTON_LEFT_SHOULDER,brake);brake_down=brake

func choose_offer() -> void:
	controls(Vector2.ZERO,false,false)
	await wait_frames(4)
	var choice: Control
	if game.screen=="reward":
		for id: String in ["afterimage","predator_line","crosscut","high_gear","chain_impact","impact_wake","iron_comet","redline","orbit_drive","momentum_bank","crash_guard"]:
			choice=matching(game.menus,{"intent":"choose_power","power_id":id})
			if choice!=null:break
		if choice==null:choice=intent("choose_power")
	elif game.screen=="mutation":choice=intent("choose_mutation")
	else:return
	await click(choice)

func state_row() -> Dictionary:
	var p: Dictionary=game.battle.player_entity()
	return {"frame":frame(),"time":game.battle.elapsed,"screen":game.screen,"rpm":p.rpm,"speed":Vector2(p.vel).length(),"position":[p.pos.x,p.pos.y],"wobble":p.wobble,"hits":game.battle.hits,"outcome":p.outcome,"run":game.battle.continuous.snapshot() if game.battle.continuous!=null else {},"music":game.music.music_snapshot(),"sfx":game.sounds.audio_snapshot()}

func live_run() -> void:
	await click_intent("launch_owned_run")
	assert(game.screen=="reward")
	await checkpoint("starting_power",2.0)
	await choose_offer()
	await checkpoint("power_acquisition",0.2)
	while game.screen!="battle":await wait_frames(1)
	begin_section("countdown_launch")
	while game.battle.battle_status!="battle":await wait_frames(1)
	await image("hud_opening")
	begin_section("normal_run")
	for i: int in range(360):
		if game.screen=="battle":
			var c: Dictionary=Bot.input(game.battle,"defensive",i)
			controls(c.direction,c.burst,c.brake)
		elif game.screen in ["reward","mutation"]:await choose_offer()
		await wait_frames(1)
	controls(Vector2.ZERO,false,false)
	assert(game.screen=="battle","Opening Run must naturally remain alive for pause review")
	await tap_key(KEY_ESCAPE)
	assert(game.screen=="pause")
	await checkpoint("pause",1.7)
	await click_intent("settings")
	assert(game.screen=="settings")
	await checkpoint("pause_options",1.7)
	await click_intent("back_settings")
	assert(game.screen=="pause")
	await click_intent("resume")
	assert(game.screen=="battle")
	prefix_end=frame()
	begin_section("continued_actual_run")
	var high_captured: bool=false
	for tick: int in range(roundi(max_run_seconds*60.0)):
		if game.screen=="result":break
		if game.screen=="battle":
			var c: Dictionary=Bot.input(game.battle,"afk" if high_captured and frame()-high_start>480 else "defensive",tick+360)
			controls(c.direction,c.burst,c.brake)
			if tick%60==0:rows.append(state_row())
			var music: Dictionary=game.music.music_snapshot()
			if not high_captured and float(music.stable_run.pressure)>=0.5:
				high_captured=true;high_start=frame()
				begin_section("actual_high_pressure")
				await image("hud_high_pressure")
		elif game.screen in ["reward","mutation"]:await choose_offer()
		else:controls(Vector2.ZERO,false,false)
		await wait_frames(1)
	controls(Vector2.ZERO,false,false)
	if game.screen!="result" or not high_captured:
		fail("Review needs an actual high-intensity state and a naturally completed Run within the input-only capture limit");return
	assert(str(game.battle.player_entity().outcome)!="" and bool(game.last_result.get("continuous_run",false)))
	result_snapshot=game.last_result.duplicate(true)
	end_start=frame()
	await checkpoint("natural_run_result",3.0)
	await click_intent("main_menu")
	assert(game.screen=="title")
	await checkpoint("returned_hub",2.0)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="):frames=arg.trim_prefix("--frames=")
		if arg.begins_with("--collection="):fixture_path=arg.trim_prefix("--collection=")
		if arg.begins_with("--fresh-collection="):fresh_path=arg.trim_prefix("--fresh-collection=")
		if arg.begins_with("--max-run-seconds="):max_run_seconds=float(arg.trim_prefix("--max-run-seconds="))
		if arg.begins_with("--run-seed="):seed=int(arg.trim_prefix("--run-seed="))
		if arg=="--diagnostic":diagnostic=true
	if not safe_path(output,"manifests") or not safe_path(fixture_path,"temp") or not safe_path(fresh_path,"temp") or (not diagnostic and not safe_path(frames,"frames")):
		fail("Every capture/save output must be explicitly scoped to external002C.6QA");return
	assert(not FileAccess.file_exists(output) and not FileAccess.file_exists(fresh_path) and fixture_path!=fresh_path,"Capture cannot overwrite an existing save/report")
	root.size=Vector2i(640,360)
	root.content_scale_size=Vector2i(640,360)
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not diagnostic:DirAccess.make_dir_recursive_absolute(frames)
	raw_start=Engine.get_process_frames()
	await fresh_collection_proof()
	seed_catalogue_fixture()
	await boot(fixture_path)
	await checkpoint("catalogue_title_gate",2.5)
	await tap_key(KEY_ENTER)
	assert(game.screen=="title")
	await checkpoint("hub",1.8)
	await tap_joy(JOY_BUTTON_DPAD_DOWN)
	await image("hub_controller_focus")
	await tap_joy(JOY_BUTTON_A)
	assert(game.screen=="garage","Controller D-pad/confirm must navigate the actual hub to workshop")
	await checkpoint("workshop_full_catalogue",2.2)
	assert(game.collection.owned_count()==31)
	await equip("blade","balance")
	await equip("ratchet","flex")
	await equip("bit","flat")
	await checkpoint("assembled_owned_top",1.8)
	await click_intent("main_menu")
	await click_intent("settings")
	assert(game.screen=="settings")
	var slider: Control=matching(game.menus,{"setting_key":"music_volume"})
	assert(slider is HSlider)
	await focus_by_tabs(slider)
	await tap_key(KEY_LEFT)
	await tap_key(KEY_RIGHT)
	await checkpoint("options",2.0)
	await click_intent("save_tools")
	await checkpoint("save_tools",1.1)
	var saved_hash: String=FileAccess.get_sha256(fixture_path)
	await click_intent("request_reset_collection")
	await checkpoint("reset_confirmation_cancelled",1.1)
	await click_intent("cancel_reset_collection")
	assert(FileAccess.get_sha256(fixture_path)==saved_hash,"Cancel must preserve the isolated catalogue")
	await click_intent("back_settings")
	await click_intent("back_settings")
	assert(game.screen=="title")
	await click_intent("help")
	await checkpoint("help",1.0)
	await tap_key(KEY_ESCAPE)
	await click_intent("play_modes")
	await checkpoint("play_modes",1.0)
	await click_intent("main_menu")
	await click_intent("open_workshop")
	await live_run()
	if result_snapshot.is_empty():return
	begin_section("capture_complete")
	var snapshot: Dictionary=game.collection.snapshot()
	var audio: Dictionary=game.sounds.audio_snapshot()
	var music: Dictionary=game.music.music_snapshot()
	var report: Dictionary={"task":"002C.6","seed":seed,"fps":60,"native_view":[640,360],"diagnostic":diagnostic,"sections":sections,"images":images,"input_events":input_events,"rows":rows,"fresh_save_proof":fresh_proof,"catalogue_fixture":{"path":fixture_path,"seeded_count":31,"label":"Explicit31part isolated QA fixture; not earned progression","final":snapshot},"raw_frames":frame(),"prefix_end_frame":prefix_end,"high_pressure_start_frame":high_start,"natural_result_start_frame":end_start,"natural_result":result_snapshot,"music_final":music,"sfx_final":audio,"authenticity":"Normal Main boot and real UI input events. Metadata only locates controls. Legal QA collection seeded before boot; fresh starter proof is a separate normal new save. Real countdown/launch/control/director/progression/music/result; no direct actions/show-screens or simulation state injection. All menu/audio/save paths are isolated."}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	assert(file!=null);file.store_string(JSON.stringify(report,"\t"));file.close()
	await close_game()
	print("PRESENTATION_CAPTURE_PASS frames=",frame()," high_frame=",high_start," natural_result=",end_start," fresh_parts=3 catalogue_parts=31")
	quit(0)
