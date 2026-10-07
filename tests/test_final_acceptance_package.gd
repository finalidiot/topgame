extends SceneTree
## Read-only actual imported resource parity and rejection coverage. This editor
## suite is separate from the same probe executed inside candidate EXE/APKs.
const Probe = preload("res://scripts/parts_package_probe.gd")
var checks: int = 0
var failures: Array[String] = []
var before: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func snapshot(path: String) -> Dictionary:
	return {"exists":FileAccess.file_exists(path), "bytes":FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

func source_pixels(path: String) -> String:
	var image: Image = Image.new()
	var error: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	check(error == OK and not image.is_empty() and not image.is_invisible(), "Authored source PNG has visible pixels: " + path)
	if error != OK or image.is_empty(): return ""
	image.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = image.get_data()
	for offset: int in range(0, bytes.size(), 4):
		if bytes[offset+3] == 0:
			for channel: int in range(3): bytes[offset+channel] = 0
	return Probe._digest(bytes)

func inspect_sheet(family: String, group: String, kind: String, meta: Dictionary) -> Dictionary:
	return Probe._inspect_defence_sheet(family, group, meta) if not family.is_empty() else Probe._inspect_arena_sheet(kind, meta)

func verify_sheet(family: String, group: String, kind: String, meta: Dictionary) -> void:
	var row: Dictionary = inspect_sheet(family, group, kind, meta)
	check(bool(row.valid) and bool(row.visible_pixels), "Actual imported sheet has native dimensions and visible pixels: " + kind)
	check(row.path == meta.texture, "Probe loads the authoritative runtime texture: " + kind)
	check(row.visible_rgba_sha256 == source_pixels(row.path) and bool(row.transparent_rgb_normalized), "Imported alpha and visible RGB exactly match source: " + kind)
	check(bool(row.native_source_available) and row.native_source_sha256 == FileAccess.get_sha256("res://" + str(meta.source)), "Probe exposes the saved editable native master hash: " + kind)
	for field: String in ["cell", "pivot", "tags", "durations_ms", "layers", "columns", "frame_count", "source"]:
		check(row[field] == meta[field], "Full imported sheet retains native topology: " + kind + "/" + field)
	var changes: Array[Dictionary] = [
		{"cell":[1,1]}, {"pivot":[-1,-1]}, {"frame_count":0}, {"columns":0},
		{"durations_ms":[]}, {"layers":[]}, {"tags":{}}, {"texture":"res://wrong.png"},
		{"source":"assets/wrong.aseprite"}, {"durations_ms":[0]},
		{"tags":{"INVALID":{"from":-1,"to":10000}}}
	]
	if family.is_empty(): changes.append_array([{"native_pixels":false},{"presentation_only":false},{"filter":"linear"}])
	else: changes.append({"source_sha256":"invalid"})
	# A correct tag name with an invalid range must also be rejected.
	var bad_tags: Dictionary = meta.tags.duplicate(true)
	bad_tags[bad_tags.keys()[0]]["to"] = int(meta.frame_count)
	changes.append({"tags":bad_tags})
	# A duplicate layer name must not pass by retaining the correct layer count.
	var bad_layers: Array = meta.layers.duplicate()
	bad_layers[bad_layers.size()-1] = bad_layers[0]
	changes.append({"layers":bad_layers})
	for change: Dictionary in changes:
		var invalid: Dictionary = meta.duplicate(true)
		invalid.merge(change, true)
		check(not bool(inspect_sheet(family, group, kind, invalid).valid), "Actual resource rejects invalid topology: " + kind + "/" + str(change.keys()[0]))

func run() -> void:
	for path: String in ["user://collection.json","user://collection.json.bak","user://prototype.cfg","user://last_run_director.json"]: before[path] = snapshot(path)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Probe.DEFENCE_MANIFEST))
	check(manifest.families.size() == 3 and manifest.art.size() == 12, "Defence catalogue contains three complete families and twelve authored card/icon states")
	for family: String in Probe.DEFENCE_VARIANTS:
		for group: String in ["cards","icons","fx"]: verify_sheet(family, group, family + "/" + group, manifest.families[family][group])
	check(Probe.ARENA_LAYOUT.size() == 6, "Arena presentation has a bounded six-sheet package family")
	for kind: String in Probe.ARENA_LAYOUT:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Probe.ARENA_ROOT + kind + ".json"))
		verify_sheet("", "", kind, meta)
	var qa_root: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa_root.is_empty(): qa_root = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	var folder: String = qa_root.path_join("003A/manifests")
	DirAccess.make_dir_recursive_absolute(folder)
	var output: String = folder.path_join("003a_final_acceptance_assets_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	check(not FileAccess.file_exists(output), "Production probe uses a fresh external evidence path")
	var status: Dictionary = Probe.inspect(output)
	check(bool(status.get("ok", false)) and int(status.get("textures", 0)) == 42, "Full additive probe preserves all accepted catalogue guards")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output))
	check(report.failures.is_empty() and bool(report.read_only_asset_inspection), "All accepted and additive resources load without gameplay grants")
	check(report.defence_json == FileAccess.get_file_as_string(Probe.DEFENCE_MANIFEST), "Full report contains actual compiled defence metadata text")
	check(report.defence_textures.size() == 9 and report.arena_textures.size() == 6 and report.arena_json.size() == 6, "Full report covers all fifteen resources exactly once")
	var found: Dictionary = {}
	for row: Dictionary in report.defence_textures + report.arena_textures:
		check(not found.has(row.kind), "Full report has no duplicate sheet identity: " + str(row.kind))
		found[row.kind] = true
		check(bool(row.valid) and row.visible_rgba_sha256 == source_pixels(row.path), "Full actual report exposes source-pixel parity: " + str(row.kind))
	for kind: String in Probe.ARENA_LAYOUT: check(report.arena_json[kind] == FileAccess.get_file_as_string(Probe.ARENA_ROOT + kind + ".json"), "Full report contains actual arena metadata text: " + kind)
	for path: String in before: check(snapshot(path) == before[path], "Asset inspection preserves player data: " + path)
	print("FINAL_ACCEPTANCE_PACKAGE_TEST_%s checks=%d failures=%d assets=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), output])
	quit(0 if failures.is_empty() else 1)
