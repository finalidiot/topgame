extends SceneTree
## Declared invested-build fixture; every observed tick uses production physics,
## AI, natural Director admission and RPM accounting. No save access, scripted
## outcomes, reserve top-ups, forced enemies or hidden threat-clock advances.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const POWER_IDS: Array[String] = ["dead_centre", "crash_guard", "clutch", "momentum_bank", "impact_wake", "iron_comet", "crosscut"]
const RANKS: Dictionary = {"dead_centre":3, "crash_guard":2, "clutch":2, "momentum_bank":2, "impact_wake":2, "iron_comet":2, "crosscut":2}
var horizon: float = 660.0
var seeds: Array[int] = [421, 7341, 205252]
var policies: Array[String] = ["zero_input", "active_centre"]
var output: String = ""
var branch: String = "bulwark"
var director_investments: int = 15
var samples: Array[Dictionary] = []

func _initialize() -> void: call_deferred("_run")

func make_battle(seed_value: int) -> Node2D:
	var b: Node2D = Battle.new()
	root.add_child(b)
	b.set_physics_process(false)
	var d: Dictionary = Encounters.for_run_event(1, seed_value)
	d.starter_id = "bastion"
	d.player_power_ids = POWER_IDS.duplicate()
	d.player_power_ranks = RANKS.duplicate()
	d.player_power_mutations = {"dead_centre":branch}
	b.begin_run(Starters.build_for("bastion"), d, seed_value)
	b.continuous.progression_level = director_investments
	b.battle_status = "battle"
	b.player_entity().pos = Vector2.ZERO
	b.player_entity().vel = Vector2.ZERO
	b.entity(2).vel = b.entity(2).launch_velocity
	return b

func controls(b: Node2D, policy: String, tick: int) -> Dictionary:
	if policy == "zero_input": return {"direction":Vector2.ZERO, "burst":false, "brake":false}
	return Bot.input(b, "defensive", tick)

func observe(seed_value: int, policy: String) -> Dictionary:
	var b: Node2D = make_battle(seed_value)
	var p: Dictionary = b.player_entity()
	var row: Dictionary = {"seed":seed_value, "policy":policy, "branch":branch,"director_investments":director_investments, "fixture":"maximum seven-family invested Bastion placed at centre once; production physics thereafter", "trace":[], "impacts":[], "peak_full":0, "peak_small":0, "peak_radius":0.0, "centre_seconds":0.0, "outside_centre_seconds":0.0, "input_seconds":0.0, "burst_presses":0, "brake_seconds":0.0, "finite":true, "overlap_contacts":0, "drain_seconds":0.0}
	var tick: int = 0
	var next_sample: float = 0.0
	var previous_contact: float = -INF
	var sectors: Dictionary = {}
	b.contact_accepted.connect(func(a: int, c: int) -> void:
		if a != 1 and c != 1: return
		var enemy: Dictionary = b.entity(c if a == 1 else a)
		if enemy.is_empty(): return
		var delta: Vector2 = Vector2(enemy.pos)-Vector2(p.pos)
		var angle: int = floori(fposmod(delta.angle(), TAU)/TAU*8.0)
		sectors[angle] = true
		if row.impacts.size() < 2048:
			row.impacts.append({"time":snappedf(b.elapsed,0.01), "id":enemy.entity_id, "kind":enemy.get("enemy_kind","swarm"), "role":enemy.get("role","swarm"), "sector":angle, "speed":snappedf(Vector2(enemy.vel).length(),0.1), "severity":snappedf(float(enemy.impact_strength),0.01), "player_radius":snappedf(Vector2(p.pos).length(),0.1)})
	)
	var last_contacts: int = 0
	while b.battle_status == "battle" and b.elapsed < horizon and tick < int(horizon*90):
		var c: Dictionary = controls(b,policy,tick)
		var before_time: float = b.elapsed
		b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		var combat_dt: float = b.elapsed-before_time
		if Vector2(c.direction).length() > 0.01: row.input_seconds += combat_dt
		if c.burst: row.burst_presses += 1
		if c.brake: row.brake_seconds += combat_dt
		if b.continuous.director.draining: row.drain_seconds += combat_dt
		var radius: float = Vector2(p.pos).length()
		row.peak_radius = maxf(row.peak_radius,radius)
		if radius <= 58.0: row.centre_seconds += combat_dt
		else: row.outside_centre_seconds += combat_dt
		row.finite = row.finite and Vector2(p.pos).is_finite() and Vector2(p.vel).is_finite() and is_finite(float(p.rpm))
		var census: Dictionary = b.continuous.census()
		row.peak_full = maxi(row.peak_full,int(census.active_full))
		row.peak_small = maxi(row.peak_small,b.swarm.active_count())
		if row.impacts.size() > last_contacts:
			if b.elapsed-previous_contact < 0.9: row.overlap_contacts += 1
			previous_contact = b.elapsed
			last_contacts = row.impacts.size()
		if b.elapsed >= next_sample:
			row.trace.append({"time":snappedf(b.elapsed,0.01), "rpm":snappedf(float(p.rpm),0.001), "radius":snappedf(radius,0.1), "speed":snappedf(Vector2(p.vel).length(),0.1), "full":census.active_full, "small":b.swarm.active_count(), "pressure":snappedf(float(census.pressure),0.1), "tier":b.continuous.director.tier_at(b.elapsed), "draining":b.continuous.director.draining, "anchor":snappedf(float(p.anchor_charge),0.01), "direction":[snappedf(float(c.direction.x),0.01),snappedf(float(c.direction.y),0.01)], "brake":c.brake, "burst":c.burst})
			next_sample += 5.0
		tick += 1
	row.merge({"survival_seconds":b.elapsed, "reason":b.last_result.get("reason","observation_horizon"), "ended_naturally":b.battle_status == "finished", "rpm":p.rpm, "wobble":p.wobble, "hits":b.hits, "sectors_hit":sectors.size(), "director":b.continuous.director.history.duplicate(true), "economy":b.continuous.economy.snapshot(), "power_procs":b.powers.counters.duplicate(), "roster_procs":b.roster.counters.duplicate(), "simulation_ticks":tick})
	print("DEFENCE_OBSERVATION seed=%d policy=%s seconds=%.2f reason=%s rpm=%.3f radius=%.1f impacts=%d sectors=%d" % [seed_value,policy,b.elapsed,row.reason,p.rpm,row.peak_radius,row.impacts.size(),sectors.size()])
	b.free()
	return row

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
		if arg.begins_with("--horizon="): horizon = clampf(float(arg.trim_prefix("--horizon=")),10.0,1200.0)
		if arg.begins_with("--seed="): seeds = [int(arg.trim_prefix("--seed="))]
		if arg.begins_with("--policy="): policies = [arg.trim_prefix("--policy=")]
		if arg.begins_with("--branch="): branch = arg.trim_prefix("--branch=")
		if arg.begins_with("--investments="): director_investments = clampi(int(arg.trim_prefix("--investments=")),1,30)
	if output.is_empty() or not output.is_absolute_path(): push_error("An explicit external report path is required"); quit(2); return
	for seed_value: int in seeds:
		for policy: String in policies: samples.append(observe(seed_value,policy))
	var report: Dictionary = {"scope":"Declared invested-build fixture with natural Director and production physics; no save, fake death, reserve top-up, injected enemies or threat-time jump.", "horizon_seconds":horizon, "power_ids":POWER_IDS, "ranks":RANKS, "samples":samples}
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Cannot write external report"); quit(2); return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	quit(0)
