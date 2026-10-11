extends RefCounted
## Inspect actual imported pixels in either platform's package.
const Art = preload("res://scripts/base_power_art.gd")
const Catalog = preload("res://scripts/run_powers.gd")
const MANIFEST: String = "res://assets/powers/base003a2/manifest.json"

static func inspect(compare_manifest: bool = true) -> Dictionary:
	var records: Array[Dictionary] = []
	var failures: Array[String] = []
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if compare_manifest else {}
	for group: String in ["cards", "icons"]:
		var path: String = "res://assets/powers/base003a2/" + group + ".svg"
		var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
		var pixels: Image = texture.get_image() if texture != null else null
		var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
		var valid: bool = pixels != null and not pixels.is_invisible() and size == (Vector2i(384,768) if group == "cards" else Vector2i(192,16))
		var hash: String = ""
		if valid:
			if pixels.is_compressed(): pixels.decompress()
			pixels.convert(Image.FORMAT_RGBA8)
			var bytes: PackedByteArray = pixels.get_data()
			for offset: int in range(0, bytes.size(), 4):
				if bytes[offset+3] == 0:
					bytes[offset] = 0; bytes[offset+1] = 0; bytes[offset+2] = 0
			var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes); hash = context.finish().hex_encode()
		if compare_manifest: valid = valid and expected.get(group, {}).get("visible_rgba_sha256", "") == hash
		records.append({"group":group, "path":path, "size":[size.x,size.y], "visible_rgba_sha256":hash, "valid":valid, "source_sha256":FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "resource_remapped"})
		if not valid: failures.append(path)
	for family: String in Art.IDS:
		if Catalog.max_rank(family) != 2 or not Catalog.mutation_choices(family).is_empty(): failures.append(family + " rank bounds")
		for rank: int in [1,2]:
			var identity: Dictionary = Catalog.get_owned_power(family,rank)
			var authored: Dictionary = Art.art(family + ("_ii" if rank == 2 else ""))
			if identity.get("card_row",-1) != authored.card_row or identity.get("icon_frame",-1) != authored.icon_frame: failures.append(family + " identity mapping")
	return {"textures":records,"failures":failures,"families":Art.IDS,"manifest":FileAccess.get_file_as_string(MANIFEST) if compare_manifest else "", "read_only":true}
