extends "res://tests/test_ability_rebalance.gd"
## Unit seams isolate real load/vent rules; these are not survival claims.

func settled(level: int = 3, branch: String = "bulwark") -> Host:
	var h: Host = host("dead_centre", level, branch)
	h.entity(2).pos = Vector2(180, 0)
	for tick: int in range(540): step(h, Vector2.ZERO)
	return h

func load_hit(h: Host, force: float = 140.0) -> void:
	h.runtime.accepted_contact(h.entity(1), h.entity(2), 0.7, Vector2.RIGHT, Vector2.ZERO, Vector2(-2, 0), Vector2(40, 0), force, 40.0)

func _test_quiet_and_inactive() -> void:
	var h: Host = settled()
	var p: Dictionary = h.entity(1)
	var mass: float = h.runtime.inverse_mass(p)
	for tick: int in range(7200): step(h, Vector2.ZERO)
	check(p.anchor_stress == 0.0 and h.runtime.inverse_mass(p) == mass, "A quiet fortress never receives an elapsed-time Stress penalty")
	check(is_equal_approx(1.0 / mass / float(p.mass), 81.0), "Low-load Bulwark retains its full original81-times mass")
	for condition: String in ["unowned", "uncharged", "legacy", "eliminated", "stopped"]:
		var q: Host = settled()
		var f: Dictionary = q.entity(1)
		if condition == "unowned": f.powers = []
		if condition == "uncharged": f.anchor_charge = 0.0
		if condition == "legacy": q.ability_rebalance = false
		if condition == "eliminated": f.outcome = "spin_out"
		if condition == "stopped": q.runtime.finish()
		load_hit(q)
		q.runtime._anchor_stress_gain(f, 0.5, "test_fixture")
		check(float(f.anchor_stress) == 0.0, condition + " cannot earn Anchor Stress")

func _test_load_and_consequence() -> void:
	var h: Host = settled()
	var p: Dictionary = h.entity(1)
	var initial_mass: float = 1.0 / h.runtime.inverse_mass(p)
	var initial_shock: float = h.runtime.incoming_rpm_scale(p)
	load_hit(h)
	check(p.anchor_stress > 0.0 and p.anchor_load > 0.0, "Genuine accepted incoming force loads the anchor despite tiny braced recoil")
	var contact_stress: float = p.anchor_stress
	for tick: int in range(120): step(h, Vector2.ZERO)
	check(p.anchor_stress > contact_stress, "A recently physically loaded connection accumulates sustained-work Stress")
	for tick: int in range(600): step(h, Vector2.ZERO)
	var unloaded: float = p.anchor_stress
	for tick: int in range(600): step(h, Vector2.ZERO)
	check(is_equal_approx(unloaded, p.anchor_stress), "Sustained-work Stress stops when genuine contact load has decayed")
	h.runtime._anchor_stress_gain(p, 1.0, "test_fixture")
	for tick: int in range(90): step(h, Vector2.ZERO)
	check(p.anchor_stress == 1.0 and float(p.anchor_strength) <= 0.151, "Accumulated physical Stress is bounded and visibly weakens the floor connection")
	check(1.0 / h.runtime.inverse_mass(p) < initial_mass * 0.03, "High Stress relinquishes the enormous added anchor mass")
	check(h.runtime.incoming_rpm_scale(p) > initial_shock + 0.25, "High Stress stops most of the perfect incoming shock discount")
	var before_rpm: float = p.rpm
	var before_losses: float = h.losses
	for tick: int in range(60): step(h, Vector2.ZERO)
	check(p.rpm >= before_rpm and h.losses == before_losses, "Stress does not directly invent damage, an RPM loss source or forced death")
	load_hit(h, 270.0)
	check(p.anchor_charge == 0.0, "A real heavy impact can now shear an overloaded Bulwark connection")

func _test_vent() -> void:
	for mode: String in ["stationary", "knockback", "tiny_input", "brake", "active", "outside"]:
		var h: Host = settled()
		var p: Dictionary = h.entity(1)
		h.runtime._anchor_stress_gain(p, 0.8, "test_fixture")
		p.vel = Vector2(60, 0) if mode != "stationary" else Vector2.ZERO
		p.pos = Vector2(95, 0) if mode == "outside" else Vector2.ZERO
		var direction: Vector2 = Vector2.RIGHT * (0.5 if mode in ["active", "outside", "brake"] else 0.20 if mode == "tiny_input" else 0.0)
		for tick: int in range(120): step(h, direction, mode == "brake")
		check(float(p.anchor_stress) < 0.70 if mode in ["active", "outside"] else is_equal_approx(p.anchor_stress, 0.8), mode + " has the correct meaningful release-and-movement vent eligibility")
		if mode == "outside": check(p.anchor_stress > 0.50 and p.anchor_overloaded, "Two seconds outside cannot clear the overload recovery window")

func _test_redline_cost() -> void:
	var a: Host = settled()
	var b: Host = settled()
	var p: Dictionary = b.entity(1)
	p.powers.append("redline"); p.power_ranks.redline = 2
	# Activate the real Burst path, which releases Dead Centre; normal holding
	# then rebuilds the connection during the live overclock window.
	b.runtime.burst_started(p, Vector2.RIGHT, p.rpm)
	for tick: int in range(90): step(b, Vector2.ZERO)
	check(b.runtime.redline_active(p) and p.anchor_charge > 0.95, "Real activation and reacquisition can overlap Redline with a strong anchor")
	var before: float = p.anchor_stress
	var control_before: float = a.entity(1).anchor_stress
	load_hit(a); load_hit(b)
	check(float(p.anchor_stress) - before > (float(a.entity(1).anchor_stress) - control_before) * 2.5, "Actual live Redline multiplies incoming physical load risk")
	check(before > 0.0, "Running anchored overclock has an explicit torque cost")
	var dormant: Host = settled()
	dormant.entity(1).powers.append("redline")
	load_hit(dormant)
	check(is_equal_approx(dormant.entity(1).anchor_stress, a.entity(1).anchor_stress), "Inactive Redline ownership alone adds no physical cost")
	var solo: Host = host("redline", 2)
	solo.runtime.burst_started(solo.entity(1), Vector2.RIGHT, 1.0)
	for tick: int in range(90): step(solo, Vector2.ZERO)
	check(solo.entity(1).anchor_stress == 0.0, "Redline without Dead Centre cannot create phantom anchor Stress")

func _test_paid_synergies() -> void:
	var h: Host = settled()
	var p: Dictionary = h.entity(1)
	p.powers.append("impact_sink"); p.power_ranks.impact_sink = 2
	h.runtime._anchor_stress_gain(p, 0.8, "test_fixture")
	h.runtime.defence.contact(p, h.entity(2), 1.0, Vector2(-100, 0), 160.0)
	var stored: float = p.sink_charge
	step(h, Vector2.ZERO, true)
	check(stored > 15.0 and p.sink_charge == 0.0 and p.anchor_stress < 0.8, "A fresh Brake empties genuine stored force to relieve Stress")
	var after_vent: float = p.anchor_stress
	for tick: int in range(120): step(h, Vector2.ZERO, true)
	check(is_equal_approx(p.anchor_stress, after_vent), "An empty or held Sink Brake cannot repeatedly refund Stress")
	var ex: Host = settled()
	var f: Dictionary = ex.entity(1)
	f.powers.append("anchor_exchange"); f.power_ranks.anchor_exchange = 2
	ex.runtime._anchor_stress_gain(f, 0.8, "test_fixture")
	for tick: int in range(30): step(ex, Vector2.ZERO, true)
	var spent: float = ex.losses
	step(ex, Vector2.RIGHT * 0.4, false)
	check(spent > 0.0 and f.anchor_stress <= 0.701, "A paid aimed Exchange release helps manage Dead Centre Stress")
	var no_aim: Host = settled()
	var n: Dictionary = no_aim.entity(1)
	n.powers.append("anchor_exchange"); n.power_ranks.anchor_exchange = 2
	no_aim.runtime._anchor_stress_gain(n, 0.8, "test_fixture")
	for tick: int in range(30): step(no_aim, Vector2.ZERO, true)
	step(no_aim, Vector2.ZERO, false)
	check(is_equal_approx(n.anchor_stress, 0.8), "Uncontrolled brace release cannot autonomously refund Stress")
	var counter: Host = settled(3, "counterweight")
	var c: Dictionary = counter.entity(1)
	load_hit(counter)
	c.anchor_stress = 0.80 # Explicit unit thermal seam; no survival claim.
	step(counter, Vector2.RIGHT * 0.5)
	counter.runtime.burst_started(c, Vector2.RIGHT, c.rpm)
	check(c.stored_force == 0.0 and c.anchor_stress < 0.80, "A controlled Counterweight discharge turns real stored force into Stress relief")

func _test_public_state() -> void:
	var h: Host = settled()
	var p: Dictionary = h.entity(1)
	p.powers.append("orbit_drive"); p.powers.append("impact_sink")
	p.power_ranks.impact_sink = 2
	p.orbit_charge = 0.63; p.drift_active = true
	p.sink_charge = 37.5; p.sink_capacity = 150.0
	var result: Dictionary = h.runtime.public_state(p)
	check(result.orbit.owned and result.orbit.drive == 0.63 and result.orbit.drifting, "Orbit Drive meter exposes actual charge and drift state")
	check(result.sink.owned and result.sink.stored == 37.5 and result.sink.ratio == 0.25, "Impact Sink meter exposes stored force against authoritative capacity")
	check(result.anchor.owned and result.anchor.charge == 1.0 and result.anchor.stress == 0.0 and result.anchor.strength == 1.0, "Anchor meter separates engagement, Stress and effective connection")
	check(not result.redline.active and result.redline.remaining == 0.0, "Dormant overdrive meter does not invent active state")

func _run() -> void:
	_test_quiet_and_inactive()
	_test_load_and_consequence()
	_test_vent()
	_test_redline_cost()
	_test_paid_synergies()
	_test_public_state()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify({"checks":checks, "failures":failures, "measurements":measurements}, "\t"))
	print("ANCHOR_STRESS_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
