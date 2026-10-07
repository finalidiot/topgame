extends SceneTree
## Real persistent transactions, isolated filesystem fault injection and recovery.
const Collection = preload("res://scripts/collection_save.gd")
const Economy = preload("res://scripts/packet_economy.gd")
const Catalog = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")

class Interrupted extends "res://scripts/collection_save.gd":
	var fail_suffix: String = ""
	func _write_file(path: String, payload: String) -> bool:
		if not fail_suffix.is_empty() and path.ends_with(fail_suffix):
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(payload.left(19))
				file.flush()
				file.close()
			return false
		return super._write_file(path,payload)

var checks: int = 0
var failures: int = 0
var directory: String
var report_path: String = ""
var evidence: Array[String] = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _write(path: String, raw: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Isolated fixture opens")
	if file != null:
		file.store_string(raw if raw is String else JSON.stringify(raw))
		file.close()

func _disk(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _new(name: String, starter: String = "breaker") -> RefCounted:
	var collection = Collection.new(directory.path_join(name + ".json"))
	check(collection.load_save().ok and collection.initialize_starter(starter).ok,"Fresh isolated starter initializes")
	return collection

func _outcome(threats: int = 5, elites: int = 0, bosses: int = 0) -> Dictionary:
	return {"reward_provenance":"earned-clear-v1","reward_fixture":false,"earned_threats_cleared":threats,"earned_elites_cleared":elites,"earned_bosses_cleared":bosses}

func _earn(collection: RefCounted, threats: int = 5) -> Dictionary:
	var started: Dictionary = collection.begin_reward_run()
	check(started.ok and not str(started.run_id).is_empty(),"Durable run reward nonce acquired")
	var result: Dictionary = collection.pay_run_reward(str(started.run_id),_outcome(threats))
	check(result.ok,"Eligible earned outcome settles")
	return result

func _run() -> void:
	directory = OS.get_temp_dir().path_join("spinning_metal_packet_transactions_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	check(DirAccess.make_dir_recursive_absolute(directory) == OK,"Isolated transaction QA root created")
	_migration()
	_rewards()
	_purchase_recovery()
	_write_failure()
	_duplicates_reclaimed()
	_corruption_limits()
	_reset_backup()
	# Evidence fixtures are intentionally retained; no production profile touched.
	if not report_path.is_empty():
		check(report_path.is_absolute_path() and not FileAccess.file_exists(report_path),"Evidence path is new and absolute")
		var file: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"status":"passed" if failures == 0 else "failed","checks":checks,"failures":failures,"fixture_directory":directory,"contracts":evidence},"\t"))
			file.close()
	print("PACKET_TRANSACTIONS_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)

func _migration() -> void:
	var path: String = directory.path_join("accepted_schema_1.json")
	var build: Dictionary = Starters.build_for("vane")
	var old: Dictionary = {"schema_version":1,"starter_selected":"vane","owned_part_ids":["blade:hook","blade:hammerfall","ratchet:mid","bit:rubber"],"equipped_build":build}
	_write(path,old)
	var bytes: String = FileAccess.get_file_as_string(path)
	var save = Collection.new(path)
	check(save.load_save().status == "migrated","Accepted main schema1 migrates")
	check(save.starter_id == "vane" and save.equipped_build() == build and save.owned_count() == 4,"Migration preserves historical starter, mixed ownership and exact equipment")
	check(save.credits == 0 and save.salvage == 0 and save.pending_packet().is_empty(),"Migration economic fields start empty without grants")
	check(FileAccess.get_file_as_string(path) == bytes,"Read-only migration leaves original accepted bytes unchanged")
	var archived: Dictionary = save.backup_collection()
	check(archived.ok and FileAccess.get_sha256(str(archived.backup_directory).path_join(path.get_file())) == FileAccess.get_sha256(path),"Explicit backup preserves accepted bytes before first write")
	_earn(save)
	check(int(_disk(path).schema_version) == 2 and save.owned_count() == 4,"First economical mutation persists schema2 without broad ownership")
	evidence.append("accepted-schema-1 migration + exact-byte backup before mutation")

func _rewards() -> void:
	var save = _new("rewards")
	var nonce: String = str(save.begin_reward_run().run_id)
	var settled: Dictionary = save.pay_run_reward(nonce,_outcome(5,1,1))
	check(settled.ok and int(settled.credits_earned) == 100 and save.credits == 100,"Data formula pays actual earned progress: 5*12+10+30")
	var disk: String = FileAccess.get_file_as_string(save.save_path)
	check(save.pay_run_reward(nonce,_outcome(500)).status == "already_paid" and save.credits == 100,"Repeated callback cannot inflate Run reward")
	check(FileAccess.get_file_as_string(save.save_path) == disk,"Duplicate payout doesn't rewrite disk")
	var reload = Collection.new(save.save_path)
	check(reload.load_save().ok and reload.pay_run_reward(nonce,_outcome(500)).status == "already_paid","Reward guard survives process reload")
	check(reload.credits == 100,"Reloaded Results cannot double pay")
	var abandon: String = str(reload.begin_reward_run().run_id)
	check(reload.abort_reward_run(abandon).ok and not reload.pay_run_reward(abandon,_outcome()).ok,"Abort/restart earns nothing and invalidates token")
	var replaced: String = str(reload.begin_reward_run().run_id)
	var fresh: String = str(reload.begin_reward_run().run_id)
	check(not reload.pay_run_reward(replaced,_outcome()).ok,"New launch invalidates an abandoned previous Run token")
	check(reload.pay_run_reward(fresh,_outcome(0)).status == "no_reward" and reload.credits == 100,"AFK survival with zero earned clears pays zero")
	var fixture: Dictionary = _outcome(50)
	fixture.reward_fixture = true
	var fixture_nonce: String = str(reload.begin_reward_run().run_id)
	check(reload.pay_run_reward(fixture_nonce,fixture).status == "no_reward" and reload.credits == 100,"Boss/event/QA fixtures cannot farm permanent currency")
	var no_provenance: Dictionary = {"threats_cleared":99,"damage":999999,"survival_time":30000}
	check(Economy.run_reward(no_provenance).credits == 0,"Raw damage/time/XP/collision counts cannot pay")
	var invalid: Dictionary = _outcome(1,2)
	check(Economy.run_reward(invalid).credits == 0,"Invalid elite count cannot exceed earned clear count")
	invalid = _outcome()
	invalid.earned_threats_cleared = -1
	check(Economy.run_reward(invalid).credits == 0,"Negative earned counters rejected")
	invalid.earned_threats_cleared = 1e40
	check(Economy.run_reward(invalid).credits == 0,"Huge counters rejected before integer conversion")
	check(Economy.run_reward(_outcome(1000000)).credits == 600,"Very long genuine run payout capped before wallet addition")
	evidence.append("run nonce persistence, duplicate settlement, abort/restart, fixture and AFK guards, reward overflow")

func _purchase_recovery() -> void:
	var save = _new("purchase")
	check(save.purchase_packet("standard").status == "insufficient_funds","Insufficient funds cannot buy")
	check(save.credits == 0 and save.pending_packet().is_empty(),"Rejected buy leaves no negative balance or phantom receipt")
	_earn(save,10)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9913001
	var request: String = save.expected_packet_request_id()
	var purchase: Dictionary = save.purchase_packet("standard",rng,request)
	var post_purchase: int = 120 - Economy.packet_cost("standard")
	check(purchase.ok and purchase.receipt.status == "pending" and save.credits == post_purchase,"Debit and exact pending results commit together before animation")
	check(save.owned_count() == 3 and save.salvage == 0,"Purchase has not silently granted ownership before finalize")
	var fixed: Dictionary = purchase.receipt.duplicate(true)
	check(save.purchase_packet("standard",rng,request).receipt == fixed and save.credits == post_purchase,"Repeated confirm returns exact same purchased receipt without another debit")
	check(not save.purchase_packet("standard",rng).ok,"A second purchase is blocked until pending packet completes")
	check(save.grant_part("blade:hammerfall").status == "pending_packet","Other reward grants cannot alter fixed duplicate resolution during opening")
	var reload = Collection.new(save.save_path)
	check(reload.load_save().ok and reload.pending_packet() == fixed,"Crash/reload restores exact purchased result without consuming RNG")
	check(reload.credits == post_purchase and not reload.finalize_packet("wrong").ok,"Recovered receipt retains single debit and rejects wrong ID")
	var resolved: Dictionary = reload.finalize_packet(str(fixed.id))
	check(resolved.ok and resolved.receipt.status == "resolved","Ownership and duplicate salvage finalize atomically")
	var expected_new: int = 0
	for row: Dictionary in fixed.rows:
		if bool(row.new): expected_new += 1
	check(reload.owned_count() == 3 + expected_new and reload.salvage == int(fixed.total_salvage),"Visible receipt describes exact ownership and salvage grant")
	var state: Dictionary = reload.snapshot()
	check(reload.finalize_packet(str(fixed.id)).status == "already_finalized" and reload.snapshot() == state,"Repeated finalize cannot duplicate grants or salvage")
	var reveal_reload = Collection.new(save.save_path)
	check(reveal_reload.load_save().ok and reveal_reload.pending_packet().status == "resolved","Crash after grant resumes resolved reveal instead of losing presentation")
	check(reveal_reload.finalize_packet(str(fixed.id)).status == "already_finalized","Resolved reveal resume idempotent")
	check(reveal_reload.acknowledge_packet(str(fixed.id)).ok and reveal_reload.pending_packet().is_empty(),"Inspect/continue explicitly acknowledges completed receipt")
	var acknowledged: Dictionary = reveal_reload.snapshot()
	check(reveal_reload.finalize_packet(str(fixed.id)).status == "already_finalized" and reveal_reload.acknowledge_packet(str(fixed.id)).ok,"Recent receipt guard survives acknowledgment")
	check(reveal_reload.purchase_packet("standard",rng,request).status == "already_purchased" and reveal_reload.snapshot() == acknowledged,"Repeated old confirm after reveal remains idempotent")
	check(reveal_reload.purchase_packet("standard",rng,"packet-99").status == "stale_request","Out-of-order purchase nonce rejects stale confirmation")
	evidence.append("exact three-result paid receipt; reload no reroll/debit; resolved reveal recovery; finalize/ack/confirm idempotence")

func _write_failure() -> void:
	var path: String = directory.path_join("write_fail.json")
	var save = Interrupted.new(path)
	save.load_save()
	save.initialize_starter("breaker")
	_earn(save,10)
	var before: String = FileAccess.get_file_as_string(path)
	save.fail_suffix = ".tmp"
	check(save.purchase_packet("standard").status == "write_failed","Interrupted debit staging reports failure")
	check(save.credits == 120 and save.pending_packet().is_empty() and FileAccess.get_file_as_string(path) == before,"Failed debit keeps wallet and receipt unchanged")
	save.fail_suffix = ""
	var packet: Dictionary = save.purchase_packet("standard")
	check(packet.ok,"Healthy retry creates a single committed paid receipt")
	var paid_bytes: String = FileAccess.get_file_as_string(path)
	save.fail_suffix = ".tmp"
	check(save.finalize_packet(str(packet.receipt.id)).status == "write_failed","Interrupted grant staging reports failure")
	check(save.owned_count() == 3 and save.credits == 120 - Economy.packet_cost("standard") and save.pending_packet().status == "pending" and FileAccess.get_file_as_string(path) == paid_bytes,"Finalize failure retains recoverable debit plus exact contents")
	save.fail_suffix = ".bak.tmp"
	check(save.finalize_packet(str(packet.receipt.id)).status == "write_failed" and FileAccess.get_file_as_string(path) == paid_bytes,"Interrupted backup aborts finalize before authoritative replacement")
	save.fail_suffix = ""
	check(save.finalize_packet(str(packet.receipt.id)).ok,"Healthy retry grants once")
	# Backup is the still-paid pending receipt, so corrupting the final primary
	# recovers the exact paid result and resolves again without duplicate grants.
	_write(path,"{broken-after-grant")
	var recovered = Collection.new(path)
	check(recovered.load_save().status == "recovered_backup" and recovered.pending_packet().rows == packet.receipt.rows,"Corruption after finalize recovers fixed paid pending receipt")
	check(recovered.credits == 120 - Economy.packet_cost("standard") and recovered.finalize_packet(str(packet.receipt.id)).ok,"Recovered grant retains exact single debit")
	var healthy: Dictionary = recovered.snapshot()
	check(recovered.finalize_packet(str(packet.receipt.id)).status == "already_finalized" and recovered.snapshot() == healthy,"Recovery cannot duplicate the recovered grant")
	var second = Collection.new(path)
	second.load_save()
	recovered.acknowledge_packet(str(packet.receipt.id))
	check(second.acknowledge_packet(str(packet.receipt.id)).status == "stale_save" and second.read_only,"Stale concurrent game window cannot erase a newer transaction")
	evidence.append("faults at debit/grant/temp/backup; fixed receipt recovery after corruption; stale-write guard")

func _duplicates_reclaimed() -> void:
	var save = _new("complete")
	for id: String in Economy.eligible_ids(): check(save.grant_part(id).ok,"Full ownership fixture grants known design")
	_earn(save,100)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 37191
	var count: int = 0
	while save.salvage < Economy.packet_cost("reclaimed") and count < 10:
		var receipt: Dictionary = save.purchase_packet("standard",rng).receipt
		check(receipt.rows.all(func(row: Dictionary) -> bool: return not bool(row.new)),"Complete collection always shows duplicate, never fake NEW")
		var before: int = save.salvage
		check(save.finalize_packet(str(receipt.id)).ok and save.salvage == before + int(receipt.total_salvage),"Duplicate row values convert exactly once")
		save.acknowledge_packet(str(receipt.id))
		count += 1
	check(save.salvage >= Economy.packet_cost("reclaimed"),"Duplicates fund useful SALVAGE sink")
	var balance: int = save.salvage
	var reclaimed: Dictionary = save.purchase_packet("reclaimed",rng)
	check(reclaimed.ok and save.salvage == balance - 36,"Reclaimed purchase spends actual SALVAGE")
	check(save.finalize_packet(str(reclaimed.receipt.id)).ok and save.salvage < balance,"Complete-collection recycling always loses SALVAGE")
	check(save.owned_count() == 31,"Design access never becomes duplicate quantity")
	evidence.append("duplicate conversion values; full collection no fake NEW; real reclaimed SALVAGE sink has strict loss")

func _corruption_limits() -> void:
	var save = _new("limits")
	var raw: Dictionary = _disk(save.save_path)
	for value: Variant in [-1, 1.5, 1e40, "100", true]:
		var bad: Dictionary = raw.duplicate(true)
		bad.progression.credits = value
		var path: String = directory.path_join("malformed_%d.json" % checks)
		_write(path,bad)
		check(Collection.new(path).load_save().status == "corrupt","Malformed balance blocked rather than coerced, clamped or wrapped")
	var path: String = directory.path_join("max_balance.json")
	raw.progression.credits = Collection.MAX_BALANCE
	_write(path,raw)
	var full = Collection.new(path)
	check(full.load_save().ok,"Documented wallet maximum safely loads")
	var nonce: String = str(full.begin_reward_run().run_id)
	check(full.pay_run_reward(nonce,_outcome(4)).status == "balance_limit" and full.credits == Collection.MAX_BALANCE,"Overflow refuses addition, retains retryable reward token and never wraps")
	check(full.purchase_packet("standard").ok,"At maximum wallet a real debit can create room")
	check(full.pay_run_reward(nonce,_outcome(4)).ok and full.credits == Collection.MAX_BALANCE,"Retained reward can settle after lawful spending frees space")
	var tampered: Dictionary = _disk(path)
	tampered.progression.pending_packet.rows[0].part_id = "blade:obsolete"
	var bad_receipt: String = directory.path_join("malformed_receipt.json")
	_write(bad_receipt,tampered)
	check(Collection.new(bad_receipt).load_save().status == "corrupt","Invalid fixed receipt blocks instead of deleting paid results")
	var full_salvage = _new("full_salvage")
	for id: String in Economy.eligible_ids(): check(full_salvage.grant_part(id).ok,"Maximum SALVAGE fixture owns the eligible designs")
	var maximum: Dictionary = full_salvage._data.duplicate(true)
	maximum.progression.salvage = Collection.MAX_BALANCE
	check(full_salvage._commit(maximum,"maximum_salvage_fixture").ok,"Isolated maximum SALVAGE fixture is a valid bounded save")
	check(full_salvage.purchase_packet("standard").status == "insufficient_funds","Maximum SALVAGE does not permit a primary-currency purchase")
	var reclaimed: Dictionary = full_salvage.purchase_packet("reclaimed")
	check(reclaimed.ok and full_salvage.salvage == Collection.MAX_BALANCE - Economy.packet_cost("reclaimed"),"Reclaimed spends SALVAGE before checking prospective duplicate-return capacity")
	check(full_salvage.finalize_packet(str(reclaimed.receipt.id)).ok,"The exact paid Reclaimed receipt finalizes at maximum starting SALVAGE")
	check(full_salvage.salvage == Collection.MAX_BALANCE - Economy.packet_cost("reclaimed") + int(reclaimed.receipt.total_salvage) and full_salvage.salvage < Collection.MAX_BALANCE,"A full-wallet Reclaimed returns exact recorded duplicates while reducing SALVAGE")
	var after_reclaimed: Dictionary = full_salvage.snapshot()
	check(full_salvage.finalize_packet(str(reclaimed.receipt.id)).status == "already_finalized" and full_salvage.snapshot() == after_reclaimed,"Maximum-wallet Reclaimed replay cannot grant duplicate SALVAGE twice")
	evidence.append("negative/fractional/huge/bool balance refusal; bounded addition with recoverable token; malformed receipt conservatism")
	evidence.append("maximum SALVAGE Reclaimed purchase uses prospective debit capacity; exact duplicate return stays below maximum; replay idempotent")

func _reset_backup() -> void:
	var save = _new("reset")
	_earn(save,10)
	var receipt: Dictionary = save.purchase_packet("standard").receipt
	var before: String = FileAccess.get_file_as_string(save.save_path)
	var settings: String = directory.path_join("prototype.cfg")
	_write(settings,"[settings]\nvolume=0.35\n")
	check(save.reset_collection().status == "explicit_reset_required","Progression reset still requires explicit request")
	var reset: Dictionary = save.reset_collection(true)
	check(reset.ok,"Backup-first progression reset succeeds")
	check(save.credits == 0 and save.salvage == 0 and save.owned_count() == 0 and save.pending_packet().is_empty() and not save.is_initialized(),"Reset clears starter, ownership, wallet, salvage, transaction and reward guards")
	check(FileAccess.get_file_as_string(str(reset.backup_directory).path_join("reset.json")) == before,"Reset backup retains exact pre-reset paid receipt and wallet bytes")
	check(FileAccess.get_file_as_string(settings) == "[settings]\nvolume=0.35\n","Collection reset preserves separately managed settings")
	check(not str(receipt.id).is_empty(),"Reset fixture included a genuine pending purchase")
	evidence.append("backup-first full progression reset; exact paid pending-state backup; settings retained")
