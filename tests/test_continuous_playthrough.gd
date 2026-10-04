extends SceneTree
## Real continuous combat with a sampled deterministic bot, not human acceptance.
## No forced wins, reserve refills, enemy deletion or teleports. Drafts use Main.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
const Starters = preload("res://scripts/starters.gd")
const Battle = preload("res://scripts/battle.gd")
const LIMIT: float = 480.0
var report: Dictionary = {"scope":"Real fixed-step continuous combat; sampled bot input, normal enemy AI, ordinary earned claims. No injected outcomes or reserve refill. Active seconds exclude menus/countdown/hit-stop; not human playtesting.","runs":[]}
func _initialize() -> void: call_deferred("_run")
func choose(game: QuietMain) -> void:
	var choice: String = game.run_context.pending_offer[0]
	for preferred: String in ["second_wind","impact_wake","dead_centre","iron_comet","afterimage","redline","chain_impact"]:
		if preferred in game.run_context.pending_offer: choice = preferred; break
	var claim: String = game.run_context.pending_draft_id
	game._action("choose_power",{"encounter_id":claim,"power_id":choice,"run_seed":game.run_context.run_seed})
	if game.screen == "mutation":
		game._action("choose_mutation",{"encounter_id":claim,"branch_id":game.run_context.pending_mutation_offer[0],"run_seed":game.run_context.run_seed})
	game._process(1.1)
func play(starter: String, seed_value: int) -> Dictionary:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.run_context.start(Starters.build_for(starter),seed_value,starter)
	game.mode = "run"
	game._show_reward()
	choose(game)
	var b: Node2D = game.battle
	b.set_physics_process(false)
	b.particles_enabled = false
	var result: Dictionary = {"starter":starter,"seed":seed_value,"launches":0,"choices":[],"entries":[],"clears":[],"peak_entities":0,"peak_power_states":0,"swarms":0}
	b.event_sfx.connect(func(kind: String) -> void:
		if kind == "launch": result.launches += 1)
	b.threat_started.connect(func(event: Dictionary) -> void:
		result.entries.append({"threat":event.threat,"time":snappedf(b.elapsed,0.01),"rpm":b.player_entity().rpm,"level":game.run_context.level,"swarm":b.swarm.enabled})
		if b.swarm.enabled: result.swarms += 1)
	b.threat_cleared.connect(func(event: Dictionary) -> void:
		result.clears.append({"threat":event.threat,"time":snappedf(b.elapsed,0.01),"rpm":b.player_entity().rpm,"swarm":b.swarm.telemetry()}))
	var player: Dictionary = b.player_entity()
	var direction: Vector2 = Vector2.ZERO
	var brake: bool = false
	for tick: int in range(65000):
		if b.elapsed >= LIMIT or game.screen == "result": break
		var burst: bool = false
		if tick % 12 == 0:
			var target: Dictionary = b._target_for(player)
			var aim: Vector2 = Vector2.ZERO
			var distance: float = INF
			if not target.is_empty():
				var offset: Vector2 = Vector2(target.pos) - Vector2(player.pos)
				distance = offset.length()
				aim = offset.normalized().rotated(sin(float(tick)*0.047)*0.16)
			if Vector2(player.pos).length() > 143.0: aim = -Vector2(player.pos).normalized()
			direction = Vector2(aim.x-aim.y,(aim.x+aim.y)*0.5).normalized()*0.86
			brake = Vector2(player.pos).length() > 153.0
			burst = float(player.cooldown) <= 0.0 and distance < 110.0 and not brake
		b.test_step(Battle.FIXED_DT,direction,burst,brake)
		assert(is_same(player,b.player_entity()),"The actual bot Run cannot recreate its player")
		if game.screen == "level_up": game._process(0.2)
		while game.screen == "reward":
			result.choices.append({"time":snappedf(b.elapsed,0.01),"level":game.run_context.level,"threat":game.run_context.slot})
			choose(game)
		result.peak_entities = maxi(int(result.peak_entities), b.fighters.size())
		result.peak_power_states = maxi(int(result.peak_power_states), b.powers._states.size())
	result.merge(b.continuous.snapshot(),true)
	result["status"] = game.run_context.status
	result["reason"] = b.last_result.get("reason","sample_limit")
	result["level"] = game.run_context.level
	result["powers"] = game.run_context.owned_power_ids
	result["ranks"] = game.run_context.power_ranks
	result["mutations"] = game.run_context.power_mutations
	result["power_procs"] = b.powers.counters.duplicate()
	result["remaining_rpm"] = player.rpm
	game.free()
	return result
func _run() -> void:
	for starter: String in Starters.IDS:
		for seed_value: int in [421,7341]:
			var result: Dictionary = play(starter,seed_value)
			report.runs.append(result)
			print("CONTINUOUS_SAMPLE starter=%s seed=%d seconds=%.2f threats=%d swarms=%d launches=%d reason=%s" % [starter,seed_value,result.survival_time,result.threats_cleared,result.swarms,result.launches,result.reason])
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--report="),FileAccess.WRITE)
			file.store_string(JSON.stringify(report,"	"))
	quit()
