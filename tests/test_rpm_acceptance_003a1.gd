extends "res://tests/test_continuous_run.gd"
## Resource/risk contracts. Fixtures are not natural Run survival evidence.
const Economy = preload("res://scripts/spin_economy.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Catalog = preload("res://scripts/parts.gd")

func _run() -> void:
	_management_debt()
	_rewards_leave_history()
	_starter_identity_and_burst()
	_risk_remains()
	print("RPM_ACCEPTANCE_003A1_%s checks=%d failures=%d"%["PASS" if failures==0 else "FAIL",checks,failures])
	quit(1 if failures else 0)

func _management_debt() -> void:
	var game: QuietMain = make_game();var b: Node2D=game.battle
	b.battle_status="battle";b.set_paused(false)
	var p: Dictionary=b.player_entity();var e: RefCounted=b.continuous.economy
	p.powers=[];p.rpm=.90;p.wobble=.30
	# Ninety seconds of expensive movement/braking creates real debt; one
	# successful collision feels useful without wiping that history.
	for step: int in range(90):
		b.elapsed+=1.0;e.begin_tick(1.0,Vector2.RIGHT)
		e.running_costs(p,190.0,Vector2.RIGHT,true,1.0,1.0)
	var debt: float=.90-float(p.rpm);var before: float=p.rpm
	check(debt>.35 and p.rpm>.045,"Prolonged waste is meaningful without instant spin-out")
	e.contact(b.entity(2),1.0,.04,100.0,190.0)
	check(p.rpm>before+.02,"A strong committed contact still visibly returns spin")
	check(float(p.rpm)-before<debt*.25,"One strong hit cannot erase ninety seconds of reserve spending")
	check(p.rpm<.75,"Recovery leaves earlier spending visible")
	var frozen: Dictionary=e.snapshot();b.set_paused(true)
	for tick: int in range(90):b.test_step(Battle.FIXED_DT,Vector2.RIGHT,true,true)
	check(e.snapshot()==frozen,"Pause cannot mint recovery tokens or alter the reserve ledger")
	game.free()

func _rewards_leave_history() -> void:
	for kind: String in ["elimination","elite","boss"]:
		var game: QuietMain=make_game();var b: Node2D=game.battle
		b.battle_status="battle";b.set_paused(false)
		var p: Dictionary=b.player_entity();var target: Dictionary=b.entity(2)
		var e: RefCounted=b.continuous.economy
		p.rpm=.45;target.enemy_kind=kind;target.outcome="spin_out"
		b.continuous.observe_input(.4,Vector2(.2,0));e.credits[int(target.entity_id)]=b.elapsed
		e.outcomes()
		var after: float=p.rpm
		check(after>.45 and after<=.55+.000001,kind+" is rewarding and preserves expenditure history")
		e.outcomes();check(p.rpm==after,kind+" cannot double-pay")
		check(float(e.gains[kind])>.0,kind+" is attributed in its own source ledger")
		game.free()

func _starter_identity_and_burst() -> void:
	for starter: String in Starters.IDS:
		var b: Node2D=Battle.new();root.add_child(b);b.set_physics_process(false)
		var d: Dictionary=Encounters.for_run_event(1,421)
		d.starter_id=starter;d.player_power_ids=[];d.player_power_ranks={}
		b.begin_run(Starters.build_for(starter),d,421);b.battle_status="battle"
		var p: Dictionary=b.player_entity();var before: Vector2=p.vel
		b._attempt_burst(p,Vector2.RIGHT)
		check(is_equal_approx(float(p.rpm),.987),starter+" ordinary Burst stays a modest1.3% cost")
		check(Vector2(p.vel).is_equal_approx(before+Vector2.RIGHT*(67.0+float(p.stats.grip)*3.0)),starter+" Burst momentum remains exact")
		check(p.handling==Starters.HANDLING[starter],starter+" authored speed/mass/bank/efficiency identity preserved")
		check(is_equal_approx(float(b.continuous.economy.losses.burst),.013),starter+" repeated commitments are source-accounted")
		b.free()
	check(Economy.TUNING.passive_base<=.0035 and Economy.TUNING.passive_floor<=.0009,"Recovery-led correction keeps the passive change modest")
	check(Starters.HANDLING.vane.spin_drain<Starters.HANDLING.breaker.spin_drain,"Vane keeps its efficient mobility")

func _risk_remains() -> void:
	var b: Node2D=Battle.new();root.add_child(b);b.set_physics_process(false)
	var d: Dictionary=Encounters.for_run_event(1,7341);d.starter_id="breaker"
	d.player_power_ids=[];d.player_power_ranks={}
	b.begin_run(Starters.build_for("breaker"),d,7341)
	# Hold a launch line and repeatedly commit. No reposition, reserve edit,
	# altered wall/gate or scripted defeat is used after initialization.
	for tick: int in range(1800):
		if b.battle_status=="finished":break
		b.test_step(Battle.FIXED_DT,Vector2.RIGHT,float(b.player_entity().cooldown)<=0.0,false)
	check(b.battle_status=="finished" and b.last_result.reason=="ring_out","Repeated reckless Breaker commitments can naturally self ring-out")
	check(float(b.player_entity().rpm)>.045,"Ring-out risk is independent of reserve exhaustion")
	b.free()
