extends SceneTree
## Declared legal investment fixtures only. Continuous Run admission, solver,
## losses/gains/AI/outcomes and every simulation clock remain production rules.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const COMBINATIONS: Dictionary = {
	"aggressive":{
		"starter":"breaker","build":{"blade":"smash","ratchet":"high","bit":"flat"},
		0:{"ranks":{},"mutations":{}},
		3:{"ranks":{"redline":1,"clutch":1,"impact_wake":1},"mutations":{}},
		6:{"ranks":{"redline":2,"clutch":2,"impact_wake":2},"mutations":{}},
		12:{"ranks":{"redline":3,"clutch":2,"impact_wake":2,"iron_comet":2,"chain_impact":2,"high_gear":1},"mutations":{"redline":"runaway"}}},
	"defensive":{
		"starter":"bastion","build":{"blade":"guard","ratchet":"low","bit":"ball"},
		0:{"ranks":{},"mutations":{}},
		3:{"ranks":{"dead_centre":1,"crash_guard":1,"clutch":1},"mutations":{}},
		6:{"ranks":{"dead_centre":2,"crash_guard":2,"clutch":2},"mutations":{}},
		12:{"ranks":{"dead_centre":3,"crash_guard":2,"clutch":2,"impact_wake":2,"iron_comet":2,"crosscut":1},"mutations":{"dead_centre":"bulwark"}}},
	"mixed":{
		"starter":"vane","build":{"blade":"hook","ratchet":"mid","bit":"rubber"},
		0:{"ranks":{},"mutations":{}},
		3:{"ranks":{"afterimage":1,"orbit_drive":1,"crash_guard":1},"mutations":{}},
		6:{"ranks":{"afterimage":2,"orbit_drive":2,"crash_guard":2},"mutations":{}},
		12:{"ranks":{"afterimage":3,"orbit_drive":2,"crash_guard":2,"dead_centre":3,"clutch":2},"mutations":{"afterimage":"slipstream","dead_centre":"counterweight"}}}
}
const INVESTMENTS: Array[int] = [0,3,6,12]
var seeds: Array[int] = [421,7341,2026]
var horizon: float = 480.0
var handoff_seconds: float = 180.0
var selected: String = ""
var output: String
var runs: Array[Dictionary] = []

static func legal(stage: Dictionary, investments: int) -> bool:
	var total: int = 0
	if stage.ranks.size() > Powers.FAMILY_CAP: return false
	for id: String in stage.ranks:
		var rank_value: int = int(stage.ranks[id])
		if id not in Powers.ACTIVE_IDS or rank_value < 1 or rank_value > Powers.max_rank(id): return false
		if rank_value == 3 and str(stage.mutations.get(id, "")) not in Powers.MUTATION_BRANCHES.get(id, []): return false
		if rank_value != 3 and stage.mutations.has(id): return false
		total += rank_value
	return total == investments

static func total(values: Dictionary) -> float:
	var result: float = 0
	for value: Variant in values.values(): result += float(value)
	return result

func _initialize() -> void: call_deferred("run")

func controls(b: Node2D, style: String, tick: int, state: Dictionary) -> Dictionary:
	var chosen: Dictionary = Bot.input(b, "hybrid" if style == "mixed" else style, tick)
	chosen.mode = "normal_" + style
	if style != "defensive": return chosen
	var p: Dictionary = b.player_entity()
	var anchor: Dictionary = b.powers.public_state(p).anchor
	if bool(anchor.get("overloaded", false)) or float(p.get("anchor_stress",0.0)) >= .80: state.recovering = true
	if bool(state.get("recovering", false)) and float(p.get("anchor_stress",0.0)) <= .30 and not bool(anchor.get("overloaded", false)): state.recovering = false
	if bool(state.get("recovering", false)):
		var world: Vector2 = p.pos
		var aim: Vector2 = world.orthogonal().normalized()*.5 + world.normalized()*clampf((105-world.length())/30,-.7,.7)
		if world.length() < 1: aim = Vector2.RIGHT
		chosen = {"direction":Vector2(aim.x-aim.y,(aim.x+aim.y)*.5).normalized()*.60,"burst":false,"brake":false,"mode":"deliberate_anchor_vent"}
	return chosen

func observe(style: String, investments: int, seed_value: int, hands_off: bool) -> Dictionary:
	var context: Dictionary = COMBINATIONS[style]
	var stage: Dictionary = context[investments]
	assert(legal(stage, investments))
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.particles_enabled = false
	var descriptor: Dictionary = Encounters.for_run_event(1, seed_value)
	descriptor.starter_id = context.starter
	descriptor.player_power_ids = stage.ranks.keys()
	descriptor.player_power_ranks = stage.ranks.duplicate(true)
	descriptor.player_power_mutations = stage.mutations.duplicate(true)
	battle.begin_run(context.build, descriptor, seed_value)
	battle.continuous.progression_level = maxi(1, investments)
	var p: Dictionary = battle.player_entity()
	var start: float = float(p.rpm)
	var row: Dictionary = {"style":style,"investments":investments,"seed":seed_value,"policy":"active_then_hands_off" if hands_off else "active",
		"initial_assembly":context.build.duplicate(true),"initial_ranks":stage.ranks.duplicate(true),"initial_mutations":stage.mutations.duplicate(true),"director_investment_context":maxi(1,investments),
		"starting_rpm":start,"trace":[],"seconds_above_90":0.0,"seconds_above_75":0.0,"seconds_below_50":0.0,"seconds_below_25":0.0,"controlled_seconds":0.0,"braking_seconds":0.0,"burst_requests":0,"contacts":0,"meaningful_contacts":0,"control_modes":{},"handoff_reached":false}
	battle.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		if int(event.first_entity_id) != 1 and int(event.second_entity_id) != 1: return
		row.contacts += 1
		if float(event.severity) >= .32: row.meaningful_contacts += 1)
	var tick: int = 0
	var next_trace: float = 0
	var state: Dictionary = {}
	var input: Dictionary = {"direction":Vector2.ZERO,"burst":false,"brake":false,"mode":"countdown"}
	while battle.elapsed < horizon and battle.battle_status != "finished" and tick < int(horizon*100) + 1000:
		if tick % 12 == 0: input = controls(battle, style, tick, state)
		var chosen: Dictionary = input.duplicate()
		if hands_off and battle.elapsed >= handoff_seconds:
			if not bool(row.handoff_reached):
				row.handoff_reached = true
				row.handoff = {"time":battle.elapsed,"rpm":p.rpm,"wobble":p.wobble,"position":[p.pos.x,p.pos.y],"velocity":[p.vel.x,p.vel.y],"economy":battle.continuous.economy.snapshot(),"tier":battle.continuous.director.tier_at(battle.elapsed)}
			chosen = {"direction":Vector2.ZERO,"burst":false,"brake":false,"mode":"hands_off"}
		var before: float = battle.elapsed
		var before_rpm: float = float(p.rpm)
		battle.test_step(Battle.FIXED_DT, chosen.direction, bool(chosen.burst) and tick % 12 == 0, chosen.brake)
		assert(is_same(p, battle.player_entity()))
		var dt: float = battle.elapsed - before
		row.seconds_above_90 += dt if before_rpm >= .90 else 0.0
		row.seconds_above_75 += dt if before_rpm >= .75 else 0.0
		row.seconds_below_50 += dt if before_rpm < .50 else 0.0
		row.seconds_below_25 += dt if before_rpm < .25 else 0.0
		row.controlled_seconds += dt if Vector2(chosen.direction).length() > .08 else 0.0
		row.braking_seconds += dt if bool(chosen.brake) else 0.0
		row.burst_requests += 1 if bool(chosen.burst) and tick % 12 == 0 else 0
		row.control_modes[chosen.mode] = float(row.control_modes.get(chosen.mode, 0)) + dt
		if battle.elapsed >= next_trace or battle.battle_status == "finished":
			var e: Dictionary = battle.continuous.economy.snapshot()
			row.trace.append({"time":battle.elapsed,"rpm":p.rpm,"speed":Vector2(p.vel).length(),"radius":Vector2(p.pos).length(),"stress":p.get("anchor_stress",0.0),"losses":e.losses,"gains":e.gains,"mode":chosen.mode,"tier":battle.continuous.director.tier_at(battle.elapsed),"threats_cleared":battle.continuous.threats_cleared})
			next_trace = battle.elapsed + 5
		tick += 1
	var economy: Dictionary = battle.continuous.economy.snapshot()
	var loss: float = total(economy.losses)
	var gain: float = total(economy.gains)
	var error: float = absf(start - loss + gain - float(p.rpm))
	assert(error < .000001)
	row.merge({"survival_seconds":battle.elapsed,"censored":battle.battle_status != "finished","reason":battle.last_result.get("reason","horizon_censored"),"final_rpm":p.rpm,"minimum_rpm":economy.minimum_rpm,
		"loss_by_source":economy.losses,"gain_by_source":economy.gains,"total_loss":loss,"total_gain":gain,"net_change":float(p.rpm)-start,"gain_loss_ratio":gain/maxf(.000001,loss),"ledger_closure_error":error,"threats_cleared":battle.continuous.threats_cleared,
		"elites_defeated":battle.continuous.elites_defeated,"bosses_defeated":battle.continuous.bosses_defeated,"director_history":battle.continuous.director.history.duplicate(true),"power_procs":battle.powers.counters.duplicate(),"simulation_ticks":tick,"final_ranks":p.power_ranks.duplicate(true)})
	assert(row.initial_ranks == row.final_ranks, "Fixed investment isolates the curve; no upgrades silently injected or removed")
	print("UPGRADE_SUSTAIN_RUN ",style," investments=",investments," seed=",seed_value," policy=",row.policy," sec=",snappedf(battle.elapsed,.01)," RPM=",snappedf(p.rpm,.001)," loss=",snappedf(loss,.001)," gain=",snappedf(gain,.001)," reason=",row.reason)
	battle.free()
	return row

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
		if arg.begins_with("--case="): selected = arg.trim_prefix("--case=")
		if arg.begins_with("--horizon="): horizon = clampf(float(arg.trim_prefix("--horizon=")),30,1200)
	assert(output.is_absolute_path() and not FileAccess.file_exists(output))
	for style: String in COMBINATIONS:
		if not selected.is_empty() and style != selected: continue
		for investments: int in INVESTMENTS:
			for seed_value: int in seeds:
				runs.append(observe(style, investments, seed_value, false))
				write_report(output + ".partial")
		for seed_value: int in seeds:
			runs.append(observe(style, 12, seed_value, true))
			write_report(output + ".partial")
	write_report(output)
	print("UPGRADE_SUSTAIN_OBSERVATION_PASS runs=",runs.size())
	quit()

func write_report(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema":"003a1-upgrade-sustain-observation-v1","horizon":horizon,"handoff_seconds":handoff_seconds,"seeds":seeds,"runs":runs,
		"scope":"Real continuous Run/physics/AI/Director and source ledger; declared legal starting assembly/powers/ranks/mutations and investment pressure context only. Normal countdown/launch and every simulation tick; no injected enemies/RPM/outcomes/teleports/clock jumps. Fixed ranks intentionally isolate investment levels; earned XP is not claimed into additional powers.",
		"input_policy":"Actual rpm_bot sampled5Hz with ordinary Burst requests, defensive deliberate overload vent and deep active180s then hands-off contrast. Time is canonical combat elapsed; hit holds/countdown excluded. Horizon survivors are censored, not proven immortal.","units":"RPM reserve/loss/gain fractions of9000 RPM"},"\t"))
	file.close()
