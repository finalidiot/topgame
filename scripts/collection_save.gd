extends RefCounted
class_name CollectionSave
## Permanent part ownership. Run XP, powers, RPM and encounters never enter this
## schema. Catalogue keys are qualified by category, not labels or array positions.
## A write stages memory, verifies a neighbouring temporary file, preserves a
## valid previous backup, then replaces the primary. Interrupted temps are ignored.

const Catalog = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")
const SCHEMA_VERSION: int = 1
const DEFAULT_PATH: String = "user://collection.json"
const CATEGORIES: Array[String] = ["blade", "ratchet", "bit"]

var save_path: String
var load_status: String = "fresh"
var last_error: String = ""
var read_only: bool = false
var starter_id: String:
	get: return str(_data.get("starter_selected", ""))
var _data: Dictionary = _empty_state()
var _write_status: String = "write_failed"

func _init(path: String = DEFAULT_PATH) -> void:
	save_path = path

static func _empty_state() -> Dictionary:
	return {"schema_version":SCHEMA_VERSION, "starter_selected":"", "owned_part_ids":[], "equipped_build":{}}

static func part_id(category: String, local_id: String) -> String:
	var qualified: String = "%s:%s" % [category, local_id]
	return qualified if is_valid_part_id(qualified) else ""

static func split_part_id(qualified_id: String) -> Dictionary:
	var fields: PackedStringArray = qualified_id.split(":", true)
	if fields.size() != 2: return {}
	return {"category":str(fields[0]), "id":str(fields[1])}

static func is_valid_part_id(qualified_id: String) -> bool:
	var fields: Dictionary = split_part_id(qualified_id)
	if fields.is_empty() or not Catalog.PARTS.has(fields.category): return false
	return Catalog.PARTS[fields.category].has(fields.id)

func is_initialized() -> bool:
	return starter_id in Starters.IDS

func owns_part(qualified_id: String) -> bool:
	return is_valid_part_id(qualified_id) and qualified_id in _data.owned_part_ids

func owned_parts(category: String = "") -> Array[String]:
	var result: Array[String] = []
	if category.is_empty():
		for id: String in _data.owned_part_ids: result.append(id)
	elif category in CATEGORIES:
		# Catalogue order is useful for menus; persistent identity is still the ID.
		for local_id: String in Catalog.PARTS[category]:
			if owns_part(part_id(category, local_id)): result.append(local_id)
	return result

func owned_count(category: String = "") -> int:
	return owned_parts(category).size()

func equipped_build() -> Dictionary:
	return _data.equipped_build.duplicate(true)

func can_equip_build(build: Dictionary) -> bool:
	return is_initialized() and _legal_owned_build(build, _data.owned_part_ids)

func can_launch() -> bool:
	return can_equip_build(_data.equipped_build) and not read_only

func snapshot() -> Dictionary:
	var result: Dictionary = _data.duplicate(true)
	result.owned_parts = {}
	for category: String in CATEGORIES: result.owned_parts[category] = owned_parts(category)
	result.total_owned = owned_count()
	result.can_launch = can_launch()
	result.read_only = read_only
	result.load_status = load_status
	return result

func load_save() -> Dictionary:
	_data = _empty_state()
	last_error = ""
	read_only = false
	var primary: Dictionary = _read_save(save_path)
	if primary.status == "future_version":
		return _block_load("future_version", "This collection was saved by a newer game version.")
	if primary.ok:
		_data = primary.state
		load_status = primary.status
		if not can_launch(): last_error = "The saved collection has no complete owned assembly. No missing parts were granted."
		return _result(true, load_status)
	var backup: Dictionary = _read_save(save_path + ".bak")
	if backup.status == "future_version":
		return _block_load("future_version", "The collection backup belongs to a newer game version.")
	if backup.ok:
		_data = backup.state
		load_status = "recovered_backup"
		last_error = "Recovered the last valid collection backup."
		return _result(true, load_status)
	if primary.status == "missing" and backup.status == "missing":
		load_status = "fresh"
		return _result(true, load_status)
	return _block_load("corrupt", "The collection cannot be read safely. Restore a backup or explicitly reset the collection for testing.")

func _block_load(status: String, message: String) -> Dictionary:
	load_status = status
	last_error = message
	read_only = true
	return _result(false, status)

func initialize_starter(id: String) -> Dictionary:
	if read_only: return _result(false, "read_only")
	if is_initialized(): return _result(false, "already_initialized")
	if not id in Starters.IDS: return _result(false, "invalid_starter")
	var candidate: Dictionary = _empty_state()
	candidate.starter_selected = id
	candidate.equipped_build = Starters.build_for(id)
	for category: String in CATEGORIES:
		candidate.owned_part_ids.append(part_id(category, candidate.equipped_build[category]))
	candidate.owned_part_ids.sort()
	return _commit(candidate, "initialized")

func grant_part(qualified_id: String) -> Dictionary:
	if read_only: return _result(false, "read_only")
	if not is_initialized(): return _result(false, "not_initialized")
	if not is_valid_part_id(qualified_id): return _result(false, "invalid_part")
	if owns_part(qualified_id): return _result(true, "already_owned")
	var candidate: Dictionary = _data.duplicate(true)
	candidate.owned_part_ids.append(qualified_id)
	candidate.owned_part_ids.sort()
	return _commit(candidate, "newly_acquired")

func equip_build(build: Dictionary) -> Dictionary:
	if read_only: return _result(false, "read_only")
	if not is_initialized(): return _result(false, "not_initialized")
	if not _catalogue_build(build): return _result(false, "invalid_build")
	if not _legal_owned_build(build, _data.owned_part_ids): return _result(false, "unowned_part")
	var candidate: Dictionary = _data.duplicate(true)
	candidate.equipped_build = build.duplicate(true)
	return _commit(candidate, "equipped")

func reset_collection(explicitly_requested: bool = false) -> Dictionary:
	if not explicitly_requested: return _result(false, "explicit_reset_required")
	# Exact named files only. Preferences and unrelated user data are untouched.
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var path: String = ProjectSettings.globalize_path(save_path + suffix)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			last_error = "Unable to remove the collection file: " + suffix
			return _result(false, "reset_failed")
	_data = _empty_state()
	read_only = false
	load_status = "fresh"
	last_error = ""
	return _result(true, "reset")

func _commit(candidate: Dictionary, status: String) -> Dictionary:
	if not _write_save(candidate): return _result(false, _write_status)
	_data = candidate.duplicate(true)
	load_status = "loaded"
	last_error = ""
	return _result(true, status)

func _write_save(candidate: Dictionary) -> bool:
	_write_status = "write_failed"
	var primary_path: String = ProjectSettings.globalize_path(save_path)
	var previous: Dictionary = _read_save(primary_path)
	var prior_backup: Dictionary = _read_save(primary_path + ".bak")
	# Recheck at write time as well: a newer application may have replaced the
	# file after this instance loaded. Never downgrade that future schema.
	if previous.status == "future_version" or prior_backup.status == "future_version":
		read_only = true
		load_status = "future_version"
		last_error = "The collection was replaced by a newer game version."
		return false
	# Optimistic single-writer protection. A second game window must reload its
	# committed state instead of replacing another window's choice or grants.
	# A recovered backup is also authoritative when the primary is interrupted.
	var committed: Dictionary = previous.get("state", {}) if previous.ok else prior_backup.get("state", {})
	if not committed.is_empty() and committed != _data:
		return _reject_stale_write("Your collection changed in another session. Close other game windows and reload before saving.")
	if committed.is_empty():
		if previous.status != "missing" or prior_backup.status != "missing":
			read_only = true
			load_status = "corrupt"
			_write_status = "read_only"
			last_error = "The collection cannot be safely read. Reload or explicitly reset it for testing."
			return false
		if is_initialized():
			return _reject_stale_write("Your collection was removed in another session. Reload before saving.")
	if primary_path.is_empty() or DirAccess.make_dir_recursive_absolute(primary_path.get_base_dir()) != OK:
		last_error = "Unable to create the collection save directory."
		return false
	var payload: String = JSON.stringify(candidate, "\t", true)
	if not _write_file(primary_path + ".tmp", payload):
		last_error = "Unable to write and verify the collection temporary file."
		return false
	# Never copy a corrupt primary over a valid backup. Backup is the previous
	# successfully readable state, not an interrupted staging file.
	if previous.ok:
		if not _write_file(primary_path + ".bak.tmp", JSON.stringify(previous.state, "\t", true)):
			last_error = "Unable to preserve the previous collection backup."
			return false
		if DirAccess.rename_absolute(primary_path + ".bak.tmp", primary_path + ".bak") != OK:
			last_error = "Unable to replace the collection backup."
			return false
	if DirAccess.rename_absolute(primary_path + ".tmp", primary_path) != OK:
		last_error = "Unable to replace the collection save. The valid backup remains available."
		return false
	# Seed a backup after the first successful primary commit. Its absence cannot
	# turn an already successful ownership choice into an apparent failed choice.
	if not FileAccess.file_exists(primary_path + ".bak"):
		if _write_file(primary_path + ".bak.tmp", payload):
			DirAccess.rename_absolute(primary_path + ".bak.tmp", primary_path + ".bak")
	return true

func _reject_stale_write(message: String) -> bool:
	read_only = true
	load_status = "stale_save"
	_write_status = "stale_save"
	last_error = message
	return false

func _write_file(path: String, payload: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(payload)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK and FileAccess.get_file_as_string(path) == payload

func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false, "status":"missing"}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok":false, "status":"unreadable"}
	var text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary: return {"ok":false, "status":"malformed"}
	return _sanitize(parser.data)

static func _sanitize(raw: Dictionary) -> Dictionary:
	var version: Variant = raw.get("schema_version", null)
	if not (version is int or version is float): return {"ok":false, "status":"malformed"}
	if float(version) != floorf(float(version)) or int(version) < 0: return {"ok":false, "status":"malformed"}
	if int(version) > SCHEMA_VERSION: return {"ok":false, "status":"future_version"}
	var chosen: Variant = raw.get("starter_selected", raw.get("starter_id", "") if int(version) == 0 else "")
	if not chosen is String or not chosen in Starters.IDS: return {"ok":false, "status":"malformed"}
	var clean: Dictionary = _empty_state()
	clean.starter_selected = chosen
	var raw_owned: Variant = raw.get("owned_part_ids", [])
	# Explicit schema-0 fixture: category-local ownership and build keys.
	if int(version) == 0 and raw.get("owned_parts", null) is Dictionary:
		raw_owned = []
		for category: String in CATEGORIES:
			var local_ids: Variant = raw.owned_parts.get(category, [])
			if local_ids is Array:
				for local_id: Variant in local_ids:
					if local_id is String: raw_owned.append(part_id(category, local_id))
	if raw_owned is Array:
		for id: Variant in raw_owned:
			if id is String and is_valid_part_id(id) and not id in clean.owned_part_ids:
				clean.owned_part_ids.append(id)
	clean.owned_part_ids.sort()
	var raw_build: Variant = raw.get("equipped_build", raw.get("build", {}) if int(version) == 0 else {})
	if raw_build is Dictionary and _legal_owned_build(raw_build, clean.owned_part_ids):
		clean.equipped_build = raw_build.duplicate(true)
	else:
		clean.equipped_build = _fallback_build(clean.owned_part_ids, str(chosen))
	var comparable: Dictionary = raw.duplicate(true)
	comparable.schema_version = int(version)
	var status: String = "migrated" if int(version) == 0 else ("loaded" if clean == comparable else "loaded_repaired")
	return {"ok":true, "status":status, "state":clean}

static func _catalogue_build(build: Dictionary) -> bool:
	if build.size() != CATEGORIES.size(): return false
	for category: String in CATEGORIES:
		if not build.get(category, null) is String or not Catalog.PARTS[category].has(build[category]): return false
	return true

static func _legal_owned_build(build: Dictionary, ownership: Array) -> bool:
	if not _catalogue_build(build): return false
	for category: String in CATEGORIES:
		if not part_id(category, str(build[category])) in ownership: return false
	return true

static func _fallback_build(ownership: Array, chosen: String) -> Dictionary:
	var starter_build: Dictionary = Starters.build_for(chosen)
	if _legal_owned_build(starter_build, ownership): return starter_build
	var result: Dictionary = {}
	for category: String in CATEGORIES:
		for local_id: String in Catalog.PARTS[category]:
			if part_id(category, local_id) in ownership:
				result[category] = local_id
				break
	return result if result.size() == CATEGORIES.size() else {}

static func _result(ok: bool, status: String) -> Dictionary:
	return {"ok":ok, "status":status}
