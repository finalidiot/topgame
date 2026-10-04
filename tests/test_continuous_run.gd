extends SceneTree
## Architectural fixtures assert lifecycle invariants; no balance claims.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
const Fixtures = preload("res://tests/continuous_fixtures.gd")
const Battle = preload("res://scripts/battle.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: int = 0
var launches: int = 0
var results: int = 0
func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func make_game() -> QuietMain:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.battle.set_physics_process(false)
	game.battle.event_sfx.connect(func(kind: String) -> void:
		if kind == "launch": launches += 1)
	game.battle.round_finished.connect(func(_result: Dictionary) -> void: results += 1)
	game.collection.initialize_starter("bastion")
	game._action("start_run")
	claim(game)
	game.battle.set_physics_process(false)
	return game
func claim(game: QuietMain) -> void:
	var id: String = game.run_context.pending_draft_id
	game._action("choose_power", {"encounter_id":id,"power_id":game.run_context.pending_offer[0],"run_seed":game.run_context.run_seed})
	if game.screen == "mutation":
		game._action("choose_mutation", {"encounter_id":id,"branch_id":game.run_context.pending_mutation_offer[0],"run_seed":game.run_context.run_seed})
	game._process(1.1)
func settle_drafts(game: QuietMain) -> void:
	if game.screen == "level_up": game._process(0.2)
	while game.screen in ["reward", "mutation"]: claim(game)
func physical(b: Node) -> Dictionary:
	return {"player":b.player_entity().duplicate(true),"elapsed":b.elapsed,
		"power_time":b.powers.time,"state":b.powers._states.duplicate(true),
		"traces":b.powers.traces.duplicate(true),"schedule":b.swarm.schedule.duplicate(true),
		"run":b.continuous.snapshot(),"economy":b.continuous.economy.snapshot(),"entities":b.snapshot().entities}
func _run() -> void:
	_test_continuity()
	_test_defeat_and_duel()
	_test_rpm_and_clock()
	_test_long_lifecycle()
	print("CONTINUOUS_RUN_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
func _test_continuity() -> void:
	launches = 0
	results = 0
	var game: QuietMain = make_game()
	var b: Node2D = game.battle
	for tick: int in range(200): b.test_step(Battle.FIXED_DT)
	check(launches == 1 and b.battle_status == "battle", "One initial launch starts the continuous arena")
	var player: Dictionary = b.player_entity()
	var runtime_id: int = b.powers.get_instance_id()
	# Real claim path, with an explicit XP fixture for controlled timing.
	var events: Array = []
	for id: int in range(6):
		events.append({"kind":"elimination","encounter_id":b.encounter.id,"time":b.elapsed,"entity_id":1000+id,"combatant_type":"small_top","reason":"impact","player_attributed":true})
	game._progression_events(events)
	check(game.screen == "level_up" and game.run_context.level == 2, "XP earns a level without an encounter boundary")
	game._process(0.2)
	var frozen: Dictionary = physical(b)
	for tick: int in range(600): b.test_step(Battle.FIXED_DT, Vector2.RIGHT, true, true)
	check(physical(b) == frozen, "Draft freezes player, surviving enemy, power timers, run timer and director")
	var spent: Dictionary = b.powers._state(player)
	spent.second_wind_used = true
	player.second_wind_used = true
	claim(game)
	check(game.screen == "battle" and game.run_context.level == 2 and b.powers.get_instance_id() == runtime_id, "Claim returns to the same live simulation")
	check(b.powers._state(player).second_wind_used and player.powers == game.run_context.owned_power_ids, "Investment retains spent recovery and installs current ownership")
	player.pos = Vector2(40,-20)
	player.vel = Vector2(37,-13)
	player.rpm = 0.66
	player.energy = 0.66
	player.wobble = 0.42
	player.cooldown = 2.3
	player.stored_force = 17.0
	player.anchor_charge = 0.4
	spent.comet_until = b.powers.time + 2.0
	spent.trace_path = [Vector2(10,10),Vector2(40,-20)]
	var ownership: Array = game.run_context.owned_power_ids
	var xp: Dictionary = game.run_context.progression_snapshot()
	var seen_ids: Dictionary = {1:true,2:true}
	var stale: Dictionary = b.entity(2)
	for threat: int in range(1, 13):
		check(b.continuous.threat_number == threat and game.run_context.slot == threat, "Context and live threat stay synchronized")
		Fixtures.resolve_threat(game)
		check(game.screen == "battle" and b.battle_status == "battle" and results == 0, "Ordinary clear emits no terminal result")
		var before: Dictionary = player.duplicate(true)
		var power_state: Dictionary = b.powers._state(player).duplicate(true)
		var run_time: float = b.elapsed
		b.continuous._spawn_next()
		check(is_same(player,b.player_entity()) and player == before, "Threat entry preserves the identical player dictionary and every field")
		check(b.powers._state(player) == power_state and b.powers.get_instance_id() == runtime_id and b.elapsed == run_time, "Threat entry preserves internal powers, cooldowns and survival clock")
		check(game.run_context.progression_snapshot() == xp and game.run_context.owned_power_ids == ownership, "XP, level and investments survive all transitions")
		check(game.run_context.selected_build == Starters.build_for("bastion") and player.starter_id == "bastion", "Build and starter identity persist")
		if b.swarm.enabled:
			check(b.swarm.schedule.size() == 24 and b.swarm.active_cap == 12, "Swarm follows prior rivals with original population/cap")
			for entry: Dictionary in b.swarm.schedule:
				check(not seen_ids.has(int(entry.id)), "Every repeated swarm reserves fresh deterministic IDs")
				seen_ids[int(entry.id)] = true
		else:
			var enemy: Dictionary = b._hud_enemy()
			check(not seen_ids.has(int(enemy.entity_id)), "New full rivals never reuse a retired ID")
			seen_ids[int(enemy.entity_id)] = true
			check(Vector2(enemy.pos).distance_to(player.pos) >= 60.0, "New rival enters safely away from player")
		# Explicitly retire fixture corpses; normal tick timing covered below.
		for f: Dictionary in b.fighters:
			if f.team_id == "hostile" and not str(f.outcome).is_empty(): f.out_time = 1.0
		b.continuous._cleanup(0.0)
	check(game.run_context.is_active() and game.run_context.slot == 13 and launches == 1, "One launch continues beyond the previous eight-threat limit")
	stale.outcome = ""
	var old_velocity: Vector2 = stale.vel
	var no_event_count: int = b._progression_queue.size()
	b._progression_contact(player, stale, 1.0)
	b.apply_power_impulse(stale,Vector2(90,0),{})
	check(b._progression_queue.size() == no_event_count and b.entity(2).is_empty() and stale.vel == old_velocity, "Removed enemy references cannot produce new XP/impulses")
	game._round_finished({"won":false,"continuous_run":true,"run_seed":game.run_context.run_seed,"encounter_id":"run_slot_01"})
	game._threat_cleared({"id":"run_slot_01","seed":1,"run_seed":game.run_context.run_seed})
	game._threat_started({"id":"run_slot_02","seed":1,"run_seed":game.run_context.run_seed,"threat":2})
	check(game.screen == "battle" and game.run_context.slot == 13, "Stale result/clear/entry callbacks cannot terminate or advance later threats")
	var preserved: Dictionary = physical(b)
	game._launch_run_encounter()
	check(physical(b) == preserved, "Repeated launch request cannot recreate a live Run")
	game.free()
func _test_defeat_and_duel() -> void:
	for reason: String in ["spin_out", "ring_out"]:
		var game: QuietMain = make_game()
		var old_enemy: Dictionary = game.battle.entity(2)
		Fixtures.resolve_threat(game)
		check(game.battle.continuous.phase == "breathing", "Clear enters a live breathing period")
		Fixtures.defeat_player(game,reason)
		check(game.screen == "result" and game.run_context.status == "failed", "Player defeat ends Run even after the threat was already committed")
		check(game.last_result.threats_cleared == 1 and game.last_result.rivals_defeated == 1 and game.last_result.level == 1, "Run result reports accumulated clear counts and level")
		check(game.last_result.owned_power_ids == game.run_context.owned_power_ids and game.last_result.has("survival_time"), "Run result retains build powers and active survival time")
		var old_result: Dictionary = game.battle.last_result.duplicate(true)
		game._action("restart_run")
		claim(game)
		game._round_finished(old_result)
		old_enemy.outcome = ""
		var old_velocity: Vector2 = old_enemy.vel
		var events_before: int = game.battle._progression_queue.size()
		game.battle._progression_contact(game.battle.player_entity(), old_enemy, 1.0)
		game.battle.apply_power_impulse(old_enemy, Vector2(20,0), {})
		check(old_enemy.vel == old_velocity and game.battle._progression_queue.size() == events_before, "Stale enemy object cannot reuse a newly restarted Run's numerical ID")
		check(game.screen == "battle" and game.run_context.is_active(), "Previous Run loss cannot terminate restarted player")
		game._pause()
		game._action("end_run")
		game._action("quick_duel")
		check(game.battle.continuous == null, "Quick Duel uses original single-battle runtime")
		game.battle.battle_status = "battle"
		game.battle.entity(2).rpm = 0.0
		game.battle._check_result()
		game.battle._update_finish(3.0)
		check(game.screen == "result" and game.last_result.won, "Quick Duel still reaches a normal victory/rematch result")
		game.free()
func _test_rpm_and_clock() -> void:
	var game: QuietMain = make_game()
	var b: Node2D = game.battle
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	p.rpm = 0.8
	b.spend_rpm(p,0.1,"burst")
	check(is_equal_approx(p.rpm,0.7), "Continuous Run charges the entire explicit cost without the old 12% discount")
	b.gain_rpm(p,0.05,"combat_reclamation")
	check(is_equal_approx(p.rpm,0.75), "Explicit earned recovery is accounted independently of spending")
	p.rpm = 0.85
	Fixtures.resolve_threat(game)
	var before: float = b.elapsed
	b.set_paused(true)
	for tick: int in range(120): b.test_step(Battle.FIXED_DT)
	check(b.elapsed == before and b.continuous.threat_number == 1, "Pause freezes survival and breathing clocks")
	b.set_paused(false)
	for tick: int in range(119): b.test_step(Battle.FIXED_DT)
	check(b.continuous.threat_number == 1 and b.elapsed > before and p.rpm < 0.85, "Breathing keeps physics/spin/time alive and respects delay")
	for tick: int in range(240):
		if b.continuous.threat_number == 2: break
		b.test_step(Battle.FIXED_DT)
	check(b.continuous.threat_number == 2 and b.battle_status == "battle", "Next rival enters after the seeded breathing interval and entry warning")
	check(b.entity(2).is_empty() and not b.powers._states.has(2), "Retirement releases corpse, AI and semantic enemy state")
	# Ensure long elapsed time cannot immediately clean up a newly introduced swarm.
	b.elapsed = 200.0
	b.powers.time = 200.0
	Fixtures.next_threat(game)
	check(b.swarm.enabled and is_zero_approx(b.threat_elapsed()), "Late swarm starts a fresh local schedule at accumulated Run time")
	for tick: int in range(100): b.test_step(Battle.FIXED_DT)
	settle_drafts(game)
	check(b.swarm.spawned > 0 and not b.swarm.cleanup_used and b.elapsed >= 201.0, "Late swarm spawns normally instead of inheriting an expired cleanup clock")
	game.free()
func _test_long_lifecycle() -> void:
	var game: QuietMain = make_game()
	var b: Node2D = game.battle
	b.battle_status = "battle"
	for index: int in range(200):
		Fixtures.next_threat(game)
		for f: Dictionary in b.fighters:
			if f.team_id == "hostile" and not str(f.outcome).is_empty(): f.out_time = 1.0
		b.continuous._cleanup(0.0)
	check(game.run_context.slot == 201 and game.run_context.is_active(), "Script repeats for hundreds of threats without a Run-clear state")
	check(b.fighters.size() <= 2 and b._ai_rngs.size() <= 2 and b.powers._states.size() <= 2 and game.run_context.committed_results.size() <= 1, "Enemy/runtime/claim memory stays bounded as threat count grows")
	game.free()
