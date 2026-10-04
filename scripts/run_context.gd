extends RefCounted
class_name RunContext

const Catalog = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Seeds = preload("res://scripts/seed_utils.gd")
const Progression = preload("res://scripts/run_progression.gd")

var _selected_build: Dictionary = {}
var _owned_power_ids: Array[String] = []
var _power_ranks: Dictionary = {}
var _power_mutations: Dictionary = {}
var _pending_offer: Array[String] = []
var _pending_mutation_power: String = ""
var _pending_mutation_offer: Array[String] = []
var _committed_results: Dictionary = {}
var _committed_rewards: Dictionary = {}
var _draft_queue: Array[Dictionary] = []
var _progression = Progression.new()
var run_seed: int = 0
var slot: int = 0
var status: String = "empty"
var starter_id: String = "custom"

# Return copies so menus cannot mutate the locked assembly, offer, or claims.
var selected_build: Dictionary:
	get: return _selected_build.duplicate(true)
var owned_power_ids: Array[String]:
	get: return _owned_power_ids.duplicate()
var power_ranks: Dictionary:
	get: return _power_ranks.duplicate()
var power_mutations: Dictionary:
	get: return _power_mutations.duplicate()
var pending_offer: Array[String]:
	get: return _pending_offer.duplicate()
var pending_mutation_power: String:
	get: return _pending_mutation_power
var pending_mutation_offer: Array[String]:
	get: return _pending_mutation_offer.duplicate()
var committed_results: Dictionary:
	get: return _committed_results.duplicate(true)
var committed_rewards: Dictionary:
	get: return _committed_rewards.duplicate(true)
var pending_draft_id: String:
	get: return "" if _draft_queue.is_empty() else str(_draft_queue[0].id)
var pending_draft_kind: String:
	get: return "" if _draft_queue.is_empty() else str(_draft_queue[0].kind)
var pending_draft_level: int:
	get: return 0 if _draft_queue.is_empty() else int(_draft_queue[0].level)
var level: int:
	get: return _progression.level
var xp: int:
	get: return _progression.xp
var xp_threshold: int:
	get: return _progression.threshold()

func start(build: Dictionary, seed_value: int, selected_starter_id: String = "custom") -> void:
	clear()
	_selected_build = Catalog.validate_build(build)
	starter_id = selected_starter_id if selected_starter_id in ["breaker", "bastion", "vane", "custom"] else "custom"
	run_seed = seed_value
	slot = 1
	status = "active"
	_progression.setup(Powers.investment_capacity())
	_draft_queue.append({"id":"draft/start", "kind":"starting", "level":1})
	_generate_offer()

func current_encounter() -> Dictionary:
	var descriptor: Dictionary = Encounters.for_slot(slot, run_seed)
	if not descriptor.is_empty():
		descriptor["player_power_ids"] = owned_power_ids
		descriptor["player_power_ranks"] = power_ranks
		descriptor["player_power_mutations"] = power_mutations
		descriptor["starter_id"] = starter_id
		# XP replaces the old fixed post-encounter draft cadence.
		descriptor["draft_after"] = false
	return descriptor

func is_active() -> bool:
	return status == "active"

func progression_snapshot() -> Dictionary:
	return _progression.snapshot()

## Only current, uncommitted combat can earn XP. Events use simulation seconds,
## so menu duration, wall-clock time and cosmetic RNG cannot change progression.
func award_xp(event: Dictionary) -> bool:
	if not is_active() or _owned_power_ids.is_empty(): return false
	var encounter_id: String = str(current_encounter().get("id", ""))
	if str(event.get("encounter_id", "")) != encounter_id or _committed_results.has(encounter_id): return false
	var crossed: Array[int] = _progression.record_event(event)
	for earned_level: int in crossed:
		_draft_queue.append({"id":"draft/level_%02d" % earned_level, "kind":"level", "level":earned_level})
	if _pending_offer.is_empty() and not _draft_queue.is_empty(): _generate_offer()
	return _progression.last_award > 0

func commit_result(encounter_id: String, won: bool) -> bool:
	if not is_active() or _owned_power_ids.is_empty() or encounter_id != str(current_encounter().get("id", "")): return false
	if _committed_results.has(encounter_id): return false
	_committed_results[encounter_id] = won
	if not won: fail_run()
	return true

## A real player defeat can occur even in the breathing period after a clear.
func fail_run() -> bool:
	if not is_active(): return false
	status = "failed"
	_pending_offer.clear()
	_clear_pending_mutation()
	_draft_queue.clear()
	return true

## The claim ID identifies a draft, rather than an encounter: multiple earned
## choices can occur in one encounter without a stale callback claiming twice.
func choose_power(encounter_id: String, power_id: String) -> bool:
	if not is_active() or encounter_id != pending_draft_id: return false
	if not _pending_mutation_power.is_empty(): return false
	if _committed_rewards.has(encounter_id) or not power_id in _pending_offer: return false
	var rank: int = int(_power_ranks.get(power_id, 0))
	if not Powers.can_progress(power_id, rank, str(_power_mutations.get(power_id, ""))): return false
	if rank == 2:
		_pending_mutation_power = power_id
		_pending_mutation_offer = Powers.mutation_choices(power_id)
		return true
	_power_ranks[power_id] = rank + 1
	if rank == 0: _owned_power_ids.append(power_id)
	_finish_claim(encounter_id, power_id)
	return true

func choose_mutation(encounter_id: String, branch_id: String) -> bool:
	if not is_active() or encounter_id != pending_draft_id or _pending_mutation_power.is_empty(): return false
	if _committed_rewards.has(encounter_id) or not branch_id in _pending_mutation_offer: return false
	var power_id: String = _pending_mutation_power
	if int(_power_ranks.get(power_id, 0)) != 2 or _power_mutations.has(power_id): return false
	if not branch_id in Powers.mutation_choices(power_id): return false
	_power_ranks[power_id] = 3
	_power_mutations[power_id] = branch_id
	_finish_claim(encounter_id, branch_id)
	return true

func _finish_claim(encounter_id: String, reward_id: String) -> void:
	_committed_rewards[encounter_id] = reward_id
	_pending_offer.clear()
	_clear_pending_mutation()
	_draft_queue.pop_front()
	if not _draft_queue.is_empty(): _generate_offer()

func _clear_pending_mutation() -> void:
	_pending_mutation_power = ""
	_pending_mutation_offer.clear()

func advance() -> bool:
	if not is_active() or not _draft_queue.is_empty(): return false
	var encounter_id: String = str(current_encounter().id)
	if not bool(_committed_results.get(encounter_id, false)): return false
	# Only the current threat needs a claim record; old IDs cannot match it.
	_committed_results.clear()
	_progression.clear_event_history()
	slot += 1
	return true

func clear() -> void:
	_selected_build.clear()
	_owned_power_ids.clear()
	_power_ranks.clear()
	_power_mutations.clear()
	_pending_offer.clear()
	_clear_pending_mutation()
	_committed_results.clear()
	_committed_rewards.clear()
	_draft_queue.clear()
	_progression.clear()
	run_seed = 0
	slot = 0
	status = "empty"
	starter_id = "custom"

func _generate_offer() -> void:
	# Created once per claim. Reopening a card screen has no RNG path. Starter
	# identity is preserved, while every implemented power remains legal.
	var candidates: Array[String] = []
	var weights: Array[float] = []
	for power_id: String in Powers.ACTIVE_IDS:
		var rank: int = int(_power_ranks.get(power_id, 0))
		if Powers.can_progress(power_id, rank, str(_power_mutations.get(power_id, ""))):
			candidates.append(power_id)
			weights.append(1.0 if rank == 0 else 1.2)
	var draft_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	draft_rng.seed = Seeds.derive(run_seed, "draft/" + pending_draft_id)
	_pending_offer.clear()
	# A small upgrade preference keeps owned powers in circulation; every
	# candidate remains possible, with no class restrictions or forced branches.
	for _draw: int in range(mini(3, candidates.size())):
		var total_weight: float = 0.0
		for weight: float in weights: total_weight += weight
		var remaining: float = draft_rng.randf() * total_weight
		var chosen: int = candidates.size() - 1
		for index: int in range(candidates.size()):
			remaining -= weights[index]
			if remaining < 0.0:
				chosen = index
				break
		_pending_offer.append(candidates[chosen])
		candidates.remove_at(chosen)
		weights.remove_at(chosen)
