extends SceneTree
## Windows/headless simulation of the real Android shell. No phone claim.
## Every screen uses isolated Main; physical dimensions/cutouts, a starting
## wallet and legal invested Duel ownership are explicitly declared fixtures.
const Shell = preload("res://scripts/mobile_shell.gd")
const Physics = preload("res://scripts/battle.gd")
const Save = preload("res://scripts/collection_save.gd")
const Economy = preload("res://scripts/packet_economy.gd")
const Starters = preload("res://scripts/starters.gd")
const Powers = preload("res://scripts/run_powers.gd")
class IsolatedShell extends "res://scripts/mobile_shell.gd":
	func _ready() -> void: pass
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass

const CASES: Array[Dictionary] = [
	{"name":"1280x720", "size":Vector2i(1280,720), "safe":Rect2i(0,0,1280,720)},
	{"name":"2160x1080", "size":Vector2i(2160,1080), "safe":Rect2i(0,0,2160,1080)},
	{"name":"2340x1080", "size":Vector2i(2340,1080), "safe":Rect2i(0,0,2340,1080)},
	{"name":"2400x1080", "size":Vector2i(2400,1080), "safe":Rect2i(0,0,2400,1080)},
	{"name":"2340x1080_cutout", "size":Vector2i(2340,1080), "safe":Rect2i(84,24,2208,1032)}]
var report: String = ""
var prefix: String = ""
var frames: String = ""
var native: bool = false
var movie: bool = false
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var events: Array[Dictionary] = []
var images: Array[Dictionary] = []
var replays: Array[Dictionary] = []
var movie_phases: Array[Dictionary] = []
var movie_frames: int = 0
var baseline_trace: Array[String] = []
var shell: IsolatedShell
var game: QuietMain
var current_case: Dictionary = {}
var seen_progression: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		if not message in failures: failures.append(message)
		push_error(message)
func portable(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Rect2 or value is Rect2i: return [value.position.x,value.position.y,value.size.x,value.size.y]
	if value is Color: return [value.r,value.g,value.b,value.a]
	if value is Array or value is PackedVector2Array:
		var array: Array = []
		for item: Variant in value: array.append(portable(item))
		return array
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys(); keys.sort_custom(func(a: Variant,b: Variant)->bool:return str(a)<str(b))
		for key: Variant in keys: result[str(key)] = portable(value[key])
		return result
	return value
func digest(value: Variant) -> String: return JSON.stringify(portable(value)).sha256_text()
func settle(count: int = 3) -> void:
	for tick: int in range(count):
		await process_frame
		if movie: movie_frames += 1
func valid_paths() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
		if arg.begins_with("--profile-prefix="): prefix = arg.trim_prefix("--profile-prefix=")
		if arg.begins_with("--frames="): frames = arg.trim_prefix("--frames=")
		if arg == "--native": native = true
		if arg == "--movie": movie = true; native = true
		if arg.begins_with("--collection-path=") or arg in ["--smoke-test","--qa-catalogue","--reset-collection"]:
			push_error("Main boot overrides refused before making a fixture"); return false
	var qa: String = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA/003A.2")
	if not OS.get_environment("TOPGAME_QA_ROOT").is_empty(): qa = OS.get_environment("TOPGAME_QA_ROOT").path_join("003A.2")
	var stamp: String = "%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	if report.is_empty(): report = qa.path_join("manifests/android_fullscreen_layout_"+stamp+"_runtime.json")
	if prefix.is_empty(): prefix = qa.path_join("temp/android_fullscreen_layout_"+stamp+"_collection")
	for item: Array in [[report,"manifests"],[prefix,"temp"]]:
		var path: String = str(item[0]).replace("\\","/").simplify_path()
		var boundary: String = qa.replace("\\","/").simplify_path().path_join(str(item[1])).to_lower()+"/"
		if not path.is_absolute_path() or not path.to_lower().begins_with(boundary) or FileAccess.file_exists(path):
			push_error("Fresh external QA paths required: "+path); return false
	if native:
		if DisplayServer.get_name() == "headless": push_error("Native evidence requires an actual renderer"); return false
		if frames.is_empty(): frames = qa.path_join("frames/android_fullscreen_layout_"+stamp)
		if not frames.is_absolute_path() or not frames.replace("\\","/").to_lower().begins_with(qa.replace("\\","/").to_lower()+"/frames/") or DirAccess.dir_exists_absolute(frames):
			push_error("Fresh external frame directory required"); return false
		DirAccess.make_dir_recursive_absolute(frames)
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	return true
func descendants(node: Node) -> Array:
	var result: Array = []
	for child: Node in node.get_children():
		result.append(child); result.append_array(descendants(child))
	return result
func button(intent: String, payload: Variant = null) -> Button:
	for node: Node in descendants(game.menus):
		if node is Button and node.is_visible_in_tree() and not node.disabled and str(node.get_meta("intent","")) == intent:
			if payload == null or node.get_meta("payload",null) == payload: return node
	return null
func physical_rect(area: Rect2) -> Rect2: return shell.surface.get_global_transform_with_canvas() * area
func tap(intent: String, payload: Variant = null) -> void:
	var target: Button = button(intent,payload)
	check(is_instance_valid(target), "Actual touch target exists: "+intent+" / "+str(payload))
	if not is_instance_valid(target): return
	var point: Vector2 = shell.surface.get_global_transform_with_canvas()*target.get_global_rect().get_center()
	check(Rect2(current_case.safe).has_point(point),"Actual touch target lies inside physical safe area: "+intent)
	var action_start: int = game.audit_actions.size()
	for pressed: bool in [true,false]:
		var event := InputEventScreenTouch.new(); event.index = 7; event.position = point; event.pressed = pressed
		events.append({"case":current_case.name,"screen":game.screen,"intent":intent,"payload":payload,"point":point,"pressed":pressed})
		Input.parse_input_event(event); await settle()
		events.append({"type":"tap_action_trace","case":current_case.name,"intent":intent,"pressed":pressed,"screen_after":game.screen,
			"new_actions":game.audit_actions.slice(action_start),"power_ranks":game.run_context.power_ranks.duplicate(true),"power_mutations":game.run_context.power_mutations.duplicate(true)})
	game.battle.set_physics_process(false)
func screenshot(label: String) -> void:
	if not native: return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.get_size() == current_case.size,"Actual root screenshot has declared physical surface dimensions")
	var path: String = frames.path_join(str(current_case.name)+"_"+label+".png")
	check(not FileAccess.file_exists(path) and image.save_png(path)==OK,"Fresh native fullscreen screenshot: "+label)
	images.append({"case":current_case.name,"screen":label,"path":path,"sha256":FileAccess.get_sha256(path),"physical_size":image.get_size(),"layout":shell.layout_snapshot(),"menu_rect":physical_rect(game.menus._content.get_global_rect())})
func audit_screen(label: String, expected: String = "") -> void:
	await settle(4); game._process(0.0); game.battle.set_physics_process(false)
	check(expected.is_empty() or game.screen == expected,"Actual Main screen for "+label+": "+game.screen)
	var safe: Rect2 = Rect2(current_case.safe)
	var controls: Array[Dictionary] = []
	for node: Node in descendants(game.menus):
		if node is Button and node.is_visible_in_tree():
			var area: Rect2 = physical_rect(node.get_global_rect())
			check(safe.grow(.1).encloses(area),"Physical safe area contains complete interactive control: "+label+" / "+node.name)
			controls.append({"name":node.name,"text":node.text,"intent":node.get_meta("intent",""),"rect":area,"disabled":node.disabled})
	var layout: Dictionary = shell.layout_snapshot()
	check(float(layout.get("unused_physical_area",-1.0))==0.0,"Layout reports zero unused physical letterbox area")
	check(layout.get("physical_safe_area",Rect2i())==current_case.safe,"Actual shell retains the declared physical safe inset")
	check(game.combat_viewport.size == Vector2i(640,360),"Canonical Battle viewport remains640×360 on "+label)
	check(shell.surface.position == Vector2.ZERO,"Fullscreen surface starts at physical origin")
	check(is_equal_approx(shell.surface.scale.x,shell.surface.scale.y),"Fullscreen surface uses one uniform scale")
	var span: Rect2 = shell.surface.get_global_rect()
	check(span.position == Vector2.ZERO and span.end.x >= current_case.size.x and span.end.y >= current_case.size.y,"Fullscreen surface covers the physical display without inner letterboxing")
	check(span.end.x-current_case.size.x < shell.surface.scale.x+0.1 and span.end.y-current_case.size.y < shell.surface.scale.y+0.1,"Ceil EXPAND has less than one logical pixel of clipped overscan")
	if label == "battle":
		var arena: Rect2 = physical_rect(game.combat_frame.get_global_rect())
		check(is_equal_approx(arena.size.x/arena.size.y,640.0/360.0),"Battle presentation remains uniformly scaled16:9")
		check(safe.grow(.1).encloses(arena),"The complete battle raster remains cutout-safe")
		check(game.combat_frame.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"Battle projection retains nearest-neighbour filtering")
		var hud: Dictionary = game.menus.combat_layout_snapshot()
		var hud_physical: Dictionary = {}
		for key: String in hud.get("regions",{}):
			var region: Rect2 = physical_rect(hud.regions[key])
			check(safe.grow(.1).encloses(region),"Complete HUD region remains physically safe: "+key+" / "+str(current_case.name))
			hud_physical[key] = region
		var touch: Dictionary = game.touch_controls.layout_snapshot()
		var actions: Dictionary = {}
		for key: String in ["steering_rect","burst_rect","brake_rect"]:
			var area: Rect2 = physical_rect(touch[key])
			actions[key] = area
			check(safe.grow(.1).encloses(area),"Actual touch provider region remains physically safe: "+key)
		check(not Rect2(actions.burst_rect).intersects(arena) and not Rect2(actions.brake_rect).intersects(arena),"Actual action rails stay outside the visible combat raster")
		check(not Rect2(actions.burst_rect).intersects(Rect2(actions.brake_rect)),"Actual Burst and Brake regions remain distinct")
		observations.append({"case":current_case.name,"screen":label,"layout":layout,"hud":hud,"hud_physical_regions":hud_physical,
			"arena_physical":arena,"touch_provider_layout":touch,"touch_physical_regions":actions,"controls":controls,
			"actual_surface_physical":span,"actual_physical_coverage":Rect2(Vector2.ZERO,Vector2(current_case.size)).intersection(span).get_area(),
			"actual_unused_physical_area":float(current_case.size.x*current_case.size.y)-Rect2(Vector2.ZERO,Vector2(current_case.size)).intersection(span).get_area()})
	else: observations.append({"case":current_case.name,"screen":label,"layout":layout,"controls":controls,"menu_physical":physical_rect(game.menus._content.get_global_rect())})
	await screenshot(label)
	if movie:
		movie_phases.append({"screen":label,"start_frame":movie_frames,"case":current_case.name})
		for tick: int in range(75):
			game._process(Physics.FIXED_DT); game.battle.set_physics_process(false)
			if label == "battle" and game.screen == "battle": game.battle.test_step(Physics.FIXED_DT,Vector2(.3,.1),tick==35,false)
			game.battle.queue_redraw(); await settle(1)
		movie_phases[-1]["end_frame"] = movie_frames
func new_case(row: Dictionary) -> void:
	current_case = row
	root.size = row.size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_factor = 1.0
	await settle(4)
	check(root.size == row.size,"Actual QA physical viewport is "+str(row.size))
	var path: String = prefix+"_"+str(row.name)+".json"
	for suffix: String in ["",".bak",".tmp",".preferences.cfg"]:
		check(not FileAccess.file_exists(path+suffix),"Fresh isolated collection: "+path+suffix)
	game = QuietMain.new(); game.smoke_mode = true; game.qa_task_id = "003A.2"; game.collection_path = path
	game.settings.muted = true; game.settings.screen_shake = false
	shell = IsolatedShell.new(); root.add_child(shell)
	shell.mount_mobile_surface(game)
	# The cutout is an explicit simulated physical inset. Windows OS polling
	# would replace it with that host's ordinary full-client safe area.
	shell.set_process(false)
	shell.apply_display_layout(row.size,row.safe)
	game.set_process(false); game.battle.set_physics_process(false)
	await settle(5); game._process(0.0)
	if native: DisplayServer.window_set_title("Spinning Metal — ANDROID FULLSCREEN ISOLATED WINDOWS QA / "+str(row.name))
	check(game.collection.save_path == path,"Actual mounted Main opens only its isolated save")
	check(game.get_viewport() == shell.game_view,"Actual Main is hosted by the production mobile viewport")
	check(shell.game_view.size != Vector2i(800,480),"Wide mobile canvas is not the old fixed800×480 letterbox")
	game.battle.progression_events.connect(func(rows: Array)->void:seen_progression.append_array(rows.duplicate(true)))
func draft_fixture() -> void:
	# An explicitly legal pending RankIII choice isolates the same actual
	# RunContext/Main handlers; natural XP acquisition is not being claimed.
	game._clear_run(); game.run_context.start(game.collection.equipped_build(),421,"vane")
	game.run_context._owned_power_ids.assign(["orbit_drive","afterimage","momentum_bank"])
	game.run_context._power_ranks = {"orbit_drive":2,"afterimage":1,"momentum_bank":1}
	game.run_context._pending_offer.assign(["orbit_drive","afterimage","momentum_bank"])
	game.run_context._draft_queue.assign([{"id":"draft/fullscreen_fixture","kind":"level","level":5}])
	game._draft_resume_origin = "starting"; game.mode = "run"; game._show_reward()
	await audit_screen("ability_draft","reward")
	var choice: Button = button("choose_power")
	for node: Node in descendants(game.menus):
		if node is Button and node.get_meta("power_id","") == "orbit_drive": choice = node; break
	check(is_instance_valid(choice),"Real RankIII eligible card exists")
	if is_instance_valid(choice): await tap("choose_power",choice.get_meta("payload"))
	await audit_screen("mutation_draft","mutation")
	check(game.run_context.pending_mutation_offer == Powers.mutation_choices("orbit_drive"),"Both actual legal siblings are visible")
	check(int(game.run_context.power_ranks.get("orbit_drive",0))==2 and game.run_context.power_mutations.is_empty(),"Upgrade contact and release cannot preselect either mutation")
	var mutate: Button = button("choose_mutation")
	if is_instance_valid(mutate): await tap("choose_mutation",mutate.get_meta("payload"))
	await audit_screen("acquisition","acquisition")
	check(int(game.run_context.power_ranks.get("orbit_drive",0))==3,"One actual RankIII claim persists in the temporary Run")
	game._clear_run(); game._title()
func navigation() -> void:
	game._title_gate(); await audit_screen("title","title_gate")
	await tap("enter_frontend"); await audit_screen("uninitialized_hub","title")
	await tap("begin_collection"); await audit_screen("starter","starter_ceremony")
	await tap("select_first_starter","vane"); await audit_screen("starter_confirmation","starter_confirm")
	await tap("confirm_first_starter","vane"); await audit_screen("starter_owned","starter_owned")
	# Honour the authored minimum ownership beat. A stopped QA Main does not
	# automatically advance that timer between mapped taps.
	while game.screen == "starter_owned" and game._ownership_remaining > 0.6:
		game._process(Physics.FIXED_DT); await settle(1)
	if game.screen == "starter_owned": await tap("finish_ownership")
	await audit_screen("workshop","garage")
	await tap("back_workshop"); await audit_screen("hub","title")
	await tap("settings"); await audit_screen("settings","settings")
	await tap("back_settings")
	var data: Dictionary = game.collection._data.duplicate(true); data.progression.credits = 10000
	check(game.collection._commit(data,"qa_fullscreen_initial_wallet").ok,"Declared isolated wallet fixture is persisted")
	await tap("open_shop"); await audit_screen("shop","shop")
	var buy: Button = button("request_packet_purchase","standard")
	check(is_instance_valid(buy),"Actual Standard packet BUY is available")
	if is_instance_valid(buy): await tap("request_packet_purchase","standard")
	await audit_screen("packet_purchase","packet_purchase")
	var confirm: Button = button("confirm_packet_purchase")
	if is_instance_valid(confirm): await tap("confirm_packet_purchase",confirm.get_meta("payload"))
	await audit_screen("packet_open","packet_open")
	await tap("packet_tear")
	if is_instance_valid(game.menus._packet_view):
		# Presentation clock fixture only. Complete precommitted packet results
		# and the debit/grants remain real durable production transactions.
		game.menus._packet_view._process(8.0)
	await audit_screen("packet_result","packet_open")
	if not is_instance_valid(game.menus._packet_view): check(false,"Actual packet view exists before result audit"); return
	check(game.menus._packet_view.phase=="RESULT","Real packet reaches its valid result")
	await tap("packet_shop"); check(game.collection.pending_packet().is_empty(),"Actual result acknowledgement retires the paid batch")
	await tap("back_shop")
	await draft_fixture()

func state(b: Node2D) -> Dictionary:
	var entities: Array[Dictionary] = []
	for actor: Dictionary in b.fighters:
		var row: Dictionary = {}
		for key: String in ["entity_id","owner_id","team_id","combatant_type","build","pos","vel","rpm","cooldown","burst_time","alive","outcome","powers","power_ranks","power_mutations","orbit_charge","orbit_flow","momentum_charge","ecology_commit_time","ecology_heading","reactive_force","reactive_time","damper_time","comet_time","ricochet_count","pilot"]:
			row[key] = actor.get(key,null)
		entities.append(row)
	var ai_rng: Dictionary = {}
	for id: Variant in b._ai_rngs: ai_rng[str(id)] = str(b._ai_rngs[id].state)
	return {"entities":entities,"elapsed":b.elapsed,"status":b.battle_status,"paused":b.paused,"hits":b.hits,"result":b.last_result,
		"simulation_rng":str(b._simulation_rng.state),"ai_rng":ai_rng,"pair_cooldowns":b._pair_cooldowns,"hit_stop":b._hit_stop,
		"powers":{"time":b.powers.time,"states":b.powers._states,"events":b.powers.events,"counters":b.powers.counters,"traces":b.powers.traces},
		"roster":{"time":b.roster.time,"states":b.roster.states,"counters":b.roster.counters},
		"ecology":{"time":b.roster.ecology.time,"states":b.roster.ecology.states,"counters":b.roster.ecology.counters},
		"defence":{"time":b.powers.defence.time,"states":b.powers.defence.states,"counters":b.powers.defence.counters},"progression":seen_progression}
func battle_replay() -> void:
	seen_progression.clear()
	game._clear_run(); game.mode = "duel"; game.screen = "battle"; game.battle.visible = true; game.combat_frame.visible = true
	var descriptor: Dictionary = {"opponent_build":Starters.build_for("bastion"),"difficulty":3,"seed":421,"live_time_limit":60.0,
		"player_power_ids":["iron_comet","orbit_drive","momentum_bank","afterimage","chain_impact","impact_sink"],
		"player_power_ranks":{"iron_comet":3,"orbit_drive":3,"momentum_bank":3,"afterimage":3,"chain_impact":2,"impact_sink":2},
		"player_power_mutations":{"iron_comet":"wallbreaker","orbit_drive":"centrifuge","momentum_bank":"flywheel_release","afterimage":"ghost_circuit"},
		"opponent_power_ids":["crash_guard","orbit_drive","redline"],"opponent_power_ranks":{"crash_guard":3,"orbit_drive":3,"redline":2},
		"opponent_power_mutations":{"crash_guard":"reactive_plating","orbit_drive":"perpetual_orbit"}}
	game.battle.begin_encounter(Starters.build_for("vane"),descriptor); game.battle.set_physics_process(false)
	var ticks: Array[String] = []; var samples: Array[Dictionary] = []; var inputs: Array[Dictionary] = []
	for tick: int in range(1200):
		var direction: Vector2 = Vector2.ZERO
		if game.battle.battle_status == "battle":
			var offset: Vector2 = Vector2(game.battle.entity(2).pos)-Vector2(game.battle.player_entity().pos)
			direction = Vector2(offset.x-offset.y,(offset.x+offset.y)*.5).normalized()*.82
		var burst: bool = tick%180==35; var brake: bool = tick%180>=125 and tick%180<140
		game.battle.test_step(Physics.FIXED_DT,direction,burst,brake)
		var snapshot: Dictionary = state(game.battle); var hash: String = digest(snapshot)
		ticks.append(hash); inputs.append({"direction":direction,"burst":burst,"brake":brake})
		if tick%30==0 or tick==1199: samples.append({"tick":tick,"sha256":hash,"state":snapshot.duplicate(true)})
		if not baseline_trace.is_empty(): check(hash==baseline_trace[tick],"Exact cross-aspect physical tick "+str(tick)+" / "+str(current_case.name))
		# Native presentation samples at a fixed tick cadence; the solver receives
		# exactly the same explicit controls regardless of render/window geometry.
		if native and not movie and tick%30==0:
			game.battle.queue_redraw(); await settle(1)
	if baseline_trace.is_empty(): baseline_trace.assign(ticks)
	check(game.battle.hits>0,"Real cross-aspect fixture produces opposing collisions")
	check(not game.battle.powers.events.is_empty(),"Real cross-aspect fixture exercises power events")
	replays.append({"case":current_case.name,"seed":421,"fixed_dt":Physics.FIXED_DT,"ticks":1200,"descriptor":descriptor,"tick_sha256":ticks,
		"input_sha256":digest(inputs),"samples":samples,"hits":game.battle.hits,"power_events":game.battle.powers.events.duplicate(true),"final":state(game.battle).duplicate(true),
		"exact_vs_first":ticks==baseline_trace,"physics_viewport":game.combat_viewport.size})
	# Begin a fresh genuine Duel for the visual battle/pause/result audit. This
	# presentation sequence never substitutes a forced result for the replay.
	game.opponent_build = Starters.build_for("bastion"); game._start_battle("duel",false,true); game.battle.set_physics_process(false)
	while game.battle.battle_status != "battle": game.battle.test_step(Physics.FIXED_DT)
	for tick: int in range(12): game.battle.test_step(Physics.FIXED_DT,Vector2(.4,0),false,false)
	game.battle._emit_hud(); game._process(0.0)
	await audit_screen("battle","battle")
	game._pause(); await audit_screen("pause","pause")
	await tap("resume")
	for tick: int in range(3800):
		if game.screen == "result": break
		game.battle.test_step(Physics.FIXED_DT,Vector2.ZERO,false,false)
	check(game.screen=="result" and game.battle.battle_status=="finished","Result audit comes from an actual solver conclusion")
	await audit_screen("result","result")

func run() -> void:
	if not valid_paths(): quit(2); return
	Input.use_accumulated_input = false
	root.min_size = Vector2i(160,96)
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var selected: Array[Dictionary] = []
	if movie:
		selected.append(CASES[2])
	else:
		selected.assign(CASES)
	for row: Dictionary in selected:
		await new_case(row); await navigation(); await battle_replay()
		shell.free(); await settle(3)
	for replay: Dictionary in replays:
		for sample: Dictionary in replay.samples:
			check(digest(sample.state)==sample.sha256,"Persisted immutable tick sample matches its captured hash")
		check(digest(replay.final)==replay.tick_sha256[-1],"Persisted final state matches the last exact physical tick")
	var data: Dictionary = {"schema":"android-fullscreen-layout-003a2-v1","checks":checks,"failures":failures,"renderer":DisplayServer.get_name(),
		"native":native,"movie":movie,"movie_frames":movie_frames,"movie_phases":movie_phases,"cases":selected,"observations":observations,
		"input_events":events,"images":images,"cross_aspect_replays":replays,"all_physics_exact":replays.all(func(row:Dictionary)->bool:return bool(row.exact_vs_first)),
		"profile_prefix":prefix,"physical_android_acceptance":false,"direct_touch_router_calls":0,
		"scope":"Actual production MobileShell and Main at declared physical display/cutout dimensions on Windows/headless. Fresh isolated saves only. Actual mapped root ScreenTouch menu navigation; declared initial wallet, legal pending draft and invested Duel fixture. Packet timeline acceleration is presentation-only. Same fixed Battle solver, real pilots and1200 controls/tick snapshots are compared exactly across aspect ratios. Result comes from an actual Duel conclusion. Native Windows simulation is not phone, immersive-bar or physical hardware acceptance."}
	var file := FileAccess.open(report,FileAccess.WRITE); file.store_string(JSON.stringify(portable(data),"\t")); file.close()
	print("ANDROID_FULLSCREEN_LAYOUT_003A2_%s checks=%d failures=%d native=%s movie=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),native,movie])
	quit(0 if failures.is_empty() else 1)
