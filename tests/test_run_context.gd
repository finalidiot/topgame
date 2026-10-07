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
	check(Powers.IDS.size() == 21, "Stable historic identities plus three new active defensive families exist")
	var ids: Dictionary = {}
	for power_id: String in Powers.IDS:
		var definition: Dictionary = Powers.get_power(power_id)
		check(not ids.has(power_id) and definition.id == power_id, "Power identities are unique and explicit")
		ids[power_id] = true
		check(bool(definition.active) == (power_id in Powers.ACTIVE_IDS), "Only current implemented families enter normal drafts")
		if definition.active:
			check(not str(definition.condition).is_empty() and definition.icon_frame >= 0, "Active power has a condition and signature icon")
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
		check(encounter.behavior_profile == "pursuit", "Later specialist behavior remains deferred")
		if encounter.fixture_type == "swarm":
			check(not encounter.fixture and encounter.fixture_type == "swarm" and encounter.objective == "clear_schedule", "Slot 3 is a real Ammunition Waves encounter")
			check(encounter.swarm_parameters.waves == [6, 8, 10] and encounter.swarm_parameters.wave_times == [0.0, 9.0, 18.0] and encounter.swarm_parameters.active_cap == 12, "Swarm descriptor preserves finite 24-entry schedule and cap")
		else:
			check(encounter.fixture and encounter.fixture_type == "duel", "Other slots retain ordinary duel fixtures")
		check(encounter.arena_modifier == "none" and encounter.boss_parameters.is_empty() and encounter.opponent_power_ids.is_empty(), "Future hazards, enemy powers and bosses remain inactive")
		check(encounter.live_time_limit == (32.0 if encounter.fixture_type == "swarm" else 60.0), "Only swarm uses its finite cleanup ceiling")
		check(Catalog.validate_build(encounter.opponent_build) == encounter.opponent_build, "Encounter opponents are real catalogue assemblies")
		encounter.opponent_build.blade = "invalid"
		check(Encounters.for_slot(slot, 9012).opponent_build.blade != "invalid", "Encounter descriptors do not share mutable builds")
	check(Encounters.for_slot(0, 9012).is_empty() and not Encounters.for_slot(10001, 9012).is_empty(), "Only non-positive threats are unavailable; the sequence has no end")

func _claim_pending(run: RefCounted) -> void:
	while not run.pending_offer.is_empty():
		var offer: Array[String] = run.pending_offer
		var claim: String = run.pending_draft_id
		var eligible: int = 0
		for power_id: String in Powers.ACTIVE_IDS:
			if Powers.can_progress(power_id, int(run.power_ranks.get(power_id, 0)), str(run.power_mutations.get(power_id, ""))): eligible += 1
		check(offer.size() == mini(3, eligible), "Only available functional investments enter a draft")
		var unique: Dictionary = {}
		for power_id: String in offer:
			unique[power_id] = true
			check(Powers.can_progress(power_id, int(run.power_ranks.get(power_id, 0))), "Draft cards can acquire or develop a functional power")
		check(unique.size() == offer.size(), "Draft cards are unique")
		check(not run.choose_power(claim, "invalid"), "Only an offered power may be acquired")
		check(run.choose_power(claim, offer[0]), "Pending claim acquires one card")
		check(not run.choose_power(claim, offer.back()), "Repeated claim cannot acquire another card")
		if not run.pending_mutation_power.is_empty():
			check(run.choose_mutation(claim, run.pending_mutation_offer[0]), "Rank III commits exactly one valid branch")

func _earn_contact(run: RefCounted, time: float, event_id: int) -> void:
	run.award_xp({"kind":"collision", "encounter_id":run.current_encounter().id, "time":time,
		"event_id":event_id, "first_entity_id":1, "second_entity_id":2,
		"severity":0.8, "player_attributed":true})

func _test_complete_run() -> void:
	var selected: Dictionary = {"blade":"hook", "ratchet":"low", "bit":"rubber"}
	var run: RefCounted = Run.new()
	run.start(selected, 12003, "vane")
	check(run.slot == 1 and run.status == "active" and run.is_active(), "Run begins active at slot one")
	check(not run.advance() and not run.commit_result("run_slot_01", true), "Unpowered opening cannot advance or commit combat")
	selected.blade = "smash"
	var exposed_build: Dictionary = run.selected_build
	exposed_build.bit = "flat"
	check(run.selected_build == {"blade":"hook", "ratchet":"low", "bit":"rubber"}, "Run assembly is isolated from caller and UI mutations")
	_claim_pending(run)
	check(run.owned_power_ids.size() == 1, "First encounter enters powered")
	for slot_number: int in range(1, 9):
		var encounter_id: String = run.current_encounter().id
		check(run.slot == slot_number and run.starter_id == "vane", "Encounter advance preserves starter identity")
		check(not run.commit_result("wrong_encounter", true), "Results from another encounter cannot commit")
		for event_number: int in range(10): _earn_contact(run, float(event_number) * 2.0, event_number)
		_claim_pending(run)
		var owned_copy: Array[String] = run.owned_power_ids
		owned_copy.clear()
		check(not run.owned_power_ids.is_empty(), "UI labels cannot erase acquired powers")
		check(run.current_encounter().player_power_ids == run.owned_power_ids, "Combat descriptor carries owned powers")
		var exposed_descriptor: Dictionary = run.current_encounter()
		exposed_descriptor.player_power_ids.clear()
		check(not run.owned_power_ids.is_empty(), "Combat descriptor cannot mutate Run ownership")
		check(run.commit_result(encounter_id, true), "The current victory commits")
		check(not run.commit_result(encounter_id, false), "A repeated result cannot change a committed victory")
		var result_copy: Dictionary = run.committed_results
		result_copy.clear()
		check(run.committed_results.has(encounter_id), "External copies cannot erase result idempotency records")
		check(run.pending_offer.is_empty(), "Victory adds no fixed encounter draft")
		check(run.advance(), "A resolved threat advances without a final index")
		check(not run.advance(), "Repeated advance cannot skip an unresolved threat")
		check(not run.commit_result(encounter_id, true), "A stale previous-threat result is ignored")
	check(run.status == "active" and run.slot == 9, "Eighth victory continues into threat nine")
	var investments: int = 0
	for rank: int in run.power_ranks.values(): investments += rank
	check(run.owned_power_ids.size() <= Powers.ACTIVE_IDS.size() and run.committed_results.is_empty() and investments == run.committed_rewards.size(), "Continuous ownership retains each investment while retiring old threat claims")
	check(not run.advance() and not run.commit_result("run_slot_08", true), "Old threat cannot advance or recommit a live Run")
	run.clear()
	check(run.status == "empty" and run.slot == 0 and run.run_seed == 0 and run.selected_build.is_empty(), "Leaving clears Run identity and assembly")
	check(run.owned_power_ids.is_empty() and run.pending_offer.is_empty() and run.committed_results.is_empty() and run.committed_rewards.is_empty(), "Leaving clears ownership and commitments")

func _test_failure_and_reset() -> void:
	var run: RefCounted = Run.new()
	var assembly: Dictionary = {"blade":"guard", "ratchet":"high", "bit":"ball"}
	run.start(assembly, 703, "bastion")
	_claim_pending(run)
	run.commit_result(run.current_encounter().id, true)
	run.advance()
	check(run.commit_result(run.current_encounter().id, false), "A current loss commits")
	check(run.status == "failed" and not run.is_active() and not run.advance(), "Loss ends Run and blocks retry/advance")
	check(not run.commit_result(run.current_encounter().id, true), "A failed Run cannot be revived by a late win")
	var locked: Dictionary = run.selected_build
	run.start(locked, 704, "bastion")
	check(run.slot == 1 and run.is_active() and run.run_seed == 704 and run.selected_build == assembly, "Restart returns to one with locked build and fresh seed")
	check(run.owned_power_ids.is_empty() and run.pending_offer.size() == 3 and run.pending_draft_kind == "starting", "Restart resets power ownership and immediately offers a new starting power")
	check(run.committed_results.is_empty() and run.committed_rewards.is_empty() and run.level == 1 and run.xp == 0, "Restart clears old XP, claims, and results")
	run.clear()
	check(run.pending_offer.is_empty() and run.current_encounter().is_empty(), "Explicit end during reward discards Run-only state")

func _test_draft_determinism() -> void:
	var first: RefCounted = Run.new()
	var second: RefCounted = Run.new()
	first.start(Catalog.DEFAULT_BUILD, 445566, "breaker")
	second.start(Catalog.DEFAULT_BUILD, 445566, "breaker")
	var cosmetics: RandomNumberGenerator = RandomNumberGenerator.new()
	cosmetics.seed = Seeds.derive(445566, "cosmetics")
	for slot_number: int in range(1, 9):
		for event_number: int in range(10):
			_earn_contact(first, float(event_number) * 2.0, event_number)
			for _sample: int in range(100): cosmetics.randf()
			_earn_contact(second, float(event_number) * 2.0, event_number)
		while not first.pending_offer.is_empty():
			check(first.pending_offer == second.pending_offer and first.pending_draft_id == second.pending_draft_id, "Seed/events/choices reproduce drafts regardless of cosmetics")
			var chosen: String = first.pending_offer[slot_number % first.pending_offer.size()]
			var claim: String = first.pending_draft_id
			first.choose_power(claim, chosen)
			second.choose_power(claim, chosen)
			if not first.pending_mutation_power.is_empty():
				var branch: String = first.pending_mutation_offer[slot_number % 2]
				first.choose_mutation(claim, branch)
				second.choose_mutation(claim, branch)
		check(first.current_encounter() == second.current_encounter(), "Draft/cosmetic consumption cannot perturb encounter seeds")
		first.commit_result(first.current_encounter().id, true)
		second.commit_result(second.current_encounter().id, true)
		first.advance()
		second.advance()
	check(first.owned_power_ids == second.owned_power_ids and first.status == "active" and second.status == "active" and first.slot == 9, "Recorded seed/events/choices reproduce continuing Runs")
