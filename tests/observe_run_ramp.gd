extends SceneTree
## Actual Main XP/drafts and unchanged fixed combat. Only assembly/policy are fixtures.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _hud_updated(_stats: Dictionary) -> void: pass
	func _battle_sound(_kind: String) -> void: pass
const Battle = preload("res://scripts/battle.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const Powers = preload("res://scripts/run_powers.gd")
const CASES: Array[Dictionary] = [
	{"id":"bastion", "starter":"bastion", "style":"defensive", "build":{"blade":"guard","ratchet":"low","bit":"ball"}},
	{"id":"breaker", "starter":"breaker", "style":"aggressive", "build":{"blade":"smash","ratchet":"high","bit":"flat"}},
	{"id":"vane", "starter":"vane", "style":"hybrid", "build":{"blade":"balance","ratchet":"mid","bit":"needle"}},
	{"id":"custom_defence", "starter":"custom", "style":"defensive", "build":{"blade":"hammerfall","ratchet":"ballast","bit":"tripod"}}]
var seeds: Array[int] = [421, 7341, 2026]
var horizon: float = 600.0
var output: String = ""
var collection_prefix: String = ""
var selected_case: String = ""

static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x, value.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = portable(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(portable(item))
		return result
	return value

func _initialize() -> void: call_deferred("run")

func choose(game: QuietMain, context: Dictionary, drafts: Array[Dictionary]) -> void:
	var preferences: Array[String] = ["redline","high_gear","impact_wake","iron_comet","clutch","chain_impact","crosscut"]
	if context.style == "defensive": preferences = ["dead_centre","impact_sink","anchor_exchange","crash_guard","clutch","momentum_bank","gyro_lock"]
	elif context.style == "hybrid": preferences = ["afterimage","orbit_drive","high_gear","impact_wake","clutch","crash_guard","dead_centre"]
	var choice: String = str(game.run_context.pending_offer[0])
	var score: float = -INF
	for offered: String in game.run_context.pending_offer:
		var preference: int = preferences.find(offered)
		var owned: int = int(game.run_context.power_ranks.get(offered, 0))
		var candidate: float = 16.0 - preference if preference >= 0 else 0.0
		if owned > 0 and preference >= 0: candidate += 8.0 + owned * 2.0
		if candidate > score: choice = offered; score = candidate
	var row: Dictionary = {"time":game.battle.elapsed, "level":game.run_context.level, "offer":game.run_context.pending_offer.duplicate(), "choice":choice, "claim":game.run_context.pending_draft_id, "total_xp":game.run_context.progression_snapshot().total_xp}
	game._action("choose_power", {"encounter_id":game.run_context.pending_draft_id,"power_id":choice,"run_seed":game.run_context.run_seed,"offer_revision":game.run_context.reroll_snapshot().revision})
	if game.screen == "mutation":
		var branch: String = str(game.run_context.pending_mutation_offer[0])
		if context.style == "defensive" and "bulwark" in game.run_context.pending_mutation_offer: branch = "bulwark"
		row["mutation_offer"] = game.run_context.pending_mutation_offer.duplicate()
		row["mutation"] = branch
		game._action("choose_mutation", {"encounter_id":game.run_context.pending_draft_id,"branch_id":branch,"run_seed":game.run_context.run_seed})
	row["ranks_after"] = game.run_context.power_ranks.duplicate(true)
	drafts.append(row)
	game._process(1.1)
	game.battle.set_physics_process(false)

func observe(context: Dictionary, seed_value: int) -> Dictionary:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	game.qa_task_id = "003A.1"
	game.collection_path = collection_prefix + "_" + str(context.id) + "_" + str(seed_value) + ".json"
	assert(not FileAccess.file_exists(game.collection_path), "Refuse existing QA collection")
	root.add_child(game)
	game.set_process(false)
	game.run_context.start(context.build, seed_value, str(context.starter))
	game.mode = "run"
	game._show_reward()
	var drafts: Array[Dictionary] = []
	choose(game, context, drafts)
	var b: Node2D = game.battle
	b.set_physics_process(false)
	b.particles_enabled = false
	var row: Dictionary = {"id":context.id,"context":context.duplicate(true),"seed":seed_value,"drafts":drafts,"entries":[{"time":0.0,"kind":"rival","key":"hunter","level":1}],"clears":[],"contacts":[],"commits":[],"trace":[],"first_contact":-1.0,"first_meaningful_contact":-1.0,"first_commit":-1.0,"first_specialist":-1.0,"first_swarm":-1.0,"first_elite":-1.0,"first_boss":-1.0,"first_overlap":-1.0,"longest_empty_gap":0.0,"longest_low_pressure_gap":0.0,"longest_contact_gap":0.0,"peak_full":1,"peak_small":0,"pressure_integral":0.0,"full_integral":0.0,"small_integral":0.0,"quiet_seconds":0.0,"low_pressure_seconds":0.0,"actual_seconds":0.0}
	b.threat_started.connect(func(event: Dictionary) -> void:
		row.entries.append({"time":b.elapsed,"kind":event.kind,"key":event.key,"level":game.run_context.level,"rpm":b.player_entity().rpm})
		for kind: String in ["specialist","swarm","elite","boss"]:
			if event.kind == kind and float(row["first_" + kind]) < 0.0: row["first_" + kind] = b.elapsed)
	b.threat_cleared.connect(func(event: Dictionary) -> void:
		row.clears.append({"time":b.elapsed,"kind":event.kind,"key":event.key,"duration":event.duration,"earned":event.get("reward_eligible",false),"level":game.run_context.level}))
	b.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		if int(event.first_entity_id) != 1 and int(event.second_entity_id) != 1: return
		row.contacts.append({"time":b.elapsed,"severity":event.severity,"level":game.run_context.level})
		if row.first_contact < 0.0: row.first_contact = b.elapsed
		if row.first_meaningful_contact < 0.0 and float(event.severity) >= 0.22: row.first_meaningful_contact = b.elapsed)
	var p: Dictionary = b.player_entity()
	var previous_commit: Dictionary = {}
	var previous_time: float = 0.0
	var empty_gap: float = 0.0
	var low_gap: float = 0.0
	var last_contact: float = 0.0
	var next_trace: float = 0.0
	var direction: Vector2 = Vector2.ZERO
	var brake: bool = false
	var tick: int = 0
	while b.elapsed < horizon and game.screen != "result" and tick < int(horizon * 120.0) + 1200:
		var burst: bool = false
		if tick % 12 == 0:
			var input: Dictionary = Bot.input(b, str(context.style), tick)
			direction = input.direction
			brake = input.brake
			burst = input.burst
		b.test_step(Battle.FIXED_DT, direction, burst, brake)
		assert(is_same(p, b.player_entity()), "No player replacement during natural Run")
		if game.screen == "level_up": game._process(0.2)
		while game.screen == "reward": choose(game, context, drafts)
		# Menu/time progression is actual Main. No pause-state or clock override.
		if game.screen == "acquisition": game._process(0.1)
		var dt: float = maxf(0.0, b.elapsed - previous_time)
		previous_time = b.elapsed
		var c: Dictionary = b.continuous.census()
		var full: int = int(c.active_full)
		var small: int = b.swarm.active_count()
		row.actual_seconds += dt
		row.pressure_integral += float(c.pressure) * dt
		row.full_integral += full * dt
		row.small_integral += small * dt
		empty_gap = empty_gap + dt if full + small == 0 else 0.0
		low_gap = low_gap + dt if full + small <= 1 else 0.0
		row.quiet_seconds += dt if full + small == 0 else 0.0
		row.low_pressure_seconds += dt if full + small <= 1 else 0.0
		row.longest_empty_gap = maxf(row.longest_empty_gap, empty_gap)
		row.longest_low_pressure_gap = maxf(row.longest_low_pressure_gap, low_gap)
		if not row.contacts.is_empty(): last_contact = float(row.contacts.back().time)
		row.longest_contact_gap = maxf(row.longest_contact_gap, b.elapsed - last_contact)
		row.peak_full = maxi(row.peak_full, full)
		row.peak_small = maxi(row.peak_small, small)
		if row.first_overlap < 0.0 and full + small > 1: row.first_overlap = b.elapsed
		for f: Dictionary in b.fighters:
			if f.team_id != "hostile" or str(f.outcome) != "" or f.combatant_type != "full_top": continue
			var cycle: int = int(f.get("role_commit_cycle", -1))
			if str(f.get("role_attack_state", "")) == "committed" and cycle != int(previous_commit.get(int(f.entity_id), -1)):
				previous_commit[int(f.entity_id)] = cycle
				row.commits.append({"time":b.elapsed,"entity":f.entity_id,"role":f.role,"kind":f.enemy_kind,"cycle":cycle})
				if row.first_commit < 0.0: row.first_commit = b.elapsed
		if b.elapsed >= next_trace:
			var investment: int = 0
			for value: int in game.run_context.power_ranks.values(): investment += value
			row.trace.append({"time":b.elapsed,"rpm":p.rpm,"wobble":p.wobble,"radius":Vector2(p.pos).length(),"tier":b.continuous.director.tier_at(b.elapsed),"pressure":c.pressure,"full":full,"small":small,"level":game.run_context.level,"total_xp":game.run_context.progression_snapshot().total_xp,"investments":investment,"draining":b.continuous.director.draining})
			next_trace = b.elapsed + 1.0
		tick += 1
	row.merge({"elapsed":b.elapsed,"simulation_ticks":tick,"ended_naturally":b.battle_status == "finished","reason":b.last_result.get("reason","observation_horizon"),"level":game.run_context.level,"powers":game.run_context.owned_power_ids.duplicate(),"ranks":game.run_context.power_ranks.duplicate(true),"mutations":game.run_context.power_mutations.duplicate(true),"director_history":b.continuous.director.history.duplicate(true),"economy":b.continuous.economy.snapshot(),"remaining_rpm":p.rpm,"draft_count":drafts.size(),"threats_cleared":b.continuous.threats_cleared})
	row["average_pressure"] = float(row.pressure_integral) / maxf(0.001, float(row.actual_seconds))
	row["average_full"] = float(row.full_integral) / maxf(0.001, float(row.actual_seconds))
	row["average_small"] = float(row.small_integral) / maxf(0.001, float(row.actual_seconds))
	row["commits_per_minute"] = row.commits.size() * 60.0 / maxf(0.001, float(row.actual_seconds))
	print("NATURAL_RAMP ", context.id, " seed=", seed_value, " elapsed=", snappedf(b.elapsed, 0.01), " level=", row.level, " elite=", snappedf(row.first_elite,0.01), " boss=", snappedf(row.first_boss,0.01), " pressure=", snappedf(row.average_pressure,0.01), " reason=", row.reason)
	game.free()
	return row

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
		if arg.begins_with("--collection-prefix="): collection_prefix = arg.trim_prefix("--collection-prefix=")
		if arg.begins_with("--horizon="): horizon = clampf(float(arg.trim_prefix("--horizon=")), 30.0, 1200.0)
		if arg.begins_with("--case="): selected_case = arg.trim_prefix("--case=")
		if arg.begins_with("--seed="): seeds = [int(arg.trim_prefix("--seed="))]
	assert(output.is_absolute_path() and collection_prefix.is_absolute_path() and not FileAccess.file_exists(output))
	var runs: Array[Dictionary] = []
	for context: Dictionary in CASES:
		if not selected_case.is_empty() and context.id != selected_case: continue
		for seed_value: int in seeds:
			runs.append(observe(context, seed_value))
			var checkpoint: FileAccess = FileAccess.open(output + ".partial", FileAccess.WRITE)
			checkpoint.store_string(JSON.stringify(portable({"horizon":horizon,"runs":runs}), "\t"))
			checkpoint.close()
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(portable({"schema":"003a1-natural-earned-run-ramp-v1","scope":"Actual Main Run, natural physics/AI/Director, legal sampled bot controls and ordinary seeded offered/earned drafts. Only starting assembly and input/preference policy are fixtures; no powers/enemies/XP/RPM/outcomes injected, no threat clock jumps, no save/economy acceptance claim.","horizon":horizon,"runs":runs}), "\t"))
	file.close()
	print("NATURAL_RAMP_STUDY_PASS runs=", runs.size())
	quit()
