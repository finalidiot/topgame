extends SceneTree
## New continuous mechanics and genuine geometry contracts. Legacy suites keep
## their accepted standalone/duel behavior; this semantic host explicitly opts in.
const Runtime = preload("res://scripts/power_runtime.gd")
var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {}

class Host extends RefCounted:
	var ability_rebalance: bool = true
	var fighters: Array[Dictionary] = []
	var impulses: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	var gains: float = 0.0
	var losses: float = 0.0
	var runtime: RefCounted
	func _ordered_fighters() -> Array[Dictionary]:
		var ordered: Array[Dictionary] = fighters.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.entity_id) < int(b.entity_id))
		return ordered
	func entity(id: int) -> Dictionary:
		for fighter: Dictionary in fighters:
			if int(fighter.entity_id) == id: return fighter
		return {}
	func spend_rpm(fighter: Dictionary, amount: float, _source: String) -> void:
		var actual: float = minf(float(fighter.rpm), maxf(0.0, amount))
		fighter.rpm -= actual
		fighter.energy = fighter.rpm
		if int(fighter.entity_id) == 1: losses += actual
	func gain_rpm(fighter: Dictionary, amount: float, _source: String, _small: bool = false) -> float:
		if not str(fighter.outcome).is_empty(): return 0.0
		var actual: float = minf(maxf(0.0, amount), maxf(0.0, float(runtime.rpm_cap(fighter)) - float(fighter.rpm)))
		fighter.rpm += actual
		fighter.energy = fighter.rpm
		if int(fighter.entity_id) == 1: gains += actual
		return actual
	func apply_power_impulse(target: Dictionary, velocity: Vector2, cause: Dictionary) -> void:
		target.vel = Vector2(target.vel) + velocity
		impulses.append({"target": target.entity_id, "velocity": velocity, "cause": cause.duplicate(true)})
	func add_power_fx(kind: String, position: Vector2, direction: Vector2, strength: float) -> void:
		effects.append({"kind": kind, "pos": position, "direction": direction, "strength": strength})

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: " + label)

func fighter(id: int, power: String = "", level: int = 1, branch: String = "", position: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"entity_id": id, "owner_id": "player" if id == 1 else "rival", "team_id": "player" if id == 1 else "hostile", "combatant_type": "full_top", "pos": position, "vel": Vector2.ZERO, "radius": 12.0, "mass": 8.0, "rpm": 1.0, "energy": 1.0, "wobble": 0.0, "outcome": "", "powers": [] if power.is_empty() else [power], "power_ranks": {} if power.is_empty() else {power: level}, "power_mutations": {} if branch.is_empty() else {power: branch}, "burst_time": 0.0, "height": 0.0, "height_vel": 0.0}

func host(power: String, level: int = 1, branch: String = "", position: Vector2 = Vector2.ZERO) -> Host:
	var result: Host = Host.new()
	result.fighters = [fighter(1, power, level, branch, position), fighter(2, "", 1, "", Vector2(20, 0))]
	result.runtime = Runtime.new()
	result.runtime.setup(result)
	return result

func step(h: Host, direction: Vector2, braking: bool = false, dt: float = 1.0 / 60.0) -> Dictionary:
	h.runtime.begin_tick(dt)
	return h.runtime.movement_control(h.entity(1), direction, braking, dt)

func contact(h: Host, severity: float = 0.7) -> void:
	h.runtime.accepted_contact(h.entity(1), h.entity(2), severity, Vector2.RIGHT, Vector2(10, 0), Vector2(-100, 0), Vector2(100, 0))
	h.runtime.flush_contact_powers()

func _run() -> void:
	_test_redline_creation()
	_test_heat_and_failure()
	_test_runaway()
	_test_breakneck()
	_test_clutch()
	_test_rank_routes()
	_test_support_depth()
	_test_slipstream()
	_test_ghost()
	_test_ghost_abuse()
	print("ABILITY_REBALANCE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}, "\t"))
	quit(0 if failures.is_empty() else 1)

func _test_redline_creation() -> void:
	for level: int in [1, 2]:
		var h: Host = host("redline", level)
		var p: Dictionary = h.entity(1)
		check(h.runtime.rpm_cap(p) == 1.0, "Unactivated Redline cannot hold overcap")
		h.runtime.burst_started(p, Vector2.RIGHT, 1.0)
		var before: float = p.rpm
		p.vel = Vector2(200, 0)
		for tick: int in range(180): step(h, Vector2.RIGHT)
		check(p.rpm > 1.0 and p.rpm > before, "Rank %d actively creates real overcap" % level)
		check(p.rpm <= h.runtime.rpm_cap(p) and h.runtime.effective_rpm(p) == p.rpm, "Real reserve and attack output share the same bounded cap")
		check(is_equal_approx(p.rpm, 1.0 + h.gains - h.losses), "Actual overcap reserve closes the RPM ledger")
		check(h.runtime.diagnostics(p).max_overcap > 0.0 and h.runtime.diagnostics(p).overcap_seconds > 0.0, "Telemetry measures created overcap time and peak")
		h.runtime._gain(p, 10.0, "redline_contact")
		check(is_equal_approx(p.rpm, 1.12 if level == 1 else 1.18), "Rank-specific cap clamps arbitrary large valid gains")
		h.runtime.begin_tick(0.3)
		check(p.rpm <= 1.0 and h.runtime.rpm_cap(p) == 1.0, "Expiry vents real excess through spending and restores ordinary cap")
		check(is_equal_approx(p.rpm, 1.0 + h.gains - h.losses), "Expiry vent also closes accounting")
		measurements["redline_rank_%d" % level] = h.runtime.diagnostics(p)
	for condition: String in ["idle", "coast", "brake", "edge"]:
		var h: Host = host("redline", 2)
		var p: Dictionary = h.entity(1)
		h.runtime.burst_started(p, Vector2.RIGHT, 1.0)
		p.vel = Vector2.ZERO if condition == "idle" else Vector2(200, 0)
		if condition == "edge": p.pos = Vector2(180, 0)
		for tick: int in range(180): step(h, Vector2.ZERO if condition in ["idle", "coast"] else Vector2.RIGHT, condition == "brake")
		check(h.gains == 0.0 and p.rpm < 1.0, condition + " cannot generate overcap")
	var low: Host = host("redline")
	low.entity(1).rpm = 0.20
	low.runtime.burst_started(low.entity(1), Vector2.RIGHT, 0.20)
	check(low.runtime.redline_active(low.entity(1)), "Redline helps create its state without already requiring high reserve")

func _test_heat_and_failure() -> void:
	var h: Host = host("redline", 2)
	var p: Dictionary = h.entity(1)
	h.runtime.burst_started(p, Vector2.RIGHT, 1.0)
	p.vel = Vector2(200, 0)
	var cold: Dictionary = step(h, Vector2.UP)
	for tick: int in range(120): step(h, Vector2.RIGHT)
	var heat: float = p.redline_heat
	var hot: Dictionary = step(h, Vector2.UP)
	check(heat > 0.30 and hot.braking_efficiency < cold.braking_efficiency and hot.recovery < cold.recovery, "Heat visibly worsens braking and stability recovery")
	check(Vector2(hot.direction).distance_to(Vector2.UP) > Vector2(cold.direction).distance_to(Vector2.UP), "Hot overclock delays trajectory correction")
	h.runtime.begin_tick(2.0)
	check(p.redline_heat < heat, "Heat cools after aggression stops")
	var fresh: Host = host("redline", 2)
	fresh.runtime.burst_started(fresh.entity(1), Vector2.RIGHT, 1.0)
	fresh.runtime.eliminated(fresh.entity(1), "ring_out")
	fresh.runtime.eliminated(fresh.entity(1), "ring_out")
	check(fresh.runtime.diagnostics(fresh.entity(1)).ring_outs_active == 1, "Unsafe Redline ring-out is observable")
	var afk: Host = host("redline", 3, "runaway")
	afk.runtime.burst_started(afk.entity(1), Vector2.RIGHT, 1.0)
	afk.entity(1).rpm = 0.5
	contact(afk)
	check(afk.gains == 0.0, "Passive collisions cannot feed Runaway")

func _test_runaway() -> void:
	var h: Host = host("redline", 3, "runaway")
	var p: Dictionary = h.entity(1)
	h.runtime.burst_started(p, Vector2.RIGHT, 1.0)
	p.vel = Vector2(210, 0)
	for hit: int in range(10):
		for tick: int in range(66): step(h, Vector2.RIGHT)
		contact(h)
		check(p.redline_time <= 3.20001 and h.runtime._state(p).redline_motion_left <= Runtime.REDLINE_MOTION_QUOTA, "Runaway sustain timer and restored quota remain bounded")
	check(h.runtime.redline_active(p) and p.rpm > 1.0 and p.redline_heat > 0.8, "Repeated meaningful aggression sustains real overclock and escalating heat")
	check(p.rpm <= 1.24, "Runaway stronger overcap retains a hard cap")
	var reserve: float = p.rpm
	var events: int = h.runtime.counters.runaway_hit
	contact(h)
	check(p.rpm == reserve and h.runtime.counters.runaway_hit == events, "Runaway contact cooldown prevents same-frame refunds")
	h.runtime.begin_tick(3.3)
	check(not h.runtime.redline_active(p) and p.rpm <= 1.0, "Missing continued aggression ends the nightmare")
	measurements.runaway = h.runtime.diagnostics(p)

func _test_breakneck() -> void:
	for hit: bool in [true, false]:
		var h: Host = host("redline", 3, "breakneck")
		var p: Dictionary = h.entity(1)
		h.runtime.burst_started(p, Vector2.RIGHT, 1.0)
		check(p.redline_commit_time == 0.0 and h.runtime.attack_multiplier(p) < 2.0, "Breakneck begins with setup rather than a free strike")
		p.vel = Vector2(210, 0)
		for tick: int in range(245): step(h, Vector2.RIGHT)
		var before: float = p.rpm
		h.runtime.burst_started(p, Vector2.RIGHT, before)
		check(p.redline_commit_time > 0.0 and p.rpm <= before - 0.079 and h.runtime.attack_multiplier(p) > 2.0, "A second committed Burst consumes built spin and unlocks one strike")
		var motion: Dictionary = step(h, Vector2.LEFT, true)
		check(not motion.braking and Vector2(motion.direction).dot(Vector2.RIGHT) > 0.98, "Breakneck locks direction and cannot brake out of the choice")
		var wobble: float = p.wobble
		if hit:
			contact(h)
			check(h.entity(2).vel.x >= 75.0 and int(h.runtime.counters.get("breakneck_impact", 0)) == 1, "Committed impact transfers physical force once")
		else: h.runtime.begin_tick(0.5)
		check(not h.runtime.redline_active(p) and p.wobble >= wobble + 0.27 and p.burst_time == 0.0, "Hit and miss both impose substantial recovery consequences")
		check(h.runtime.diagnostics(p).failed_commitments == (0 if hit else 1), "Missed commitment is measured independently of hit")
		check(is_equal_approx(p.rpm, 1.0 + h.gains - h.losses), "Breakneck setup, strike cost and aftermath close accounting")

func _test_clutch() -> void:
	var h: Host = host("clutch", 2)
	var p: Dictionary = h.entity(1)
	p.rpm = 0.6
	h.runtime.recover()
	check(not p.clutch_active, "Clutch ignores safe spin")
	p.rpm = 0.15
	p.wobble = 0.80
	p.vel = Vector2(80, 0)
	var identity: Dictionary = p
	h.runtime.recover()
	check(p.clutch_active and p.rpm == 0.15 and p.wobble == 0.80, "Danger activation gives no refill or wobble reset")
	check(is_same(identity, h.entity(1)) and h.fighters.size() == 2 and p.pos == Vector2.ZERO, "Comeback retains exact player and arena dictionaries")
	var motion: Dictionary = step(h, Vector2(0.5, 0))
	check(motion.drain < 0.60 and motion.recovery > 1.0, "Controlled low-spin movement improves efficiency while instability persists")
	contact(h)
	check(p.rpm > 0.15 and p.rpm < 0.22 and p.wobble >= 0.75, "Meaningful contact earns bounded recovery without resolving all danger")
	var reserve: float = p.rpm
	contact(h)
	check(p.rpm == reserve, "Same contact cannot farm Clutch repeatedly")
	h.runtime.begin_tick(8.1)
	h.runtime.recover()
	check(not p.clutch_active and int(h.runtime.counters.clutch_activate) == 1, "Unrecovered danger cannot repeatedly reactivate Clutch")
	p.rpm = 0.04
	h.runtime.recover()
	check(p.rpm == 0.04, "Clutch never rescues an actual spin-out reserve")
	p.rpm = 0.01
	p.outcome = "ring_out"
	h.runtime.recover()
	contact(h)
	check(p.rpm == 0.01 and p.outcome == "ring_out", "Confirmed defeat cannot be revived by Clutch")
	var earned: Host = host("clutch", 2)
	var catch_top: Dictionary = earned.entity(1)
	catch_top.rpm = 0.265
	catch_top.vel = Vector2(80, 0)
	earned.runtime.recover()
	step(earned, Vector2(0.5, 0))
	# The real battle pays ordinary reclamation before this semantic hook.
	earned.gain_rpm(catch_top, 0.095, "combat_reclamation")
	contact(earned)
	check(catch_top.rpm > 0.36 and int(earned.runtime.counters.get("clutch_recover", 0)) == 1, "A useful danger-state hit cannot cancel Clutch by first paying ordinary reclamation")
	var safe: Host = host("clutch", 2)
	safe.entity(1).rpm = 0.265
	safe.runtime.recover()
	safe.entity(1).rpm = 0.40
	safe.entity(1).vel = Vector2(80, 0)
	step(safe, Vector2(0.5, 0))
	contact(safe)
	check(int(safe.runtime.counters.get("clutch_recover", 0)) == 0 and safe.entity(1).rpm == 0.40, "A safely spinning approach cannot borrow an old Clutch window")
	var bounded: Host = host("clutch", 2)
	bounded.entity(1).rpm = 0.10
	bounded.entity(1).vel = Vector2(30, 0)
	bounded.runtime.recover()
	step(bounded, Vector2(0.5, 0))
	contact(bounded, 0.21)
	check(bounded.gains == 0.0, "Weak brushing still cannot generate Clutch reclamation")
	contact(bounded, 0.22)
	check(bounded.gains > 0.0, "A genuinely moving low-spin approach can earn a catch without impossible high-speed requirements")
	for hit: int in range(6):
		step(bounded, Vector2(0.5, 0), false, 1.4)
		contact(bounded, 0.30)
	check(bounded.gains <= 0.130001, "One dangerous window has a finite total catch quota even with repeated useful contacts")

func _test_rank_routes() -> void:
	var strengths: Array[float] = []
	for level: int in [1, 2]:
		var h: Host = host("afterimage", level)
		var p: Dictionary = h.entity(1)
		p.vel = Vector2(150, 0)
		p.pos = Vector2(40, 0)
		h.entity(2).pos = Vector2(20, 8)
		h.runtime.after_movement()
		h.runtime.flush_contact_powers()
		check(h.runtime.traces.size() == 1 and h.entity(2).vel.y > 0.0 and h.entity(2).wobble > 0.0, "Rank %d route immediately disrupts a hostile at ordinary movement speed" % level)
		strengths.append(h.entity(2).vel.y)
		h.runtime.begin_tick(1.6)
		check(h.runtime.traces.is_empty() if level == 1 else not h.runtime.traces.is_empty(), "Rank II meaningfully extends route persistence")
	check(strengths[1] > strengths[0] * 1.5, "Rank II physical route pressure is a deeper useful investment")

func _test_slipstream() -> void:
	var h: Host = host("afterimage", 3, "slipstream")
	var p: Dictionary = h.entity(1)
	p.pos = Vector2(40, 0)
	p.vel = Vector2(180, 0)
	h.runtime.after_movement()
	h.runtime.begin_tick(0.4)
	p.pos = Vector2(20, 40)
	p.vel = Vector2(0, -180)
	h.runtime.after_movement()
	p.pos = Vector2(20, -25)
	h.runtime.after_movement()
	check(int(h.runtime.counters.get("slipstream_cross", 0)) == 1 and p.vel.length() >= 269.0, "Crossing even past the route immediately produces Slipstream surge")
	var reserve: float = p.rpm
	h.runtime.after_movement()
	check(int(h.runtime.counters.slipstream_cross) == 1 and p.rpm == reserve, "Slipstream same-route retrigger protection prevents stationary farming")

func _test_support_depth() -> void:
	var base: Host = host("impact_wake", 1)
	var deeper: Host = host("impact_wake", 2)
	for h: Host in [base, deeper]:
		h.fighters.append(fighter(3, "", 1, "", Vector2(10, 60)))
		contact(h)
	check(base.entity(3).vel == Vector2.ZERO and deeper.entity(3).vel.length() >= 24.0, "Wake II changes which nearby physical machines join the wake")
	for level: int in [1, 2]:
		var h: Host = host("chain_impact", level)
		h.entity(2).pos = Vector2(50, 0)
		contact(h)
		h.runtime.burst_started(h.entity(1), Vector2.RIGHT, 1.0)
		h.runtime.flush_contact_powers()
		check(h.entity(2).vel.x == (0.0 if level == 1 else 24.0), "Chain II extends the deliberate follow-through to more distant physical contact")
	var comet: Host = host("iron_comet", 2)
	var radius: float = comet.entity(1).radius
	comet.runtime.wall_rebound(comet.entity(1), 150.0, Vector2.RIGHT, Vector2(155, 0))
	comet.runtime.begin_tick(2.1)
	contact(comet)
	check(comet.entity(2).vel.x == 34.0 and comet.entity(1).radius == radius, "Iron Comet II allows delayed mechanical release without altering collision geometry")

func draw_orbit(h: Host, radius: float, ticks: int = 91, offset: Vector2 = Vector2.ZERO) -> Dictionary:
	var preview_seen: bool = false
	var first_preview: Dictionary = {}
	for tick: int in range(ticks):
		var angle: float = TAU * float(tick) / 90.0
		h.runtime.begin_tick(1.0 / 60.0)
		h.entity(1).pos = offset + Vector2(cos(angle), sin(angle)) * radius
		h.entity(1).vel = Vector2(-sin(angle), cos(angle)) * 200.0
		h.runtime.after_movement()
		h.runtime.flush_contact_powers()
		if not h.entity(1).ghost_preview.is_empty():
			preview_seen = true
			if first_preview.is_empty(): first_preview = h.entity(1).ghost_preview.duplicate(true)
	return {"preview": preview_seen, "first_preview": first_preview}

func _test_ghost() -> void:
	var h: Host = host("afterimage", 3, "ghost_circuit", Vector2(52, 0))
	h.entity(2).pos = Vector2.ZERO
	h.fighters.append(fighter(3, "", 1, "", Vector2(180, 0)))
	var result: Dictionary = draw_orbit(h, 52.0)
	check(result.preview, "Valid nearing paid route offers a readable closure bridge before activation")
	check(Vector2(result.first_preview.a).distance_to(result.first_preview.b) <= 70.0, "Preview bridge remains local and bounded")
	check(int(h.runtime.counters.get("ghost_closure", 0)) == 1, "Assisted closure snaps one imperfect real circuit")
	check(h.entity(2).vel.length() >= 80.0 and h.entity(2).rpm < 1.0 and h.entity(2).wobble > 0.10, "Circuit pays off with strong enclosed physical disruption and limited RPM damage")
	check(h.entity(3).vel == Vector2.ZERO and h.entity(3).rpm == 1.0, "Outside targets are not affected by completed route")
	var before: int = int(h.runtime.counters.get("ghost_closure", 0))
	h.runtime._modern_circuit(h.entity(1), true)
	check(int(h.runtime.counters.ghost_closure) == before, "Same trace cannot trigger duplicate simultaneous closures")
	var field: bool = false
	for trace: Dictionary in h.runtime.traces:
		if trace.has("circuit_points"):
			field = true
			check(trace.circuit_points.size() <= Runtime.CIRCUIT_POINT_LIMIT + 1, "Completed presentation route has bounded geometry")
	check(field, "Successful closure lights its own exact route geometry")
	measurements.ghost = {"preview_events": h.runtime.counters.get("ghost_preview", 0), "closures": h.runtime.counters.get("ghost_closure", 0), "target_reaction_speed": h.entity(2).vel.length()}
	var wider: Host = host("afterimage", 3, "ghost_circuit", Vector2(108, 0))
	var preview: bool = false
	for tick: int in range(271):
		var angle: float = TAU*float(tick)/270.0
		wider.runtime.begin_tick(1.0/60.0)
		wider.entity(1).pos = Vector2(cos(angle),sin(angle))*108.0
		wider.entity(1).vel = Vector2(-sin(angle),cos(angle))*150.0
		wider.runtime.after_movement()
		if not wider.entity(1).ghost_preview.is_empty(): preview = true
	check(preview and int(wider.runtime.counters.get("ghost_closure",0)) == 1, "A realistic wider four-second route retains its paid socket long enough for preview and snap")

func _test_ghost_abuse() -> void:
	var tiny: Host = host("afterimage", 3, "ghost_circuit", Vector2(12, 0))
	draw_orbit(tiny, 12.0, 271)
	check(int(tiny.runtime.counters.get("ghost_closure", 0)) == 0 and int(tiny.runtime.counters.get("ghost_preview", 0)) == 0, "Tiny-circle spam fails minimum area and meaningful-route criteria")
	var open: Host = host("afterimage", 3, "ghost_circuit")
	for tick: int in range(120):
		open.runtime.begin_tick(1.0 / 60.0)
		open.entity(1).pos = Vector2(tick * 3, 0)
		open.entity(1).vel = Vector2(180, 0)
		open.runtime.after_movement()
	check(int(open.runtime.counters.get("ghost_preview", 0)) == 0 and int(open.runtime.counters.get("ghost_closure", 0)) == 0, "A straight distant route cannot create unrelated bridge or fake loop")
	var gap: Host = host("afterimage", 3, "ghost_circuit", Vector2(52, 0))
	draw_orbit(gap, 52.0, 45)
	gap.entity(1).vel = Vector2.ZERO
	gap.entity(1).pos = Vector2(600, 0)
	gap.runtime.after_movement()
	draw_orbit(gap, 52.0, 35, Vector2(600, 0))
	check(int(gap.runtime.counters.get("ghost_closure", 0)) == 0, "Disconnected distant route sections cannot be joined across an invisible chord")
	var soak: Host = host("afterimage", 3, "ghost_circuit", Vector2(52, 0))
	draw_orbit(soak, 52.0, 901)
	check(soak.runtime.traces.size() <= Runtime.MODERN_GHOST_TRACE_LIMIT and soak.runtime.traces.size() <= Runtime.MAX_ALL_TRACES and soak.runtime.events.size() <= 256, "Long route play keeps trace and telemetry memory bounded")
	var first: Host = host("afterimage", 3, "ghost_circuit", Vector2(52, 0))
	var second: Host = host("afterimage", 3, "ghost_circuit", Vector2(52, 0))
	second.fighters.reverse()
	draw_orbit(first, 52.0)
	draw_orbit(second, 52.0)
	check(first.runtime.events == second.runtime.events and first.impulses == second.impulses, "Circuit events and physical reactions remain deterministic under reversed storage")
