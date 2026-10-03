extends RefCounted
class_name RunContext

const Catalog = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Seeds = preload("res://scripts/seed_utils.gd")
const Progression = preload("res://scripts/run_progression.gd")

var _selected_build: Dictionary = {}
var _owned_power_ids: Array[String] = []
var _pending_offer: Array[String] = []
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
var pending_offer: Array[String]:
	get: return _pending_offer.duplicate()
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
	_progression.setup(Powers.ACTIVE_IDS.size())
	_draft_queue.append({"id":"draft/start", "kind":"starting", "level":1})
	_generate_offer()

func current_encounter() -> Dictionary:
	var descriptor: Dictionary = Encounters.for_slot(slot, run_seed)
	if not descriptor.is_empty():
		descriptor["player_power_ids"] = owned_power_ids
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
	if not won:
		status = "failed"
		_pending_offer.clear()
		_draft_queue.clear()
	elif slot == Encounters.SLOT_COUNT and _draft_queue.is_empty():
		status = "complete"
	return true

## The claim ID identifies a draft, rather than an encounter: multiple earned
## choices can occur in one encounter without a stale callback claiming twice.
func choose_power(encounter_id: String, power_id: String) -> bool:
	if not is_active() or encounter_id != pending_draft_id: return false
	if _committed_rewards.has(encounter_id) or not power_id in _pending_offer: return false
	if power_id in _owned_power_ids or not power_id in Powers.ACTIVE_IDS: return false
	_committed_rewards[encounter_id] = power_id
	_owned_power_ids.append(power_id)
	_pending_offer.clear()
	_draft_queue.pop_front()
	if not _draft_queue.is_empty(): _generate_offer()
	elif slot == Encounters.SLOT_COUNT and bool(_committed_results.get(str(current_encounter().id), false)):
		status = "complete"
	return true

func advance() -> bool:
	if not is_active() or not _draft_queue.is_empty(): return false
	var encounter_id: String = str(current_encounter().id)
	if not bool(_committed_results.get(encounter_id, false)): return false
	if slot >= Encounters.SLOT_COUNT: return false
	slot += 1
	return true

func clear() -> void:
	_selected_build.clear()
	_owned_power_ids.clear()
	_pending_offer.clear()
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
	for power_id: String in Powers.ACTIVE_IDS:
		if not power_id in _owned_power_ids: candidates.append(power_id)
	var draft_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	draft_rng.seed = Seeds.derive(run_seed, "draft/" + pending_draft_id)
	for index: int in range(candidates.size() - 1, 0, -1):
		var other: int = draft_rng.randi_range(0, index)
		var saved: String = candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = saved
	_pending_offer.clear()
	for index: int in range(mini(3, candidates.size())):
		_pending_offer.append(candidates[index])
