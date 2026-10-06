extends RefCounted
## Session-bound permanent reward accounting. Money is calculated centrally by
## PacketEconomy; this ledger verifies the live clear history before settlement.
const PROVENANCE: String = "earned-clear-v1"
const MAX_CLEARS: int = 10000
var run_seed: int = 0
var run_nonce: String = ""
var eligible: bool = false
var _started: bool = false
var _finished: bool = false
var _aborted: bool = false
var _fixture: bool = false
var _seen: Dictionary = {}
var _earned: Dictionary = {"threats":0,"elites":0,"bosses":0}

func start(seed_value: int, nonce: String, can_earn: bool = true) -> void:
	run_seed = seed_value
	run_nonce = nonce
	eligible = can_earn and seed_value != 0 and not nonce.is_empty()
	_started = true
	_finished = false
	_aborted = false
	_fixture = false
	_seen.clear()
	_earned = {"threats":0,"elites":0,"bosses":0}

func observe_clear(summary: Dictionary) -> bool:
	if not _started or _finished or _aborted: return false
	if not summary.get("run_seed", null) is int or int(summary.run_seed) != run_seed: return false
	if not summary.get("threat", null) is int: return false
	var serial: int = int(summary.threat)
	if serial < 1 or serial > MAX_CLEARS or _seen.has(serial): return false
	if str(summary.get("reward_provenance", "")) != PROVENANCE: return false
	if not summary.get("reward_eligible", null) is bool or not summary.get("reward_fixture", null) is bool: return false
	if not str(summary.get("kind", "")) in ["rival", "specialist", "swarm", "elite", "boss"]: return false
	_seen[serial] = true
	_fixture = _fixture or bool(summary.reward_fixture)
	if _fixture or not bool(summary.reward_eligible): return false
	_earned.threats += 1
	if summary.kind == "elite": _earned.elites += 1
	if summary.kind == "boss": _earned.bosses += 1
	return true

func abort() -> void:
	_aborted = true
	eligible = false

func snapshot() -> Dictionary:
	return {"reward_provenance":PROVENANCE,"earned_threats_cleared":int(_earned.threats),
		"earned_elites_cleared":int(_earned.elites),"earned_bosses_cleared":int(_earned.bosses),
		"reward_fixture":_fixture or not eligible,"aborted":_aborted}

func finalize(result: Dictionary) -> Dictionary:
	if not _started or run_nonce.is_empty(): return {"ok":false,"status":"not_started"}
	if _finished: return {"ok":false,"status":"already_finalized"}
	if _aborted: return {"ok":false,"status":"aborted"}
	if not result.get("run_seed", null) is int or int(result.run_seed) != run_seed:
		return {"ok":false,"status":"stale_result"}
	if result.get("continuous_run", false) != true or result.get("won", true) != false:
		return {"ok":false,"status":"not_completed_run"}
	if str(result.get("reason", "")) not in ["spin_out", "ring_out", "impact"]:
		return {"ok":false,"status":"not_player_defeat"}
	if str(result.get("reward_provenance", "")) != PROVENANCE:
		return {"ok":false,"status":"unverified_accounting"}
	var outcome: Dictionary = snapshot()
	# A fixture introduced after the last clear still poisons the whole session.
	if result.get("reward_fixture", false) == true:
		_fixture = true
		outcome.reward_fixture = true
	for field: String in ["earned_threats_cleared", "earned_elites_cleared", "earned_bosses_cleared"]:
		if not result.get(field, null) is int or int(result[field]) != int(outcome[field]):
			return {"ok":false,"status":"accounting_mismatch"}
	_finished = true
	return {"ok":true,"status":"verified" if eligible and not _fixture else "ineligible", "run_nonce":run_nonce,"outcome":outcome}
