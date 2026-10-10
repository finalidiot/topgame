extends SceneTree
## Natural early Run. The bot only sends mapped buttons and selects earned cards.
class Game extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
const Battle = preload("res://scripts/battle.gd")
const Bot = preload("res://tests/rpm_bot.gd")
var output: String = ""
var collection_prefix: String = ""
var frame_directory: String = ""
var diagnostic: bool = false
var rows: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var summaries: Array[Dictionary] = []
var movie_frames: int = 0
var mapped_events: int = 0
var captions: Label

func _initialize() -> void: call_deferred("run")
func choose(game: Game, drafts: Array[Dictionary]) -> void:
	var preferences: Array[String] = ["redline","high_gear","impact_wake","iron_comet","clutch","chain_impact","crosscut"]
	var choice: String = str(game.run_context.pending_offer[0])
	var score: float = -INF
	for offered: String in game.run_context.pending_offer:
		var preference: int = preferences.find(offered)
		var candidate: float = 16.0 - preference if preference >= 0 else 0.0
		var owned: int = int(game.run_context.power_ranks.get(offered,0))
		if owned > 0 and preference >= 0: candidate += 8.0 + owned * 2.0
		if candidate > score: choice = offered; score = candidate
	drafts.append({"time":game.battle.elapsed,"choice":choice,"offer":game.run_context.pending_offer.duplicate()})
	game._action("choose_power",{"encounter_id":game.run_context.pending_draft_id,"power_id":choice,"run_seed":game.run_context.run_seed,"offer_revision":game.run_context.reroll_snapshot().revision})
	if game.screen == "mutation": game._action("choose_mutation",{"encounter_id":game.run_context.pending_draft_id,"branch_id":game.run_context.pending_mutation_offer[0],"run_seed":game.run_context.run_seed})
	game._process(1.1)
	game.battle.set_physics_process(false)

func mapped(direction: Vector2, burst: bool, brake: bool) -> void:
	var magnitude: float = clampf(direction.length(),0.0,1.0)
	var raw: Vector2 = direction.normalized()*(0.22+0.78*magnitude) if magnitude > 0.0 else Vector2.ZERO
	for axis: int in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
		var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
		event.device = 29; event.axis = axis; event.axis_value = raw.x if axis == JOY_AXIS_LEFT_X else raw.y
		Input.parse_input_event(event); mapped_events += 1
	for value: Array in [[JOY_BUTTON_A,burst],[JOY_BUTTON_LEFT_SHOULDER,brake]]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 29; event.button_index = int(value[0]); event.pressed = bool(value[1])
		Input.parse_input_event(event); mapped_events += 1
	Input.flush_buffered_events()

func film(seed_value: int, duration: float, title: String) -> void:
	var game: Game = Game.new()
	game.smoke_mode = true; game.review_audio = not diagnostic; game.qa_task_id = "003A.1"
	game.collection_path = collection_prefix+"_"+str(seed_value)+".json"
	assert(not FileAccess.file_exists(game.collection_path))
	root.add_child(game); game.set_process(false)
	game.music.configure_playback(not diagnostic)
	game.run_context.start({"blade":"smash","ratchet":"high","bit":"flat"},seed_value,"breaker")
	game.mode = "run"; game._show_reward()
	var drafts: Array[Dictionary] = []
	choose(game,drafts)
	var b: Node2D = game.battle; b.set_physics_process(false)
	b.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		if int(event.first_entity_id)==1 or int(event.second_entity_id)==1:
			contacts.append({"seed":seed_value,"frame":movie_frames,"time":b.elapsed,"severity":event.severity}))
	var first: int = movie_frames
	var tick: int = 0
	var c: Dictionary = {"direction":Vector2.ZERO,"burst":false,"brake":false}
	while game.screen != "result" and b.elapsed < duration and tick < int(duration*120)+600:
		var burst: bool = false
		if tick%12==0:
			c = Bot.input(b,"aggressive",tick)
			burst = c.burst
		mapped(c.direction,burst,c.brake)
		b._physics_process(Battle.FIXED_DT)
		if game.screen=="level_up": game._process(.2)
		while game.screen=="reward": choose(game,drafts)
		if game.screen=="acquisition": game._process(.1)
		game.reroll_pickups.update_simulation()
		captions.text = title
		b._emit_hud(); b.queue_redraw(); game.top_status_bars.queue_redraw()
		if tick%12==0:
			rows.append({"seed":seed_value,"frame":movie_frames,"time":b.elapsed,"rpm":b.player_entity().rpm,"radius":Vector2(b.player_entity().pos).length(),"speed":Vector2(b.player_entity().vel).length(),"losses":b.continuous.economy.losses.duplicate(),"gains":b.continuous.economy.gains.duplicate(),"burst":burst,"brake":c.brake})
		if not diagnostic:
			await process_frame
			if tick%600==0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(frame_directory.path_join("breaker_%d_%06d.png"%[seed_value,movie_frames]))
		movie_frames+=1; tick+=1
	var ended: bool = game.screen=="result"
	if ended:
		captions.text = "NATURAL SELF RING-OUT / SAME SPEED + BURST"
		for hold: int in range(90):
			if not diagnostic: await process_frame
			movie_frames+=1
	summaries.append({"seed":seed_value,"frames":[first,movie_frames],"seconds":b.elapsed,"natural_end":ended,"result":b.last_result.duplicate(),"economy":b.continuous.economy.snapshot(),"drafts":drafts})
	mapped(Vector2.ZERO,false,false)
	game.music.configure_playback(false); game.free()
	if not diagnostic: await process_frame

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--collection-prefix="): collection_prefix=arg.trim_prefix("--collection-prefix=")
		if arg.begins_with("--frames="): frame_directory=arg.trim_prefix("--frames=")
		if arg=="--diagnostic": diagnostic=true
	assert(output.is_absolute_path() and collection_prefix.is_absolute_path() and not FileAccess.file_exists(output))
	root.size=Vector2i(640,360);root.content_scale_size=Vector2i(640,360)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_directory.is_empty():DirAccess.make_dir_recursive_absolute(frame_directory)
	var layer: CanvasLayer = CanvasLayer.new();layer.layer=30;root.add_child(layer)
	captions=Label.new();captions.position=Vector2(12,281);captions.size=Vector2(520,12)
	captions.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"));captions.add_theme_font_size_override("font_size",9)
	captions.add_theme_color_override("font_color",Color("e4ebd6"));layer.add_child(captions)
	await film(2026,42.0,"BREAKER / REPEATED BURST / SPEND + EARN SPIN")
	await film(7341,20.0,"BREAKER / COMMITMENT STILL RISKS THE RING")
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema":"003a1-breaker-rpm-risk-v1","scope":"Normal production Main, natural opening Runs/earned drafts, legal sampled mapped joystick/button input; no forced collision, reserve or outcome. Editorial cuts are between separate disclosed seeds. Native production HUD/status bars; small QA caption only.","native_view":[640,360],"fps":60,"movie_frames":movie_frames,"nominal_seconds":float(movie_frames)/60.0,"mapped_events":mapped_events,"rows":rows,"contacts":contacts,"cases":summaries},"\t"));file.close()
	layer.free()
	print("BREAKER_RPM_RISK_CAPTURE_PASS frames=",movie_frames," contacts=",contacts.size())
	quit()
