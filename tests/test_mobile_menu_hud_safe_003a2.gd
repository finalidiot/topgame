extends SceneTree
## Read-only presentation fixtures: real Menus controls, font measurements and
## transforms. Supplied HUD values do not claim earned gameplay or phone feel.
const Menus = preload("res://scripts/menus.gd")
const Layout = preload("res://scripts/combat_hud_layout.gd")
const FAMILY_IDS: Array = ["dead_centre","impact_sink","redline","orbit_drive","iron_comet","momentum_bank","crash_guard"]
var report: String = ""
var checks: int = 0
var failures: Array[String] = []
var measurements: Array = []
var menus: Control
var intents: Array = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func valid_report() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	var normalized: String = report.replace("\\","/").simplify_path().to_lower()
	return report.is_absolute_path() and normalized.contains("gyrobrothers-qa/003a.2/manifests/") and not FileAccess.file_exists(report) and not DirAccess.dir_exists_absolute(report)
func stats() -> Dictionary:
	return {"player_name":"BASTION","starter_id":"bastion","player_rpm":1.18,"player_rpm_value":10620,"overdrive_active":true,
		"enemy_name":"BALLAST ELITE","enemy_rpm":0.9,"elapsed":887.0,"status":"battle","is_run":true,"continuous_run":true,
		"level":19,"xp":241,"xp_threshold":460,"burst_cooldown":2.7,"burst_ready":false,"rerolls":2,
		"owned_power_ids":FAMILY_IDS.duplicate(),"power_ranks":{"dead_centre":3,"impact_sink":2,"redline":2,"orbit_drive":3,"iron_comet":3,"momentum_bank":3,"crash_guard":3},
		"power_mutations":{"dead_centre":"counterweight","orbit_drive":"centrifuge","iron_comet":"wallbreaker","momentum_bank":"countersteer","crash_guard":"reactive_plating"},
		"impact_confirmation":"ELITE RING OUT","run_state":{"director":true,"threat_number":124,"phase":"active","next_at":890.0,"census":{"full":6,"active_full":6,"small":12,"pressure":21.3},"limits":{"tier":9,"budget":25.0},"callout":"ELITE ENTERING","calm":false,"threats_cleared":123},
		"power_state":{"anchor":{"owned":true,"strength":0.76,"stress":0.72},"sink":{"owned":true,"stored":115,"capacity":150,"ratio":115.0/150.0},
			"redline":{"owned":true,"active":true,"heat":0.7,"excess":0.18},"orbit":{"owned":true,"drive":1.0,"drifting":true,"flowing":true,"mutation":"centrifuge"}}}

func label_fits(key: String) -> void:
	var label: Label = menus._hud[key]
	if not label.visible or label.text.is_empty() or label.autowrap_mode != TextServer.AUTOWRAP_OFF: return
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	var width: float = font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	check(width <= label.size.x+0.01,"Actual HUD text fits its local native rail: %s %s (%s/%s)" % [key,label.text,width,label.size.x])
	check(font.get_height(size) <= label.size.y+0.01,"HUD text height fits: "+key)

func hud_case(canvas: Vector2, safe: Rect2) -> void:
	menus.mobile_hud = true
	menus.set_presentation_canvas(canvas,safe)
	menus.show_hud(stats())
	await settle()
	var actual: Dictionary = Layout.responsive(canvas,true,safe)
	check(menus._content.position == actual.hud_origin and menus._content.scale.is_equal_approx(Vector2.ONE*float(actual.hud_scale)),"HUD uses one safe-origin/uniform-scale transform")
	check(menus._content.clip_contents,"Expanded touch caps are clipped at the actual safe HUD surface")
	for key: String in ["player_panel","enemy_panel","player_name","player_rpm","enemy_name","enemy_rpm","clock_panel","time","round","director_callout","pause_button","burst_panel","burst","burst_bar","xp_panel","xp_label","xp_detail","xp_bar","power_note","rerolls","impact_confirmation"]:
		var control: Control = menus._hud[key]
		check(safe.grow(0.1).encloses(control.get_global_rect()),"Rendered HUD child remains safe: "+key+str(control.get_global_rect()))
	for key: String in ["player_name","player_rpm","enemy_name","enemy_rpm","time","round","director_callout","burst","xp_label","xp_detail","power_note","rerolls","pressure_counts"]: label_fits(key)
	for index: int in range(FAMILY_IDS.size()):
		for prefix: String in ["power_panel_","power_","power_rank_"]:
			var control: Control = menus._hud[prefix+str(index)]
			check(control.visible and safe.grow(0.1).encloses(control.get_global_rect()),"All seven actual owned power slots remain inside safe bounds")
	var state: Dictionary = menus._hud.state_meters.diagnostic_snapshot()
	for side: String in ["left","right"]:
		var local_region: Rect2 = menus._hud_layout.regions["state_"+side]
		var origin: Vector2 = state[side]
		for row: int in range(state.rows[side].size()):
			var box: Rect2 = Rect2(origin+Vector2(0,row*float(state.row_height)),Vector2(state.width,66))
			check(local_region.grow(0.1).encloses(box),"Actual two-row state raster fits the declared state rail")
	check(safe.grow(0.1).encloses(menus._ability_inspector.get_global_rect()),"Hidden inspector remains safe if opened next")
	check(menus._hud.player_bar.value == 1.0 and is_equal_approx(menus._hud.rpm_overflow.value,0.18),"Actual overdrive reserve and overflow values remain intact")
	check(is_equal_approx(menus._hud.enemy_bar.value,21.3/25.0),"Pressure bar still reads actual census/budget")
	check(menus._hud.state_meters.diagnostic_snapshot().state == stats().power_state,"Presentation transform does not alter public power state")
	if bool(actual.mobile_wide):
		check(menus._hud.player_rpm.text == "10620 RPM" and menus._hud.burst.text == "BURST 2.7s","Wide captions retain real RPM and remaining Burst time")
		check(menus._hud.xp_label.text == "LV 19 / NEXT" and menus._hud.xp_detail.text == "241 / 460 XP","Wide progression keeps level and exact current XP")
		check(menus._hud.enemy_rpm.text == "21.3 / 25.0" and menus._hud.pressure_counts.text == "6RIVALS/12SMALL","Wide pressure retains precise budget and live population")
	measurements.append({"canvas":canvas,"safe":safe,"layout":menus.combat_layout_snapshot(),"hud_scale":actual.hud_scale,"wide":actual.mobile_wide,"state":state})

func mutation_read_geometry(canvas: Vector2, safe: Rect2) -> void:
	menus.mobile_hud = true
	menus.set_presentation_canvas(canvas,safe)
	menus.show_mutation("momentum_bank",["flywheel_release","countersteer"],"qa-read-row",39,"",{"charges":1,"revision":0,"mutation_available":true})
	await settle()
	var buttons: Array = menus._content.find_children("*","Button",true,false)
	var reads: Array = buttons.filter(func(node: Node) -> bool: return node.text=="READ")
	var cards: Array = buttons.filter(func(node: Node) -> bool: return node.get_meta("intent","")=="choose_mutation")
	check(reads.size()==2 and cards.size()==2,"Both mutation cards have separate full READ controls")
	for read: Button in reads:
		check(read.size.y==44 and safe.grow(.1).encloses(read.get_global_rect()),"Full44px READ row stays inside transformed safe panel")
		check(read._has_point(read.size*.5),"READ centre remains a real touch hit target")
		for card: Button in cards:
			var confirm: Label = card.get_node("AbilityCardConfirm")
			check(not read.get_global_rect().intersects(card.get_global_rect()),"READ control does not cover the mutation card")
			check(not read.get_global_rect().intersects(confirm.get_global_rect()),"READ control leaves the actual TRANSFORM confirmation unobstructed")
			var read_in_card: Vector2 = card.get_global_transform().affine_inverse()*read.get_global_rect().get_center()
			check(not card._has_point(read_in_card),"A READ tap cannot hit a mutation card")
	var hint: Label
	for node: Node in menus._content.get_children():
		if node is Label and node.text=="READ / CARD: COMMIT": hint=node
	check(hint!=null and safe.grow(.1).encloses(hint.get_global_rect()),"Mobile mutation hint is readable in the free right-column strip")
	if hint!=null:
		var font: Font=hint.get_theme_font("font")
		var font_size: int=hint.get_theme_font_size("font_size")
		check(font.get_string_size(hint.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x<=hint.size.x and font.get_height(font_size)<=hint.size.y,"Actual mobile mutation hint fits its native text rectangle")
		for read: Button in reads: check(not hint.get_global_rect().intersects(read.get_global_rect()),"Instruction text remains outside the READ row")

func menu_inset_change() -> void:
	var canvas: Vector2 = Vector2(1200,480)
	var before: Rect2 = Rect2(24,8,1136,464)
	var after: Rect2 = Rect2(56,18,1088,444)
	menus.mobile_hud = true
	menus.set_presentation_canvas(canvas,before)
	menus.show_settings({"volume":0.65,"music_volume":0.55,"sfx_volume":1.0})
	await settle()
	var content_id: int = menus._content.get_instance_id()
	var prior_origin: Vector2 = menus._content.position
	var focus: Control = root.gui_get_focus_owner()
	menus.set_presentation_canvas(canvas,after)
	await settle()
	check(menus._content.get_instance_id()==content_id and root.gui_get_focus_owner()==focus,"Same-size safe inset change preserves controls and focused intent")
	check(menus._content.position != prior_origin and after.encloses(menus._content.get_global_rect()),"Same-size inset change genuinely recentres the full readable panel")
	check(is_instance_valid(menus._presentation_background) and menus._presentation_background.get_global_rect()==Rect2(Vector2.ZERO,canvas),"Authored mobile background fills canvas beyond the interactive safe panel")
	var overlays: Array = []
	menus.show_pause(true)
	for child: Node in menus._content.get_children():
		if child is Control and child.has_meta("mobile_full_canvas_overlay"): overlays.append(child)
	check(overlays.size()==1 and overlays[0].get_global_rect().is_equal_approx(Rect2(Vector2.ZERO,canvas)),"Existing paused dim rectangle covers the full canvas once")
	menus.show_mutation("momentum_bank",["flywheel_release","countersteer"],"qa-draft",39)
	await settle()
	var read_buttons: Array = menus._content.find_children("*","Button",true,false)
	check(read_buttons.any(func(node: Node) -> bool: return node.text == "READ"),"Hosted mobile mutation screen has actual touch READ affordances")
	menus.mobile_hud = false
	menus.set_presentation_canvas(Vector2(800,480))
	menus.show_settings({})
	await settle()
	check(menus._content.position==Vector2.ZERO and menus._content.size==Vector2(800,480) and menus._content.scale==Vector2.ONE and menus.presentation_snapshot().presentation_class=="frontend","Desktop Options uses full-client responsive root while mobile safe panels remain unchanged")
	menus.show_hud(stats())
	check(menus._hud.player_panel.get_global_rect()==Rect2(86,6,248,48) and menus._hud.xp_panel.get_global_rect()==Rect2(326,450,388,28),"Desktop permanent HUD retains accepted panel positions")
	check(menus._hud.xp_label.text=="LV 19  /  NEXT INVESTMENT" and menus._hud.burst.text=="BURST RECHARGING   2.7 s","Desktop captions remain unchanged")
	menus.show_mutation("momentum_bank",["flywheel_release","countersteer"],"qa-desktop",39)
	check(not menus._content.find_children("*","Button",true,false).any(func(node: Node)->bool:return node.text=="READ"),"Desktop mutation keeps its accepted card arrangement")
	var desktop_hint: Label
	for node: Node in menus._content.get_children():
		if node is Label and node.text=="CONFIRM: MUTATE / REROLL: FRESH DRAFT": desktop_hint=node
	check(desktop_hint!=null and desktop_hint.position==Vector2(24,334) and desktop_hint.size==Vector2(402,16),"Desktop mutation instruction retains accepted text and geometry")

func run() -> void:
	if not valid_report(): push_error("Fresh absolute external003A.2 report required"); quit(2); return
	root.size = Vector2i(1200,480)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	menus = Menus.new()
	root.add_child(menus)
	menus.action.connect(func(intent: String,value: Variant) -> void: intents.append({"intent":intent,"value":value}))
	await settle()
	for fixture: Array in [[Vector2(800,480),Rect2(0,0,800,480)],[Vector2(1200,480),Rect2(24,8,1136,464)],
		[Vector2(960,480),Rect2(30,0,900,480)],[Vector2(720,432),Rect2(8,12,704,408)]]:
		await hud_case(fixture[0],fixture[1])
		await mutation_read_geometry(fixture[0],fixture[1])
	await menu_inset_change()
	var file: FileAccess = FileAccess.open(report,FileAccess.WRITE)
	check(file!=null,"Fresh read-only presentation report opens")
	if file!=null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"scope":"Actual Menus/font/layout transforms with declared read-only HUD states; no Main gameplay, device feel, or natural acquisition claim.","player_files_opened":0},"\t"))
		file.close()
	print("MOBILE_MENU_HUD_SAFE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	menus.free()
	quit(0 if failures.is_empty() else 1)
