extends SceneTree
## Production UI rendered at native scale with explicit isolated flow fixtures.
## Saved starter/payout/packet operations are real APIs; funding is a labelled
## fixture and makes no earned-gameplay or survival claim.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
var game: QuietMain
var output: String = ""
var frames: String = ""
var collection_path: String = ""
var images: Dictionary = {}
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func image(name: String) -> void:
	game.battle.set_physics_process(false)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var im: Image = root.get_texture().get_image()
	if im.get_size()!=Vector2i(640,360):failures.append("Capture is not native640x360 "+name)
	var path: String = frames.path_join(name+".png")
	if im.save_png(path)!=OK:failures.append("Cannot write native screenshot "+name)
	images[name]={"path":path,"screen":game.screen,"viewport":[640,360],"collection_credits":game.collection.credits,"collection_owned":game.collection.owned_count()}
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="):frames=arg.trim_prefix("--frames=")
		if arg.begins_with("--collection="):collection_path=arg.trim_prefix("--collection=")
	if output.is_empty() or frames.is_empty() or collection_path.is_empty():push_error("External manifest/frames/collection required");quit(2);return
	root.size=Vector2i(640,360);root.content_scale_size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	DirAccess.make_dir_recursive_absolute(frames)
	game=QuietMain.new();game.smoke_mode=true;game.collection_path=collection_path;game.qa_task_id="003A";root.add_child(game);game.set_process(false)
	game.battle.set_physics_process(false)
	game._title_gate();await image("title")
	game._title();await image("fresh_hub")
	game._action("begin_collection");await create_timer(1.1).timeout;await image("starter_selection")
	game._action("select_first_starter","breaker");await image("make_it_yours")
	game._action("confirm_first_starter","breaker");game._process(1.6);await image("workshop")
	game._title();await image("main_hub")
	game._action("start_run");await image("power_draft")
	# Structured new-family rank-II reading uses the same production controls.
	game.menus.show_reward(["gyro_lock","impact_sink","anchor_exchange"],[],1,"qa/defence-reading",421,"",{"power_ranks":{"gyro_lock":2,"impact_sink":2,"anchor_exchange":2},"title":"DEFENSIVE INVESTMENT","subtitle":"Explicit UI inspection fixture / owned Rank II","resume_label":"RETURN TO COMBAT"})
	await image("ability_inspection")
	for family: String in ["gyro_lock","impact_sink","anchor_exchange"]:
		game.menus.show_mutation(family,preload("res://scripts/run_powers.gd").mutation_choices(family),"qa/defence-reading",421)
		await image("mutation_"+family)
	game._clear_run();game._hide_battle()
	var nonce: Dictionary=game.collection.begin_reward_run()
	var payout: Dictionary=game.collection.pay_run_reward(str(nonce.run_id),{"reward_provenance":"earned-clear-v1","reward_fixture":false,"aborted":false,"earned_threats_cleared":4,"earned_elites_cleared":0,"earned_bosses_cleared":0})
	if not bool(payout.ok) or game.collection.credits!=48:failures.append("Isolated saved funding fixture failed")
	game.screen="result";game.last_result={"is_run":true,"continuous_run":true,"build":game.collection.equipped_build(),"starter_id":"breaker","credits_earned":48,"wallet_credits":48,"survival_time":244.0,"threats_cleared":4,"level":7,"run_seed":421,"rivals_defeated":6,"small_enemies_defeated":12,"owned_power_ids":["dead_centre","gyro_lock","impact_sink","anchor_exchange"],"power_ranks":{"dead_centre":3,"gyro_lock":2,"impact_sink":2,"anchor_exchange":2},"power_mutations":{"dead_centre":"bulwark"}}
	game.menus.show_result(game.last_result);await create_timer(1.05).timeout;await image("results")
	game._action("open_shop");await create_timer(0.35).timeout;await image("shop")
	game.packet_rng_override=RandomNumberGenerator.new();game.packet_rng_override.seed=19
	game._action("request_packet_purchase","standard");await image("purchase_confirmation")
	game._action("confirm_packet_purchase",game._packet_purchase_token)
	await create_timer(0.25).timeout
	game._action("packet_tear");await create_timer(2.65).timeout;await image("packet_final_result")
	if not is_instance_valid(game.menus._packet_view) or game.menus._packet_view.phase!="RESULT":failures.append("Packet final did not reach settled inspection")
	game._action("packet_workshop");game._action("settings");await image("reduced_flashing_option")
	var report: Dictionary={"images":images,"failures":failures,"native_view":[640,360],"collection":collection_path,"collection_sha256":FileAccess.get_sha256(collection_path),"profile_writes":false,"scope":"Production Windows menus and art, native640x360, explicit isolated flow fixtures. Starter ownership, saved payout transaction and seeded packet receipt/opening use actual APIs. Four-clear funding and displayed owned defence ranks are labelled UI fixtures, not earned gameplay/AI/survival evidence. Android cell must be supplied from the final real-phone capture separately."}
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("FINAL_UI_CAPTURE_%s images=%d" % ["PASS" if failures.is_empty() else "FAIL",images.size()]);game.free();quit(0 if failures.is_empty() else 1)
