extends SceneTree
## Declared collection/display fixtures. Actual controls and transforms are
## exercised; no gameplay, transaction or physical-device claim is made.
const Menus=preload("res://scripts/menus.gd")
const Parts=preload("res://scripts/parts.gd")
const Starters=preload("res://scripts/starters.gd")
const Combat=preload("res://scripts/combat_hud_layout.gd")
var menus:Control
var checks:int=0
var failures:Array[String]=[]
var report:String=""
var observations:Array=[]
var snapshot:Dictionary={"credits":137,"salvage":29,"owned_parts":{},"total_owned":31}
var build:Dictionary={}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func settle()->void:
	for tick:int in range(3):await process_frame
func clipped(node:Control)->bool:
	var parent:Node=node.get_parent()
	while parent!=null:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(node.get_global_rect()):return true
		parent=parent.get_parent()
	return false
func inspect(page:String,canvas:Vector2)->void:
	await settle()
	var actual:Dictionary=menus.presentation_snapshot()
	check(actual.presentation_class=="frontend" and actual.root_scale==Vector2.ONE,page+": independently laid out full-client page")
	check(Rect2(actual.root_rect).is_equal_approx(Rect2(Vector2.ZERO,canvas)),page+": root fills actual canvas")
	if page=="Options" and not menus._frontend_layout.compact:
		var nodes:Dictionary=menus._frontend_settings_nodes
		var panel:Panel=nodes.controls_panel
		check(nodes.audio_title.get_theme_font_size("font_size")==nodes.comfort_title.get_theme_font_size("font_size") and nodes.audio_title.get_theme_font_size("font_size")==nodes.controls_title.get_theme_font_size("font_size"),"Equal-purpose Options pane titles share the actual font hierarchy")
		for key:String in ["controller_button","window_note","controls_title","controls_copy"]:
			var foreground:Control=nodes[key]
			check(panel.get_parent()==foreground.get_parent() and panel.get_index()<foreground.get_index() and panel.z_index==foreground.z_index,"Controls background paints before visible foreground: "+key)
		check(panel.get_global_rect().encloses(nodes.controller_button.get_global_rect()),"Actual controller choice is inside its visible Controls pane")
		check(nodes.controls_copy.vertical_alignment==VERTICAL_ALIGNMENT_TOP,"Controls instructions read directly beneath controller choice")
	for node:Node in menus._content.find_children("*","Control",true,false):
		if not node.is_visible_in_tree() or clipped(node):continue
		if node is BaseButton or node is HSlider:
			check(Rect2(Vector2.ZERO,canvas).encloses(node.get_global_rect()),page+": actual interactive control in client "+str(node.name))
		if node is Label and not node.text.is_empty():
			check(node.get_visible_line_count()==node.get_line_count(),page+": all actual shaped lines visible: "+node.text.left(52))
			var height:float=0
			for line:int in range(node.get_line_count()):height+=node.get_line_height(line)
			check(height<=node.size.y+1,page+": shaped text height fits: "+node.text.left(52))
	observations.append({"page":page,"canvas":canvas,"presentation":actual})
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
	if not report.is_empty() and (not report.is_absolute_path() or not report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/") or FileAccess.file_exists(report)):quit(2);return
	var unmounted:Control=Menus.new()
	check(unmounted.presentation_snapshot().content_instance_id==0,"Unmounted diagnostic has no viewport requirement")
	unmounted.free()
	build=Starters.get_starter("breaker").assembly.duplicate(true)
	for category:String in Parts.PARTS:snapshot.owned_parts[category]=Parts.PARTS[category].keys()
	menus=Menus.new();root.add_child(menus);await settle()
	for canvas:Vector2 in [Vector2(800,480),Vector2(960,600),Vector2(1280,720),Vector2(1920,1080),Vector2(1920,1017),Vector2(2560,1440)]:
		root.size=Vector2i(canvas);menus.set_presentation_canvas(canvas)
		menus.show_title_gate(true);await inspect("Title",canvas)
		menus.show_collection_title(build,{},true,snapshot);await inspect("Hub",canvas)
		menus.show_play_modes(build);await inspect("Modes",canvas)
		menus.show_starter_ceremony();await inspect("Starter cards",canvas)
		menus.show_starter_confirmation("breaker");await inspect("Starter confirmation",canvas)
		menus.show_starter_owned("breaker");await inspect("Starter acquired",canvas)
		menus.show_collection_workshop(build,snapshot);await inspect("Workshop",canvas)
		menus.show_shop(snapshot);await inspect("Shop",canvas)
		menus.show_settings({});await inspect("Options",canvas)
		menus.show_help();await inspect("Help",canvas)
		menus.show_save_tools(snapshot);await inspect("Save tools",canvas)
		menus.show_reset_confirmation();await inspect("Reset confirmation",canvas)
		menus.show_result({"won":true,"duration":48,"hits":32,"player_remaining":.7});await inspect("Duel result",canvas)
		menus.show_result({"continuous_run":true,"duration":100,"level":8,"power_ids":["orbit_drive"],"power_ranks":{"orbit_drive":2}});await inspect("Run result",canvas)
	menus.set_presentation_canvas(Vector2(1280,720));menus.show_settings({"volume":.45});await settle()
	var slider:HSlider=menus._frontend_settings_nodes.volume_slider
	slider.grab_focus();slider.value=.8
	var content_id:int=menus._content.get_instance_id()
	menus.set_presentation_canvas(Vector2(1920,1080));await settle()
	check(menus._content.get_instance_id()==content_id and root.gui_get_focus_owner()==slider and slider.value==.8,"Resize preserves actual slider node, focus and value")
	var revision:int=menus.presentation_snapshot().layout_revision
	for tick:int in range(12):menus.set_presentation_canvas(Vector2(1920,1080));await process_frame
	check(menus.presentation_snapshot().layout_revision==revision,"Unchanged display does not rebuild/reflow every frame")
	menus.show_pause(true);await settle()
	check(menus._content.scale==Vector2.ONE and menus._content.get_global_rect().get_center().is_equal_approx(Vector2(960,540)),"Pause retains accepted centered native modality")
	menus.show_reward(["orbit_drive","momentum_bank","crash_guard"],[],1,"fixture",39);await settle()
	check(menus._content.scale==Vector2(1.5,1.5),"Draft scale applied on construction at unchanged large display")
	menus.mobile_hud=true
	var canvas:Vector2=Vector2(1200,480);var safe:Rect2=Rect2(56,18,1088,444)
	menus.set_presentation_canvas(canvas,safe);menus.show_settings({});await settle()
	var accepted:Dictionary=Combat.responsive(canvas,true,safe)
	check(menus._content.position==accepted.menu_origin and menus._content.scale==Vector2.ONE*accepted.menu_scale and menus._content.size==Vector2(640,360),"Android retains accepted safe authored panel transform")
	check(menus._presentation_background.get_global_rect()==Rect2(Vector2.ZERO,canvas),"Android authored background retains full-canvas coverage")
	if not report.is_empty():
		var file:FileAccess=FileAccess.open(report,FileAccess.WRITE)
		check(file!=null,"Fresh external report opens")
		if file!=null:file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"));file.close()
	print("FRONTEND_PAGES_003A2_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
