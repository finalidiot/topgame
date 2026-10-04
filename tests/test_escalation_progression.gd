extends SceneTree

const Run = preload("res://scripts/run_context.gd")
const Progression = preload("res://scripts/run_progression.gd")
const Parts = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")

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
	_test_catalog_and_costs()
	_test_variable_offers()
	for power_id: String in Powers.VERTICAL_IDS:
		for branch_id: String in Powers.mutation_choices(power_id):
			_test_vertical_claims(power_id, branch_id)
	_test_reset_and_terminal_mutation()
	print("ESCALATION_PROGRESSION_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)

func _event(entity_id: int, encounter_id: String = "run_slot_01") -> Dictionary:
	return {"kind":"elimination", "encounter_id":encounter_id, "time":10.0,
		"entity_id":entity_id, "combatant_type":"small_top", "reason":"impact", "player_attributed":true}

func _fill_entitlements(run: RefCounted) -> void:
	# Attribution fixtures verify capacity and queuing, not playable pacing.
	for entity_id: int in range(100, 100 + int((132 + 84 * (Powers.investment_capacity() - 5)) / 3)): run.award_xp(_event(entity_id, run.current_encounter().id))

func _start_with(power_id: String) -> RefCounted:
	var run: RefCounted = Run.new()
	for seed_value: int in range(1, 101):
		run.start(Parts.DEFAULT_BUILD, seed_value)
		if power_id in run.pending_offer:
			run.choose_power(run.pending_draft_id, power_id)
			return run
	check(false, "Every active power can appear as an opening choice")
	return run

func _test_catalog_and_costs() -> void:
	check(Powers.ACTIVE_IDS.size() == 13 and "clutch" in Powers.ACTIVE_IDS and not "second_wind" in Powers.ACTIVE_IDS, "Thirteen-family pool replaces draftable Second Wind with Clutch")
	check(Powers.investment_capacity() == 30, "All families develop to II and four flagships mutate")
	for power_id: String in Powers.ACTIVE_IDS:
		var acquire: Dictionary = Powers.get_offer(power_id)
		check(acquire.rank == 1 and acquire.offer_kind == "acquire" and acquire.id == power_id, "Rank I offer acquires its stable power ID")
		var tune: Dictionary = Powers.get_offer(power_id, 1)
		check(tune.rank == 2 and tune.art_id == power_id + "_ii", "Every family has a real Rank II offer")
		if not power_id in Powers.VERTICAL_IDS:
			check(Powers.get_offer(power_id, 2).is_empty() and Powers.mutation_choices(power_id).is_empty(), "Two-rank family stops at II without filler mutations")
			continue
		var mutate: Dictionary = Powers.get_offer(power_id, 2)
		check(tune.rank == 2 and tune.offer_kind == "tune" and tune.id == power_id and tune.art_id == power_id + "_ii", "Rank II visibly develops its stable power")
		check(mutate.rank == 3 and mutate.offer_kind == "mutation" and not mutate.card_copy.is_empty(), "Rank III offer announces a behavioural branch event")
		var branches: Array[String] = Powers.mutation_choices(power_id)
		check(branches.size() == 2 and branches[0] != branches[1], "Each vertical path has two exclusive branches")
		for branch_id: String in branches:
			var branch: Dictionary = Powers.get_mutation(branch_id)
			check(branch.power_id == power_id and branch.rank == 3 and branch.source_tag == branch_id, "Mutation metadata binds its power and dedicated source art")
			check(branch.card_texture == (Powers.ROSTER_CARD_SHEET if power_id == "high_gear" else Powers.ESCALATION_CARD_SHEET) and branch.icon == (Powers.ROSTER_ICON_SHEET if power_id == "high_gear" else Powers.ESCALATION_ICON_SHEET), "Branches use their separate editable production atlases")
			check(Powers.get_owned_power(power_id, 3, branch_id).name == branch.name, "Current owned metadata names the chosen transformation")
			branch.name = "UI COPY"
			check(Powers.get_mutation(branch_id).name != "UI COPY", "Mutation metadata cannot be changed by menu copies")
		branches.clear()
		check(Powers.mutation_choices(power_id).size() == 2, "UI branch copies cannot erase either option")
		check(Powers.get_offer(power_id, 3).is_empty() and Powers.get_offer(power_id, 2, "invalid").is_empty(), "Fully mutated or inconsistent ownership cannot be offered again")
	check(Powers.get_offer("unknown").is_empty() and Powers.get_mutation("unknown").is_empty(), "Unknown powers and branches fail closed")
	for row: int in range(Powers.LEGACY_ART_IDS.size()):
		var id: String = Powers.LEGACY_ART_IDS[row]
		var power: Dictionary = Powers.get_power(id)
		var replaced: bool = id == "iron_comet"
		var active_row: int = Powers.ROSTER_ART_IDS.find(id) if replaced else row
		check(power.card_row == active_row and power.icon_frame == active_row and power.card_texture == (Powers.ROSTER_CARD_SHEET if replaced else Powers.CARD_SHEET), "Current catalogue maps original rows or the dedicated Iron Comet replacement")
	check(Powers.get_power("dead_centre").card_row == 0 and Powers.get_power("dead_centre").card_texture == Powers.ESCALATION_CARD_SHEET, "New Anchor art occupies escalation row zero")
	var progression: RefCounted = Progression.new()
	progression.setup(Powers.investment_capacity())
	check(progression.threshold() == 18, "Free opening investment preserves the original first earned cost")
	for entity_id: int in range(100, 200): progression.record_event(_event(entity_id))
	check(progression.level == 7 and progression.threshold() == 84 and not progression.is_maxed(), "Later costs plateau at 84 without ending at six or seven powers")
	for entity_id: int in range(200, 100 + int((132 + 84 * (Powers.investment_capacity() - 5)) / 3)): progression.record_event(_event(entity_id))
	check(progression.level == Powers.investment_capacity() and progression.total_xp == 132 + 84 * (Powers.investment_capacity() - 5) and progression.is_maxed(), "Unchanged XP awards and plateau prices cover the larger investment pool")
	check(Progression.TUNING.collision_xp == 2 and Progression.TUNING.heavy_collision_xp == 4 and Progression.TUNING.full_elimination_xp == 18 and Progression.TUNING.small_elimination_xp == 3 and Progression.TUNING.wave_completion_xp == 6, "Escalation does not inflate existing XP awards")

func _test_variable_offers() -> void:
	var starting_signatures: Dictionary = {}
	var new_seen: Dictionary = {}
	var mixed_offers: int = 0
	var omitted_vertical: int = 0
	for seed_value: int in range(1, 65):
		var run: RefCounted = Run.new()
		run.start(Parts.DEFAULT_BUILD, seed_value, "breaker")
		starting_signatures[str(run.pending_offer)] = true
		for power_id: String in run.pending_offer: new_seen[power_id] = true
		var has_vertical: bool = false
		for power_id: String in run.pending_offer:
			if power_id in Powers.VERTICAL_IDS: has_vertical = true
		if not has_vertical: omitted_vertical += 1
		var choice: String = run.pending_offer[0]
		for candidate: String in run.pending_offer:
			if candidate in Powers.VERTICAL_IDS:
				choice = candidate
				break
		run.choose_power(run.pending_draft_id, choice)
		for entity_id: int in range(100, 106): run.award_xp(_event(entity_id))
		if choice in run.pending_offer: mixed_offers += 1
		var twin: RefCounted = Run.new()
		twin.start(Parts.DEFAULT_BUILD, seed_value, "bastion")
		twin.choose_power(twin.pending_draft_id, choice)
		for entity_id: int in range(100, 106): twin.award_xp(_event(entity_id))
		check(twin.pending_offer == run.pending_offer, "Starter identity does not lock or alter the offer pool")
	check(starting_signatures.size() > 20 and new_seen.size() == Powers.ACTIVE_IDS.size(), "Seeded offers vary and can offer all current families")
	check(omitted_vertical > 0, "The opening offer does not guarantee a vertical path")
	check(mixed_offers > 0 and mixed_offers < 64, "Owned eligible powers mix with new powers without an upgrade guarantee")

func _test_vertical_claims(power_id: String, branch_id: String) -> void:
	var run: RefCounted = _start_with(power_id)
	check(run.power_ranks[power_id] == 1 and run.owned_power_ids == [power_id], "First acquisition activates exactly one Rank I power")
	check(not run.choose_mutation("draft/start", branch_id), "A branch cannot bypass Rank II or its offer")
	_fill_entitlements(run)
	var tuned: bool = false
	var transformed: bool = false
	while not run.pending_offer.is_empty():
		var claim: String = run.pending_draft_id
		var choice: String = power_id if power_id in run.pending_offer else run.pending_offer[0]
		var before_rank: int = int(run.power_ranks.get(choice, 0))
		var owned_count: int = run.owned_power_ids.size()
		var offer: Array[String] = run.pending_offer
		check(run.choose_power(claim, choice), "An offered acquisition or upgrade succeeds")
		if before_rank == 1:
			check(run.power_ranks[choice] == 2 and run.owned_power_ids.size() == owned_count, "Rank II upgrades without duplicating ownership")
			if choice == power_id: tuned = true
		if not run.pending_mutation_power.is_empty():
			var pending_power: String = run.pending_mutation_power
			var branches: Array[String] = run.pending_mutation_offer
			check(run.pending_draft_id == claim and run.pending_offer == offer and run.power_ranks[pending_power] == 2, "Mutation selection retains the entitlement, offer and previous mechanical rank")
			check(not run.committed_rewards.has(claim) and not run.advance(), "Opening mutation selection neither spends nor skips its draft")
			check(not run.choose_power(claim, choice), "Held ordinary confirm cannot bypass mutation selection")
			check(not run.choose_mutation("draft/start", branches[0]) and not run.choose_mutation(claim, "invalid"), "Stale claim and invalid branch leave mutation pending")
			var branch: String = branch_id if pending_power == power_id else branches[0]
			var opposite: String = branches[1] if branch == branches[0] else branches[0]
			var ranks_copy: Dictionary = run.power_ranks
			var mutations_copy: Dictionary = run.power_mutations
			var offer_copy: Array[String] = run.pending_mutation_offer
			ranks_copy[pending_power] = 3
			mutations_copy[pending_power] = opposite
			offer_copy.clear()
			check(run.power_ranks[pending_power] == 2 and not run.power_mutations.has(pending_power) and run.pending_mutation_offer == branches, "Menu copies cannot acquire, mutate or erase a branch selection")
			check(run.choose_mutation(claim, branch), "The valid branch commits Rank III")
			check(run.power_ranks[pending_power] == 3 and run.power_mutations[pending_power] == branch and run.committed_rewards[claim] == branch, "One entitlement records one named mutation")
			check(not run.choose_mutation(claim, branch) and not run.choose_mutation(claim, opposite), "Neither duplicate nor opposite branch can claim the same entitlement again")
			check(run.pending_mutation_power.is_empty() and run.pending_mutation_offer.is_empty(), "Confirmation clears only the completed branch event")
			if pending_power == power_id: transformed = true
		check(not run.choose_power(claim, choice), "Stale prior claim cannot consume a later queued level")
	check(tuned and transformed and run.power_mutations[power_id] == branch_id, "Each path reaches its intended exclusive transformation")
	var owned_flagships: int = 0
	for id: String in run.owned_power_ids:
		if id in Powers.VERTICAL_IDS: owned_flagships += 1
	check(run.owned_power_ids.size() == Powers.FAMILY_CAP and run.power_mutations.size() == owned_flagships and run.committed_rewards.size() == run.available_investment_capacity(), "Every chosen family reaches full depth within the machine's seven slots")
	var encounter: Dictionary = run.current_encounter()
	check(encounter.player_power_ranks == run.power_ranks and encounter.player_power_mutations == run.power_mutations, "Encounter and pause/resume descriptors persist exact ranks and branches")
	encounter.player_power_ranks.clear()
	encounter.player_power_mutations.clear()
	check(run.power_ranks.size() == Powers.FAMILY_CAP and run.power_mutations.size() == owned_flagships, "Battle descriptor copies cannot erase progression")
	check(run.commit_result(run.current_encounter().id, true) and run.advance(), "Fully invested build advances normally")
	check(run.current_encounter().player_power_mutations[power_id] == branch_id, "Selected branch survives encounter transitions")

func _reach_pending_mutation() -> RefCounted:
	var run: RefCounted = _start_with("redline")
	_fill_entitlements(run)
	while run.pending_mutation_power.is_empty():
		var choice: String = "redline" if "redline" in run.pending_offer else run.pending_offer[0]
		run.choose_power(run.pending_draft_id, choice)
	return run

func _test_reset_and_terminal_mutation() -> void:
	var run: RefCounted = _reach_pending_mutation()
	var old_claim: String = run.pending_draft_id
	check(run.commit_result(run.current_encounter().id, false), "A failure can terminate a pending mutation")
	check(run.pending_offer.is_empty() and run.pending_mutation_power.is_empty() and run.pending_mutation_offer.is_empty(), "Failure discards every unclaimed branch and queued entitlement")
	check(not run.choose_mutation(old_claim, "runaway"), "Late branch events cannot revive a failed run")
	run.start(Parts.DEFAULT_BUILD, 800, "vane")
	check(run.power_ranks.is_empty() and run.power_mutations.is_empty() and run.pending_mutation_power.is_empty(), "Restart clears ranks, branches and old pending transformations")
	run.clear()
	check(run.power_ranks.is_empty() and run.power_mutations.is_empty() and run.pending_mutation_offer.is_empty(), "Leaving a Run clears all escalation state")
	# A final-result fixture proves the last entitlement completes only on the
	# branch confirmation, rather than on entry to the mutation screen.
	run = _start_with("redline")
	for _slot: int in range(1, 8):
		run.commit_result(run.current_encounter().id, true)
		run.advance()
	_fill_entitlements(run)
	check(run.commit_result("run_slot_08", true) and run.is_active(), "Eighth threat clear keeps earned investments claimable")
	while not run.pending_offer.is_empty():
		var claim: String = run.pending_draft_id
		run.choose_power(claim, run.pending_offer[0])
		if not run.pending_mutation_power.is_empty():
			check(run.status == "active" and not run.advance(), "Mutation event holds threat advancement while selection is paused")
			run.choose_mutation(claim, run.pending_mutation_offer[0])
	check(run.status == "active" and run.advance() and run.slot == 9 and run.power_mutations.size() > 0 and run.pending_draft_id.is_empty() and run.committed_rewards.size() == run.available_investment_capacity(), "Final investment continues beyond threat eight with all chosen branches retained")
