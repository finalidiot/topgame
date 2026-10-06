extends SceneTree
## Headless real-engine mixer and read-only presentation checks. Native music
## playback remains off: mix_audio() exercises actual imported PCM/sync mixing.
const Music = preload("res://scripts/music.gd")
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); push_error(text)

func tick(music: Node, seconds: float) -> void:
	for index: int in range(ceili(seconds * 60.0)): music.advance_presentation(1.0 / 60.0)

func policy(music: Node) -> void:
	var opening: Dictionary = {"census": {"pressure": 2.6, "bosses": 0, "elites": 0, "active_total": 2}, "limits": {"budget": 2.8, "tier": 0}, "calm": false}
	var high: Dictionary = {"census": {"pressure": 13.0, "bosses": 1, "elites": 1, "active_total": 8}, "limits": {"budget": 16.0, "tier": 4}, "calm": false}
	var before: Dictionary = opening.duplicate(true)
	check(Music.adaptive_targets(opening).pressure == 0.0 and Music.adaptive_targets(opening).boss == 0.0, "Opening tight budget cannot pretend a single rival is high pressure")
	check(Music.adaptive_targets(high).boss == 1.0, "Actual admitted boss drives its aligned layer")
	check(Music.adaptive_targets(opening, {"player_rpm": 0.17}).reason == "danger", "Real dangerous reserve contributes to intensity")
	check(Music.adaptive_targets(opening, {"redline_active": true, "redline_heat": 0.7}).pressure >= 0.5, "Actual paid build escalation can intensify its groove")
	check(opening == before, "Music policy leaves its Run observation untouched")
	music.set_context("title"); tick(music, 3.0)
	check(music.music_snapshot().gains[0] > 0.90, "Title hook fades into its own composition")
	music.set_context("workshop"); tick(music, 6.0)
	check(music.music_snapshot().gains[1] > 0.99 and music.music_snapshot().gains[0] < 0.09, "Workshop crossfades to its lighter arrangement")
	music.set_context("run"); music.observe_run(opening); tick(music, 4.0)
	check(music.music_snapshot().targets[2] == 1.0 and music.music_snapshot().targets[3] == 0.0, "New Run starts with its actual baseline arrangement")
	music.observe_run(high); tick(music, 2.0)
	check(music.music_snapshot().targets[4] == 1.0, "Boss buildup changes gains without replacing playback")
	var events: int = music.music_snapshot().events.size()
	for index: int in range(120):
		music.observe_run(opening if index % 2 == 0 else high)
		music.advance_presentation(1.0 / 60.0)
	check(music.music_snapshot().targets[4] == 1.0 and music.music_snapshot().events.size() == events, "Rapid pressure toggles cannot thrash the musical plateaus")
	music.observe_run(opening); tick(music, 3.0)
	check(music.music_snapshot().targets[4] == 0.0, "A sustained real release returns to baseline after hysteresis")
	music.set_paused(true)
	check(is_equal_approx(music.music_snapshot().targets[2], 0.35), "Pause/draft subdues the Run without stopping its shared chronology")
	music.set_paused(false)
	var master: float = AudioServer.get_bus_volume_db(0)
	music.apply_settings({"music_volume": 0.0})
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")) and AudioServer.get_bus_volume_db(0) == master, "Music mute leaves Master/SFX settings untouched")
	music.apply_settings({"music_volume": 0.55}); music.notify_cue("low_rpm"); tick(music, 0.01)
	var duck: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
	tick(music, 0.5)
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")) > duck + 10.0, "Critical low-RPM cue gets a temporary clear window and music recovers")
	check(music.music_snapshot().transport_starts == 0 and not music.music_snapshot().playing, "No native WAV transport starts in headless/probe-default configuration")

func mixer(music: Node) -> void:
	var stream: AudioStreamSynchronized = music.synchronized_stream()
	check(music.music_snapshot().asset_errors.is_empty(), "All five runtime stems import as exact stereo PCM grids")
	var duration: float = stream.get_length()
	var refs: Array[AudioStreamPlayback] = []
	for index: int in range(5):
		var wav: AudioStreamWAV = stream.get_sync_stream(index)
		check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_begin == 0 and wav.loop_end == 1117091 and wav.mix_rate == 32000 and wav.stereo and wav.data.size() == 4468364, "Every imported stem keeps the identical exact sample grid and native loop")
		var ref: AudioStreamPlayback = wav.instantiate_playback()
		ref.start(duration - 0.025)
		refs.append(ref)
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	playback.start(duration - 0.025)
	var maximum_error: float = 0.0
	var energy: float = 0.0
	for profile: Array in [[1.0,0.0,0.0,0.0,0.0],[0.0,0.0,1.0,0.0,0.0],[0.0,0.0,1.0,0.65,1.0]]:
		for index: int in range(5): stream.set_sync_stream_volume(index, linear_to_db(maxf(0.0001, float(profile[index]))))
		var actual: PackedVector2Array = playback.mix_audio(1.0, 4096)
		var separate: Array[PackedVector2Array] = []
		for ref: AudioStreamPlayback in refs: separate.append(ref.mix_audio(1.0, 4096))
		for frame: int in range(actual.size()):
			var expected: Vector2 = Vector2.ZERO
			for index: int in range(5): expected += separate[index][frame] * maxf(0.0001, float(profile[index]))
			maximum_error = maxf(maximum_error, actual[frame].distance_to(expected))
			energy += actual[frame].length_squared()
	check(maximum_error < 0.00001, "Actual synchronized mixing exactly follows five uninterrupted reference stem cursors while gains change")
	check(energy > 0.01, "Engine mixer produces actual audible non-silent music samples")
	# WAV's native get_loop_count() intentionally returns zero in Godot. The
	# real playback cursor wrapping from34.88s tobelow1s proves this boundary.
	var wrapped_position: float = playback.get_playback_position()
	check(wrapped_position > 0.05 and wrapped_position < 1.0, "Actual imported synchronized playback cursor crosses the common seamless loop boundary")
	for ref: AudioStreamPlayback in refs:
		check(absf(ref.get_playback_position() - wrapped_position) < 0.000002, "Every layer wraps to the same actual engine cursor")
		ref.stop()
	playback.stop()
	measurements.engine_mixer = {"maximum_reference_error": maximum_error, "energy": energy, "duration": duration, "native_stems": 5, "mixed_frames": 12288, "wrapped_position": wrapped_position}

func combat_parity(music: Node) -> void:
	var shown: Node2D = Battle.new(); var control: Node2D = Battle.new()
	root.add_child(shown); root.add_child(control)
	shown.set_physics_process(false); control.set_physics_process(false)
	var build: Dictionary = {"blade": "smash", "ratchet": "low", "bit": "flat"}
	var descriptor: Dictionary = Encounters.for_run_event(1, 771)
	shown.begin_run(build, descriptor, 771); control.begin_run(build, descriptor, 771)
	music.set_context("run")
	for frame: int in range(900):
		var direction: Vector2 = Vector2(cos(float(frame) / 90.0), sin(float(frame) / 90.0)) * 0.7
		shown.test_step(1.0 / 60.0, direction, frame % 270 == 0, frame % 200 > 180)
		control.test_step(1.0 / 60.0, direction, frame % 270 == 0, frame % 200 > 180)
		music.observe_run(shown.continuous.snapshot(), {"player_rpm": shown.player_entity().rpm})
		music.advance_presentation(1.0 / 60.0)
		check(shown.snapshot() == control.snapshot() and shown.continuous.economy.snapshot() == control.continuous.economy.snapshot(), "Music observation cannot change exact real combat/RPM/outcomes")
		check(shown.continuous.director.rng.state == control.continuous.director.rng.state and shown._simulation_rng.state == control._simulation_rng.state and shown._cosmetic_rng.state == control._cosmetic_rng.state and shown.powers.events == control.powers.events, "Music consumes no combat/cosmetic/director RNG or power events")
	shown.free(); control.free()

func run() -> void:
	var music: Node = Music.new()
	root.add_child(music); music.set_process(false)
	policy(music); mixer(music); combat_parity(music)
	measurements.final = music.music_snapshot()
	music.free()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			assert(file != null)
			file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}, "\t")); file.close()
	print("MUSIC_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
