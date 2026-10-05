extends SceneTree
## Isolated on-disk collection contracts. No production user data or preferences
## are loaded, edited or removed by this suite.
const Collection = preload("res://scripts/collection_save.gd")
const Catalog = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")

class InterruptedWrite extends "res://scripts/collection_save.gd":
	var interrupt: bool = false
	var backup_interrupt: bool = false
	func _write_file(path: String, payload: String) -> bool:
		if interrupt and (not backup_interrupt or path.ends_with(".bak.tmp")):
			var partial: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			if partial != null:
				partial.store_string(payload.left(17))
				partial.flush()
				partial.close()
			return false
		return super._write_file(path, payload)

var checks: int = 0
var failures: int = 0
var isolated_dir: String
var fixture_files: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _path(name: String) -> String:
	var path: String = isolated_dir.path_join(name + ".json")
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if not path + suffix in fixture_files: fixture_files.append(path + suffix)
	return path

func _write(path: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Fixture file opens in isolated directory")
	if file != null:
		file.store_string(value if value is String else JSON.stringify(value))
		file.close()
	if not path in fixture_files: fixture_files.append(path)

func _disk(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value is Dictionary and value.get("schema_version", null) is float: value.schema_version = int(value.schema_version)
	return value if value is Dictionary else {}

func _stored(collection: RefCounted) -> Dictionary:
	var snapshot: Dictionary = collection.snapshot()
	return {"schema_version":snapshot.schema_version, "starter_selected":snapshot.starter_selected,
		"owned_part_ids":snapshot.owned_part_ids, "equipped_build":snapshot.equipped_build}

func _run() -> void:
	isolated_dir = OS.get_temp_dir().path_join("spinning_metal_collection_unit_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	check(DirAccess.make_dir_recursive_absolute(isolated_dir) == OK, "Isolated fixture directory created")
	_test_ids_and_fresh()
	for starter: String in Starters.IDS: _test_starter(starter)
	_test_future_grants_and_equipment()
	_test_write_failures()
	_test_stale_instances()
	_test_loaded_data()
	_test_backup_and_corruption()
	_test_migration()
	_test_malformed_shapes()
	_test_future_version_and_reset()
	for path: String in fixture_files:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(isolated_dir)
	print("COLLECTION_SAVE_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)

func _test_ids_and_fresh() -> void:
	var catalog_count: int = 0
	for category: String in Collection.CATEGORIES:
		for local_id: String in Catalog.PARTS[category]:
			catalog_count += 1
			var id: String = Collection.part_id(category, local_id)
			check(Collection.is_valid_part_id(id), "Every catalogue key has a stable globally qualified identity")
			check(Collection.split_part_id(id) == {"category":category, "id":local_id}, "Qualified identity round trips without label/index")
	check(catalog_count == Catalog.BLADE_IDS.size() + Catalog.RATCHET_IDS.size() + Catalog.BIT_IDS.size(), "All expanded catalogue parts remain valid content")
	for invalid: String in ["smash", "BLADE:SMASH", "blade:SMASH", "blade:missing", "blade:smash:extra", "run_power:redline", "blade", "", ":blade:smash"]:
		check(not Collection.is_valid_part_id(invalid), "Ambiguous, unknown and nonpart identities are rejected: " + invalid)
	var path: String = _path("fresh")
	var collection = Collection.new(path)
	check(collection.load_save().status == "fresh", "Missing collection is a fresh save independently of preferences")
	check(not collection.is_initialized() and collection.owned_count() == 0, "Fresh player owns nothing")
	check(collection.equipped_build().is_empty() and not collection.can_launch(), "Fresh save cannot launch an unequipped machine")
	check(collection.grant_part("blade:guard").status == "not_initialized", "Future reward API does not silently seed fresh inventory")
	check(collection.equip_build(Catalog.DEFAULT_BUILD).status == "not_initialized", "Fresh save cannot equip broad prototype catalogue")
	check(collection.initialize_starter("missing").status == "invalid_starter", "Unknown starter rejected")
	check(not FileAccess.file_exists(path), "Reads and rejected mutations do not create a collection")

func _test_starter(starter: String) -> void:
	var path: String = _path(starter)
	var collection = Collection.new(path)
	collection.load_save()
	check(collection.initialize_starter(starter).status == "initialized", starter + " first choice saves successfully")
	check(collection.is_initialized() and collection.starter_id == starter, starter + " historical identity is saved")
	check(collection.owned_count() == 3 and collection.can_launch(), starter + " begins with exactly three parts and valid launch")
	var assembly: Dictionary = Starters.build_for(starter)
	check(collection.equipped_build() == assembly, starter + " original assembly equipped immediately")
	for category: String in Collection.CATEGORIES:
		check(collection.owned_parts(category) == [assembly[category]], starter + " owns only the selected " + category)
		for local_id: String in Catalog.PARTS[category]:
			check(collection.owns_part(Collection.part_id(category, local_id)) == (local_id == assembly[category]), starter + " other catalogue parts stay unowned")
	var initial: Dictionary = _stored(collection)
	check(collection.initialize_starter("breaker" if starter != "breaker" else "bastion").status == "already_initialized", "Historical starter cannot be switched")
	check(_stored(collection) == initial, "Repeated ceremony cannot grant unchosen parts")
	var exposed: Dictionary = collection.snapshot()
	exposed.owned_part_ids.append("blade:balance")
	exposed.owned_parts.blade.append("balance")
	exposed.equipped_build.blade = "balance"
	check(_stored(collection) == initial, "Snapshots cannot mutate authoritative collection")
	var exposed_build: Dictionary = collection.equipped_build()
	exposed_build.blade = "balance"
	check(collection.equipped_build() == assembly, "Equipped preview copy cannot modify persistent machine")
	var reloaded = Collection.new(path)
	check(reloaded.load_save().ok and reloaded.is_initialized(), starter + " survives a new collection instance/application load")
	check(_stored(reloaded) == initial, starter + " ownership and equipped build reload exactly")
	check(_disk(path).size() == 4, "Only four persistent schema fields are written")
	for temporary: String in ["powers", "power_ranks", "mutations", "xp", "rpm", "level", "run_seed", "director"]:
		check(not _disk(path).has(temporary), "Temporary Run state never enters collection: " + temporary)
	check(FileAccess.file_exists(path + ".bak"), "First successful ownership has a valid recovery backup")

func _test_future_grants_and_equipment() -> void:
	var path: String = _path("grants")
	var collection = Collection.new(path)
	collection.load_save()
	collection.initialize_starter("breaker")
	var locked: Dictionary = {"blade":"guard", "ratchet":"high", "bit":"flat"}
	check(not collection.can_equip_build(locked), "Unowned parts are unavailable even when catalogue-valid")
	check(collection.equip_build(locked).status == "unowned_part", "Equip API rejects an unowned blade cleanly")
	check(collection.equip_build({"blade":"unknown", "ratchet":"high", "bit":"flat"}).status == "invalid_build", "Invalid IDs cannot default into an owned build")
	check(collection.equip_build({"blade":"smash", "bit":"flat"}).status == "invalid_build", "Incomplete assembly rejected without defaulting")
	check(collection.equip_build({"blade":"smash", "ratchet":"high", "bit":"flat", "powers":["redline"]}).status == "invalid_build", "Temporary fields cannot sneak through equip_build")
	var before_invalid: String = FileAccess.get_file_as_string(path)
	check(collection.grant_part("blade:nope").status == "invalid_part", "Future reward grants validate catalogue identity")
	check(FileAccess.get_file_as_string(path) == before_invalid, "Rejected grant does not rewrite the save")
	check(collection.grant_part("blade:guard").status == "newly_acquired", "Future shop/boss API grants a new real part")
	var after_grant: String = FileAccess.get_file_as_string(path)
	check(collection.grant_part("blade:guard").status == "already_owned", "Duplicate grant returns an explicit useful result")
	check(collection.owned_count() == 4 and FileAccess.get_file_as_string(path) == after_grant, "Duplicate does not add entries or rewrite a file")
	check(collection.equip_build(locked).status == "equipped", "Acquired part can be equipped immediately")
	check(collection.starter_id == "breaker", "Different equipped blade does not rewrite historical starter")
	var reload = Collection.new(path)
	reload.load_save()
	check(reload.equipped_build() == locked and reload.owned_count() == 4, "Future mixed build survives save/load")
	check(reload.snapshot().owned_parts.blade == ["smash", "guard"], "Workshop category view follows catalogue order")
	check(reload.owned_parts("unknown").is_empty(), "Unknown category safely yields no ownership")

func _test_write_failures() -> void:
	var initial_path: String = _path("interrupted_initial")
	var initial = InterruptedWrite.new(initial_path)
	initial.load_save()
	initial.interrupt = true
	check(initial.initialize_starter("vane").status == "write_failed", "Partial initial write reports failure")
	check(not initial.is_initialized() and initial.owned_count() == 0, "Failed write does not commit phantom ownership in memory")
	check(not FileAccess.file_exists(initial_path), "Partial initial staging never becomes the primary save")
	var retry = Collection.new(initial_path)
	check(retry.load_save().status == "fresh", "Interrupted initial temporary file is ignored after restart")
	var path: String = _path("interrupted_existing")
	var collection = InterruptedWrite.new(path)
	collection.load_save()
	collection.initialize_starter("bastion")
	var disk: String = FileAccess.get_file_as_string(path)
	var memory: Dictionary = _stored(collection)
	collection.interrupt = true
	check(collection.grant_part("bit:needle").status == "write_failed", "Partial grant write reports failure")
	check(_stored(collection) == memory and FileAccess.get_file_as_string(path) == disk, "Interrupted grant preserves authoritative memory and primary")
	collection.backup_interrupt = true
	check(collection.grant_part("bit:needle").status == "write_failed", "Interrupted backup preservation aborts the new commit")
	check(_stored(collection) == memory and FileAccess.get_file_as_string(path) == disk, "Backup failure cannot damage committed ownership")
	var reload = Collection.new(path)
	check(reload.load_save().ok and _stored(reload) == memory, "Existing collection reloads unchanged after both failure modes")
	collection.interrupt = false
	check(collection.grant_part("bit:needle").ok, "A later healthy write can replace stale partial staging")
	check(collection.owns_part("bit:needle"), "Retry commits only after a verified complete write")
	var inaccessible: String = _path("not_a_file")
	check(DirAccess.make_dir_absolute(inaccessible) == OK, "Isolated directory fixture prevents primary replacement")
	var rejected = Collection.new(inaccessible)
	rejected.load_save()
	check(rejected.initialize_starter("breaker").status == "write_failed", "Filesystem replacement failure is reported")
	check(not rejected.is_initialized() and rejected.owned_count() == 0, "Replacement failure also keeps memory uncommitted")
	DirAccess.remove_absolute(inaccessible)

func _test_loaded_data() -> void:
	var path: String = _path("filtered")
	_write(path, {"schema_version":1, "starter_selected":"breaker", "owned_part_ids":["blade:smash", "blade:smash", "ratchet:high", "bit:flat", "blade:obsolete", "future:unknown", 33, null],
		"equipped_build":{"blade":"smash", "ratchet":"high", "bit":"flat"}, "powers":["redline"], "xp":500})
	var collection = Collection.new(path)
	check(collection.load_save().status == "loaded_repaired", "Unknown/duplicate/malformed ownership entries are conservatively filtered")
	check(collection.owned_count() == 3 and collection.can_launch(), "Filtering never grants the full catalogue")
	check(not collection.owns_part("blade:obsolete"), "Obsolete identity is not an equippable owned part")
	check(not collection.snapshot().has("powers") and not collection.snapshot().has("xp"), "Loaded temporary fields are discarded")
	check(collection.grant_part("blade:guard").ok and _disk(path).size() == 4, "Next legitimate write persists only current schema")
	var partial: String = _path("partial")
	_write(partial, {"schema_version":1, "starter_selected":"vane", "owned_part_ids":["blade:hook", "ratchet:mid"], "equipped_build":{"blade":"hook", "ratchet":"mid", "bit":"rubber"}})
	var damaged = Collection.new(partial)
	check(damaged.load_save().ok and damaged.is_initialized(), "Partial collection preserves its historical starter")
	check(damaged.owned_count() == 2 and not damaged.owns_part("bit:rubber"), "Missing components are never silently restored or granted")
	check(damaged.equipped_build().is_empty() and not damaged.can_launch(), "No complete owned build cannot launch")
	check(damaged.initialize_starter("breaker").status == "already_initialized", "Partial data cannot reopen ceremony to switch historical starter")
	var repair: String = _path("equipped_repair")
	_write(repair, {"schema_version":1, "starter_selected":"bastion", "owned_part_ids":["blade:guard", "ratchet:low", "bit:ball"], "equipped_build":{"blade":"smash", "ratchet":"high", "bit":"flat"}})
	var legal = Collection.new(repair)
	legal.load_save()
	check(legal.equipped_build() == Starters.build_for("bastion"), "Invalid equipment repairs to a complete owned assembly only")
	check(legal.owned_count() == 3, "Equipment repair does not grant any parts")

func _test_stale_instances() -> void:
	var path: String = _path("two_fresh")
	var first = Collection.new(path)
	var second = Collection.new(path)
	first.load_save()
	second.load_save()
	check(first.initialize_starter("breaker").ok, "First fresh instance commits its historical choice")
	var chosen_bytes: String = FileAccess.get_file_as_string(path)
	check(second.initialize_starter("bastion").status == "stale_save" and second.read_only, "Stale fresh second instance cannot choose a different starter")
	check(FileAccess.get_file_as_string(path) == chosen_bytes and not second.is_initialized(), "Conflicting initial choice never changes disk or in-memory ownership")
	check(second.load_save().ok and second.starter_id == "breaker", "Reload resolves stale choice to the already committed collection")
	check(second.initialize_starter("bastion").status == "already_initialized", "Reloaded instance keeps historical choice irreversible")
	var unloaded = Collection.new(path)
	check(unloaded.initialize_starter("vane").status == "stale_save", "Caller forgetting load_save cannot overwrite an existing first choice")
	check(FileAccess.get_file_as_string(path) == chosen_bytes, "Unloaded initializer preserves an existing collection byte-for-byte")
	check(first.grant_part("blade:guard").ok, "First initialized instance commits a future acquisition")
	var acquired_bytes: String = FileAccess.get_file_as_string(path)
	check(second.grant_part("blade:hook").status == "stale_save", "Stale initialized grant is rejected instead of dropping another acquisition")
	check(FileAccess.get_file_as_string(path) == acquired_bytes and not second.owns_part("blade:hook"), "Rejected stale grant preserves committed disk and local state")
	second.load_save()
	check(second.owns_part("blade:guard") and second.grant_part("blade:hook").ok, "Reload then grant keeps both acquired parts")
	first.load_save()
	second.load_save()
	var guard_build: Dictionary = Starters.build_for("breaker")
	guard_build.blade = "guard"
	var hook_build: Dictionary = guard_build.duplicate()
	hook_build.blade = "hook"
	check(first.equip_build(guard_build).ok, "First instance saves newly equipped owned assembly")
	var equipped_bytes: String = FileAccess.get_file_as_string(path)
	check(second.equip_build(hook_build).status == "stale_save", "Stale equipment cannot silently erase another session's equipped assembly")
	check(FileAccess.get_file_as_string(path) == equipped_bytes and second.equipped_build() == Starters.build_for("breaker"), "Rejected stale equipment preserves disk and prior local equipment")
	second.load_save()
	check(second.equipped_build() == guard_build and second.equip_build(hook_build).ok, "Reload then equip updates the latest legal owned state")
	var backup_only: String = _path("unloaded_backup")
	var saved = Collection.new(backup_only)
	saved.load_save()
	saved.initialize_starter("vane")
	DirAccess.remove_absolute(backup_only)
	var backup_bytes: String = FileAccess.get_file_as_string(backup_only + ".bak")
	var stale_backup = Collection.new(backup_only)
	check(stale_backup.initialize_starter("breaker").status == "stale_save", "Initialized backup prevents forgotten-load overwrite when primary is missing")
	check(not FileAccess.file_exists(backup_only) and FileAccess.get_file_as_string(backup_only + ".bak") == backup_bytes, "Rejected initialization leaves valid backup intact")
	check(stale_backup.load_save().status == "recovered_backup" and stale_backup.grant_part("blade:balance").ok, "Recovered backup still permits a legitimate current-state write")
	var corrupt: String = _path("unloaded_corrupt")
	_write(corrupt, "{partial")
	var unsafe = Collection.new(corrupt)
	check(unsafe.initialize_starter("bastion").status == "read_only" and unsafe.read_only, "Forgotten load cannot overwrite corrupt existing ownership")
	check(FileAccess.get_file_as_string(corrupt) == "{partial", "Unloaded mutation preserves malformed recovery source")
	var removed: String = _path("removed_live")
	var older = Collection.new(removed)
	older.load_save()
	older.initialize_starter("breaker")
	var resetter = Collection.new(removed)
	resetter.load_save()
	resetter.reset_collection(true)
	check(older.grant_part("blade:guard").status == "stale_save", "An old game window cannot resurrect collection after explicit reset in another instance")
	check(not FileAccess.file_exists(removed), "Stale post-reset grant does not recreate deleted save")

func _test_backup_and_corruption() -> void:
	var path: String = _path("backup")
	var collection = Collection.new(path)
	collection.load_save()
	collection.initialize_starter("breaker")
	collection.grant_part("blade:guard")
	var backup: Dictionary = _disk(path + ".bak")
	_write(path, "{\"schema_version\":1,broken")
	var recovered = Collection.new(path)
	check(recovered.load_save().status == "recovered_backup", "Malformed primary loads its last valid backup")
	check(_stored(recovered) == backup and recovered.owned_count() == 3, "Backup recovery is conservative and retains original starter")
	check(recovered.grant_part("bit:needle").ok, "Recovered state may be saved without copying corrupt primary into backup")
	check(_disk(path + ".bak") == backup, "Corrupt primary cannot overwrite a valid backup")
	DirAccess.remove_absolute(path)
	var missing_primary = Collection.new(path)
	check(missing_primary.load_save().status == "recovered_backup", "Interrupted primary replacement can recover even when primary is absent")
	var corrupt: String = _path("no_backup")
	_write(corrupt, "{partial")
	var blocked = Collection.new(corrupt)
	check(blocked.load_save().status == "corrupt" and blocked.read_only, "Damaged save without backup is blocked conservatively")
	check(blocked.initialize_starter("vane").status == "read_only", "Corrupt ownership is not silently replaced by a new starter")
	check(FileAccess.get_file_as_string(corrupt) == "{partial", "Unrecoverable source remains available for manual recovery")
	check(blocked.reset_collection(true).ok and blocked.load_save().status == "fresh", "Explicit testing reset clears a blocked collection safely")

func _test_migration() -> void:
	var path: String = _path("older")
	_write(path, {"schema_version":0, "starter_id":"vane", "owned_parts":{"blade":["hook", "hook", "obsolete"], "ratchet":["mid"], "bit":["rubber"]},
		"build":{"blade":"hook", "ratchet":"mid", "bit":"rubber"}, "powers":["afterimage"]})
	var migrated = Collection.new(path)
	check(migrated.load_save().status == "migrated", "Explicit schema-0 fixture migrates category-local ownership")
	check(migrated.starter_id == "vane" and migrated.owned_count() == 3 and migrated.can_launch(), "Migration retains valid assembly without broad grants")
	check(migrated.snapshot().schema_version == Collection.SCHEMA_VERSION, "Migrated memory uses the current schema")
	check(migrated.grant_part("blade:balance").ok and int(_disk(path).schema_version) == 1, "Next deliberate mutation writes the current version")
	var malformed_version: String = _path("invalid_version")
	_write(malformed_version, {"schema_version":"1", "starter_selected":"breaker", "owned_part_ids":[]})
	check(Collection.new(malformed_version).load_save().status == "corrupt", "Malformed schema version is not silently coerced")

func _test_malformed_shapes() -> void:
	var fixtures: Array = [null, [], "true", {"schema_version":-1}, {"schema_version":0.5},
		{"schema_version":1, "starter_selected":"unknown", "owned_part_ids":[]},
		{"schema_version":true, "starter_selected":"breaker", "owned_part_ids":[]},
		{"schema_version":1, "starter_selected":13, "owned_part_ids":[]}]
	for index: int in range(fixtures.size()):
		var path: String = _path("shape_%d" % index)
		_write(path, fixtures[index])
		var collection = Collection.new(path)
		check(collection.load_save().status == "corrupt" and collection.read_only, "Malformed root/version/starter shape blocks safely")
		check(collection.owned_count() == 0 and not collection.can_launch(), "Malformed shape cannot create a full catalogue or valid build")
	var partial: String = _path("ownership_type")
	_write(partial, {"schema_version":1, "starter_selected":"breaker", "owned_part_ids":"all", "equipped_build":null})
	var conservative = Collection.new(partial)
	check(conservative.load_save().ok and conservative.is_initialized(), "Known historical starter survives malformed ownership field")
	check(conservative.owned_count() == 0 and not conservative.can_launch(), "Malformed ownership is empty, never assumed fully owned")

func _test_future_version_and_reset() -> void:
	var path: String = _path("future")
	var future: Dictionary = {"schema_version":99, "starter_selected":"breaker", "owned_part_ids":["blade:future_part"], "future_collection_metadata":{"retain":"me"}}
	_write(path, future)
	var untouched: String = FileAccess.get_file_as_string(path)
	var collection = Collection.new(path)
	check(collection.load_save().status == "future_version" and collection.read_only, "Future schema is preserved behind a read-only gate")
	check(collection.initialize_starter("breaker").status == "read_only", "Older build cannot overwrite future starter ownership")
	check(collection.grant_part("blade:guard").status == "read_only" and collection.equip_build(Starters.build_for("breaker")).status == "read_only", "All normal mutations reject future save writes")
	check(FileAccess.get_file_as_string(path) == untouched, "Future save bytes remain unchanged")
	check(collection.reset_collection().status == "explicit_reset_required", "Testing reset never activates without explicit intent")
	check(FileAccess.get_file_as_string(path) == untouched, "Implicit reset cannot delete the future collection")
	var preferences: String = isolated_dir.path_join("prototype.cfg")
	_write(preferences, "[settings]\nvolume=0.35\n")
	check(collection.reset_collection(true).ok, "Explicit dev/test reset can start a genuine fresh collection")
	check(not FileAccess.file_exists(path) and collection.owned_count() == 0 and not collection.is_initialized(), "Explicit reset removes only collection ownership")
	check(FileAccess.get_file_as_string(preferences) == "[settings]\nvolume=0.35\n", "Collection reset preserves unrelated preferences")
	check(collection.initialize_starter("bastion").ok, "Explicit reset permits a new ceremony choice")
	var live: String = _path("future_replaced_live")
	var older = Collection.new(live)
	older.load_save()
	older.initialize_starter("breaker")
	_write(live, future)
	var preserved: String = FileAccess.get_file_as_string(live)
	check(older.grant_part("blade:guard").status == "write_failed" and older.read_only, "Write time rechecks externally replaced future schema")
	check(FileAccess.get_file_as_string(live) == preserved and not older.owns_part("blade:guard"), "Live old instance preserves future bytes and does not commit a reward")
	var backup_path: String = _path("future_backup_live")
	var prior = Collection.new(backup_path)
	prior.load_save()
	prior.initialize_starter("vane")
	_write(backup_path + ".bak", future)
	var main_bytes: String = FileAccess.get_file_as_string(backup_path)
	check(prior.grant_part("blade:guard").status == "write_failed" and prior.read_only, "A future backup also prevents downgrade during live writes")
	check(FileAccess.get_file_as_string(backup_path) == main_bytes and _disk(backup_path + ".bak") == future, "Future backup and existing primary both remain intact")
