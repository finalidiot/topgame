extends SceneTree
## Actual combat -> real clear notification -> steering collection. The legal
## Bastion assembly and a sampled centre-control policy are disclosed fixtures,
## not difficulty acceptance. No reserve, damage, outcomes or drops are injected.
const Battle = preload("res://scripts/battle.gd")
const Run = preload("res://scripts/run_context.gd")
const Pickups = preload("res://scripts/run_pickups.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const BUILD: Dictionary = {"blade":"guard","ratchet":"low","bit":"ball"}
var created: int = 0
var collected: int = 0
var checks: int = 0
var failures: int = 0
var report: String = ""
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
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
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	if not report.is_empty() and (not report.is_absolute_path() or FileAccess.file_exists(report) or not (report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/") or report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/"))):
		push_error("A fresh external QA report is required"); quit(2); return
	var run = Run.new()
	run.start(BUILD,421,"bastion")
	var initial_offer: Array = run.pending_offer
	var initial_power: String = str(initial_offer[0])
	check(run.choose_power(run.pending_draft_id,initial_power),"A seeded offered power starts the Run")
	check(initial_power in initial_offer and int(run.power_ranks.get(initial_power,0)) == 1,"Starting ownership comes from the ordinary seeded rank-I offer")
	var battle = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.begin_run(BUILD,run.current_encounter(),run.run_seed)
	var pickups = Pickups.new()
	battle.add_child(pickups)
	pickups.set_process(false)
	pickups.setup(battle,run)
	var player_reference: Dictionary = battle.player_entity()
	var player_preserved: bool = true
	var clear_events: Array[Dictionary] = []
	var drop_events: Array[Dictionary] = []
	var collection_events: Array[Dictionary] = []
	var impact_events: Array[Dictionary] = []
	var control_samples: Array[Dictionary] = []
	battle.threat_cleared.connect(func(summary: Dictionary) -> void:
		var defeated: Array[Dictionary] = []
		for fighter: Dictionary in battle.fighters:
			if fighter.team_id == "hostile" and not str(fighter.outcome).is_empty():
				defeated.append({"entity_id":fighter.entity_id,"outcome":fighter.outcome,"rpm":fighter.rpm,"cause":battle.powers.cause_for(fighter)})
		clear_events.append({"time":battle.elapsed,"summary":summary.duplicate(true),"defeated_entities":defeated})
		if pickups.notify_clear(summary):
			created += 1
			drop_events.append({"time":battle.elapsed,"player_position":Vector2(battle.player_entity().pos),"items":pickups.items.duplicate(true)}))
	pickups.reroll_collected.connect(func(id: String) -> void:
		collected += 1
		collection_events.append({"time":battle.elapsed,"id":id,"player_position":Vector2(battle.player_entity().pos),"charges":run.reroll_charges}))
	battle.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		if impact_events.size() < 64: impact_events.append(event.duplicate(true)))
	var stepped: int = 0
	var controls: Dictionary = {"direction":Vector2.ZERO,"burst":false,"brake":false}
	for tick: int in range(60*180):
		# Human-sized 200 ms sampling observes current position/velocity only.
		# Stable centre corrections receive the new finite committed attacks;
		# chasing with this old fast attack assembly used to ring out at 5.23 s.
		if tick % 12 == 0:
			controls = Bot.input(battle,"defensive",tick)
			if not pickups.items.is_empty():
				var player: Dictionary = battle.player_entity()
				var difference: Vector2 = Vector2(pickups.items[0].pos) - Vector2(player.pos)
				var desired: Vector2 = difference.limit_length(60.0)*2.0-Vector2(player.vel)*0.60
				var world: Vector2 = desired.limit_length(100.0)/100.0
				controls = {"direction":Vector2(world.x-world.y,(world.x+world.y)*0.5),"burst":false,"brake":difference.length()<22.0 and Vector2(player.vel).length()>65.0}
			control_samples.append({"tick":tick,"time":battle.elapsed,"phase":"seek_real_chip" if not pickups.items.is_empty() else "centre_combat","controls":controls.duplicate(true),"player_position":Vector2(battle.player_entity().pos)})
		battle.test_step(Battle.FIXED_DT,controls.direction,controls.burst,controls.brake)
		pickups.update_simulation()
		player_preserved = player_preserved and is_same(player_reference,battle.player_entity())
		stepped += 1
		if collected > 0 or battle.battle_status == "finished": break
	check(battle.hits > 0 and battle.continuous.threats_cleared > 0,"Real combat, rather than direct outcome assignment, clears a threat")
	check(created > 0,"Real threat notification creates a floor chip")
	check(collected == 1 and run.rerolls_collected == 1 and run.reroll_charges == 2,"Real steering through the spawned floor chip grants one charge")
	check(not clear_events.is_empty() and bool(clear_events[0].summary.get("reward_eligible",false)) and not bool(clear_events[0].summary.get("reward_fixture",true)),"The natural clear is earned and never marked as an outcome fixture")
	check(not impact_events.is_empty() and not clear_events.is_empty() and not clear_events[0].defeated_entities.is_empty(),"Accepted physical impacts precede the real defeated enemy and clear")
	check(player_preserved,"Actual fixed ticks preserve the same player dictionary")
	check(not drop_events.is_empty() and Vector2(drop_events[0].items[0].pos).distance_to(Vector2(drop_events[0].player_position)) >= 30.0,"The genuine chip spawns away from the player and requires travel")
	check(not drop_events.is_empty() and not collection_events.is_empty() and collection_events[0].id == drop_events[0].items[0].id and float(collection_events[0].time) > float(drop_events[0].time),"One real spawned chip identity is collected later through physical movement")
	print("LIVE_PICKUP_DETAILS ticks=%d time=%.2f hits=%d threats=%d chips=%d collected=%d" % [stepped,battle.elapsed,battle.hits,battle.continuous.threats_cleared,created,collected])
	if not report.is_empty():
		var file: FileAccess = FileAccess.open(report,FileAccess.WRITE)
		file.store_string(JSON.stringify(portable({"checks":checks,"failures":failures,"seed":421,"build":BUILD,"starter":"bastion","starting_offer":initial_offer,"starting_choice":initial_power,"policy":"Observed current-state defensive centre corrections and genuine floor-chip seeking, both sampled every 200 ms. Legal starting assembly and seeded first offer only; no enemies, damage, reserve, outcomes or pickups injected.","ticks":stepped,"seconds":battle.elapsed,"hits":battle.hits,"threats_cleared":battle.continuous.threats_cleared,"chips_created":created,"chips_collected":collected,"clear_events":clear_events,"drop_events":drop_events,"collection_events":collection_events,"accepted_impacts":impact_events,"control_samples":control_samples,"player_dictionary_preserved":player_preserved,"economy":battle.continuous.economy.snapshot()}),"\t"))
		file.close()
	battle.free()
	print("FEEDBACK_LIVE_PICKUP_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
