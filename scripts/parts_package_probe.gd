extends RefCounted
## Read-only catalogue/texture inspection for exported release QA. Main validates
## the external report destination before calling; existing files are refused.
const Catalog = preload("res://scripts/parts.gd")

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
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null: return {"ok":false, "error":"Cannot write the external package asset report."}
	file.store_string(JSON.stringify({"catalogue_sha256":FileAccess.get_sha256(Catalog.DATA_PATH), "catalogue_json":catalogue_json,
		"textures":records, "failures":failures, "read_only_asset_inspection":true}, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK: return {"ok":false, "error":"The external package asset report could not be written completely."}
	if not failures.is_empty(): return {"ok":false, "error":"Packaged textures failed validation: " + str(failures)}
	return {"ok":true, "textures":records.size(), "report":output}
