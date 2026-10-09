extends "res://tests/test_ability_card_hierarchy_003a1.gd"
## Main input/selection/acquisition with declared legal initial draft fixtures.
## Initial ranks/offers are supplied to isolate UI; no XP, damage or wins claimed.
const Main = preload("res://scripts/main.gd")
const Save = preload("res://scripts/collection_save.gd")
var game: Main
var profile: String = ""
var frames_path: String = ""
var images: Dictionary = {}
var matrix: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var selections: Array[Dictionary] = []
var movie_start_frame: int = 0
var last_phase: String = ""
var phase_start: int = 0
var saved_before: String = ""
var collection_before: Dictionary = {}

func phase(name: String) -> void:
	var frame: int = Engine.get_process_frames()
	if not last_phase.is_empty(): phases.append({"name":last_phase,"from_frame":phase_start,"to_frame":frame})
	last_phase=name;phase_start=frame
func screenshot(name: String, card: Button = null) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = frames_path.path_join(name + ".png")
	check(not FileAccess.file_exists(path) and image.save_png(path)==OK,"Actual native screenshot is saved once: "+name)
	var record: Dictionary = {"path":path,"sha256":FileAccess.get_sha256(path),"frame":Engine.get_process_frames(),"menu_rect":[ui._content.get_global_rect().position.x,ui._content.get_global_rect().position.y,ui._content.size.x,ui._content.size.y]}
	if card != null:
		var area: Rect2i = Rect2i(card.get_global_rect()).grow(2)
		record["card_rect"]=[area.position.x,area.position.y,area.size.x,area.size.y]
		record["badge"]=card.get_meta("ability_badge")
	images[name]=record
func fixture(rank: int = 0, focus: String = "redline") -> void:
	game._clear_run()
	game.run_context.start(game.collection.equipped_build(),421,"breaker")
	game.run_context._owned_power_ids.clear()
	if rank>0: game.run_context._owned_power_ids.assign(["redline","dead_centre","afterimage"])
	game.run_context._power_ranks={} if rank==0 else {"redline":rank,"dead_centre":rank,"afterimage":rank}
	game.run_context._pending_offer.assign(["redline","dead_centre","afterimage"])
	game.run_context._draft_queue.assign([{"id":"draft/card_fixture_%d"%rank,"kind":"starting" if rank==0 else "level","level":rank+1}])
	game._draft_resume_origin="starting"
	game._reward_focus_id=focus
	game.mode="run"
	game._show_reward()
	await settle(10)
	if game.screen!="reward" or cards().size()!=3:
		check(false,"Declared fixture must reach its real three-card Main draft");quit(1);return
func find_card(id: String) -> Button:
	for card: Button in cards():
		if str(card.get_meta("power_id"))==id:return card
	return null
func pad_button(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new();event.device=0;event.button_index=button
	event.pressed=true;Input.parse_input_event(event);await settle(4)
	event.pressed=false;Input.parse_input_event(event);await settle(4)
func pad_direction(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new();event.device=0;event.axis=axis;event.axis_value=value
	Input.parse_input_event(event);await settle(5);event.axis_value=0;Input.parse_input_event(event);await settle(5)
func park_pointer() -> void:
	# Hover intentionally reads independently of focus. Clear the previous mouse
	# position before demonstrating controller-only inspection/navigation.
	var event := InputEventMouseMotion.new();event.position=Vector2(12,12);event.global_position=event.position
	Input.parse_input_event(event);await settle(5)
func selection(power_id: String, expected_rank: int, branch: String = "") -> void:
	check(game.screen=="acquisition","Actual choice reaches the acquisition presentation")
	check(int(game.run_context.power_ranks.get(power_id,0))==expected_rank,"Actual RunContext claims the selected investment once")
	if not branch.is_empty():check(str(game.run_context.power_mutations.get(power_id,""))==branch,"Actual mutation claim preserves branch ownership")
	selections.append({"power":power_id,"rank":expected_rank,"mutation":branch,"screen":game.screen,"frame":Engine.get_process_frames()})
	await screenshot("selected_"+power_id+"_"+str(expected_rank))
	await settle(48)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
		if arg.begins_with("--profile="):profile=arg.trim_prefix("--profile=")
		if arg.begins_with("--frames="):frames_path=arg.trim_prefix("--frames=")
	for path: String in [report,profile,frames_path]:
		if not path.is_absolute_path() or not path.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/"):
			push_error("Fresh external QA paths required");quit(2);return
	if FileAccess.file_exists(report) or FileAccess.file_exists(profile) or DirAccess.dir_exists_absolute(frames_path):
		push_error("Existing review files must remain untouched");quit(2);return
	DirAccess.make_dir_recursive_absolute(profile.get_base_dir());DirAccess.make_dir_recursive_absolute(frames_path)
	root.size=Vector2i(800,480);root.content_scale_size=Vector2i(800,480)
	Input.use_accumulated_input=false
	var collection := Save.new(profile);collection.load_save()
	check(collection.initialize_starter("breaker").ok,"Declared isolated collection owns an ordinary legal starter")
	var cfg := ConfigFile.new();cfg.set_value("settings","controller_layout","xbox")
	check(cfg.save(profile+".preferences.cfg")==OK,"Review uses its own controller preference")
	game=Main.new();game.collection_path=profile;root.add_child(game);await settle(8)
	DisplayServer.window_set_title("Spinning Metal — CARD HIERARCHY ISOLATED QA")
	ui=game.menus
	ui.action.connect(func(name: String,value: Variant)->void:actions.append({"name":name,"value":value}))
	saved_before=FileAccess.get_sha256(profile)
	collection_before={"credits":game.collection.credits,"salvage":game.collection.salvage,"parts":game.collection.owned_count(),"build":game.collection.equipped_build()}
	# Nine actual UI cards, not repainted art; their entire raw source screens persist.
	for family: String in ["redline","dead_centre","afterimage"]:
		for rank: int in [0,1]:
			await fixture(rank,family)
			var card: Button=find_card(family)
			await screenshot(family+"_"+str(rank+1),card)
			matrix.append({"family":family,"rank":rank+1,"image":family+"_"+str(rank+1),"badge":card.get_meta("ability_badge")})
		await fixture(2,family)
		await click(find_card(family));check(game.screen=="mutation","Ordinary parent selection opens its real two-branch mutation draft")
		var branch: String={"redline":"breakneck","dead_centre":"bulwark","afterimage":"ghost_circuit"}[family]
		find_card(branch).grab_focus();await settle(10)
		await screenshot(branch,find_card(branch));matrix.append({"family":family,"rank":3,"image":branch,"badge":"MUTATION"})
	check(matrix.size()==9,"Matrix includes the required three complete power/upgrade/mutation progressions")
	movie_start_frame=Engine.get_process_frames()
	phase("POWER / NEW FAMILY / KEYBOARD AND HOVER")
	await fixture(0,"redline");await settle(45)
	await motion(find_card("afterimage"));await settle(40)
	await key(KEY_RIGHT);await settle(35)
	await motion(find_card("redline"));find_card("redline").grab_focus();await settle(35)
	await screenshot("normal_draft_focus",find_card("redline"))
	await key(KEY_ENTER);phase("POWER COLLECTED / ACTUAL ACQUISITION")
	await selection("redline",1)
	phase("RANK II / OWNED POWER / CONTROLLER FOCUS")
	await fixture(1,"redline");Bindings.configure("xbox");ui._note_input_profile("xbox")
	await park_pointer();find_card("redline").grab_focus()
	await settle(45);await pad_direction(JOY_AXIS_LEFT_X,0.9);await settle(35)
	await pad_direction(JOY_AXIS_LEFT_X,-0.9);await settle(35)
	await screenshot("rank_ii_controller_focus",find_card("redline"))
	await pad_button(Bindings.confirm_button("xbox"));phase("RANK II CLAIMED / ACTUAL ACQUISITION")
	await selection("redline",2)
	phase("MUTATION / CHOOSE A MAJOR TRANSFORMATION")
	await fixture(2,"afterimage");await settle(45)
	await click(find_card("afterimage"));await settle(35)
	Bindings.configure("nintendo");ui._note_input_profile("nintendo")
	await park_pointer()
	find_card("ghost_circuit").release_focus()
	find_card("ghost_circuit").grab_focus();await settle(45)
	check(ui._ability_inspector.breakdown.name=="Ghost Circuit","Controller focus reads the selected Ghost branch after the pointer leaves sibling cards")
	await screenshot("mutation_controller_focus",find_card("ghost_circuit"))
	await pad_direction(JOY_AXIS_LEFT_X,0.9);await settle(35)
	await pad_direction(JOY_AXIS_LEFT_X,-0.9);await settle(35)
	await pad_button(Bindings.confirm_button("nintendo"));phase("GHOST CIRCUIT CLAIMED / ACTUAL MUTATION")
	await selection("afterimage",3,"ghost_circuit")
	phase("TOUCH / ONE ACTUAL POWER CLAIM")
	await fixture(0,"dead_centre");ui._note_input_profile("touch")
	await settle(45)
	await tap(find_card("dead_centre"))
	await selection("dead_centre",1)
	check(game.run_context.owned_power_ids==["dead_centre"],"Touch plus engine mouse emulation claims one actual investment through Main")
	phase("end")
	var collection_after: Dictionary={"credits":game.collection.credits,"salvage":game.collection.salvage,"parts":game.collection.owned_count(),"build":game.collection.equipped_build()}
	check(collection_before==collection_after,"Actual isolated Run launch/abort bookkeeping grants no wallet, parts or build changes")
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"profile":profile,"profile_sha256_before":saved_before,"profile_sha256":FileAccess.get_sha256(profile),"isolated_collection_before":collection_before,"isolated_collection_after":collection_after,"images":images,"matrix":matrix,"phases":phases,"movie_start_frame":movie_start_frame,"movie_end_frame":Engine.get_process_frames(),"selections":selections,"scope":"Actual Main menus, mapped input, RunContext selection and acquisition. Explicit legal initial16-family roster comparisons and preowned1/2-rank drafts isolate UI; no XP/damage/outcomes/natural draft or human hardware claim. Real launch/abort reward bookkeeping may change the isolated QA save hash but wallet/parts/build remain exact; no human save is opened. Original illustration pixels remain unmodified. The final movie excludes the fast matrix preparation prelude."},"\t"));file.close()
	game.sounds.muted=true;game.music.set_paused(true)
	game.free();print("CARD_HIERARCHY_CAPTURE_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
