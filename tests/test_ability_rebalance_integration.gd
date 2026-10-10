extends "res://tests/test_continuous_run.gd"
## Controlled build fixtures use the real continuous economy, input and solver.
## Initial danger positions are fixtures, never claimed as natural-run footage.
var measurements: Dictionary = {}

func _run() -> void:
	_test_real_overcap_ledger()
	_test_real_clutch_identity()
	_test_pause_and_defeat()
	_test_live_rank_updates()
	print("ABILITY_REBALANCE_INTEGRATION_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}, "\t"))
	quit(1 if failures else 0)

func configure(b: Node2D, power: String, level: int, branch: String = "") -> Dictionary:
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	p.powers = [power]
	p.power_ranks = {power: level}
	p.power_mutations = {} if branch.is_empty() else {power: branch}
	return p

func total(values: Dictionary) -> float:
	var result: float = 0.0
	for value: float in values.values(): result += value
	return result

func director_state(b: Node2D) -> Dictionary:
	var director = b.continuous.director
	return {"serial": director.serial, "history": director.history.duplicate(true), "active": director.active.duplicate(true), "rng_state": director.rng.state, "next_decision": director.next_decision}

func _test_real_overcap_ledger() -> void:
	for level: int in [1, 2]:
		var game = make_game()
		var b: Node2D = game.battle
		var p: Dictionary = configure(b, "redline", level)
		b._attempt_burst(p, Vector2.RIGHT)
		# This is a movement/economy unit integration, so position stays central
		# while the real acceleration/drag and reserve costs run, independently
		# of director death noise. Natural samples cover unconstrained movement.
		for tick: int in range(185):
			b.elapsed += Battle.FIXED_DT
			b.continuous.economy.begin_tick(Battle.FIXED_DT, Vector2.RIGHT)
			b.powers.begin_tick(Battle.FIXED_DT)
			p.pos = Vector2.ZERO
			b._update_fighter(p, Vector2.RIGHT, false, Battle.FIXED_DT)
			b.continuous.economy.end_tick(Battle.FIXED_DT)
		check(float(p.rpm) > 1.0 and b.powers.effective_rpm(p) == p.rpm, "Real Rank %d input/physics/economy creates stored overcap" % level)
		var e = b.continuous.economy
		check(e.gains.redline_motion > 0.0 and e.losses.redline > 0.0 and e.losses.powers == 0.0 and e.losses.movement > 0.0, "Actual Redline writes retain their dedicated gain/cost sources without double-counting powers")
		check(is_equal_approx(float(p.rpm), 1.0 + total(e.gains) - total(e.losses)), "Continuous ledger exactly closes above 100% RPM")
		b.powers.begin_tick(0.3)
		check(float(p.rpm) <= 1.0 and is_equal_approx(float(p.rpm), 1.0 + total(e.gains) - total(e.losses)), "Expiry vent leaves no unaccounted excess discard")
		measurements["overclock_rank_%d" % level] = {"power": b.powers.diagnostics(p), "economy": e.snapshot()}
		game.free()

func _test_real_clutch_identity() -> void:
	var game = make_game()
	var b: Node2D = game.battle
	var p: Dictionary = configure(b, "clutch", 2)
	p.rpm = 0.15
	p.wobble = 0.8
	p.vel = Vector2(90, 0)
	var identity: Dictionary = p
	var position_before: Vector2 = p.pos
	var size_before: int = b.fighters.size()
	var director_before: Dictionary = director_state(b)
	var e = b.continuous.economy
	e.begin_tick(Battle.FIXED_DT, Vector2(0.5, 0))
	b.powers.recover()
	check(p.clutch_active and p.rpm == 0.15 and p.wobble == 0.8, "Real danger activates Clutch without a free reserve or stability reset")
	b.powers.movement_control(p, Vector2(0.5, 0), false, Battle.FIXED_DT)
	b.powers.accepted_contact(p, b.entity(2), 0.7, Vector2.RIGHT, Vector2(10, 0), Vector2(-70, 0), Vector2(70, 0))
	b.powers.flush_contact_powers()
	check(e.gains.clutch > 0.0 and p.rpm > 0.15 and p.rpm < 0.22, "Accepted meaningful real contact earns limited Clutch reclamation")
	check(is_same(identity, b.player_entity()) and b.fighters.size() == size_before and director_state(b) == director_before, "Clutch preserves same player, enemies and director state")
	check(p.wobble >= 0.75 and p.pos == position_before, "Earned rescue still preserves dangerous wobble and physical position")
	measurements.clutch = {"rpm": p.rpm, "wobble": p.wobble, "gains": e.gains.duplicate()}
	game.free()

func _test_pause_and_defeat() -> void:
	var game = make_game()
	var b: Node2D = game.battle
	var p: Dictionary = configure(b, "redline", 3, "runaway")
	p.powers.append("clutch")
	p.power_ranks.clutch = 2
	b._attempt_burst(p, Vector2.RIGHT)
	b.set_paused(true)
	var before: Dictionary = physical(b)
	for tick: int in range(240): b.test_step(Battle.FIXED_DT, Vector2.RIGHT, true, true)
	check(physical(b) == before, "Paused/draft continuous input freezes new heat, quota, routes, costs and timers")
	b.set_paused(false)
	p.rpm = 0.046
	b.spend_rpm(p, 0.01, "walls")
	b.powers.recover()
	b._check_result()
	check(b.battle_status == "finished" and b.last_result.reason == "spin_out" and p.rpm < 0.045, "Clutch and Redline cannot revive real defeated spin reserve")
	game.free()

func _test_live_rank_updates() -> void:
	var game = make_game()
	var b: Node2D = game.battle
	var p: Dictionary = configure(b, "clutch", 1)
	var identity: Dictionary = p
	var runtime_id: int = b.powers.get_instance_id()
	check(b.acquire_run_power("clutch", 2) and b.powers.rank(p, "clutch") == 2, "Earned Clutch II reaches the actual continuous runtime")
	for id: String in ["impact_wake","iron_comet","chain_impact","orbit_drive","crash_guard","momentum_bank","predator_line","crosscut"]:
		check(b.acquire_run_power(id) and b.acquire_run_power(id, 2) and b.powers.rank(p,id) == 2, "Earned support/new Rank II installs real investment: " + id)
		check(not b.acquire_run_power(id, 3, "runaway"), "Two-rank family rejects an invented mutation: " + id)
	check(is_same(identity,b.player_entity()) and runtime_id == b.powers.get_instance_id(), "Expanded live upgrades preserve the same player and power runtime")
	game.free()
