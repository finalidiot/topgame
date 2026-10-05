extends SceneTree
## Controlled centre-start study: real Run director, rivals, collisions and RPM
## costs advance normally. Fixed initial position is setup, never a fake hit,
## recovery or kill. No collection is read or written.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: Array[String] = []
var runs: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL: " + label)
func study(level: int, seed_value: int) -> void:
	var b: Node2D = Battle.new()
	root.add_child(b); b.set_physics_process(false); b.set_process(false)
	var d: Dictionary = Encounters.for_run_event(1, seed_value)
	d.starter_id = "bastion"
	d.player_power_ids = [] if level == 0 else ["dead_centre"]
	d.player_power_ranks = {} if level == 0 else {"dead_centre":level}
	b.begin_run(Starters.build_for("bastion"), d, seed_value)
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	p.pos = Vector2.ZERO; p.vel = Vector2.ZERO
	var max_rpm: float = p.rpm
	var peak_hold: float = 0.0
	for tick: int in range(18000):
		if b.battle_status != "battle": break
		b.test_step(Battle.FIXED_DT, Vector2.ZERO, false, false)
		max_rpm = maxf(max_rpm, float(p.rpm))
		peak_hold = maxf(peak_hold, float(p.get("anchor_maturity", 0.0)))
	var ledger: Dictionary = b.continuous.economy.snapshot()
	var result: Dictionary = {"rank":level,"seed":seed_value,"seconds":b.elapsed,"outcome":str(p.outcome),"rpm":p.rpm,"peak_rpm":max_rpm,"position":{ "x":p.pos.x,"y":p.pos.y },"maturity_peak":peak_hold,"threats_cleared":b.continuous.threat_number-1,"rpm_ledger":ledger}
	runs.append(result)
	check(Vector2(p.pos).is_finite() and Vector2(p.vel).is_finite() and is_finite(float(p.rpm)), "Passive natural pressure remains finite")
	check(max_rpm <= 1.000001 and float(ledger.gains.get("dead_centre", 0.0)) <= b.elapsed * 0.012 + 0.012, "Passive centre reserve and recovery stay bounded under actual foes")
	print("CENTRE_PRESSURE rank=%d seed=%d seconds=%.2f outcome=%s rpm=%.4f threats=%d" % [level,seed_value,b.elapsed,str(p.outcome),float(p.rpm),b.continuous.threat_number-1])
	b.free()
func run() -> void:
	for seed_value: int in [421, 7331]:
		for level: int in [0, 1, 2]: study(level, seed_value)
	print("CENTRE_PRESSURE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify({"label":"Controlled central start; real director, movement, contacts and recovery; no steering or injected results", "seconds_limit":300.0,"checks":checks,"failures":failures,"runs":runs}, "\t"))
	quit(0 if failures.is_empty() else 1)
