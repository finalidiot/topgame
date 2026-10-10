extends SceneTree
## UI-only desktop fixtures. Physical mouse projection uses push_input(false).
## Saves are isolated; no human hardware or phone acceptance is claimed.
const Physics = preload("res://scripts/battle.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
const PacketEconomy = preload("res://scripts/packet_economy.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
const SIZES: Array[Vector2i] = [Vector2i(800,480),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
var report: String = ""
var prefix: String = ""
var frames: String = ""
var native: bool = false
var showcase: bool = false
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var input_trace: Array[Dictionary] = []
var images: Array[Dictionary] = []
var film: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var live_controls: Array[Dictionary] = []
var game: QuietMain
var case_id: String = ""
var film_tick: int = 0
var current_phase: String = ""

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
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value: out[str(key)] = portable(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value: out.append(portable(item))
		return out
	return value
func settle(count: int = 3, live: bool = false) -> void:
	for tick: int in range(count):
		if is_instance_valid(game):
			game._process(Physics.FIXED_DT if live else 0.0)
			game.battle.set_physics_process(false)
			if live and game.screen == "battle":
				var steer: Vector2=Vector2(.3,.1)
				var brake: bool=false
				if showcase:
					# Disclosed QA player policy: current observed position/velocity
					# only. Ordinary paid mechanics; no held actors or outcomes.
					var player: Dictionary=game.battle.player_entity()
					var position: Vector2=player.pos
					var velocity: Vector2=player.vel
					var desired: Vector2=-position-velocity*.45
					steer=Vector2(desired.x-desired.y,(desired.x+desired.y)*.5).normalized()*minf(1.0,desired.length()/80.0)
					brake=position.length()>170.0 and velocity.dot(position)>30.0
					live_controls.append({"fixture":"observed centre/momentum correction; ordinary steering and Brake only","tick":film_tick,"elapsed":game.battle.elapsed,"status_before":game.battle.battle_status,"position":position,"velocity":velocity,"steer":steer,"brake":brake,"burst":false})
				game.battle.test_step(Physics.FIXED_DT,steer,false,brake)
		await process_frame
		if showcase and native and not current_phase.is_empty():
			film_tick += 1
			if film_tick%2==0:
				await RenderingServer.frame_post_draw
				var image: Image = root.get_texture().get_image()
				var path: String = frames.path_join("film_%05d.png" % film.size())
				check(image.save_png(path)==OK,"Fresh actual variable-client film frame")
				film.append({"path":path,"sha256":FileAccess.get_sha256(path),"client":root.size,"pixels":image.get_size(),"screen":game.screen,"phase":current_phase,"window_mode":root.mode,"borderless":root.borderless})
func descendants(node: Node) -> Array:
	var out: Array = []
	for child: Node in node.get_children(): out.append(child);out.append_array(descendants(child))
	return out
func target(intent: String, payload: Variant = null) -> Button:
	for node: Node in descendants(game.menus):
		if node is Button and node.is_visible_in_tree() and not node.disabled and str(node.get_meta("intent",""))==intent:
			if payload==null or (node.has_meta("payload") and node.get_meta("payload")==payload): return node
	return null
func physical_point(node: Control, point: Vector2) -> Vector2:
	return root.get_final_transform()*node.get_global_transform_with_canvas()*point
func physical_rect(node: Control) -> Rect2:
	return root.get_final_transform()*node.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,node.size)
func clipped_visible(node: Control) -> Rect2:
	var area: Rect2 = physical_rect(node)
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents: area = area.intersection(physical_rect(parent))
		parent = parent.get_parent()
	return area
func move_mouse(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new();motion.position=point;motion.global_position=point;motion.button_mask=0
	root.push_input(motion,false);await settle(2)
func click(node: Control) -> void:
	check(is_instance_valid(node),"Actual physical mouse target exists")
	if not is_instance_valid(node): return
	var point: Vector2 = physical_point(node,node.size*.5)
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(point),"Physical mouse target lies inside actual client")
	check(clipped_visible(node).has_point(point),"Physical mouse target lies inside actual unoccluded control clip")
	await move_mouse(point)
	if node is BaseButton: check(node.is_hovered(),"Physical projected hover reaches actual intended Button")
	var start: int = game.audit_actions.size()
	var intent: String = str(node.get_meta("intent",""))
	var payload: Variant = node.get_meta("payload") if node.has_meta("payload") else null
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.global_position=point;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,false);await settle(3)
	input_trace.append({"type":"physical_client_mouse","target":node.name if is_instance_valid(node) else "replaced","intent":intent,"payload":payload,"physical_point":point,"root_final_transform":root.get_final_transform(),"push_input_in_local_coords":false,"actions":game.audit_actions.slice(start),"screen_after":game.screen,"synthetic_ui_only":true})
	if not intent.is_empty() and intent != "catalogue_tab": check(intent in game.audit_actions.slice(start),"Actual handler receives intended projected mouse action: "+intent)
func mouse(intent: String, payload: Variant = null) -> void: await click(target(intent,payload))
func joy(button: JoyButton) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventJoypadButton.new();event.device=3;event.button_index=button;event.pressed=pressed
		Input.parse_input_event(event);await settle(2)
	input_trace.append({"type":"logical_controller","device":3,"button":button,"screen":game.screen,"physical_hardware_acceptance":false})
func navigate(node: Control) -> void:
	check(is_instance_valid(node),"Focus target exists")
	if not is_instance_valid(node): return
	var first: Control = root.gui_get_focus_owner()
	check(is_instance_valid(first),"Actual page installs an initial focus")
	if not is_instance_valid(first): return
	var routes: Dictionary = {first:[]};var queue: Array[Control] = [first]
	while not queue.is_empty():
		var current: Control = queue.pop_front()
		for side: int in range(4):
			if current is HSlider and side in [0,2]: continue # Left/right adjust Range rather than move focus.
			var path: NodePath = current.get_focus_neighbor(side)
			var next: Control = current.get_node_or_null(path) if not path.is_empty() else null
			if next==null or routes.has(next) or not next.is_visible_in_tree() or (next is BaseButton and next.disabled): continue
			var route: Array = routes[current].duplicate();route.append(side);routes[next]=route;queue.append(next)
	check(routes.has(node),"Actual expanded focus graph reaches requested control")
	if not routes.has(node): return
	for side: int in routes[node]: await joy([JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN][side])
	check(root.gui_get_focus_owner()==node,"Delivered logical controller navigation reaches actual identity")
func presentation() -> Dictionary:
	for method: String in ["frontend_layout_snapshot","presentation_snapshot","frontend_snapshot"]:
		if game.menus.has_method(method): return game.menus.call(method)
	check(false,"Production Menus exposes its central presentation snapshot")
	return {}
func audit(label: String, expected: String, kind: String = "frontend") -> void:
	await settle(5)
	check(game.screen==expected,"Actual Main screen is "+expected+" for "+label+" (actual="+game.screen+")")
	if native: check(root.mode in [Window.MODE_WINDOWED,Window.MODE_MAXIMIZED] and not root.borderless,"Native desktop remains decorated ordinary/maximized window")
	check(game.combat_viewport.size==Vector2i(640,360),"Presentation never resizes canonical combat viewport")
	var snap: Dictionary = presentation()
	var actual_kind: String = str(snap.get("presentation_class",snap.get("class",""))).to_lower()
	if actual_kind=="combat_modal": actual_kind="modal"
	check(actual_kind==kind,"Central classification is "+kind+" for "+label)
	var bounds: Rect2 = Rect2(Vector2.ZERO,Vector2(root.size))
	var content: Rect2 = physical_rect(game.menus._content)
	if kind=="frontend":
		check(content.size.x>=bounds.size.x*.85 and content.size.y>=bounds.size.y*.80,"Actual front-end root uses the available client rather than a centred640x360 island")
		check(bounds.grow(.1).encloses(content),"Actual front-end root remains inside physical client")
	var controls: Array[Dictionary] = [];var panels: Array[Dictionary] = [];var text_bounds: Array[Dictionary] = []
	for node: Node in descendants(game.menus):
		if not node is Control or not node.is_visible_in_tree(): continue
		if node is Panel: panels.append({"name":node.name,"physical_rect":physical_rect(node),"parent":str(node.get_parent().get_path())})
		if node is BaseButton or node is HSlider:
			var visible: Rect2 = clipped_visible(node)
			check(visible.size==Vector2.ZERO or bounds.grow(.1).encloses(visible),"Actual visible interactive raster remains inside client: "+label+" / "+node.name)
			controls.append({"name":node.name,"intent":node.get_meta("intent",""),"text":node.text if node is BaseButton else "slider","physical_rect":physical_rect(node),"visible_after_scroll_clip":visible,"focus_mode":node.focus_mode,"disabled":node.disabled if node is BaseButton else false})
		if kind=="frontend" and node is Label and not node.text.is_empty() and clipped_visible(node).is_equal_approx(physical_rect(node)):
			var height: float = 0.0
			for line: int in range(node.get_line_count()): height+=node.get_line_height(line)
			var width: float = 0.0
			if node.autowrap_mode==TextServer.AUTOWRAP_OFF:
				for line: String in node.text.split("\n"): width=maxf(width,node.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x)
				check(width<=node.size.x+1.0,"Actual unwrapped Label width fits: "+label+" / "+node.text.left(48))
			check(node.get_visible_line_count()==node.get_line_count(),"Actual shaped Label lines remain visible: "+label+" / "+node.text.left(48))
			check(height<=node.size.y+1.0,"Actual shaped Label height fits: "+label+" / "+node.text.left(48))
			text_bounds.append({"text":node.text,"physical_rect":physical_rect(node),"line_count":node.get_line_count(),"visible_lines":node.get_visible_line_count(),"shaped_height":height,"local_height":node.size.y,"unwrapped_width":width,"local_width":node.size.x,"autowrap":node.autowrap_mode})
	var focus: Control = root.gui_get_focus_owner()
	var overlaps: Array[Dictionary] = []
	for first: int in range(panels.size()):
		for second: int in range(first+1,panels.size()):
			var a: Dictionary = panels[first];var b: Dictionary = panels[second]
			var aa: Rect2 = a.physical_rect;var bb: Rect2 = b.physical_rect
			if a.parent!=b.parent or aa.size.x<bounds.size.x*.15 or bb.size.x<bounds.size.x*.15 or aa.size.y<bounds.size.y*.18 or bb.size.y<bounds.size.y*.18: continue
			var crossed: Rect2 = aa.intersection(bb)
			if crossed.get_area()<=0: continue
			var backdrop: bool = aa.grow(.1).encloses(bb) or bb.grow(.1).encloses(aa)
			overlaps.append({"first":a.name,"second":b.name,"intersection":crossed,"containment_background":backdrop})
			check(backdrop,"Actual peer major panels do not overlap: "+label)
	var row: Dictionary = {"case":case_id,"client_size":root.size,"main_screen_id":game.screen,"menu_screen_id":game.menus.screen,"screen_label":label,"presentation_class":actual_kind,"snapshot":snap.duplicate(true),"content_rect":content,"content_scale":game.menus._content.scale,"panels":panels,"controls":controls,"text_bounds":text_bounds,"focus_start":str(focus.get_path()) if is_instance_valid(focus) else "","window":game.window_presentation_snapshot().duplicate(true),"overlaps":overlaps,"clipping_failures":failures.size(),"mouse_hit_tests":input_trace.filter(func(r:Dictionary)->bool:return r.type=="physical_client_mouse").duplicate(true)}
	if game.screen=="settings" and game.menus._frontend_settings_nodes.has("controls_panel"):
		var pane: Control=game.menus._frontend_settings_nodes.controls_panel
		if pane.is_visible_in_tree():
			var order: Dictionary={"panel_index":pane.get_index()}
			for key: String in ["controller_button","window_note"]:
				var node: Control=game.menus._frontend_settings_nodes[key]
				check(pane.get_parent()==node.get_parent() and pane.get_index()<node.get_index(),"Actual Controls background paints below "+key)
				order[key+"_index"]=node.get_index()
			row["controls_paint_order"]=order
	observations.append(row)
	if native:
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		check(image.get_size()==root.size,"Native screenshot captures complete actual client")
		var path: String = frames.path_join(case_id+"_"+label+".png")
		check(not FileAccess.file_exists(path) and image.save_png(path)==OK,"Fresh full-client native screen")
		images.append({"case":case_id,"screen":label,"path":path,"sha256":FileAccess.get_sha256(path),"pixels":image.get_size(),"window_mode":root.mode})
		if game.screen=="settings" and row.has("controls_paint_order"):
			var proof: Array[Dictionary]=[]
			for key: String in ["controller_button","window_note"]:
				var node: Control=game.menus._frontend_settings_nodes[key]
				# Exclude all border pixels: actual glyphs must change the panel's
				# otherwise flat interior, even when hit testing still succeeds.
				var interior: Rect2i=Rect2i(physical_rect(node).grow(-4.0)).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
				var colours: Dictionary={}
				for y: int in range(interior.position.y,interior.end.y):
					for x: int in range(interior.position.x,interior.end.x): colours[image.get_pixel(x,y).to_html(false)]=true
				check(colours.size()>1,"Actual rendered text pixels remain visible inside "+key)
				proof.append({"element":key,"physical_rect":physical_rect(node),"interior_without_border":interior,"distinct_colours":colours.keys(),"source_image":path,"sha256":FileAccess.get_sha256(path)})
			observations.back()["controls_rendered_pixels"]=proof
func phase(label: String, hold: int = 90, live: bool = false) -> void:
	current_phase=label;var start: int = film.size()
	await settle(hold,live)
	phases.append({"label":label,"first_frame":start,"last_frame":film.size()-1,"client":root.size,"mode":root.mode,"borderless":root.borderless,"screen":game.screen,"actuation":"OS_API for maximize/restore/resize; synthetic GUI pointer elsewhere"})
func new_case(size: Vector2i) -> void:
	case_id="%dx%d" % [size.x,size.y]
	root.mode=Window.MODE_WINDOWED;root.borderless=false;root.size=size
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	await settle(4)
	game=QuietMain.new();game.smoke_mode=true;game.qa_task_id="003A.2";game.collection_path=prefix+"_"+case_id+".json"
	check(not FileAccess.file_exists(game.collection_path),"Fresh isolated page profile")
	root.add_child(game);game.set_process(false);game.battle.set_physics_process(false)
	await settle(5)
	check(game.collection.save_path==prefix+"_"+case_id+".json","Actual Main opens only explicit isolated save")
	if native: DisplayServer.window_set_title("Spinning Metal / ISOLATED FRONTEND FULL-CLIENT QA")
	game._title_gate()

func setting_control(key: String) -> Control:
	for node: Node in descendants(game.menus):
		if node is Control and node.is_visible_in_tree() and str(node.get_meta("setting_key",""))==key: return node
	return null
func slider_drag(key: String) -> void:
	var slider: HSlider = setting_control(key) as HSlider
	check(is_instance_valid(slider),"Actual expanded Options slider exists: "+key)
	if not is_instance_valid(slider): return
	var from: Vector2 = physical_point(slider,Vector2(slider.size.x*.25,slider.size.y*.5))
	var to: Vector2 = physical_point(slider,Vector2(slider.size.x*.80,slider.size.y*.5))
	await move_mouse(from)
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.position=from;press.global_position=from;press.pressed=true
	root.push_input(press,false);await settle(2)
	var drag:=InputEventMouseMotion.new();drag.button_mask=MOUSE_BUTTON_MASK_LEFT;drag.position=to;drag.global_position=to;drag.relative=to-from
	root.push_input(drag,false);await settle(2)
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=to;release.global_position=to;release.pressed=false
	root.push_input(release,false);await settle(3)
	check(slider.value>=.70 and is_equal_approx(float(game.settings[key]),slider.value),"Actual physical slider drag reaches its production preference callback: "+key)
	input_trace.append({"type":"physical_client_slider","key":key,"from":from,"to":to,"value":slider.value,"production_value":game.settings[key],"root_final_transform":root.get_final_transform(),"push_input_in_local_coords":false})
func options_contract() -> void:
	for key: String in ["volume","music_volume","sfx_volume"]: await slider_drag(key)
	for key: String in ["muted","screen_shake","reduced_flashing","top_status_bars","impact_numbers"]:
		var before: bool = bool(game.settings[key]);await click(setting_control(key))
		check(bool(game.settings[key])!=before,"Physical expanded toggle changes only requested production preference: "+key)
	var identities: Array = descendants(game.menus).map(func(node:Node)->int:return node.get_instance_id())
	await settle(36)
	check(descendants(game.menus).map(func(node:Node)->int:return node.get_instance_id())==identities,"Stable Options state does not reconstruct all controls per frame")
	for profile: String in ["nintendo","xbox","playstation"]:
		for attempt: int in range(4):
			if str(game.settings.controller_layout)==profile: break
			await click(setting_control("controller_layout"))
		check(game.settings.controller_layout==profile,"Actual expanded controller preference chooses "+profile)
		var control: Control = setting_control("muted")
		await navigate(control)
		var before: bool = bool(game.settings.muted)
		await joy(Bindings.confirm_button(profile))
		check(bool(game.settings.muted)!=before,"Delivered logical printed Confirm activates focused toggle: "+profile)
		Input.joy_connection_changed.emit(3,true);await settle(2)
		check(game.settings.controller_layout==profile,"Synthetic reconnect callback preserves selected configuration: "+profile)
		Input.joy_connection_changed.emit(3,false);await settle(2)
	await navigate(target("back_settings"))
	await joy(Bindings.confirm_button("playstation"))
	check(game.screen=="title","Logical focus navigation returns from Options to Hub")
func workshop_contract() -> void:
	for category: String in ["blade","ratchet","bit"]:
		await mouse("catalogue_tab",category)
		check(game.menus._catalogue_category==category,"Physical full-client Workshop tab selects "+category)
		var owned: Dictionary = game.collection.equipped_build()
		var selected: Button = target("equip_part",{"category":category,"id":owned[category]})
		check(is_instance_valid(selected),"Actual owned Workshop part control exists")
		if is_instance_valid(selected):
			await navigate(selected);await click(selected)
			check(game.collection.equipped_build()[category]==owned[category],"Physical Workshop equip uses actual owned assembly handler")
		var scroll: ScrollContainer = game.menus._part_scrolls.get(category)
		if is_instance_valid(scroll) and scroll.get_v_scroll_bar().max_value>scroll.get_v_scroll_bar().page:
			var before: int = scroll.scroll_vertical;var point: Vector2 = physical_point(scroll,scroll.size*.5)
			for count: int in range(5):
				await move_mouse(point)
				for pressed: bool in [true,false]:
					var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=pressed;wheel.position=point;wheel.global_position=point;wheel.button_mask=0
					root.push_input(wheel,false);await settle(2)
			check(scroll.scroll_vertical>before,"Actual physical Workshop wheel scroll reveals overflow parts")
			input_trace.append({"type":"physical_client_scroll","category":category,"before":before,"after":scroll.scroll_vertical,"point":point})
	await mouse("back_workshop");check(game.screen=="title","Actual Workshop Back returns directly to Hub")
func packet_contract() -> void:
	for kind: String in ["standard","reclaimed"]:
		for quantity: int in [1,3,5]:
			await mouse("packet_quantity",{"kind":kind,"quantity":quantity})
			var card: Dictionary = game.menus._shop_cards[kind]
			var currency: String = str(PacketEconomy.config().packets[kind].currency).to_upper()
			check(game.menus.selected_shop_product()==kind and game.menus.selected_shop_quantity(kind)==quantity,"Physical quantity owns its displayed product: "+kind+" x%d" % quantity)
			check(card.price.text=="%d %s" % [PacketEconomy.packet_cost(kind)*quantity,currency],"Actual quantity immediately displays exact total and currency")
	await mouse("packet_quantity",{"kind":"standard","quantity":3})
	check(game.menus.selected_shop_product()=="standard" and game.menus.selected_shop_quantity("standard")==3,"Physical x3 control selects its own Standard product")
	await mouse("packet_odds");await audit("packet_odds","packet_odds")
	await mouse("packet_salvage_info");await audit("packet_salvage","packet_odds")
	await mouse("open_shop")
	await mouse("packet_quantity",{"kind":"standard","quantity":3})
	var wallet: int = game.collection.credits
	await mouse("request_packet_purchase","standard");await audit("packet_purchase","packet_purchase")
	var confirm: Button = target("confirm_packet_purchase")
	if is_instance_valid(confirm): await click(confirm)
	check(game.collection.credits==wallet-144,"Actual durable x3 purchase debits exact144 once")
	check(game.collection.pending_packet().get("quantity",0)==3,"All three predetermined packet receipts persist before presentation")
	await audit("packet_open","packet_open")
	await mouse("packet_tear")
	if is_instance_valid(game.menus._packet_view): game.menus._packet_view._process(30.0)
	await settle(5)
	await audit("packet_result","packet_open")
	await mouse("packet_shop")
	check(game.screen=="shop" and game.collection.pending_packet().is_empty(),"Actual packet summary acknowledges durable receipt and returns to Shop")
	await mouse("open_workshop");await audit("workshop_from_shop","garage")
	await mouse("back_workshop");check(game.screen=="shop","Workshop opened from Shop returns directly to Shop")
	await mouse("back_shop");check(game.screen=="title","Shop Back returns directly to Hub")
func modal_fixture() -> void:
	# Legal pending investment is a disclosed presentation fixture, not earned XP.
	game._clear_run();game._start_battle("duel",false,true);game.battle.set_physics_process(false)
	while game.battle.battle_status!="battle": game.battle.test_step(Physics.FIXED_DT)
	for tick: int in range(12): game.battle.test_step(Physics.FIXED_DT,Vector2(.4,0),false,false)
	game.battle.set_paused(true)
	game.run_context.start(game.collection.equipped_build(),421,"vane")
	game.run_context._owned_power_ids.assign(["orbit_drive","afterimage","momentum_bank"])
	game.run_context._power_ranks={"orbit_drive":2,"afterimage":1,"momentum_bank":1}
	game.run_context._pending_offer.assign(["orbit_drive","afterimage","momentum_bank"])
	game.run_context._draft_queue.assign([{"id":"draft/frontend_fixture","kind":"level","level":5}])
	game.mode="run";game._draft_resume_origin="starting"
	game.screen="level_up";game._level_up_remaining=.18;game.menus.show_level_up(5)
	await audit("level_up","level_up","modal")
	game._show_reward();await audit("ability_draft","reward","modal")
	var choice: Button = target("choose_power")
	for node: Node in descendants(game.menus):
		if node is Button and node.get_meta("power_id","")=="orbit_drive": choice=node;break
	if is_instance_valid(choice): await click(choice)
	await audit("mutation_draft","mutation","modal")
	check(game.run_context.pending_mutation_offer==Powers.mutation_choices("orbit_drive"),"Actual mutation modal retains both legal siblings")
	check(int(game.run_context.power_ranks.get("orbit_drive",0))==2,"Parent physical click cannot also consume mutation choice")
	await mouse("choose_mutation")
	await audit("acquisition","acquisition","modal")
	game._clear_run();game._title()

func showcase_navigation() -> void:
	await audit("title","title_gate");await phase("TITLE / NORMAL DECORATED CLIENT")
	await mouse("enter_frontend");await mouse("begin_collection")
	await phase("STARTER / RESPONSIVE FRONT END")
	await mouse("select_first_starter","vane");await mouse("confirm_first_starter","vane")
	while game.screen=="starter_owned" and game._ownership_remaining>.6: game._process(Physics.FIXED_DT);await settle(1)
	if game.screen=="starter_owned": await mouse("finish_ownership")
	await audit("workshop","garage");await phase("WORKSHOP / FULL CLIENT")
	await mouse("back_workshop");await audit("hub","title");await phase("HUB / FULL CLIENT")
	await mouse("settings");await audit("options","settings");await phase("OPTIONS / NORMAL960x600")
	var identities: Array = descendants(game.menus).map(func(node:Node)->int:return node.get_instance_id())
	root.size=Vector2i(1280,720);await settle(12)
	check(descendants(game.menus).map(func(node:Node)->int:return node.get_instance_id())==identities,"Actual Options resize retains all control instances")
	await audit("options_resized","settings");await phase("OPTIONS / REAL1280x720 RESIZE")
	var restore_size: Vector2i=root.size
	var restore_position: Vector2i=root.position
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED);await settle(12)
	check(root.mode==Window.MODE_MAXIMIZED,"Showcase actual OS maximize reaches native mode")
	await audit("options_native_maximized","settings");await phase("OPTIONS / NATIVE OS API MAXIMIZE",120)
	await slider_drag("music_volume")
	await mouse("back_settings");await phase("HUB / NATIVE MAXIMIZED")
	await mouse("open_shop");await audit("shop","shop");await phase("SHOP / FULL CLIENT")
	await mouse("packet_quantity",{"kind":"reclaimed","quantity":5})
	check(game.menus.selected_shop_product()=="reclaimed" and game.menus.selected_shop_quantity("reclaimed")==5,"Showcase physical x5 selects Reclaimed")
	await phase("SHOP / OWNED X5 QUANTITY AND COST")
	await mouse("back_shop")
	# Ordinary initial Run power choice and launch, with no XP/proc/outcome injection.
	await mouse("start_run");await audit("ability_draft","reward","modal");await phase("STARTING ABILITY / COMBAT MODAL")
	await mouse("choose_power");check(game.screen=="acquisition","Real initial choice enters acquisition")
	await phase("ACQUISITION / AUTHORED BEAT",30)
	await settle(90,true)
	check(game.screen=="battle","Ordinary acquisition timer launches actual Run")
	await phase("RUN / READY INTO ACCEPTED COMBAT",240,true)
	await audit("battle","battle","combat")
	await mouse("pause");await audit("pause","pause","modal");await phase("PAUSE / LIVE ARENA OVERLAY",120)
	check(game.combat_frame.visible and game.battle.visible,"Showcase Pause preserves live arena")
	await mouse("resume");await phase("RESUME / AUTHORED RE-ENTRY READY GO",120,true)
	check(game.screen=="battle" and game.battle.battle_status=="battle","Actual Resume resolves READY and returns to live combat")
	await mouse("pause")
	check(game.screen=="pause" and game.battle.paused,"Native Restore invariance fixture is the actual paused live Run")
	var before_restore: Array=game.battle.fighters.duplicate(true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);await settle(12)
	check(root.size==restore_size,"Native OS Restore returns actual pre-Maximize client size without forced resize")
	check(game.battle.fighters==before_restore,"Actual native Restore changes no combat actor state")
	input_trace.append({"type":"native_OS_API_restore","before_maximize_client":restore_size,"before_maximize_position":restore_position,"restored_client":root.size,"restored_position":root.position,"mode":root.mode,"actual_paused":game.battle.paused,"actors_unchanged":game.battle.fighters==before_restore,"forced_size_assignment":false,"human_caption_button_acceptance":false})
	await phase("PAUSE / TRUE NATIVE OS API RESTORE",90)
	check(root.mode==Window.MODE_WINDOWED and not root.borderless,"Showcase restores ordinary decorated window")
	root.size=Vector2i(960,600);await settle(12)
	await phase("PAUSE / SEPARATE960x600 OS API RESIZE",60)
	await mouse("end_run");await audit("workshop_after_end_run","garage");await phase("WORKSHOP / EXPLICIT END RUN FRONT END")
	await mouse("back_workshop");await audit("hub_restored","title");await phase("HUB / RESTORED960x600",120)
	current_phase=""
func combat_contract() -> void:
	# This genuine production Duel reaches result through the actual solver.
	game._start_battle("duel",false,true);game.battle.set_physics_process(false)
	while game.battle.battle_status!="battle": game.battle.test_step(Physics.FIXED_DT)
	for tick: int in range(12): game.battle.test_step(Physics.FIXED_DT,Vector2(.4,0),false,false)
	game.battle._emit_hud();game._process(0.0)
	await audit("battle","battle","combat")
	var original: Array = game.battle.fighters.duplicate(true)
	var old_size: Vector2i = root.size
	root.size=Vector2i(old_size.x+17,old_size.y+11);await settle(5)
	check(game.battle.fighters==original,"Actual live resize changes no actor physics state")
	root.size=old_size;await settle(5)
	check(game.battle.fighters==original,"Restoring client changes no actor physics state")
	await mouse("pause");await audit("pause","pause","modal")
	check(game.combat_frame.visible and game.battle.visible,"Pause remains an overlay over actual live arena")
	await mouse("resume")
	for tick: int in range(5000):
		if game.screen=="result": break
		game.battle.test_step(Physics.FIXED_DT,Vector2.ZERO,false,false)
	check(game.screen=="result" and game.battle.battle_status=="finished","Actual solver conclusion produces front-end Results")
	await audit("result","result")
	game._title()
func navigation() -> void:
	await audit("title","title_gate")
	await mouse("enter_frontend");await audit("uninitialized_hub","title")
	await mouse("begin_collection");await audit("starter","starter_ceremony")
	await mouse("select_first_starter","vane");await audit("starter_confirmation","starter_confirm")
	await mouse("confirm_first_starter","vane");await audit("starter_owned","starter_owned")
	while game.screen=="starter_owned" and game._ownership_remaining>.6: game._process(Physics.FIXED_DT);await settle(1)
	if game.screen=="starter_owned": await mouse("finish_ownership")
	await audit("workshop","garage");await workshop_contract()
	await audit("hub","title")
	await mouse("play_modes");await audit("modes","play_modes")
	await mouse("practice_garage");await audit("practice_workshop","practice_garage")
	await mouse("main_menu")
	await mouse("help");await audit("help","help")
	await mouse("main_menu")
	await mouse("settings");await audit("options","settings")
	if native and root.size==Vector2i(1920,1080):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED);await settle(12)
		await audit("options_native_maximized","settings")
		check(root.mode==Window.MODE_MAXIMIZED,"Actual OS native maximize reaches maximized mode")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);root.size=Vector2i(1920,1080);await settle(12)
		await audit("options_native_restored","settings")
	await mouse("save_tools");await audit("save_tools","save_tools")
	await mouse("request_reset_collection");await audit("reset_confirm","reset_confirm")
	await mouse("cancel_reset_collection");await mouse("back_settings")
	await options_contract()
	var initial: Dictionary = game.collection._data.duplicate(true);initial.progression.credits=10000
	check(game.collection._commit(initial,"qa_frontend_initial_wallet").ok,"Declared isolated initial wallet fixture persists")
	await mouse("open_shop");await audit("shop","shop")
	await packet_contract()
	await modal_fixture()
	await combat_contract()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
		if arg.begins_with("--profile-prefix="): prefix=arg.trim_prefix("--profile-prefix=")
		if arg.begins_with("--frames="): frames=arg.trim_prefix("--frames=")
		if arg=="--native": native=true
		if arg=="--showcase": showcase=true;native=true
	var qa: String = OS.get_environment("TOPGAME_QA_ROOT").path_join("003A.2")
	var valid: bool = not OS.get_environment("TOPGAME_QA_ROOT").is_empty()
	for item: Array in [[report,"manifests"],[prefix,"temp"]]:
		var path: String = str(item[0]).replace("\\","/").simplify_path()
		valid = valid and path.is_absolute_path() and path.to_lower().begins_with(qa.replace("\\","/").simplify_path().path_join(str(item[1])).to_lower()+"/") and not FileAccess.file_exists(path)
	if native: valid = valid and frames.is_absolute_path() and frames.replace("\\","/").to_lower().begins_with(qa.replace("\\","/").to_lower()+"/frames/") and not DirAccess.dir_exists_absolute(frames)
	check(valid,"Fresh external QA task paths required before opening Main")
	if not valid: quit(2);return
	if native: DirAccess.make_dir_recursive_absolute(frames)
	root.min_size=Vector2i(800,480);root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var selected: Array[Vector2i] = []
	if showcase: selected.append(Vector2i(960,600))
	else: selected.assign(SIZES)
	for size: Vector2i in selected:
		await new_case(size)
		if showcase: await showcase_navigation()
		else: await navigation()
		game.free();game=null;await settle(3)
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify(portable({"schema":"frontend-fullscreen-003a2-v1","checks":checks,"failures":failures,"native":native,"showcase":showcase,"observations":observations,"inputs":input_trace,"images":images,"film":film,"phases":phases,"live_controls":live_controls,"physical_phone_acceptance":false,"physical_controller_acceptance":false,"scope":"Actual production Main/Menus. Four declared desktop clients, isolated saves/default preferences, actual starter ownership and durable x3 packet purchase with initial wallet fixture. Packet clock acceleration and legal pending investment are explicitly UI presentation fixtures. Physical client pointer projection uses final viewport+control transform and push_input(false); controller/reconnect events are synthetic GUI mapping, not hardware presses. Combat results use actual Duel solver; all canonical640x360 combat/actor physics remain unchanged by resize. Showcase uses a declared fixed Run seed and observed current-position/velocity centre correction through ordinary steering/Brake; no actor/RPM/XP/outcome injection. Native OS maximize/restore actuation is labelled separately."}),"\t"));file.close()
	print("FRONTEND_FULLSCREEN_003A2_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
