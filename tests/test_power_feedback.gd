extends "res://tests/test_ability_rebalance.gd"
## Human feedback acceptance: actual bounded reserve, grounded centre control,
## and lasting paid routes. Semantic setups are labelled test fixtures; the
## ledger check below uses the real continuous Run economy and movement.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")

func _run() -> void:
	_test_centre_hold()
	_test_centre_failures()
	_test_centre_rearm()
	_test_pull()
	_test_route_persistence()
	_test_actual_ledger()
	print("POWER_FEEDBACK_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}, "\t"))
	quit(0 if failures.is_empty() else 1)

func _test_centre_hold() -> void:
	for level: int in [1, 2, 3]:
		var branch: String = "bulwark" if level == 3 else ""
		var h: Host = host("dead_centre", level, branch)
		var p: Dictionary = h.entity(1)
		p.rpm = 0.15; p.wobble = 0.55
		h.entity(2).pos = Vector2(180, 0)
		for tick: int in range(120): step(h, Vector2.ZERO)
		var early_rate: float = float(p.anchor_recovery_rate)
		var early_defence: float = h.runtime.incoming_rpm_scale(p)
		for tick: int in range(420): step(h, Vector2.ZERO)
		check(is_equal_approx(p.anchor_charge, 1.0) and p.anchor_maturity >= 0.999, "Rank %d hold matures only after sustained actual charge" % level)
		check(p.rpm > 0.18 and float(p.anchor_recovery_rate) > early_rate, "Rank %d sustained central lock increases actual reserve and recovery rate" % level)
		check(h.runtime.incoming_rpm_scale(p) < early_defence and h.runtime.incoming_rpm_scale(p) >= 0.45, "Rank %d maturing brace strengthens bounded shock defence" % level)
		check(h.runtime.inverse_mass(p) < 1.0 / float(p.mass) * 0.18 and p.wobble < 0.05, "Rank %d physical brace resists displacement and stabilises wobble" % level)
		check(is_equal_approx(p.rpm, 0.15 + h.gains - h.losses), "Rank %d recovery closes actual reserve accounting" % level)
		var ceiling: float = 0.78 if level == 1 else 0.86 if level == 2 else 0.90
		p.rpm = ceiling - 0.001
		for tick: int in range(1800): step(h, Vector2.ZERO)
		check(p.rpm <= ceiling + 0.000001 and p.rpm < 1.0, "Rank %d positional recovery cannot exceed its below-full ceiling" % level)
		measurements["centre_rank_%d" % level] = {"early_rate":early_rate,"settled_rate":0.009 if level == 1 else 0.012,"ceiling":ceiling,"shock_scale":h.runtime.incoming_rpm_scale(p)}
		var before: float = p.rpm
		h.runtime.burst_started(p, Vector2.RIGHT, p.rpm)
		check(p.anchor_charge == 0.0 and p.anchor_hold_seconds == 0.0 and p.anchor_pull_radius == 0.0 and p.rpm == before, "Burst releases floor lock and all matured sustain state")

func _test_centre_failures() -> void:
	var h: Host = host("dead_centre")
	var p: Dictionary = h.entity(1)
	p.rpm = 0.3; p.pos = Vector2(90, 0)
	for tick: int in range(540): step(h, Vector2.ZERO)
	check(p.anchor_charge > 0.99 and p.rpm == 0.3 and not bool(p.anchor_central_hold), "Outer defence can brace but cannot earn central RPM or pull")
	check(p.anchor_pull_strength == 0.0, "No inward field appears from an off-centre hold")
	p.pos = Vector2(145, 0)
	for tick: int in range(120): step(h, Vector2.ZERO)
	check(p.anchor_charge == 0.0 and h.runtime.incoming_rpm_scale(p) == 1.0, "Wall camping loses every brace benefit")
	p.pos = Vector2.ZERO
	for tick: int in range(540): step(h, Vector2.ZERO)
	var gained: float = h.gains
	step(h, Vector2.RIGHT)
	check(h.gains == gained and p.anchor_recovery_rate == 0.0 and p.anchor_pull_strength == 0.0, "Leaving the controlled hold immediately stops recovery and attraction")
	for tick: int in range(120): step(h, Vector2.RIGHT)
	check(p.anchor_charge == 0.0 and p.anchor_maturity == 0.0, "Sustained aggressive motion releases both charge and accumulated hold")
	for tick: int in range(540): step(h, Vector2.ZERO)
	h.runtime.accepted_contact(p, h.entity(2), 1.0, Vector2.RIGHT, p.pos, Vector2(-260, 0), Vector2(260, 0), 260.0, 260.0)
	check(p.anchor_charge == 0.0 and p.anchor_maturity == 0.0, "A genuinely extreme force still tears out the rank I floor lock")
	p.rpm = 0.03; p.vel = Vector2.ZERO
	for tick: int in range(540): step(h, Vector2.ZERO)
	check(p.rpm == 0.03 and p.anchor_recovery_rate == 0.0, "Dead Centre cannot revive a top below spin-out reserve")
	p.rpm = 0.25; p.outcome = "spin_out"
	for tick: int in range(120): step(h, Vector2.ZERO)
	check(p.rpm == 0.25 and p.anchor_recovery_rate == 0.0, "Confirmed elimination cannot receive positional recovery")
	var neutral: Host = host("")
	check(neutral.runtime.incoming_rpm_scale(neutral.entity(1)) == 1.0, "Unowned power leaves collision losses exactly neutral")

func _test_pull() -> void:
	var h: Host = host("dead_centre", 2)
	var p: Dictionary = h.entity(1)
	h.entity(2).pos = Vector2(70, 0)
	h.fighters.append(fighter(3, "", 1, "", Vector2(155, 0)))
	h.fighters.append(fighter(4, "", 1, "", Vector2(70, 0)))
	h.entity(4).team_id = "player"
	h.fighters.append(fighter(5, "", 1, "", Vector2(70, 0)))
	h.entity(5).enemy_kind = "boss"
	for tick: int in range(540):
		step(h, Vector2.ZERO)
		h.runtime.flush_contact_powers()
	check(h.entity(2).vel.x < -20.0 and p.anchor_pull_radius == 124.0, "Settled central gravity physically pulls a nearby hostile toward the socket")
	check(h.entity(3).vel == Vector2.ZERO and h.entity(4).vel == Vector2.ZERO, "Pull respects finite range and team ownership")
	check(absf(h.entity(5).vel.x) < absf(h.entity(2).vel.x) * 0.5, "Boss receives a reduced bend rather than losing movement authority")
	h.entity(2).vel = Vector2(-120, 0)
	var impulse_count: int = h.impulses.size()
	step(h, Vector2.ZERO); h.runtime.flush_contact_powers()
	check(h.entity(2).vel == Vector2(-120, 0) and h.impulses.size() <= impulse_count + 1, "Already fast inward approaches receive no stacked attraction acceleration")
	var before: Vector2 = h.entity(5).vel
	step(h, Vector2.ZERO, false, 10.0); h.runtime.flush_contact_powers()
	check(Vector2(h.entity(5).vel).distance_to(before) <= 4.6, "Long update intervals retain a strict bounded pull offer")
	h.runtime.burst_started(p, Vector2.RIGHT, p.rpm)
	before = h.entity(5).vel
	step(h, Vector2.RIGHT); h.runtime.flush_contact_powers()
	check(h.entity(5).vel == before and p.anchor_pull_strength == 0.0, "Releasing the socket immediately stops the real force")
	measurements["pull"] = {"rank2_radius":124.0,"rank2_acceleration":46.0,"inward_speed_ceiling":120.0,"boss_factor":0.45,"target_budget":16}

func _test_centre_rearm() -> void:
	for level: int in [1, 2]:
		var h: Host = host("dead_centre", level)
		var p: Dictionary = h.entity(1)
		p.rpm = 0.15; h.entity(2).pos = Vector2(180, 0)
		for tick: int in range(7200): step(h, Vector2.ZERO)
		var capacity: float = 0.20 if level == 1 else 0.28
		check(is_equal_approx(h.gains, capacity) and p.anchor_recovery_remaining <= 0.000001, "Rank %d indefinite single hold cannot exceed its real recovery quota" % level)
		check(p.anchor_recovery_rate == 0.0 and p.anchor_central_hold and p.anchor_pull_radius > 0.0, "Spent recovery leaves physical defence and attraction, not a fake gain indicator")
		var before: float = h.gains
		h.runtime.accepted_contact(p, h.entity(2), 1.0, Vector2.RIGHT, p.pos, Vector2(-350, 0), Vector2(350, 0), 350.0, 350.0)
		p.pos = Vector2(90, 0); p.vel = Vector2(60, 0)
		for tick: int in range(180): step(h, Vector2.ZERO)
		p.pos = Vector2.ZERO; p.vel = Vector2.ZERO
		for tick: int in range(540): step(h, Vector2.ZERO)
		check(h.gains == before and p.anchor_recovery_remaining <= 0.000001, "Incoming knockback, charge break and automatic return cannot renew recovery")
		h.runtime.burst_started(p, Vector2.RIGHT, p.rpm)
		for tick: int in range(540): step(h, Vector2.ZERO)
		check(h.gains == before, "Repeated paid bursts cannot reset the positional recovery quota")
		p.pos = Vector2(90, 0); p.vel = Vector2(60, 0)
		for tick: int in range(45): step(h, Vector2.RIGHT)
		check(p.anchor_recovery_remaining <= 0.000001 and p.anchor_rearm_progress > 0.0 and p.anchor_rearm_progress < 1.0, "Brief steering outside centre shows rearming progress without premature refill")
		for tick: int in range(340): step(h, Vector2.RIGHT)
		check(is_equal_approx(p.anchor_recovery_remaining, capacity), "A deliberate sustained outside rotation reloads exactly one quota")
		p.pos = Vector2.ZERO; p.vel = Vector2.ZERO
		for tick: int in range(540): step(h, Vector2.ZERO)
		check(h.gains > before and h.gains <= capacity * 2.0 + 0.000001, "Returning to the centre after a real rotation earns bounded recovery again")
		measurements["quota_rank_%d" % level] = {"capacity":capacity,"rearm_radius":Runtime.ANCHOR_REARM_RADIUS,"rearm_seconds":Runtime.ANCHOR_REARM_SECONDS,"final_gained":h.gains}

func _test_route_persistence() -> void:
	for level: int in [1, 2]:
		var h: Host = host("afterimage", level)
		var p: Dictionary = h.entity(1)
		p.pos = Vector2(40, 0); p.vel = Vector2(150, 0)
		h.entity(2).pos = Vector2(180, 0)
		h.runtime.after_movement()
		var paid: float = h.losses
		check(h.runtime.traces.size() == 1 and paid > 0.0, "Rank %d visible route is created by real paid movement" % level)
		h.runtime.begin_tick(3.0)
		check(h.runtime.traces.size() == 1 and h.runtime.traces[0].life > 0.0, "Rank %d physical route remains usable after three seconds" % level)
		p.vel = Vector2.ZERO
		h.entity(2).pos = Vector2(20, 8)
		h.runtime.after_movement(); h.runtime.flush_contact_powers()
		check(h.entity(2).vel.y > 0.0 and h.losses == paid, "A delayed crossing hits the same paid route without an unpaid redraw")
		h.runtime.begin_tick(1.7)
		check(h.runtime.traces.is_empty(), "Expired paid routes remove physical pressure and presentation together")
		var retained: int = 0
		p.vel = Vector2(150, 0)
		for tick: int in range(1200):
			h.runtime.begin_tick(1.0 / 60.0)
			p.pos = Vector2(float(tick % 200) * 2.5, float(tick / 200) * 20.0)
			h.runtime.after_movement()
			retained = maxi(retained, h.runtime.traces.size())
			check(h.runtime.traces.size() <= (Runtime.MODERN_TRACE_LIMIT if level == 1 else Runtime.MODERN_DEEP_TRACE_LIMIT), "Extended routes keep their explicit rank memory budget")
		measurements["route_rank_%d" % level] = {"life":3.4 if level == 1 else 4.6,"max_retained":retained,"paid_reserve":h.losses}

func _test_actual_ledger() -> void:
	var b: Node2D = Battle.new()
	root.add_child(b); b.set_physics_process(false); b.set_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1, 421)
	descriptor.starter_id = "bastion"; descriptor.player_power_ids = ["dead_centre"]
	descriptor.player_power_ranks = {"dead_centre":2}
	b.begin_run(Starters.build_for("bastion"), descriptor, 421); b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	p.pos = Vector2.ZERO; p.vel = Vector2.ZERO; p.rpm = 0.40; p.energy = 0.40
	b.entity(2).pos = Vector2(180, 0)
	for tick: int in range(1800):
		b.elapsed += Battle.FIXED_DT
		b.continuous.economy.begin_tick(Battle.FIXED_DT, Vector2.ZERO)
		b.powers.begin_tick(Battle.FIXED_DT)
		b._update_fighter(p, Vector2.ZERO, false, Battle.FIXED_DT)
		b.powers.flush_contact_powers()
	var ledger: Dictionary = b.continuous.economy.snapshot()
	var losses: float = 0.0
	for value: float in ledger.losses.values(): losses += value
	check(float(ledger.gains.get("dead_centre", 0.0)) > 0.25 and p.rpm > 0.60, "Real continuous economy records substantial source-named centre recovery")
	check(absf(float(p.rpm) - (0.40 + float(ledger.total_recovered) - losses)) < 0.00001, "Real centre recovery and unchanged running costs close the RPM ledger")
	check(float(ledger.gains.get("dead_centre", 0.0)) <= 30.0 * 0.012 + 0.012, "Real gain rate remains bounded over sustained time")
	check(p.rpm <= 0.86 and b.continuous.economy.tokens >= 0.0, "Recovery respects both rank ceiling and existing shared gain budget")
	b.set_paused(true)
	var frozen: Dictionary = p.duplicate(true)
	var frozen_ledger: Dictionary = b.continuous.economy.snapshot()
	for tick: int in range(180): b.test_step(Battle.FIXED_DT, Vector2.ZERO)
	check(p == frozen and b.continuous.economy.snapshot() == frozen_ledger, "Draft pause freezes hold, pull, reserve and source ledger")
	measurements["actual_run_ledger"] = ledger
	b.free()
