extends RefCounted
## Read-only catalogue/texture inspection for exported release QA. Main validates
## the external report destination before calling; existing files are refused.
const Catalog = preload("res://scripts/parts.gd")
const FEEDBACK_MANIFEST: String = "res://assets/powers/feedback_002c5_2/manifest.json"
const BEAST_MANIFEST: String = "res://assets/powers/beasts_002c5_2/manifest.json"
const MUSIC_MANIFEST: String = "res://assets/audio/music/manifest.json"

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
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null: return {"ok":false, "error":"Cannot write the external package asset report."}
	file.store_string(JSON.stringify({"catalogue_sha256":FileAccess.get_sha256(Catalog.DATA_PATH), "catalogue_json":catalogue_json,
		"textures":records, "feedback_json":feedback_json, "feedback_textures":feedback_records,
		"beast_json":beast_json, "beast_textures":beast_records,
		"music_json":music_json, "music_stems":music_records,
		"failures":failures, "read_only_asset_inspection":true}, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK: return {"ok":false, "error":"The external package asset report could not be written completely."}
	if not failures.is_empty(): return {"ok":false, "error":"Packaged textures failed validation: " + str(failures)}
	return {"ok":true, "textures":records.size(), "report":output}

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
