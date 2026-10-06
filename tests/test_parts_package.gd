extends SceneTree
## Compiled package-probe gating, actual texture loading and save isolation.
## Intercept process exit only: the production Main and inspection both run.

class QuietMain extends "res://scripts/main.gd":
	var probe_result: Dictionary = {}
	func _smoke_test() -> void:
		pass
	func _finish_qa_assets_probe(result: Dictionary) -> void:
		probe_result = result

const Catalog = preload("res://scripts/parts.gd")
const Probe = preload("res://scripts/parts_package_probe.gd")
const Collection = preload("res://scripts/collection_save.gd")
var checks: int = 0
var failures: int = 0
var qa_temp: String
var qa_manifests: String
var files: Array[String] = []
var real_before: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _snapshot(path: String) -> Dictionary:
	return {"exists":FileAccess.file_exists(path), "bytes":FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

func _path(folder: String, label: String) -> String:
	var path: String = folder.path_join("parts_package_%d_%d_%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label])
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp", ".preferences.cfg", ".last_run_director.json"]:
		files.append(path + suffix)
	return path

func _game(path: String, catalogue: bool, report: String = "", report_requested: bool = false) -> QuietMain:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = path
	game.qa_catalogue_requested = catalogue
	game.qa_assets_report = report
	game.qa_assets_report_requested = report_requested
	root.add_child(game)
	game.set_process(false)
	game.battle.set_physics_process(false)
	return game

func _settle() -> void:
	await process_frame
	await process_frame

func _test_default_boot() -> void:
	var path: String = _path(qa_temp, "ordinary")
	var game: QuietMain = _game(path, false)
	await _settle()
	check(game.probe_result.is_empty() and not game.qa_assets_report_requested, "Ordinary boot never runs the package probe")
	check(game.screen == "title" and not game.collection.is_initialized(), "Ordinary fresh boot keeps the starter-choice title")
	check(not FileAccess.file_exists(path) and game.collection.owned_count() == 0, "Ordinary boot grants and writes no permanent parts")
	check(not game.run_context.is_active() and not game.battle.visible, "The read-only diagnostic adds no gameplay or battle changes")
	game.queue_free()
	await _settle()

func _test_valid_probe() -> void:
	var path: String = _path(qa_temp, "catalogue")
	var output: String = _path(qa_manifests, "assets")
	var game: QuietMain = _game(path, true, output)
	await _settle()
	check(game.qa_catalogue_error.is_empty() and bool(game.probe_result.get("ok", false)), "Valid explicit QA boot runs the compiled probe successfully")
	game.review_audio = true
	game._battle_sound("ui_focus")
	check(game.sounds.played_counts.is_empty(), "Read-only package inspection never starts native audio playback, even when review audio is enabled")
	check(int(game.probe_result.get("textures", 0)) == 42, "The compiled probe loads all 31 static components and 11 blade spin sheets")
	check(game.collection.owned_count() == 31 and game.collection.equipped_build() == {"blade":"smash", "ratchet":"high", "bit":"flat"}, "Probe session has the complete isolated collection and unchanged Breaker assembly")
	check(not game.run_context.is_active() and not game.battle.visible, "The package probe inspects assets without injecting gameplay")
	check(game.preferences_path == path + ".preferences.cfg" and not FileAccess.file_exists(game.preferences_path), "QA boot has an isolated preference path and inspection writes no preferences")
	check(FileAccess.file_exists(output), "The package probe writes its new external report")
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(output))
	check(report is Dictionary, "Package asset report is valid JSON")
	if report is Dictionary:
		check(str(report.get("catalogue_json", "")) == FileAccess.get_file_as_string(Catalog.DATA_PATH), "Report preserves the exact packaged catalogue JSON, including physical coefficients")
		check(str(report.get("catalogue_sha256", "")) == FileAccess.get_sha256(Catalog.DATA_PATH), "Report records the catalogue content fingerprint")
		check(report.get("failures", []) == [] and bool(report.get("read_only_asset_inspection", false)), "Asset inspection has no failures and identifies its evidence scope")
		check(str(report.get("beast_json", "")) == FileAccess.get_file_as_string(Probe.BEAST_MANIFEST), "Report preserves the actual beast manifest")
		var beast_rows: Array = report.get("beast_textures", [])
		check(beast_rows.size() == 4, "Release probe includes all four beast manifestation sheets")
		var beast_ids: Array[String] = []
		for row: Dictionary in beast_rows:
			beast_ids.append(str(row.get("kind", "")))
			check(bool(row.get("valid", false)) and bool(row.get("visible_pixels", false)), "Packaged beast sheet loads actual visible pixels")
			check(str(row.get("visible_rgba_sha256", "")).length() == 64 and bool(row.get("transparent_rgb_normalized", false)), "Beast sheet records a visible-pixel fingerprint")
		for kind: String in ["black_arrow", "iron_bull", "stone_tortoise", "coil_dragon"]:
			check(beast_ids.count(kind) == 1, "Release probe covers exactly one sheet for " + kind)
		check(str(report.get("music_json", "")) == FileAccess.get_file_as_string(Probe.MUSIC_MANIFEST), "Probe reads the actual synchronized music manifest")
		var music_rows: Array = report.get("music_stems", [])
		check(music_rows.size() == 5, "Probe includes the complete bounded original score")
		var music_ids: Array[String] = []
		for row: Dictionary in music_rows:
			music_ids.append(str(row.kind))
			check(bool(row.valid) and int(row.mix_rate) == 32000 and int(row.pcm_frames) > 1000000, "Imported music has real uncompressed stereo PCM on the shared sample grid")
			check(str(row.pcm_sha256).length() == 64, "Imported PCM fingerprint is recorded for actual package comparison")
		for kind: String in ["title", "workshop", "run_base", "run_pressure", "run_boss"]:
			check(music_ids.count(kind) == 1, "Probe covers exactly one original music stem for " + kind)
		var rows: Array = report.get("textures", [])
		check(rows.size() == 42, "Report contains all 42 distinct runtime component textures")
		var found: Dictionary = {}
		for row: Dictionary in rows:
			check(bool(row.get("valid", false)) and bool(row.get("visible_pixels", false)), "Every reported texture actually loads and contains visible pixels: " + str(row.get("path", "")))
			var size: Array = row.get("size", [])
			check(size.size() == 2 and int(size[0]) == (384 if str(row.get("path", "")).ends_with("_spin.png") else 48) and int(size[1]) == 48, "Every reported runtime sprite has the correct native dimensions")
			check(not found.has(row.path), "Texture report has no duplicate paths")
			found[row.path] = true
		for category: String in Collection.CATEGORIES:
			for id: String in Catalog.PARTS[category]:
				var part: Dictionary = Catalog.PARTS[category][id]
				check(found.has(str(part.visual.sprite)), "The current catalogue sprite is included: " + category + ":" + id)
				if category == "blade": check(found.has(str(part.visual.spin)), "The current Blade spin sheet is included: " + id)
	var before: Dictionary = _snapshot(output)
	check(not bool(Probe.inspect(output).ok) and _snapshot(output) == before, "Probe itself refuses to overwrite an existing report")
	game.queue_free()
	await _settle()

func _test_refused_probe() -> void:
	var existing: String = _path(qa_manifests, "sentinel")
	var sentinel: FileAccess = FileAccess.open(existing, FileAccess.WRITE)
	sentinel.store_string("preserved existing QA artifact")
	sentinel.close()
	var existing_before: Dictionary = _snapshot(existing)
	var cases: Array[Dictionary] = [
		{"catalogue":false, "collection":_path(qa_temp, "missing_flag"), "report":_path(qa_manifests, "missing_flag")},
		{"catalogue":true, "collection":"", "report":_path(qa_manifests, "missing_collection")},
		{"catalogue":true, "collection":Collection.DEFAULT_PATH, "report":_path(qa_manifests, "real_profile")},
		{"catalogue":true, "collection":_path(qa_temp, "empty_report"), "report":""},
		{"catalogue":true, "collection":_path(qa_temp, "existing_report"), "report":existing},
		{"catalogue":true, "collection":_path(qa_temp, "directory_report"), "report":qa_manifests},
	]
	for report: String in ["user://collection.json", "res://collection.json", "relative_report.json", _path(qa_temp, "wrong_report_category"), qa_manifests.path_join("../temp/escaped_report.json")]:
		cases.append({"catalogue":true, "collection":_path(qa_temp, "unsafe_report"), "report":report})
	for item: Dictionary in cases:
		var game: QuietMain = _game(str(item.collection), bool(item.catalogue), str(item.report), true)
		await _settle()
		check(not game.qa_catalogue_error.is_empty() and not bool(game.probe_result.get("ok", true)), "Invalid probe request exits through the failure path")
		check(game.collection.read_only and game.collection.owned_count() == 0, "Invalid report request opens no player collection and grants no QA parts")
		check(not FileAccess.file_exists(game.collection_path), "Invalid report request writes no fallback save")
		check(not FileAccess.file_exists(game.preferences_path), "Invalid report request writes no preferences")
		check(not game.run_context.is_active() and game.screen == "collection_error", "Invalid package-probe flags never continue into regular gameplay")
		if str(item.collection).begins_with(qa_temp): check(not FileAccess.file_exists(str(item.collection)), "Report is refused before any valid QA collection is created")
		game.queue_free()
		await _settle()
	check(_snapshot(existing) == existing_before, "Previously existing QA report is preserved byte for byte")

func _run() -> void:
	root.size = Vector2i(640, 360)
	var project: String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var qa_root: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa_root.is_empty(): qa_root = project.get_base_dir().path_join("GyroBrothers-QA")
	qa_temp = qa_root.path_join("002C.5.2/temp")
	qa_manifests = qa_root.path_join("002C.5.2/manifests")
	DirAccess.make_dir_recursive_absolute(qa_temp)
	DirAccess.make_dir_recursive_absolute(qa_manifests)
	for path: String in ["user://collection.json", "user://collection.json.bak", "user://prototype.cfg", "user://last_run_director.json"]:
		real_before[path] = _snapshot(path)
	await _test_default_boot()
	await _test_valid_probe()
	await _test_refused_probe()
	for path: String in real_before: check(_snapshot(path) == real_before[path], "Real collection, backup, preferences and Run diagnostic stay byte-identical")
	for path: String in files:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("PARTS_PACKAGE_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
