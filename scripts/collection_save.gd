extends RefCounted
class_name CollectionSave
## Permanent part ownership. Run XP, powers, RPM and encounters never enter this
## schema. Catalogue keys are qualified by category, not labels or array positions.
## A write stages memory, verifies a neighbouring temporary file, preserves a
## valid previous backup, then replaces the primary. Interrupted temps are ignored.

const Catalog = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")
const Economy = preload("res://scripts/packet_economy.gd")
const SCHEMA_VERSION: int = 2
const MAX_BALANCE: int = 1000000000
const DEFAULT_PATH: String = "user://collection.json"
const CATEGORIES: Array[String] = ["blade", "ratchet", "bit"]

var save_path: String
var load_status: String = "fresh"
var last_error: String = ""
var read_only: bool = false
var starter_id: String:
	get: return str(_data.get("starter_selected", ""))
var credits: int:
	get: return int(_data.progression.credits)
var salvage: int:
	get: return int(_data.progression.salvage)
var _data: Dictionary = _empty_state()
var _write_status: String = "write_failed"
var last_backup_path: String = ""

func _init(path: String = DEFAULT_PATH) -> void:
	save_path = path

static func _empty_state() -> Dictionary:
	return {"schema_version":SCHEMA_VERSION, "starter_selected":"", "owned_part_ids":[], "equipped_build":{},
		"progression":{"credits":0,"salvage":0,"packet_serial":0,"pending_packet":{},"last_packet":{},"run_serial":0,"active_run":"","last_reward":{}}}

func wallet() -> Dictionary:
	return {"credits":credits,"salvage":salvage}

func pending_packet() -> Dictionary:
	return _data.progression.pending_packet.duplicate(true)

func expected_packet_request_id() -> String:
	return "packet-%d" % (int(_data.progression.packet_serial) + 1)

func purchase_packet(kind: String, rng: RandomNumberGenerator = null, request_nonce: String = "") -> Dictionary:
	if read_only: return _result(false, "read_only")
	if not is_initialized(): return _result(false, "not_initialized")
	if not Economy.validate_config().is_empty(): return _result(false, "invalid_economy")
	var pending: Dictionary = pending_packet()
	if not pending.is_empty():
		return {"ok":request_nonce == str(pending.id),"status":"pending_packet","receipt":pending}
	var last: Dictionary = _data.progression.last_packet
	if not request_nonce.is_empty() and request_nonce == str(last.get("id", "")):
		return {"ok":true,"status":"already_purchased","receipt":last.duplicate(true)}
	if not request_nonce.is_empty() and request_nonce != expected_packet_request_id(): return _result(false, "stale_request")
	var products: Dictionary = Economy.config().packets
	if not products.has(kind): return _result(false, "invalid_packet")
	var product: Dictionary = products[kind]
	var currency: String = str(product.currency)
	var cost: int = int(product.cost)
	if int(_data.progression[currency]) < cost: return _result(false, "insufficient_funds")
	if int(_data.progression.packet_serial) >= MAX_BALANCE: return _result(false, "counter_limit")
	var roll: Dictionary = Economy.generate(kind, _data.owned_part_ids, rng)
	if not bool(roll.ok): return roll
	# Fixed NEW/duplicate resolution is part of the paid receipt. Reject grants
	# during opening so ownership cannot drift under the already purchased rows.
	var prospective_salvage: int = salvage - cost if currency == "salvage" else salvage
	if prospective_salvage > MAX_BALANCE - int(roll.total_salvage): return _result(false, "balance_limit")
	var candidate: Dictionary = _data.duplicate(true)
	var receipt: Dictionary = {"id":expected_packet_request_id(),"request_nonce":expected_packet_request_id(),"kind":kind,"cost":cost,"currency":currency,
		"status":"pending","rows":roll.rows,"total_salvage":int(roll.total_salvage)}
	candidate.progression[currency] -= cost
	candidate.progression.packet_serial += 1
	candidate.progression.pending_packet = receipt
	var result: Dictionary = _commit(candidate, "purchased")
	if result.ok: result.receipt = receipt.duplicate(true)
	return result

func finalize_packet(receipt_id: String) -> Dictionary:
	if read_only: return _result(false, "read_only")
	var receipt: Dictionary = pending_packet()
	if receipt.is_empty():
		var last: Dictionary = _data.progression.last_packet
		if not last.is_empty() and str(last.id) == receipt_id: return {"ok":true,"status":"already_finalized","receipt":last.duplicate(true)}
		return _result(false, "unknown_receipt")
	if str(receipt.id) != receipt_id: return _result(false, "wrong_receipt")
	if str(receipt.status) == "resolved": return {"ok":true,"status":"already_finalized","receipt":receipt}
	if salvage > MAX_BALANCE - int(receipt.total_salvage): return _result(false, "balance_limit")
	var candidate: Dictionary = _data.duplicate(true)
	for row: Dictionary in receipt.rows:
		if bool(row.new): candidate.owned_part_ids.append(str(row.part_id))
	candidate.owned_part_ids.sort()
	candidate.progression.salvage += int(receipt.total_salvage)
	receipt.status = "resolved"
	candidate.progression.pending_packet = receipt
	candidate.progression.last_packet = receipt.duplicate(true)
	var result: Dictionary = _commit(candidate, "finalized")
	if result.ok: result.receipt = receipt.duplicate(true)
	return result

func acknowledge_packet(receipt_id: String) -> Dictionary:
	if read_only: return _result(false, "read_only")
	var receipt: Dictionary = pending_packet()
	if receipt.is_empty():
		return _result(not _data.progression.last_packet.is_empty() and str(_data.progression.last_packet.id) == receipt_id, "already_acknowledged")
	if str(receipt.id) != receipt_id: return _result(false, "wrong_receipt")
	if str(receipt.status) != "resolved": return _result(false, "not_finalized")
	var candidate: Dictionary = _data.duplicate(true)
	candidate.progression.pending_packet = {}
	return _commit(candidate, "acknowledged")

func begin_reward_run() -> Dictionary:
	if read_only: return _result(false, "read_only")
	if not can_launch(): return _result(false, "not_initialized")
	if int(_data.progression.run_serial) >= MAX_BALANCE: return _result(false, "counter_limit")
	var candidate: Dictionary = _data.duplicate(true)
	candidate.progression.run_serial += 1
	var token: String = "run-%d" % int(candidate.progression.run_serial)
	candidate.progression.active_run = token
	var result: Dictionary = _commit(candidate, "run_started")
	if result.ok:
		result.run_id = token
		result.run_nonce = token
	return result

func pay_run_reward(token: String, outcome: Dictionary) -> Dictionary:
	if read_only: return _result(false, "read_only")
	var last: Dictionary = _data.progression.last_reward
	if not last.is_empty() and str(last.id) == token:
		return {"ok":true,"status":"already_paid","credits_earned":int(last.credits),"wallet":wallet(),"reward":last.duplicate(true)}
	if token.is_empty() or token != str(_data.progression.active_run): return _result(false, "unknown_run")
	var reward: Dictionary = Economy.run_reward(outcome)
	var amount: int = int(reward.credits)
	if credits > MAX_BALANCE - amount: return _result(false, "balance_limit")
	var candidate: Dictionary = _data.duplicate(true)
	candidate.progression.credits += amount
	candidate.progression.active_run = ""
	candidate.progression.last_reward = {"id":token,"credits":amount,"breakdown":reward.breakdown,"eligible":bool(reward.eligible)}
	var result: Dictionary = _commit(candidate, "paid" if amount > 0 else "no_reward")
	if result.ok:
		result.credits_earned = amount
		result.wallet = wallet()
		result.reward = candidate.progression.last_reward.duplicate(true)
	return result

func abort_reward_run(token: String) -> Dictionary:
	if read_only: return _result(false, "read_only")
	if token.is_empty() or token != str(_data.progression.active_run): return _result(false, "unknown_run")
	var candidate: Dictionary = _data.duplicate(true)
	candidate.progression.active_run = ""
	return _commit(candidate, "aborted")

func begin_run_reward() -> Dictionary:
	return begin_reward_run()

func settle_run_reward(token: String, outcome: Dictionary) -> Dictionary:
	return pay_run_reward(token, outcome)

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
	result.credits = credits
	result.salvage = salvage
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
	if not _data.progression.pending_packet.is_empty(): return _result(false, "pending_packet")
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

func backup_collection() -> Dictionary:
	var source: String = ProjectSettings.globalize_path(save_path).replace("\\", "/").simplify_path()
	var project: String = ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/") + "/"
	if not source.is_absolute_path() or source.get_extension().to_lower() != "json" or source.to_lower().begins_with(project.to_lower()):
		return _result(false, "unsafe_save_path")
	var files: Array[Dictionary] = []
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var path: String = source + suffix
		if DirAccess.dir_exists_absolute(path): return _result(false, "unexpected_save_directory")
		if FileAccess.file_exists(path):
			var input: FileAccess = FileAccess.open(path, FileAccess.READ)
			if input == null: return _result(false, "unreadable_save")
			input.close()
			files.append({"source":path,"name":path.get_file(),"sha256":FileAccess.get_sha256(path)})
	if files.is_empty(): return {"ok":true,"status":"no_save_files","backup_directory":"","files":[]}
	var stamp: String = Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	var archive: String = source.get_base_dir().path_join("collection-backups").path_join(source.get_file().get_basename()).path_join("backup_%s_%d_%d" % [stamp, OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.dir_exists_absolute(archive) or DirAccess.make_dir_recursive_absolute(archive) != OK:
		return _result(false, "backup_directory_failed")
	for row: Dictionary in files:
		var destination: String = archive.path_join(str(row.name))
		if DirAccess.copy_absolute(str(row.source), destination) != OK or FileAccess.get_sha256(destination) != row.sha256:
			return _result(false, "backup_verification_failed")
	# Corrupt/future saves and interrupted temps are retained as exact bytes.
	# No sanitisation, rewrite or preference/settings copy is involved.
	var manifest_path: String = archive.path_join("manifest.json")
	var payload: String = JSON.stringify({"schema":1,"purpose":"explicit_collection_backup","created_utc":Time.get_datetime_string_from_system(true),"source":source,"files":files}, "\t")
	if not _write_file(manifest_path, payload): return _result(false, "backup_manifest_failed")
	if not _files_match_backup(files): return _result(false, "save_changed_during_backup")
	last_backup_path = archive
	return {"ok":true,"status":"backed_up","backup_directory":archive,"files":files}

func _files_match_backup(files: Array, removed: Array = []) -> bool:
	# Absent siblings are part of the inventory too. A concurrent writer must
	# not create a new backup/temp that can silently restore the old collection.
	var source: String = ProjectSettings.globalize_path(save_path).replace("\\", "/").simplify_path()
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var path: String = source + suffix
		var expected: String = ""
		for row: Dictionary in files:
			if str(row.source) == path and row not in removed: expected = str(row.sha256)
		if DirAccess.dir_exists_absolute(path): return false
		if expected.is_empty():
			if FileAccess.file_exists(path): return false
		elif not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != expected: return false
	return true

func _restore_removed_collection(removed: Array, archive: String) -> void:
	for row: Dictionary in removed:
		if not FileAccess.file_exists(str(row.source)) and not DirAccess.dir_exists_absolute(str(row.source)):
			DirAccess.copy_absolute(archive.path_join(str(row.name)), str(row.source))

func reset_collection(explicitly_requested: bool = false) -> Dictionary:
	if not explicitly_requested: return _result(false, "explicit_reset_required")
	var backup: Dictionary = backup_collection()
	if not bool(backup.ok):
		last_error = "Reset stopped because a verified collection backup could not be made."
		return _result(false, str(backup.status))
	var removed: Array[Dictionary] = []
	if not _files_match_backup(backup.files):
		last_error = "The collection changed during backup. Close other game instances and retry."
		return {"ok":false,"status":"save_changed_during_backup","backup_directory":backup.backup_directory}
	for row: Dictionary in backup.files:
		# Exact files only, rechecked immediately before removal. A concurrent
		# replacement is preserved; already removed files can be restored safely.
		var path: String = str(row.source)
		if not _files_match_backup(backup.files, removed) or DirAccess.remove_absolute(path) != OK:
			_restore_removed_collection(removed, str(backup.backup_directory))
			last_error = "Reset could not finish. The verified backup is retained. Close other game instances and retry."
			return {"ok":false,"status":"reset_failed","backup_directory":backup.backup_directory}
		removed.append(row)
	if not _files_match_backup(backup.files, removed):
		_restore_removed_collection(removed, str(backup.backup_directory))
		last_error = "Another game instance wrote during reset. The verified backup is retained."
		return {"ok":false,"status":"reset_failed","backup_directory":backup.backup_directory}
	_data = _empty_state()
	read_only = false
	load_status = "fresh"
	last_error = ""
	return {"ok":true,"status":"reset","backup_directory":backup.backup_directory,"files":backup.files}

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
	if int(version) >= 2:
		var progression: Variant = raw.get("progression", null)
		if not progression is Dictionary: return {"ok":false,"status":"malformed"}
		for key: String in ["credits", "salvage", "packet_serial", "run_serial"]:
			if not _safe_integer(progression.get(key, null), MAX_BALANCE): return {"ok":false,"status":"malformed"}
			clean.progression[key] = int(progression[key])
		var active: Variant = progression.get("active_run", null)
		if not active is String or (not str(active).is_empty() and str(active) != "run-%d" % int(clean.progression.run_serial)):
			return {"ok":false,"status":"malformed"}
		clean.progression.active_run = active
		for key: String in ["pending_packet", "last_packet"]:
			var receipt: Variant = progression.get(key, null)
			if not receipt is Dictionary: return {"ok":false,"status":"malformed"}
			if not receipt.is_empty():
				if not _valid_receipt(receipt, clean.owned_part_ids, int(clean.progression.packet_serial), key == "pending_packet"):
					return {"ok":false,"status":"malformed"}
				clean.progression[key] = receipt.duplicate(true)
				clean.progression[key].cost = int(receipt.cost)
				clean.progression[key].total_salvage = int(receipt.total_salvage)
				for row: Dictionary in clean.progression[key].rows: row.salvage = int(row.salvage)
		var last_reward: Variant = progression.get("last_reward", null)
		if not last_reward is Dictionary: return {"ok":false,"status":"malformed"}
		if not last_reward.is_empty():
			if not _serial_id(last_reward.get("id", null), "run-", int(clean.progression.run_serial)) or not _safe_integer(last_reward.get("credits", null), 600): return {"ok":false,"status":"malformed"}
			if not last_reward.get("breakdown", null) is Dictionary or not last_reward.get("eligible", null) is bool: return {"ok":false,"status":"malformed"}
			for key: String in ["threats", "elites", "bosses"]:
				if not _safe_integer(last_reward.breakdown.get(key, null), MAX_BALANCE): return {"ok":false,"status":"malformed"}
			if str(last_reward.id) == str(active): return {"ok":false,"status":"malformed"}
			clean.progression.last_reward = last_reward.duplicate(true)
			clean.progression.last_reward.credits = int(last_reward.credits)
			for key: String in ["threats", "elites", "bosses"]: clean.progression.last_reward.breakdown[key] = int(last_reward.breakdown[key])
	var comparable: Dictionary = raw.duplicate(true)
	comparable.schema_version = int(version)
	var status: String = "migrated" if int(version) < SCHEMA_VERSION else ("loaded" if _json_equivalent(clean, comparable) else "loaded_repaired")
	return {"ok":true, "status":status, "state":clean}

static func _json_equivalent(first: Variant, second: Variant) -> bool:
	# JSON decodes numbers as floats. Integral economics are validated and
	# normalized to int, which is not a repair of the player's persisted facts.
	if (first is int or first is float) and (second is int or second is float): return float(first) == float(second)
	if first is Dictionary and second is Dictionary:
		if first.size() != second.size(): return false
		for key: Variant in first:
			if not second.has(key) or not _json_equivalent(first[key], second[key]): return false
		return true
	if first is Array and second is Array:
		if first.size() != second.size(): return false
		for index: int in range(first.size()):
			if not _json_equivalent(first[index], second[index]): return false
		return true
	return first == second

static func _safe_integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= maximum and float(value) == floorf(float(value))

static func _serial_id(value: Variant, prefix: String, maximum: int) -> bool:
	if not value is String or not str(value).begins_with(prefix): return false
	var suffix: String = str(value).trim_prefix(prefix)
	return suffix.is_valid_int() and int(suffix) > 0 and int(suffix) <= maximum and str(int(suffix)) == suffix

static func _valid_receipt(receipt: Dictionary, ownership: Array, serial: int, pending: bool) -> bool:
	if not _serial_id(receipt.get("id", null), "packet-", serial): return false
	if pending and str(receipt.id) != "packet-%d" % serial: return false
	if receipt.get("request_nonce", null) != receipt.id: return false
	var kind: Variant = receipt.get("kind", null)
	var products: Dictionary = Economy.config().packets
	if not kind is String or not products.has(kind): return false
	if not _safe_integer(receipt.get("cost", null), MAX_BALANCE) or int(receipt.cost) <= 0: return false
	# Paid costs and conversion amounts are historical receipt facts. Validate
	# against bounded recorded values rather than rerolling after a balance patch.
	if receipt.get("currency", null) != products[kind].currency: return false
	var status: Variant = receipt.get("status", null)
	if status not in ["pending", "resolved"] or (not pending and status != "resolved"): return false
	var rows: Variant = receipt.get("rows", null)
	if not rows is Array or rows.size() != CATEGORIES.size(): return false
	var total: int = 0
	for index: int in range(rows.size()):
		var row: Variant = rows[index]
		if not row is Dictionary or row.get("category", null) != CATEGORIES[index]: return false
		var category: String = CATEGORIES[index]
		if not row.get("id", null) is String or not is_valid_part_id(category + ":" + str(row.id)): return false
		if row.get("part_id", null) != category + ":" + str(row.id) or row.get("rarity", null) != Catalog.rarity(category, str(row.id)): return false
		if not row.get("new", null) is bool or not _safe_integer(row.get("salvage", null), MAX_BALANCE): return false
		if bool(row.new) and int(row.salvage) != 0: return false
		if not bool(row.new) and int(row.salvage) <= 0: return false
		if (status == "resolved" or not bool(row.new)) and str(row.part_id) not in ownership: return false
		if status == "pending" and bool(row.new) and str(row.part_id) in ownership: return false
		total += int(row.salvage)
	if not _safe_integer(receipt.get("total_salvage", null), MAX_BALANCE) or total != int(receipt.total_salvage): return false
	return true

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
