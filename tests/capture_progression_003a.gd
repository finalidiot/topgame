extends SceneTree
## Real Main, control events, natural Run outcomes and production packet view.
## Showcase-only wallet/seed fixtures are explicitly labelled before boot.
const Main = preload("res://scripts/main.gd")
const Collection = preload("res://scripts/collection_save.gd")
const Economy = preload("res://scripts/packet_economy.gd")
const Catalog = preload("res://scripts/parts.gd")
const Bot = preload("res://tests/rpm_bot.gd")
var game: Node2D
var output: String = ""
var frames: String = ""
var collection_path: String = ""
var diagnostic: bool = false
var showcase: bool = false
var max_run_seconds: float = 300.0
var bot_style: String = "hybrid"
var raw_start: int = 0
var phase: String = ""
var phase_start: int = 0
var sections: Array[Dictionary] = []
var images: Dictionary = {}
var events: Array[Dictionary] = []
var rows: Array[Dictionary] = []
var results: Array[Dictionary] = []
var receipts: Array[Dictionary] = []
var axis: Vector2 = Vector2.ZERO
var burst_down: bool = false
var brake_down: bool = false
var fixture: Dictionary = {}
var before_collection: Dictionary = {}
var after_collection: Dictionary = {}
var equipped_new: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func frame() -> int: return Engine.get_process_frames() - raw_start
func fail(message: String) -> void:
	push_error(message)
	quit(2)
func wait_frames(count: int) -> void:
	for index: int in range(count): await process_frame

func safe_path(path: String, folder: String) -> bool:
	var qa: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa.is_empty(): qa = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	var allowed: String = qa.replace("\\", "/").simplify_path().path_join("003A/" + folder).to_lower() + "/"
	return path.is_absolute_path() and path.replace("\\", "/").simplify_path().to_lower().begins_with(allowed)

func section(name: String) -> void:
	if not phase.is_empty(): sections.append({"name":phase,"from_frame":phase_start,"to_frame":frame()})
	phase = name
	phase_start = frame()
	print("PROGRESSION_CAPTURE_STAGE ", name, " frame=", frame(), " screen=", game.screen if is_instance_valid(game) else "none")

func image(name: String) -> void:
	if diagnostic: return
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	assert(pixels.get_size() == Vector2i(640,360))
	var path: String = frames.path_join(name + ".png")
	assert(not FileAccess.file_exists(path) and pixels.save_png(path) == OK)
	images[name] = {"path":path,"frame":frame(),"screen":game.screen,"wallet":game.collection.wallet()}

func checkpoint(name: String, seconds: float = 1.6) -> void:
	section(name)
	await wait_frames(4)
	await image(name)
	await wait_frames(roundi(seconds * 60.0))

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	events.append({"frame":frame(),"type":"key","code":code,"pressed":pressed,"screen":game.screen})

func tap_key(code: Key) -> void:
	key(code,true)
	await wait_frames(2)
	key(code,false)
	await wait_frames(2)

func button(code: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = code
	event.pressed = pressed
	Input.parse_input_event(event)
	events.append({"frame":frame(),"type":"joy_button","button":code,"pressed":pressed,"screen":game.screen})

func matching(node: Node, metadata: Dictionary) -> Control:
	if node is Control and node.is_visible_in_tree():
		var matches: bool = true
		for field: String in metadata:
			if not node.has_meta(field) or node.get_meta(field) != metadata[field]: matches = false
		if matches and (not node is BaseButton or not node.disabled): return node
	for child: Node in node.get_children():
		var found: Control = matching(child,metadata)
		if found != null: return found
	return null

func click(control: Control) -> void:
	assert(is_instance_valid(control) and control.is_visible_in_tree())
	var point: Vector2 = control.get_global_rect().get_center()
	assert(Rect2(0,0,640,360).has_point(point))
	var description: Dictionary = {"frame":frame(),"type":"gui_mouse_click","intent":control.get_meta("intent", ""),"position":[point.x,point.y],"screen":game.screen}
	if control.has_meta("payload"): description.payload = control.get_meta("payload")
	var movement := InputEventMouseMotion.new()
	movement.position = point
	movement.global_position = point
	Input.parse_input_event(movement)
	await wait_frames(2)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await wait_frames(2)
	events.append(description)
	await wait_frames(4)

func click_intent(name: String) -> void:
	var control: Control = matching(game.menus,{"intent":name})
	assert(control != null,"Missing actual visible UI intent " + name + " at " + game.screen)
	await click(control)

func controls(direction: Vector2, burst: bool, brake: bool) -> void:
	if direction.distance_to(axis) > 0.01:
		for index: int in range(2):
			var event := InputEventJoypadMotion.new()
			event.device = 0
			event.axis = JOY_AXIS_LEFT_X if index == 0 else JOY_AXIS_LEFT_Y
			event.axis_value = direction.x if index == 0 else direction.y
			Input.parse_input_event(event)
		axis = direction
		events.append({"frame":frame(),"type":"joy_axes","direction":[direction.x,direction.y],"screen":game.screen})
	if burst != burst_down: button(JOY_BUTTON_A,burst); burst_down = burst
	if brake != brake_down: button(JOY_BUTTON_LEFT_SHOULDER,brake); brake_down = brake

func choose_offer() -> void:
	controls(Vector2.ZERO,false,false)
	await wait_frames(3)
	var choice: Control
	if game.screen == "reward":
		for id: String in ["afterimage","predator_line","crosscut","high_gear","chain_impact","impact_wake","iron_comet","orbit_drive","crash_guard","momentum_bank"]:
			choice = matching(game.menus,{"intent":"choose_power","power_id":id})
			if choice != null: break
		if choice == null: choice = matching(game.menus,{"intent":"choose_power"})
	elif game.screen == "mutation": choice = matching(game.menus,{"intent":"choose_mutation"})
	else: return
	assert(choice != null)
	await click(choice)

func boot() -> void:
	game = Main.new()
	game.collection_path = collection_path
	game.qa_task_id = "003A"
	game.review_audio = not diagnostic
	if showcase:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(fixture.seed)
		game.packet_rng_override = rng
	root.add_child(game)
	await wait_frames(4)
	game.music.configure_playback(not diagnostic)
	assert(game.screen == "title_gate" and game.preferences_path == collection_path + ".preferences.cfg")

func seed_showcase() -> void:
	var save = Collection.new(collection_path)
	assert(bool(save.load_save().ok) and bool(save.initialize_starter("breaker").ok))
	var begin: Dictionary = save.begin_reward_run()
	var seeded: Dictionary = save.pay_run_reward(str(begin.run_nonce),{"reward_provenance":"earned-clear-v1","earned_threats_cleared":50,"earned_elites_cleared":0,"earned_bosses_cleared":0,"reward_fixture":false,"aborted":false})
	assert(bool(seeded.ok) and save.credits == 600)
	var selected: int = -1
	var example: Dictionary = {}
	for seed_value: int in range(1,10000):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var roll: Dictionary = Economy.generate("standard",save.owned_parts(),rng)
		var common: bool = false
		var rare: bool = false
		var new_part: bool = false
		var duplicate: bool = false
		for row: Dictionary in roll.rows:
			common = common or row.rarity == "COMMON"
			rare = rare or row.rarity in ["RARE","EPIC","LEGENDARY"]
			new_part = new_part or bool(row.new)
			duplicate = duplicate or not bool(row.new)
		if common and rare and new_part and duplicate: selected = seed_value; example = roll; break
	assert(selected > 0)
	fixture = {"label":"EXPLICIT SEEDED QA WALLET / PRODUCTION PACKET ROLL AND VIEW","initial_credits":600,"initial_owned":3,"seed":selected,"preview":example}

func fresh_starter() -> void:
	assert(not game.collection.is_initialized() and game.collection.owned_count() == 0)
	await tap_key(KEY_ENTER)
	await click_intent("begin_collection")
	await click(matching(game.menus,{"intent":"select_first_starter","starter_id":"breaker"}))
	await click_intent("confirm_first_starter")
	await wait_frames(150)
	assert(game.screen == "garage" and game.collection.owned_count() == 3 and game.collection.credits == 0)
	before_collection = game.collection.snapshot()
	await checkpoint("collection_before",1.3)

func natural_run(index: int) -> bool:
	section("run_" + str(index) + "_start")
	await click_intent("launch_owned_run")
	await checkpoint("starting_power_" + str(index),1.0)
	await choose_offer()
	while game.screen != "battle": await wait_frames(1)
	while game.battle.battle_status != "battle": await wait_frames(1)
	await image("run_" + str(index) + "_opening")
	section("run_" + str(index) + "_natural_play")
	var ending: bool = false
	for tick: int in range(roundi(max_run_seconds * 60.0)):
		if game.screen == "result": break
		if game.screen == "battle":
			var earned: int = int(Economy.run_reward(game.battle.continuous.snapshot()).credits)
			if not ending and game.collection.credits + earned >= Economy.packet_cost("standard"):
				ending = true
				section("run_" + str(index) + "_earned_target")
				await image("run_" + str(index) + "_earned_target")
			# After the earned target, deliberately risky real controls demonstrate
			# a normal physical defeat promptly. Never assign an outcome or RPM.
			var c: Dictionary = Bot.input(game.battle,"reckless" if ending else bot_style,tick)
			controls(c.direction,c.burst,c.brake)
			if tick % 60 == 0: rows.append({"frame":frame(),"time":game.battle.elapsed,"state":game.battle.continuous.snapshot(),"wallet":game.collection.wallet(),"rpm":game.battle.player_entity().rpm})
		elif game.screen in ["reward","mutation"]: await choose_offer()
		else: controls(Vector2.ZERO,false,false)
		await wait_frames(1)
	controls(Vector2.ZERO,false,false)
	if game.screen != "result": fail("Input-only Run did not naturally finish in the allowed limit"); return false
	assert(bool(game.last_result.continuous_run) and not bool(game.last_result.won) and not str(game.battle.player_entity().outcome).is_empty())
	results.append(game.last_result.duplicate(true))
	await checkpoint("run_" + str(index) + "_result",3.0)
	return true

func buy_and_open(fast: bool = false, prefix: String = "packet") -> void:
	await click(matching(game.menus,{"intent":"request_packet_purchase","payload":"standard"}))
	await checkpoint(prefix + "_purchase_confirmation",1.4)
	var wallet_before: Dictionary = game.collection.wallet()
	await click_intent("confirm_packet_purchase")
	assert(game.screen == "packet_open")
	var receipt: Dictionary = game.collection.pending_packet()
	assert(not receipt.is_empty() and game.collection.credits == int(wallet_before.credits) - Economy.packet_cost("standard"))
	section(prefix + "_physical_opening")
	# Show the landed sealed bag before its normal crinkle begins at0.45s.
	while game.menus._packet_view.elapsed < 0.30: await wait_frames(1)
	await image(prefix + "_sealed")
	while game.menus._packet_view.elapsed < 0.60: await wait_frames(1)
	await image(prefix + "_crinkle")
	await wait_frames(65)
	if fast:
		var start: int = frame()
		await click_intent("packet_skip")
		assert(game.menus._packet_view.phase == "RESULT" and frame() - start < 90)
	else:
		await click_intent("packet_tear")
		await wait_frames(9)
		await image(prefix + "_tear")
		await wait_frames(39)
		await image(prefix + "_spill")
		while game.menus._packet_view.phase != "RESULT": await wait_frames(1)
	await checkpoint(prefix + "_result",4.2)
	var completed: Dictionary = game.collection.pending_packet()
	assert(completed.rows == receipt.rows and completed.id == receipt.id and completed.status == "resolved")
	receipts.append(completed)

func equip_unlocked() -> void:
	var chosen: Dictionary = {}
	for row: Dictionary in receipts[0].rows:
		if bool(row.new): chosen = row; break
	assert(not chosen.is_empty(),"Natural packet must discover an equippable new component")
	await click_intent("packet_workshop")
	assert(game.screen == "garage")
	after_collection = game.collection.snapshot()
	await checkpoint("collection_after",2.5)
	var tab: Control = matching(game.menus,{"catalogue_tab":chosen.category})
	await click(tab)
	var card: Control = matching(game.menus,{"part_category":chosen.category,"part_id":chosen.id})
	assert(card != null and bool(card.get_meta("owned",false)))
	for attempt: int in range(100):
		if root.gui_get_focus_owner() == card: break
		await tap_key(KEY_TAB)
	assert(root.gui_get_focus_owner() == card)
	await tap_key(KEY_ENTER)
	assert(game.collection.equipped_build()[chosen.category] == chosen.id)
	equipped_new = chosen
	await checkpoint("equipped_new_part",2.5)
	await click_intent("launch_owned_run")
	await checkpoint("run_again_starting_power",1.0)
	await choose_offer()
	while game.screen != "battle": await wait_frames(1)
	while game.battle.battle_status != "battle": await wait_frames(1)
	section("run_again_new_machine")
	for tick: int in range(360):
		if game.screen == "battle":
			var c: Dictionary = Bot.input(game.battle,"defensive",tick)
			controls(c.direction,c.burst,c.brake)
		elif game.screen in ["reward","mutation"]: await choose_offer()
		await wait_frames(1)
	controls(Vector2.ZERO,false,false)
	await image("run_again_new_machine")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): output = arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frames = arg.trim_prefix("--frames=")
		if arg.begins_with("--collection="): collection_path = arg.trim_prefix("--collection=")
		if arg.begins_with("--max-run-seconds="): max_run_seconds = float(arg.trim_prefix("--max-run-seconds="))
		if arg.begins_with("--bot-style="): bot_style = arg.trim_prefix("--bot-style=")
		if arg == "--diagnostic": diagnostic = true
		if arg == "--showcase": showcase = true
	if not safe_path(output,"manifests") or not safe_path(collection_path,"temp") or (not diagnostic and not safe_path(frames,"frames")):
		fail("Capture outputs must be explicit fresh external003AQA paths"); return
	assert(not FileAccess.file_exists(output) and not FileAccess.file_exists(collection_path))
	root.size = Vector2i(640,360)
	root.content_scale_size = Vector2i(640,360)
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not diagnostic: DirAccess.make_dir_recursive_absolute(frames)
	raw_start = Engine.get_process_frames()
	section("seeded_showcase_boot" if showcase else "normal_fresh_collection")
	if showcase: seed_showcase()
	await boot()
	if showcase:
		await tap_key(KEY_ENTER)
		await click_intent("open_shop")
		await checkpoint("shop_native",2.0)
		await click_intent("packet_odds")
		await checkpoint("packet_odds",1.2)
		await click_intent("packet_reclaimed_odds")
		await checkpoint("packet_reclaimed_odds",1.5)
		await click_intent("open_shop")
		await buy_and_open(false,"packet")
		await click_intent("packet_shop")
		await checkpoint("salvage_wallet",1.5)
		await buy_and_open(true,"fast_packet")
		await wait_frames(120)
	else:
		await fresh_starter()
		for index: int in range(1,3):
			if not await natural_run(index): return
			if game.collection.credits >= Economy.packet_cost("standard"): break
			await click_intent("customize")
		if game.collection.credits < Economy.packet_cost("standard"):
			fail("First packet must be affordable within at most two genuine Runs"); return
		await click_intent("open_shop")
		await checkpoint("shop_native",3.0)
		await buy_and_open(false,"packet")
		await equip_unlocked()
	section("complete")
	var report: Dictionary = {"task":"003A","showcase":showcase,"diagnostic":diagnostic,"bot_style":bot_style,"economy_config":Economy.config(),"native_view":[640,360],"fps":60,"raw_frames":frame(),"sections":sections,"images":images,"input_events":events,"rows":rows,"natural_results":results,"receipts":receipts,"fixture":fixture,"collection_before":before_collection,"collection_after":after_collection,"equipped_new":equipped_new,"final_collection":game.collection.snapshot(),"sfx":game.sounds.audio_snapshot(),"music":game.music.music_snapshot(),"authenticity":"Actual normal Main boot and UI input events only; real controls and naturally ended Runs supply progression wallet. No direct action/screen/outcome/position/RPM/director/currency injection after boot. Showcase alone labels its preboot fixture wallet and deterministic production purchase RNG. Receipt contents stay fixed through physical opening/skip; all save/settings paths isolated."}
	var file := FileAccess.open(output,FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	game.music.configure_playback(false)
	for channel: AudioStreamPlayer in game.sounds.channels: channel.stop()
	OS.delay_msec(200)
	game.free()
	OS.delay_msec(100)
	await wait_frames(3)
	print("PROGRESSION_CAPTURE_PASS showcase=",showcase," runs=",results.size()," packets=",receipts.size())
	quit(0)
