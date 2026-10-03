extends SceneTree

const Run = preload("res://scripts/run_context.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Seeds = preload("res://scripts/seed_utils.gd")
const Catalog = preload("res://scripts/parts.gd")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	_test_seed_and_catalogs()
	_test_complete_run()
	_test_failure_and_reset()
	_test_draft_determinism()
	print("RUN_CONTEXT_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)

func _test_seed_and_catalogs() -> void:
	check(Seeds.derive(7341, "combat") == 2548610973, "Versioned seed derivation retains a known value")
	var streams: Array[int] = []
	for domain: String in ["combat", "ai", "draft/run_slot_01", "cosmetics"]:
		var seed_value: int = Seeds.derive(7341, domain)
		check(not seed_value in streams, "Independent RNG domains have distinct derived seeds")
		check(seed_value == Seeds.derive(7341, domain), "Derivation does not consume mutable RNG state")
		streams.append(seed_value)
	check(Powers.IDS.size() == 12, "Twelve approved power IDs exist")
	var ids: Dictionary = {}
	for power_id: String in Powers.IDS:
		var definition: Dictionary = Powers.get_power(power_id)
		check(not ids.has(power_id) and definition.id == power_id, "Power identities are unique and explicit")
		ids[power_id] = true
		check(not bool(definition.active), "Task 002A powers have no active combat effect")
		check(not str(definition.name).is_empty() and not str(definition.description).is_empty() and definition.has("icon"), "Each power has card and future icon data")
		definition.name = "MUTATED COPY"
		check(Powers.get_power(power_id).name != "MUTATED COPY", "Card callers cannot mutate the catalogue")
	check(Powers.get_power("unknown").is_empty(), "Unknown powers do not become catalogue entries")
	var encounter_ids: Dictionary = {}
	var encounter_seeds: Dictionary = {}
	for slot: int in range(1, 9):
		var encounter: Dictionary = Encounters.for_slot(slot, 9012)
		check(not encounter_ids.has(encounter.id) and encounter.id == encounter.slot_id and encounter.slot == slot, "Each encounter has a stable unique ID")
		encounter_ids[encounter.id] = true
		check(not encounter_seeds.has(encounter.seed), "Each slot has its own deterministic combat seed")
		encounter_seeds[encounter.seed] = true
		check(encounter == Encounters.for_slot(slot, 9012), "Encounter descriptors are deterministic")
		check(encounter.fixture and encounter.fixture_type == "duel" and encounter.behavior_profile == "pursuit", "All eight encounters explicitly use ordinary duel fixtures")
		check(encounter.arena_modifier == "none" and encounter.boss_parameters.is_empty() and encounter.opponent_power_ids.is_empty(), "Future hazards, enemy powers and bosses remain inactive")
		check(encounter.live_time_limit == 60.0, "Every ordinary duel fixture retains the baseline time limit")
		check(Catalog.validate_build(encounter.opponent_build) == encounter.opponent_build, "Encounter opponents are real catalogue assemblies")
		encounter.opponent_build.blade = "invalid"
		check(Encounters.for_slot(slot, 9012).opponent_build.blade != "invalid", "Encounter descriptors do not share mutable builds")
	check(Encounters.for_slot(0, 9012).is_empty() and Encounters.for_slot(9, 9012).is_empty(), "Out-of-range encounters are unavailable")

func _test_complete_run() -> void:
	var selected: Dictionary = {"blade":"hook", "ratchet":"low", "bit":"rubber"}
	var run: RefCounted = Run.new()
	run.start(selected, 12003)
	check(run.slot == 1 and run.status == "active" and run.is_active(), "Run begins active at slot one")
	check(not run.advance() and not run.choose_power("run_slot_01", "impact_wake"), "No reward or advance is available before victory")
	selected.blade = "smash"
	var exposed_build: Dictionary = run.selected_build
	exposed_build.bit = "flat"
	check(run.selected_build == {"blade":"hook", "ratchet":"low", "bit":"rubber"}, "Run assembly is isolated from caller and UI mutations")
	var draft_slots: Array[int] = []
	for slot: int in range(1, 9):
		var encounter: Dictionary = run.current_encounter()
		var encounter_id: String = encounter.id
		check(run.slot == slot, "Slot advances exactly once")
		check(not run.commit_result("wrong_encounter", true), "Results from another encounter cannot commit")
		check(run.commit_result(encounter_id, true), "The current victory commits")
		check(not run.commit_result(encounter_id, false), "A repeated result cannot change a committed victory")
		var result_copy: Dictionary = run.committed_results
		result_copy.clear()
		check(run.committed_results.has(encounter_id), "External result copies cannot erase idempotency records")
		if slot in [1, 2, 3, 4, 6, 7]:
			draft_slots.append(slot)
			var offer: Array[String] = run.pending_offer
			check(offer.size() == 3, "Every draft has three cards")
			check(offer[0] != offer[1] and offer[0] != offer[2] and offer[1] != offer[2], "Each offer is internally unique")
			for power_id: String in offer:
				check(not power_id in run.owned_power_ids, "Draft cards are unowned")
			check(not run.advance(), "A pending choice blocks progression")
			check(not run.choose_power(encounter_id, "invalid"), "Only an offered power may be acquired")
			var offer_copy: Array[String] = run.pending_offer
			offer_copy.clear()
			check(run.pending_offer == offer, "Reading/reopening cannot discard or reroll the offer")
			check(run.choose_power(encounter_id, offer[0]), "One offered card is acquired")
			check(not run.choose_power(encounter_id, offer[1]), "Repeated card input cannot acquire another reward")
			check(run.pending_offer.is_empty() and run.owned_power_ids.size() == draft_slots.size(), "Claim clears the pending offer and retains exactly one power")
			var owned_copy: Array[String] = run.owned_power_ids
			owned_copy.clear()
			check(run.owned_power_ids.size() == draft_slots.size(), "UI-owned labels cannot erase acquired powers")
		else:
			check(run.pending_offer.is_empty(), "Slots five and eight do not offer rewards")
		if slot < 8:
			check(run.advance(), "A resolved encounter advances toward the next launch")
			check(not run.advance(), "Repeated advance cannot skip an unresolved encounter")
			check(not run.commit_result(encounter_id, true), "A stale previous-encounter result is ignored")
			check(not run.choose_power(encounter_id, "impact_wake"), "A stale reward callback is ignored")
		if run.slot == 8:
			check(run.owned_power_ids.size() == 6, "Player enters the final fixture with six powers")
	check(draft_slots == [1, 2, 3, 4, 6, 7], "Exactly the approved six draft points were visited")
	check(run.status == "complete" and not run.is_active(), "Eighth victory completes the run")
	check(run.committed_results.size() == 8 and run.committed_rewards.size() == 6, "Completion retains one commitment per encounter and draft")
	check(not run.advance() and not run.commit_result("run_slot_08", true), "A completed run cannot advance or recommit")
	run.clear()
	check(run.status == "empty" and run.slot == 0 and run.run_seed == 0 and run.selected_build.is_empty(), "Leaving a run clears identity and assembly")
	check(run.owned_power_ids.is_empty() and run.pending_offer.is_empty() and run.committed_results.is_empty() and run.committed_rewards.is_empty(), "Leaving a run clears all rewards and commitments")

func _test_failure_and_reset() -> void:
	var run: RefCounted = Run.new()
	var assembly: Dictionary = {"blade":"guard", "ratchet":"high", "bit":"ball"}
	run.start(assembly, 703)
	run.commit_result(run.current_encounter().id, true)
	run.choose_power(run.current_encounter().id, run.pending_offer[0])
	run.advance()
	check(run.commit_result(run.current_encounter().id, false), "A loss commits on the current encounter")
	check(run.status == "failed" and not run.is_active() and not run.advance(), "Loss ends the run and blocks encounter retry/advance")
	check(not run.commit_result(run.current_encounter().id, true), "A failed run cannot be revived by a late win")
	var locked: Dictionary = run.selected_build
	run.start(locked, 704)
	check(run.slot == 1 and run.is_active() and run.run_seed == 704 and run.selected_build == assembly, "Restart returns to one with the locked build and supplied fresh seed")
	check(run.owned_power_ids.is_empty() and run.pending_offer.is_empty() and run.committed_results.is_empty() and run.committed_rewards.is_empty(), "Restart clears every prior reward and result")
	run.commit_result(run.current_encounter().id, true)
	check(run.pending_offer.size() == 3, "A restart can produce a fresh pending reward")
	run.clear()
	check(run.pending_offer.is_empty() and run.current_encounter().is_empty(), "Explicit end during reward discards run-only state")

func _test_draft_determinism() -> void:
	var first: RefCounted = Run.new()
	var second: RefCounted = Run.new()
	first.start(Catalog.DEFAULT_BUILD, 445566)
	second.start(Catalog.DEFAULT_BUILD, 445566)
	var cosmetics: RandomNumberGenerator = RandomNumberGenerator.new()
	cosmetics.seed = Seeds.derive(445566, "cosmetics")
	for slot: int in range(1, 9):
		var encounter_id: String = first.current_encounter().id
		first.commit_result(encounter_id, true)
		for _sample: int in range(1000): cosmetics.randf()
		second.commit_result(encounter_id, true)
		check(first.pending_offer == second.pending_offer, "Recorded seed/choices reproduce draft regardless of cosmetic consumption")
		if not first.pending_offer.is_empty():
			var chosen: String = first.pending_offer[slot % 3]
			first.choose_power(encounter_id, chosen)
			second.choose_power(encounter_id, chosen)
		check(first.current_encounter() == second.current_encounter(), "Draft/cosmetic consumption cannot perturb encounter seeds")
		first.advance()
		second.advance()
	check(first.owned_power_ids == second.owned_power_ids and first.status == "complete" and second.status == "complete", "A seed plus recorded choices reproduces the complete collection")
