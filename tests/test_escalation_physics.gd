extends SceneTree
## Deterministic mechanics fixtures. These are not a human feel verdict.
const Battle = preload("res://scripts/battle.gd")
const Runtime = preload("res://scripts/power_runtime.gd")
const Starters = preload("res://scripts/starters.gd")
const BUILD: Dictionary = {"blade": "balance", "ratchet": "mid", "bit": "ball"}
var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {}

class Host extends RefCounted:
	var fighters: Array[Dictionary] = []
	var impulses: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	func _ordered_fighters() -> Array[Dictionary]:
		var sorted: Array[Dictionary] = fighters.duplicate()
		sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.entity_id) < int(b.entity_id))
		return sorted
	func entity(id: int) -> Dictionary:
		for fighter: Dictionary in fighters:
			if int(fighter.entity_id) == id: return fighter
		return {}
	func apply_power_impulse(target: Dictionary, velocity: Vector2, cause: Dictionary) -> void:
		target.vel = Vector2(target.vel) + velocity
		impulses.append({"target": target.entity_id, "velocity": velocity, "cause": cause.duplicate(true)})
	func add_power_fx(kind: String, pos: Vector2, direction: Vector2, strength: float) -> void:
		effects.append({"kind": kind, "pos": pos, "dir": direction, "strength": strength})

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		print("FAIL: " + description)

func _fighter(id: int, powers: Array = [], ranks: Dictionary = {}, branches: Dictionary = {}, pos: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"entity_id": id, "owner_id": "player" if id == 1 else "rival", "team_id": "player" if id == 1 else "hostile",
		"combatant_type": "full_top", "pos": pos, "vel": Vector2.ZERO, "radius": 12.0, "mass": 8.0,
		"rpm": 1.0, "energy": 1.0, "wobble": 0.0, "outcome": "", "powers": powers,
		"power_ranks": ranks, "power_mutations": branches, "burst_time": 0.0, "height": 0.0, "height_vel": 0.0}

func _host(power: String, level: int, branch: String = "", start: Vector2 = Vector2.ZERO) -> Host:
	var host: Host = Host.new()
	host.fighters = [_fighter(1, [power], {power: level}, {power: branch}, start), _fighter(2, [], {}, {}, Vector2(20, 0))]
	return host

func _runtime(host: Host) -> RefCounted:
	var runtime: RefCounted = Runtime.new()
	runtime.setup(host)
	return runtime

func _battle(power: String = "", level: int = 1, branch: String = "") -> Node2D:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.begin_encounter(BUILD, {"opponent_build": BUILD, "seed": 713, "player_power_ids": [] if power.is_empty() else [power],
		"player_power_ranks": {} if power.is_empty() else {power: level}, "player_power_mutations": {} if branch.is_empty() else {power: branch}})
	battle.battle_status = "battle"
	return battle

func _contact(runtime: RefCounted, host: Host, severity: float = 0.7, incoming: float = 100.0) -> void:
	runtime.accepted_contact(host.entity(1), host.entity(2), severity, Vector2.RIGHT, Vector2(10, 0), Vector2(-100, 0), Vector2(100, 0), incoming, incoming)
	runtime.flush_contact_powers()

func _run() -> void:
	_test_acquisition_pause()
	_test_upgrade_during_overload()
	_test_redline()
	_test_real_runaway()
	_test_anchor()
	_test_counterweight()
	_test_afterimage()
	_test_unpaid_circuit_return()
	_test_caps_and_determinism()
	print("Escalation physics: %d checks, %d failures" % [checks, failures.size()])
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var report: FileAccess = FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			if report != null: report.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}, "\t"))
	quit(0 if failures.is_empty() else 1)

func _test_acquisition_pause() -> void:
	var battle: Node2D = _battle()
	_check(not battle.acquire_run_power("unknown"), "Battle rejects unknown powers")
	_check(not battle.acquire_run_power("redline", 2), "Cannot skip acquisition and jump straight to Rank II")
	for power: String in ["impact_wake", "second_wind", "redline", "iron_comet", "afterimage", "chain_impact", "dead_centre"]:
		_check(battle.acquire_run_power(power), "All seven powers can coexist: " + power)
	_check(battle.player_entity().powers.size() == 7, "Seven-power ownership has no small build cap")
	_check(not battle.acquire_run_power("redline"), "Repeated Rank I is rejected")
	_check(not battle.acquire_run_power("impact_wake", 2), "Horizontal support power cannot receive invented upgrades")
	var runtime: RefCounted = battle.powers
	battle.player_entity().rpm = 0.13
	battle.powers.recover()
	battle.player_entity().vel = Vector2(250, 0)
	battle.powers.after_movement()
	battle.player_entity().cooldown = 2.8
	battle.set_paused(true)
	var state: Dictionary = battle.snapshot()
	var runtime_state: Dictionary = battle.powers._states.duplicate(true)
	var traces: Array = battle.powers.traces.duplicate(true)
	_check(battle.acquire_run_power("redline", 2), "Owned Rank I upgrades to Rank II")
	_check(not battle.acquire_run_power("redline", 3, "bulwark"), "Cross-power mutation is rejected")
	_check(battle.acquire_run_power("redline", 3, "runaway"), "Valid mutation applies immediately")
	_check(not battle.acquire_run_power("redline", 3, "breakneck") and not battle.acquire_run_power("redline", 3, "runaway"), "Mutations are exclusive and cannot be acquired twice")
	_check(battle.player_entity().powers.size() == 7 and battle.player_entity().power_ranks.redline == 3, "Upgrade changes investment without duplicate owned IDs")
	_check(battle.encounter.player_power_mutations.redline == "runaway", "Encounter descriptor mirrors investment")
	battle.test_step(0.25, Vector2.ONE, true, true)
	_check(battle.powers == runtime and battle.powers._states == runtime_state and battle.powers.traces == traces, "Upgrade and paused ticks preserve exact runtime cooldowns, causes and traces")
	_check(battle.player_entity().rpm == state.player.rpm and battle.player_entity().pos == state.player.pos and battle.player_entity().cooldown == 2.8, "Mutation preview fabricates no gameplay outcome")
	_check(battle.player_entity().second_wind_used, "Upgrading never replenishes Second Wind")
	battle.set_paused(false)
	_check(battle.player_entity().power_mutations.redline == "runaway", "Mutation survives same-encounter resume")
	battle.free()
	var reconstructed: Node2D = _battle("dead_centre", 3, "counterweight")
	_check(reconstructed.powers.mutation(reconstructed.player_entity(), "dead_centre") == "counterweight", "Encounter reconstruction reads ranks and branch descriptor")
	reconstructed.free()

func _test_redline() -> void:
	var basic: Node2D = _battle("redline", 1)
	var tuned: Node2D = _battle("redline", 2)
	for battle: Node2D in [basic, tuned]:
		battle.player_entity().pos = Vector2.ZERO
		battle._attempt_burst(battle.player_entity(), Vector2.RIGHT)
		for step: int in range(18):
			battle.powers.begin_tick(1.0 / 60.0)
			battle._update_fighter(battle.player_entity(), Vector2.RIGHT, false, 1.0 / 60.0)
	_check(Vector2(tuned.player_entity().vel).length() > Vector2(basic.player_entity().vel).length() * 1.25, "Redline II produces visibly stronger real acceleration")
	_check(tuned.player_entity().rpm < basic.player_entity().rpm and tuned.player_entity().wobble > basic.player_entity().wobble, "Redline II pays larger reserve and instability costs")
	_check(tuned.powers.attack_multiplier(tuned.player_entity()) > basic.powers.attack_multiplier(basic.player_entity()), "Redline II changes real collision weighting")
	basic.free()
	tuned.free()
	var runaway_host: Host = _host("redline", 3, "runaway")
	var runaway: RefCounted = _runtime(runaway_host)
	var player: Dictionary = runaway_host.entity(1)
	runaway.burst_started(player, Vector2.RIGHT, 1.0)
	runaway.begin_tick(0.9)
	var remaining: float = player.redline_time
	_contact(runaway, runaway_host, 0.34)
	_check(is_equal_approx(player.redline_time, remaining) and player.runaway_heat == 0.0, "Runaway ignores meaningless contacts")
	_contact(runaway, runaway_host)
	_check(player.redline_time > remaining and player.runaway_heat > 0.0, "Meaningful aggression extends Runaway and increases heat")
	var reserve: float = player.rpm
	_contact(runaway, runaway_host)
	_check(is_equal_approx(player.rpm, reserve), "Runaway cannot refund reserve repeatedly inside hit cooldown")
	for hit: int in range(5):
		runaway.begin_tick(0.30)
		_contact(runaway, runaway_host)
	_check(runaway.time > 2.0 and runaway.redline_active(player) and player.runaway_heat == 1.0, "Successive hits sustain overload beyond basic duration and reach capped heat")
	_check(player.redline_time <= 1.25 and player.rpm <= 1.0, "Runaway timer and reserve refund have finite caps")
	runaway.begin_tick(1.26)
	_check(not runaway.redline_active(player) and player.runaway_heat == 0.0, "Missing the next attack ends overload and clears heat")
	var starving: Host = _host("redline", 3, "runaway")
	var starved: RefCounted = _runtime(starving)
	starved.burst_started(starving.entity(1), Vector2.RIGHT, 1.0)
	starving.entity(1).rpm = 0.13
	starved.begin_tick(0.10)
	_check(not starved.redline_active(starving.entity(1)), "Runaway loses overload when reserve is exhausted")
	var break_host: Host = _host("redline", 3, "breakneck")
	var breakneck: RefCounted = _runtime(break_host)
	player = break_host.entity(1)
	breakneck.burst_started(player, Vector2.RIGHT, 1.0)
	var motion: Dictionary = breakneck.movement_control(player, Vector2.LEFT, true, 1.0 / 60.0)
	_check(player.redline_time == 0.36 and player.vel == Vector2(180, 0), "Breakneck compresses overload into short directional commitment")
	_check(Vector2(motion.direction).dot(Vector2.RIGHT) > 0.98 and not motion.braking, "Breakneck sharply reduces steering and ignores brake during commitment")
	var before_wobble: float = player.wobble
	_contact(breakneck, break_host, 0.20)
	_check(breakneck.redline_active(player) and not bool(breakneck._state(player).redline_hit), "Glancing contact cannot silently consume Breakneck's catastrophic strike")
	_contact(breakneck, break_host)
	_check(break_host.entity(2).vel.x >= 80.0 and not breakneck.redline_active(player), "Breakneck delivers one physical catastrophic impact then exits")
	_check(player.wobble > before_wobble + 0.30, "Breakneck impact leaves substantial recovery instability")
	_contact(breakneck, break_host)
	_check(int(breakneck.counters.get("breakneck_impact", 0)) == 1, "Breakneck cannot repeat its strike after commitment ends")
	var missed_host: Host = _host("redline", 3, "breakneck")
	var missed: RefCounted = _runtime(missed_host)
	missed.burst_started(missed_host.entity(1), Vector2.RIGHT, 1.0)
	missed.begin_tick(0.37)
	_check(missed_host.entity(1).wobble >= 0.49 and not missed.redline_active(missed_host.entity(1)), "Missed Breakneck still incurs post-charge instability")
	var small_losses: Array[float] = []
	for branch: String in ["", "breakneck"]:
		var battle: Node2D = _battle("redline", 2 if branch.is_empty() else 3, branch)
		battle._attempt_burst(battle.player_entity(), Vector2.RIGHT)
		battle.player_entity().pos = Vector2(-10, 0)
		battle.player_entity().vel = Vector2(200, 0)
		battle.entity(2).combatant_type = "small_top"
		battle.entity(2).radius = 6.0
		battle.entity(2).mass = 1.3
		battle.entity(2).pos = Vector2(6, 0)
		battle.entity(2).vel = Vector2(-100, 0)
		battle.resolve_pair(1, 2)
		small_losses.append(1.0 - float(battle.entity(2).rpm))
		if not branch.is_empty(): _check(battle.player_entity().burst_time == 0.0, "Breakneck clears ordinary Burst after its committed strike")
		battle.free()
	_check(small_losses[1] > small_losses[0] * 1.7, "Small-top solver preserves pre-strike Breakneck output even when contact consumes overload")

func _test_upgrade_during_overload() -> void:
	var basic: Node2D = _battle("redline", 1)
	basic._attempt_burst(basic.player_entity(), Vector2.RIGHT)
	var basic_state: Dictionary = basic.powers._states.duplicate(true)
	_check(basic.acquire_run_power("redline", 2), "Rank II investment is legal during paid Rank I overload")
	_check(basic.powers._states == basic_state and basic.powers.attack_multiplier(basic.player_entity()) == 1.0 and basic.player_entity().redline_active_rank == 1, "Rank I activation retains its original paid behavior after Rank II investment")
	basic.free()
	var battle: Node2D = _battle("redline", 2)
	var player: Dictionary = battle.player_entity()
	battle._attempt_burst(player, Vector2.RIGHT)
	player.pos = Vector2(-10, 0)
	player.vel = Vector2(180, 0)
	battle.entity(2).pos = Vector2(10, 0)
	battle.entity(2).vel = Vector2(-100, 0)
	battle.resolve_pair(1, 2)
	battle.powers.flush_contact_powers()
	_check(bool(battle.powers._state(player).redline_hit), "Real Rank II contact marks its existing recoil interaction as spent")
	battle.set_paused(true)
	var before: Dictionary = battle.snapshot()
	var runtime_state: Dictionary = battle.powers._states.duplicate(true)
	_check(battle.acquire_run_power("redline", 3, "breakneck"), "Breakneck investment is legal during existing contact-triggered overload")
	_check(battle.powers._states == runtime_state and player.pos == before.player.pos and player.vel == before.player.vel and player.rpm == before.player.rpm and player.cooldown == before.player.cooldown, "Mutation acquisition preserves exact paid activation state and physical reserve")
	var motion: Dictionary = battle.powers.movement_control(player, Vector2.LEFT, true, 1.0 / 60.0)
	_check(player.redline_active_mutation == "" and player.redline_active_rank == 2 and motion.direction == Vector2.LEFT and motion.braking and battle.powers.attack_multiplier(player) == 1.35, "Current Rank II activation retains matching steering, attack and presentation after Breakneck selection")
	battle.set_paused(false)
	var reserve: float = player.rpm
	var wobble: float = player.wobble
	var velocity: Vector2 = player.vel
	battle.powers.begin_tick(1.11)
	_check(not battle.powers.redline_active(player) and player.rpm == reserve and player.wobble == wobble and player.vel == velocity, "Old Rank II expiration does not apply newly selected Breakneck recovery penalties")
	# Advance ordinary cooldown/control clocks without replacing the fighter.
	for tick: int in range(241):
		battle.powers.begin_tick(1.0 / 60.0)
		battle._update_fighter(player, Vector2.ZERO, true, 1.0 / 60.0)
	_check(player.cooldown == 0.0, "Next mutated activation still waits for ordinary Burst cooldown")
	battle._attempt_burst(player, Vector2.RIGHT)
	_check(player.redline_active_mutation == "breakneck" and is_equal_approx(player.redline_time, 0.36) and not bool(battle.powers._state(player).redline_hit), "Next valid Burst starts fresh Breakneck duration and unspent defining strike")
	battle.powers.accepted_contact(player, battle.entity(2), 0.7, Vector2.RIGHT, player.pos, Vector2(-100, 0), Vector2(100, 0))
	battle.powers.flush_contact_powers()
	_check(int(battle.powers.counters.get("breakneck_impact", 0)) == 1 and not battle.powers.redline_active(player), "Mutated next activation delivers its defining physical strike")
	battle.free()

func _test_real_runaway() -> void:
	var rows: Array[Dictionary] = []
	for replay_seed: int in [421, 7341, 1609, 975]:
		var battle: Node2D = Battle.new()
		root.add_child(battle)
		battle.set_physics_process(false)
		battle.begin_encounter(Starters.build_for("breaker"), {"slot": 1, "seed": replay_seed, "starter_id": "breaker", "opponent_build": Starters.build_for("bastion"), "live_time_limit": 60.0,
			"player_power_ids": ["redline", "second_wind", "chain_impact", "impact_wake", "iron_comet"], "player_power_ranks": {"redline": 3}, "player_power_mutations": {"redline": "runaway"}})
		var active_start: float = -1.0
		var longest: float = 0.0
		var peak_heat: float = 0.0
		# Native starting positions, launch, AI and contacts remain intact.
		# The policy only submits legal steering, brake and Burst controls.
		for tick: int in range(3600):
			var player: Dictionary = battle.player_entity()
			var enemy: Dictionary = battle.entity(2)
			var offset: Vector2 = Vector2(enemy.pos) - Vector2(player.pos)
			var world: Vector2 = (offset + Vector2(enemy.vel) * 0.08).normalized()
			var screen: Vector2 = Vector2(world.x - world.y, (world.x + world.y) * 0.5).normalized()
			var edge: bool = Vector2(player.pos).length() > 145.0 and Vector2(player.pos).dot(Vector2(player.vel)) > 0.0
			var burst: bool = float(player.cooldown) <= 0.0 and float(player.rpm) >= 0.38 and offset.length() < 110.0 and not edge
			battle.test_step(1.0 / 60.0, screen, burst, edge)
			if battle.powers.redline_active(player):
				if active_start < 0.0: active_start = battle.elapsed
				longest = maxf(longest, float(battle.elapsed) - active_start)
			else: active_start = -1.0
			peak_heat = maxf(peak_heat, float(player.runaway_heat))
			if battle.battle_status == "finished": break
		_check(int(battle.powers.counters.get("runaway_hit", 0)) > 0 and longest > 1.50, "Legal pursuit sustains Runaway through real contact beyond start duration: seed %d" % replay_seed)
		_check(battle.player_entity().rpm < 1.0 and battle.hits > 0, "Real sustained aggression still spends physical reserve: seed %d" % replay_seed)
		rows.append({"seed": replay_seed, "combat_seconds": battle.elapsed, "sustain_hits": battle.powers.counters.get("runaway_hit", 0), "longest_overload_seconds": longest,
			"peak_heat": peak_heat, "redline_starts": battle.powers.counters.get("redline", 0), "won": battle.last_result.get("won", false), "reason": battle.last_result.get("reason", ""), "remaining_rpm": battle.player_entity().rpm})
		battle.free()
	measurements["real_runaway_pursuit"] = rows

func _test_anchor() -> void:
	var anchor: Node2D = _battle("dead_centre", 1)
	anchor.player_entity().pos = Vector2.ZERO
	anchor.player_entity().vel = Vector2(50, 0)
	for tick: int in range(120):
		anchor.powers.begin_tick(1.0 / 60.0)
		anchor._update_fighter(anchor.player_entity(), Vector2.ZERO, true, 1.0 / 60.0)
	_check(anchor.player_entity().anchor_charge >= 0.99 and Vector2(anchor.player_entity().vel).length() < 3.0, "Braking centrally builds a visible, physically planted anchor")
	_check(anchor.powers.inverse_mass(anchor.player_entity()) < 1.0 / float(anchor.player_entity().mass) * 0.26, "Rank I Anchor increases physical mass through solver inverse mass")
	for tick: int in range(30):
		anchor.powers.begin_tick(1.0 / 60.0)
		anchor._update_fighter(anchor.player_entity(), Vector2.RIGHT, false, 1.0 / 60.0)
	_check(anchor.player_entity().anchor_charge <= 0.001, "Aggressive movement disrupts Anchor")
	anchor.player_entity().pos = Vector2(135, 0)
	anchor.player_entity().vel = Vector2.ZERO
	for tick: int in range(20): anchor.powers.movement_control(anchor.player_entity(), Vector2.ZERO, true, 1.0 / 60.0)
	_check(anchor.player_entity().anchor_charge == 0.0, "Edge camping cannot charge central Anchor")
	anchor.free()
	var displacement: Array[float] = []
	var reactions: Array[float] = []
	for branch: String in ["none", "anchor", "bulwark"]:
		var battle: Node2D = _battle() if branch == "none" else _battle("dead_centre", 2 if branch == "anchor" else 3, "" if branch == "anchor" else branch)
		var player: Dictionary = battle.player_entity()
		player.pos = Vector2(-10, 0)
		player.vel = Vector2.ZERO
		player.anchor_charge = 1.0 if branch != "none" else 0.0
		battle.entity(2).pos = Vector2(10, 0)
		battle.entity(2).vel = Vector2(-220, 0)
		battle.resolve_pair(1, 2)
		battle.powers.flush_contact_powers()
		displacement.append(Vector2(player.pos).distance_to(Vector2(-10, 0)))
		reactions.append(Vector2(battle.entity(2).vel).length())
		if branch == "bulwark":
			_check(player.anchor_charge > 0.95 and Vector2(player.vel).length() < 5.0, "Bulwark remains planted through heavy real collision")
			_check(player.height_vel == 0.0 and int(battle.powers.counters.get("bulwark_impact", 0)) == 1, "Bulwark suppresses loft and visibly retaliates once")
		battle.free()
	_check(displacement[1] < displacement[0] * 0.25 and displacement[2] < displacement[0] * 0.04, "Rank II and Bulwark materially resist overlap displacement")
	_check(reactions[2] > reactions[0] * 1.6, "Bulwark converts heavy contact into dramatic enemy physical reaction")
	var broken_host: Host = _host("dead_centre", 1)
	var broken: RefCounted = _runtime(broken_host)
	broken_host.entity(1).anchor_charge = 1.0
	_contact(broken, broken_host, 1.0, 160.0)
	_check(broken_host.entity(1).anchor_charge == 0.0, "Extreme force breaks Rank I Anchor")

func _test_counterweight() -> void:
	var host: Host = _host("dead_centre", 3, "counterweight")
	var runtime: RefCounted = _runtime(host)
	var player: Dictionary = host.entity(1)
	player.anchor_charge = 1.0
	_contact(runtime, host, 0.7, 100.0)
	_check(is_equal_approx(player.stored_force, 42.0), "Counterweight stores captured incoming physical force")
	_check(host.entity(2).vel == Vector2.ZERO, "Storing force does not fabricate retaliation before release")
	var stored: float = player.stored_force
	runtime.begin_tick(0.5)
	_check(player.stored_force == stored, "Stored force persists until deliberate release")
	runtime.burst_started(player, Vector2.RIGHT, 1.0)
	runtime.flush_contact_powers()
	_check(player.stored_force == 0.0 and player.anchor_charge == 0.0, "Burst consumes stored force and releases the brace")
	_check(player.vel.x >= stored and host.entity(2).vel.x > 30.0, "Counterweight launches owner and pushes enemies along chosen heading")
	runtime.burst_started(player, Vector2.RIGHT, 1.0)
	_check(int(runtime.counters.get("counterweight_release", 0)) == 1, "Empty Counterweight cannot release twice")
	player.anchor_charge = 1.0
	for hit: int in range(6):
		runtime.begin_tick(0.25)
		_contact(runtime, host, 0.7, 150.0)
	_check(player.stored_force == 150.0, "Counterweight stored force has a hard cap")
	var unbraced: Host = _host("dead_centre", 3, "counterweight")
	var empty: RefCounted = _runtime(unbraced)
	_contact(empty, unbraced)
	_check(unbraced.entity(1).stored_force == 0.0, "Counterweight requires real Anchor to capture force")
	var battle: Node2D = _battle("dead_centre", 3, "counterweight")
	battle.player_entity().anchor_charge = 1.0
	battle.apply_power_impulse(battle.player_entity(), Vector2(-100, 0), {"owner_entity_id": 2, "owner_id": "rival", "expires_at": 1.0})
	_check(is_equal_approx(battle.player_entity().stored_force, 42.0) and Vector2(battle.player_entity().vel).length() < 15.0, "Hostile pressure force is stored and physically resisted by an anchored Counterweight")
	var previous: float = battle.player_entity().stored_force
	battle.apply_power_impulse(battle.player_entity(), Vector2(20, 0), {"owner_entity_id": 1, "owner_id": "player", "expires_at": 1.0})
	_check(battle.player_entity().stored_force == previous, "Own power impulses cannot create Counterweight resources")
	battle.free()

func _test_afterimage() -> void:
	for level: int in [1, 2]:
		var host: Host = _host("afterimage", level)
		var runtime: RefCounted = _runtime(host)
		host.entity(1).vel = Vector2(220, 0)
		host.entity(1).pos = Vector2(40, 0)
		host.entity(2).pos = Vector2(20, 8)
		runtime.after_movement()
		runtime.flush_contact_powers()
		_check(runtime.traces[0].rank == level and runtime.traces[0].has("mutation") and runtime.traces[0].has("energized"), "Trace carries escalation presentation state")
		_check(host.entity(2).vel.y == (12.0 if level == 1 else 24.0), "Rank II doubles useful lateral route pressure without fake damage")
		runtime.begin_tick(0.46)
		_check(runtime.traces.is_empty() if level == 1 else runtime.traces.size() == 1, "Rank II extends useful live route lifetime")
	var ghost_host: Host = _host("afterimage", 3, "ghost_circuit", Vector2(42, 0))
	ghost_host.entity(2).pos = Vector2.ZERO
	var ghost: RefCounted = _runtime(ghost_host)
	for tick: int in range(91):
		var angle: float = TAU * float(tick) / 90.0
		ghost.begin_tick(1.0 / 60.0)
		ghost_host.entity(1).pos = Vector2(cos(angle), sin(angle)) * 42.0
		ghost_host.entity(1).vel = Vector2(-sin(angle), cos(angle)) * 220.0
		ghost.after_movement()
		ghost.flush_contact_powers()
	_check(int(ghost.counters.get("ghost_closure", 0)) == 1, "Forgiving live orbit closes exactly one Ghost Circuit")
	_check(int(ghost.counters.get("ghost_activation", 0)) == 1 and Vector2(ghost_host.entity(2).vel).length() >= 65.0, "Closed circuit produces a physical pressure event inside the route")
	var energized: int = 0
	for trace: Dictionary in ghost.traces:
		if bool(trace.energized): energized += 1
	_check(energized >= 3, "Ghost closure energizes connected route segments")
	_check(ghost_host.entity(2).rpm == 1.0, "Ghost Circuit uses physical impulse instead of fabricated direct damage")
	var open_host: Host = _host("afterimage", 3, "ghost_circuit")
	var open: RefCounted = _runtime(open_host)
	for tick: int in range(90):
		open.begin_tick(1.0 / 60.0)
		open_host.entity(1).pos = Vector2(tick * 4, 0)
		open_host.entity(1).vel = Vector2(240, 0)
		open.after_movement()
	_check(int(open.counters.get("ghost_closure", 0)) == 0, "Straight open route cannot falsely close a circuit")
	var slip_host: Host = _host("afterimage", 3, "slipstream")
	var slip: RefCounted = _runtime(slip_host)
	var player: Dictionary = slip_host.entity(1)
	player.vel = Vector2(220, 0)
	player.pos = Vector2(40, 0)
	slip.after_movement()
	slip.begin_tick(0.35)
	player.pos = Vector2(20, 50)
	player.vel = Vector2(0, -200)
	player.wobble = 0.3
	slip.after_movement()
	player.pos = Vector2(20, 0)
	slip.after_movement()
	_check(int(slip.counters.get("slipstream_cross", 0)) == 1 and player.slipstream_time > 0.0, "Re-entering an aged live own route triggers Slipstream")
	_check(Vector2(player.vel).length() == 275.0 and is_equal_approx(player.wobble, 0.14), "Slipstream recovers momentum and reduces actual instability")
	var motion: Dictionary = slip.movement_control(player, Vector2.DOWN, false, 1.0 / 60.0)
	_check(float(motion.acceleration) == 1.65 and float(motion.drain) == 0.55, "Slipstream grants temporary acceleration and spin efficiency")
	slip.after_movement()
	_check(int(slip.counters.get("slipstream_cross", 0)) == 1, "Remaining on a path does not continuously farm crossings")
	slip.begin_tick(0.71)
	_check(player.slipstream_time == 0.0, "Slipstream movement benefit expires on active time")
	var fresh_host: Host = _host("afterimage", 3, "slipstream")
	var fresh: RefCounted = _runtime(fresh_host)
	fresh_host.entity(1).vel = Vector2(220, 0)
	fresh_host.entity(1).pos = Vector2(40, 0)
	fresh.after_movement()
	fresh.after_movement()
	_check(int(fresh.counters.get("slipstream_cross", 0)) == 0, "Fresh emission cannot count as immediate self-crossing")

func _test_caps_and_determinism() -> void:
	var first: Host = _host("afterimage", 3, "ghost_circuit", Vector2(42, 0))
	var second: Host = _host("afterimage", 3, "ghost_circuit", Vector2(42, 0))
	first.entity(2).pos = Vector2.ZERO
	second.entity(2).pos = Vector2.ZERO
	second.fighters.reverse()
	var a: RefCounted = _runtime(first)
	var b: RefCounted = _runtime(second)
	for tick: int in range(360):
		for pair: Array in [[first, a], [second, b]]:
			var host: Host = pair[0]
			var runtime: RefCounted = pair[1]
			var angle: float = TAU * float(tick) / 90.0
			runtime.begin_tick(1.0 / 60.0)
			host.entity(1).pos = Vector2(cos(angle), sin(angle)) * 42.0
			host.entity(1).vel = Vector2(-sin(angle), cos(angle)) * 220.0
			runtime.after_movement()
			runtime.flush_contact_powers()
	_check(a.events == b.events and first.impulses == second.impulses and a.traces == b.traces, "Escalation event/route/impulse results are deterministic under reversed fighter storage")
	_check(a.traces.size() <= Runtime.MAX_ESCALATED_TRACES and a.events.size() <= 256, "Long Ghost Circuit play stays inside route and event budgets")
	var battle: Node2D = _battle("dead_centre", 3, "bulwark")
	for index: int in range(80): battle.add_power_fx("bulwark_impact", Vector2.ZERO)
	_check(battle._power_fx.size() == 32, "Escalation visuals retain the existing bounded FX pool")
	battle.free()

func _test_unpaid_circuit_return() -> void:
	var host: Host = _host("afterimage", 3, "ghost_circuit")
	var runtime: RefCounted = _runtime(host)
	var player: Dictionary = host.entity(1)
	# Draw two legs of a large open L at legal trace-producing speed.
	for tick: int in range(46):
		runtime.begin_tick(1.0 / 60.0)
		player.pos = Vector2(float(tick) * 220.0 / 60.0, 0)
		player.vel = Vector2(220, 0)
		runtime.after_movement()
	for tick: int in range(46):
		runtime.begin_tick(1.0 / 60.0)
		player.pos = Vector2(165, float(tick) * 220.0 / 60.0)
		player.vel = Vector2(0, 220)
		runtime.after_movement()
	var paid_count: int = int(runtime.counters.get("afterimage", 0))
	var endpoint: Vector2 = player.pos
	# A slow diagonal return does not pay for or draw the closing third leg.
	for tick: int in range(91):
		runtime.begin_tick(1.0 / 60.0)
		player.pos = endpoint.lerp(Vector2.ZERO, float(tick) / 90.0)
		player.vel = -endpoint.normalized() * 150.0
		runtime.after_movement()
	_check(int(runtime.counters.get("afterimage", 0)) == paid_count and not runtime.traces.is_empty(), "Open paid arc remains live during an unpaid low-speed return")
	_check(int(runtime.counters.get("ghost_closure", 0)) == 0 and int(runtime.counters.get("ghost_activation", 0)) == 0, "Undrawn slow return cannot turn an open route into a damaging circuit")
	player.vel = Vector2(220, 0)
	runtime._close_circuit(player)
	_check(int(runtime.counters.get("ghost_closure", 0)) == 0, "Closure detector rejects a gap from last paid tail to reset current buffer")
	runtime.after_movement()
	_check(int(runtime.counters.get("ghost_closure", 0)) == 0, "Resuming fast movement at old route start cannot inherit an undrawn closing chord")
