extends SceneTree
## Explicit audio review fixture, never gameplay footage. Real native players,
## production SFX and buses are recorded through Godot's Master bus. Ordinary
## headless suites never opt in and therefore start no native WAV playback.
const Music = preload("res://scripts/music.gd")
const Sound = preload("res://scripts/sound.gd")
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); push_error(text)

func run() -> void:
	var allowed: bool = false
	var report: String = ""
	var recording_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--allow-native-audio": allowed = true
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
		if arg.begins_with("--recording="): recording_path = arg.trim_prefix("--recording=")
	if not allowed:
		print("MUSIC_NATIVE_SKIPPED requires explicit --allow-native-audio")
		quit(0); return
	if report.is_empty() or recording_path.is_empty() or AudioServer.get_driver_name() == "Dummy":
		push_error("Explicit review requires a real audio driver and external report/recording paths")
		quit(2); return
	var music: Node = Music.new()
	music.configure_playback(true)
	root.add_child(music)
	var sound: Node = Sound.new()
	root.add_child(sound)
	sound.apply_settings({"volume": 0.65, "sfx_volume": 1.0, "muted": false})
	music.apply_settings({"music_volume": 0.55})
	var recorder: AudioEffectRecord = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var slot: int = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)
	var rows: Array[Dictionary] = []
	for context: String in ["title", "workshop", "run", "boss", "pause"]:
		print("MUSIC_NATIVE_STAGE ", context)
		music.set_context("run" if context in ["boss", "pause"] else context)
		music.set_paused(context == "pause")
		if context == "run": music.observe_run({"census": {"pressure": 2.6}, "limits": {"tier": 0}})
		if context == "boss": music.observe_run({"census": {"pressure": 13.0, "bosses": 1, "elites": 1}, "limits": {"tier": 4}})
		await create_timer(2.0).timeout
		if context == "run": sound.play_sound("heavy"); music.notify_cue("heavy")
		if context == "boss": sound.play_sound("low_rpm"); music.notify_cue("low_rpm")
		await create_timer(1.0).timeout
		var snap: Dictionary = music.music_snapshot()
		check(snap.playing and snap.transport_starts == 1 and snap.position > 0.1, "Real native transport stays alive without restart through " + context)
		rows.append(snap)
	recorder.set_recording_active(false)
	var recording: AudioStreamWAV = recorder.get_recording()
	check(recording != null and recording.data.size() > 100000, "Actual native bus recording contains sustained PCM")
	var peak: float = 0.0
	var energy: float = 0.0
	var count: int = 0
	if recording != null:
		var pcm: PackedByteArray = recording.data
		for offset: int in range(0, pcm.size(), 2):
			var value: float = float(pcm.decode_s16(offset)) / 32767.0
			peak = maxf(peak, absf(value)); energy += value * value; count += 1
		check(peak > 0.05 and peak < 0.99 and energy > 0.1, "Actual native Music/SFX mix is non-silent with clipping headroom")
		check(recording.save_to_wav(recording_path) == OK, "Actual native review PCM saves outside runtime/source art")
	AudioServer.remove_bus_effect(0, slot)
	music.configure_playback(false); music.free(); sound.free()
	await create_timer(0.10).timeout
	var file: FileAccess = FileAccess.open(report, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "audio_driver": AudioServer.get_driver_name(), "recording": recording_path,
		"peak": peak, "rms": sqrt(energy / maxf(1.0, float(count))), "states": rows,
		"fixture_policy": "Explicit native audio review of production controllers/buses; controlled observation dictionaries test arrangements and real SFX ducking, not gameplay. Recording is Master-bus PCM before its final Master-volume fader. No collection/preferences opened or combat hosted."}, "\t")); file.close()
	print("MUSIC_NATIVE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
