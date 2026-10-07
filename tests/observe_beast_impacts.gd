extends SceneTree
## Natural continuous Runs with sampled legal controls and ordinary earned drafts.
## Only the declared starting assembly is a fixture. No powers are granted, no
## bodies are injected, no outcomes/RPM are edited and every fixed tick runs.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	# HUD drawing/audio are read-only subscribers; drafts and progression retain
	# the actual Main handlers while offline physics avoids widget rebuilding.
	func _hud_updated(_stats: Dictionary) -> void: pass
	func _battle_sound(_kind: String) -> void: pass
const Battle = preload("res://scripts/battle.gd")
const Starters = preload("res://scripts/starters.gd")
const Parts = preload("res://scripts/parts.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const CASES: Array[Dictionary] = [
	{"id":"aggressive", "starter":"breaker", "style":"aggressive", "build":{"blade":"smash","ratchet":"high","bit":"flat"}},
	{"id":"balanced", "starter":"custom", "style":"hybrid", "build":{"blade":"balance","ratchet":"mid","bit":"ball"}},
	{"id":"defensive", "starter":"bastion", "style":"defensive", "build":{"blade":"guard","ratchet":"low","bit":"ball"}},
	{"id":"high_mass", "starter":"custom", "style":"defensive", "build":{"blade":"hammerfall","ratchet":"ballast","bit":"tripod"}},
	{"id":"high_speed", "starter":"custom", "style":"aggressive", "build":{"blade":"sawtooth","ratchet":"high","bit":"skate"}}]
var horizon: float = 600.0
var seeds: Array[int] = [421,7341,2026]
var output: String = ""
var collection_prefix: String = ""
var selected_case: String = ""

static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = portable(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(portable(item))
		return result
	return value

func _initialize() -> void: call_deferred("_run")

func choose(game: QuietMain, context: Dictionary, drafts: Array[Dictionary]) -> void:
	var preferences: Array[String] = ["redline","iron_comet","impact_wake","second_wind","momentum_bank","crosscut","afterimage"]
	if str(context.style) == "defensive": preferences = ["dead_centre","impact_sink","anchor_exchange","crash_guard","second_wind","momentum_bank","gyro_lock"]
	elif str(context.style) == "hybrid": preferences = ["afterimage","impact_wake","second_wind","iron_comet","momentum_bank","redline","dead_centre"]
	var choice: String = str(game.run_context.pending_offer[0])
	for preferred: String in preferences:
		if preferred in game.run_context.pending_offer: choice = preferred; break
	var row: Dictionary = {"time":game.battle.elapsed, "level":game.run_context.level, "offer":game.run_context.pending_offer.duplicate(), "choice":choice, "claim":game.run_context.pending_draft_id}
	game._action("choose_power",{"encounter_id":game.run_context.pending_draft_id,"power_id":choice,"run_seed":game.run_context.run_seed,"offer_revision":game.run_context.reroll_snapshot().revision})
	if game.screen == "mutation":
		var branch: String = str(game.run_context.pending_mutation_offer[0])
		if str(context.style) == "defensive" and "bulwark" in game.run_context.pending_mutation_offer: branch = "bulwark"
		row["mutation_offer"] = game.run_context.pending_mutation_offer.duplicate(); row["mutation"] = branch
		game._action("choose_mutation",{"encounter_id":game.run_context.pending_draft_id,"branch_id":branch,"run_seed":game.run_context.run_seed})
	drafts.append(row)
	game._process(1.1)
	game.battle.set_physics_process(false)

func observe(context: Dictionary, seed_value: int) -> Dictionary:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = collection_prefix+"_"+str(context.id)+"_"+str(seed_value)+".json"
	assert(not FileAccess.file_exists(game.collection_path),"Natural study cannot overwrite an existing isolated save")
	root.add_child(game); game.set_process(false)
	game.run_context.start(context.build,seed_value,str(context.starter)); game.mode = "run"
	game._show_reward()
	var drafts: Array[Dictionary] = []
	choose(game,context,drafts)
	var b: Node2D = game.battle
	b.set_physics_process(false); b.particles_enabled = false
	assert(b.has_signal("full_top_impact_accepted"),"The canonical full-top impact observer is required")
	var events: Array[Dictionary] = []
	var row: Dictionary = {"context":context.duplicate(true), "seed":seed_value,"starting_stats":Parts.derive(context.build),"assembly_fixture_only":true,"injected_powers":[],"drafts":drafts,"events":events,"input_samples":[],"peak_full":1,"peak_small":0,"presentation_spawned":0}
	b.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		var contact: Dictionary = event.duplicate(true)
		contact["level"] = game.run_context.level
		contact["powers"] = game.run_context.owned_power_ids.duplicate()
		contact["power_ranks"] = game.run_context.power_ranks.duplicate(true)
		contact["power_mutations"] = game.run_context.power_mutations.duplicate(true)
		contact["player_involved"] = int(event.first_entity_id)==1 or int(event.second_entity_id)==1
		var presentation: Dictionary = b.beast_presentation_snapshot()
		contact["presentation"] = {"spawned":presentation.spawned,"qualified":presentation.qualified,"suppressed":presentation.suppressed,"duplicates":presentation.duplicates,"count":presentation.count,"peak_live":presentation.peak_live}
		events.append(contact))
	var direction: Vector2 = Vector2.ZERO
	var brake: bool = false
	var p: Dictionary = b.player_entity()
	var tick: int = 0
	while b.elapsed < horizon and game.screen != "result" and tick < int(horizon*120.0)+600:
		var burst: bool = false
		if tick%12 == 0:
			var input: Dictionary = Bot.input(b,str(context.style),tick)
			direction = input.direction; brake = input.brake; burst = input.burst
			if tick%600 == 0: row.input_samples.append({"tick":tick,"time":b.elapsed,"direction":direction,"brake":brake,"burst":burst})
		b.test_step(Battle.FIXED_DT,direction,burst,brake)
		assert(is_same(p,b.player_entity()),"Natural Run never replaces its player")
		if game.screen == "level_up": game._process(0.2)
		while game.screen == "reward": choose(game,context,drafts)
		var census: Dictionary = b.continuous.census()
		row.peak_full = maxi(row.peak_full,int(census.active_full))
		row.peak_small = maxi(row.peak_small,b.swarm.active_count())
		tick += 1
	row.merge({"elapsed":b.elapsed,"simulation_ticks":tick,"reason":b.last_result.get("reason","observation_horizon"),"ended_naturally":b.battle_status=="finished","remaining_rpm":p.rpm,"all_contacts_including_small":b.hits,"full_top_events":events.size(),"level":game.run_context.level,"powers":game.run_context.owned_power_ids.duplicate(),"ranks":game.run_context.power_ranks.duplicate(true),"mutations":game.run_context.power_mutations.duplicate(true),"director_history":b.continuous.director.history.duplicate(true),"power_procs":b.powers.counters.duplicate(true),"presentation":b.beast_presentation_snapshot(),"economy":b.continuous.economy.snapshot()})
	print("BEAST_IMPACT_RUN ",context.id," seed=",seed_value," seconds=",snappedf(b.elapsed,0.01)," full_top=",events.size()," reason=",row.reason)
	game.free()
	return row

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
		if arg.begins_with("--collection-prefix="): collection_prefix = arg.trim_prefix("--collection-prefix=")
		if arg.begins_with("--horizon="): horizon = clampf(float(arg.trim_prefix("--horizon=")),10.0,1200.0)
		if arg.begins_with("--seed="): seeds = [int(arg.trim_prefix("--seed="))]
		if arg.begins_with("--case="): selected_case = arg.trim_prefix("--case=")
	assert(output.is_absolute_path() and collection_prefix.is_absolute_path() and not FileAccess.file_exists(output))
	var runs: Array[Dictionary] = []
	for context: Dictionary in CASES:
		if not selected_case.is_empty() and str(context.id) != selected_case: continue
		for seed_value: int in seeds:
			runs.append(observe(context,seed_value))
			var checkpoint: FileAccess = FileAccess.open(output+".partial",FileAccess.WRITE)
			assert(checkpoint!=null)
			checkpoint.store_string(JSON.stringify(portable({"scope":"Partial natural impact observation; not a final accepted distribution.","horizon":horizon,"runs":runs}),"\t")); checkpoint.close()
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	assert(file!=null)
	file.store_string(JSON.stringify(portable({"scope":"Natural real continuous Runs; legal declared starting assemblies, ordinary offered/earned power choices, sampled deterministic bot controls. Every 60Hz simulation tick runs. No outcome injection, enemy injection, reserve grant, profile access, threat-clock jump or imposed manifestation rate.","horizon":horizon,"runs":runs}),"\t")); file.close()
	print("BEAST_IMPACT_STUDY_PASS runs=",runs.size())
	quit()
