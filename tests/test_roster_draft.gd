extends SceneTree
## Attributed XP and seeded offers are real. Policy comparisons are synthetic
## choice models, not natural combat or human pacing evidence.
const Powers = preload("res://scripts/run_powers.gd")
const Run = preload("res://scripts/run_context.gd")
const Parts = preload("res://scripts/parts.gd")
const Seeds = preload("res://scripts/seed_utils.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
var checks: int = 0
var failures: int = 0
var report: Dictionary = {"scope":"Seeded draft and synthetic investment preferences; no combat balance claim","seeds":256,"policy_models":[],"ownership_states":[]}
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _run() -> void:
	check(Powers.ACTIVE_IDS.size() == 16 and Powers.investment_capacity() == 39,"Sixteen meaningful families, thirty-nine total investments")
	check(not "second_wind" in Powers.ACTIVE_IDS and "clutch" in Powers.ACTIVE_IDS,"Retired revive is excluded from every normal offer")
	check(not Powers.get_owned_power("second_wind").is_empty() and not Powers.get_power("second_wind").active and Powers.get_offer("second_wind").is_empty(),"Legacy owned identity remains readable without re-entering drafts")
	for power: String in Powers.ACTIVE_IDS:
		check(Powers.max_rank(power) >= 2 and not Powers.get_offer(power,1).is_empty(),"Every family develops beyond Rank I")
	for seed_value: int in range(1,257):
		_test_real_claims(seed_value)
	for seed_value: int in range(1,17): _test_late_seventh(seed_value)
	_test_live_claims()
	for owned_count: int in [3,5,7]: _test_ownership_state(owned_count)
	for policy: String in ["enlarged_old_weights","soft_depth","hard_five","hard_six","hard_seven","hard_seven_soft"]:
		for preference: String in ["random","deepen"]:
			report.policy_models.append(_model(policy,preference))
	for policy: String in ["soft_depth","hard_seven_soft"]: report.policy_models.append(_model(policy,"random",18))
	var old: Dictionary = report.policy_models[0]
	var soft: Dictionary = report.policy_models[2]
	check(float(soft.mean_families) < float(old.mean_families),"Soft saturation produces fewer deeper families than enlarged old weighting")
	check(float(soft.mean_mutations) > float(old.mean_mutations),"Soft saturation retains access to behavioural development")
	check(float(soft.mean_families) > 4.0 and float(soft.mean_families) < 8.0,"Random twelve-investment model stays near a coherent family range")
	var path: String = "user://task002c5-draft-study.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): path = arg.trim_prefix("--report=")
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	print("ROSTER_DRAFT_%s checks=%d failures=%d models=%s" % ["PASS" if failures == 0 else "FAIL",checks,failures,JSON.stringify(report.policy_models)])
	quit(1 if failures else 0)
func _test_real_claims(seed_value: int) -> void:
	var first = Run.new()
	var second = Run.new()
	first.start(Parts.DEFAULT_BUILD,seed_value,"breaker")
	second.start(Parts.DEFAULT_BUILD,seed_value,"vane")
	check(first.pending_offer == second.pending_offer,"No hard starter classes affect seeded offers")
	var opening: String = first.pending_offer[seed_value % 3]
	first.choose_power(first.pending_draft_id,opening)
	second.choose_power(second.pending_draft_id,opening)
	for entity_id: int in range(100,224):
		var event: Dictionary = {"kind":"elimination","encounter_id":"run_slot_01","time":1.0,"entity_id":entity_id,"combatant_type":"full_top","reason":"spin_out","player_attributed":true}
		first.award_xp(event)
		second.award_xp(event)
	check(first.level == Powers.run_investment_capacity(),"Large real attributed XP queues the maximum available machine investments")
	while not first.pending_offer.is_empty():
		var seen: Dictionary = {}
		check(first.pending_offer == second.pending_offer,"Same seed and choices reproduce every enlarged offer")
		for id: String in first.pending_offer:
			check(not seen.has(id) and Powers.can_progress(id,int(first.power_ranks.get(id,0)),str(first.power_mutations.get(id,""))),"Every offer is distinct and eligible")
			seen[id] = true
		var claim: String = first.pending_draft_id
		var choice: String = first.pending_offer[seed_value % first.pending_offer.size()]
		check(first.choose_power(claim,choice) and second.choose_power(claim,choice),"Real normal claim accepts the offered investment")
		if not first.pending_mutation_power.is_empty():
			var branch: String = first.pending_mutation_offer[seed_value % 2]
			check(first.choose_mutation(claim,branch) and second.choose_mutation(claim,branch),"Every mutation remains reachable through real drafts")
	var owned_flagships: int = 0
	for id: String in first.owned_power_ids:
		if id in Powers.VERTICAL_IDS: owned_flagships += 1
	check(first.owned_power_ids.size() == Powers.FAMILY_CAP and first.power_mutations.size() == owned_flagships and first.committed_rewards.size() == first.available_investment_capacity(),"Seven chosen families reach full depth without empty queued claims")
	check(first.pending_draft_id.is_empty() and first.level == first.available_investment_capacity() and first.progression_snapshot().maxed and first.xp == 0,"Dynamic investment ceiling closes unavailable overflow")
	check(first.power_ranks == second.power_ranks and first.power_mutations == second.power_mutations,"Final ranks and branches are deterministic across starters")
func _test_late_seventh(seed_value: int) -> void:
	var run = Run.new()
	run.start(Parts.DEFAULT_BUILD,seed_value)
	run.choose_power(run.pending_draft_id,run.pending_offer[0])
	for entity_id: int in range(100,224):
		run.award_xp({"kind":"elimination","encounter_id":"run_slot_01","time":1.0,"entity_id":entity_id,"combatant_type":"full_top","reason":"spin_out","player_attributed":true})
	var before_xp: int = run.progression_snapshot().total_xp
	while run.owned_power_ids.size() < 6:
		var choice: String = run.pending_offer[0]
		for id: String in run.pending_offer:
			if not id in run.owned_power_ids: choice = id; break
		_claim(run,choice)
	while true:
		var choice: String = ""
		for id: String in run.pending_offer:
			if id in run.owned_power_ids: choice = id; break
		if choice.is_empty(): break
		_claim(run,choice)
	check(run.owned_power_ids.size() == 6,"Six deeply developed families still retain a seventh-family choice")
	_claim(run,run.pending_offer[0])
	check(run.owned_power_ids.size() == 7 and run.progression_snapshot().max_level == run.available_investment_capacity(),"Late seventh family recomputes the exact available investment ceiling")
	while not run.pending_offer.is_empty(): _claim(run,run.pending_offer[0])
	check(run.pending_draft_id.is_empty() and run.committed_rewards.size() == run.available_investment_capacity() and run.progression_snapshot().total_xp == before_xp,"Large pre-earned queues close coherently without losing XP attribution history")
	run.start(Parts.DEFAULT_BUILD,seed_value)
	check(run.owned_power_ids.is_empty() and run.progression_snapshot().max_level == Powers.run_investment_capacity() and run.level == 1,"A fresh Run restores uncommitted family slots and maximum possible depth")
func _claim(run, choice: String) -> void:
	var claim: String = run.pending_draft_id
	check(run.choose_power(claim,choice),"Cap fixture accepts only a real current offer")
	if not run.pending_mutation_power.is_empty(): check(run.choose_mutation(claim,run.pending_mutation_offer[0]),"Cap fixture commits an ordinary behavioural branch")
func _test_live_claims() -> void:
	var tunes_seen: Dictionary = {}
	for seed_value: int in range(1,33):
		var game: QuietMain = QuietMain.new()
		game.smoke_mode = true
		root.add_child(game)
		game.set_process(false)
		game.run_context.start(Parts.DEFAULT_BUILD,seed_value,"custom")
		game.mode = "run"
		game._draft_resume_origin = "starting"
		game._show_reward()
		game._action("choose_power",{"encounter_id":game.run_context.pending_draft_id,"power_id":game.run_context.pending_offer[0],"run_seed":seed_value})
		game._process(1.1)
		game.battle.set_physics_process(false)
		var player: Dictionary = game.battle.player_entity()
		for entity_id: int in range(100,224):
			game.run_context.award_xp({"kind":"elimination","encounter_id":"run_slot_01","time":1.0,"entity_id":entity_id,"combatant_type":"full_top","reason":"spin_out","player_attributed":true})
		game._progression_events([])
		game._process(0.2)
		while not game.run_context.pending_offer.is_empty():
			var claim: String = game.run_context.pending_draft_id
			var choice: String = game.run_context.pending_offer[seed_value % game.run_context.pending_offer.size()]
			game._action("choose_power",{"encounter_id":claim,"power_id":choice,"run_seed":seed_value})
			if game.screen == "mutation":
				game._action("choose_mutation",{"encounter_id":claim,"branch_id":game.run_context.pending_mutation_offer[seed_value % 2],"run_seed":seed_value})
			check(is_same(player,game.battle.player_entity()),"Actual Main draft claims preserve the same live player dictionary")
			check(player.power_ranks == game.run_context.power_ranks and player.power_mutations == game.run_context.power_mutations and player.powers == game.run_context.owned_power_ids,"Every real claim immediately installs all context ranks and branches in Battle")
			if int(player.power_ranks.get(choice,0)) == 2: tunes_seen[choice] = true
			game._process(1.1)
		check(game.screen == "battle" and game.run_context.pending_draft_id.is_empty(),"Full capped investment resumes live combat after actual acquisition screens")
		game.free()
	check(tunes_seen.size() == Powers.ACTIVE_IDS.size(),"All active Rank II paths were installed through actual Main acquisition, including support families")
func _test_ownership_state(owned_count: int) -> void:
	var new_seen: Dictionary = {}
	var counts: Dictionary = {"owned":owned_count,"new":0,"rank":0,"mutation":0,"offers":0}
	for seed_value: int in range(1,257):
		var run = Run.new()
		run.start(Parts.DEFAULT_BUILD,seed_value)
		for index: int in range(owned_count):
			var id: String = Powers.ACTIVE_IDS[index]
			run._owned_power_ids.append(id)
			run._power_ranks[id] = 2 if index % 2 == 0 and id in Powers.VERTICAL_IDS else 1
		run._generate_offer()
		var develops: bool = false
		for id: String in run.pending_offer:
			var rank: int = int(run.power_ranks.get(id,0))
			counts["new" if rank == 0 else ("rank" if rank == 1 else "mutation")] += 1
			if rank > 0: develops = true
			else: new_seen[id] = true
		check(run.pending_offer.size() == 3 and develops,"At three/five/seven families an eligible upgrade always occupies one slot")
		counts.offers += 1
	check(new_seen.size() == (Powers.ACTIVE_IDS.size()-owned_count if owned_count < Powers.FAMILY_CAP else 0),"All families remain reachable until seven slots; full machines offer only development")
	report.ownership_states.append(counts)
func _model(policy: String, preference: String, investments: int = 12) -> Dictionary:
	var result: Dictionary = {"policy":policy,"preference":preference,"investments":investments,"runs":256,"mean_families":0.0,"mean_mutations":0.0,"offered_new":0,"offered_rank":0,"offered_mutation":0,"picked_new":0,"picked_rank":0,"picked_mutation":0,"families_min":Powers.ACTIVE_IDS.size(),"families_max":0}
	for seed_value: int in range(1,257):
		var ranks: Dictionary = {}
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = Seeds.derive(seed_value,"study/choices")
		for level: int in range(1,investments+1):
			var run = Run.new()
			run.start(Parts.DEFAULT_BUILD,seed_value)
			run._power_ranks = ranks.duplicate()
			run._owned_power_ids.clear()
			for id: String in ranks: run._owned_power_ids.append(id)
			run._draft_queue.clear()
			run._draft_queue.append({"id":"draft/start" if level == 1 else "draft/level_%02d" % level,"kind":"starting" if level == 1 else "level","level":level})
			var offer: Array[String] = []
			if policy == "hard_seven_soft":
				run._generate_offer()
				offer = run.pending_offer
			else:
				var candidates: Array[String] = []
				var weights: Array[float] = []
				for id: String in Powers.ACTIVE_IDS:
					var rank: int = int(ranks.get(id,0))
					if not Powers.can_progress(id,rank): continue
					var cap: int = {"hard_five":5,"hard_six":6,"hard_seven":7}.get(policy,Powers.ACTIVE_IDS.size())
					if rank == 0 and ranks.size() >= cap: continue
					candidates.append(id)
					weights.append(Run.draft_weight(ranks.size(),rank) if policy == "soft_depth" else (1.0 if rank == 0 else 1.2))
				var draft_rng: RandomNumberGenerator = RandomNumberGenerator.new()
				draft_rng.seed = Seeds.derive(seed_value,"draft/" + run.pending_draft_id)
				if policy == "soft_depth" and ranks.size() >= int(Run.DRAFT_TUNING.upgrade_slot_from):
					var upgrades: Array[int] = []
					var upgrade_weights: Array[float] = []
					for index: int in range(candidates.size()):
						if int(ranks.get(candidates[index],0)) > 0:
							upgrades.append(index)
							upgrade_weights.append(weights[index])
					if not upgrades.is_empty():
						var chosen: int = upgrades[Run._weighted_index(upgrade_weights,draft_rng)]
						offer.append(candidates[chosen])
						candidates.remove_at(chosen)
						weights.remove_at(chosen)
				for _draw: int in range(mini(3,candidates.size())):
					if offer.size() >= 3: break
					var chosen: int = Run._weighted_index(weights,draft_rng)
					offer.append(candidates[chosen])
					candidates.remove_at(chosen)
					weights.remove_at(chosen)
				if policy == "soft_depth":
					for index: int in range(offer.size()-1,0,-1):
						var swap_index: int = draft_rng.randi_range(0,index)
						var swap: String = offer[index]
						offer[index] = offer[swap_index]
						offer[swap_index] = swap
			if offer.is_empty(): break
			for id: String in offer:
				var rank: int = int(ranks.get(id,0))
				result["offered_new" if rank == 0 else ("offered_rank" if rank == 1 else "offered_mutation")] += 1
			var choice: String = offer[rng.randi_range(0,offer.size()-1)]
			if preference == "deepen":
				for id: String in offer:
					if int(ranks.get(id,0)) > int(ranks.get(choice,0)): choice = id
			var before: int = int(ranks.get(choice,0))
			result["picked_new" if before == 0 else ("picked_rank" if before == 1 else "picked_mutation")] += 1
			ranks[choice] = before + 1
		result.mean_families += ranks.size()
		result.families_min = mini(result.families_min,ranks.size())
		result.families_max = maxi(result.families_max,ranks.size())
		for rank: int in ranks.values():
			if rank == 3: result.mean_mutations += 1.0
	result.mean_families /= 256.0
	result.mean_mutations /= 256.0
	return result
