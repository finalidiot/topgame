extends SceneTree
## Real file/reset transactions on uniquely named external QA fixtures only.
const Collection = preload("res://scripts/collection_save.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: Array[String] = []
var qa: String
var evidence: Array[Dictionary] = []

class RefuseManifest extends "res://scripts/collection_save.gd":
	func _write_file(_path: String, _payload: String) -> bool: return false

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func fixture(label: String) -> String:
	return qa.path_join("temp/save_tools_%s_%d_%d.json" % [label, OS.get_process_id(), Time.get_ticks_usec()])

func write(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null); file.store_string(content); file.close()

func snapshot(path: String) -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp", ".preferences.cfg", ".unrelated.txt"]:
		result[suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	return result

func assert_archive(result: Dictionary, before: Dictionary) -> void:
	var folder: String = str(result.get("backup_directory", ""))
	check(not folder.is_empty() and DirAccess.dir_exists_absolute(folder), "A dedicated verified collection archive exists")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("manifest.json")))
	check(manifest is Dictionary and int(manifest.get("schema", 0)) == 1, "Archive has readable provenance")
	if not manifest is Dictionary: return
	for row: Dictionary in manifest.files:
		var source: String = str(row.source)
		var archived: String = folder.path_join(str(row.name))
		var suffix: String = source.trim_prefix(str(manifest.source))
		check(suffix in ["", ".bak", ".tmp", ".bak.tmp"], "Only four exact collection names are archived")
		check(FileAccess.get_file_as_bytes(archived) == before.get(suffix), "Archive retains original bytes including corrupt/temp data")
		check(FileAccess.get_sha256(archived) == row.sha256, "Archive fingerprint matches every retained file")
	check(not FileAccess.file_exists(folder.path_join(str(manifest.source).get_file() + ".preferences.cfg")), "Settings are not part of collection reset")

func test_ordinary_reset() -> void:
	var path: String = fixture("ordinary")
	var collection: RefCounted = Collection.new(path)
	check(collection.load_save().ok and collection.initialize_starter("breaker").ok, "Isolated reset fixture selects one actual starter")
	check(collection.grant_part("blade:hammerfall").ok, "Fixture owns a genuine additional part")
	write(path + ".tmp", "interrupted write preserved byte for byte")
	write(path + ".bak.tmp", "interrupted backup preserved")
	write(path + ".preferences.cfg", "[settings]\nvolume=0.45\nmusic_volume=0.35\n")
	write(path + ".unrelated.txt", "unrelated user material")
	var before: Dictionary = snapshot(path)
	var state: Dictionary = collection.snapshot()
	check(not collection.reset_collection().ok and snapshot(path) == before, "Implicit reset cannot change any file")
	var backup: Dictionary = collection.backup_collection()
	check(backup.ok and snapshot(path) == before and collection.snapshot() == state, "Explicit backup changes no active save or ownership")
	assert_archive(backup, before)
	var reset: Dictionary = collection.reset_collection(true)
	check(reset.ok and not collection.is_initialized() and collection.owned_count() == 0, "Explicit reset gives real empty ownership")
	assert_archive(reset, before)
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		check(not FileAccess.file_exists(path + suffix), "The exact active collection file was cleared after verified backup")
	for suffix: String in [".preferences.cfg", ".unrelated.txt"]:
		check(FileAccess.get_file_as_bytes(path + suffix) == before[suffix], "Options and unrelated data remain byte-identical")
	check(collection.initialize_starter("vane").ok, "Reset permits a genuine new first-save choice")
	check(collection.owned_count() == 3 and collection.equipped_build() == Starters.build_for("vane"), "Fresh save owns exactly its chosen starter's three parts")
	check(not collection.owns_part("blade:hammerfall") and not collection.owns_part("blade:smash"), "Reset never grants prior collection or all catalogue parts")
	evidence.append({"fixture":path,"backup":backup.backup_directory,"reset_archive":reset.backup_directory,"fresh_owned":collection.owned_count(),"starter":"vane"})

func test_corrupt_and_future() -> void:
	for label: String in ["corrupt", "future"]:
		var path: String = fixture(label)
		write(path, "malformed preserved {" if label == "corrupt" else '{"schema_version":999,"private_future_payload":[1,2,3]}')
		write(path + ".bak", "invalid backup bytes")
		var collection: RefCounted = Collection.new(path)
		check(not collection.load_save().ok and collection.read_only, "Unrecognised data retains corruption/future-schema protection")
		var before: Dictionary = snapshot(path)
		var backup: Dictionary = collection.backup_collection()
		check(backup.ok and collection.read_only and snapshot(path) == before, "Backup preserves blocked data without sanitisation")
		assert_archive(backup, before)
		var reset: Dictionary = collection.reset_collection(true)
		check(reset.ok and not collection.read_only, "Explicit backed-up reset can recover a blocked collection")
		assert_archive(reset, before)
		check(collection.initialize_starter("bastion").ok and collection.owned_count() == 3, "Recovered fresh flow grants only one starter")

func test_refusals() -> void:
	var path: String = fixture("failed_manifest")
	write(path, '{"schema_version":999,"preserve":"original"}')
	var before: Dictionary = snapshot(path)
	var collection: RefCounted = RefuseManifest.new(path)
	collection.load_save()
	check(not collection.reset_collection(true).ok and snapshot(path) == before, "A failed backup manifest blocks reset before any file removal")
	var blocked: RefCounted = Collection.new("res://assets/data/parts_catalogue.json")
	var asset_hash: String = FileAccess.get_sha256(blocked.save_path)
	check(not blocked.reset_collection(true).ok and FileAccess.get_sha256(blocked.save_path) == asset_hash, "Reset rejects production resource paths")
	var empty: RefCounted = Collection.new(fixture("empty"))
	check(empty.load_save().ok and empty.reset_collection(true).ok, "Already fresh isolated collection stays fresh without an invented archive")

func run() -> void:
	var configured: String = OS.get_environment("TOPGAME_QA_ROOT")
	var base: String = configured if not configured.is_empty() else ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	qa = base.path_join("002C.6")
	assert(DirAccess.make_dir_recursive_absolute(qa.path_join("temp")) == OK)
	var human_before: Dictionary = snapshot("user://collection.json")
	test_ordinary_reset(); test_corrupt_and_future(); test_refusals()
	check(snapshot("user://collection.json") == human_before, "Every automated reset leaves the human's real profile untouched")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var path: String = arg.trim_prefix("--report=")
			assert(not FileAccess.file_exists(path))
			write(path, JSON.stringify({"checks":checks,"failures":failures,"fixture_policy":"Unique external QA files only; human collection never reset", "reset_fresh_save_evidence":evidence}, "\t"))
	print("SAVE_TOOLS_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
