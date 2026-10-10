extends SceneTree
## Same external observer runs against frozen before/after production projects.
## Only starting assemblies, sampled input and draft preferences are fixtures.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _hud_updated(_stats: Dictionary) -> void: pass
	func _battle_sound(_kind: String) -> void: pass

class CountingEconomy extends "res://scripts/spin_economy.gd":
	var detailed_losses: Dictionary = {}
	var detailed_gains: Dictionary = {}
	var spend_calls: Dictionary = {}
	func spend(f: Dictionary, amount: float, source: String) -> void:
		var before: float = float(f.rpm)
		var is_player: bool = player(f)
		var category: String = source
		# Debug call stacks classify the old collapsed power ledger without any
		# production edits or extra writes. Analysis is never in live gameplay.
		if source == "powers":
			for frame: Dictionary in get_stack():
				var method: String = str(frame.get("function", ""))
				if method in ["_modern_tick", "_modern_burst", "_modern_end_redline", "_end_redline"]:
					category = "redline"
					break
		super.spend(f, amount, source)
		if is_player:
			detailed_losses[category] = float(detailed_losses.get(category, 0.0)) + before - float(f.rpm)
			spend_calls[category] = int(spend_calls.get(category, 0)) + 1 if amount > 0.0 else int(spend_calls.get(category, 0))
	func gain(f: Dictionary, amount: float, source: String, small: bool = false) -> float:
		var actual: float = super.gain(f, amount, source, small)
		if actual > 0.0: detailed_gains[source] = float(detailed_gains.get(source, 0.0)) + actual
		return actual

const Battle = preload("res://scripts/battle.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const CASES: Array[Dictionary] = [
	{"id":"breaker", "starter":"breaker", "style":"aggressive", "build":{"blade":"smash","ratchet":"high","bit":"flat"}},
	{"id":"bastion", "starter":"bastion", "style":"defensive", "build":{"blade":"guard","ratchet":"low","bit":"ball"}},
	{"id":"vane", "starter":"vane", "style":"hybrid", "build":{"blade":"hook","ratchet":"mid","bit":"rubber"}},
	{"id":"custom_aggressive", "starter":"custom", "style":"aggressive", "build":{"blade":"hammerfall","ratchet":"kickback","bit":"chisel"}},
	{"id":"custom_defensive", "starter":"custom", "style":"defensive", "build":{"blade":"outrigger","ratchet":"ballast","bit":"tripod"}}]
var seeds: Array[int] = [421, 7341, 2026]
var horizon: float = 600.0
var output: String = ""
var collection_prefix: String = ""
var selected_case: String = ""

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
	var row: Dictionary = {"time":game.battle.elapsed, "level":game.run_context.level, "offer":game.run_context.pending_offer.duplicate(), "choice":choice}
	game._action("choose_power", {"encounter_id":game.run_context.pending_draft_id,"power_id":choice,"run_seed":game.run_context.run_seed,"offer_revision":game.run_context.reroll_snapshot().revision})
	if game.screen == "mutation":
		var branch: String = str(game.run_context.pending_mutation_offer[0])
		if context.style == "defensive" and "bulwark" in game.run_context.pending_mutation_offer: branch = "bulwark"
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
	var e: CountingEconomy = CountingEconomy.new()
	e.setup(b)
	b.continuous.economy = e
	var p: Dictionary = b.player_entity()
	var row: Dictionary = {"id":context.id,"context":context.duplicate(true),"seed":seed_value,"drafts":drafts,"trace":[],"contacts":0,"meaningful_contacts":0,"seconds_above_90":0.0,"seconds_above_75":0.0,"seconds_below_50":0.0,"seconds_below_25":0.0,"controlled_seconds":0.0,"braking_seconds":0.0,"venting_seconds":0.0,"burst_requests":0,"max_speed":0.0,"max_radius":0.0,"starting_rpm":float(p.rpm),"minimum_rpm":float(p.rpm)}
	b.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		if int(event.first_entity_id) != 1 and int(event.second_entity_id) != 1: return
		row.contacts += 1
		if float(event.severity) >= 0.32: row.meaningful_contacts += 1)
	var tick: int = 0
	var previous_time: float = 0.0
	var next_trace: float = 0.0
	var direction: Vector2 = Vector2.ZERO
	var brake: bool = false
	var recovering: bool = false
	while b.elapsed < horizon and game.screen != "result" and tick < int(horizon * 120.0) + 1200:
		var burst: bool = false
		if tick % 12 == 0:
			var input: Dictionary = Bot.input(b, str(context.style), tick)
			direction = input.direction
			brake = input.brake
			burst = input.burst
			if context.style == "defensive":
				if float(p.get("anchor_stress", 0.0)) >= 0.80: recovering = true
				if recovering and float(p.get("anchor_stress", 0.0)) <= 0.30 and not bool(b.powers.public_state(p).anchor.get("overloaded", false)): recovering = false
				if recovering:
					var world: Vector2 = Vector2(p.pos)
					var aim: Vector2 = world.orthogonal().normalized() * 0.5 + world.normalized() * clampf((105.0 - world.length()) / 30.0, -0.7, 0.7)
					if world.length() < 1.0: aim = Vector2.RIGHT
					direction = Vector2(aim.x-aim.y,(aim.x+aim.y)*0.5).normalized() * 0.60
					brake = false
					burst = false
		var before_rpm: float = float(p.rpm)
		b.test_step(Battle.FIXED_DT, direction, burst, brake)
		assert(is_same(p, b.player_entity()), "No player replacement")
		if game.screen == "level_up": game._process(0.2)
		while game.screen == "reward": choose(game, context, drafts)
		if game.screen == "acquisition": game._process(0.1)
		var dt: float = maxf(0.0, b.elapsed - previous_time)
		previous_time = b.elapsed
		row.seconds_above_90 += dt if before_rpm > 0.90 else 0.0
		row.seconds_above_75 += dt if before_rpm > 0.75 else 0.0
		row.seconds_below_50 += dt if before_rpm < 0.50 else 0.0
		row.seconds_below_25 += dt if before_rpm < 0.25 else 0.0
		row.controlled_seconds += dt if direction.length() > 0.08 else 0.0
		row.braking_seconds += dt if brake else 0.0
		row.venting_seconds += dt if recovering else 0.0
		row.burst_requests += 1 if burst else 0
		row.max_speed = maxf(float(row.max_speed), Vector2(p.vel).length())
		row.max_radius = maxf(float(row.max_radius), Vector2(p.pos).length())
		row.minimum_rpm = minf(float(row.minimum_rpm), minf(float(p.rpm), e.minimum))
		if b.elapsed >= next_trace:
			row.trace.append({"time":b.elapsed,"rpm":p.rpm,"stress":p.get("anchor_stress",0.0),"radius":Vector2(p.pos).length(),"level":game.run_context.level,"losses":e.detailed_losses.duplicate(),"gains":e.detailed_gains.duplicate()})
			next_trace = b.elapsed + 5.0
		tick += 1
	var total_loss: float = 0.0
	var total_gain: float = 0.0
	for value: float in e.detailed_losses.values(): total_loss += value
	for value: float in e.detailed_gains.values(): total_gain += value
	row.merge({"survival_seconds":b.elapsed,"final_rpm":float(p.rpm),"loss_by_source":e.detailed_losses,"recovery_by_source":e.detailed_gains,"spend_calls":e.spend_calls,"total_loss":total_loss,"total_recovered":total_gain,"net_change":float(p.rpm)-float(row.starting_rpm),"ledger_closure_error":absf(float(p.rpm)-(float(row.starting_rpm)-total_loss+total_gain)),"ended_naturally":b.battle_status=="finished","outcome":b.last_result.get("reason","horizon_censored"),"powers":game.run_context.owned_power_ids.duplicate(),"ranks":game.run_context.power_ranks.duplicate(),"mutations":game.run_context.power_mutations.duplicate(),"threats_cleared":b.continuous.threats_cleared,"level":game.run_context.level,"canonical_ledger":e.snapshot()})
	assert(float(row.ledger_closure_error) < 0.000001, "Every RPM write accounted")
	print("RPM_ECONOMY_RUN ",context.id," seed=",seed_value," sec=",snappedf(b.elapsed,0.01)," RPM=",snappedf(p.rpm,0.001)," loss=",snappedf(total_loss,0.001)," recovery=",snappedf(total_gain,0.001)," outcome=",row.outcome)
	game.free()
	return row

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
		if arg.begins_with("--collection-prefix="): collection_prefix = arg.trim_prefix("--collection-prefix=")
		if arg.begins_with("--horizon="): horizon = clampf(float(arg.trim_prefix("--horizon=")),30.0,1200.0)
		if arg.begins_with("--case="): selected_case = arg.trim_prefix("--case=")
	assert(output.is_absolute_path() and collection_prefix.is_absolute_path() and not FileAccess.file_exists(output))
	var runs: Array[Dictionary] = []
	for context: Dictionary in CASES:
		if not selected_case.is_empty() and str(context.id) != selected_case: continue
		for seed_value: int in seeds:
			runs.append(observe(context,seed_value))
			var partial: FileAccess = FileAccess.open(output+".partial",FileAccess.WRITE)
			partial.store_string(JSON.stringify({"horizon":horizon,"runs":runs},"\t"))
			partial.close()
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema":"003a1-rpm-economy-observation-v1","scope":"Natural production Main Run/physics/AI/Director/XP/offered drafts; assembly and legal 10 Hz sampled input/draft preference fixtures only. No injected powers/enemies/outcomes/RPM, no clock jumps. CountingEconomy delegates every write to canonical code and uses editor debug call stacks only for historical collapsed Redline accounting.","input_policy":"rpm_bot.gd aggressive/hybrid/defensive; defensive overload recovery chooses actual steering orbit at radius105 until stress<=.30 and latch clear. Burst presses ordinary accepted path. Horizon censored runs are not proven lifetime.","seeds":seeds,"horizon":horizon,"runs":runs},"\t"))
	file.close()
	print("RPM_ECONOMY_OBSERVATION_PASS runs=",runs.size())
	quit()
