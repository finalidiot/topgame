extends SceneTree
## Actual imported UI resources, source-pixel parity and invalid metadata.
## No Main, collection, settings, Battle or economic transaction is created.
const Probe = preload("res://scripts/parts_package_probe.gd")
var checks: int = 0
var failures: Array[String] = []
var real_before: Dictionary = {}
var report_path: String = ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func snapshot(path: String) -> Dictionary:
	return {"exists":FileAccess.file_exists(path), "bytes":FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

func source_pixels(path: String) -> String:
	var image: Image = Image.new()
	var error: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	check(error == OK and not image.is_empty() and not image.is_invisible(), "Source authored UI PNG contains visible native pixels: " + path)
	if error != OK or image.is_empty(): return ""
	image.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = image.get_data()
	for offset: int in range(0, bytes.size(), 4):
		if bytes[offset + 3] == 0:
			for channel: int in range(3): bytes[offset + channel] = 0
	return Probe._digest(bytes)

func run() -> void:
	for path: String in ["user://collection.json", "user://collection.json.bak", "user://prototype.cfg", "user://last_run_director.json"]:
		real_before[path] = snapshot(path)
	check(Probe.UI_POLISH_LAYOUT.size() == 7, "The actual package probe covers the bounded seven-sheet UI family")
	for kind: String in Probe.UI_POLISH_LAYOUT:
		var metadata_path: String = Probe.UI_POLISH_ROOT + kind + ".json"
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		check(parsed is Dictionary, "Production UI metadata is valid JSON: " + kind)
		if not parsed is Dictionary: continue
		var meta: Dictionary = parsed
		var row: Dictionary = Probe._inspect_ui_polish_sheet(kind, meta)
		check(bool(row.valid) and bool(row.visible_pixels), "Actual imported UI sheet loads visible pixels with valid native topology: " + kind)
		check(row.path == Probe.UI_POLISH_ROOT + kind + ".png" and row.metadata_path == metadata_path, "UI probe uses the actual PNG and JSON resource paths: " + kind)
		check(bool(row.transparent_rgb_normalized) and row.visible_rgba_sha256 == source_pixels(row.path), "Imported alpha and every visible RGB byte match authored source: " + kind)
		for field: String in ["cell", "pivot", "tags", "durations_ms", "layers", "columns", "frame_count"]:
			check(row[field] == meta[field], "UI package report retains authored " + kind + "/" + field)
		for change: Dictionary in [
			{"cell":[1, 1]}, {"pivot":[-1, -1]}, {"frame_count":0}, {"columns":0},
			{"durations_ms":[]}, {"layers":[]}, {"tags":{}}, {"filter":"linear"},
			{"native_pixels":false}, {"texture":"other.png"},
			{"tags":{"INVALID":{"from":0, "to":1000}}}
		]:
			var invalid: Dictionary = meta.duplicate(true)
			invalid.merge(change, true)
			check(not bool(Probe._inspect_ui_polish_sheet(kind, invalid).valid), "Real UI sheet rejects invalid authored topology " + kind + "/" + str(change.keys()[0]))
	# Exercise the full production report wiring as well as the sheet helper.
	var qa_root: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa_root.is_empty(): qa_root = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	var manifest_dir: String = qa_root.path_join("003A/manifests")
	DirAccess.make_dir_recursive_absolute(manifest_dir)
	report_path = manifest_dir.path_join("003a_human_feedback_ui_package_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	check(not FileAccess.file_exists(report_path), "Full UI package report uses a fresh external evidence path")
	var result: Dictionary = Probe.inspect(report_path)
	check(bool(result.get("ok", false)) and int(result.get("textures", 0)) == 42, "Extended production report preserves the accepted 31-part / 42-texture probe")
	var packaged: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	check(packaged is Dictionary, "Production extended package report is valid JSON")
	if packaged is Dictionary:
		check(packaged.failures.is_empty() and bool(packaged.read_only_asset_inspection), "All retained and new imported package resources validate without gameplay")
		var rows: Array = packaged.get("ui_polish_textures", [])
		var json_rows: Dictionary = packaged.get("ui_polish_json", {})
		check(rows.size() == 7 and json_rows.size() == 7, "Full compiled report includes all seven UI sheets and actual metadata texts")
		var found: Array[String] = []
		for row: Dictionary in rows:
			var kind: String = str(row.kind)
			found.append(kind)
			check(bool(row.valid) and row.visible_rgba_sha256 == source_pixels(row.path), "Full report exposes real imported source-pixel parity: " + kind)
			check(json_rows.get(kind, "") == FileAccess.get_file_as_string(Probe.UI_POLISH_ROOT + kind + ".json"), "Full report preserves the actual authored UI JSON: " + kind)
		for kind: String in Probe.UI_POLISH_LAYOUT: check(found.count(kind) == 1, "Compiled report exposes exactly one UI sheet for " + kind)
	for path: String in real_before:
		check(snapshot(path) == real_before[path], "Read-only UI resource inspection preserves player data: " + path)
	print("UI_POLISH_PACKAGE_TEST_%s checks=%d failures=%d assets=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), report_path])
	quit(0 if failures.is_empty() else 1)
