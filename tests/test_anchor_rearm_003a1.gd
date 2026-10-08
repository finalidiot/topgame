extends "res://tests/test_anchor_stress.gd"
## Explicit semantic thermal seams; solver-backed timing is separate evidence.
const Battle = preload("res://scripts/battle.gd")

func _test_reserve_before_position() -> void:
	for configuration: Dictionary in [{"rank":1,"branch":"","old":0.64,"now":0.82}, {"rank":2,"branch":"","old":0.54,"now":0.76}, {"rank":3,"branch":"bulwark","old":0.45,"now":0.72}]:
		var h: Host = settled(configuration.rank, configuration.branch)
		var p: Dictionary = h.entity(1)
		check(is_equal_approx(h.runtime.incoming_rpm_scale(p), configuration.now), "A mature low-stress brace retains only modest reserve protection: " + str(configuration.rank))
		check(is_equal_approx(h.runtime.incoming_wobble_scale(p), configuration.old), "The accepted low-stress stability discount is preserved: " + str(configuration.rank))
		var initial_mass: float = 1.0 / h.runtime.inverse_mass(p)
		for stress: float in [0.15, 0.30, 0.45, 0.60, 0.79]:
			p.anchor_stress = stress
			var loss_scale: float = h.runtime.incoming_rpm_scale(p)
			check(loss_scale >= configuration.now and loss_scale <= 1.0, "Stress never strengthens reserve protection")
			if stress <= 0.35: check(h.runtime.anchor_efficiency(p) == 1.0 and 1.0 / h.runtime.inverse_mass(p) == initial_mass, "Low-stress positional coefficients remain exact")
			if stress == 0.60:
				check(loss_scale == 1.0 and h.runtime.anchor_efficiency(p) > 0.67, "RPM protection is exhausted while a substantial positional brace remains")
		p.anchor_stress = 0.0
		h.runtime._anchor_stress_gain(p, 0.80, "thermal_test_seam")
		check(p.anchor_overloaded and h.runtime.incoming_rpm_scale(p) == 1.0, "Overload latches and cannot shield reserve")
		h.runtime.vent_anchor_stress(p, 1.0, "paid_vent_test_seam")
		for tick: int in range(180): step(h, Vector2.ZERO)
		check(p.anchor_overloaded and h.runtime.anchor_efficiency(p) <= 0.35 and p.anchor_recovery_rate == 0.0, "Even a paid full vent cannot skip the released movement window")
		h.runtime.finish()
		step(h, Vector2.RIGHT)
		check(p.anchor_overloaded, "Stopped presentation cannot clear the recovery latch")

func _test_hysteresis_and_time() -> void:
	for mode: String in ["outside", "inner", "paid", "pixel_idle", "knockback", "brake", "burst", "micro_input"]:
		var h: Host = settled()
		var p: Dictionary = h.entity(1)
		h.runtime._anchor_stress_gain(p, 1.0, "thermal_test_seam")
		p.pos = Vector2(95,0) if mode != "inner" else Vector2(45,0)
		p.vel = Vector2.ZERO if mode == "pixel_idle" else Vector2(60,0)
		if mode == "paid": h.runtime.vent_anchor_stress(p, 1.0, "paid_vent_test_seam")
		var steering: Vector2 = Vector2.RIGHT * (0.20 if mode == "micro_input" else 0.0 if mode in ["pixel_idle", "knockback"] else 0.5)
		if mode == "burst": p.burst_time = 9.0
		var first_safe: float = -1.0
		for tick: int in range(600):
			step(h, steering, mode == "brake")
			if not p.anchor_overloaded and first_safe < 0.0: first_safe = float(tick+1)/60.0
			if tick == 29: check(p.anchor_overloaded and h.runtime.anchor_efficiency(p) < 1.0, "Half a second cannot restore a full socket: " + mode)
			if tick == 269 and mode in ["outside", "inner", "paid"]: check(p.anchor_overloaded, "Four and a half seconds is below the minimum meaningful recovery window: " + mode)
		if mode in ["outside", "inner", "paid"]:
			check(first_safe >= 5.0 and first_safe < 9.0 and float(p.anchor_stress) <= Runtime.ANCHOR_STRESS_REENGAGE, "Genuine release needs enough movement AND the safe Stress threshold: " + mode)
			p.pos = Vector2.ZERO; p.vel = Vector2.ZERO
			for tick: int in range(60): step(h, Vector2.ZERO)
			check(p.anchor_charge == 1.0 and h.runtime.anchor_efficiency(p) == 1.0, "A safe recovery can reclaim the original full fortress: " + mode)
		else: check(first_safe < 0.0 and p.anchor_overloaded, "Passive/blocked movement cannot recharge the socket: " + mode)
		measurements[mode] = {"first_safe_seconds":first_safe,"final_stress":p.anchor_stress,"unit_seam":true}
	var near: Host = settled()
	near.entity(1).anchor_stress = 0.79
	near.entity(1).vel = Vector2(60,0)
	for tick: int in range(30): step(near, Vector2.RIGHT*0.5)
	near.entity(1).vel = Vector2.ZERO
	for tick: int in range(60): step(near, Vector2.ZERO)
	check(near.runtime.anchor_efficiency(near.entity(1)) < 0.50, "A just-below-overload half-second excursion cannot regain full defence")

func _test_frozen_clock_and_coarse_frame() -> void:
	var b: Node2D = Battle.new(); root.add_child(b); b.set_physics_process(false)
	b.begin({"blade":"guard","ratchet":"low","bit":"ball"},{"blade":"balance","ratchet":"mid","bit":"ball"},1,421)
	b.ability_rebalance = true; b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	p.powers = ["dead_centre"]; p.power_ranks = {"dead_centre":2}; p.anchor_charge = 1.0
	b.powers._anchor_stress_gain(p,1.0,"thermal_test_seam")
	p.pos = Vector2(90,0); p.vel = Vector2(60,0)
	var stress: float = p.anchor_stress
	b.set_paused(true)
	for tick: int in range(20): b.test_step(1.0,Vector2.RIGHT*0.5)
	check(p.anchor_stress == stress and b.powers._state(p).anchor_release_seconds == 0.0, "Pause cannot count wall time toward safe anchoring")
	b.set_paused(false); b.begin_reentry()
	for tick: int in range(30): b.test_step(Battle.FIXED_DT,Vector2.RIGHT*0.5)
	check(p.anchor_stress == stress and b.powers._state(p).anchor_release_seconds == 0.0, "READY/re-entry cannot vent or recharge while the physical clock is frozen")
	b.battle_status = "battle"
	b.test_step(10.0,Vector2.RIGHT*0.5)
	check(p.anchor_overloaded and float(b.powers._state(p).anchor_release_seconds) <= 0.25, "A coarse frame keeps canonical bounded fixed ticks instead of skipping the five-second movement window")
	b.free()

func _run() -> void:
	_test_quiet_and_inactive()
	_test_load_and_consequence()
	_test_vent()
	_test_redline_cost()
	_test_paid_synergies()
	_test_public_state()
	_test_reserve_before_position()
	_test_hysteresis_and_time()
	_test_frozen_clock_and_coarse_frame()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements},"\t"))
	print("ANCHOR_REARM_003A1_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
