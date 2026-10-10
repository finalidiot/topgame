extends "res://tests/test_continuous_run.gd"
const Economy = preload("res://scripts/spin_economy.gd")
func _run() -> void:
	_test_sources()
	_test_recovery()
	_test_powers()
	_test_continuity()
	_test_defeat_and_duel()
	_test_rpm_and_clock()
	print("SPIN_ECONOMY_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)

func _test_sources() -> void:
	var game = make_game()
	var b = game.battle
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	var e = b.continuous.economy
	check(not b.continuous.TUNING.has("player_rpm_loss_scale") and not b.continuous.has_method("apply_testing_rpm"),"Old net-loss rule is removed")
	p.powers = []
	p.rpm = 0.8
	e.running_costs(p,0.0,Vector2.ZERO,false,1.0,1.0)
	var idle_loss: float = 0.8-p.rpm
	check(idle_loss > 0.0,"Natural decay remains real while idle")
	p.rpm = 0.8
	e.running_costs(p,220.0,Vector2.RIGHT,true,1.0,1.0)
	check(0.8-float(p.rpm) > idle_loss*2.0,"Movement, acceleration and braking spend more than conservation")
	check(e.losses.passive > 0 and e.losses.movement > 0 and e.losses.braking > 0,"Running sources are separately accounted")
	p.rpm = 0.8
	b._attempt_burst(p,Vector2.RIGHT)
	check(is_equal_approx(p.rpm,0.787),"Burst charges all 1.3% reserve, no hidden rebate")
	var rpm: float = p.rpm
	var ledger: Dictionary = e.snapshot()
	b.set_paused(true)
	for tick in range(180): b.test_step(Battle.FIXED_DT,Vector2.RIGHT,true,true)
	check(p.rpm == rpm and e.snapshot() == ledger,"Pause freezes reserve and accounting")
	b.set_paused(false)
	p.rpm = 0.046
	b.spend_rpm(p,0.01,"walls")
	b._check_result()
	check(b.battle_status == "finished" and b.last_result.reason == "spin_out","Real spending can still spin the player out")
	game.free()

func _test_recovery() -> void:
	var game = make_game()
	var b = game.battle
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	var target: Dictionary = b.entity(2)
	var e = b.continuous.economy
	p.rpm = 0.2
	e.begin_tick(1.0,Vector2.RIGHT)
	for attempt in range(100): e.contact(target,0.1,0.001,100.0)
	check(p.rpm == 0.2,"Tiny contact spam cannot farm RPM")
	e.control = 0.0
	e.contact(target,1.0,0.03,100.0)
	check(p.rpm == 0.2,"AFK contacts cannot reclaim")
	e.control = 0.8
	e.contact(target,1.0,0.03,0.0,0.0)
	check(p.rpm == 0.2,"Stationary contacts cannot farm even with held steering")
	e.contact(target,1.0,0.03,100.0)
	check(p.rpm > 0.2 and p.rpm <= 0.2+Economy.TUNING.contact_max,"A meaningful committed collision can rescue low RPM")
	var after: float = p.rpm
	b.add_full_top(target.build,3,"hostile","rival_3",Vector2(100,40))
	e.contact(b.entity(3),1.0,0.03,100.0)
	check(p.rpm == after,"Global contact cooldown also rejects another target in the same instant")
	for attempt in range(100): e.contact(target,1.0,0.03,100.0)
	check(p.rpm == after,"Same-target/global cooldowns reject spam")
	b.elapsed += 2.0
	e.begin_tick(2.0,Vector2.RIGHT)
	e.contact(target.duplicate(true),1.0,0.03,100.0)
	check(p.rpm == after,"Stale enemy record cannot grant recovery")
	target.outcome = "spin_out"
	e.contact(target,1.0,0.03,100.0)
	check(p.rpm == after,"Dead enemy contacts cannot grant recovery")
	target.outcome = ""
	target.rpm = 0.03
	target.powers = ["second_wind"]
	target.second_wind_used = false
	e.outcomes()
	check(p.rpm == after and not e.paid.has(2),"Provisional enemy spin-out cannot pay before its Second Wind rescue")
	b.powers.recover()
	check(float(target.rpm) > 0.045,"Enemy emergency recovery remains valid")
	target.outcome = "spin_out"
	for kind: String in ["elite","boss"]:
		# This fixture represents a recently controlled defensive impact; raw
		# dictionary credit alone must not stand in for production activity.
		b.continuous.observe_input(0.4,Vector2(0.20,0))
		e.paid.clear()
		e.tokens = Economy.TUNING.bucket_capacity
		target.enemy_kind = kind
		e.credits[2] = b.elapsed
		p.rpm = 0.3
		var position: Vector2 = p.pos
		var velocity: Vector2 = p.vel
		var wobble: float = p.wobble
		e.outcomes()
		check(is_equal_approx(p.rpm,0.3+float(Economy.TUNING[kind])),kind+" payoff is modest and exact")
		e.outcomes()
		check(is_equal_approx(p.rpm,0.3+float(Economy.TUNING[kind])),kind+" cannot pay twice")
		check(p.pos == position and p.vel == velocity and p.wobble == wobble and is_same(p,b.player_entity()),kind+" never resets physical state")
	p.rpm = 0.999
	e.gain(p,1.0,"second_wind")
	check(p.rpm == 1.0,"Recovery cannot exceed maximum")
	p.rpm = 0.3
	e.tokens = Economy.TUNING.bucket_capacity
	for attempt in range(1000): e.gain(p,0.03,"runaway",true)
	check(p.rpm <= 0.3+Economy.TUNING.small_capacity+0.000001,"Dense small-top and power recovery share a strict budget")
	for tick in range(600):
		e.begin_tick(0.1,Vector2.RIGHT)
		e.gain(p,1.0,"elimination",true)
	check(p.rpm <= 0.308+60.0*Economy.TUNING.small_rate+0.000001,"Small recovery remains rate-limited over time")
	e.paid.clear()
	e.credits[2] = b.elapsed-30.0
	var stale_rpm: float = p.rpm
	e.outcomes()
	check(p.rpm == stale_rpm,"Old contact credit cannot cash a later passive enemy death")
	p.rpm = 0.2
	e.tokens = Economy.TUNING.bucket_capacity
	for attempt in range(100): e.gain(p,0.095,"combat_reclamation")
	check(p.rpm <= 0.2+Economy.TUNING.bucket_capacity+0.000001,"Shared bucket bounds even many independent full-enemy rewards")
	e.retire(2)
	check(not e.contacts.has(2) and not e.credits.has(2) and not e.paid.has(2),"Enemy economy state retires without leaking")
	var old_economy = e
	var build: Dictionary = p.build.duplicate()
	var descriptor: Dictionary = b.encounter.duplicate(true)
	b.begin_run(build,descriptor,777)
	b.battle_status = "battle"
	var new_player: Dictionary = b.player_entity()
	new_player.rpm = 0.5
	old_economy.gain(new_player,0.1,"elimination")
	check(new_player.rpm == 0.5,"Old Run economy cannot mutate a restarted player")
	game.free()

func _test_powers() -> void:
	var game = make_game()
	var b = game.battle
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	p.powers = ["redline","second_wind"]
	p.power_ranks = {"redline":3,"second_wind":1}
	p.power_mutations = {"redline":"breakneck"}
	p.rpm = 0.8
	b._attempt_burst(p,Vector2.RIGHT)
	check(p.rpm < 0.76 and b.continuous.economy.losses.redline > 0.0,"Expensive Redline activation still spends separately accounted reserve")
	p.rpm = 0.13
	b.powers.recover()
	check(is_equal_approx(p.rpm,0.31) and p.second_wind_used,"Second Wind retains the emergency 18% rescue")
	p.rpm = 0.13
	b.powers.recover()
	check(p.rpm == 0.13,"Second Wind remains once per launch")
	check(is_equal_approx(b.continuous.economy.gains.second_wind,0.18),"Second Wind is separately accounted")
	game.free()
