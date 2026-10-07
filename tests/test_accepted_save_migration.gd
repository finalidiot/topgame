extends SceneTree
## Exercise the actual accepted parent's CollectionSave source in an isolated path.
## Its class_name line alone is removed in memory to avoid a global-name collision.
const Collection = preload("res://scripts/collection_save.gd")
var checks: int = 0
var failures: int = 0
var old_source: String = ""
var collection_path: String = ""
var report_path: String = ""
var parent_sha: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--old-source="): old_source = arg.trim_prefix("--old-source=")
		elif arg.begins_with("--collection="): collection_path = arg.trim_prefix("--collection=")
		elif arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		elif arg.begins_with("--parent="): parent_sha = arg.trim_prefix("--parent=")
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"Isolated evidence file opens")
	if file != null:
		file.store_string(text)
		file.flush()
		file.close()

func _run() -> void:
	var safe: bool = old_source.is_absolute_path() and collection_path.is_absolute_path() and report_path.is_absolute_path()
	safe = safe and FileAccess.file_exists(old_source) and not FileAccess.file_exists(collection_path) and not FileAccess.file_exists(report_path)
	safe = safe and collection_path.get_base_dir() == old_source.get_base_dir() and collection_path.get_extension() == "json"
	check(safe,"New explicit isolated source, collection and report paths required")
	if not safe:
		quit(1)
		return
	var original: String = FileAccess.get_file_as_string(old_source)
	check(original.count("class_name CollectionSave") == 1,"Actual accepted source declares exactly the expected class")
	var accepted_script: GDScript = GDScript.new()
	accepted_script.source_code = original.replace("class_name CollectionSave\n", "")
	check(accepted_script.reload() == OK,"Actual accepted source compiles with only its global class declaration removed")
	var legacy = accepted_script.new(collection_path)
	check(legacy.load_save().status == "fresh","Accepted API sees a fresh isolated collection")
	check(legacy.initialize_starter("vane").ok,"Accepted API genuinely creates the chosen starter")
	for id: String in ["blade:hammerfall","ratchet:flywheel","bit:needle"]:
		check(legacy.grant_part(id).ok,"Accepted API genuinely grants an additional known design")
	var equipped: Dictionary = {"blade":"hammerfall","ratchet":"flywheel","bit":"needle"}
	check(legacy.equip_build(equipped).ok,"Accepted API genuinely equips a mixed owned assembly")
	var old_primary: String = FileAccess.get_file_as_string(collection_path)
	var old_backup: String = FileAccess.get_file_as_string(collection_path + ".bak")
	var old_json: Dictionary = JSON.parse_string(old_primary)
	check(int(old_json.schema_version) == 1 and old_json.size() == 4 and not old_json.has("progression"),"Actual parent API emitted accepted schema1 without economic fields")
	check(old_json.owned_part_ids.size() == 6 and old_json.equipped_build == equipped,"Actual parent save retains its three starter and three later designs")
	var primary_hash: String = FileAccess.get_sha256(collection_path)
	var backup_hash: String = FileAccess.get_sha256(collection_path + ".bak")
	var preserved: String = collection_path.get_basename() + "_accepted_schema1.json"
	check(not FileAccess.file_exists(preserved) and DirAccess.copy_absolute(collection_path,preserved) == OK,"Exact old-generated primary bytes retained as evidence")
	check(FileAccess.get_sha256(preserved) == primary_hash,"Preserved actual accepted primary hash matches")
	var preferences: String = collection_path + ".preferences.cfg"
	var prefs: String = "[settings]\nvolume=0.35\nmusic_volume=0.40\nsfx_volume=0.8\nscreen_shake=false\nfullscreen=false\n"
	_write(preferences,prefs)
	var prefs_hash: String = FileAccess.get_sha256(preferences)
	var migrated = Collection.new(collection_path)
	check(migrated.load_save().status == "migrated","Current API migrates the actual accepted main save")
	check(migrated.starter_id == "vane" and migrated.equipped_build() == equipped,"Actual accepted historical starter and mixed equipment survive")
	check(migrated.owned_count() == 6,"Actual accepted ownership survives without broad grants")
	for id: String in old_json.owned_part_ids: check(migrated.owns_part(id),"Each actually accepted owned design remains owned")
	check(migrated.credits == 0 and migrated.salvage == 0 and migrated.pending_packet().is_empty(),"Migration starts with zero economics and no phantom packet")
	check(FileAccess.get_sha256(collection_path) == primary_hash and FileAccess.get_sha256(collection_path + ".bak") == backup_hash,"Migration read preserves actual parent primary and backup bytes")
	var backup: Dictionary = migrated.backup_collection()
	check(backup.ok,"Verified explicit backup preserves the actual parent save before economical mutation")
	var archive: String = str(backup.backup_directory)
	check(FileAccess.get_sha256(archive.path_join(collection_path.get_file())) == primary_hash,"Archive preserves actual parent primary bytes exactly")
	check(FileAccess.get_sha256(archive.path_join(collection_path.get_file() + ".bak")) == backup_hash,"Archive preserves actual parent recovery backup bytes exactly")
	var nonce: Dictionary = migrated.begin_reward_run()
	check(nonce.ok,"Migrated collection can start a durable real reward transaction")
	var paid: Dictionary = migrated.pay_run_reward(str(nonce.run_id),{"reward_provenance":"earned-clear-v1","reward_fixture":false,"earned_threats_cleared":4,"earned_elites_cleared":0,"earned_bosses_cleared":0})
	check(paid.ok and migrated.credits == 48,"Explicit isolated earned-outcome transaction funds the configured Standard price")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3143001
	var purchase: Dictionary = migrated.purchase_packet("standard",rng,migrated.expected_packet_request_id())
	check(purchase.ok and migrated.credits == 0,"Migrated accepted collection makes an actual production packet purchase")
	var receipt: Dictionary = purchase.receipt
	check(migrated.finalize_packet(str(receipt.id)).ok,"Migrated accepted collection finalizes its actual fixed receipt")
	check(migrated.equipped_build() == equipped and migrated.starter_id == "vane","Packet acquisition retains actual accepted mixed machine and starter history")
	for id: String in old_json.owned_part_ids: check(migrated.owns_part(id),"Packet acquisition cannot drop actual accepted ownership")
	check(FileAccess.get_sha256(preferences) == prefs_hash,"Migration, backup, reward and packet leave preferences byte-identical")
	check(FileAccess.get_sha256(archive.path_join(collection_path.get_file())) == primary_hash,"Later schema2 writes cannot rewrite the archived actual parent save")
	var final_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(collection_path))
	check(int(final_json.schema_version) == 2,"Deliberate mutation writes the current schema2")
	var reload = Collection.new(collection_path)
	check(reload.load_save().ok and reload.equipped_build() == equipped,"Actual migrated collection reloads with the same mixed equipment")
	var final_count: int = reload.owned_count()
	var final_salvage: int = reload.salvage
	check(reload.finalize_packet(str(receipt.id)).status == "already_finalized" and reload.owned_count() == final_count and reload.salvage == final_salvage,"Reloading the actual migrated packet cannot double grant or double convert")
	var report: Dictionary = {"task":"003A","status":"passed" if failures == 0 else "failed","checks":checks,"failures":failures,
		"accepted_parent_sha":parent_sha,"accepted_source_path":old_source,"accepted_source_sha256":FileAccess.get_sha256(old_source),
		"source_adaptation":"Only the class_name CollectionSave line was removed in memory to avoid a global class collision; no save behavior or schema changed.",
		"generation":"The accepted parent API created Vane, granted Hammerfall/Flywheel/Needle and equipped that mixed machine.",
		"original_generated_primary_sha256":primary_hash,"original_generated_backup_sha256":backup_hash,"preserved_schema1_primary":preserved,
		"original_owned":old_json.owned_part_ids,"original_equipped":equipped,"verified_archive":archive,
		"preferences_path":preferences,"preferences_sha256":prefs_hash,"preferences_unchanged":FileAccess.get_sha256(preferences) == prefs_hash,
		"migration_initial_credits":0,"migration_initial_salvage":0,"qa_reward_fixture":"Explicit isolated earned outcome drives real durable transaction; not gameplay balance evidence",
		"packet_receipt":migrated.pending_packet(),"final_collection_path":collection_path,"final_collection_sha256":FileAccess.get_sha256(collection_path),
		"final_schema":final_json.schema_version,"final_owned":reload.owned_parts(),"final_equipped":reload.equipped_build()}
	var output: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	check(output != null,"Isolated actual-parent migration report opens")
	report.checks = checks
	report.failures = failures
	report.status = "passed" if failures == 0 else "failed"
	if output != null:
		output.store_string(JSON.stringify(report,"\t"))
		output.flush()
		output.close()
	print("ACCEPTED_SAVE_MIGRATION_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
