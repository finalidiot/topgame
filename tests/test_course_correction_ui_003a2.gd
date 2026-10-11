extends SceneTree
## Actual menu/input geometry with declared assemblies/ownership/offer fixtures.
## No collection file, wallet, physics world or real controller is opened.
const Menus = preload("res://scripts/menus.gd")
const Catalog = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Stats = preload("res://scripts/workshop_build_stats.gd")
const Combat = preload("res://scripts/combat_hud_layout.gd")
const REFERENCE = {"blade":"lopsider","ratchet":"flywheel","bit":"needle"}
var menus: Control
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var report: String = ""
var images: String = ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func settle() -> void:
	for tick: int in range(4): await process_frame
func capture(name: String) -> void:
	if images.is_empty(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(images.path_join(name+".png")) == OK,"Fresh native UI pixels saved: "+name)
func joy(button: JoyButton, pressed: bool, device: int = 3) -> void:
	var event := InputEventJoypadButton.new()
	event.device=device; event.button_index=button; event.pressed=pressed
	Input.parse_input_event(event)
	await settle()
func key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=pressed; event.echo=echo
	Input.parse_input_event(event)
	await settle()

func workshop() -> void:
	var owned: Dictionary = {"blade":["lopsider"],"ratchet":["flywheel"],"bit":["needle"]}
	var snapshot: Dictionary = {"owned_parts":owned,"can_launch":true,"credits":123,"salvage":45}
	menus.show_collection_workshop(REFERENCE,snapshot)
	await settle()
	var initial: Dictionary = menus.workshop_stats_snapshot()
	check(initial.current.ratings == Catalog.derive(REFERENCE),"Current Workshop ratings equal the exact production calculator")
	check(initial.current.physical == Catalog.derive_physics(REFERENCE),"Current mechanical notes use the production assembled coefficients")
	for row: Array in [["power",7.4],["stamina",5.9],["grip",1.7],["speed",2.6],["stability",2.7],["mass",9.2]]:
		check(is_equal_approx(float(initial.current.ratings[row[0]]),float(row[1])),"Reference rating verified: "+str(row[0]))
	check("Heavy attack" in initial.current.summary and "Spin retention" in initial.current.summary and "Slower control" in initial.current.summary and "Imbalance" in initial.current.summary,"Reference assembly explains attack, endurance, control and imbalance")
	check(initial.current.starter_identity=="custom" and initial.current.run_handling.is_empty(),"Reference custom assembly cannot inherit its historical starter's handling")
	for starter: String in Menus.Starters.IDS:
		var starter_build: Dictionary = Menus.Starters.build_for(starter)
		var inspection: Dictionary = Stats.inspect(starter_build)
		check(inspection.ratings==Catalog.derive(starter_build) and inspection.run_handling==Menus.Starters.HANDLING[starter],"Starter Run handling is described separately from exact base ratings: "+starter)
		check("RUN ONLY / "+Menus.Starters.display_name(starter) in "\n".join(inspection.notes),"Actual assembly identity selects the separate Run-only note: "+starter)
	check(menus._build == REFERENCE and menus._collection_snapshot == snapshot,"Initial readout preserves equipment and fixture snapshot")
	await capture("workshop_equipped")
	for row: Array in [["blade","guard"],["ratchet","low"],["bit","flat"]]:
		menus.focus_collection_part(row[0],row[1]); await settle()
		var expected: Dictionary = REFERENCE.duplicate(); expected[row[0]]=row[1]
		var observed: Dictionary = menus.workshop_stats_snapshot()
		check(observed.preview.build == expected and observed.current.build == REFERENCE,"Preview replaces only highlighted category "+str(row[0]))
		check(observed.preview.ratings == Catalog.derive(expected),"Preview includes production caps/order "+str(row[0]))
		check(menus._workshop_stats_heading.text == "PREVIEW / NOT EQUIPPED","Locked part has unmistakable not-equipped preview label")
		check(menus._build == REFERENCE and menus._collection_snapshot == snapshot and actions.is_empty(),"Locked focus cannot equip, save, grant or debit "+str(row[0]))
		observations.append({"case":"preview_"+str(row[0]),"data":observed})
		await capture("workshop_preview_"+str(row[0]))
	menus._catalogue_footer[0].grab_focus(); await settle()
	check(not menus.workshop_stats_snapshot().is_preview and menus._preview.build == REFERENCE,"Leaving the part preview restores equipped assembly and readout")
	menus.set_ui_input_owner(3); menus.focus_collection_part("blade","guard"); await settle()
	await joy(JOY_BUTTON_RIGHT_SHOULDER,true)
	check(menus._catalogue_category == "ratchet","RB changes the active category")
	await joy(JOY_BUTTON_RIGHT_SHOULDER,true)
	check(menus._catalogue_category == "ratchet","Held/repeated RB does not switch twice")
	await joy(JOY_BUTTON_RIGHT_SHOULDER,false); await joy(JOY_BUTTON_RIGHT_SHOULDER,true)
	check(menus._catalogue_category == "bit","Release rearms category switching")
	await joy(JOY_BUTTON_RIGHT_SHOULDER,false); await joy(JOY_BUTTON_RIGHT_SHOULDER,true)
	check(menus._catalogue_category == "blade" and root.gui_get_focus_owner().get_meta("part_id") == "guard","Category wraps and retains per-category part focus")
	await joy(JOY_BUTTON_RIGHT_SHOULDER,false); await joy(JOY_BUTTON_LEFT_SHOULDER,true,4)
	check(menus._catalogue_category == "blade","Another controller cannot switch the owning player's category")
	await joy(JOY_BUTTON_LEFT_SHOULDER,false,4)
	check(menus._build == REFERENCE and actions.is_empty(),"Shoulder tabs never equip or change ownership")
	# Existing equip flow remains an intent. Its confirmed refreshed build becomes
	# the baseline only when the game presents the actual equipped result.
	var equipped: Dictionary = REFERENCE.duplicate(); equipped.bit="flat"
	owned.bit.append("flat")
	menus.show_collection_workshop(equipped,snapshot); await settle()
	check(menus.workshop_stats_snapshot().current.ratings == Catalog.derive(equipped),"An actual equip refresh establishes the new comparison baseline")
	menus.set_ui_input_owner(-1)

func drafts() -> void:
	var context: Dictionary = {"power_ranks":{"dead_centre":1,"afterimage":2},"rerolls":{"charges":2,"available":true,"revision":5}}
	menus.show_reward(["redline","dead_centre","afterimage"],["dead_centre","afterimage"],1,"ui_fixture",421,"",context)
	await settle()
	var reroll: Button = menus._reroll_control
	check(reroll.focus_mode == Control.FOCUS_NONE,"Reroll is a direct action without D-pad/stick focus")
	var cards: Array[Button] = []
	for child: Node in menus._content.get_children():
		if child is Button and child.has_meta("ability_tier"): cards.append(child)
	for card: Button in cards:
		for side: int in range(4):
			var target: Node = card.get_node(card.get_focus_neighbor(side))
			check(target in cards and target != reroll,"Draft navigation remains among valid power choices")
		card.grab_focus(); menus._animate_cards()
		var frame: StyleBoxFlat = card.get_node("SemanticCardFrame").get_theme_stylebox("panel")
		check(frame.border_color == Menus.AbilityCardStyle.FOCUS and frame.border_width_left == 4 and frame.shadow_color == Menus.AbilityCardStyle.FOCUS_SEPARATOR,"Universal focus survives every investment colour")
		var luminance: float = frame.border_color.r*.2126+frame.border_color.g*.7152+frame.border_color.b*.0722
		check(luminance > .9 and frame.shadow_color.get_luminance() < .1,"Grayscale focus frame has bright/dark separation")
	await capture("draft_focus_direct_reroll")
	var before: int = actions.size()
	await key(KEY_R,true); await key(KEY_R,true,true)
	check(actions.size()==before+1 and actions.back().name=="reroll_power","One pressed/held R spends one direct-action intent")
	await key(KEY_R,false); await key(KEY_R,true); await key(KEY_R,false)
	check(actions.size()==before+2,"Release permits the next reroll")
	await key(KEY_R,true)
	menus.show_reward(["redline"],[],1,"held_fixture",421,"",context); await settle()
	var held_count: int = actions.size()
	await key(KEY_R,true)
	check(actions.size()==held_count,"Held input crossing into a new draft cannot reroll it")
	await key(KEY_R,false)
	menus.show_mutation("redline",Powers.mutation_choices("redline"),"mutation_fixture",421,"",{"charges":2,"mutation_available":true,"revision":5})
	await settle()
	check(menus._reroll_control.focus_mode == Control.FOCUS_NONE,"Mutation reroll also remains outside automatic focus")
	await capture("mutation_focus")

func layouts() -> void:
	menus._inspection_owned_state={"ids":["dead_centre","impact_sink","gyro_lock"],"ranks":{"dead_centre":2,"impact_sink":2,"gyro_lock":2},"mutations":{},"state":{}}
	for extent: Vector2 in [Vector2(800,480),Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1440)]:
		root.size=Vector2i(extent); menus.mobile_hud=false; menus.set_presentation_canvas(extent)
		menus.show_pause(true); await settle()
		var observed: Dictionary=menus.presentation_snapshot()
		check(observed.presentation_policy=="pause_overlay" and observed.root_rect==Rect2(Vector2.ZERO,extent),"Pause uses the independent full-client root "+str(extent))
		check(observed.safe_rect.encloses(menus._content.get_global_rect()),"Pause root stays in client")
		if extent.x>=1280:
			check(observed.frame_rect.size.x/extent.x>=.80,"Pause uses substantial client width")
			check(menus._ability_inspector.scale.x>1.0,"Power inspection grows readably without stretching its illustration")
		observations.append({"case":"pause_"+str(extent),"layout":observed})
		if extent.x==1920: await capture("pause_1080p")
	menus.mobile_hud=true; menus.set_presentation_canvas(Vector2(1200,480),Rect2(56,18,1088,444)); menus.show_pause(true); await settle()
	var mobile: Dictionary=Combat.responsive(Vector2(1200,480),true,Rect2(56,18,1088,444))
	check(menus._content.position==mobile.menu_origin and menus._content.scale==Vector2.ONE*mobile.menu_scale,"Android Pause retains accepted uniform safe-area policy")
	root.size=Vector2i(1200,480); root.content_scale_size=root.size
	menus.show_collection_workshop(REFERENCE,{"owned_parts":{"blade":["lopsider"],"ratchet":["flywheel"],"bit":["needle"]},"can_launch":true}); await settle()
	menus.focus_collection_part("blade","guard"); await settle()
	check(menus._workshop_stats_heading.is_visible_in_tree() and menus._catalogue_note_scroll.is_visible_in_tree(),"Android keeps direct stats and inspectable physical notes")
	check(menus._assembly_name.get_visible_line_count()==menus._assembly_name.get_line_count(),"Actual equipped identity remains fully readable in the mobile preview")
	for stat: String in Catalog.STAT_IDS:
		var label: Label = menus._stat_numbers[stat]
		check(label.get_visible_line_count()==label.get_line_count() and label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x<=label.size.x,"Mobile signed ratings comparison fits: "+stat)
	await capture("workshop_mobile_safe_preview")
	menus.mobile_hud=false; root.size=Vector2i(1920,1080); root.content_scale_size=root.size; menus.set_presentation_canvas(Vector2(1920,1080))
	menus.show_settings({"controller_rumble":true,"rumble_intensity":.55}); await settle()
	check(menus._frontend_settings_nodes.controller_rumble_button.is_visible_in_tree() and menus._frontend_settings_nodes.rumble_intensity_slider.is_visible_in_tree() and menus._frontend_settings_nodes.test_rumble.is_visible_in_tree(),"Rumble toggle, intensity and explicit test remain directly accessible")
	menus.set_rumble_test_status("Short rumble requested. Confirm the controller response.")
	await capture("settings_rumble_1080p")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report=argument.trim_prefix("--report=")
		if argument.begins_with("--images="): images=argument.trim_prefix("--images=")
	if not report.is_absolute_path() or FileAccess.file_exists(report): quit(2); return
	if not images.is_empty(): DirAccess.make_dir_recursive_absolute(images)
	root.size=Vector2i(1920,1080); root.content_scale_size=root.size
	Input.use_accumulated_input=false
	menus=Menus.new(); root.add_child(menus); menus.set_presentation_canvas(Vector2(1920,1080))
	menus.action.connect(func(name: String,value: Variant) -> void: actions.append({"name":name,"value":value}))
	await settle(); await workshop(); await drafts(); await layouts()
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations,"actions":actions,"scope":"Production assembly calculations and actual menu nodes with declared ownership/build/offer fixtures; synthetic logical input, native pixels when requested. No player collection or world mutations; physical controller/phone review remains separate."},"\t")); file.close()
	print("COURSE_CORRECTION_UI_003A2_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	menus.free(); quit(0 if failures.is_empty() else 1)
