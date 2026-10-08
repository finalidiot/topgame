extends SceneTree
## Isolated semantic payout fixtures, not natural survival evidence. Real
## Battle/continuous Economy validate identity, caps, eligibility and cooldowns.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Economy = preload("res://scripts/spin_economy.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func fixture() -> Node2D:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1,421)
	descriptor.starter_id = "bastion"
	descriptor.player_power_ids = []
	descriptor.player_power_ranks = {}
	descriptor.player_power_mutations = {}
	battle.begin_run(Starters.build_for("bastion"),descriptor,421)
	for tick: int in range(240):
		if battle.battle_status == "battle": break
		battle.test_step(Battle.FIXED_DT)
	check(battle.battle_status == "battle", "Ordinary production countdown reaches battle")
	var player: Dictionary = battle.player_entity()
	player.rpm = .40
	player.energy = .40
	player.wobble = .10
	battle.continuous.observe_input(.4, Vector2(.25,0))
	battle.continuous.economy.begin_tick(.4,Vector2(.25,0))
	return battle

func run() -> void:
	var previous: float = .65
	for speed: float in [-200.0,-20.0,0.0,24.999,25.0,25.001,35.0,45.0,55.0,64.999,65.0,200.0]:
		var scale: float = Economy.generic_contact_scale(speed)
		check(scale >= .65 and scale <= 1 and scale >= previous, "Bounded monotonic normal-speed commitment " + str(speed))
		if speed <= 25: check(is_equal_approx(scale,.65), "Received/low-approach contact retains65% generic gain")
		if speed >= 65: check(is_equal_approx(scale,1), "Committed contact retains exact original scale")
		previous = scale
	check(is_equal_approx(Economy.generic_contact_scale(45),.825), "Middle smoothstep is a gradual bridge")
	check(absf(Economy.generic_contact_scale(25.001)-Economy.generic_contact_scale(25)) < .000001, "No abrupt lower threshold jump")
	check(absf(Economy.generic_contact_scale(65)-Economy.generic_contact_scale(64.999)) < .000001, "No abrupt upper threshold jump")
	for approach: float in [-25.0,0.0,25.0,45.0,65.0,100.0]:
		var battle: Node2D = fixture()
		var player: Dictionary = battle.player_entity()
		var e = battle.continuous.economy
		var start: float = player.rpm
		var old_amount: float = minf(.060,.02*1.4+1.0*.014+(.022 if approach>=65 else 0.0))
		e.contact(battle.entity(2),1.0,.02,approach,80.0)
		check(is_equal_approx(float(player.rpm)-start,old_amount*Economy.generic_contact_scale(approach)), "Actual valid payout follows only generic scale " + str(approach))
		check(is_equal_approx(float(e.gains.combat_reclamation),float(player.rpm)-start), "Generic contact ledger records exact real payout")
		if approach < 25: check(float(player.rpm)>start, "Active defensive absorption still qualifies")
		if approach >= 65: check(is_equal_approx(float(player.rpm)-start,.060), "Committed hard hit amount/bonus/cap remain original")
		var paid: float = player.rpm
		e.contact(battle.entity(2),1.0,.02,approach,80.0)
		check(player.rpm == paid, "Repeated same target cannot pay through cooldown")
		check(is_equal_approx(float(e.contacts[2])-battle.elapsed,1.8) and is_equal_approx(float(e.ready_at)-battle.elapsed,.45), "Existing target/global cooldown seconds unchanged")
		battle.free()
	eligibility_and_caps()
	print("CONTACT_RECLAIM_003A1_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func eligibility_and_caps() -> void:
	for issue: String in ["idle", "stationary", "unstable", "tiny", "low_severity", "wrong_owner", "retired"]:
		var battle: Node2D = fixture()
		var player: Dictionary = battle.player_entity()
		var e = battle.continuous.economy
		var target: Dictionary = battle.entity(2)
		var before: float = player.rpm
		var severity: float = 1
		var damage: float = .02
		var moving: float = 80
		match issue:
			"idle": e.begin_tick(.1,Vector2.ZERO)
			"stationary": moving = 7.99
			"unstable": player.wobble = .31
			"tiny": damage = .00399
			"low_severity": severity = .31999
			"wrong_owner": target = player
			"retired": target.outcome = "spin_out"
		e.contact(target,severity,damage,0,moving)
		check(float(player.rpm)==before, "Existing defensive eligibility/canonical target rejection retained " + issue)
		battle.free()
	var battle: Node2D = fixture()
	var player: Dictionary = battle.player_entity()
	var e = battle.continuous.economy
	e.tokens = .01
	e.contact(battle.entity(2),1,.02,100,80)
	check(is_equal_approx(float(player.rpm),.41) and is_equal_approx(float(e.gains.combat_reclamation),.01), "Shared gain bucket still caps committed contacts")
	battle.free()
	battle = fixture()
	player = battle.player_entity()
	e = battle.continuous.economy
	player.rpm = .99
	e.contact(battle.entity(2),1,.02,100,80)
	check(is_equal_approx(float(player.rpm),1.0) and is_equal_approx(float(e.gains.combat_reclamation),.01), "Actual remaining reserve capacity still caps gain")
	battle.free()
	battle = fixture()
	player = battle.player_entity()
	e = battle.continuous.economy
	var before: float = player.rpm
	e.gain(player,.03,"impact_sink")
	check(is_equal_approx(float(player.rpm)-before,.03), "Power-specific stored-force gain is not scaled by generic contact rule")
	battle.free()
