extends "res://tests/test_parts_package.gd"
## Reuse accepted compiled catalogue/beast/music/gating coverage under 003A QA,
## then verify actual packet/economy resource reports against source bytes.
const PacketEconomyModel = preload("res://scripts/packet_economy.gd")
var packet_assets_output: String = ""

func _game(path: String, catalogue: bool, report: String = "", report_requested: bool = false) -> QuietMain:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = path
	game.qa_task_id = "003A"
	game.qa_catalogue_requested = catalogue
	game.qa_assets_report = report
	game.qa_assets_report_requested = report_requested
	root.add_child(game)
	game.set_process(false)
	game.battle.set_physics_process(false)
	return game

func _fingerprint(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _visible_pixels(path: String) -> String:
	var image: Image = Image.new()
	var error: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	check(error == OK and not image.is_empty(), "Source runtime PNG decodes for independent visible-pixel comparison: " + path)
	if error != OK or image.is_empty(): return ""
	image.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = image.get_data()
	for offset: int in range(0, bytes.size(), 4):
		if bytes[offset + 3] == 0:
			for channel: int in range(3): bytes[offset + channel] = 0
	return _fingerprint(bytes)

func _test_packet_assets() -> void:
	packet_assets_output = qa_manifests.path_join("003a_packet_package_%d_%d_assets.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	check(not FileAccess.file_exists(packet_assets_output), "New asset report never overwrites prior evidence")
	var result: Dictionary = Probe.inspect(packet_assets_output)
	check(bool(result.get("ok", false)) and int(result.get("textures", 0)) == 42, "Extended production inspection preserves all accepted catalogue assets")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(packet_assets_output))
	check(parsed is Dictionary, "Extended real-resource report is valid JSON")
	if not parsed is Dictionary: return
	var report: Dictionary = parsed
	check(report.failures == [] and report.read_only_asset_inspection, "Extended asset inspection reports read-only success")
	var texture_rows: Array = report.get("packet_textures", [])
	check(texture_rows.size() == 3, "Actual production probe inspects both packet atlases and native bench mat")
	var texture_kinds: Array[String] = []
	for row: Dictionary in texture_rows:
		var kind: String = str(row.kind)
		texture_kinds.append(kind)
		var expected_path: String = Probe.PACKET_ART_ROOT + kind + ".png"
		var expected_json: String = FileAccess.get_file_as_string(Probe.PACKET_ART_ROOT + kind + ".json")
		var metadata: Dictionary = JSON.parse_string(expected_json)
		check(row.path == expected_path and row.metadata_path == Probe.PACKET_ART_ROOT + kind + ".json", "Packet report records actual runtime resource paths: " + kind)
		check(bool(row.valid) and bool(row.visible_pixels) and bool(row.transparent_rgb_normalized), "Packaged-family texture loads visible native pixels: " + kind)
		check(str(report.packet_json.get(kind, "")) == expected_json, "Report includes exact production packet metadata: " + kind)
		for field: String in ["cell", "pivot", "tags", "durations_ms", "columns", "frame_count"]:
			check(row[field] == metadata[field], "Imported packet report preserves saved metadata " + kind + "/" + field)
		check(str(row.rgba_sha256).length() == 64 and str(row.visible_rgba_sha256) == _visible_pixels(expected_path), "Actual imported packet pixels match authored runtime PNG: " + kind)
	for kind: String in ["packet", "reclaimed_packet", "reveal_mat"]:
		check(texture_kinds.count(kind) == 1, "Every physical packet-family runtime appears exactly once: " + kind)
	var audio_json: String = FileAccess.get_file_as_string(Probe.PACKET_AUDIO_MANIFEST)
	check(str(report.get("packet_audio_json", "")) == audio_json, "Probe preserves actual finite-fx PCM manifest")
	var manifest: Dictionary = JSON.parse_string(audio_json)
	var audio_rows: Array = report.get("packet_audio", [])
	check(audio_rows.size() == 8, "Probe inspects all eight original packet foley cues")
	var audio_kinds: Array[String] = []
	for row: Dictionary in audio_rows:
		var kind: String = str(row.kind)
		audio_kinds.append(kind)
		var expected_path: String = Probe.PACKET_AUDIO_ROOT + kind + ".wav"
		var source_file: PackedByteArray = FileAccess.get_file_as_bytes(expected_path)
		check(source_file.slice(0, 4).get_string_from_ascii() == "RIFF" and source_file.slice(36, 40).get_string_from_ascii() == "data", "Original finite cue uses reproducible standard PCM WAV container: " + kind)
		var source_pcm: PackedByteArray = source_file.slice(44)
		check(row.path == expected_path and bool(row.valid) and not bool(row.stereo) and int(row.channels) == 1, "Production cue reports real mono audio: " + kind)
		check(int(row.format) == AudioStreamWAV.FORMAT_16_BITS and int(row.loop_mode) == AudioStreamWAV.LOOP_DISABLED and int(row.mix_rate) == 32000, "Actual cue report preserves finite 16-bit/32k PCM import: " + kind)
		check(int(row.pcm_frames) == int(manifest.cues[kind].pcm_frames) and source_pcm.size() == int(row.pcm_frames) * 2, "Actual cue retains exact authored PCM frame count: " + kind)
		check(str(row.pcm_sha256) == str(manifest.cues[kind].pcm_sha256) and str(row.pcm_sha256) == _fingerprint(source_pcm), "Actual imported PCM matches source WAV bytes and frozen manifest: " + kind)
	for kind: String in manifest.cues:
		check(audio_kinds.count(kind) == 1, "Each original cue appears once in package evidence: " + kind)
	check(str(report.get("economy_json", "")) == FileAccess.get_file_as_string(PacketEconomyModel.DATA_PATH), "Report preserves exact production packet economy JSON")
	check(JSON.stringify(report.get("economy_config", {})) == JSON.stringify(PacketEconomyModel.config()), "Compiled config matches saved production economy data")
	check(JSON.stringify(report.get("economy_odds", {})) == JSON.stringify(PacketEconomyModel.rarity_odds("standard")), "Package reports actual production-derived per-slot odds and guarantee rules")
	check(report.get("economy_validation_errors", []) == [], "Compiled package economy passes production validation without changing state")

func _run() -> void:
	root.size = Vector2i(640, 360)
	var project: String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var qa_root: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa_root.is_empty(): qa_root = project.get_base_dir().path_join("GyroBrothers-QA")
	qa_temp = qa_root.path_join("003A/temp")
	qa_manifests = qa_root.path_join("003A/manifests")
	DirAccess.make_dir_recursive_absolute(qa_temp)
	DirAccess.make_dir_recursive_absolute(qa_manifests)
	for path: String in ["user://collection.json", "user://collection.json.bak", "user://prototype.cfg", "user://last_run_director.json"]:
		real_before[path] = _snapshot(path)
	await _test_default_boot()
	await _test_valid_probe()
	await _test_refused_probe()
	_test_packet_assets()
	for path: String in real_before:
		check(_snapshot(path) == real_before[path], "Player collection, backup, preferences and Run diagnostic stay byte-identical under extended package inspection")
	for path: String in files:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var output: FileAccess = FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			assert(output != null)
			output.store_string(JSON.stringify({"checks":checks, "failures":failures, "asset_report":packet_assets_output, "accepted_package_coverage_reused":true, "qa_task":"003A"}, "\t"))
			output.close()
	print("PACKET_PACKAGE_TEST_%s checks=%d failures=%d assets=%s" % ["PASS" if failures == 0 else "FAIL", checks, failures, packet_assets_output])
	quit(1 if failures else 0)
