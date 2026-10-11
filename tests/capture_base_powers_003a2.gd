extends SceneTree
## Normal-speed native footage. Declared initial ownership is a QA fixture.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Menus = preload("res://scripts/menus.gd")
const Sounds = preload("res://scripts/sound.gd")
const Music = preload("res://scripts/music.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Base = preload("res://scripts/base_power_runtime.gd")
var report: String = ""
var images: String = ""
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var frame: int = 0
var game: Node2D
var menu: Control
var caption: Label
var sound: Node
var music: Node
var current: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func portable(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x, value.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = portable(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result: Array = []
		for item: Variant in value: result.append(portable(item))
		return result
	return value

func hud(stats: Dictionary) -> void:
	stats = stats.duplicate(true)
	stats.owned_power_ids = current.ranks.keys()
	stats.power_ranks = current.ranks
	stats.power_mutations = {}
	stats.run_label = "DECLARED INITIAL OWNERSHIP / REAL COMBAT"
	stats.is_run = true; stats.starter_id = "custom"
	stats.level = 1; stats.xp = 0; stats.xp_threshold = 1; stats.progression_max = true; stats.rerolls = 0
	menu.show_hud(stats)

func input_direction(world: Vector2) -> Vector2:
	return Vector2(world.x-world.y, (world.x+world.y)*0.5).normalized() * minf(1.0, world.length())

func one_case(configuration: Dictionary) -> void:
	current = configuration
	var viewport := SubViewport.new(); viewport.size = Vector2i(640,360); viewport.disable_3d = true; viewport.gui_disable_input = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var picture := TextureRect.new(); picture.position = Vector2(80,60); picture.size = Vector2(640,360); picture.texture = viewport.get_texture(); picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; root.add_child(picture)
	menu = Menus.new(); root.add_child(menu); menu.set_presentation_canvas(Vector2(800,480))
	game = Battle.new(); viewport.add_child(game); game.set_physics_process(false)
	game.hud_updated.connect(hud)
	game.event_sfx.connect(func(kind: String) -> void: sound.play_sound(kind); music.notify_cue(kind))
	sound.grind_provider = game.grind_audio_snapshot
	var descriptor: Dictionary = Encounters.for_run_event(1, int(configuration.seed))
	descriptor.starter_id = "custom"; descriptor.player_power_ids = configuration.ranks.keys(); descriptor.player_power_ranks = configuration.ranks.duplicate(true)
	game.begin_run({"blade":"lopsider", "ratchet":"flywheel", "bit":"needle"}, descriptor, int(configuration.seed))
	game.continuous.progression_level = 1 + configuration.ranks.values().reduce(func(total: int, value: Variant) -> int: return total + int(value), 0)
	if configuration.has("initial_rpm"):
		# Low-reserve Last Stand showcase begins at a disclosed state. There
		# are no later refills, actor holds, forced contacts or forced outcomes.
		game.player_entity().rpm = float(configuration.initial_rpm)
		game.player_entity().energy = float(configuration.initial_rpm)
	var contacts: Array[Dictionary] = []
	game.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		if int(event.first_entity_id) == 1 or int(event.second_entity_id) == 1: contacts.append(event.duplicate(true)))
	var first_frame: int = frame
	var trace: Array[Dictionary] = []
	var states_seen: Array[int] = []
	var screenshots: Array[String] = []
	for tick: int in range(int(float(configuration.seconds)*60.0)):
		var player: Dictionary = game.player_entity()
		var position: Vector2 = player.pos
		var direction: Vector2 = (Vector2(cos(game.elapsed*0.55), sin(game.elapsed*0.55))*72.0-position-Vector2(player.vel)*0.25).limit_length(60.0)/60.0
		var brake: bool = fmod(game.elapsed, 6.0) > 4.7
		game.test_step(Battle.FIXED_DT, input_direction(direction)*0.7, tick%240 == 180, brake)
		music.observe_run(game.continuous.snapshot(), player)
		var state: Dictionary = game.powers.base_powers.snapshot(player)
		var prism: String = " / " + str(state.get("emphasis", "")) + " " + str(state.get("bonus_label", "")) + "%" if bool(state.owned) else ""
		caption.text = str(configuration.title) + prism + " / INITIAL LOADOUT FIXTURE / NORMAL SPEED"
		await process_frame
		await RenderingServer.frame_post_draw
		frame += 1
		if tick % 60 == 0: trace.append({"tick":tick, "seconds":game.elapsed, "rpm":player.rpm, "wobble":player.wobble, "state":state, "position":player.pos})
		var capture_frame: bool = tick == 240
		if bool(state.owned) and state.has("state") and int(state.state) not in states_seen:
			states_seen.append(int(state.state)); capture_frame = true
		if capture_frame:
			var path: String = images.path_join(str(configuration.id)+"_"+str(tick)+".png")
			if root.get_texture().get_image().save_png(path) != OK: failures.append("Frame save " + path)
			screenshots.append(path)
		if game.battle_status == "finished": break
	rows.append({"configuration":configuration, "movie_from":first_frame, "movie_to":frame, "trace":trace, "states_seen":states_seen, "contacts":contacts, "economy":game.continuous.economy.snapshot(), "screenshots":screenshots, "outcome":game.last_result})
	sound.grind_provider = Callable()
	game.free(); menu.free(); picture.free(); viewport.free()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
		if arg.begins_with("--images="): images = arg.trim_prefix("--images=")
	if DisplayServer.get_name() == "headless" or not report.is_absolute_path() or FileAccess.file_exists(report) or not images.is_absolute_path() or DirAccess.dir_exists_absolute(images): quit(2); return
	DirAccess.make_dir_recursive_absolute(images)
	root.size = Vector2i(800,512); root.content_scale_size = Vector2i(800,512); root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var layer := CanvasLayer.new(); layer.layer = 40; root.add_child(layer)
	caption = Label.new(); caption.position = Vector2(8,484); caption.size = Vector2(784,24); caption.add_theme_font_size_override("font_size",12); layer.add_child(caption)
	sound = Sounds.new(); root.add_child(sound); music = Music.new(); root.add_child(music); music.configure_playback(true); music.set_context("run")
	for id: String in Base.IDS:
		await one_case({"id":id,"title":Powers.get_power(id).name+" II","ranks":{id:2},"seconds":7.0,"seed":7341,"initial_rpm":0.30} if id == "last_stand" else {"id":id,"title":Powers.get_power(id).name+" II","ranks":{id:2},"seconds":7.0,"seed":7341})
	await one_case({"id":"three_auras","title":"CRIMSON + AZURE + EMERALD II","ranks":{"crimson_impact":2,"azure_stability":2,"emerald_endurance":2},"seconds":10.0,"seed":421})
	await one_case({"id":"prismatic_changes","title":"PRISMATIC CURRENT II","ranks":{"prismatic_current":2},"seconds":60.0,"seed":7341})
	await one_case({"id":"defensive_complements","title":"TRUE BEARING + LAST STAND / GYRO + SINK + GUARD","ranks":{"true_bearing":2,"last_stand":2,"gyro_lock":2,"impact_sink":2,"crash_guard":2},"seconds":22.0,"seed":2026,"initial_rpm":0.30})
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify(portable({"schema":"003a2-base-power-native-review-v1","failures":failures,"movie_frames":frame,"native_client":[800,512],"arena":[640,360],"cases":rows,"main_created":false,"collection_accessed":false,"scope":"Normal-speed fixed60 native Godot rendering and actual physics/AI/Director. Initial powers/ranks/pressure context injected per configuration; low-reserve .30 initial fixtures explicitly declared. No later resource/actor/effect/outcome edits. MovieWriter wall speed may differ; output playback is60fps. Automated sampled inputs are not human feel acceptance."}),"\t"))
	music.configure_playback(false); music.free(); sound.free(); layer.free()
	print("BASE_POWER_CAPTURE_%s frames=%d" % ["PASS" if failures.is_empty() else "FAIL", frame])
	quit(0 if failures.is_empty() else 1)
