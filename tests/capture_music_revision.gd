extends SceneTree
## Labelled auditory review of production synchronized playback, not gameplay.
## No Main, profile, collection, Battle or economy transaction is instantiated.
const Music = preload("res://scripts/music.gd")
const Sound = preload("res://scripts/sound.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const PHASES: Array[Dictionary] = [
	{"name":"title", "context":"title", "seconds":45},
	{"name":"first_machine", "context":"workshop", "seconds":8},
	{"name":"shop", "context":"workshop", "seconds":6},
	{"name":"workshop", "context":"workshop", "seconds":6},
	{"name":"early_run", "context":"run", "seconds":12},
	{"name":"mid_run", "context":"run", "seconds":12},
	{"name":"late_run", "context":"run", "seconds":12},
	{"name":"boss", "context":"run", "seconds":12},
	{"name":"results", "context":"result", "seconds":8},
	{"name":"normal_mix_sfx", "context":"run", "seconds":12}
]
const FIXTURE_LABEL: String = "CONTROLLED SOUNDTRACK REVIEW / RUN OBSERVATIONS ARE FIXTURES"
var output: String = ""
var music: Node
var sound: Node
var phase_label: Label
var details: Label
var mix_label: Label
var last_cue: String = "WAITING FOR CUES"
var start_frame: int = 0
var rows: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var cues: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func safe_path(path: String) -> bool:
	var qa: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa.is_empty(): qa = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	var allowed: String = qa.replace("\\", "/").simplify_path().path_join("003A/manifests/").to_lower()
	return path.is_absolute_path() and path.replace("\\", "/").simplify_path().to_lower().begins_with(allowed) and path.get_extension() == "json"
func frame() -> int: return Engine.get_process_frames() - start_frame
func label(text: String, y: int, color: Color, size: int = 12) -> Label:
	var node: Label = Label.new(); node.position = Vector2(20, y); node.size = Vector2(600, 42)
	node.text = text; node.add_theme_color_override("font_color", color); node.add_theme_font_size_override("font_size", size)
	return node
func review_ui() -> void:
	var overlay: Control = Control.new(); overlay.theme = FrontEnd.make_theme(); root.add_child(overlay)
	var background: ColorRect = ColorRect.new(); background.color = FrontEnd.INK; background.size = Vector2(640, 360); overlay.add_child(background)
	overlay.add_child(label("SPINNING METAL / HUMAN FEEDBACK MUSIC REVISION", 18, FrontEnd.ORANGE))
	overlay.add_child(label(FIXTURE_LABEL, 48, FrontEnd.MUTED, 10))
	phase_label = label("", 100, FrontEnd.TEXT, 18); overlay.add_child(phase_label)
	details = label("", 157, FrontEnd.BLUE); overlay.add_child(details)
	mix_label = label("", 223, FrontEnd.TEXT); overlay.add_child(mix_label)
	mix_label.size.y = 64
	overlay.add_child(label("ORIGINAL SCORE / ACTUAL NATIVE MIXER / CONTINUOUS TRANSPORT\nNO GAMEPLAY, COLLECTION OR SAVE IS OPEN", 303, FrontEnd.MUTED, 10))
func fixture(name: String) -> Dictionary:
	var elapsed: float = {"early_run":5, "mid_run":110, "late_run":240, "boss":380, "normal_mix_sfx":110}.get(name, 0)
	var state: Dictionary = {"director":true, "run_seed":73019, "survival_time":elapsed, "threats_cleared":0, "calm":false,
		"census":{"pressure":2.6, "active_total":2, "bosses":0, "elites":0}, "limits":{"tier":0}}
	if name in ["mid_run", "normal_mix_sfx"]: state.limits.tier = 2; state.threats_cleared = 4
	if name == "late_run": state.limits.tier = 3; state.threats_cleared = 7
	if name == "boss": state.census = {"pressure":13.0, "active_total":7, "bosses":1, "elites":1}; state.limits.tier = 4; state.threats_cleared = 10
	return state
func audition_phase(phase: Dictionary, index: int) -> void:
	music.set_context(phase.context)
	var observed: Dictionary = fixture(phase.name)
	var begin: int = frame()
	phase_label.text = "%02d / 10   %s" % [index + 1, phase.name.replace("_", " ").to_upper()]
	for tick: int in range(int(phase.seconds) * 60):
		if phase.context == "run": music.observe_run(observed, {"player_rpm":0.8, "power_ranks":{}})
		if phase.name == "normal_mix_sfx" and tick in [120, 240, 390, 510]:
			var cue: String = {120:"ui", 240:"heavy", 390:"low_rpm", 510:"level_up"}[tick]
			sound.play_sound(cue); music.notify_cue(cue)
			last_cue = cue.replace("_", " ").to_upper()
			cues.append({"frame":frame(), "cue":cue, "label":"SFX CUE AUDITION; NOT GAMEPLAY"})
		var snap: Dictionary = music.music_snapshot()
		details.text = "MUSIC %.2f / SFX %.2f / MUSIC BUS %.1f DB\nLIVE SHARED CURSOR %.2f S / TRANSPORT STARTS %d" % [0.55, 0.65, AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), snap.position, snap.transport_starts]
		mix_label.text = "TITLE %.2f / PRESERVED BENCH %.2f\nPRESERVED RUN %.2f / RHYTHM %.2f / BAND %.2f\n%s" % [snap.gains[0], snap.gains[1], snap.gains[2], snap.gains[3], snap.gains[4], "NORMAL MIX: LABELLED SFX + MUSIC DUCK" if phase.name == "normal_mix_sfx" else "MUSIC ONLY / NO SFX IN THIS SECTION"]
		if phase.name == "normal_mix_sfx": mix_label.text += "\nLAST CUE: " + last_cue
		if tick % 60 == 0: rows.append({"frame":frame(), "phase":phase.name, "music":snap})
		await process_frame
	var snap: Dictionary = music.music_snapshot()
	assert(snap.transport_starts == 1 and snap.playing and snap.asset_errors.is_empty())
	phases.append({"name":phase.name, "context":phase.context, "from_frame":begin, "to_frame":frame(), "fixture":observed, "settled_music":snap})
	print("MUSIC_REVISION_PHASE ", phase.name, " frame=", frame(), " targets=", snap.targets)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): output = arg.trim_prefix("--manifest=")
	if not safe_path(output) or FileAccess.file_exists(output): push_error("Music review requires a fresh isolated 003A report"); quit(2); return
	root.size = Vector2i(640, 360); root.content_scale_size = Vector2i(640, 360); root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	start_frame = Engine.get_process_frames()
	music = Music.new(); music.configure_playback(true); root.add_child(music); music.apply_settings({"music_volume":0.55})
	sound = Sound.new(); root.add_child(sound); sound.rng.seed = 421; sound.apply_settings({"volume":0.65, "sfx_volume":1.0, "muted":false})
	review_ui()
	var native_stems: Array[Dictionary] = []
	var stream: AudioStreamSynchronized = music.synchronized_stream()
	for index: int in range(stream.stream_count):
		var wav: AudioStreamWAV = stream.get_sync_stream(index)
		var hash_context: HashingContext = HashingContext.new(); hash_context.start(HashingContext.HASH_SHA256); hash_context.update(wav.data)
		native_stems.append({"name":Music.STEM_NAMES[index], "mix_rate":wav.mix_rate, "stereo":wav.stereo, "format":wav.format, "pcm_bytes":wav.data.size(), "pcm_sha256":hash_context.finish().hex_encode(), "loop_begin":wav.loop_begin, "loop_end":wav.loop_end})
	for index: int in range(PHASES.size()): await audition_phase(PHASES[index], index)
	var report: Dictionary = {"task":"003A human feedback music", "fixture_label":FIXTURE_LABEL, "native_view":[640,360], "fps":60, "collection_opened":false, "battle_created":false, "native_stems":native_stems, "phases":phases, "rows":rows, "cue_auditions":cues, "music_final":music.music_snapshot(), "sfx_final":sound.audio_snapshot()}
	music.configure_playback(false)
	for channel: AudioStreamPlayer in sound.channels: channel.stop()
	OS.delay_msec(200); music.free(); sound.free(); OS.delay_msec(100); await process_frame
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE); assert(file != null); file.store_string(JSON.stringify(report, "\t")); file.close()
	print("MUSIC_REVISION_REVIEW_PASS phases=", phases.size(), " transport_starts=1")
	quit(0)
