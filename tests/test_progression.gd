extends SceneTree

const Run = preload("res://scripts/run_context.gd")
const Progression = preload("res://scripts/run_progression.gd")
const Catalog = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Seeds = preload("res://scripts/seed_utils.gd")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func contact(time: float, severity: float = 0.8, first: int = 1, second: int = 2) -> Dictionary:
	return {"kind":"collision", "encounter_id":"run_slot_01", "time":time,
		"first_entity_id":first, "second_entity_id":second, "severity":severity, "player_attributed":true}

func elimination(time: float, entity_id: int, body_type: String = "small_top", reason: String = "ring_out") -> Dictionary:
	return {"kind":"elimination", "encounter_id":"run_slot_01", "time":time,
		"entity_id":entity_id, "combatant_type":body_type, "reason":reason, "player_attributed":true}

func _run() -> void:
	_test_meaningful_events()
	_test_front_loaded_curve()
	_test_initial_draft()
	_test_deterministic_overflow_and_cap()
	_test_terminal_earned_draft()
	print("PROGRESSION_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)

func _test_meaningful_events() -> void:
	var progression = Progression.new()
	progression.setup()
	progression.record_event({"kind":"time", "encounter_id":"run_slot_01", "time":600.0, "player_attributed":true})
	check(progression.total_xp == 0, "Passive time never awards XP")
	progression.record_event(contact(0.0, 0.08))
	check(progression.total_xp == 0, "Weak repeated touching does not earn collision XP")
	progression.record_event(contact(1.0, 0.3))
	check(progression.total_xp == 2, "A meaningful accepted contact earns normal XP")
	progression.record_event(contact(1.0, 0.3))
	progression.record_event(contact(1.24, 1.3, 2, 1))
	check(progression.total_xp == 2, "Duplicate and reversed-pair contacts cannot bypass pair cooldown")
	progression.record_event(contact(1.25, 0.8, 1, 3))
	check(progression.total_xp == 2, "Global collision gate prevents many-pair spam")
	progression.record_event(contact(1.31, 0.8, 1, 3))
	check(progression.total_xp == 6, "A distinct meaningful heavy collision gets severity-weighted XP")
	progression.record_event(contact(2.15, 0.8))
	check(progression.total_xp == 10, "Exact simulation-time pair cooldown boundary awards once")
	var old: Dictionary = contact(1.9, 0.8, 1, 4)
	progression.record_event(old)
	check(progression.total_xp == 10, "Out-of-order timestamps cannot reset deterministic cooldowns")
	var ambient: Dictionary = contact(3.0, 0.8, 3, 4)
	ambient.player_attributed = false
	progression.record_event(ambient)
	check(progression.total_xp == 10, "Unattributed enemy collisions never award player XP")
	var cause_contact: Dictionary = contact(3.1, 0.8, 3, 4)
	cause_contact.erase("player_attributed")
	cause_contact["cause"] = {"owner_id":"player", "expires_at":3.0}
	progression.record_event(cause_contact)
	check(progression.total_xp == 10, "Expired player causes cannot credit distant contacts")
	cause_contact.time = 3.2
	cause_contact.cause.expires_at = 4.0
	progression.record_event(cause_contact)
	check(progression.total_xp == 14, "A live propagated player cause credits meaningful mechanical interactions")
	progression.record_event(elimination(4.0, 100, "small_top", "impact"))
	progression.record_event(elimination(4.1, 100, "small_top", "spin_out"))
	check(progression.total_xp == 17, "Each small top earns exactly one elimination award")
	for reason: String in ["natural_retirement", "cleanup", "despawn", "timeout"]:
		progression.record_event(elimination(4.2, 200, "small_top", reason))
	check(progression.total_xp == 17, "Natural retirement and cleanup do not reward passive survival")
	progression.record_event(elimination(5.0, 2, "full_top", "spin_out"))
	check(progression.total_xp == 35 and progression.level == 2, "Credited full-rival spin-out earns a larger award with overflow")
	var wave: Dictionary = {"kind":"wave_complete", "encounter_id":"run_slot_01", "time":6.0, "wave":1, "player_attributed":true}
	progression.record_event(wave)
	wave.time = 7.0
	wave["event_id"] = "different_event_same_wave"
	progression.record_event(wave)
	check(progression.total_xp == 41, "A credited completed wave awards once even with a fresh event ID")
	wave.wave = 2
	wave.player_attributed = false
	progression.record_event(wave)
	check(progression.total_xp == 41, "An entirely naturally retired wave gives no XP")
	var copy: Dictionary = progression.snapshot()
	copy.xp = 10000
	check(progression.level == 3 and progression.xp == 1, "HUD snapshot cannot mutate XP after crossing the authored 18 and 22 XP opening costs")

func _test_front_loaded_curve() -> void:
	var progression = Progression.new()
	progression.setup()
	check(progression.level == 1 and progression.threshold() == 18, "Opening earned upgrade costs 18 XP after the free initial power")
	var level_times: Array[float] = []
	# A representative active-contact cadence, not an elapsed-time XP source.
	for index: int in range(1, 14):
		var crossed: Array[int] = progression.record_event(contact(float(index) * 3.0))
		if not crossed.is_empty(): level_times.append(float(index) * 3.0)
	check(level_times.size() == 2 and level_times[0] >= 15.0 and level_times[0] <= 25.0, "Representative committed heavy contacts earn the first upgrade in 15–25 seconds")
	check(level_times[1] < 60.0, "The same active cadence earns a second meaningful choice within the first minute")
	var costs: Array = Progression.TUNING.level_costs
	check(costs[0] < costs[1] and costs[1] < costs[2] and costs[2] < costs[3] and costs[3] < costs[4], "Costs deliberately lengthen after rapid identity formation")

func _test_initial_draft() -> void:
	var run = Run.new()
	run.start(Catalog.DEFAULT_BUILD, 12003, "breaker")
	check(run.starter_id == "breaker" and run.pending_draft_kind == "starting" and run.pending_draft_level == 1, "Run identity is locked before a starting choice")
	check(run.pending_offer.size() == 3 and run.pending_draft_id == "draft/start", "Starting offer has three functional choices before any battle")
	var unique: Dictionary = {}
	for power_id: String in run.pending_offer:
		unique[power_id] = true
		check(power_id in Powers.ACTIVE_IDS, "Only working powers are in the starting draft")
	check(unique.size() == 3, "Starting cards have no duplicates")
	check(not run.commit_result("run_slot_01", true) and not run.award_xp(contact(1.0)), "No unpowered battle can commit or earn XP before the opening claim")
	var claim: String = run.pending_draft_id
	var choice: String = run.pending_offer[0]
	check(not run.choose_power("run_slot_01", choice), "An encounter ID cannot impersonate a draft claim")
	check(run.choose_power(claim, choice), "Starting choice claims exactly once")
	check(not run.choose_power(claim, choice) and run.owned_power_ids == [choice], "Held or repeated opening confirmation cannot acquire twice")
	check(run.current_encounter().player_power_ids == [choice] and not run.current_encounter().draft_after, "First launch carries a power and no fixed slot reward")

func _test_deterministic_overflow_and_cap() -> void:
	var first = Run.new()
	var second = Run.new()
	first.start(Catalog.DEFAULT_BUILD, 554433, "vane")
	second.start(Catalog.DEFAULT_BUILD, 554433, "vane")
	var cosmetics: RandomNumberGenerator = RandomNumberGenerator.new()
	cosmetics.seed = Seeds.derive(554433, "cosmetics")
	var first_choice: String = first.pending_offer[0]
	first.choose_power(first.pending_draft_id, first_choice)
	second.choose_power(second.pending_draft_id, first_choice)
	# Multiple independent eliminations can legitimately arrive in one fixed tick.
	for entity_id: int in range(100, 368):
		var event: Dictionary = elimination(10.0, entity_id)
		first.award_xp(event)
		for _sample: int in range(7): cosmetics.randf()
		second.award_xp(event)
	check(first.level == 13 and first.progression_snapshot().maxed, "A batch crossing costs preserves twelve earned entitlements and caps at thirteen investments")
	check(first.pending_draft_id == "draft/level_02", "Queued overflow presents the earliest earned draft first")
	check(not first.advance(), "Unclaimed earned drafts cannot skip the encounter")
	for earned_level: int in range(2, 14):
		var draft_id: String = first.pending_draft_id
		var offer: Array[String] = first.pending_offer
		check(first.pending_draft_level == earned_level and first.pending_draft_kind == "level", "Overflow draft retains a stable level identity")
		check(offer == second.pending_offer and draft_id == second.pending_draft_id, "Recorded events and choices reproduce the offer independently of cosmetic RNG")
		var eligible: int = 0
		for power_id: String in Powers.ACTIVE_IDS:
			if Powers.can_progress(power_id, int(first.power_ranks.get(power_id, 0))): eligible += 1
		check(offer.size() == mini(3, eligible), "Exhaustion offers only real remaining investments")
		for power_id: String in offer: check(Powers.can_progress(power_id, int(first.power_ranks.get(power_id, 0))), "Owned powers reappear only while they can progress")
		var exposed: Array[String] = first.pending_offer
		exposed.clear()
		check(first.pending_offer == offer, "Reopening and mutating UI copies cannot reroll a pending draft")
		var choice: String = offer[earned_level % offer.size()]
		check(first.choose_power(draft_id, choice) and second.choose_power(draft_id, choice), "Each earned entitlement can be claimed")
		check(not first.choose_power(draft_id, choice), "Stale same-encounter claim cannot consume the next queued entitlement")
		if not first.pending_mutation_power.is_empty():
			var branch: String = first.pending_mutation_offer[earned_level % 2]
			check(first.choose_mutation(draft_id, branch) and second.choose_mutation(draft_id, branch), "Queued mutation entitlement commits a mutually exclusive branch")
			check(not first.choose_mutation(draft_id, branch), "Stale branch claim cannot consume the next queued entitlement")
	check(first.owned_power_ids.size() == 7 and first.pending_offer.is_empty() and first.pending_draft_id.is_empty(), "All seven powers and six vertical upgrades end drafting cleanly")
	var max_state: Dictionary = first.progression_snapshot()
	first.award_xp(elimination(20.0, 999))
	check(first.level == max_state.level and first.progression_snapshot().total_xp == max_state.total_xp and first.xp == 0 and first.pending_offer.is_empty(), "MAX ignores further XP without fake duplicate ranks")
	check(first.owned_power_ids == second.owned_power_ids and first.current_encounter() == second.current_encounter(), "Seed and recorded choices reproduce collection and unchanged encounter descriptors")

func _test_terminal_earned_draft() -> void:
	var run = Run.new()
	run.start(Catalog.DEFAULT_BUILD, 81)
	run.choose_power(run.pending_draft_id, run.pending_offer[0])
	for _slot: int in range(1, 8):
		run.commit_result(run.current_encounter().id, true)
		run.advance()
	for index: int in range(6):
		var event: Dictionary = contact(float(index) * 2.0)
		event.encounter_id = "run_slot_08"
		run.award_xp(event)
	check(run.commit_result("run_slot_08", true) and run.is_active(), "An ending victory preserves a draft already earned by final combat")
	check(not run.advance(), "Final queued choice cannot launch a ninth encounter")
	check(run.choose_power(run.pending_draft_id, run.pending_offer[0]) and run.status == "complete", "Claiming the earned final entitlement completes the Run")
	run.start(Catalog.DEFAULT_BUILD, 82, "bastion")
	run.choose_power(run.pending_draft_id, run.pending_offer[0])
	for index: int in range(6): run.award_xp(contact(float(index) * 2.0))
	check(run.commit_result("run_slot_01", false) and run.pending_offer.is_empty() and run.status == "failed", "Failure discards unclaimed entitlements and freezes progression")
	check(not run.award_xp(contact(20.0)) and not run.choose_power("draft/level_02", "impact_wake"), "Failed Run cannot be revived by late events or cards")
