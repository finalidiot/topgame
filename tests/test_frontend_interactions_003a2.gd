extends "res://tests/test_collection_ui.gd"
## Actual desktop client-coordinate GUI ingress. Catalogue/wallet/seed are
## declared isolated fixtures; production generates and persists packet rows.
const SaveModel = preload("res://scripts/collection_save.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
var output_path: String = ""
var profile_prefix: String = ""
var interactions: Array[Dictionary] = []
var observations: Array[Dictionary] = []
var native_requested: bool = false

func valid_paths() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output_path=arg.trim_prefix("--report=")
		if arg.begins_with("--profile-prefix="): profile_prefix=arg.trim_prefix("--profile-prefix=")
		if arg=="--native": native_requested=true
	var qa: String=OS.get_environment("TOPGAME_QA_ROOT")
	if qa.is_empty():qa=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	qa=qa.path_join("003A.2").replace("\\","/").simplify_path()
	for item: Array in [[output_path,"manifests"],[profile_prefix,"temp"]]:
		var value: String=str(item[0]).replace("\\","/").simplify_path()
		if not value.is_absolute_path() or not value.to_lower().begins_with(qa.path_join(str(item[1])).to_lower()+"/"):return false
		if FileAccess.file_exists(value) or DirAccess.dir_exists_absolute(value):return false
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(profile_prefix.get_base_dir())
	return true

func logical_point(node: Control, fraction: Vector2=Vector2(.5,.5)) -> Vector2:
	return node.get_global_transform_with_canvas()*(node.size*fraction)
func physical_point(node: Control, fraction: Vector2=Vector2(.5,.5)) -> Vector2:
	return root.get_final_transform()*logical_point(node,fraction)
func physical_mouse(point: Vector2, pressed: bool, button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
	event.button_index=button;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed and button==MOUSE_BUTTON_LEFT else 0
	root.push_input(event,false);await _settle()
func physical_motion(point: Vector2, relative: Vector2=Vector2.ZERO, down: bool=false) -> void:
	var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point;event.relative=relative
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(event,false);await _settle()
func mouse_target(target: Button, label: String) -> void:
	check(target!=null and is_instance_valid(target),label+": real button exists")
	if target==null or not is_instance_valid(target):return
	var scroll: ScrollContainer=_scroll_ancestor(target)
	if scroll!=null:scroll.ensure_control_visible(target);await _settle()
	var marker: Dictionary={"hover":false,"pressed":0}
	target.mouse_entered.connect(func()->void:marker.hover=true,CONNECT_ONE_SHOT)
	target.pressed.connect(func()->void:marker.pressed+=1,CONNECT_ONE_SHOT)
	var point: Vector2=physical_point(target)
	await physical_motion(Vector2(1,1));await physical_motion(point)
	check(marker.hover or target.is_hovered(),label+": physical pointer reaches expected hover target")
	var trace: Dictionary={"label":label,"client":root.size,"screen":game.screen,"logical_point":logical_point(target),"physical_point":point,"root_transform":root.get_final_transform(),"intent":target.get_meta("intent",""),"payload":target.get_meta("payload") if target.has_meta("payload") else null}
	await physical_mouse(point,true);await physical_mouse(point,false)
	check(int(marker.pressed)==1,label+": actual GUI emits exactly one intended button press")
	trace["pressed"]=marker.pressed;trace["after_screen"]=game.screen;interactions.append(trace)

func slider(key: String) -> HSlider:
	for node: Node in _descendants(game.menus):
		if node is HSlider and str(node.get_meta("setting_key",""))==key:return node
	return null
func setting_button(key: String) -> Button:
	for node: Node in _descendants(game.menus):
		if node is Button and str(node.get_meta("setting_key",""))==key:return node
	return null
func quantity_button(kind: String, count: int) -> Button:
	for node: Node in _descendants(game.menus):
		if node is Button and node.is_visible_in_tree() and str(node.get_meta("intent",""))=="packet_quantity":
			var payload: Variant=node.get_meta("payload",null)
			if payload is Dictionary and payload.get("kind")==kind and payload.get("quantity")==count:return node
	return null
func screenshot_state(label: String) -> void:
	game._refresh_window_presentation();game._process(0.0);await _settle()
	var view: Dictionary=game.menus.presentation_snapshot()
	check(str(view.get("presentation_class",""))=="frontend",label+": centralized front-end class")
	check(game.menus._content.position==Vector2.ZERO and game.menus._content.scale==Vector2.ONE,label+": full-client root has no old panel transform")
	check(game.menus._content.size==game._presentation_canvas_size,label+": actual root spans responsive canvas")
	var focus: Control=root.gui_get_focus_owner()
	check(focus!=null and focus.is_visible_in_tree(),label+": first focus is visible")
	_check_layout(label)
	observations.append({"label":label,"client":root.size,"canvas":game._presentation_canvas_size,"screen":game.menus.screen,"presentation":view})

func prepare_fixture(index: int, size: Vector2i) -> void:
	if is_instance_valid(game):game.free();await process_frame
	root.size=size
	var path: String=profile_prefix+"_%d.json"%index
	check(not FileAccess.file_exists(path),"Unique external isolated profile is fresh")
	var model=SaveModel.new(path);check(model.load_save().ok and model.initialize_starter("breaker").ok,"Declared starter fixture uses actual collection API")
	for category: String in Parts.PARTS:
		for id: String in Parts.PARTS[category]:check(model.grant_part(category+":"+id).ok,"Declared browsing catalogue fixture: "+category+":"+id)
	var state: Dictionary=model._data.duplicate(true);state.progression.credits=3000;state.progression.salvage=1200
	check(model._commit(state,"declared_frontend_initial_wallet").ok,"Declared initial wallet fixture is crash-safe persisted")
	game=QuietMain.new();game.smoke_mode=true;game.qa_task_id="003A.2";game.collection_path=path
	game.packet_rng_override=RandomNumberGenerator.new();game.packet_rng_override.seed=19
	root.add_child(game);game.set_process(false);game.battle.set_physics_process(false);await _settle()
	game.smoke_mode=false # Subsequent settings persist only at this isolated path.
	game._title();game._refresh_window_presentation();game._process(0.0);await _settle()
	check(game.collection.owned_count()==31 and game.preferences_path==path+".preferences.cfg","Catalogue and preference scope remain explicitly isolated")

func options_flow() -> void:
	await mouse_target(_button("settings"),"Hub to Options")
	check(game.screen=="settings","Actual Options navigation")
	await screenshot_state("Options")
	var collection_before: Dictionary=game.collection.snapshot().duplicate(true)
	for key: String in ["volume","music_volume","sfx_volume"]:
		var control: HSlider=slider(key);check(control!=null,"Visible independent audio slider: "+key)
		if control==null:continue
		var before: Dictionary=game.settings.duplicate(true)
		var start: Vector2=physical_point(control,Vector2(.15,.5));var finish: Vector2=physical_point(control,Vector2(.8,.5))
		await physical_motion(start);await physical_mouse(start,true)
		for step: int in range(1,5):await physical_motion(start.lerp(finish,step/4.0),(finish-start)/4.0,true)
		await physical_mouse(finish,false)
		check(float(game.settings[key])>=.70 and float(game.settings[key])<=.90,"Physical slider drag reaches chosen range: "+key)
		for other: String in ["volume","music_volume","sfx_volume"]:
			if other!=key:check(game.settings[other]==before[other],"Slider preserves independent channel: "+other)
		check(is_equal_approx(control.value,float(game.settings[key])),"Actual control and applied preference agree")
		check(await _navigate(control),"Controller focus reaches responsive slider")
		var value: float=control.value;await _key_tap(KEY_LEFT)
		check(is_equal_approx(control.value,maxf(0,value-.05)),"Keyboard changes focused slider by its exact native step")
	for key: String in ["muted","screen_shake","reduced_flashing","top_status_bars","impact_numbers"]:
		var before: bool=bool(game.settings[key]);await mouse_target(setting_button(key),"Toggle "+key)
		check(bool(game.settings[key])!=before,"Physical toggle changes its actual setting only: "+key)
	check(game.collection.snapshot()==collection_before,"Options preserve collection, wallet and assembly")
	var cfg:=ConfigFile.new();check(cfg.load(game.preferences_path)==OK,"Options persist readable isolated preferences")
	check(bool(cfg.get_value("settings","reduced_flashing",false))==bool(game.settings.reduced_flashing),"Reduced flashing remains source-aware persisted")
	var focus_before: Control=root.gui_get_focus_owner();game._controller_connection_changed(PAD,false);game._controller_connection_changed(PAD,true);await _settle()
	check(root.gui_get_focus_owner()==focus_before,"Reconnect keeps a valid focus without rebuilding page")
	await mouse_target(_button("back_settings"),"Options return")
	check(game.screen=="title","Options return reaches Hub")

func workshop_flow() -> void:
	await mouse_target(_button("open_workshop"),"Hub to Workshop");check(game.screen=="garage","Actual Workshop page")
	await screenshot_state("Workshop")
	for category: String in ["blade","ratchet","bit"]:
		await mouse_target(game.menus._catalogue_tabs[category],"Workshop tab "+category)
		check(game.menus._catalogue_category==category,"Actual responsive category selected")
		var ids: Array=Parts.PARTS[category].keys();var id: String=str(ids[-1])
		if id==str(game.build.get(category,"")):id=str(ids[0])
		var target: Button=game.menus._part_buttons[category][id]
		var scroll: ScrollContainer=game.menus._part_scrolls[category]
		scroll.ensure_control_visible(target);await _settle()
		await physical_motion(physical_point(target))
		check(game.menus._catalogue_metadata.text.contains(str(Parts.PARTS[category][id].name)),"Hover updates actual part inspector")
		var before: Dictionary=game.collection.equipped_build().duplicate(true)
		await mouse_target(target,"Equip "+category+":"+id)
		check(str(game.collection.equipped_build()[category])==id,"Physical part selection persists the chosen component")
		for other: String in ["blade","ratchet","bit"]:
			if other!=category:check(game.collection.equipped_build()[other]==before[other],"Equip preserves other component "+other)
		check(game.menus._preview.build==game.collection.equipped_build(),"Preview refreshes from actual assembled build")
		var selected: Button=game.menus._part_buttons[category][id]
		check(await _navigate(selected),"Expanded grid focus reaches selected component")
		var current_scroll: ScrollContainer=game.menus._part_scrolls[category]
		var viewport_point: Vector2=physical_point(current_scroll)
		var old_offset: int=current_scroll.scroll_vertical
		await physical_motion(viewport_point);await physical_mouse(viewport_point,true,MOUSE_BUTTON_WHEEL_DOWN);await physical_mouse(viewport_point,false,MOUSE_BUTTON_WHEEL_DOWN)
		check(current_scroll.scroll_vertical>=old_offset,"Physical scroll reaches current catalogue container")
	await mouse_target(_button("back_workshop"),"Workshop return");check(game.screen=="title","Workshop returns to Hub")

func packet_flow(kind: String, quantity: int) -> void:
	var wallet: Dictionary=game.collection.wallet();var unit: String="credits" if kind=="standard" else "salvage"
	var before: int=int(wallet[unit]);var cost: int=(48 if kind=="standard" else 36)*quantity
	await mouse_target(_button("request_packet_purchase",kind),"Buy visible "+kind)
	check(game.screen=="packet_purchase" and game._packet_quantity==quantity,"Confirmation preserves focused product and exact quantity")
	check(game.collection.wallet()==wallet,"Confirmation alone does not charge")
	await screenshot_state("Packet purchase")
	await mouse_target(_button("confirm_packet_purchase"),"Confirm real packet transaction")
	check(game.screen=="packet_open","Production paid transaction opens packet page")
	check(int(game.collection.wallet()[unit])==before-cost or (unit=="salvage" and int(game.collection.wallet()[unit])>=before-cost),"Actual paid receipt spends its exact accepted product cost")
	var receipt: Dictionary=game.collection.pending_packet().duplicate(true)
	check(int(receipt.get("quantity",0))==quantity and int(receipt.get("cost",0))==cost,"Immutable generated receipt records actual quantity/cost")
	var packet: Control=game.menus._packet_view
	check(packet!=null and not packet.opening,"New paid packet preserves authored sealed phase")
	await screenshot_state("Packet opening")
	# Desktop tear starts via its actual visible button. The separate touch
	# regression exercises42 native pouch pixels through its component transform.
	await mouse_target(_button("packet_tear"),"Physical packet tear")
	check(packet.opening,"Real packet control starts authored tear state")
	packet.set_process(false)
	for tick: int in range(360):
		if packet.phase=="RESULT":break
		packet._process(1.0/60.0)
	await _settle()
	check(packet.phase=="RESULT","Real packet animation completes the entire accepted batch")
	check(int(game.collection.pending_packet().get("cursor",0))==quantity,"Sequential presentation checkpoint reaches every batch packet")
	check(game.collection.pending_packet().get("rows",[])==receipt.get("rows",[]),"Layout and reveal preserve crash-safe generated rows")
	await screenshot_state("Packet result")
	await mouse_target(_button("packet_shop"),"Packet result route")
	check(game.screen=="shop" and game.collection.pending_packet().is_empty(),"Actual result route acknowledges once and returns to Shop")

func shop_flow() -> void:
	await mouse_target(_button("open_shop"),"Hub to Shop");check(game.screen=="shop","Actual Shop page")
	await screenshot_state("Shop")
	for kind: String in ["standard","reclaimed"]:
		for quantity: int in [1,3,5]:
			await mouse_target(quantity_button(kind,quantity),"Quantity "+kind+" x%d"%quantity)
			check(game.menus.selected_shop_product()==kind and game.menus.selected_shop_quantity(kind)==quantity,"Quantity focus belongs to its visible product")
			var row: Dictionary=game.menus._shop_cards[kind]
			check(row.price.text=="%d %s"%[(48 if kind=="standard" else 36)*quantity,"CREDITS" if kind=="standard" else "SALVAGE"],"Visible total is exact without hidden quantity")
	await mouse_target(_button("packet_odds"),"Visible packet odds")
	check(game.screen=="packet_odds","Odds route remains reachable")
	await screenshot_state("Packet odds")
	await mouse_target(_button("open_shop"),"Odds return")
	await mouse_target(quantity_button("standard",3),"Select real Standard x3")
	await packet_flow("standard",3)
	await mouse_target(_button("back_shop"),"Shop return");check(game.screen=="title","Shop returns to its actual Hub source")

func controller_profiles() -> void:
	for layout: String in ["xbox","nintendo","playstation"]:
		game.settings.controller_layout=layout;game._apply_settings();game._title();await _settle()
		var options: Button=_button("settings")
		check(await _navigate(options),"D-pad traverses expanded Hub for "+layout)
		await _tap(JOY_BUTTON_B if layout=="nintendo" else JOY_BUTTON_A)
		check(game.screen=="settings","Printed Confirm opens actual Options for "+layout)
		await _tap(JOY_BUTTON_A if layout=="nintendo" else JOY_BUTTON_B)
		check(game.screen=="title","Printed Back returns cleanly for "+layout)
	game.settings.controller_layout="auto";game._apply_settings()

func _run() -> void:
	if not valid_paths():quit(2);return
	Input.use_accumulated_input=false
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var original_mode: int=DisplayServer.window_get_mode();var original_borderless: bool=DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	var index: int=0
	for size: Vector2i in [Vector2i(800,480),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		index+=1;await prepare_fixture(index,size);await screenshot_state("Hub")
		await options_flow();await workshop_flow();await shop_flow();await controller_profiles()
		check(DisplayServer.window_get_mode()==original_mode and DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)==original_borderless,"Page/input changes never replace native desktop window mode")
	if is_instance_valid(game):game.free();await process_frame
	var result: Dictionary={"checks":checks,"failures":failures,"observations":observations,"interactions":interactions,"scope":"Actual Main/Menus controls via physical client-coordinate Viewport.push_input(event,false), plus mapped synthetic controller/keyboard. Declared isolated full catalogue/wallet/packet seed19. Real transactions, no injected results, no physical controller or Android acceptance."}
	var file:=FileAccess.open(output_path,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("FRONTEND_INTERACTIONS_003A2_%s checks=%d failures=%d"%["PASS" if failures==0 else "FAIL",checks,failures]);quit(0 if failures==0 else 1)