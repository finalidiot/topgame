extends SceneTree
## Actual Main/Menus presentation fixtures; never a phone or hardware claim.
## A legal initial invested Run and pending level draft are disclosed fixtures.
const Physics = preload("res://scripts/battle.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Layout = preload("res://scripts/combat_hud_layout.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
class IsolatedShell extends "res://scripts/mobile_shell.gd":
	func _ready() -> void: pass
const SIZES: Array[Vector2i] = [Vector2i(800,480),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
const MOBILE_SIZE = Vector2i(2340,1080)
const MOBILE_SAFE = Rect2i(84,24,2208,1032)
var report: String = ""
var prefix: String = ""
var frames: String = ""
var native: bool = false
var movie: bool = false
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var inputs: Array[Dictionary] = []
var images: Array[Dictionary] = []
var film: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var game: QuietMain
var shell: IsolatedShell
var case_id: String = ""
var mobile: bool = false
var film_phase: String = ""
var film_tick: int = 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		if not message in failures: failures.append(message)
		push_error(message)
func portable(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Rect2 or value is Rect2i: return [value.position.x,value.position.y,value.size.x,value.size.y]
	if value is Transform2D: return {"x":portable(value.x),"y":portable(value.y),"origin":portable(value.origin)}
	if value is Color: return [value.r,value.g,value.b,value.a]
	if value is Dictionary:
		var out: Dictionary = {}
		var keys: Array = value.keys();keys.sort_custom(func(a:Variant,b:Variant)->bool:return str(a)<str(b))
		for key: Variant in keys: out[str(key)]=portable(value[key])
		return out
	if value is Array or value is PackedVector2Array:
		var out: Array=[]
		for item: Variant in value: out.append(portable(item))
		return out
	return value
func digest(value: Variant) -> String: return JSON.stringify(portable(value)).sha256_text()
func descendants(node: Node) -> Array:
	var out: Array=[]
	for child: Node in node.get_children(): out.append(child);out.append_array(descendants(child))
	return out
func simulation() -> Dictionary:
	return {"battle":game.battle.snapshot(),"power_time":game.battle.powers.time,
		"power_states":game.battle.powers._states.duplicate(true),"traces":game.battle.powers.traces.duplicate(true),"events":game.battle.powers.events.duplicate(true),
		"defence":game.battle.powers.defence.states.duplicate(true),"roster_time":game.battle.roster.time,"roster":game.battle.roster.states.duplicate(true),
		"ecology_time":game.battle.roster.ecology.time,"ecology":game.battle.roster.ecology.states.duplicate(true),"director":game.battle.continuous.snapshot()}
func controls() -> Dictionary:
	var cards: Array=[]
	for node: Node in descendants(game.menus):
		if node is Button and node.has_meta("power_id"): cards.append([node.get_instance_id(),str(node.get_meta("power_id"))])
	var focus: Control=game.get_viewport().gui_get_focus_owner()
	return {"content":game.menus._content.get_instance_id(),"cards":cards,
		"inspector":game.menus._ability_inspector.get_instance_id() if is_instance_valid(game.menus._ability_inspector) else 0,
		"reroll":game.menus._reroll_control.get_instance_id() if is_instance_valid(game.menus._reroll_control) else 0,
		"focus":focus.get_instance_id() if is_instance_valid(focus) else 0}
func settle(count: int = 4) -> void:
	for tick: int in range(count):
		if is_instance_valid(game):
			game._process(0.0)
			game.battle.set_physics_process(false)
		await process_frame
		if movie and not film_phase.is_empty():
			film_tick+=1
			if film_tick%2==0:
				await RenderingServer.frame_post_draw
				var image: Image=root.get_texture().get_image()
				var path: String=frames.path_join("film_%05d.png" % film.size())
				check(image.save_png(path)==OK,"Fresh actual animated choice film frame")
				film.append({"path":path,"sha256":FileAccess.get_sha256(path),"client":root.size,"pixels":image.get_size(),"screen":game.screen,"phase":film_phase,"art_frames":game.menus._art_animations.map(func(row:Dictionary)->int:return int(row.frame))})
func phase(label: String, hold: int = 90) -> void:
	if not movie: return
	film_phase=label
	var first: int=film.size()
	await settle(hold)
	phases.append({"label":label,"screen":game.screen,"first_frame":first,"last_frame":film.size()-1,"client":root.size})
func button(intent: String, power_id: String = "") -> Button:
	for node: Node in descendants(game.menus):
		if node is Button and node.is_visible_in_tree() and not node.disabled and str(node.get_meta("intent",""))==intent:
			if power_id.is_empty() or str(node.get_meta("power_id",""))==power_id: return node
	return null
func transform(node: Control) -> Transform2D:
	var mapped: Transform2D=node.get_global_transform_with_canvas()
	if mobile: mapped=shell.surface.get_global_transform_with_canvas()*mapped
	return root.get_final_transform()*mapped
func area(node: Control) -> Rect2: return transform(node)*Rect2(Vector2.ZERO,node.size)
func point(node: Control) -> Vector2: return transform(node)*(node.size*.5)
func motion(position: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=position;event.global_position=position;event.button_mask=0
	root.push_input(event,false);await settle(4)
func click(target: Button) -> void:
	check(is_instance_valid(target),case_id+" / actual pointer target exists")
	if not is_instance_valid(target): return
	var position: Vector2=point(target)
	var intended: String=str(target.get_meta("intent",""))
	var payload: Variant=target.get_meta("payload") if target.has_meta("payload") else null
	var safe: Rect2=Rect2(MOBILE_SAFE) if mobile else Rect2(Vector2.ZERO,Vector2(root.size))
	check(safe.has_point(position),case_id+" / physical pointer target is inside actual safe client")
	await motion(position)
	check(target.is_hovered(),case_id+" / physical projection reaches actual Button hover")
	var before: int=game.audit_actions.size()
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=position;event.global_position=position;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,false);await settle(4)
	inputs.append({"case":case_id,"type":"physical_client_pointer","point":position,"intent":intended,"payload":payload,"actions":game.audit_actions.slice(before),"screen_after":game.screen,"push_input_in_local_coords":false,"synthetic_ui_only":true})
	if not intended.is_empty(): check(intended in game.audit_actions.slice(before),case_id+" / actual Main handler receives projected "+intended)
func inspect_card(card: Button) -> void:
	check(is_instance_valid(card),case_id+" / actual inspection card exists")
	if not is_instance_valid(card): return
	var before: Dictionary=game.run_context.power_ranks
	await motion(point(card))
	check(card.is_hovered(),case_id+" / projected hover reaches intended card")
	check(game.menus._ability_inspector.power_id==str(card.get_meta("inspection_power","")),case_id+" / actual inspector follows physical card hover")
	check(game.run_context.power_ranks==before,case_id+" / hover inspection cannot claim an investment")
	inputs.append({"case":case_id,"type":"physical_client_inspection","power_id":card.get_meta("power_id",""),"physical_card_rect":area(card),"physical_inspector_rect":area(game.menus._ability_inspector),"point":point(card),"push_input_in_local_coords":false})
func uniform(node: Control) -> bool:
	# Uniform authored components must not add deformation to the accepted
	# outer Window projection (whose integer canvas can round fractionally).
	var mapping: Transform2D=node.get_global_transform_with_canvas()
	if mobile: mapping=shell.surface.get_global_transform_with_canvas()*mapping
	return is_equal_approx(mapping.x.length(),mapping.y.length()) and absf(mapping.x.dot(mapping.y))<0.01
func audit(label: String, expected_cards: int = 0) -> void:
	await settle(7)
	var snap: Dictionary=game.menus.presentation_snapshot()
	check(game.screen==label and game.menus.screen==label,case_id+" / actual Main/Menus screen "+label)
	check(snap.presentation_class=="modal",case_id+" / in-run presentation remains modal")
	check(game.combat_viewport.size==Vector2i(640,360),case_id+" / canonical Battle viewport remains 640×360")
	check(game.battle.paused and game.battle.visible,case_id+" / actual arena remains visible and paused under choices")
	if native: check(not root.borderless and root.mode in [Window.MODE_WINDOWED,Window.MODE_MAXIMIZED],case_id+" / actual Windows client stays decorated")
	if not mobile:
		check(str(snap.get("presentation_policy",""))=="run_overlay",case_id+" / desktop uses responsive run overlay")
		check(snap.root_rect==Rect2(Vector2.ZERO,snap.canvas_size) and snap.root_scale==Vector2.ONE,case_id+" / actual run overlay fills logical canvas without whole-panel stretch")
		check((root.get_final_transform()*snap.root_rect).grow(.8).encloses(Rect2(Vector2.ZERO,Vector2(root.size))),case_id+" / actual Window projection covers entire physical client")
	else:
		var accepted: Dictionary=Layout.responsive(Vector2(shell.game_view.size),true,shell.layout_snapshot().safe_rect)
		check(str(snap.get("presentation_policy",""))=="modal",case_id+" / accepted Android modal policy remains unchanged")
		check(snap.root_rect.is_equal_approx(Rect2(accepted.menu_origin,Vector2(640,360)*float(accepted.menu_scale))),case_id+" / Android authored modal origin and scale remain accepted")
	var safe: Rect2=Rect2(MOBILE_SAFE) if mobile else Rect2(Vector2.ZERO,Vector2(root.size))
	var cards: Array[Dictionary]=[]
	var visible_buttons: Array[Dictionary]=[]
	var fit_failures: Array[String]=[]
	for node: Node in descendants(game.menus._content):
		if not node is Control or not node.is_visible_in_tree(): continue
		if node is Button:
			check(safe.grow(.8).encloses(area(node)),case_id+" / "+label+" complete interactive target is safe: "+str(node.name))
			visible_buttons.append({"name":str(node.name),"intent":node.get_meta("intent",""),"rect":area(node),"disabled":node.disabled})
			if node.has_meta("power_id"):
				check(uniform(node),case_id+" / authored card preserves uniform pixel proportions")
				cards.append({"id":node.get_meta("power_id"),"rect":area(node),"scale":node.scale,"native_size":node.size})
		if node is Label and not node.text.is_empty():
			if node.get_visible_line_count()<node.get_line_count(): fit_failures.append(str(node.name)+": "+node.text)
	check(fit_failures.is_empty(),case_id+" / "+label+" actual shaped text is completely visible: "+str(fit_failures))
	check(cards.size()==expected_cards,case_id+" / "+label+" shows exact legal card count")
	for index: int in range(cards.size()):
		for other: int in range(index+1,cards.size()): check(not cards[index].rect.intersects(cards[other].rect),case_id+" / choice cards have independent non-overlapping targets")
	var inspector: Rect2=Rect2()
	if is_instance_valid(game.menus._ability_inspector):
		inspector=area(game.menus._ability_inspector)
		check(safe.grow(.8).encloses(inspector) and uniform(game.menus._ability_inspector),case_id+" / complete inspector is safe and uniformly rendered")
		for card: Dictionary in cards: check(not inspector.intersects(card.rect),case_id+" / inspector cannot occlude a choice card")
	var image_path: String=""
	if native:
		await RenderingServer.frame_post_draw
		var pixels: Image=root.get_texture().get_image()
		check(pixels.get_size()==root.size,case_id+" / capture contains the complete actual client")
		image_path=frames.path_join(case_id+"_"+label+".png")
		check(not FileAccess.file_exists(image_path) and pixels.save_png(image_path)==OK,"Fresh full-client choice PNG")
		images.append({"case":case_id,"screen":label,"path":image_path,"sha256":FileAccess.get_sha256(image_path),"pixels":pixels.get_size()})
	observations.append({"case":case_id,"screen":label,"client":root.size,"mobile_simulation":mobile,"window_mode":root.mode,"presentation":snap,"root_final_transform":root.get_final_transform(),"cards":cards,"inspector_rect":inspector,"buttons":visible_buttons,"font_fit_failures":fit_failures,"simulation_sha256":digest(simulation()),"control_identity":controls(),"image":image_path,"physical_safe":safe,"shell":shell.layout_snapshot() if mobile else {}})
func resize_proof(size: Vector2i, os_mode: int = -1) -> void:
	var state_before: String=digest(simulation())
	var controls_before: Dictionary=controls()
	var old_size: Vector2i=root.size
	if os_mode>=0: root.mode=os_mode
	else: root.size=size
	await settle(16)
	check(state_before==digest(simulation()),case_id+" / presentation resize cannot advance actors, RPM, power clocks or Director")
	check(controls_before==controls(),case_id+" / presentation resize retains exact card, inspector, reroll and focus identity")
	var focused_lift: Array[Dictionary]=[]
	for entry: Dictionary in game.menus._card_animations:
		if is_instance_valid(entry.card) and entry.card.has_focus():
			var expected: Vector2=entry.position+Vector2(0,-2)
			check(entry.card.position.is_equal_approx(expected),case_id+" / resize preserves actual focused-card two-pixel lift")
			focused_lift.append({"position":entry.card.position,"layout_home":entry.position,"expected":expected,"focused":entry.card.has_focus()})
	check(not focused_lift.is_empty(),case_id+" / actual focused-card animation entry survives resize")
	inputs.append({"case":case_id,"type":"native_OS_API_mode" if os_mode>=0 else "actual_client_resize","before_client":old_size,"after_client":root.size,"requested_mode":os_mode,"simulation_before":state_before,"simulation_after":digest(simulation()),"control_identity_before":controls_before,"control_identity_after":controls(),"focused_lift":focused_lift,"synthetic_ui_only":true})
func reconnect_proof() -> void:
	var original_focus: Control=game.get_viewport().gui_get_focus_owner()
	var before_id: String=game.menus.focused_power_id()
	for pressed: bool in [true,false]:
		var event:=InputEventJoypadButton.new();event.device=3;event.button_index=JOY_BUTTON_DPAD_RIGHT;event.pressed=pressed
		Input.parse_input_event(event);await settle(3)
	check(not game.menus.focused_power_id().is_empty() and game.get_viewport().gui_get_focus_owner()!=original_focus,case_id+" / delivered logical pad moves focus to a distinct real card")
	var state_before: String=digest(simulation())
	var before: Dictionary=controls()
	Input.joy_connection_changed.emit(3,false);Input.joy_connection_changed.emit(3,true)
	await settle(5)
	check(before==controls(),case_id+" / logical reconnect preserves focused card and control identity")
	check(state_before==digest(simulation()),case_id+" / logical reconnect cannot alter frozen arena")
	inputs.append({"case":case_id,"type":"logical_reconnect_callback","device":3,"delivered_button":JOY_BUTTON_DPAD_RIGHT,"focus_before_navigation":before_id,"focus_after_navigation":game.menus.focused_power_id(),"signal":"Input.joy_connection_changed","controls_before":before,"controls_after":controls(),"physical_hardware_acceptance":false})
func prepare_case(size: Vector2i, name: String, is_mobile: bool = false) -> void:
	case_id=name;mobile=is_mobile
	root.mode=Window.MODE_WINDOWED;root.borderless=false;root.size=size;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_factor=1
	await settle(4)
	var path: String=prefix+"_"+case_id+".json"
	check(not FileAccess.file_exists(path),"New isolated initial collection")
	game=QuietMain.new();game.smoke_mode=true;game.qa_task_id="003A.2";game.collection_path=path
	if mobile:
		shell=IsolatedShell.new();root.add_child(shell);shell.mount_mobile_surface(game);shell.set_process(false);shell.apply_display_layout(size,MOBILE_SAFE)
	else: root.add_child(game)
	game.set_process(false);game.battle.set_physics_process(false);await settle(5)
	check(game.collection.save_path==path,"Actual Main opened exact isolated profile")
	check(bool(game.collection.initialize_starter("vane").ok),"Normal starter ownership commits only the new isolated save")
	if native: DisplayServer.window_set_title("Spinning Metal / ISOLATED LEVEL-UP FULL-CLIENT QA / "+case_id)
	game._clear_run();game.run_context.start(game.collection.equipped_build(),421717,"vane")
	game.run_context._owned_power_ids.assign(["orbit_drive","afterimage","momentum_bank"])
	game.run_context._power_ranks={"orbit_drive":2,"afterimage":1,"momentum_bank":1}
	game.run_context._pending_offer.clear();game.run_context._draft_queue.clear()
	game._launch_run_encounter();game.battle.set_physics_process(false)
	var ticks: int=0
	while game.battle.battle_status!="battle" and ticks<240:
		game.battle.test_step(Physics.FIXED_DT);ticks+=1
	for tick: int in range(12): game.battle.test_step(Physics.FIXED_DT,Vector2(.3,.1),false,false)
	check(game.battle.battle_status=="battle","Actual initial Run solver entered combat before presentation fixture")
	game.battle.set_paused(true);game._draft_resume_origin="battle"
	game.run_context._pending_offer.assign(["orbit_drive","afterimage","momentum_bank"])
	game.run_context._draft_queue.assign([{"id":"draft/levelup_fullclient/"+case_id,"kind":"level","level":5}])
	game.screen="level_up";game._level_up_remaining=.18;game.menus.show_level_up(5)
func pause_regression() -> void:
	game.screen="pause";game.pause_origin="reward";game.menus.show_pause(true)
	await settle(5)
	var snap: Dictionary=game.menus.presentation_snapshot()
	check(snap.presentation_class=="modal" and str(snap.get("presentation_policy",""))=="modal","Pause retains accepted modal policy")
	if not mobile: check(snap.root_scale==Vector2.ONE and snap.root_rect.is_equal_approx(Rect2((Vector2(snap.canvas_size)-Vector2(640,360))*.5,Vector2(640,360))),"Desktop Pause remains unchanged scale-one 640×360 panel")
	inputs.append({"case":case_id,"type":"pause_regression","presentation":snap,"simulation_sha256":digest(simulation())})
func navigation() -> void:
	if case_id=="native_maximized":
		var before: String=digest(simulation())
		root.mode=Window.MODE_MAXIMIZED;await settle(16)
		check(root.mode==Window.MODE_MAXIMIZED and root.size.x>=1280,"Actual native OS maximise uses real client size")
		check(before==digest(simulation()),"Native maximise cannot alter initial paused Run")
	await audit("level_up");await phase("LEVEL UP / FULL CLIENT",60)
	game._show_reward();await audit("reward",3)
	var desired: Button=button("choose_power","orbit_drive")
	await inspect_card(desired);await reconnect_proof()
	if not mobile:
		var original: Vector2i=root.size
		if case_id=="native_maximized":
			await resize_proof(Vector2i.ZERO,Window.MODE_WINDOWED)
			check(root.size==Vector2i(1280,720),"True OS Restore returns pre-Maximise client without size assignment")
			await resize_proof(Vector2i.ZERO,Window.MODE_MAXIMIZED)
			check(root.size==original,"Native maximise returns the same actual client")
		else:
			await resize_proof(Vector2i(1280,720) if original==Vector2i(800,480) else Vector2i(800,480))
			await resize_proof(original)
	await phase("THREE POWERS / PHYSICAL INSPECTION",100)
	var initial_charges: int=game.run_context.reroll_charges
	var revision: int=int(game.run_context.reroll_snapshot().revision)
	var frozen: String=digest(simulation())
	await click(button("reroll_power"))
	check(game.screen=="reward" and game.run_context.reroll_charges==initial_charges-1 and int(game.run_context.reroll_snapshot().revision)==revision+1,case_id+" / real projected reroll consumes exactly one charge and revision")
	check(frozen==digest(simulation()),case_id+" / reroll preserves actual frozen combat state")
	# Re-present the declared legal offer after measuring the one real reroll.
	# No new currency/pickup is injected and the revised draft identity is kept.
	game.run_context._pending_offer.assign(["orbit_drive","afterimage","momentum_bank"]);game._show_reward();await settle(4)
	await click(button("choose_power","orbit_drive"))
	check(game.screen=="mutation" and game.run_context.pending_mutation_offer==Powers.mutation_choices("orbit_drive"),case_id+" / actual Rank II choice opens both legal siblings")
	check(int(game.run_context.power_ranks.get("orbit_drive",0))==2 and game.run_context.power_mutations.is_empty(),case_id+" / parent pointer release cannot preselect either mutation")
	check(frozen==digest(simulation()),case_id+" / opening mutation cannot advance or acquire a power before choice")
	await audit("mutation",2);await inspect_card(button("choose_mutation"));await reconnect_proof();await phase("TWO MUTATIONS / INDEPENDENT CHOICE",110)
	if mobile:
		var read: Button=game.menus._content.get_node_or_null("ReadPower_orbit_drive")
		var ranks: Dictionary=game.run_context.power_ranks
		await click(read)
		check(game.screen=="mutation" and game.run_context.power_ranks==ranks,"Accepted Android READ is distinct from mutation commitment")
	await click(button("choose_mutation"))
	check(game.screen=="acquisition" and int(game.run_context.power_ranks.get("orbit_drive",0))==3,case_id+" / one actual mutation claim resolves to acquisition")
	check(game.battle.player_entity().get("power_ranks",{}).get("orbit_drive",0)==3,case_id+" / actual in-run mutation reaches owned player state once")
	await audit("acquisition");await phase("LOCKED IN / REAL AUTHORED ACQUISITION",110)
	await pause_regression()
func valid_paths() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
		if arg.begins_with("--profile-prefix="): prefix=arg.trim_prefix("--profile-prefix=")
		if arg.begins_with("--frames="): frames=arg.trim_prefix("--frames=")
		if arg=="--native": native=true
		if arg=="--movie": movie=true;native=true
		if arg.begins_with("--collection-path=") or arg in ["--smoke-test","--qa-catalogue","--reset-collection"]: return false
	var qa: String=OS.get_environment("TOPGAME_QA_ROOT").path_join("003A.2")
	if OS.get_environment("TOPGAME_QA_ROOT").is_empty(): return false
	for item: Array in [[report,"manifests"],[prefix,"temp"]]:
		var path: String=str(item[0]).replace("\\","/").simplify_path()
		if not path.is_absolute_path() or not path.to_lower().begins_with(qa.replace("\\","/").simplify_path().path_join(str(item[1])).to_lower()+"/") or FileAccess.file_exists(path): return false
	if native:
		if DisplayServer.get_name()=="headless" or not frames.is_absolute_path() or not frames.replace("\\","/").to_lower().begins_with(qa.replace("\\","/").to_lower()+"/frames/") or DirAccess.dir_exists_absolute(frames): return false
		DirAccess.make_dir_recursive_absolute(frames)
	return true
func run() -> void:
	check(valid_paths(),"Fresh explicit external QA paths required before mounting Main")
	if not failures.is_empty(): quit(2);return
	root.min_size=Vector2i(800,480);root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var sizes: Array[Vector2i]=[]
	if movie: sizes.append(Vector2i(1920,1080))
	else: sizes.assign(SIZES)
	for size: Vector2i in sizes:
		await prepare_case(size,"%dx%d" % [size.x,size.y]);await navigation();film_phase="";game.free();game=null;await settle(3)
	if not movie:
		if native: await prepare_case(Vector2i(1280,720),"native_maximized");await navigation();game.free();game=null;await settle(3)
		await prepare_case(MOBILE_SIZE,"android_2340x1080_cutout",true);await navigation();shell.free();shell=null;game=null;await settle(3)
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify(portable({"schema":"levelup-fullclient-003a2-v1","checks":checks,"failures":failures,"native":native,"movie":movie,"observations":observations,"inputs":inputs,"images":images,"film":film,"phases":phases,"physical_phone_acceptance":false,"physical_controller_acceptance":false,"scope":"Actual production Main/Menus/Shell. Initial starter and legal invested Run with pending Level5 are disclosed fixtures, not earned XP. The Run uses ordinary initial ready and12 actual solver ticks before pausing. No actor/RPM/outcome injection or ongoing resource holds. Main UI timers are held with delta0 while actual authored card/acquisition animation runs. One real reroll per fixture consumes its starting charge; the declared legal pending offer is re-presented afterward without new charges. Actual pointer projection uses final Window+Control transforms and push_input(false), including the real hosted mobile surface. Native OS Maximise/Restore is API-actuated, not human caption-button acceptance. Android safe-area run is a Windows simulation; Pause and Android modal policies are regression-only."}),"\t"));file.close()
	print("LEVELUP_FULLCLIENT_003A2_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
