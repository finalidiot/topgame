extends SceneTree
## Actual Main/Menus integration with isolated profiles and declared initial
## wallet/frozen Duel fixtures. Native OS window actuation is optional; no phone
## or natural outcome/physics acceptance is inferred from these UI contracts.
const Layout = preload("res://scripts/combat_hud_layout.gd")
const FrontendLayout = preload("res://scripts/frontend_layout.gd")
const Physics = preload("res://scripts/battle.gd")
const Save = preload("res://scripts/collection_save.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _battle_sound(_kind: String) -> void: pass
var game: QuietMain
var report: String = ""
var profile: String = ""
var native: bool = false
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var player_before: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func settle() -> void:
	game._refresh_window_presentation()
	for tick: int in range(3): await process_frame
func file_state(path: String) -> Dictionary:
	return {"exists":FileAccess.file_exists(path),"sha256":FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
func world_state() -> Dictionary:
	var fighters: Array[Dictionary] = []
	for fighter: Dictionary in game.battle._ordered_fighters():
		var row: Dictionary = {}
		for key: String in ["entity_id","pos","vel","rpm","wobble","height","height_vel","mass","radius","build","stats","part_physics","cooldown","burst_time","outcome","phase"]:
			row[key] = fighter[key]
		fighters.append(row.duplicate(true))
	return {"fighters":fighters,"elapsed":game.battle.elapsed,"seed":game.battle.seed_value,
		"power_time":game.battle.powers.time,"roster_time":game.battle.roster.time,
		"ecology_time":game.battle.roster.ecology.time,"hits":game.battle.hits,
		"limit":game.battle.live_time_limit,"projection":game.battle.project(Vector2.ZERO)}
func button(intent: String) -> Button:
	for node: Node in game.menus.find_children("*","Button",true,false):
		if str(node.get_meta("intent","")) == intent and node.is_visible_in_tree(): return node
	return null
func press(intent: String) -> void:
	var control: Button = button(intent)
	check(control != null,"Actual visible control exists: "+intent)
	if control != null: control.pressed.emit()
	await settle()
func inspect(expected: String, label: String) -> Dictionary:
	await settle()
	var actual: Dictionary = game.menus.presentation_snapshot()
	var presentation: Dictionary = game.window_presentation_snapshot()
	check(actual.presentation_class == expected and presentation.presentation_class == expected,label+": Main and visible Menus agree on centralized class")
	check(actual.presentation_class == FrontendLayout.presentation_class(game.menus.screen),label+": classification follows actual visible screen")
	check(Vector2(actual.canvas_size) == Vector2(presentation.canvas_size),label+": Main publishes current canvas")
	check(game.combat_viewport.size == Vector2i(640,360) and game.battle.project(Vector2.ZERO) == Vector2(320,165),label+": canonical arena and camera remain fixed")
	var accepted: Dictionary = Layout.responsive(presentation.canvas_size,false)
	check(game.combat_frame.get_rect() == accepted.arena_rect,label+": accepted desktop combat rectangle is unchanged")
	check(game.combat_frame.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,label+": combat retains nearest filtering")
	if expected == "frontend":
		check(Rect2(actual.root_rect).is_equal_approx(Rect2(Vector2.ZERO,presentation.canvas_size)),label+": front-end root occupies the whole presentation client")
		check(Vector2(actual.root_scale).is_equal_approx(Vector2.ONE),label+": front-end geometry expands without scaling the old panel")
		check(not game.combat_frame.visible and not game.presentation_surround.visible,label+": page owns its foundation instead of underlying arena/casing")
	else:
		check(game.combat_frame.visible == game.battle.visible and game.presentation_surround.visible,label+": accepted arena/casing remains behind combat or modal")
		if expected == "modal":
			var modal: Rect2 = actual.root_rect
			check(modal.get_center().distance_to(Vector2(presentation.canvas_size)*0.5) < 1.0,label+": modal remains centered above the retained arena")
			if FrontendLayout.uses_run_overlay(game.menus.screen):
				check(modal.is_equal_approx(Rect2(Vector2.ZERO,presentation.canvas_size)) and Vector2(actual.root_scale)==Vector2.ONE,label+": Run overlay uses the whole current client")
				check(actual.get("presentation_policy","")=="run_overlay",label+": visible Run overlay exposes its responsive policy")
			else:
				check(modal.size.is_equal_approx(Vector2(640,360)) and Vector2(actual.root_scale)==Vector2.ONE,label+": accepted Pause remains the centered native component")
	observations.append({"label":label,"client_size":root.size,"menus":actual,"main":presentation})
	return actual
func stable_layout(label: String) -> void:
	var before: Dictionary = game.menus.presentation_snapshot()
	var focus: Control = root.gui_get_focus_owner()
	var children: Array[int] = []
	for child: Node in game.menus._content.get_children(): children.append(child.get_instance_id())
	for tick: int in range(12): game._refresh_window_presentation(); await process_frame
	var after: Dictionary = game.menus.presentation_snapshot()
	var current: Array[int] = []
	for child: Node in game.menus._content.get_children(): current.append(child.get_instance_id())
	check(after.content_instance_id == before.content_instance_id and current == children,label+": unchanged client does not rebuild controls")
	check(after.layout_revision == before.layout_revision,label+": unchanged presentation does not repeatedly reflow")
	check(root.gui_get_focus_owner() == focus,label+": refresh preserves focused intent")
func hub_context() -> void:
	game._title(); await inspect("frontend","fresh Hub before Workshop")
	var text: String = ""
	for node: Node in game.menus._content.find_children("*","Label",true,false): text += node.text.to_upper()+"\n"
	check(text.contains("CREDITS") and text.contains("137"),"Hub shows current137 CREDITS without a prior Workshop cache")
	check(text.contains("SALVAGE") and text.contains("29"),"Hub shows current29 SALVAGE without placeholders")
	check(game.collection.owned_count() == 3 and game.collection.credits == 137 and game.collection.salvage == 29,"Hub display cannot change actual ownership or wallet")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report = argument.trim_prefix("--report=")
		if argument.begins_with("--profile="): profile = argument.trim_prefix("--profile=")
		if argument == "--native": native = true
	if not report.is_absolute_path() or FileAccess.file_exists(report) or not report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/"):
		push_error("A fresh external003A.2 --report is required"); quit(2); return
	if profile.is_empty(): profile = report.get_base_dir().get_base_dir().path_join("temp/frontend_classes_%d_%d.json"%[OS.get_process_id(),Time.get_ticks_usec()])
	if not profile.is_absolute_path() or not profile.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/temp/"):
		push_error("An isolated external003A.2 profile is required"); quit(2); return
	for suffix: String in ["",".bak",".tmp",".bak.tmp",".preferences.cfg",".last_run_director.json"]:
		if FileAccess.file_exists(profile+suffix): push_error("Existing QA profile is preserved"); quit(2); return
	for path: String in [Save.DEFAULT_PATH,Save.DEFAULT_PATH+".bak","user://prototype.cfg","user://last_run_director.json"]: player_before[path] = file_state(path)
	for screen: String in ["hud","battle"]: check(FrontendLayout.presentation_class(screen)=="combat","Central combat classification: "+screen)
	for screen: String in ["pause","reward","mutation","level_up","acquisition"]: check(FrontendLayout.presentation_class(screen)=="modal","Central modal classification: "+screen)
	for screen: String in ["title_gate","collection_title","play_modes","starter_ceremony","starter_confirm","starter_owned","collection_workshop","garage","shop","packet_purchase","packet_odds","packet_open","settings","help","save_tools","reset_confirm","result","future_frontend"]:
		check(FrontendLayout.presentation_class(screen)=="frontend","Central page/default classification: "+screen)
	root.size = Vector2i(800,480)
	var mode_before: int = DisplayServer.window_get_mode()
	var border_before: bool = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	game = QuietMain.new(); game.smoke_mode = true; game.collection_path = profile
	root.add_child(game); game.set_process(false); game.battle.set_physics_process(false)
	game._title_gate(); await inspect("frontend","actual title gate")
	await press("enter_frontend")
	await inspect("frontend","actual uninitialized Hub")
	game._begin_collection(); await inspect("frontend","actual starter selection")
	game._action("select_first_starter","breaker"); await inspect("frontend","actual starter confirmation")
	game._action("confirm_first_starter","breaker"); await inspect("frontend","actual ownership page")
	var fixture: Dictionary = game.collection._data.duplicate(true)
	fixture.progression.credits = 137; fixture.progression.salvage = 29
	check(bool(game.collection._commit(fixture,"declared_ui_wallet_fixture").ok),"Declared isolated wallet fixture is saved through the canonical save writer")
	var profile_before: Dictionary = file_state(profile)
	await hub_context()
	for client: Vector2i in [Vector2i(800,480),Vector2i(960,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size = client; game._title(); await inspect("frontend","Hub "+str(client))
		game._action("play_modes"); await inspect("frontend","Play modes "+str(client))
		game._action("settings"); await inspect("frontend","Options "+str(client))
		await stable_layout("Options "+str(client))
		game._show_save_tools(); await inspect("frontend","Save tools "+str(client))
		game._action("help"); await inspect("frontend","Help "+str(client))
		game._garage(); await inspect("frontend","Workshop "+str(client))
		game._shop(); await inspect("frontend","Shop "+str(client))
		game._action("packet_odds"); await inspect("frontend","Packet odds "+str(client))
	check(file_state(profile)==profile_before,"Presentation/navigation does not write collection state or transact wallet")
	game._start_battle("duel"); game.battle.set_physics_process(false)
	for tick: int in range(240):
		if game.battle.battle_status == "battle": break
		game.battle._physics_process(Physics.FIXED_DT)
	check(game.battle.battle_status=="battle","Declared Duel completes its actual opening countdown before UI freeze")
	await inspect("combat","actual Duel HUD")
	game._pause(); await inspect("modal","actual Pause above Duel")
	var frozen: Dictionary = world_state()
	var retained_visible: bool = game.battle.visible
	await press("settings"); await inspect("frontend","Options entered from Pause")
	check(game.battle.paused and game.battle.visible == retained_visible and world_state() == frozen,"Pause Options hides only presentation and retains the frozen world")
	var content: int = game.menus._content.get_instance_id()
	var focus: Control = root.gui_get_focus_owner()
	check(is_instance_valid(focus) and game.menus._content.is_ancestor_of(focus),"Options begins with an actual focused control inside the page")
	root.size = Vector2i(1280,800); await inspect("frontend","live Options contraction")
	root.size = Vector2i(1920,1017); await inspect("frontend","live Options expansion")
	check(game.menus._content.get_instance_id()==content and root.gui_get_focus_owner()==focus,"Live breakpoint reflow preserves controls and focused intent")
	check(world_state()==frozen,"Live UI resizing never advances or changes the world")
	if native:
		check(DisplayServer.get_name() != "headless","Native window actuation requires a rendered engine")
		var restore_size: Vector2i = root.size; var restore_position: Vector2i = root.position
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED); await inspect("frontend","native maximized Options")
		check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MAXIMIZED and not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS),"Native Maximize remains a decorated OS window")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); await inspect("frontend","native restored Options")
		check(root.size==restore_size and root.position==restore_position,"Native Restore retains OS-managed previous bounds")
		check(world_state()==frozen,"Native window actuation preserves the retained world")
	await press("back_settings"); await inspect("modal","Back restores actual Pause")
	check(game.screen=="pause" and game.battle.visible==retained_visible and world_state()==frozen,"Back from Options restores the same paused world")
	await press("resume"); game.battle.set_physics_process(false); await inspect("combat","Resume restores actual HUD")
	check(game.battle.battle_status=="reentry" and world_state()==frozen,"Resume retains accepted READY state without a UI-generated simulation step")
	# This declared result callback is a presentation fixture, not a physics win.
	game._round_finished({"won":true,"reason":"declared_ui_result","duration":0.0,"hits":0,"player_remaining":1.0,"enemy_remaining":0.0})
	await inspect("frontend","actual front-end result route")
	check(game.screen=="result" and game.battle.visible and not game.combat_frame.visible,"Front-end result covers the retained completed arena")
	if not native: check(DisplayServer.window_get_mode()==mode_before and DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)==border_before,"Read-only UI reflow never changes native mode or border policy")
	for path: String in player_before: check(file_state(path)==player_before[path],"Real player data remains untouched: "+path)
	var output: FileAccess = FileAccess.open(report,FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"isolated_profile":profile,"native_window_actuation":native,
		"scope":"Actual Main/Menus class and route integration. Legal Breaker acquisition, explicit137/29 wallet fixture, paused legal Duel and declared UI result callback. Fixed combat geometry/state, responsive page roots, modal restoration and stable control identity/focus. Optional native Max/Restore are OS API proof; no human physical interaction, natural outcome or Android device/APK acceptance claim."},"\t")); output.close()
	game.free(); await process_frame
	print("FRONTEND_CLASSES_003A2_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
