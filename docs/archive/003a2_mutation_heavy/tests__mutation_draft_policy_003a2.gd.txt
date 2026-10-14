extends RefCounted
## QA choice models. These preferences never change the production draft weights.
const Run = preload("res://scripts/run_context.gd")
const Parts = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Seeds = preload("res://scripts/seed_utils.gd")
const NEW_PAIRS: Dictionary = {
	"iron_comet":["wallbreaker","ricochet_engine"],
	"orbit_drive":["centrifuge","perpetual_orbit"],
	"momentum_bank":["flywheel_release","countersteer"],
	"crash_guard":["reactive_plating","sacrificial_damper"]
}
const POLICIES: Dictionary = {
	"aggression":["redline","iron_comet","momentum_bank","predator_line","chain_impact","high_gear","crosscut"],
	"fortress":["crash_guard","dead_centre","impact_sink","anchor_exchange","gyro_lock","clutch","momentum_bank"],
	"technique":["orbit_drive","momentum_bank","iron_comet","afterimage","crosscut","gyro_lock","high_gear"],
	"endurance":["orbit_drive","clutch","gyro_lock","impact_sink","dead_centre","anchor_exchange","crash_guard"],
	"hybrid":[]
}
const PREFERRED_BRANCHES: Dictionary = {
	"aggression":{"iron_comet":"wallbreaker","orbit_drive":"centrifuge","momentum_bank":"flywheel_release","crash_guard":"reactive_plating"},
	"fortress":{"crash_guard":"sacrificial_damper","orbit_drive":"perpetual_orbit","momentum_bank":"countersteer","iron_comet":"ricochet_engine"},
	"technique":{"iron_comet":"ricochet_engine","orbit_drive":"centrifuge","momentum_bank":"countersteer","crash_guard":"reactive_plating"},
	"endurance":{"orbit_drive":"perpetual_orbit","crash_guard":"sacrificial_damper","momentum_bank":"countersteer","iron_comet":"ricochet_engine"}
}

static func seeded_opening(family: String) -> int:
	for seed_value: int in range(1,513):
		var run: RefCounted=Run.new();run.start(Parts.DEFAULT_BUILD,seed_value)
		if family in run.pending_offer:return seed_value
	return -1

static func award_declared_xp(run: RefCounted, count: int=124) -> int:
	## Attributed elimination events are an explicit XP fixture, not won combats.
	var accepted: int=0
	for index: int in range(count):
		accepted+=int(run.award_xp({"kind":"elimination","encounter_id":run.current_encounter().id,
			"time":1.0+index*.0166666667,"entity_id":1000+index,"combatant_type":"full_top",
			"reason":"spin_out","player_attributed":true}))
	return accepted

static func choose_offer(run: RefCounted, policy: String, ordinal: int) -> String:
	var offer: Array=run.pending_offer
	if offer.is_empty():return ""
	var rng:=RandomNumberGenerator.new();rng.seed=Seeds.derive(run.run_seed,"003a2/choice/%s/%d"%[policy,ordinal])
	if policy=="hybrid":return str(offer[rng.randi_range(0,offer.size()-1)])
	var priorities: Array=POLICIES.get(policy,[])
	var best: String=str(offer[0]);var best_score: float=-1000.0
	for id: String in offer:
		var position: int=priorities.find(id)
		var score: float=(16.0-float(position)*1.6 if position>=0 else 1.0)+float(run.power_ranks.get(id,0))*2.4+rng.randf()*.4
		if score>best_score:best_score=score;best=id
	return best

static func choose_branch(run: RefCounted, policy: String, ordinal: int) -> String:
	var branches: Array=run.pending_mutation_offer
	if branches.is_empty():return ""
	var rng:=RandomNumberGenerator.new();rng.seed=Seeds.derive(run.run_seed,"003a2/branch/%s/%d"%[policy,ordinal])
	var preferred: String=str(PREFERRED_BRANCHES.get(policy,{}).get(run.pending_mutation_power,""))
	if preferred in branches and rng.randf()<.75:return preferred
	return str(branches[rng.randi_range(0,branches.size()-1)])

static func claim(run: RefCounted, id: String, policy: String, ordinal: int, desired_branch: String="") -> Dictionary:
	var token: String=run.pending_draft_id;var before: int=int(run.power_ranks.get(id,0))
	var offer: Array=run.pending_offer;var branches: Array=[];var selected: String=""
	if not run.choose_power(token,id):return {"accepted":false,"token":token,"id":id}
	if not run.pending_mutation_power.is_empty():
		branches=run.pending_mutation_offer
		selected=desired_branch if desired_branch in branches else choose_branch(run,policy,ordinal)
		if not run.choose_mutation(token,selected):return {"accepted":false,"token":token,"id":id,"branch":selected}
	return {"accepted":true,"token":token,"id":id,"offer":offer,"before":before,
		"rank":int(run.power_ranks.get(id,0)),"branch_offer":branches,"branch":selected,
		"families":run.owned_power_ids.size(),"mutations":run.power_mutations.size()}

static func portable(value: Variant) -> Variant:
	if value is Vector2:return [value.x,value.y]
	if value is Vector2i:return [value.x,value.y]
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(portable(item))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=portable(value[key])
		return result
	return value
