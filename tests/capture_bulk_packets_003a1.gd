extends "res://tests/test_collection_ui.gd"
## Native production GUI clicks and ordinary packet timers. Declared isolated
## wallet/starter/seed fixtures; fixed batch results are never supplied by QA.
var manifest_path: String
var profile_path: String
var frames_path: String
var diagnostic: bool = false
var movie_frames: int = 0
var phases: Array[Dictionary] = []
var images: Dictionary = {}
var transactions: Array[Dictionary] = []
var observations: Array[Dictionary] = []
var input_events: Array[Dictionary] = []
var crash_proof: Dictionary = {}
var current_phase: String = "setup"

func _process(_dt: float) -> bool:
	movie_frames += 1
	if movie_frames % 6 == 0 and is_instance_valid(game) and game.collection != null:
		var pending: Dictionary = game.collection.pending_packet()
		observations.append({"movie_frame":movie_frames,"scene":current_phase,"screen":game.screen,"cursor":pending.get("cursor", -1),"phase":game.menus._packet_view.phase if is_instance_valid(game.menus._packet_view) else "","sounds":game.sounds.played_counts.duplicate()})
	return false

func wait_frames(count: int) -> void:
	for tick: int in range(count): await process_frame

func phase(name: String) -> void:
	if not phases.is_empty(): phases[-1].to_frame = movie_frames
	current_phase = name
	phases.append({"name":name,"from_frame":movie_frames})

func click(intent: String, payload: String = "") -> void:
	var button: Button = _button(intent, payload)
	check(button != null, "Production GUI target exists " + intent)
	if button == null: return
	input_events.append({"movie_frame":movie_frames,"type":"actual_gui_mouse_click","intent":intent,"payload":payload,"global_point":[button.get_global_rect().get_center().x,button.get_global_rect().get_center().y]})
	await _click(button)

func image(name: String) -> void:
	if diagnostic: return
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	check(pixels.get_size() == Vector2i(800,480), "Actual native root is800x480")
	var rect: Rect2i = Rect2i(Vector2i(game.menus._content.global_position), Vector2i(640,360))
	var native: Image = pixels.get_region(rect)
	var path: String = frames_path.path_join(name + ".png")
	check(native.save_png(path) == OK, "Real centred native menu screenshot saved")
	images[name] = {"path":path,"movie_frame":movie_frames,"crop":[rect.position.x,rect.position.y,640,360]}

func boot() -> void:
	game = QuietMain.new()
	game.smoke_mode = true
	game.review_audio = not diagnostic
	game.collection_path = profile_path
	game.qa_task_id = "003A.1"
	game.packet_rng_override = RandomNumberGenerator.new()
	game.packet_rng_override.seed = 19 if crash_proof.is_empty() else 999777
	root.add_child(game)
	game.set_process(false)
	game.music.configure_playback(not diagnostic)
	game.music.set_context("workshop")
	game.music.set_paused(false)
	await _settle()

func buy(quantity: int) -> void:
	await click("packet_quantity", str(quantity))
	check(game.menus.selected_shop_quantity() == quantity, "Visible quantity matches production selection")
	await image("quantity_x%d_%d" % [quantity,transactions.size()])
	await click("request_packet_purchase", "standard")
	check(game.screen == "packet_purchase" and game._packet_quantity == quantity, "Cost-confirmation screen owns requested quantity")
	_check_layout("Batch cost confirmation")
	await wait_frames(40)
	await click("confirm_packet_purchase")
	check(game.screen == "packet_open", "Whole fixed batch saved before physical presentation")
	transactions.append({"quantity":quantity,"credits_after_debit":game.collection.credits,"fixed_receipt":game.collection.pending_packet(),"save_sha256_after_grants":FileAccess.get_sha256(profile_path)})
	await wait_frames(40)
	await image("fan_x%d_%d" % [quantity,transactions.size()])

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): manifest_path = arg.trim_prefix("--manifest=")
		if arg.begins_with("--profile="): profile_path = arg.trim_prefix("--profile=")
		if arg.begins_with("--frames="): frames_path = arg.trim_prefix("--frames=")
		if arg == "--diagnostic": diagnostic = true
	if manifest_path.is_empty() or profile_path.is_empty(): quit(2); return
	root.size = Vector2i(800,480)
	root.content_scale_size = Vector2i(800,480)
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	Input.use_accumulated_input = false
	if not diagnostic: DirAccess.make_dir_recursive_absolute(frames_path)
	var fixture = preload("res://scripts/collection_save.gd").new(profile_path)
	check(fixture.load_save().ok and fixture.initialize_starter("breaker").ok, "Fresh isolated owned starter")
	var state: Dictionary = fixture._data.duplicate(true)
	state.progression.credits = 1200
	check(fixture._commit(state, "declared_capture_wallet").ok, "Explicit1200-credit QA wallet fixture persists; no part results injected")
	await boot()
	phase("x1_original_physical_packet")
	await click("open_shop")
	await buy(1)
	await click("packet_tear")
	await wait_frames(160)
	check(game.menus._packet_view.phase == "RESULT", "Original x1 physical flow completes")
	_check_layout("x1 result")
	await image("x1_result")
	await wait_frames(95)
	await click("packet_shop")
	phase("x3_fast_staggered_tears")
	await buy(3)
	await click("packet_tear")
	await wait_frames(45)
	await image("x3_partial_tear")
	await wait_frames(115)
	check(game.menus._packet_view.phase == "RESULT", "x3 completes under three seconds")
	_check_layout("x3 result")
	await image("x3_result")
	await wait_frames(110)
	await click("packet_shop")
	phase("x5_fan_and_mid_batch_close")
	await buy(5)
	await click("packet_tear")
	await wait_frames(137)
	var saved: Dictionary = game.collection.pending_packet()
	check(int(saved.cursor) >= 1 and int(saved.cursor) < 5, "Close occurs during actual incomplete batch presentation")
	crash_proof = {"before_close":saved,"credits":game.collection.credits,"salvage":game.collection.salvage,"owned":game.collection.owned_parts(),"disk_sha256":FileAccess.get_sha256(profile_path),"movie_frame":movie_frames,"reloaded_rng_seed":999777}
	await image("x5_before_close")
	game.queue_free()
	await process_frame
	await boot()
	check(game.screen == "packet_open" and game.collection.pending_packet() == saved, "Reload resumes exact same receipt and cursor with unrelated RNG seed")
	check(game.collection.credits == int(crash_proof.credits) and game.collection.salvage == int(crash_proof.salvage) and game.collection.owned_parts() == crash_proof.owned, "Reload does not reroll, charge or grant again")
	crash_proof.after_reload = game.collection.pending_packet()
	phase("x5_resume_exact_remaining_packets")
	await image("x5_recovered_cursor")
	await click("packet_tear")
	await wait_frames(180)
	check(game.menus._packet_view.phase == "RESULT", "Recovered x5 completes remaining packets")
	_check_layout("x5 result")
	await image("x5_result")
	await wait_frames(160)
	await click("packet_shop")
	phase("x5_fast_open_all_actual_mixed_results")
	await buy(5)
	await click("packet_skip")
	check(game.menus._packet_view.phase == "RESULT", "FAST OPEN ALL completes existing fixed batch immediately")
	_check_layout("Fast Open All x5 result")
	await image("x5_fast_open_all_result")
	await wait_frames(220)
	phases[-1].to_frame = movie_frames
	var report: Dictionary = {"task":"003A.1","mode":"bulk_packet_opening","checks":checks,"failures":failures,"native_root":[800,480],"native_menu":[640,360],"nominal_seconds":float(movie_frames)/60,"movie_frames":movie_frames,"phases":phases,"images":images,"transactions":transactions,"mid_batch_close_reload":crash_proof,"observations":observations,"input_events":input_events,"final_wallet":game.collection.wallet(),"final_owned":game.collection.owned_parts(),"sound_counts":game.sounds.played_counts.duplicate(),"profile":profile_path,"diagnostic":diagnostic,"fixture_disclosure":"Fresh1200-credit wallet/starter/seed fixture; production GUI mouse dispatch, transaction/RNG, actual art/timers/SFX. Mid-batch object close/reload reads real disk; automated GUI is not human/physical controller acceptance."}
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
