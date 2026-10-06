extends SceneTree
## Controlled presentation/audio audition. No Main, save, Run or Battle exists.
## Production synchronized stems and gain envelopes render actual mixed audio.
const Music = preload("res://scripts/music.gd")
const Sound = preload("res://scripts/sound.gd")
const Menus = preload("res://scripts/menus.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const Parts = preload("res://scripts/parts.gd")
const STAGE_FRAMES: int = 540
const FIXTURE_LABEL: String = "CONTROLLED MUSIC AUDITION — RUN-TIME INPUTS ARE FIXTURES"
var output: String = ""
var frames: String = ""
var diagnostic: bool = false
var music: Node
var sound: Node
var menus: Control
var stage_label: Label
var details_label: Label
var gains_label: Label
var cue_label: Label
var rows: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var images: Dictionary = {}
var cues: Array[Dictionary] = []
var start_frame: int = 0

func _initialize() -> void: call_deferred("run")

func safe_path(path: String, folder: String) -> bool:
	var qa: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa.is_empty(): qa = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	var allowed: String = qa.replace("\\", "/").simplify_path().path_join("002C.6/" + folder).to_lower() + "/"
	return path.is_absolute_path() and path.replace("\\", "/").simplify_path().to_lower().begins_with(allowed)

func frame() -> int: return Engine.get_process_frames() - start_frame

func label(value: String, area: Rect2, color: Color = FrontEnd.TEXT) -> Label:
	var text: Label = Label.new()
	text.text = value; text.position = area.position; text.size = area.size
	text.add_theme_color_override("font_color", color)
	text.add_theme_font_size_override("font_size", 10)
	return text

func audition_ui() -> void:
	menus = Menus.new()
	root.add_child(menus)
	# Display only: this method receives a build dictionary and opens no save.
	menus.show_collection_title(Parts.DEFAULT_BUILD, {"volume": 0.65, "music_volume": 0.55}, true)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100; root.add_child(layer)
	var overlay: Control = Control.new()
	overlay.theme = FrontEnd.make_theme()
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(overlay)
	var band: Panel = Panel.new()
	band.position = Vector2(8, 6); band.size = Vector2(624, 75)
	band.add_theme_stylebox_override("panel", FrontEnd.plate(FrontEnd.INK, FrontEnd.ORANGE))
	overlay.add_child(band)
	overlay.add_child(label(FIXTURE_LABEL, Rect2(16, 13, 608, 15), FrontEnd.ORANGE))
	overlay.add_child(label("ACTUAL SYNCHRONIZED PLAYER / MIXER / ENVELOPES / NO GAMEPLAY", Rect2(16, 32, 608, 15), FrontEnd.BLUE))
	overlay.add_child(label("DISPLAY ASSEMBLY IS A FIXTURE. NO COLLECTION OR BATTLE IS OPEN.", Rect2(16, 51, 608, 15), FrontEnd.MUTED))
	var body: Panel = Panel.new()
	body.position = Vector2(14, 87); body.size = Vector2(313, 233)
	body.add_theme_stylebox_override("panel", FrontEnd.plate(FrontEnd.PANEL, FrontEnd.BORDER))
	overlay.add_child(body)
	stage_label = label("", Rect2(24, 101, 292, 33), FrontEnd.ORANGE)
	details_label = label("", Rect2(24, 144, 292, 55), FrontEnd.TEXT)
	gains_label = label("", Rect2(24, 205, 292, 69), FrontEnd.BLUE)
	cue_label = label("NO SFX CUE IN THIS PHASE", Rect2(24, 282, 292, 30), FrontEnd.MUTED)
	for item: Label in [stage_label, details_label, gains_label, cue_label]: overlay.add_child(item)
	var footer: Panel = Panel.new()
	footer.position = Vector2(8, 324); footer.size = Vector2(624, 32)
	footer.add_theme_stylebox_override("panel", FrontEnd.plate(FrontEnd.INK, FrontEnd.BORDER))
	overlay.add_child(footer)
	overlay.add_child(label("CONTROLLED AUDITION / CONTINUOUS TRANSPORT / FIXTURE CHANGES ONLY", Rect2(16, 334, 608, 15), FrontEnd.MUTED))

func snapshot_image(name: String) -> void:
	if diagnostic and frames.is_empty(): return
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	assert(pixels.get_size() == Vector2i(640, 360))
	var path: String = frames.path_join(name + ".png")
	assert(not FileAccess.file_exists(path))
	assert(pixels.save_png(path) == OK)
	images[name] = {"path": path, "frame": frame(), "fixture_label": FIXTURE_LABEL, "menu_screen": menus.screen, "music": music.music_snapshot()}

func stage_fixture(name: String) -> Dictionary:
	var elapsed: float = {"opening_run": 5.0, "middle_run": 110.0, "late_anthem": 240.0, "boss_cue_audition": 380.0}.get(name, 0.0)
	var state: Dictionary = {"director": true, "run_seed": 7301, "survival_time": elapsed, "threats_cleared": 0, "calm": false,
		"census": {"pressure": 2.6, "active_total": 2, "bosses": 0, "elites": 0}, "limits": {"tier": 0}}
	if name == "middle_run": state.limits.tier = 2; state.threats_cleared = 4
	if name == "late_anthem": state.limits.tier = 3; state.threats_cleared = 7
	if name == "boss_cue_audition":
		state.census = {"pressure": 13.0, "active_total": 7, "bosses": 1, "elites": 1}; state.limits.tier = 4; state.threats_cleared = 10
	return {"state": state, "player_stats": {"player_rpm": 0.8, "power_ranks": {}}, "synthetic_elapsed_seconds": elapsed}

func audition_stage(name: String, index: int) -> void:
	var phase_start: int = frame()
	var fixture: Dictionary = stage_fixture(name)
	if name in ["title", "workshop", "opening_run"]:
		music.set_context(name if name in ["title", "workshop"] else "run")
	stage_label.text = "%d / 6  %s\n9 SECONDS / CONTROLLED FIXTURE" % [index + 1, name.replace("_", " ").to_upper()]
	cue_label.text = "NO SFX CUE IN THIS PHASE"
	for tick: int in range(STAGE_FRAMES):
		if name not in ["title", "workshop"]: music.observe_run(fixture.state, fixture.player_stats)
		if name == "boss_cue_audition" and tick in [270, 390]:
			var cue: String = "heavy" if tick == 270 else "low_rpm"
			sound.play_sound(cue); music.notify_cue(cue)
			cue_label.text = "LABELLED SFX CUE AUDITION:\n" + cue.to_upper() + " / MUSIC DUCK"
			cues.append({"frame": frame(), "cue": cue, "fixture_only": true})
		var current: Dictionary = music.music_snapshot()
		details_label.text = "FIXTURE ELAPSED %03d SECONDS\nCENSUS PRESSURE %04.1f / TIER %d\nBOSSES %d / LIVE POSITION %04.1fS" % [int(fixture.synthetic_elapsed_seconds), float(fixture.state.census.pressure), int(fixture.state.limits.tier), int(fixture.state.census.bosses), float(current.position)]
		gains_label.text = "LIVE MUSIC GAINS / ACTUAL MIXER\nTITLE %.2f / BENCH %.2f\nBASE %.2f / PRESSURE %.2f\nANTHEM %.2f / DUCK %.2fS" % [current.gains[0], current.gains[1], current.gains[2], current.gains[3], current.gains[4], current.duck_left]
		if tick % 30 == 0:
			rows.append({"frame": frame(), "phase": name, "phase_tick": tick, "fixture": fixture.duplicate(true), "music": current, "music_bus_db": AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))})
		if tick == 240: await snapshot_image(name)
		await process_frame
	var snap: Dictionary = music.music_snapshot()
	assert(snap.asset_errors.is_empty())
	assert(snap.transport_starts == (0 if diagnostic else 1))
	assert(diagnostic or snap.playing)
	phases.append({"name": name, "from_frame": phase_start, "to_frame": frame(), "fixture": fixture, "settled_music": snap})
	print("METAL_AUDITION_STAGE ", name, " frame=", frame(), " gains=", snap.gains)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): output = arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frames = arg.trim_prefix("--frames=")
		if arg == "--diagnostic": diagnostic = true
	if not safe_path(output, "manifests") or FileAccess.file_exists(output) or ((not diagnostic or not frames.is_empty()) and not safe_path(frames, "frames")):
		push_error("Controlled audition requires fresh external C6 paths"); quit(2); return
	if not frames.is_empty(): DirAccess.make_dir_recursive_absolute(frames)
	root.size = Vector2i(640, 360); root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	start_frame = Engine.get_process_frames()
	music = Music.new(); music.configure_playback(not diagnostic); root.add_child(music)
	sound = Sound.new(); root.add_child(sound); sound.rng.seed = 421
	sound.apply_settings({"volume": 0.65, "sfx_volume": 1.0, "muted": false})
	music.apply_settings({"music_volume": 0.55, "music_muted": false})
	if diagnostic: sound.muted = true
	audition_ui()
	var stream: AudioStreamSynchronized = music.synchronized_stream()
	var native_stems: Array[Dictionary] = []
	for index: int in range(stream.stream_count):
		var stem: AudioStreamWAV = stream.get_sync_stream(index)
		var digest: HashingContext = HashingContext.new()
		digest.start(HashingContext.HASH_SHA256); digest.update(stem.data)
		native_stems.append({"name": Music.STEM_NAMES[index], "mix_rate": stem.mix_rate, "format": stem.format, "stereo": stem.stereo, "pcm_bytes": stem.data.size(), "pcm_sha256": digest.finish().hex_encode(), "loop_begin": stem.loop_begin, "loop_end": stem.loop_end, "loop_mode": stem.loop_mode})
	var names: Array[String] = ["title", "workshop", "opening_run", "middle_run", "late_anthem", "boss_cue_audition"]
	for index: int in range(names.size()): await audition_stage(names[index], index)
	var final_music: Dictionary = music.music_snapshot()
	var final_sfx: Dictionary = sound.audio_snapshot()
	var raw_frames: int = frame()
	music.configure_playback(false)
	for channel: AudioStreamPlayer in sound.channels: channel.stop()
	# Give the native mixer callback time to release active WAV playback handles.
	OS.delay_msec(200); music.free(); sound.free(); OS.delay_msec(100)
	await process_frame
	var report: Dictionary = {"task": "002C.6", "diagnostic": diagnostic, "fixture_label": FIXTURE_LABEL, "policy": "Controlled music audition only: scalar run-time dictionaries are synthetic fixtures. Production Menus/Music/Sound, native synchronized AudioStreamPlayer/mixer/gain envelopes, no Main, collection, save or battle. SFX cues are labelled auditions, never gameplay impacts.", "collection_opened": false, "battle_created": false, "audio_driver": AudioServer.get_driver_name(), "mixer_rate": AudioServer.get_mix_rate(), "native_view": [640, 360], "fps": 60, "raw_frames": raw_frames, "phases": phases, "rows": rows, "images": images, "native_stems": native_stems, "cue_auditions": cues, "music_final": final_music, "sfx_final": final_sfx}
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	assert(file != null); file.store_string(JSON.stringify(report, "\t")); file.close()
	print("METAL_AUDITION_PASS phases=", phases.size(), " frames=", raw_frames, " transport_starts=", final_music.transport_starts)
	quit(0)
