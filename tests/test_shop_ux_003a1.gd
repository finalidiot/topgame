extends "res://tests/test_collection_ui.gd"
## Actual GUI mouse/key/pad/touch dispatch. Wallet/starter/seed are labelled
## isolated fixtures; production chooses and persists every packet result.
const Bindings = preload("res://scripts/controller_bindings.gd")
const Save = preload("res://scripts/collection_save.gd")
var report_path: String
var profile_path: String
var frames_path: String
var mode: String = "all"
var diagnostic: bool = false
var movie_frames: int = 0
var phases: Array[Dictionary] = []
var screenshots: Dictionary = {}
var inputs: Array[Dictionary] = []
var receipts: Array[Dictionary] = []
var route_trace: Array[Dictionary] = []
var recovered_another: Dictionary = {}

func _process(_dt: float) -> bool:
	movie_frames += 1
	return false

func wait_frames(count: int) -> void:
	for frame: int in range(count): await process_frame

func phase(name: String) -> void:
	if not phases.is_empty(): phases[-1].to_frame = movie_frames
	phases.append({"name":name,"from_frame":movie_frames})

func picture(name: String) -> void:
	_check_layout(name)
	if diagnostic: return
	await RenderingServer.frame_post_draw
	var rect: Rect2i = Rect2i(Vector2i(game.menus._content.global_position),Vector2i(640,360))
	var path: String = frames_path.path_join(name+".png")
	check(root.get_texture().get_image().get_region(rect).save_png(path) == OK,"Actual menu pixels saved")
	screenshots[name] = {"path":path,"frame":movie_frames,"crop":[rect.position.x,rect.position.y,640,360]}

func quantity_button(kind: String, quantity: int) -> Button:
	for child: Node in _descendants(game.menus):
		if child is Button and child.get_meta("intent","") == "packet_quantity":
			var value: Dictionary = child.get_meta("payload",{})
			if value.get("kind") == kind and value.get("quantity") == quantity: return child
	return null

func click(intent: String, value: String = "") -> void:
	var button: Button = _button(intent,value)
	check(button != null,"Visible action exists: "+intent)
	if button == null: return
	inputs.append({"frame":movie_frames,"device":"mouse","intent":intent,"payload":value,"point":button.get_global_rect().get_center()})
	await _click(button)
	trace(intent)

func click_quantity(kind: String, quantity: int) -> void:
	var button: Button = quantity_button(kind,quantity)
	check(button != null,"Each product owns its explicit x%d quantity button" % quantity)
	if button == null: return
	inputs.append({"frame":movie_frames,"device":"mouse","kind":kind,"quantity":quantity,"point":button.get_global_rect().get_center()})
	await _click(button)
	check(game.menus.selected_shop_product() == kind and game.menus.selected_shop_quantity(kind) == quantity,"Mouse quantity owns exactly its visible product")

func key(code: Key) -> void:
	inputs.append({"frame":movie_frames,"device":"keyboard","key":code})
	await _key_tap(code)
	trace("key")

func pad(button: JoyButton) -> void:
	inputs.append({"frame":movie_frames,"device":"synthetic_pad","button":button,"layout":Bindings.layout})
	await _tap(button)
	trace("pad")

func touch(button: Button) -> void:
	check(button != null,"Explicit touch action exists")
	if button == null: return
	var point: Vector2 = button.get_global_rect().get_center()
	inputs.append({"frame":movie_frames,"device":"synthetic_screen_touch","intent":button.get_meta("intent",""),"point":point})
	for pressed: bool in [true,false]:
		var event: InputEventScreenTouch = InputEventScreenTouch.new()
		event.index = 7
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await _settle()
	trace("touch")

func trace(intent: String) -> void:
	route_trace.append({"frame":movie_frames,"intent":intent,"screen":game.screen,"menu":game.menus.screen,"selected_product":game.menus.selected_shop_product(),"standard_quantity":game.menus.selected_shop_quantity("standard"),"reclaimed_quantity":game.menus.selected_shop_quantity("reclaimed"),"wallet":game.collection.wallet()})

func card_assert(kind: String, quantity: int) -> void:
	var card: Dictionary = game.menus._shop_cards[kind]
	var currency: String = "CREDITS" if kind == "standard" else "SALVAGE"
	check(card.price.text == "%d %s" % [quantity*(48 if kind == "standard" else 36),currency],"Immediate total uses the actual owned currency")
	check(str(card.title.text).ends_with("x%d" % quantity),"Visible card title includes its own quantity")
	for button: Button in card.quantities:
		check(button.is_visible_in_tree() and str(button.get_meta("payload").kind) == kind,"Independent visible quantity controls cannot silently address another product")

func accept_and_open(kind: String, quantity: int) -> void:
	var wallet: Dictionary = game.collection.wallet()
	var unit: String = "credits" if kind == "standard" else "salvage"
	check(game.screen == "packet_purchase" and game._packet_product == kind and game._packet_quantity == quantity,"Confirmation exactly matches highlighted product and quantity")
	await picture(kind+"_confirmation")
	game._action("confirm_packet_purchase",game._packet_purchase_token+1)
	check(game.screen == "packet_purchase" and game.collection.wallet() == wallet,"Stale confirmation cannot spend or replace the visible purchase")
	await wait_frames(45)
	await click("confirm_packet_purchase")
	var receipt: Dictionary = game.collection.pending_packet()
	check(game.screen == "packet_open" and receipt.kind == kind and receipt.quantity == quantity and receipt.rows.size() == quantity*3,"Whole production batch is persisted before animation")
	check(int(game.collection.wallet()[unit]) == int(wallet[unit])-int(receipt.cost)+(int(receipt.total_salvage) if unit == "salvage" else 0),"One correct currency debit and one actual duplicate conversion")
	receipts.append(receipt.duplicate(true))
	game._action("confirm_packet_purchase",game._packet_purchase_token)
	check(game.collection.pending_packet() == receipt,"Repeated Confirm cannot charge or reroll an already opened batch")
	await click("packet_tear")
	await wait_frames(200)
	check(game.menus._packet_view.phase == "RESULT","Natural packet timers resolve authored physical opening")
	await picture(kind+"_actual_result")
	await wait_frames(75)

func shop_flow() -> void:
	phase("visible_independent_products")
	await click("open_shop")
	card_assert("standard",1)
	card_assert("reclaimed",1)
	await picture("both_cards_x1")
	await wait_frames(85)
	phase("mouse_standard_x3")
	await click_quantity("standard",3)
	card_assert("standard",3)
	card_assert("reclaimed",1)
	await picture("standard_x3_144_credits")
	await wait_frames(90)
	phase("mouse_reclaimed_x5_independent")
	await click_quantity("reclaimed",5)
	card_assert("standard",3)
	card_assert("reclaimed",5)
	await picture("reclaimed_x5_180_salvage")
	await wait_frames(90)
	var wallet: Dictionary = game.collection.wallet()
	game._action("request_packet_purchase","standard")
	check(game.screen == "shop" and game.collection.wallet() == wallet,"A stale nonhighlighted product request cannot substitute or debit")
	phase("keyboard_quantity_and_exact_buy")
	game.menus._shop_cards.standard.title.grab_focus()
	await _settle()
	await key(KEY_RIGHT)
	check(game.menus.selected_shop_quantity("standard") == 5 and game.menus.selected_shop_quantity("reclaimed") == 5,"Right changes only currently focused Standard")
	await key(KEY_LEFT)
	check(game.menus.selected_shop_quantity("standard") == 3,"Left restores Standard x3")
	_key(KEY_RIGHT,true,true)
	await _settle()
	_key(KEY_RIGHT,false)
	await _settle()
	check(game.menus.selected_shop_quantity("standard") == 3,"Keyboard echo cannot silently increase the selected quantity")
	await picture("keyboard_standard_x3")
	await wait_frames(85)
	await key(KEY_ENTER)
	await accept_and_open("standard",3)
	await click("packet_shop")
	phase("controller_glyphs_and_quantity")
	for layout: String in ["xbox","nintendo","playstation"]:
		Bindings.configure(layout)
		game.menus._shop_cards.reclaimed.title.grab_focus()
		await _settle()
		await pad(JOY_BUTTON_DPAD_LEFT)
		await pad(JOY_BUTTON_DPAD_RIGHT)
		check(game.menus.input_profile() == layout,"Actual mapped synthetic pad selects expected glyph profile")
		check(game.menus._prompt_labels.confirm.text == {"xbox":"A BUY","nintendo":"A BUY","playstation":"CROSS BUY"}[layout],"Visible buy help uses the controller's printed Confirm name")
		check(game.menus._prompt_labels.back.text == {"xbox":"B BACK","nintendo":"B BACK","playstation":"CIRCLE BACK"}[layout],"Visible Back help uses the controller's printed Back name")
		await picture("controller_"+layout)
		await wait_frames(65)
		await pad(Bindings.confirm_button(layout))
		check(game.screen == "packet_purchase" and game._packet_product == "reclaimed" and game._packet_quantity == 5,"Mapped Confirm purchases exactly visible Reclaimed x5")
		await pad(Bindings.back_button(layout))
		check(game.screen == "shop","Mapped Back cancels without spending")
	Bindings.configure("xbox")
	game.menus._shop_cards.standard.title.grab_focus()
	await _settle()
	_axis(JOY_AXIS_LEFT_X,.8)
	await _settle()
	_axis(JOY_AXIS_LEFT_X,.95)
	await _settle()
	check(game.menus.selected_shop_quantity("standard") == 5 and game.menus.selected_shop_quantity("reclaimed") == 5,"Held/jittered analogue direction advances exactly one quantity for its own card")
	_axis(JOY_AXIS_LEFT_X,0)
	await _settle()
	await pad(JOY_BUTTON_DPAD_LEFT)
	phase("explicit_touch_reclaimed_x3")
	await touch(quantity_button("reclaimed",3))
	check(game.menus.selected_shop_product() == "reclaimed" and game.menus.selected_shop_quantity("reclaimed") == 3 and game.menus.selected_shop_quantity("standard") == 3,"Touch directly addresses Reclaimed quantity without changing Standard")
	card_assert("reclaimed",3)
	game.menus._note_input_profile("touch")
	await picture("touch_reclaimed_x3")
	await wait_frames(85)
	await touch(_button("request_packet_purchase","reclaimed"))
	await accept_and_open("reclaimed",3)
	await click("packet_shop")
	check(game.collection.pending_packet().is_empty(),"Fixed paid batch is acknowledged exactly once")
	await picture("final_independent_shop")
	await wait_frames(65)

func workshop_flow() -> void:
	phase("hub_direct_workshop")
	await click("open_workshop")
	check(game.screen == "garage" and game.menus.screen == "collection_workshop","WORKSHOP directly enters collection/build/equip without a hub detour")
	check(_button("back_workshop").text == "BACK TO HUB","Hub-origin Workshop gives a truthful return label")
	await picture("workshop_owned_build")
	await wait_frames(120)
	await click("back_workshop")
	check(game.screen == "title","Workshop Back returns directly to its original hub")
	phase("shop_direct_workshop_and_equip")
	await click("open_shop")
	await click("open_workshop")
	check(game.screen == "garage" and _button("back_workshop").text == "BACK TO SHOP","Shop WORKSHOP routes directly and remembers Shop as its origin")
	await picture("shop_origin_workshop")
	await wait_frames(85)
	var old_build: Dictionary = game.collection.equipped_build()
	inputs.append({"frame":movie_frames,"device":"mouse","intent":"catalogue_tab","category":"ratchet"})
	await _click(game.menus._catalogue_tabs.ratchet)
	inputs.append({"frame":movie_frames,"device":"mouse","intent":"equip_part","category":"ratchet","id":"kickback"})
	await _click(game.menus._part_buttons.ratchet.kickback)
	check(game.collection.equipped_build().ratchet == "kickback" and game.collection.equipped_build().blade == old_build.blade,"Owned component equips through production catalogue")
	var disk = Save.new(profile_path)
	check(disk.load_save().ok and disk.equipped_build() == game.collection.equipped_build(),"Equipped assembly survives an actual disk reload")
	await picture("actually_equipped_kickback")
	await wait_frames(125)
	await click("back_workshop")
	check(game.screen == "shop","Workshop Back returns directly to Shop with no generic hub")
	await picture("returned_direct_shop")
	await wait_frames(75)
	await click("back_shop")
	check(game.screen == "title","Returning from Workshop preserves Shop's original hub escape route")
	phase("workshop_shop_back_controller")
	await click("open_workshop")
	await click("open_shop")
	check(_button("back_shop").text == "BACK TO WORKSHOP","Workshop-origin Shop has a truthful direct return")
	await key(KEY_ESCAPE)
	check(game.screen == "garage" and _button("back_workshop").text == "BACK TO HUB","Keyboard Back preserves the original Workshop origin")
	Bindings.configure("nintendo")
	await pad(Bindings.back_button("nintendo"))
	check(game.screen == "title","Printed Nintendo Back returns directly to hub")
	await touch(_button("open_workshop"))
	check(game.screen == "garage","Explicit touch WORKSHOP directly opens collection")
	await picture("touch_direct_workshop")
	await wait_frames(115)
	Bindings.configure("auto")

func recovered_reclaimed_route() -> void:
	phase("real_reclaimed_receipt_reload_and_another")
	await click("open_shop")
	await click_quantity("reclaimed",1)
	await click("request_packet_purchase","reclaimed")
	await click("confirm_packet_purchase")
	var fixed: Dictionary = game.collection.pending_packet()
	var wallet: Dictionary = game.collection.wallet()
	var owned: Array = game.collection.owned_parts()
	recovered_another = {"before_close":fixed,"wallet":wallet,"owned":owned,"save_sha256":FileAccess.get_sha256(profile_path),"reload_rng_seed":999777}
	game.queue_free()
	await process_frame
	game = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = profile_path
	game.qa_task_id = "003A.1"
	game.packet_rng_override = RandomNumberGenerator.new()
	game.packet_rng_override.seed = 999777
	root.add_child(game)
	game.set_process(false)
	game.music.configure_playback(false)
	await _settle()
	check(game.screen == "packet_open" and game.collection.pending_packet() == fixed,"Reload reads the actual exact Reclaimed receipt with unrelated RNG")
	check(game.collection.wallet() == wallet and game.collection.owned_parts() == owned,"Reload cannot debit, reroll or grant again")
	recovered_another.after_reload = game.collection.pending_packet()
	if game.menus._packet_view.phase != "RESULT": await click("packet_skip")
	await click("packet_another","reclaimed")
	check(game.screen == "packet_purchase" and game._packet_product == "reclaimed" and game.menus.selected_shop_product() == "reclaimed","Recovered Open Another explicitly selects its visible Reclaimed card before confirmation")
	check(game.collection.wallet() == wallet and game.collection.pending_packet().is_empty(),"Another opens a fresh confirmation without charging or retaining the old receipt")
	await click("cancel_packet_purchase")


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg.begins_with("--profile="): profile_path = arg.trim_prefix("--profile=")
		if arg.begins_with("--frames="): frames_path = arg.trim_prefix("--frames=")
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg == "--diagnostic": diagnostic = true
	if report_path.is_empty() or profile_path.is_empty(): quit(2); return
	root.size = Vector2i(800,480)
	root.content_scale_size = Vector2i(800,480)
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	Input.use_accumulated_input = false
	if not diagnostic: DirAccess.make_dir_recursive_absolute(frames_path)
	var fixture = Save.new(profile_path)
	check(fixture.load_save().ok and fixture.initialize_starter("breaker").ok,"Fresh isolated starter")
	var state: Dictionary = fixture._data.duplicate(true)
	state.progression.credits = 1000
	state.progression.salvage = 500
	check(fixture._commit(state,"declared_shop_wallet_fixture").ok,"Declared initial wallet fixture persists")
	if mode in ["workshop","all"]: check(fixture.grant_part("ratchet:kickback").ok,"Declared initial owned Workshop component fixture")
	game = QuietMain.new()
	game.smoke_mode = true
	game.review_audio = not diagnostic
	game.collection_path = profile_path
	game.qa_task_id = "003A.1"
	game.packet_rng_override = RandomNumberGenerator.new()
	game.packet_rng_override.seed = 19
	root.add_child(game)
	game.set_process(false)
	game.music.configure_playback(not diagnostic)
	await _settle()
	if mode in ["shop","all"]: await shop_flow()
	if mode == "all": await click("back_shop")
	if mode in ["workshop","all"]: await workshop_flow()
	if mode == "all": await recovered_reclaimed_route()
	phases[-1].to_frame = movie_frames
	var record: Dictionary = {"scope":"Actual GUI mouse/keyboard/mapped synthetic controller/screen-touch; declared initial wallet/starter/seed and Workshop-only owned component. No packet results supplied; no human hardware acceptance.","mode":mode,"diagnostic":diagnostic,"checks":checks,"failures":failures,"phases":phases,"images":screenshots,"inputs":inputs,"receipts":receipts,"route_trace":route_trace,"recovered_another":recovered_another,"profile":profile_path,"profile_sha256":FileAccess.get_sha256(profile_path),"final_wallet":game.collection.wallet(),"final_build":game.collection.equipped_build(),"movie_frames":movie_frames,"seconds":movie_frames/60.0,"sound_counts":game.sounds.played_counts.duplicate()}
	var file: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"\t"));file.close()
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
