extends RefCounted
## Read-only catalogue/texture inspection for exported release QA. Main validates
## the external report destination before calling; existing files are refused.
const Catalog = preload("res://scripts/parts.gd")
const FEEDBACK_MANIFEST: String = "res://assets/powers/feedback_002c5_2/manifest.json"
const BEAST_MANIFEST: String = "res://assets/powers/beasts_002c5_2/manifest.json"
const MUSIC_MANIFEST: String = "res://assets/audio/music/manifest.json"
const PacketEconomyModel = preload("res://scripts/packet_economy.gd")
const PACKET_ART_ROOT: String = "res://assets/ui/shop_003a/"
const PACKET_AUDIO_ROOT: String = "res://assets/audio/shop_003a/"
const PACKET_AUDIO_MANIFEST: String = PACKET_AUDIO_ROOT + "manifest.json"
const UI_POLISH_ROOT: String = "res://assets/ui/human_feedback003a/"
const UI_POLISH_LAYOUT: Dictionary = {
	"metal_plate":{"cell":[32, 32], "frames":3},
	"inspection_frame":{"cell":[32, 32], "frames":1},
	"button_caps":{"cell":[24, 24], "frames":6},
	"merchant":{"cell":[48, 64], "frames":14},
	"merchant_fixture":{"cell":[192, 64], "frames":1},
	"credit_chip":{"cell":[16, 16], "frames":4},
	"preview_station":{"cell":[160, 56], "frames":1}
}

static func inspect(output: String) -> Dictionary:
	if output.is_empty() or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output):
		return {"ok":false, "error":"Package asset report already exists or has no destination."}
	var catalogue_json: String = FileAccess.get_file_as_string(Catalog.DATA_PATH)
	var data: Variant = JSON.parse_string(catalogue_json)
	if not data is Dictionary or int(data.get("schema_version", 0)) != 1:
		return {"ok":false, "error":"The package does not contain the expected catalogue JSON."}
	var records: Array[Dictionary] = []
	var failures: Array[String] = []
	for category: String in ["blade", "ratchet", "bit"]:
		for id: String in Catalog.PARTS[category]:
			var part: Dictionary = Catalog.PARTS[category][id]
			var paths: Array[String] = [str(part.visual.sprite)]
			if category == "blade": paths.append(str(part.visual.spin))
			for path: String in paths:
				var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
				var spin: bool = path == str(part.visual.get("spin", ""))
				var expected: Vector2i = Vector2i(384 if spin else 48, 48)
				var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
				var visible: bool = false
				if texture != null:
					var pixels: Image = texture.get_image()
					visible = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
				var valid: bool = texture != null and size == expected and visible
				records.append({"part_id":category + ":" + id, "path":path, "size":[size.x, size.y], "visible_pixels":visible, "valid":valid})
				if not valid: failures.append(path)
	# Inspect the new floor sheets through the compiled release probe as well:
	# the editor loading them does not prove a fresh Windows package contains them.
	var feedback_json: String = FileAccess.get_file_as_string(FEEDBACK_MANIFEST)
	var feedback: Variant = JSON.parse_string(feedback_json)
	var feedback_records: Array[Dictionary] = []
	if not feedback is Dictionary or not feedback.get("effects", {}) is Dictionary:
		failures.append(FEEDBACK_MANIFEST)
	else:
		for kind: String in ["centre", "impact", "pickup"]:
			var meta: Dictionary = feedback.effects.get(kind, {})
			var path: String = str(meta.get("texture", ""))
			var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
			var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
			var pixels: Image = texture.get_image() if texture != null else null
			var valid: bool = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
			var fingerprint: String = ""
			var visible_fingerprint: String = ""
			if valid:
				pixels.convert(Image.FORMAT_RGBA8)
				var decoded: PackedByteArray = pixels.get_data()
				var hash: HashingContext = HashingContext.new()
				hash.start(HashingContext.HASH_SHA256)
				hash.update(decoded)
				fingerprint = hash.finish().hex_encode()
				# Godot pads RGB behind fully transparent pixels at import. Those
				# bytes never render; every alpha and every visible RGB must match.
				for offset: int in range(0,decoded.size(),4):
					if decoded[offset+3] == 0:
						for channel: int in range(3): decoded[offset+channel] = 0
				hash.start(HashingContext.HASH_SHA256)
				hash.update(decoded)
				visible_fingerprint = hash.finish().hex_encode()
			feedback_records.append({"kind":kind,"path":path,"size":[size.x,size.y],"visible_pixels":valid,"valid":valid,
				"rgba_sha256":fingerprint,"visible_rgba_sha256":visible_fingerprint,"transparent_rgb_normalized":true})
			if not valid: failures.append(path)
	var beast_json: String = FileAccess.get_file_as_string(BEAST_MANIFEST)
	var beasts: Variant = JSON.parse_string(beast_json)
	var beast_records: Array[Dictionary] = []
	if not beasts is Dictionary or not beasts.get("effects", {}) is Dictionary:
		failures.append(BEAST_MANIFEST)
	else:
		for kind: String in ["black_arrow", "iron_bull", "stone_tortoise", "coil_dragon"]:
			var record: Dictionary = _inspect_beast_sheet(kind, beasts.effects.get(kind, {}))
			beast_records.append(record)
			if not bool(record.valid): failures.append(str(record.path))
	var music_json: String = FileAccess.get_file_as_string(MUSIC_MANIFEST)
	var music: Variant = JSON.parse_string(music_json)
	var music_records: Array[Dictionary] = []
	if not music is Dictionary or not music.get("stems", {}) is Dictionary:
		failures.append(MUSIC_MANIFEST)
	else:
		for kind: String in ["title", "workshop", "run_base", "run_pressure", "run_boss"]:
			var path: String = "res://assets/audio/music/" + kind + ".wav"
			var sample: AudioStreamWAV = (load(path) as AudioStreamWAV) if ResourceLoader.exists(path) else null
			var valid: bool = sample != null and sample.format == AudioStreamWAV.FORMAT_16_BITS and sample.stereo and sample.mix_rate == 32000
			var pcm_data: PackedByteArray = sample.data if sample != null else PackedByteArray()
			valid = valid and pcm_data.size() == int(music.grid.frames) * 4
			var hash: HashingContext = HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(pcm_data)
			music_records.append({"kind":kind,"path":path,"valid":valid,"pcm_frames":pcm_data.size() / 4,"mix_rate":sample.mix_rate if sample != null else 0,"pcm_sha256":hash.finish().hex_encode()})
			if not valid: failures.append(path)
	# These are actual compiled/imported resources, not a receipt/UI fixture.
	# Exact source parity is checked by the external verifier from these hashes.
	var packet_json: Dictionary = {}
	var packet_records: Array[Dictionary] = []
	for kind: String in ["packet", "reclaimed_packet", "reveal_mat"]:
		var metadata_path: String = PACKET_ART_ROOT + kind + ".json"
		var source_json: String = FileAccess.get_file_as_string(metadata_path)
		packet_json[kind] = source_json
		var parsed: Variant = JSON.parse_string(source_json)
		var record: Dictionary = _inspect_packet_sheet(kind, parsed if parsed is Dictionary else {})
		packet_records.append(record)
		if not bool(record.valid): failures.append(str(record.path))
	var packet_audio_json: String = FileAccess.get_file_as_string(PACKET_AUDIO_MANIFEST)
	var packet_audio_manifest: Variant = JSON.parse_string(packet_audio_json)
	var packet_audio_records: Array[Dictionary] = []
	if not packet_audio_manifest is Dictionary or not packet_audio_manifest.get("cues", {}) is Dictionary:
		failures.append(PACKET_AUDIO_MANIFEST)
	else:
		for kind: String in ["packet_land", "packet_crinkle", "packet_tear", "packet_spill", "packet_clink", "packet_new", "packet_rare", "packet_recycle"]:
			var record: Dictionary = _inspect_packet_audio(kind, packet_audio_manifest.cues.get(kind, {}))
			packet_audio_records.append(record)
			if not bool(record.valid): failures.append(str(record.path))
	var economy_json: String = FileAccess.get_file_as_string(PacketEconomyModel.DATA_PATH)
	var economy_validation_errors: Array[String] = PacketEconomyModel.validate_config()
	var economy_odds: Dictionary = PacketEconomyModel.rarity_odds("standard")
	if not economy_validation_errors.is_empty() or economy_odds.is_empty(): failures.append(PacketEconomyModel.DATA_PATH)
	var ui_polish_json: Dictionary = {}
	var ui_polish_records: Array[Dictionary] = []
	for kind: String in UI_POLISH_LAYOUT:
		var source_json: String = FileAccess.get_file_as_string(UI_POLISH_ROOT + kind + ".json")
		ui_polish_json[kind] = source_json
		var parsed: Variant = JSON.parse_string(source_json)
		var record: Dictionary = _inspect_ui_polish_sheet(kind, parsed if parsed is Dictionary else {})
		ui_polish_records.append(record)
		if not bool(record.valid): failures.append(str(record.path))
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null: return {"ok":false, "error":"Cannot write the external package asset report."}
	file.store_string(JSON.stringify({"catalogue_sha256":FileAccess.get_sha256(Catalog.DATA_PATH), "catalogue_json":catalogue_json,
		"textures":records, "feedback_json":feedback_json, "feedback_textures":feedback_records,
		"beast_json":beast_json, "beast_textures":beast_records,
		"music_json":music_json, "music_stems":music_records,
		"packet_json":packet_json, "packet_textures":packet_records,
		"packet_audio_json":packet_audio_json, "packet_audio":packet_audio_records,
		"economy_json":economy_json, "economy_config":PacketEconomyModel.config(),
		"economy_odds":economy_odds, "economy_validation_errors":economy_validation_errors,
		"ui_polish_json":ui_polish_json, "ui_polish_textures":ui_polish_records,
		"failures":failures, "read_only_asset_inspection":true}, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK: return {"ok":false, "error":"The external package asset report could not be written completely."}
	if not failures.is_empty(): return {"ok":false, "error":"Packaged textures failed validation: " + str(failures)}
	return {"ok":true, "textures":records.size(), "report":output}

static func _inspect_ui_polish_sheet(kind: String, meta: Dictionary) -> Dictionary:
	var path: String = UI_POLISH_ROOT + kind + ".png"
	var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
	var pixels: Image = texture.get_image() if texture != null else null
	var visible: bool = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
	var cell: Array = meta.get("cell", [])
	var pivot: Array = meta.get("pivot", [])
	var durations: Array = meta.get("durations_ms", [])
	var layers: Array = meta.get("layers", [])
	var tags: Dictionary = meta.get("tags", {})
	var expected: Dictionary = UI_POLISH_LAYOUT.get(kind, {})
	var columns: int = int(meta.get("columns", 0))
	var count: int = int(meta.get("frame_count", 0))
	var expected_cell: Array = expected.get("cell", [])
	var valid: bool = visible and cell.size() == 2 and expected_cell.size() == 2 and pivot.size() == 2
	if valid: valid = Vector2i(int(cell[0]), int(cell[1])) == Vector2i(int(expected_cell[0]), int(expected_cell[1]))
	valid = valid and count == int(expected.get("frames", 0)) and columns == count
	if valid:
		valid = size == Vector2i(int(cell[0]) * count, int(cell[1]))
		valid = valid and int(pivot[0]) >= 0 and int(pivot[0]) <= int(cell[0]) and int(pivot[1]) >= 0 and int(pivot[1]) <= int(cell[1])
	valid = valid and str(meta.get("texture", "")) == kind + ".png" and str(meta.get("filter", "")) == "nearest" and bool(meta.get("native_pixels", false))
	valid = valid and durations.size() == count and not layers.is_empty() and not tags.is_empty()
	for duration: Variant in durations: valid = valid and float(duration) > 0.0
	for tag: String in tags:
		var bounds: Dictionary = tags[tag]
		valid = valid and int(bounds.get("from", -1)) >= 0 and int(bounds.get("to", -1)) >= int(bounds.get("from", -1)) and int(bounds.get("to", -1)) < count
	var fingerprint: String = ""
	if visible:
		if pixels.is_compressed(): pixels.decompress()
		pixels.convert(Image.FORMAT_RGBA8)
		var decoded: PackedByteArray = pixels.get_data()
		for offset: int in range(0, decoded.size(), 4):
			if decoded[offset + 3] == 0:
				for channel: int in range(3): decoded[offset + channel] = 0
		fingerprint = _digest(decoded)
	return {"kind":kind, "path":path, "metadata_path":UI_POLISH_ROOT + kind + ".json",
		"valid":valid, "visible_pixels":visible, "size":[size.x, size.y], "cell":cell,
		"pivot":pivot, "tags":tags, "durations_ms":durations, "layers":layers,
		"columns":columns, "frame_count":count, "visible_rgba_sha256":fingerprint,
		"transparent_rgb_normalized":true}

static func _inspect_beast_sheet(kind: String, meta: Dictionary) -> Dictionary:
	var path: String = str(meta.get("texture", ""))
	var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
	var pixels: Image = texture.get_image() if texture != null else null
	var cell: Array = meta.get("cell", [])
	var columns: int = int(meta.get("columns", 0))
	var frames: int = int(meta.get("frame_count", 0))
	var valid: bool = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
	valid = valid and cell.size() == 2 and int(cell[0]) == 128 and int(cell[1]) == 128 and columns > 0 and frames >= 20
	if valid: valid = size == Vector2i(columns * 128, ceili(float(frames) / float(columns)) * 128)
	var fingerprint: String = ""
	if valid:
		pixels.convert(Image.FORMAT_RGBA8)
		var decoded: PackedByteArray = pixels.get_data()
		for offset: int in range(0, decoded.size(), 4):
			if decoded[offset + 3] == 0:
				for channel: int in range(3): decoded[offset + channel] = 0
		var hash: HashingContext = HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(decoded)
		fingerprint = hash.finish().hex_encode()
	return {"kind":kind, "path":path, "size":[size.x, size.y], "visible_pixels":valid, "valid":valid,
		"visible_rgba_sha256":fingerprint, "transparent_rgb_normalized":true}

static func _digest(bytes: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func _inspect_packet_sheet(kind: String, meta: Dictionary) -> Dictionary:
	var path: String = PACKET_ART_ROOT + kind + ".png"
	var texture: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
	var pixels: Image = texture.get_image() if texture != null else null
	var visible: bool = pixels != null and not pixels.is_empty() and not pixels.is_invisible()
	var cell: Array = meta.get("cell", [])
	var pivot: Array = meta.get("pivot", [])
	var durations: Array = meta.get("durations_ms", [])
	var layers: Array = meta.get("layers", [])
	var tags: Dictionary = meta.get("tags", {})
	var expected_cell: Vector2i = Vector2i(272, 134) if kind == "reveal_mat" else Vector2i(96, 96)
	var expected_pivot: Vector2i = Vector2i(136, 124) if kind == "reveal_mat" else Vector2i(48, 86)
	var expected_frames: int = 1 if kind == "reveal_mat" else 13
	var columns: int = int(meta.get("columns", 0))
	var count: int = int(meta.get("frame_count", 0))
	var valid: bool = visible and cell.size() == 2 and pivot.size() == 2
	if valid:
		valid = Vector2i(int(cell[0]), int(cell[1])) == expected_cell and Vector2i(int(pivot[0]), int(pivot[1])) == expected_pivot
	valid = valid and count == expected_frames and columns == expected_frames and size == Vector2i(expected_cell.x * expected_frames, expected_cell.y)
	valid = valid and str(meta.get("texture", "")) == kind + ".png" and str(meta.get("filter", "")) == "nearest" and bool(meta.get("native_pixels", false))
	valid = valid and durations.size() == expected_frames and layers.size() == (3 if kind == "reveal_mat" else 6)
	var required_tags: Array = ["REVEAL_MAT"] if kind == "reveal_mat" else ["SEALED", "CRINKLE", "TEAR_START", "TEAR_OPEN", "SPILL", "EMPTY_PACKET"]
	valid = valid and tags.size() == required_tags.size()
	for tag: String in required_tags:
		valid = valid and tags.has(tag)
	for duration: Variant in durations:
		valid = valid and float(duration) > 0.0
	var rgba_fingerprint: String = ""
	var visible_fingerprint: String = ""
	if visible:
		if pixels.is_compressed(): pixels.decompress()
		pixels.convert(Image.FORMAT_RGBA8)
		var decoded: PackedByteArray = pixels.get_data()
		rgba_fingerprint = _digest(decoded)
		# Normalize only RGB behind alpha-zero pixels, matching beast/feedback
		# package verification while preserving every alpha and visible RGB byte.
		for offset: int in range(0, decoded.size(), 4):
			if decoded[offset + 3] == 0:
				for channel: int in range(3): decoded[offset + channel] = 0
		visible_fingerprint = _digest(decoded)
	return {"kind":kind, "path":path, "metadata_path":PACKET_ART_ROOT + kind + ".json",
		"valid":valid, "visible_pixels":visible, "size":[size.x, size.y],
		"cell":cell, "pivot":pivot, "tags":tags, "durations_ms":durations, "columns":columns, "frame_count":count,
		"rgba_sha256":rgba_fingerprint, "visible_rgba_sha256":visible_fingerprint, "transparent_rgb_normalized":true}

static func _inspect_packet_audio(kind: String, meta: Dictionary) -> Dictionary:
	var path: String = PACKET_AUDIO_ROOT + kind + ".wav"
	var sample: AudioStreamWAV = (load(path) as AudioStreamWAV) if ResourceLoader.exists(path) else null
	var pcm: PackedByteArray = sample.data if sample != null else PackedByteArray()
	var fingerprint: String = _digest(pcm)
	var valid: bool = sample != null and sample.format == AudioStreamWAV.FORMAT_16_BITS and not sample.stereo and sample.mix_rate == 32000 and sample.loop_mode == AudioStreamWAV.LOOP_DISABLED
	valid = valid and str(meta.get("file", "")) == kind + ".wav" and int(meta.get("pcm_frames", 0)) > 0
	valid = valid and pcm.size() == int(meta.get("pcm_frames", 0)) * 2 and fingerprint == str(meta.get("pcm_sha256", ""))
	return {"kind":kind, "path":path, "valid":valid, "mix_rate":sample.mix_rate if sample != null else 0,
		"channels":(2 if sample.stereo else 1) if sample != null else 0, "stereo":sample.stereo if sample != null else false,
		"format":sample.format if sample != null else -1, "loop_mode":sample.loop_mode if sample != null else -1,
		"pcm_frames":pcm.size() / 2, "pcm_sha256":fingerprint}
