extends SceneTree
## Actual imported packet texture/PCM/SFX/music contracts. No save is opened,
## no game RNG runs and native playback remains disabled in this headless test.
const Sound = preload("res://scripts/sound.gd")
const Music = preload("res://scripts/music.gd")
const ART_ROOT: String = "res://assets/ui/shop_003a/"
const AUDIO_ROOT: String = "res://assets/audio/shop_003a/"
var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func digest(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func art() -> void:
	var art_rows: Array[Dictionary] = []
	for name: String in ["packet", "reclaimed_packet", "reveal_mat"]:
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART_ROOT + name + ".json"))
		var texture: Texture2D = load(ART_ROOT + name + ".png")
		check(texture != null, "Actual imported packet-family texture exists: " + name)
		if texture == null: continue
		var cell: Vector2i = Vector2i(int(metadata.cell[0]), int(metadata.cell[1]))
		var count: int = int(metadata.frame_count)
		check(texture.get_size() == Vector2(cell.x * count, cell.y), "Actual horizontal atlas agrees with native frame grid: " + name)
		check(metadata.native_pixels and metadata.filter == "nearest", "Native source metadata retains nearest output: " + name)
		check(FileAccess.file_exists(ART_ROOT + str(metadata.source)), "Declared editable Aseprite master exists: " + name)
		var pixels: Image = texture.get_image()
		if pixels.is_compressed(): pixels.decompress()
		var unique: Dictionary = {}
		for index: int in range(count):
			var frame: Image = pixels.get_region(Rect2i(index * cell.x, 0, cell.x, cell.y))
			check(not frame.is_invisible(), "Imported authored frame remains visible: %s/%d" % [name, index])
			unique[digest(frame.get_data())] = true
		check(unique.size() == count, "Actual imported poses are distinct: " + name)
		if name != "reveal_mat":
			check(cell == Vector2i(96, 96) and int(metadata.pivot[0]) == 48 and int(metadata.pivot[1]) == 86 and count == 13, "Native pouch dimensions/contact pivot survive export: " + name)
			var covered: Dictionary = {}
			for tag: String in ["SEALED", "CRINKLE", "TEAR_START", "TEAR_OPEN", "SPILL", "EMPTY_PACKET"]:
				check(metadata.tags.has(tag), "Required physical pouch state is exported: " + name + "/" + tag)
				if not metadata.tags.has(tag): continue
				for index: int in range(int(metadata.tags[tag].from), int(metadata.tags[tag].to) + 1):
					check(not covered.has(index) and int(metadata.durations_ms[index]) > 0, "Authored state has unambiguous positive timing: %s/%d" % [name, index])
					covered[index] = true
			check(covered.size() == count, "Every authored pose belongs to one required animation state: " + name)
			check(pixels.get_pixel(48, 28).a == 1.0 and pixels.get_pixel(2, 2).a == 0.0, "Sealed pouch is opaque while its exterior stays transparent: " + name)
		art_rows.append({"name":name, "imported_size":texture.get_size(), "unique_frames":unique.size(), "pivot":metadata.pivot})
	measurements.art = art_rows

func audio(sound: Node) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AUDIO_ROOT + "manifest.json"))
	var cues: Array[Dictionary] = []
	check(manifest.original and manifest.sample_rate == 32000 and manifest.channels == 1, "Packet manifest declares original finite mono PCM")
	for key: String in manifest.cues:
		var metadata: Dictionary = manifest.cues[key]
		check(Sound.SOUNDS.has(key), "Production SFX dispatcher registers real packet cue: " + key)
		var imported: AudioStreamWAV = load(AUDIO_ROOT + str(metadata.file))
		check(imported != null, "Actual Godot packet cue imports: " + key)
		if imported == null: continue
		check(imported.format == AudioStreamWAV.FORMAT_16_BITS and not imported.stereo and imported.mix_rate == 32000, "Imported packet cue remains exact mono16bit/32k PCM: " + key)
		check(imported.loop_mode == AudioStreamWAV.LOOP_DISABLED and imported.data.size() == int(metadata.pcm_frames) * 2, "Imported packet cue remains finite and keeps exact authored frame count: " + key)
		check(digest(imported.data) == str(metadata.pcm_sha256), "Actual imported cue bytes match frozen authored PCM: " + key)
		var playback: AudioStreamPlayback = imported.instantiate_playback()
		playback.start(0.0)
		var mix: PackedVector2Array = playback.mix_audio(1.0, int(metadata.pcm_frames))
		var peak: float = 0.0
		var energy: float = 0.0
		for sample: Vector2 in mix:
			peak = maxf(peak, absf(sample.x))
			energy += sample.length_squared()
		check(peak > 0.05 and peak < 0.70 and energy > 0.01, "Actual packet cue mixer is audible and unclipped: " + key)
		playback.stop()
		sound.audio_time += 1.0
		sound.play_sound(key)
		check(int(sound.audio_snapshot().played.get(key, 0)) == 1, "Real production SFX dispatcher starts each packet cue: " + key)
		var suppression: int = int(sound.audio_snapshot().suppressed)
		sound.play_sound(key)
		check(int(sound.audio_snapshot().played.get(key, 0)) == 1 and int(sound.audio_snapshot().suppressed) == suppression + 1, "Duplicate packet event is bounded by cue cooldown: " + key)
		var player: AudioStreamPlayer = sound.channels[sound.current]
		check(player.bus == "SFX" and player.volume_db <= -4.5 and player.pitch_scale == 1.0, "Packet cue retains original restrained mix on accepted SFX bus: " + key)
		cues.append({"key":key, "pcm_frames":metadata.pcm_frames, "actual_mixer_peak":peak, "energy":energy, "gain_db":player.volume_db})
	check(sound.channels.size() == 8, "Packet foley preserves accepted bounded channel pool")
	measurements.audio = cues

func music_policy(music: Node, sound: Node) -> void:
	music.set_context("workshop")
	for index: int in range(360): music.advance_presentation(1.0 / 60.0)
	var bus: int = AudioServer.get_bus_index("Music")
	var stream: AudioStreamSynchronized = music.synchronized_stream()
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	playback.start(1.0)
	var previous: float = playback.get_playback_position()
	var baseline: float = AudioServer.get_bus_volume_db(bus)
	for cue: String in ["packet_tear", "packet_rare"]:
		music.notify_cue(cue)
		music.advance_presentation(0.01)
		check(AudioServer.get_bus_volume_db(bus) < baseline - 1.0, "Physical packet cue clears temporary space above existing workshop music: " + cue)
		playback.mix_audio(1.0, 4096)
		check(playback.get_playback_position() > previous + 0.08, "Actual synchronized workshop mixer cursor continues across packet cue: " + cue)
		previous = playback.get_playback_position()
		for index: int in range(60): music.advance_presentation(1.0 / 60.0)
		check(is_equal_approx(AudioServer.get_bus_volume_db(bus), baseline), "Workshop music recovers its accepted gain after short packet cue: " + cue)
		check(music.music_snapshot().context == "workshop" and music.music_snapshot().transport_starts == 0 and music.synchronized_stream() == stream, "Packet cue preserves arrangement/resource and cannot start native transport in headless mode: " + cue)
	playback.stop()
	sound.apply_settings({"volume":0.65, "sfx_volume":0.0})
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "Accepted SFX mute includes packet cues")
	var master: float = AudioServer.get_bus_volume_db(0)
	music.apply_settings({"music_volume":0.0})
	check(AudioServer.is_bus_mute(bus) and AudioServer.get_bus_volume_db(0) == master, "Packet integration preserves independently muted Music/SFX buses")
	measurements.music = music.music_snapshot()

func run() -> void:
	var sound: Node = Sound.new()
	var music: Node = Music.new()
	root.add_child(sound)
	root.add_child(music)
	# The headless Dummy driver has no native sample transport. Exercise the
	# production dispatcher with engine stream mixing for this isolated test.
	for player: AudioStreamPlayer in sound.channels:
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	sound.set_process(false)
	music.set_process(false)
	art()
	audio(sound)
	music_policy(music, sound)
	await create_timer(0.80).timeout
	for player: AudioStreamPlayer in sound.channels: player.stop()
	sound.free()
	music.free()
	# The dummy audio driver's thread must consume queued player-stop commands
	# before SceneTree teardown, just as the native driver does during playback.
	await create_timer(0.12).timeout
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var output: FileAccess = FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			assert(output != null)
			output.store_string(JSON.stringify({"checks":checks, "failures":failures, "measurements":measurements}, "\t"))
			output.close()
	print("PACKET_ART_AUDIO_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
