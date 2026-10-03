extends RefCounted
class_name RunContext

const Catalog = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Seeds = preload("res://scripts/seed_utils.gd")

var _selected_build: Dictionary = {}
var _owned_power_ids: Array[String] = []
var _pending_offer: Array[String] = []
var _committed_results: Dictionary = {}
var _committed_rewards: Dictionary = {}
var run_seed: int = 0
var slot: int = 0
var status: String = "empty"

# Return copies so menu code cannot mutate the locked assembly or claims.
var selected_build: Dictionary:
	get: return _selected_build.duplicate(true)
var owned_power_ids: Array[String]:
	get: return _owned_power_ids.duplicate()
var pending_offer: Array[String]:
	get: return _pending_offer.duplicate()
var committed_results: Dictionary:
	get: return _committed_results.duplicate(true)
var committed_rewards: Dictionary:
	get: return _committed_rewards.duplicate(true)

func start(build: Dictionary, seed_value: int) -> void:
	clear()
	_selected_build = Catalog.validate_build(build)
	run_seed = seed_value
	slot = 1
	status = "active"

func current_encounter() -> Dictionary:
	return Encounters.for_slot(slot, run_seed)

func is_active() -> bool:
	return status == "active"

func commit_result(encounter_id: String, won: bool) -> bool:
	if not is_active() or encounter_id != str(current_encounter().get("id", "")):
		return false
	if _committed_results.has(encounter_id): return false
	_committed_results[encounter_id] = won
	if not won:
		status = "failed"
		_pending_offer.clear()
	elif slot == Encounters.SLOT_COUNT:
		status = "complete"
	elif Encounters.has_draft(slot):
		_generate_offer(encounter_id)
	return true

func choose_power(encounter_id: String, power_id: String) -> bool:
	if not is_active() or encounter_id != str(current_encounter().get("id", "")):
		return false
	if not bool(_committed_results.get(encounter_id, false)):
		return false
	if _committed_rewards.has(encounter_id) or not power_id in _pending_offer:
		return false
	if power_id in _owned_power_ids: return false
	_committed_rewards[encounter_id] = power_id
	_owned_power_ids.append(power_id)
	_pending_offer.clear()
	return true

func advance() -> bool:
	if not is_active(): return false
	var encounter_id: String = str(current_encounter().id)
	if not bool(_committed_results.get(encounter_id, false)): return false
	if Encounters.has_draft(slot) and not _committed_rewards.has(encounter_id):
		return false
	if slot >= Encounters.SLOT_COUNT: return false
	slot += 1
	return true

func clear() -> void:
	_selected_build.clear()
	_owned_power_ids.clear()
	_pending_offer.clear()
	_committed_results.clear()
	_committed_rewards.clear()
	run_seed = 0
	slot = 0
	status = "empty"

func _generate_offer(encounter_id: String) -> void:
	# This is called only by the first committed result. Rendering/reopening a
	# reward has no RNG path, and other streams cannot perturb this slot's offer.
	var candidates: Array[String] = []
	for power_id: String in Powers.IDS:
		if not power_id in _owned_power_ids: candidates.append(power_id)
	var draft_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	draft_rng.seed = Seeds.derive(run_seed, "draft/" + encounter_id)
	for index: int in range(candidates.size() - 1, 0, -1):
		var other: int = draft_rng.randi_range(0, index)
		var saved: String = candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = saved
	_pending_offer.clear()
	for index: int in range(mini(3, candidates.size())):
		_pending_offer.append(candidates[index])
