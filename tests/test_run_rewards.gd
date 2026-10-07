extends SceneTree
## Discrete earned clear accounting and session provenance. All outcome edits
## below are labelled unit fixtures; no player collection is opened.
const Rewards = preload("res://scripts/run_rewards.gd")
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func clear_summary(serial: int, kind: String = "rival", earned: bool = true) -> Dictionary:
	return {"run_seed":421,"threat":serial,"kind":kind,"reward_provenance":Rewards.PROVENANCE,
		"reward_eligible":earned,"reward_fixture":false}

func result_for(ledger: RefCounted) -> Dictionary:
	var result: Dictionary = ledger.snapshot()
	result.merge({"run_seed":421,"continuous_run":true,"won":false,"reason":"spin_out"})
	return result

func new_battle() -> Node2D:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.begin_run(Starters.build_for("breaker"), Encounters.for_run_event(1,421),421)
	battle.battle_status = "battle"
	battle.elapsed = 1.0
	return battle

func test_ledger() -> void:
	var ledger = Rewards.new()
	check(not bool(ledger.finalize({}).ok),"Unstarted ledgers cannot finalize")
	ledger.start(421,"unit-nonce")
	check(ledger.observe_clear(clear_summary(1)),"One earned discrete clear enters the ledger")
	check(not ledger.observe_clear(clear_summary(1)),"Repeated threat-clear callback cannot pay again")
	check(ledger.observe_clear(clear_summary(2,"elite")),"Earned elite receives one threat and one bonus counter")
	check(ledger.observe_clear(clear_summary(3,"boss")),"Earned boss receives one threat and one bonus counter")
	check(not ledger.observe_clear(clear_summary(4,"swarm",false)),"Cleanup without credited eliminations gives zero")
	var stale: Dictionary = clear_summary(5)
	stale.run_seed = 422
	check(not ledger.observe_clear(stale),"Clear from another seeded session is refused")
	stale = clear_summary(5)
	stale.reward_provenance = ""
	check(not ledger.observe_clear(stale),"Raw clear numbers without provenance are refused")
	check(ledger.observe_clear(clear_summary(5,"specialist")),"Production flanker/harasser specialist clears enter the same discrete threat ledger")
	check(ledger.snapshot().earned_threats_cleared == 4 and ledger.snapshot().earned_elites_cleared == 1 and ledger.snapshot().earned_bosses_cleared == 1,"Only genuine event counters are accumulated")
	var end: Dictionary = result_for(ledger)
	end.merge({"hits":999999,"duration":999999.0,"xp":999999,"threats_cleared":999999,"elites_defeated":999999,"bosses_defeated":999999})
	var paid: Dictionary = ledger.finalize(end)
	check(bool(paid.ok) and paid.outcome.earned_threats_cleared == 4,"Collisions, time, raw XP and legacy counts cannot enter reward outcome")
	check(not bool(ledger.finalize(end).ok),"Reopening results cannot finalize the same ledger twice")
	ledger.start(421,"second-nonce")
	ledger.observe_clear(clear_summary(1))
	end = result_for(ledger)
	end.earned_threats_cleared += 1
	check(not bool(ledger.finalize(end).ok),"A forged final counter that differs from observed clears is refused")
	end = result_for(ledger)
	end.won = true
	check(not bool(ledger.finalize(end).ok),"Ordinary victory cannot be paid as a continuous Run end")
	end = result_for(ledger)
	end.reason = "timeout"
	check(not bool(ledger.finalize(end).ok),"Timed QA result is refused")
	ledger.abort()
	check(not bool(ledger.finalize(result_for(ledger)).ok),"Aborting the Run cannot pay partial rewards")
	ledger.start(421,"practice-nonce",false)
	ledger.observe_clear(clear_summary(1))
	paid = ledger.finalize(result_for(ledger))
	check(bool(paid.ok) and bool(paid.outcome.reward_fixture),"Practice/smoke eligibility carries a permanent no-payment flag")
	ledger.start(421,"fixture-nonce")
	ledger.observe_clear(clear_summary(1))
	end = result_for(ledger)
	end.reward_fixture = true
	paid = ledger.finalize(end)
	check(bool(paid.ok) and bool(paid.outcome.reward_fixture),"Fixture introduced after the last clear invalidates the whole session")

func test_physical_accounting() -> void:
	var battle: Node2D = new_battle()
	# No-input fixture: a rival spins down without any player contribution.
	battle.entity(2).outcome = "spin_out"
	battle.continuous.after_tick(0.0)
	check(battle.continuous.threats_cleared == 1 and battle.continuous.earned_threats_cleared == 0,"AFK natural spin-down clears the event but earns no Credits")
	battle.free()
	battle = new_battle()
	battle.continuous.observe_input(0.5,Vector2.RIGHT)
	battle.entity(2).outcome = "ring_out"
	battle.continuous.after_tick(0.0)
	check(battle.continuous.earned_threats_cleared == 0,"Movement alone cannot turn an unattributed retirement into money")
	battle.free()
	battle = new_battle()
	battle.continuous.observe_input(0.5,Vector2.RIGHT)
	battle._progression_contacted[2] = true
	battle.entity(2).outcome = "ring_out"
	battle.continuous.after_tick(0.0)
	check(battle.continuous.earned_threats_cleared == 1 and battle.continuous.last_clear.reward_eligible,"A played, attributed physical clear earns exactly one discrete clear")
	battle.continuous.after_tick(0.0)
	check(battle.continuous.earned_threats_cleared == 1,"After-tick repetition cannot accrue the same clear again")
	battle.free()
	battle = new_battle()
	battle.continuous.observe_input(0.5,Vector2.RIGHT)
	battle.elapsed = 10.0
	battle._progression_contacted[2] = true
	battle.entity(2).outcome = "spin_out"
	battle.continuous.after_tick(0.0)
	check(battle.continuous.earned_threats_cleared == 0,"Stale participation followed by no-input waiting earns zero")
	battle.free()
	battle = new_battle()
	battle.continuous.observe_input(0.5,Vector2(0.038,0.0))
	battle._progression_contacted[2] = true
	battle.entity(2).outcome = "ring_out"
	battle.continuous.after_tick(0.0)
	check(battle.continuous.earned_threats_cleared == 1,"Fine analogue steering after native stick deadzone remains deliberate play")
	battle.free()
	for control: Dictionary in [{"brake":true,"burst":false},{"brake":false,"burst":true}]:
		battle = new_battle()
		battle.continuous.observe_input(0.5,Vector2.ZERO,bool(control.brake),bool(control.burst))
		battle._progression_contacted[2] = true
		battle.entity(2).outcome = "ring_out"
		battle.continuous.after_tick(0.0)
		check(battle.continuous.earned_threats_cleared == 1,"Deliberate brake/burst play can earn attributed clears without steering")
		battle.free()
	battle = new_battle()
	battle.continuous.observe_input(Battle.FIXED_DT,Vector2.ZERO,false,true)
	battle._progression_contacted[2] = true
	battle.entity(2).outcome = "ring_out"
	battle.continuous.after_tick(0.0)
	check(battle.continuous.earned_threats_cleared == 1,"An immediate no-steering physical Burst knockout proves intent on its first tick")
	battle.free()
	for credited_count: int in [0,2,3]:
		battle = new_battle()
		battle.continuous.observe_input(0.5,Vector2.RIGHT)
		var event: Dictionary = {"serial":2,"kind":"swarm","key":"ammunition","name":"AMMUNITION WAVES","role":"hunter","small_cap":10}
		battle.continuous._admit(event,Vector2(115,30))
		for entry: Dictionary in battle.swarm.schedule: entry.state = "cancelled"
		battle.swarm.cancelled = battle.swarm.schedule.size()
		battle.swarm.wave = battle.swarm.total_waves
		var ids: Array = battle.continuous.events[2].ids
		for index: int in range(credited_count):
			var fighter: Dictionary = battle.swarm.add_small(int(ids[index]),Vector2(100 + index,30))
			fighter.player_cause = {"owner_id":"player","expires_at":100.0}
			fighter.outcome = "impact"
		battle.continuous.after_tick(0.0)
		check(battle.continuous.earned_threats_cleared == (1 if credited_count >= 3 else 0),"Swarm clear requires three real attributed eliminations; zero/cleanup and token kills pay zero (%d)" % credited_count)
		battle.free()
	battle = new_battle()
	battle.continuous._spawn_next()
	check(battle.continuous.reward_fixture and battle.continuous.snapshot().reward_fixture,"Explicit threat-spawn QA seam permanently disables economic eligibility")
	battle.free()

func run() -> void:
	test_ledger()
	test_physical_accounting()
	print("RUN_REWARDS_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
