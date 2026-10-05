extends RefCounted
class_name RunContext

const Catalog = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Seeds = preload("res://scripts/seed_utils.gd")
const Progression = preload("res://scripts/run_progression.gd")
const STARTING_REROLLS: int = 1
const MAX_REROLLS: int = 6

# Soft depth preference within seven machine slots. Beyond five owned families
# another acquisition is less common; at seven the remaining cards deepen them.
const DRAFT_TUNING: Dictionary = {"soft_family_start":5,"new_weight_floor":0.10,"new_decay":0.55,"rank_weight":2.15,"mutation_weight":2.60,"upgrade_slot_from":3}

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
var reroll_charges: int = 0
var rerolls_used: int = 0
var rerolls_collected: int = 0
var _draft_revision: int = 0
var _collected_reroll_ids: Array[String] = []
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
	reroll_charges = STARTING_REROLLS
	_progression.setup(Powers.run_investment_capacity())
	_draft_queue.append({"id":"draft/start", "kind":"starting", "level":1})
	_generate_offer()

func current_encounter() -> Dictionary:
	var descriptor: Dictionary = Encounters.for_run_event(slot, run_seed)
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

func reroll_snapshot() -> Dictionary:
	return {"charges":reroll_charges, "maximum":MAX_REROLLS, "revision":_draft_revision,
		"available":can_reroll(), "used":rerolls_used, "collected":rerolls_collected}

func can_reroll() -> bool:
	if not is_active() or reroll_charges <= 0 or _pending_offer.is_empty() or not _pending_mutation_power.is_empty(): return false
	var eligible: int = 0
	for id: String in Powers.ACTIVE_IDS:
		var rank_value: int = int(_power_ranks.get(id, 0))
		if rank_value == 0 and _owned_power_ids.size() >= Powers.FAMILY_CAP: continue
		if Powers.can_progress(id, rank_value, str(_power_mutations.get(id, ""))): eligible += 1
	return eligible > _pending_offer.size()

func reroll_offer(draft_id: String, expected_revision: int) -> bool:
	# A stale button cannot consume twice or reroll an unrelated later draft.
	if draft_id != pending_draft_id or expected_revision != _draft_revision or not can_reroll(): return false
	var previous: Array[String] = pending_offer
	_draft_revision += 1
	_generate_offer(previous)
	reroll_charges -= 1
	rerolls_used += 1
	return true

func collect_reroll_pickup(id: String) -> bool:
	if not is_active() or id.is_empty() or reroll_charges >= MAX_REROLLS or id in _collected_reroll_ids: return false
	_collected_reroll_ids.append(id)
	if _collected_reroll_ids.size() > 128: _collected_reroll_ids.pop_front()
	reroll_charges += 1
	rerolls_collected += 1
	return true

func progression_snapshot() -> Dictionary:
	var snapshot: Dictionary = _progression.snapshot()
	snapshot["family_cap"] = Powers.FAMILY_CAP
	snapshot["families_owned"] = _owned_power_ids.size()
	return snapshot

func available_investment_capacity() -> int:
	if _owned_power_ids.size() < Powers.FAMILY_CAP: return Powers.run_investment_capacity()
	var capacity: int = 0
	for id: String in _owned_power_ids: capacity += Powers.max_rank(id)
	return capacity

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
	if rank == 0:
		_owned_power_ids.append(power_id)
		if _owned_power_ids.size() == Powers.FAMILY_CAP:
			var capacity: int = available_investment_capacity()
			_progression.set_investment_limit(capacity)
			for index: int in range(_draft_queue.size()-1,-1,-1):
				if int(_draft_queue[index].level) > capacity: _draft_queue.remove_at(index)
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
	_draft_revision = 0
	if not _draft_queue.is_empty(): _generate_offer()

func _clear_pending_mutation() -> void:
	_pending_mutation_power = ""
	_pending_mutation_offer.clear()

## Director entries overlap. They do not resolve prior events or reset XP guards.
func admit_event(number: int) -> bool:
	if not is_active() or number != slot+1: return false
	slot = number
	_committed_results.clear()
	return true

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
	reroll_charges = 0
	rerolls_used = 0
	rerolls_collected = 0
	_draft_revision = 0
	_collected_reroll_ids.clear()
	run_seed = 0
	slot = 0
	status = "empty"
	starter_id = "custom"

func _generate_offer(previous: Array[String] = []) -> void:
	# Created once per claim. Reopening a card screen has no RNG path. Starter
	# identity is preserved, while every implemented power remains legal.
	var candidates: Array[String] = []
	var weights: Array[float] = []
	for power_id: String in Powers.ACTIVE_IDS:
		var rank: int = int(_power_ranks.get(power_id, 0))
		if rank == 0 and _owned_power_ids.size() >= Powers.FAMILY_CAP: continue
		if Powers.can_progress(power_id, rank, str(_power_mutations.get(power_id, ""))):
			candidates.append(power_id)
			weights.append(draft_weight(_owned_power_ids.size(), rank))
	var draft_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var domain: String = "draft/" + pending_draft_id
	if _draft_revision > 0: domain += "/reroll_%d" % _draft_revision
	draft_rng.seed = Seeds.derive(run_seed, domain)
	_pending_offer.clear()
	# Once a build has a few families, one card always develops an eligible owned
	# family. Other slots still invite new combinations. No investment is forced.
	if _owned_power_ids.size() >= int(DRAFT_TUNING.upgrade_slot_from):
		var upgrades: Array[int] = []
		var upgrade_weights: Array[float] = []
		for index: int in range(candidates.size()):
			if int(_power_ranks.get(candidates[index], 0)) > 0:
				upgrades.append(index)
				upgrade_weights.append(weights[index])
		if not upgrades.is_empty():
			var chosen: int = upgrades[_weighted_index(upgrade_weights, draft_rng)]
			_pending_offer.append(candidates[chosen])
			candidates.remove_at(chosen)
			weights.remove_at(chosen)
	for _draw: int in range(mini(3, candidates.size())):
		if _pending_offer.size() >= 3: break
		var chosen: int = _weighted_index(weights, draft_rng)
		_pending_offer.append(candidates[chosen])
		candidates.remove_at(chosen)
		weights.remove_at(chosen)
	# A paid reroll must change an actual card, rather than just its order.
	# The guaranteed development card is first here; replace the last slot so
	# that guarantee survives. The display shuffle happens afterwards.
	if not previous.is_empty():
		var same_cards: bool = _pending_offer.size() == previous.size()
		for id: String in _pending_offer:
			if not id in previous: same_cards = false
		if same_cards:
			var replacements: Array[String] = []
			var replacement_weights: Array[float] = []
			for index: int in range(candidates.size()):
				if not candidates[index] in previous:
					replacements.append(candidates[index])
					replacement_weights.append(weights[index])
			assert(not replacements.is_empty(), "A valid reroll needs a different eligible card")
			_pending_offer[_pending_offer.size() - 1] = replacements[_weighted_index(replacement_weights, draft_rng)]
	# Keep the guaranteed development card from occupying a predictable UI slot.
	for index: int in range(_pending_offer.size() - 1, 0, -1):
		var swap_index: int = draft_rng.randi_range(0, index)
		var swap: String = _pending_offer[index]
		_pending_offer[index] = _pending_offer[swap_index]
		_pending_offer[swap_index] = swap

static func draft_weight(owned_count: int, rank: int) -> float:
	if rank > 0: return float(DRAFT_TUNING.mutation_weight if rank == 2 else DRAFT_TUNING.rank_weight)
	var excess: int = maxi(0, owned_count - int(DRAFT_TUNING.soft_family_start) + 1)
	return maxf(float(DRAFT_TUNING.new_weight_floor), pow(float(DRAFT_TUNING.new_decay), excess))

static func _weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for weight: float in weights: total += weight
	var remaining: float = rng.randf() * total
	for index: int in range(weights.size()):
		remaining -= weights[index]
		if remaining < 0.0: return index
	return weights.size() - 1
