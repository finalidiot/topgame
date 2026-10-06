extends SceneTree
## Retention/profiling fixtures, never presented as human gameplay footage.
## Controls and legitimate draft intents only: no fighter/outcome/RPM edits.
const Battle = preload("res://scripts/battle.gd")
const Music = preload("res://scripts/music.gd")
const Sound = preload("res://scripts/sound.gd")
const Menus = preload("res://scripts/menus.gd")
const Context = preload("res://scripts/run_context.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const Collection = preload("res://scripts/collection_save.gd")
var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {}
var qa: String
var native_sample: bool = false
var allow_audio: bool = false
var requested_ticks: int = 2400

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _battle_sound(_kind: String) -> void: pass

class ConcurrentSibling extends "res://scripts/collection_save.gd":
	func backup_collection() -> Dictionary:
		var result: Dictionary = super.backup_collection()
		# Deterministic transaction-boundary fixture, external path only: an
		# absent valid backup appears after the verified inventory was captured.
		if bool(result.ok): assert(DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),ProjectSettings.globalize_path(save_path)+".bak") == OK)
		return result

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value and failures.size() < 30: failures.append(message); push_error(message)

func script_state(subject: Object) -> Dictionary:
	# Enumerate all script variables, including guards/queues omitted from public
	# telemetry. Exclude only scene/weak/resource references; recurse pure state.
	var state: Dictionary = {}
	for property: Dictionary in subject.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var name: String = str(property.name)
		var value: Variant = subject.get(name)
		if value is RandomNumberGenerator:
			state[name] = {"seed":value.seed,"state":value.state}
		elif value is Object:
			if value is RefCounted and not value is Resource and not value is WeakRef and value.get_script() != null:
				state[name] = script_state(value)
		elif value is Dictionary or value is Array: state[name] = value.duplicate(true)
		else: state[name] = value
	return state

func combat_state(b: Node2D) -> Dictionary:
	# Before the opening draft is chosen, Battle is genuinely uninitialized;
	# its public combat snapshot expects a SwarmRuntime host after begin().
	var state: Dictionary = b.snapshot() if b.swarm.battle != null else {"entities":b.fighters.duplicate(true),"status":b.battle_status,"elapsed":b.elapsed,"paused":b.paused}
	state["powers"] = script_state(b.powers)
	state["roster"] = script_state(b.roster)
	state["swarm_state"] = script_state(b.swarm)
	state["continuous_state"] = script_state(b.continuous) if b.continuous != null else {}
	state["simulation_rng"] = b._simulation_rng.state
	state["cosmetic_rng"] = b._cosmetic_rng.state
	var ai: Dictionary = {}
	for id: int in b._ai_rngs: ai[id] = b._ai_rngs[id].state
	state["ai_rngs"] = ai
	# Contact/input/progression queues and all fixed-tick transition guards.
	for key: String in ["_accumulator","_countdown","_launch_time","_finish_timer","_result_emitted","_hit_stop","_pair_cooldowns","_burst_was_down","_burst_buffer","_buffered_burst_direction","_progression_queue","_progression_sequence","_progression_eliminated","_progression_contacted","_progression_waves","_combat_needs_release"]:
		var value: Variant = b.get(key)
		state[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return state

func inventory(node: Node) -> Dictionary:
	var nodes: Array[int] = []
	var controls: Array[int] = []
	var textures: Dictionary = {}
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		nodes.append(current.get_instance_id())
		if current is Control: controls.append(current.get_instance_id())
		if current is TextureRect and current.texture != null: textures[current.get_instance_id()] = current.texture.get_instance_id()
		for child: Node in current.get_children(): pending.append(child)
	return {"nodes":nodes,"controls":controls,"textures":textures}

func profile(samples: Array[float]) -> Dictionary:
	if samples.is_empty(): return {"samples":0}
	var values: Array[float] = samples.duplicate(); values.sort()
	return {"samples":values.size(),"median_us":values[values.size()/2],"p95_us":values[mini(values.size()-1,ceili(values.size()*0.95)-1)],"maximum_us":values.back()}

func current_hud(raw: Dictionary, context: RefCounted, b: Node2D) -> Dictionary:
	var stats: Dictionary = raw.duplicate(true)
	var p: Dictionary = b.player_entity()
	stats["player_rpm"] = float(p.rpm)
	stats["player_rpm_value"] = int(float(p.rpm)*9000.0)
	stats["owned_power_ids"] = context.owned_power_ids if context != null else p.powers.duplicate()
	stats["power_ranks"] = context.power_ranks if context != null else p.power_ranks.duplicate()
	stats["power_mutations"] = context.power_mutations if context != null else p.power_mutations.duplicate()
	stats["is_run"] = context != null
	if context != null:
		var progress: Dictionary = context.progression_snapshot()
		stats.merge({"starter_id":context.starter_id,"rerolls":context.reroll_charges,"level":progress.level,"xp":progress.xp,"xp_threshold":progress.threshold,"progression_max":progress.maxed},true)
	if b.continuous != null: stats["run_state"] = b.continuous.snapshot()
	return stats

func connect_progression(b: Node2D, context: RefCounted) -> void:
	b.progression_events.connect(func(events: Array) -> void:
		for event: Dictionary in events: context.award_xp(event)
		if b.continuous != null: b.continuous.progression_level = context.level)
	b.threat_started.connect(func(summary: Dictionary) -> void: context.admit_event(int(summary.threat)))
	b.round_finished.connect(func(result: Dictionary) -> void:
		if not bool(result.get("won",false)): context.fail_run())

func claim_offer(context: RefCounted, b: Node2D = null) -> bool:
	if context.pending_offer.is_empty(): return false
	var id: String = str(context.pending_offer[0])
	var draft: String = context.pending_draft_id
	if not context.choose_power(draft,id): return false
	if not context.pending_mutation_power.is_empty():
		if not context.choose_mutation(draft,str(context.pending_mutation_offer[0])): return false
	if b != null: return b.acquire_run_power(id,int(context.power_ranks[id]),str(context.power_mutations.get(id,"")))
	return true

func paired_fixture(label: String, seed_value: int, ticks: int, intense: bool) -> void:
	var shown: Node2D = Battle.new(); var control: Node2D = Battle.new()
	root.add_child(shown); root.add_child(control)
	shown.set_physics_process(false); control.set_physics_process(false)
	control.visible = false
	var contexts: Array = [null,null]
	var build: Dictionary = Starters.build_for("bastion")
	var hud: Array[Dictionary] = [{}]
	shown.hud_updated.connect(func(stats: Dictionary) -> void: hud[0] = stats.duplicate(true))
	if not intense:
		for index: int in range(2):
			var context: RefCounted = Context.new()
			context.start(build,seed_value,"bastion")
			check(claim_offer(context),label+": legitimate starting offer committed")
			contexts[index] = context
		var ctx_shown: RefCounted = contexts[0]; var ctx_control: RefCounted = contexts[1]
		connect_progression(shown,ctx_shown); connect_progression(control,ctx_control)
		shown.begin_run(build,ctx_shown.current_encounter(),seed_value)
		control.begin_run(build,ctx_control.current_encounter(),seed_value)
	else:
		# Explicit authored 10-small-body / rank-II stress fixture. Starts through
		# begin_encounter and real scheduled admissions; no fake hits/outcomes.
		var descriptor: Dictionary = Encounters.for_slot(3,seed_value)
		descriptor["ability_rebalance"] = true
		descriptor["swarm_parameters"] = {"waves":[10,10,10],"wave_times":[0.0,4.0,8.0],"active_cap":10,"cleanup_time":32.0}
		descriptor["player_power_ids"] = ["impact_wake","iron_comet","dead_centre","chain_reaction","second_wind","redline","breakneck"]
		descriptor["player_power_ranks"] = {"impact_wake":2,"iron_comet":2,"dead_centre":2,"chain_reaction":2,"second_wind":2,"redline":2,"breakneck":2}
		shown.begin_encounter(build,descriptor); control.begin_encounter(build,descriptor)
	var menus: Control = Menus.new(); root.add_child(menus); menus.set_process(false)
	var music: Node = Music.new()
	music.configure_playback(native_sample and allow_audio)
	root.add_child(music); music.set_process(false); music.set_context("run")
	var sound: Node = Sound.new(); root.add_child(sound); sound.set_process(false)
	if native_sample and allow_audio:
		shown.event_sfx.connect(func(kind: String) -> void: sound.play_sound(kind); music.notify_cue(kind))
	var disabled_music: Node = Music.new(); root.add_child(disabled_music); disabled_music.set_process(false)
	check(music.get_child_count() == 1 and music.synchronized_stream().stream_count == 5,"Five synchronized stems use exactly one MusicPlayer")
	check(sound.channels.size() == 8 and sound.get_child_count() == 8,"SFX retains exactly eight pooled channels")
	var stats: Dictionary = current_hud(hud[0],contexts[0],shown)
	menus.show_hud(stats)
	await process_frame # Retire only old HUD shell nodes before retained-ID baseline.
	var baseline: Dictionary = inventory(menus)
	var texture_key: String = str(stats.power_ranks)+str(stats.power_mutations)+str(stats.owned_power_ids)
	var step_us: Array[float] = []; var control_us: Array[float] = []; var hud_us: Array[float] = []; var music_us: Array[float] = []; var frame_us: Array[float] = []
	var max_hud_object_delta: int = 0; var max_hud_resource_delta: int = 0
	var max_nodes: int = baseline.nodes.size(); var max_controls: int = baseline.controls.size()
	var max_live: int = 0; var max_pressure: float = 0.0; var max_small: int = 0; var active_ticks: int = 0; var draft_claims: int = 0; var power_texture_changes: int = 0
	var draw_calls: Array[float] = []; var drawn_objects: Array[float] = []; var drawn_primitives: Array[float] = []
	var max_texture_bytes: int = 0; var max_video_bytes: int = 0
	var last_frame: int = Time.get_ticks_usec()
	for frame: int in range(ticks):
		var input: Dictionary = Bot.input(shown,"hybrid" if intense else "defensive",frame)
		var stamp: int = Time.get_ticks_usec()
		shown.test_step(Battle.FIXED_DT,input.direction,input.burst,input.brake)
		var shown_time: float = Time.get_ticks_usec()-stamp
		stamp = Time.get_ticks_usec()
		control.test_step(Battle.FIXED_DT,input.direction,input.burst,input.brake)
		var control_time: float = Time.get_ticks_usec()-stamp
		if not intense and not contexts[0].pending_offer.is_empty():
			check(script_state(contexts[0]) == script_state(contexts[1]),label+": exact actual XP draft before claim")
			check(claim_offer(contexts[0],shown) and claim_offer(contexts[1],control),label+": both legitimate level drafts committed")
			draft_claims += 1
		stats = current_hud(hud[0],contexts[0],shown)
		stamp = Time.get_ticks_usec()
		music.observe_run(stats.get("run_state",{}),stats); music.advance_presentation(Battle.FIXED_DT)
		var music_time: float = Time.get_ticks_usec()-stamp
		var objects_before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var resources_before: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
		stamp = Time.get_ticks_usec(); menus.show_hud(stats)
		var hud_time: float = Time.get_ticks_usec()-stamp
		var objects_delta: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))-objects_before
		var resource_delta: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))-resources_before
		var ids: Dictionary = inventory(menus)
		check(ids.nodes == baseline.nodes and ids.controls == baseline.controls,label+": per-frame HUD retains every node/Control instance")
		var new_key: String = str(stats.power_ranks)+str(stats.power_mutations)+str(stats.owned_power_ids)
		if texture_key == new_key:
			check(ids.textures == baseline.textures,label+": unchanged power state retains AtlasTexture objects")
			max_hud_object_delta = maxi(max_hud_object_delta,objects_delta); max_hud_resource_delta = maxi(max_hud_resource_delta,resource_delta)
		else:
			power_texture_changes += 1; baseline.textures = ids.textures; texture_key = new_key
		max_nodes = maxi(max_nodes,ids.nodes.size()); max_controls = maxi(max_controls,ids.controls.size())
		check(combat_state(shown) == combat_state(control),label+": observed Music preserves all exact fighters/RPM/director/AI/RNG/guards at tick%d" % frame)
		if not intense: check(script_state(contexts[0]) == script_state(contexts[1]),label+": exact seed/draft/XP/offer/reroll/claim state at tick%d" % frame)
		if shown.battle_status == "battle":
			active_ticks += 1; step_us.append(shown_time); control_us.append(control_time); hud_us.append(hud_time); music_us.append(music_time)
			max_live = maxi(max_live,shown.fighters.size()); max_small = maxi(max_small,shown.swarm.active_count())
			if shown.continuous != null: max_pressure = maxf(max_pressure,float(shown.continuous.census().pressure))
		if native_sample:
			await process_frame
			frame_us.append(Time.get_ticks_usec()-last_frame); last_frame = Time.get_ticks_usec()
			if shown.battle_status == "battle":
				draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				drawn_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
				drawn_primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
				max_texture_bytes = maxi(max_texture_bytes,int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)))
				max_video_bytes = maxi(max_video_bytes,int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	check(active_ticks > 300,label+": sample contains substantial real active combat")
	check(max_hud_object_delta == 0 and max_hud_resource_delta == 0,label+": steady HUD causes no retained Godot Object/Resource allocation")
	check(disabled_music.music_snapshot().transport_starts == 0,"Disabled control never starts native audio")
	check(music.music_snapshot().transport_starts <= 1,"Observation/intensity never restarts the music transport")
	measurements[label] = {"seed":seed_value,"requested_ticks":ticks,"actual_active_ticks":active_ticks,"survival_seconds":shown.elapsed,"final_status":shown.battle_status,"hits":shown.hits,"max_live_fighters":max_live,"max_live_small":max_small,"max_pressure":max_pressure,"draft_claims":draft_claims,"HUD":{"nodes":max_nodes,"controls":max_controls,"steady_max_object_delta":max_hud_object_delta,"steady_max_resource_delta":max_hud_resource_delta,"legitimate_power_texture_changes":power_texture_changes,"transient_string_allocations":"not instrumented"},"timings":{"observed_battle":profile(step_us),"unobserved_battle":profile(control_us),"music_observe_and_envelope":profile(music_us),"show_hud":profile(hud_us),"native_frame_including_verifier":profile(frame_us)},"renderer":{"draw_calls":count_profile(draw_calls),"drawn_objects":count_profile(drawn_objects),"drawn_primitives":count_profile(drawn_primitives),"maximum_texture_bytes":max_texture_bytes,"maximum_video_bytes":max_video_bytes},"music":music.music_snapshot(),"fixture_policy":"Real seeded opening Run and legal actual XP drafts" if not intense else "Clearly labelled profiler-only 10-body swarm / seven rank-II loadout; actual simulation, no injected hits/outcomes"}
	music.free(); disabled_music.free(); sound.free(); menus.free(); shown.free(); control.free()
	await process_frame

func raw_hashes(path: String) -> Dictionary:
	var hashes: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp", ".preferences.cfg"]: hashes[suffix] = FileAccess.get_sha256(path+suffix) if FileAccess.file_exists(path+suffix) else ""
	return hashes

func count_profile(samples: Array[float]) -> Dictionary:
	var data: Dictionary = profile(samples)
	for key: String in ["median_us","p95_us","maximum_us"]:
		if data.has(key): data[key.trim_suffix("_us")] = data[key]; data.erase(key)
	return data

func test_main_boundaries() -> void:
	var path: String = qa.path_join("temp/retention_shell_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	var app: QuietMain = QuietMain.new(); app.smoke_mode = true; app.collection_path = path
	root.add_child(app); app.set_process(false); app.battle.set_physics_process(false)
	var default_path: String = ProjectSettings.globalize_path(Collection.DEFAULT_PATH)
	check(app._is_default_collection_path(default_path.to_upper()),"Windows casing aliases cannot bypass real-profile reset confirmation")
	check(app._is_default_collection_path(default_path.replace("/","\\")),"Windows separator aliases cannot bypass real-profile reset confirmation")
	check(not app._is_default_collection_path(path),"External QA collection is distinguished from the player profile")
	check(app.collection.initialize_starter("bastion").ok,"Shell audit initializes only a unique external QA collection")
	app._garage(); app._start_run()
	var lock: Dictionary = script_state(app.run_context)
	var files: Dictionary = raw_hashes(path)
	for intent: String in ["main_menu","open_workshop","quick_duel","start_run","customize","build_changed","help","settings","play_modes","save_tools","backup_collection","request_reset_collection","confirm_reset_collection","equip_part","launch_owned_run","confirm_first_starter"]:
		var screen_before: String = app.screen
		app._action(intent,{"blade":"smash","category":"blade","id":"smash"})
		check(app.screen == screen_before and script_state(app.run_context) == lock and raw_hashes(path) == files,"Active Run rejects stale front/options/save/build intent: "+intent)
	# Options -> Pause -> Return to the actual opening draft preserves chronology.
	app._pause(); app._action("settings")
	var physical: Dictionary = combat_state(app.battle)
	app.battle.test_step(0.25,Vector2.RIGHT,true,true)
	app._action("back_settings"); app._resume()
	check(app.screen == "reward" and app.battle.paused and script_state(app.run_context) == lock,"Return from paused Options restores the actual draft and exact Run state")
	check(combat_state(app.battle) == physical,"Options/pause does not advance the physical arena")
	var row: Dictionary = {"encounter_id":app.run_context.pending_draft_id,"power_id":app.run_context.pending_offer[0],"run_seed":app.run_context.run_seed,"offer_revision":app.run_context.reroll_snapshot().revision}
	app._action("choose_power",row); app._acquisition_remaining = 0.0; app._finish_acquisition(); app.battle.set_physics_process(false)
	for frame: int in range(240): app.battle.test_step(Battle.FIXED_DT,Vector2.ZERO,false,false)
	app._pause(); app._action("settings")
	physical = combat_state(app.battle); lock = script_state(app.run_context)
	app.battle.test_step(0.25,Vector2.LEFT,true,true)
	app._action("back_settings")
	check(app.screen == "pause" and app.battle.paused,"Options Back retains the actual battle pause")
	check(combat_state(app.battle) == physical and script_state(app.run_context) == lock,"Real combat and Director/RPM/draft remain exact during paused Options")
	app._resume(); check(app.screen == "battle" and not app.battle.paused,"Return resumes the same physical arena")
	check(raw_hashes(path) == files,"Run routing and options audit preserve permanent collection bytes")
	measurements.shell = {"fixture":path,"windows_default_aliases_checked":true,"stale_intents":16,"pause_origins":["reward","battle"]}
	app.free(); await process_frame
	var concurrent_path: String = qa.path_join("temp/retention_concurrent_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	var concurrent: RefCounted = ConcurrentSibling.new(concurrent_path)
	check(concurrent.load_save().ok and concurrent.initialize_starter("breaker").ok,"Concurrency fixture selects one actual starter outside the profile")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(concurrent_path)
	# First-save commit legitimately writes a backup; remove just this exact
	# unique external fixture sibling so the race tests initial absence.
	if FileAccess.file_exists(concurrent_path+".bak"): assert(DirAccess.remove_absolute(concurrent_path+".bak") == OK)
	check(not FileAccess.file_exists(concurrent_path+".bak"),"Concurrency fixture starts with an absent exact backup sibling")
	var result: Dictionary = concurrent.reset_collection(true)
	check(not bool(result.ok) and FileAccess.get_file_as_bytes(concurrent_path) == original and FileAccess.get_file_as_bytes(concurrent_path+".bak") == original,"New previously absent sibling blocks reset and preserves both original and concurrent data")
	check(concurrent.is_initialized() and concurrent.owned_count() == 3,"Conflicted reset preserves live ownership")
	measurements.shell["concurrent_absent_sibling"] = {"fixture":concurrent_path,"result":result,"preserved_original":true}

func run() -> void:
	var base: String = OS.get_environment("TOPGAME_QA_ROOT")
	if base.is_empty(): base = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	qa = base.path_join("002C.6"); assert(DirAccess.make_dir_recursive_absolute(qa.path_join("temp")) == OK)
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--native-sample": native_sample = true
		if arg == "--allow-native-audio": allow_audio = true
		if arg.begins_with("--ticks="): requested_ticks = clampi(int(arg.trim_prefix("--ticks=")),600,2400)
	check(not native_sample or DisplayServer.get_name() != "headless","Native display sample must use an actual renderer")
	var human_before: Dictionary = raw_hashes(Collection.DEFAULT_PATH)
	var human_preferences_before: String = FileAccess.get_sha256("user://prototype.cfg") if FileAccess.file_exists("user://prototype.cfg") else ""
	var controller_inventory: Array[Dictionary] = []
	for id: int in Input.get_connected_joypads(): controller_inventory.append({"device":id,"name":Input.get_joy_name(id),"guid":Input.get_joy_guid(id)})
	measurements.environment = {"display":DisplayServer.get_name(),"audio_driver":AudioServer.get_driver_name(),"native_audio_explicitly_enabled":native_sample and allow_audio,"controller_inventory":controller_inventory,"physical_controller_validation":"Not exercised; inventory only","accepted_combat_baseline":"58cd1790561337be1fc7c4c114b87564c4617aa1","original_prepared_parent":"0525cb0ff6665705bb0e1ccc3db3dcae10fae6f7"}
	measurements.source_hashes = {}
	for source: String in ["scripts/battle.gd","scripts/power_runtime.gd","scripts/run_context.gd","scripts/threat_director.gd","scripts/spin_economy.gd","scripts/part_physics.gd","scripts/parts.gd","assets/data/parts_catalogue.json","scripts/main.gd","scripts/menus.gd","scripts/collection_save.gd","scripts/sound.gd","scripts/music.gd","tests/test_presentation_retention.gd"]: measurements.source_hashes[source] = FileAccess.get_sha256("res://"+source)
	await test_main_boundaries()
	await paired_fixture("real_seeded_run",7731,requested_ticks,false)
	await paired_fixture("intense_profiler_fixture",9191,mini(1200,requested_ticks),true)
	measurements.memory = {"texture_bytes":int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),"video_bytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),"resource_objects":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"note":"Rendering memory monitors may be unavailable/zero under headless; music source PCM budget is 22,341,820 bytes"}
	check(raw_hashes(Collection.DEFAULT_PATH) == human_before,"All retention/performance QA preserves the human collection and preferences")
	check((FileAccess.get_sha256("user://prototype.cfg") if FileAccess.file_exists("user://prototype.cfg") else "") == human_preferences_before,"Every human Master/Music/SFX/Mute/display preference byte is preserved")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var path: String = arg.trim_prefix("--report="); assert(not FileAccess.file_exists(path))
			var file: FileAccess = FileAccess.open(path,FileAccess.WRITE); assert(file != null)
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"limits":"Retained Object/Resource identity/counts and actual combat CPU timings; transient allocations and verifier-influenced native frame timing are not production frametime claims"},"\t")); file.close()
	print("PRESENTATION_RETENTION_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
