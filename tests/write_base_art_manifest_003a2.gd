extends SceneTree
## Explicit authoring tool; not called by tests or ordinary startup.
const Probe = preload("res://scripts/base_power_package_probe.gd")
func _initialize() -> void:
	var result: Dictionary = Probe.inspect(false)
	if not result.failures.is_empty(): push_error(str(result.failures)); quit(1); return
	var manifest: Dictionary = {"schema":"003a2-native-vector-identity-v1", "engine":Engine.get_version_info(), "families":result.families, "card_frames":6, "source":"editable cards.svg and icons.svg; visible imported RGBA fingerprint", "transparent_rgb_normalized":true}
	for record: Dictionary in result.textures: manifest[record.group] = record
	FileAccess.open(Probe.MANIFEST,FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t"))
	print("BASE_ART_MANIFEST_PASS"); quit(0)
