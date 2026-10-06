extends SceneTree
## Eligibility fixtures isolate automatic physical credit from active defence.
## Physics/XP attribution are preserved; these are unit outcomes, not balance.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func make_battle() -> Node2D:
	var b: Node2D = Battle.new()
	root.add_child(b)
	b.set_physics_process(false)
	var d: Dictionary = Encounters.for_run_event(1,421)
	d.starter_id = "bastion"
	d.player_power_ids = ["dead_centre"]
	d.player_power_ranks = {"dead_centre":3}
	d.player_power_mutations = {"dead_centre":"bulwark"}
	b.begin_run(Starters.build_for("bastion"),d,421)
	b.battle_status = "battle"
	return b

func passive_pressure(b: Node2D, target: Dictionary) -> void:
	b.apply_power_impulse(target,Vector2(0.15,0),b.powers._owned_effect_cause(b.player_entity(),"dead_centre_pull"))

func _run() -> void:
	_test_passive()
	_test_active()
	_test_stale_and_pause()
	print("DEFENCE_PARTICIPATION_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)

func _test_passive() -> void:
	var b: Node2D = make_battle()
	var p: Dictionary = b.player_entity()
	var target: Dictionary = b.entity(2)
	p.rpm = 0.50
	var velocity: Vector2 = target.vel
	passive_pressure(b,target)
	check(target.vel != velocity,"Automatic fortress pressure retains its real physical impulse")
	check(b._progression_contacted.has(2),"Automatic pressure retains kill and XP attribution")
	check(not b.continuous.economy.credits.has(2),"Automatic pressure cannot establish renewable RPM elimination credit with zero controls")
	target.outcome = "impact"
	b.continuous.economy.outcomes()
	check(p.rpm == 0.50,"A passive full-top unit defeat pays no renewable RPM")
	check(b.powers.inverse_mass(p) > 0.0,"Fortress inverse-mass solver remains finite")
	b.free()

func _test_active() -> void:
	for activity: String in ["steering", "brake", "burst"]:
		var b: Node2D = make_battle()
		var p: Dictionary = b.player_entity()
		var target: Dictionary = b.entity(2)
		p.rpm = 0.50
		var direction: Vector2 = Vector2(0.20,0) if activity == "steering" else Vector2.ZERO
		b.continuous.observe_input(0.4,direction,activity == "brake",activity == "burst")
		check(b.continuous.has_recent_control(),"Deliberate "+activity+" qualifies controlled defence")
		passive_pressure(b,target)
		check(b.continuous.economy.credits.has(2),"Active defence keeps full pressure-effect recovery eligibility")
		target.outcome = "impact"
		b.continuous.economy.outcomes()
		check(is_equal_approx(p.rpm,0.545),"Active defence earns the original exact45-milli-reserve elimination payoff")
		b.continuous.economy.outcomes()
		check(is_equal_approx(p.rpm,0.545),"Repeated outcome cannot repay controlled defence")
		b.free()

func _test_stale_and_pause() -> void:
	var b: Node2D = make_battle()
	var p: Dictionary = b.player_entity()
	var target: Dictionary = b.entity(2)
	p.rpm = 0.50
	b.continuous.observe_input(0.4,Vector2(0.20,0))
	passive_pressure(b,target)
	check(b.continuous.economy.credits.has(2),"Initial active impact has credit")
	var original_credit: float = b.continuous.economy.credits[2]
	b.elapsed = 4.0 # Declared unit clock seam: no balance or survival claim.
	passive_pressure(b,target)
	check(b.continuous.economy.credits[2] == original_credit,"Continued automatic pressure cannot refresh activity after controls stop")
	target.outcome = "impact"
	b.continuous.economy.outcomes()
	check(p.rpm == 0.50,"A delayed automatic defeat cannot cash an old controlled window")
	var snapshot: Dictionary = b.continuous.economy.snapshot()
	b.set_paused(true)
	for tick: int in range(240): b.test_step(Battle.FIXED_DT,Vector2.RIGHT,true,true)
	check(b.elapsed == 4.0 and b.continuous.economy.snapshot() == snapshot,"Pause freezes activity windows and cannot earn control or RPM")
	b.free()
