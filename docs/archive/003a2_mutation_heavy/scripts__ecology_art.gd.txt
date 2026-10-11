extends RefCounted
## Saved native mutation illustrations. This lookup has no gameplay state.
const PATH: String = "res://assets/powers/ecology003a2/manifest.json"
static var metadata: Dictionary = {}

static func meta() -> Dictionary:
	if metadata.is_empty() and FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: metadata = parsed
	return metadata

static func art(art_id: String) -> Dictionary:
	return meta().get("art", {}).get(art_id, {}).duplicate(true)
