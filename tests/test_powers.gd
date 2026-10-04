extends SceneTree
## Semantic power fixtures use a host with real entity dictionaries. Battle
## integration and continuous collision tests live in test_swarm.gd.
const Powers = preload("res://scripts/power_runtime.gd")
const Battle = preload("res://scripts/battle.gd")
var checks: int = 0
var failures: Array[String] = []

class Host extends RefCounted:
	var fighters: Array[Dictionary] = []
	var impulses: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	func entity(id: int) -> Dictionary:
		for fighter: Dictionary in fighters:
			if int(fighter["entity_id"]) == id:
				return fighter
		return {}
	func _ordered_fighters() -> Array[Dictionary]:
		var ordered: Array[Dictionary] = fighters.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["entity_id"]) < int(b["entity_id"]))
		return ordered
	func apply_power_impulse(target: Dictionary, velocity: Vector2, cause: Dictionary) -> void:
		target["vel"] = Vector2(target["vel"]) + velocity
		impulses.append({"target": int(target["entity_id"]), "velocity": velocity, "cause": cause.duplicate(true)})
	func add_power_fx(kind: String, position: Vector2, direction: Vector2, strength: float) -> void:
		effects.append({"kind": kind, "pos": position, "dir": direction, "strength": strength})

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: " + label)

func _fighter(id: int, position: Vector2, small: bool = false, powers: Array = []) -> Dictionary:
	return {"entity_id": id, "owner_id": "player" if id == 1 else "small_%d" % id,
		"team_id": "player" if id == 1 else "hostile", "combatant_type": "small_top" if small else "full_top",
		"pos": position, "vel": Vector2.ZERO, "radius": 6.0 if small else 12.0,
		"rpm": 1.0, "energy": 1.0, "wobble": 0.0, "outcome": "", "powers": powers,
		"burst_time": 0.42}

func _host(powers: Array, small: bool = false) -> Host:
	var host: Host = Host.new()
	host.fighters = [_fighter(1, Vector2.ZERO, false, powers), _fighter(2, Vector2(20, 0), small)]
	return host

func _runtime(host: Host) -> RefCounted:
	var runtime: RefCounted = Powers.new()
	runtime.setup(host)
	return runtime

func _contact(runtime: RefCounted, host: Host, severity: float = 0.7) -> void:
	runtime.accepted_contact(host.entity(1), host.entity(2), severity, Vector2.RIGHT, Vector2(10, 0), Vector2(-100, 0), Vector2(100, 0))

func _run() -> void:
	_test_wake()
	_test_second_wind()
	_test_redline_comet()
	_test_afterimage()
	_test_duel_chain()
	_test_attribution_and_cascade()
	_test_chain_budget_and_terminal()
	_test_competing_causes_and_trace_path()
	_test_battle_hooks()
	_test_determinism()
	print("Power runtime: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_wake() -> void:
	var host: Host = _host(["impact_wake"])
	var runtime: RefCounted = _runtime(host)
	_contact(runtime, host, 0.54)
	runtime.flush_contact_powers()
	_check(host.impulses.is_empty(), "Wake rejects contacts below severity threshold")
	_contact(runtime, host, 0.55)
	_check(host.impulses.is_empty(), "Contact powers queue until primary pair pass is complete")
	runtime.flush_contact_powers()
	_check(host.entity(2).vel == Vector2(12, 0), "Lone full rival receives capped 12-unit Wake follow-through")
	_check(host.entity(2).rpm == 1.0, "Wake never drains reserve directly")
	_contact(runtime, host)
	runtime.flush_contact_powers()
	_check(host.impulses.size() == 1, "Wake cooldown prevents same-tick spam")
	host.fighters.append(_fighter(3, Vector2(10, 30), true))
	host.fighters.append(_fighter(4, Vector2(80, 0), true))
	runtime.begin_tick(1.25)
	_contact(runtime, host)
	runtime.flush_contact_powers()
	_check(host.entity(2).vel == Vector2(12, 0), "Crowd Wake excludes direct target")
	_check(host.entity(3).vel == Vector2(0, 60), "Crowd Wake throws a secondary small top outward")
	_check(host.entity(4).vel == Vector2.ZERO, "Wake world-space radius excludes distant targets")
	_check(runtime.counters.impact_wake == 2, "Secondary Wake impulse does not recursively proc Wake")

func _test_second_wind() -> void:
	var host: Host = _host(["second_wind", "redline"])
	var runtime: RefCounted = _runtime(host)
	var player: Dictionary = host.entity(1)
	player.rpm = 0.14
	player.wobble = 0.80
	player.vel = Vector2(33, 18)
	runtime.recover()
	_check(is_equal_approx(player.rpm, 0.32) and is_equal_approx(player.wobble, 0.55), "Second Wind restores finite reserve and reduces wobble")
	_check(player.vel == Vector2(33, 18), "Recovery preserves position and motion")
	player.rpm = 0.01
	runtime.recover()
	_check(player.rpm == 0.01 and runtime.counters.second_wind == 1, "Second Wind cannot sustain repeatedly")
	runtime.setup(host)
	player.rpm = 0.28
	player.wobble = 0.75
	runtime.recover()
	_check(is_equal_approx(player.rpm, 0.40), "Wobble-triggered recovery respects its 0.40 reserve ceiling")
	runtime.setup(host)
	player.rpm = 0.0
	player.outcome = "ring_out"
	runtime.recover()
	_check(player.rpm == 0.0 and not player.second_wind_used, "Confirmed gate exit defeats recovery")
	player.outcome = ""
	runtime.setup(host)
	player.rpm = 0.36
	player.wobble = 0.0
	player.rpm -= 0.013
	runtime.burst_started(player, Vector2.RIGHT, 0.36)
	_check(player.rpm < 0.35 and runtime.redline_active(player), "Second Wind plus Redline pays ordinary and extra costs")
	player.rpm = 0.13
	runtime.recover()
	_check(is_equal_approx(player.rpm, 0.31), "Second Wind uses stored reserve while Redline is active")
	player.rpm = 0.03
	runtime.recover()
	_check(player.rpm == 0.03, "Second Wind plus Redline has only one comeback")

func _test_redline_comet() -> void:
	var host: Host = _host(["redline", "iron_comet"])
	var runtime: RefCounted = _runtime(host)
	var player: Dictionary = host.entity(1)
	player.rpm = 0.337
	runtime.burst_started(player, Vector2.RIGHT, 0.349)
	_check(not runtime.redline_active(player), "Redline requires at least 0.35 reserve before normal Burst cost")
	player.rpm = 0.987
	runtime.burst_started(player, Vector2.RIGHT, 1.0)
	_check(is_equal_approx(player.rpm, 0.947) and runtime.effective_rpm(player) == 1.15, "Redline overdrive is effective output, not stored healing")
	_check(is_equal_approx(player.wobble, 0.10) and is_equal_approx(player.burst_time, 0.42), "Redline instability is finite and ordinary attack multiplier window stays 0.42 seconds")
	var paid: float = player.rpm
	runtime.burst_started(player, Vector2.RIGHT, 1.0)
	_check(player.rpm == paid, "Already-active Redline cannot recharge or repay extra cost")
	runtime.wall_rebound(player, 109.9, Vector2.RIGHT, Vector2(155, 0))
	_check(player.comet_time == 0.0, "Iron Comet ignores weak wall rebounds")
	runtime.wall_rebound(player, 110.0, Vector2.RIGHT, Vector2(155, 0))
	_check(player.comet_time == 2.0 and player.rpm == paid, "Real wall rebound charges Comet without refunding wall reserve")
	_contact(runtime, host)
	runtime.flush_contact_powers()
	_check(host.entity(2).vel == Vector2(25, 0), "Redline plus Iron Comet releases bounded extra target impulse")
	_check(player.vel == Vector2(20, 0), "Redline restores only 20 percent of recoil opposite committed heading")
	_check(player.comet_time == 0.0, "Next accepted contact consumes Comet")
	_contact(runtime, host)
	runtime.flush_contact_powers()
	_check(player.vel == Vector2(20, 0) and host.entity(2).vel == Vector2(25, 0), "Recoil restoration and wall charge are each single-use")
	runtime.begin_tick(0.79)
	_check(runtime.redline_active(player), "Redline extends speed to its full 0.8-second window")
	runtime.begin_tick(0.02)
	_check(not runtime.redline_active(player) and runtime.effective_rpm(player) == player.rpm, "Redline releases back to ordinary RPM weighting")
	runtime.wall_rebound(player, 200, Vector2.RIGHT, Vector2.ZERO)
	_check(player.comet_time == 0.0, "Comet cannot rearm inside one-second delay")
	runtime.begin_tick(0.20)
	runtime.wall_rebound(player, 200, Vector2.RIGHT, Vector2.ZERO)
	runtime.begin_tick(2.01)
	_contact(runtime, host)
	runtime.flush_contact_powers()
	_check(host.entity(2).vel == Vector2(25, 0), "Expired Comet does not empower a later hit")

func _test_afterimage() -> void:
	var host: Host = _host(["afterimage", "redline", "impact_wake"])
	var runtime: RefCounted = _runtime(host)
	var player: Dictionary = host.entity(1)
	player.vel = Vector2(180, 0)
	runtime.after_movement()
	_check(runtime.traces.is_empty(), "Afterimage requires movement above 180 units per second")
	player.vel = Vector2(250, 0)
	player.pos = Vector2(40, 0)
	host.entity(2).pos = Vector2(20, 8)
	runtime.after_movement()
	runtime.flush_contact_powers()
	_check(runtime.traces.size() == 1 and is_equal_approx(player.rpm, 0.998), "Fast actual trajectory emits a finite paid trace")
	_check(host.entity(2).vel == Vector2(0, 12) and host.entity(2).rpm == 1.0, "Trace overlap applies capped lateral pressure without reserve drain")
	runtime.after_movement()
	runtime.flush_contact_powers()
	_check(host.impulses.size() == 1 and runtime.traces.size() == 1, "Trace emission and per-enemy hit cooldown both prevent spam")
	for index: int in range(5):
		runtime.begin_tick(0.18)
		player.pos += Vector2(30, 0)
		runtime.after_movement()
		runtime.flush_contact_powers()
		_check(runtime.traces.size() <= 3, "At most three active Afterimage segments")
	player.vel = Vector2.ZERO
	runtime.begin_tick(0.46)
	runtime.after_movement()
	_check(runtime.traces.is_empty(), "All traces expire after 0.45 seconds")
	player.rpm = 0.8
	runtime.burst_started(player, Vector2.RIGHT, 0.813)
	player.vel = Vector2(260, 0)
	player.pos += Vector2(20, 0)
	runtime.after_movement()
	_check(runtime.redline_active(player) and runtime.traces.size() == 1, "Redline and Afterimage coexist through high-speed movement")
	host.entity(2).pos = player.pos + Vector2(20, 0)
	_contact(runtime, host)
	runtime.flush_contact_powers()
	_check(runtime.counters.impact_wake == 1 and runtime.traces.size() == 1, "Impact Wake plus Afterimage preserves both pressure mechanisms")

func _test_duel_chain() -> void:
	var host: Host = _host(["chain_impact"])
	var runtime: RefCounted = _runtime(host)
	_contact(runtime, host, 0.59)
	runtime.burst_started(host.entity(1), Vector2.RIGHT, 1.0)
	runtime.flush_contact_powers()
	_check(host.impulses.is_empty(), "Chain duel fallback requires a heavy accepted primary hit")
	_contact(runtime, host, 0.60)
	runtime.burst_started(host.entity(1), Vector2.RIGHT, 1.0)
	runtime.flush_contact_powers()
	_check(host.entity(2).vel == Vector2(15, 0), "Next valid Burst releases a close-range chain pulse in a duel")
	runtime.burst_started(host.entity(1), Vector2.RIGHT, 1.0)
	runtime.flush_contact_powers()
	_check(host.impulses.size() == 1 and runtime.counters.chain_prime == 1, "Chain Burst pulse cannot re-prime itself")
	runtime.begin_tick(2.01)
	_contact(runtime, host)
	host.entity(2).pos = Vector2(43, 0)
	runtime.burst_started(host.entity(1), Vector2.RIGHT, 1.0)
	runtime.flush_contact_powers()
	_check(host.impulses.size() == 1, "Chain Burst cannot hit a rival outside actual 42-unit radius")
	runtime.begin_tick(2.01)
	_contact(runtime, host)
	runtime.begin_tick(2.01)
	host.entity(2).pos = Vector2(20, 0)
	runtime.burst_started(host.entity(1), Vector2.RIGHT, 1.0)
	runtime.flush_contact_powers()
	_check(host.impulses.size() == 1, "Unused duel prime expires after two seconds")

func _test_attribution_and_cascade() -> void:
	var host: Host = _host(["impact_wake", "chain_impact"], true)
	host.fighters.append(_fighter(3, Vector2(10, 20), true))
	host.fighters.append(_fighter(4, Vector2(10, 30), true))
	var runtime: RefCounted = _runtime(host)
	_contact(runtime, host)
	runtime.flush_contact_powers()
	var direct: Dictionary = runtime.cause_for(host.entity(2))
	var wake: Dictionary = runtime.cause_for(host.entity(3))
	_check(direct.owner_id == "player" and direct.primary and direct.generation == 0, "Direct player contact tags a thrown small top")
	_check(not wake.primary and wake.root_event_id == direct.root_event_id, "Player-owned Wake inherits the direct contact root")
	runtime.accepted_contact(host.entity(2), host.entity(4), 0.7, Vector2.DOWN, Vector2(10, 25))
	var inherited: Dictionary = runtime.cause_for(host.entity(4))
	_check(inherited.root_event_id == direct.root_event_id and inherited.generation == 0, "Thrown-body physical collision preserves root and generation")
	_check(runtime.counters.impact_wake == 1, "Thrown bodies cannot proc their owner's Wake")
	host.entity(2).outcome = "spin_out"
	runtime.eliminated(host.entity(2), "impact")
	var count_before: int = host.impulses.size()
	runtime.end_tick(false)
	_check(host.impulses.size() == count_before, "Elimination queues pressure after terminal exclusion without same-tick impulse")
	runtime.begin_tick(1.0 / 60.0)
	_check(runtime.counters.chain_impact == 1 and host.impulses.size() > count_before, "Elimination pulse applies at next live tick")
	_check(runtime.cause_for(host.entity(3)).generation == 1, "First chain pulse advances inherited generation once")
	host.entity(3).outcome = "spin_out"
	runtime.eliminated(host.entity(3), "impact")
	runtime.end_tick(false)
	runtime.begin_tick(1.0 / 60.0)
	_check(runtime.cause_for(host.entity(4)).generation == 2, "Second chain pulse reaches maximum generation two")
	host.entity(4).outcome = "ring_out"
	runtime.eliminated(host.entity(4), "ring_out")
	runtime.end_tick(false)
	runtime.begin_tick(1.0 / 60.0)
	_check(runtime.counters.chain_impact == 2, "Generation-two elimination cannot emit a third-generation pulse")
	var old_root: int = direct.root_event_id
	host.entity(2).outcome = ""
	_contact(runtime, host)
	_check(runtime.cause_for(host.entity(2)).root_event_id != old_root, "New direct player contact establishes a new root")
	runtime.begin_tick(1.01)
	_check(runtime.cause_for(host.entity(2)).is_empty(), "Thrown-body attribution expires after one second")

func _test_chain_budget_and_terminal() -> void:
	var host: Host = _host(["chain_impact"], true)
	var runtime: RefCounted = _runtime(host)
	_contact(runtime, host)
	var cause: Dictionary = runtime.cause_for(host.entity(2))
	for id: int in range(3, 18):
		var body: Dictionary = _fighter(id, Vector2(10, 0), true)
		body["player_cause"] = cause.duplicate(true)
		body.outcome = "spin_out"
		host.fighters.append(body)
		runtime.eliminated(body, "impact")
		runtime.eliminated(body, "impact")
	runtime.end_tick(false)
	runtime.begin_tick(1.0 / 60.0)
	_check(runtime.counters.chain_impact == 12, "Each root permits at most twelve pulses; duplicate eliminated IDs never pulse twice")
	runtime.setup(host)
	host.entity(2).outcome = ""
	_contact(runtime, host)
	host.entity(2).outcome = "spin_out"
	runtime.eliminated(host.entity(2), "natural_retirement")
	runtime.end_tick(false)
	runtime.begin_tick(1.0 / 60.0)
	_check(not runtime.counters.has("chain_impact"), "Natural retirement never earns a chain pulse even with a recent cause")
	runtime.setup(host)
	host.entity(2).outcome = ""
	_contact(runtime, host)
	host.entity(2).outcome = "ring_out"
	runtime.eliminated(host.entity(2), "ring_out")
	runtime.end_tick(true)
	runtime.begin_tick(1.0 / 60.0)
	_check(not runtime.counters.has("chain_impact"), "Terminal encounter result suppresses queued elimination cascade")
	var before: int = host.effects.size()
	runtime.burst_started(host.entity(1), Vector2.RIGHT, 1.0)
	runtime.wall_rebound(host.entity(1), 300, Vector2.RIGHT, Vector2.ZERO)
	runtime.recover()
	_check(host.effects.size() == before, "No gameplay procs occur after encounter finishes")

func _test_competing_causes_and_trace_path() -> void:
	var host: Host = _host(["chain_impact"], true)
	host.fighters.append(_fighter(3, Vector2(30, 0), true))
	var runtime: RefCounted = _runtime(host)
	_contact(runtime, host)
	var original_root: int = runtime.cause_for(host.entity(2)).root_event_id
	runtime.begin_tick(0.1)
	runtime.accepted_contact(host.entity(1), host.entity(3), 0.5, Vector2.RIGHT, Vector2(15, 0))
	var latest: Dictionary = runtime.cause_for(host.entity(3))
	runtime.accepted_contact(host.entity(2), host.entity(3), 0.5, Vector2.RIGHT, Vector2(25, 0))
	var inherited: Dictionary = runtime.cause_for(host.entity(2))
	_check(inherited.root_event_id != original_root and inherited.root_event_id == latest.root_event_id, "Competing inherited causes choose latest valid direct root")
	_check(inherited.source_entity_id == 3, "Inherited source identifies body supplying latest cause, regardless of pair position")
	_check(inherited.expires_at == latest.expires_at, "Physical inheritance never refreshes the attribution lifetime")
	runtime.begin_tick(1.01)
	runtime.accepted_contact(host.entity(2), host.entity(3), 0.5, Vector2.RIGHT, Vector2(25, 0))
	_check(runtime.cause_for(host.entity(2)).is_empty(), "Expired small-body contacts cannot manufacture a fresh root")
	host = _host(["afterimage"], true)
	runtime = _runtime(host)
	var player: Dictionary = host.entity(1)
	player.vel = Vector2(220, 0)
	host.entity(2).pos = Vector2(1000, 1000)
	runtime.after_movement()
	for point: Vector2 in [Vector2(100, 0), Vector2(100, 100)]:
		runtime.begin_tick(0.05)
		player.pos = point
		runtime.after_movement()
	runtime.begin_tick(0.09)
	player.pos = Vector2(0, 100)
	host.entity(2).pos = Vector2(0, 50)
	runtime.after_movement()
	runtime.flush_contact_powers()
	_check(host.impulses.is_empty(), "Turning Afterimage cannot hit across an imaginary chord between emissions")
	_check(runtime.traces.back().points.size() == 4, "Trace retains actual sampled trajectory through a turn")
	host.entity(2).pos = Vector2(100, 50)
	runtime.begin_tick(0.2)
	player.vel = Vector2.ZERO
	runtime.after_movement()
	runtime.flush_contact_powers()
	var trace_cause: Dictionary = runtime.cause_for(host.entity(2))
	_check(host.impulses.size() == 1 and not trace_cause.is_empty(), "Enemy crossing the actual old trace receives pressure")
	_check(is_equal_approx(float(trace_cause.expires_at), float(runtime.time) + 1.0), "A delayed trace impulse receives a full one-second attribution window")

func _integration_battle(power_ids: Array) -> Node2D:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	var build: Dictionary = {"blade": "balance", "ratchet": "mid", "bit": "ball"}
	battle.begin_encounter(build, {"opponent_build": build, "player_power_ids": power_ids, "seed": 713})
	battle.battle_status = "battle"
	return battle

func _test_battle_hooks() -> void:
	var battle: Node2D = _integration_battle(["iron_comet", "second_wind", "redline"])
	var player: Dictionary = battle.player_entity()
	player.pos = Vector2(160, 30)
	player.vel = Vector2(200, 0)
	player.rpm = 0.8
	battle._resolve_boundary(player)
	_check(player.comet_time == 2.0 and float(player.vel.x) < 0.0, "Battle charges Comet only after actual solid-wall reflection")
	_check(player.rpm < 0.8 and player.wobble > 0.0, "Battle preserves wall RPM loss and wobble while charging Comet")
	battle.powers.setup(battle)
	player.pos = Vector2(145, -145)
	player.vel = Vector2(220, -220)
	player.rpm = 0.01
	battle._resolve_boundary(player)
	battle.powers.recover()
	_check(player.outcome == "ring_out" and player.comet_time == 0.0 and player.rpm == 0.01, "Battle gate branch neither charges Comet nor permits Second Wind")
	battle.free()
	var ordinary: Node2D = _integration_battle([])
	var redline: Node2D = _integration_battle(["redline"])
	redline.player_entity().rpm = 0.987
	redline.powers.burst_started(redline.player_entity(), Vector2.RIGHT, 1.0)
	ordinary.player_entity().rpm = redline.player_entity().rpm
	for current: Node2D in [ordinary, redline]:
		current.player_entity().pos = Vector2(-10, 0)
		current.player_entity().vel = Vector2(140, 0)
		current.entity(2).pos = Vector2(10, 0)
		current.entity(2).vel = Vector2(-140, 0)
		current.resolve_pair(1, 2)
		current.powers.flush_contact_powers()
	_check(redline.entity(2).rpm < ordinary.entity(2).rpm, "Battle uses Redline effective RPM for real full-top attack weighting")
	_check(redline.player_entity().rpm <= 1.0 and redline.player_entity().rpm < 0.947, "Real Redline contact still pays stored reserve loss")
	_check(float(redline.player_entity().vel.x) > float(ordinary.player_entity().vel.x), "Real Redline contact restores bounded owner recoil")
	ordinary.free()
	redline.free()

func _test_determinism() -> void:
	var left: Host = _host(["impact_wake", "chain_impact", "afterimage", "redline"], true)
	var right: Host = _host(["impact_wake", "chain_impact", "afterimage", "redline"], true)
	for host: Host in [left, right]:
		host.fighters.append(_fighter(3, Vector2(10, 30), true))
		host.fighters.append(_fighter(4, Vector2(40, 10), true))
	right.fighters.reverse()
	var a: RefCounted = _runtime(left)
	var b: RefCounted = _runtime(right)
	for index: int in range(120):
		for pair: Array in [[left, a], [right, b]]:
			var host: Host = pair[0]
			var runtime: RefCounted = pair[1]
			runtime.begin_tick(1.0 / 60.0)
			host.entity(1).vel = Vector2(220, 0)
			host.entity(1).pos = Vector2(float(index) * 0.2, 0)
			if index == 2:
				runtime.burst_started(host.entity(1), Vector2.RIGHT, 1.0)
			runtime.after_movement()
			if index % 30 == 0:
				_contact(runtime, host)
			runtime.flush_contact_powers()
			runtime.recover()
			runtime.end_tick(false)
	_check(left._ordered_fighters() == right._ordered_fighters(), "Power physics and attribution are identical under reversed storage order")
	_check(a.events == b.events and left.impulses == right.impulses, "Semantic event, source, root and impulse ordering is deterministic")
