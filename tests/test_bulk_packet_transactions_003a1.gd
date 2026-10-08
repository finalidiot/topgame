extends SceneTree
## Exact on-disk batch transactions. Wallet fixtures are explicitly isolated;
## all results, debit, grants, checkpoints and reloads use production code.
const Save = preload("res://scripts/collection_save.gd")
const Economy = preload("res://scripts/packet_economy.gd")
const PacketView = preload("res://scripts/packet_view.gd")
class Interrupted extends "res://scripts/collection_save.gd":
	var fail_suffix: String = ""
	func _write_file(path: String, payload: String) -> bool:
		if not fail_suffix.is_empty() and path.ends_with(fail_suffix): return false
		return super._write_file(path, payload)
var checks: int = 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var folder: String
var report: String

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func fresh(name: String, credits: int = 1000, salvage: int = 1000) -> RefCounted:
	var save = Interrupted.new(folder.path_join(name + ".json"))
	check(save.load_save().ok and save.initialize_starter("breaker").ok, "Isolated starter")
	var fixture: Dictionary = save._data.duplicate(true)
	fixture.progression.credits = credits
	fixture.progression.salvage = salvage
	check(save._commit(fixture, "declared_qa_wallet").ok, "Declared QA wallet persists")
	return save

func reload(save: RefCounted) -> RefCounted:
	var loaded = Save.new(save.save_path)
	check(loaded.load_save().ok, "Fresh instance reads actual committed bytes")
	return loaded

func rng(seed_value: int = 19) -> RandomNumberGenerator:
	var source: RandomNumberGenerator = RandomNumberGenerator.new()
	source.seed = seed_value
	return source

func run() -> void:
	folder = OS.get_temp_dir().path_join("spinning_metal_bulk_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "Fresh isolated filesystem")
	for kind: String in ["standard", "reclaimed"]:
		for quantity: int in [1, 3, 5]: exercise(kind, quantity)
	limits_and_failures()
	sequential_completion()
	legacy_migration()
	malformed_batches()
	presentation()
	if not report.is_empty(): check(report.is_absolute_path() and not FileAccess.file_exists(report), "New absolute report")
	var payload: Dictionary = {"status":"passed" if failures.is_empty() else "failed", "checks":checks,"failures":failures,
		"scope":"Production persisted transactions; declared isolated wallet/ownership/seed fixtures, no human profile mutation", "schema":Save.SCHEMA_VERSION,
		"fixture_directory":folder,"transactions":records,"rules":{"quantities":[1,3,5],"one_total_debit_before_art":true,"all_results_fixed_before_art":true,"sequential_reclaimed":true,"grants_atomic_idempotent":true,"cursor_persisted":true,"max_parts":15}}
	if not report.is_empty():
		var file: FileAccess = FileAccess.open(report, FileAccess.WRITE)
		file.store_string(JSON.stringify(payload, "\t"))
		file.close()
	print("BULK_PACKET_TRANSACTIONS_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func exercise(kind: String, quantity: int) -> void:
	var save = fresh(kind + str(quantity))
	var initial: Dictionary = save.snapshot()
	var request: String = save.expected_packet_request_id()
	var source: RandomNumberGenerator = rng()
	var purchased: Dictionary = save.purchase_packet_batch(kind, quantity, source, request)
	check(purchased.ok, "Batch accepted " + kind + str(quantity))
	var fixed: Dictionary = purchased.receipt.duplicate(true)
	var unit: String = str(fixed.currency)
	check(save.wallet()[unit] == initial[unit] - Economy.packet_cost(kind) * quantity, "One complete cost debit")
	check(save.owned_count() == 3 and save.salvage == initial.salvage - (int(fixed.cost) if unit == "salvage" else 0), "No ownership or duplicate grants before finalize")
	check(fixed.packets.size() == quantity and fixed.rows.size() == quantity * 3 and int(fixed.cursor) == 0, "Entire bounded batch persisted before art")
	var state: int = source.state
	check(save.purchase_packet_batch(kind, quantity, source, request).receipt == fixed and source.state == state, "Repeated confirm consumes no RNG/debit")
	check(not save.purchase_packet_batch(kind, quantity, source).ok, "No second receipt before completion")
	var before = reload(save)
	check(before.pending_packet() == fixed, "Close before tear keeps exact paid batch")
	check(before.finalize_packet(str(fixed.id)).ok, "Atomic complete batch grant")
	var new_count: int = 0
	for row: Dictionary in fixed.rows:
		if bool(row.new): new_count += 1
	check(before.owned_count() == 3 + new_count, "Final ownership matches immutable NEW classifications")
	var expected_salvage: int = initial.salvage - (int(fixed.cost) if unit == "salvage" else 0) + int(fixed.total_salvage)
	check(before.salvage == expected_salvage, "Exact duplicate salvage sum once")
	var mid: int = 1 if quantity > 1 else quantity
	check(before.advance_packet_presentation(str(fixed.id), mid).ok, "After packet one checkpoints presentation")
	var halfway = reload(before)
	check(halfway.pending_packet().rows == fixed.rows and int(halfway.pending_packet().cursor) == mid, "Mid-batch reload uses fixed rows and cursor")
	var held: Dictionary = halfway.snapshot()
	check(halfway.finalize_packet(str(fixed.id)).status == "already_finalized" and halfway.snapshot() == held, "Partial reveal never regrants")
	if quantity > 3:
		check(halfway.advance_packet_presentation(str(fixed.id), 2).ok, "Halfway through third retains second complete packet")
		var third = reload(halfway)
		check(int(third.pending_packet().cursor) == 2 and third.pending_packet().packets == fixed.packets, "Third packet cannot reroll")
		halfway = third
	check(halfway.advance_packet_presentation(str(fixed.id), quantity).ok, "Fast Open All commits terminal cursor")
	var result = reload(halfway)
	check(int(result.pending_packet().cursor) == quantity and result.salvage == expected_salvage, "Close on result resumes exact terminal presentation")
	check(result.acknowledge_packet(str(fixed.id)).ok, "Results acknowledgement closes batch")
	var acknowledged: Dictionary = result.snapshot()
	check(result.purchase_packet_batch(kind, quantity, source, request).status == "already_purchased" and result.snapshot() == acknowledged, "Replayed batch nonce cannot buy again")
	check(result.finalize_packet(str(fixed.id)).status == "already_finalized" and result.snapshot() == acknowledged, "Replayed grant cannot duplicate parts")
	check(result.purchase_packet_batch(kind, quantity, source, "packet-999").status == "stale_request", "Stale request rejected")
	records.append({"kind":kind,"quantity":quantity,"seed":19,"save_path":save.save_path,"initial_wallet":{"credits":initial.credits,"salvage":initial.salvage},"cost":fixed.cost,"fixed_paid_receipt":fixed,"final_wallet":result.wallet(),"final_owned":result.owned_parts(),"new_count":new_count,"save_sha256":FileAccess.get_sha256(save.save_path),"crash_points":["before_tear","after_packet_1","mid_packet_3" if quantity == 5 else "mid_batch","result"]})

func limits_and_failures() -> void:
	for quantity: int in [1, 3, 5]:
		var cost: int = Economy.packet_cost("standard") * quantity
		var short = fresh("short" + str(quantity), cost - 1)
		var bytes: String = FileAccess.get_file_as_string(short.save_path)
		check(short.purchase_packet_batch("standard", quantity).status == "insufficient_funds" and FileAccess.get_file_as_string(short.save_path) == bytes, "Complete cost required before any debit")
		var exact = fresh("exact" + str(quantity), cost)
		check(exact.purchase_packet_batch("standard", quantity).ok and exact.credits == 0, "Exact total currency accepted")
	var failed = fresh("write_fail")
	var bytes: String = FileAccess.get_file_as_string(failed.save_path)
	failed.fail_suffix = ".tmp"
	check(not failed.purchase_packet_batch("standard", 5).ok and failed.credits == 1000 and failed.pending_packet().is_empty() and FileAccess.get_file_as_string(failed.save_path) == bytes, "Failed save loses no debit/receipt")
	failed.fail_suffix = ""
	var paid: Dictionary = failed.purchase_packet_batch("standard", 5, rng()).receipt
	var paid_bytes: String = FileAccess.get_file_as_string(failed.save_path)
	failed.fail_suffix = ".bak.tmp"
	check(not failed.finalize_packet(str(paid.id)).ok and failed.owned_count() == 3 and FileAccess.get_file_as_string(failed.save_path) == paid_bytes, "Failed atomic grants retain whole recoverable paid batch")
	failed.fail_suffix = ""
	check(failed.finalize_packet(str(paid.id)).ok, "Grant retry safe")
	failed.fail_suffix = ".tmp"
	var before: Dictionary = failed.snapshot()
	check(not failed.advance_packet_presentation(str(paid.id), 2).ok and failed.snapshot() == before, "Failed cursor write retains last exact checkpoint")
	failed.fail_suffix = ""
	var stale = reload(failed)
	check(failed.advance_packet_presentation(str(paid.id), 1).ok and stale.advance_packet_presentation(str(paid.id), 2).status == "stale_save", "Concurrent stale window cannot replace batch cursor")
	var bound = fresh("overflow", 1000, Save.MAX_BALANCE)
	for id: String in Economy.eligible_ids(): check(bound.grant_part(id).ok, "Complete collection overflow fixture")
	check(bound.purchase_packet_batch("standard", 5, rng()).status == "balance_limit" and bound.credits == 1000, "Duplicate overflow rejects complete debit")
	var reclaimed: Dictionary = bound.purchase_packet_batch("reclaimed", 5, rng())
	check(reclaimed.ok and bound.finalize_packet(str(reclaimed.receipt.id)).ok and bound.salvage < Save.MAX_BALANCE, "Reclaimed total debit creates safe salvage room")
	check(fresh("invalid").purchase_packet_batch("standard", 10).status == "invalid_quantity", "Cap five")

func sequential_completion() -> void:
	var save = fresh("sequential")
	var missing: Array = Economy.eligible_ids("blade").slice(-3)
	for id: String in Economy.eligible_ids():
		if id not in missing: check(save.grant_part(id).ok, "Declared nearly complete isolated collection")
	var ownership: Array = save.owned_parts()
	var fixed: Dictionary = save.purchase_packet_batch("reclaimed", 5, rng(8801)).receipt
	var progression: Array[Dictionary] = []
	for index: int in range(5):
		var fresh_count: int = 0
		for row: Dictionary in fixed.packets[index].rows:
			check(bool(row.new) == (str(row.part_id) not in ownership), "Each packet resolves against prior packet ownership")
			if bool(row.new):
				fresh_count += 1
				ownership.append(str(row.part_id))
		check(fresh_count == (1 if index < missing.size() else 0), "Guaranteed missing blade until collection completes within batch")
		progression.append({"packet":index + 1,"new":fresh_count,"ownership_after":ownership.duplicate()})
	check(save.finalize_packet(str(fixed.id)).ok and save.owned_count() == 31, "Complete partway batch retains duplicate results without false NEW")
	records.append({"kind":"reclaimed","quantity":5,"seed":8801,"missing_before":missing,"sequential_guarantees":progression,"fixed_paid_receipt":fixed,"final_wallet":save.wallet(),"final_owned":save.owned_parts()})

func legacy_migration() -> void:
	for resolved: bool in [false, true]:
		var save = fresh("legacy" + str(resolved))
		var receipt: Dictionary = save.purchase_packet("standard", rng()).receipt
		if resolved: check(save.finalize_packet(str(receipt.id)).ok, "Legacy resolved fixture")
		var old: Dictionary = save._data.duplicate(true)
		old.schema_version = 2
		for key: String in ["pending_packet", "last_packet"]:
			if old.progression[key].is_empty(): continue
			for field: String in ["quantity", "packets", "cursor"]: old.progression[key].erase(field)
		var file: FileAccess = FileAccess.open(save.save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(old))
		file.close()
		var old_bytes: String = FileAccess.get_file_as_string(save.save_path)
		var loaded = reload(save)
		check(loaded.load_status == "migrated" and loaded.pending_packet().rows == receipt.rows, "Schema2 exact paid rows migrate to x1 batch")
		check(FileAccess.get_file_as_string(save.save_path) == old_bytes, "Migration does not rewrite existing profile on read")
		check(loaded.finalize_packet(str(receipt.id)).ok and loaded.owned_count() >= 3, "Legacy receipt finalizes without reroll or double debit")

func presentation() -> void:
	var save = fresh("presentation")
	var receipt: Dictionary = save.purchase_packet_batch("standard", 5, rng()).receipt
	check(save.finalize_packet(str(receipt.id)).ok, "Presentation fixture uses durable grant")
	var view = PacketView.new()
	root.add_child(view)
	var cursors: Array[int] = []
	view.presented.connect(func(cursor: int) -> void: cursors.append(cursor))
	view.configure(save.pending_packet())
	view.tear()
	view._process(3.2)
	check(view.phase == "RESULT" and cursors.has(1) and cursors.has(5), "Coarse delta completes authored bounded batch with checkpoint events")
	check(save.advance_packet_presentation(str(receipt.id), 2).ok, "Real partial checkpoint")
	view.queue_free()
	var resumed = PacketView.new()
	root.add_child(resumed)
	resumed.configure(reload(save).pending_packet(), true)
	check(resumed.phase != "RESULT" and resumed._cursor == 2, "Recovered multi batch resumes remaining physical packets")
	resumed.tear()
	resumed._process(2.5)
	check(resumed.phase == "RESULT", "Remaining batch completes cleanly")
	resumed.queue_free()

func malformed_batches() -> void:
	var save = fresh("malformed_source")
	check(save.purchase_packet_batch("standard", 5, rng()).ok, "Real paid malformed-source fixture")
	var raw: Dictionary = save._data.duplicate(true)
	for issue: String in ["quantity", "cursor", "rows", "group", "total", "duplicate_new"]:
		var broken: Dictionary = raw.duplicate(true)
		var receipt: Dictionary = broken.progression.pending_packet
		match issue:
			"quantity": receipt.quantity = 4
			"cursor": receipt.cursor = 1
			"rows": receipt.rows[3].part_id = "blade:missing"
			"group": receipt.packets.remove_at(2)
			"total": receipt.total_salvage += 1
			"duplicate_new":
				receipt.packets[1].rows[1] = receipt.packets[0].rows[1].duplicate(true)
				receipt.rows[4] = receipt.rows[1].duplicate(true)
				receipt.total_salvage = 0
				for packet: Dictionary in receipt.packets:
					packet.total_salvage = 0
					for row: Dictionary in packet.rows: packet.total_salvage += int(row.salvage)
					receipt.total_salvage += int(packet.total_salvage)
		var path: String = folder.path_join("malformed_" + issue + ".json")
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(broken)); file.close()
		check(Save.new(path).load_save().status == "corrupt", "Malformed paid batch blocked conservatively " + issue)
	var old_nonce: String = str(raw.progression.pending_packet.id)
	check(save.finalize_packet(old_nonce).ok and save.acknowledge_packet(old_nonce).ok, "First valid batch closes")
	var second: Dictionary = save.purchase_packet_batch("standard", 3, rng()).receipt
	check(save.finalize_packet(str(second.id)).ok and save.acknowledge_packet(str(second.id)).ok, "Next valid batch closes")
	var unchanged: Dictionary = save.snapshot()
	check(save.purchase_packet_batch("standard", 5, rng(), old_nonce).status == "stale_request" and save.snapshot() == unchanged, "Replay older than latest guard remains stale without grants/debit")
