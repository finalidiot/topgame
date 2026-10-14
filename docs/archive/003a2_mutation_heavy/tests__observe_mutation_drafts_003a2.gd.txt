extends SceneTree
## Real draft eligibility and claim tokens; choice preferences and XP are fixtures.
const Draft = preload("res://tests/mutation_draft_policy_003a2.gd")
const Run = preload("res://scripts/run_context.gd")
const Parts = preload("res://scripts/parts.gd")
const Powers = preload("res://scripts/run_powers.gd")
var output: String=""
var label: String="development"
var seed_count: int=256
var require_new: bool=false
var checks: int=0
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok and not message in failures:failures.append(message);push_error(message)
func simulate(seed_value: int, policy: String, starter: String, detail: bool) -> Dictionary:
	var r: RefCounted=Run.new();r.start(Parts.DEFAULT_BUILD,seed_value,starter)
	var claims: Array[Dictionary]=[];var offers: Dictionary={};var branches: Dictionary={}
	var snapshots: Dictionary={};var ordinal: int=0;var first_mutation: int=0
	while not r.pending_offer.is_empty() and ordinal<32:
		var current_offer: Array=r.pending_offer
		var seen: Dictionary={}
		for family: String in current_offer:
			check(not seen.has(family) and Powers.can_progress(family,int(r.power_ranks.get(family,0)),str(r.power_mutations.get(family,""))),"Every actual offer is distinct and eligible")
			check(int(r.power_ranks.get(family,0))>0 or r.owned_power_ids.size()<Powers.FAMILY_CAP,"Full family slots cannot admit an eighth family")
			seen[family]=true;offers[family]=int(offers.get(family,0))+1
		var choice: String=Draft.choose_offer(r,policy,ordinal)
		var row: Dictionary=Draft.claim(r,choice,policy,ordinal)
		check(bool(row.accepted),"Synthetic preference accepts only a real current offered claim")
		if not row.accepted:break
		ordinal+=1;row["ordinal"]=ordinal
		if int(row.rank)==3:
			if first_mutation==0:first_mutation=ordinal
			check(row.branch_offer.size()==2 and row.branch in row.branch_offer,"RankIII always chooses one of two actual siblings")
			check(not Powers.can_progress(choice,3,str(row.branch)) and not choice in r.pending_offer,"Committed branch completes its family")
			branches[str(row.branch)]=int(branches.get(str(row.branch),0))+1
			check(not r.choose_mutation(str(row.token),str(row.branch)),"Committed mutation token cannot replay")
		check(not r.choose_power(str(row.token),choice),"Committed normal token cannot replay")
		check(r.owned_power_ids.size()<=7,"Seven-family cap stays authoritative")
		claims.append(row)
		if ordinal==1:check(Draft.award_declared_xp(r)>0,"Attributed XP fixture uses the ordinary progression award API")
		if ordinal in [6,12,18]:snapshots[str(ordinal)]={"families":r.owned_power_ids.size(),"mutations":r.power_mutations.size(),"ranks":r.power_ranks,"branches":r.power_mutations}
	check(r.pending_offer.is_empty() and r.pending_draft_id.is_empty(),"Eligible development terminates without an empty queued draft")
	check(ordinal==r.available_investment_capacity() and r.committed_rewards.size()==ordinal,"Full legal machine closes at its exact available investment ceiling")
	return {"seed":seed_value,"policy":policy,"starter":starter,"investments":ordinal,"first_mutation_ordinal":first_mutation,
		"families":r.owned_power_ids,"ranks":r.power_ranks,"branches":r.power_mutations,"offered_families":offers,
		"chosen_branches":branches,"snapshots":snapshots,"claims":claims if detail else [],"replay_claims":claims}

func group(cases: Array[Dictionary], policy: String) -> Dictionary:
	var selected: Array[Dictionary]=[]
	for item: Dictionary in cases:
		if item.policy==policy:selected.append(item)
	var result: Dictionary={"runs":selected.size(),"mean_families":0.0,"mean_mutations":0.0,"mean_first_mutation_ordinal":0.0,
		"families_available":{},"branches_available":{},"offered_families":{},"investment_snapshots":{}}
	for item: Dictionary in selected:
		result.mean_families+=item.families.size();result.mean_mutations+=item.branches.size();result.mean_first_mutation_ordinal+=int(item.first_mutation_ordinal)
		for family: String in item.families:result.families_available[family]=int(result.families_available.get(family,0))+1
		for branch: String in item.branches.values():result.branches_available[branch]=int(result.branches_available.get(branch,0))+1
		for family: String in item.offered_families:result.offered_families[family]=int(result.offered_families.get(family,0))+int(item.offered_families[family])
		for ordinal: String in item.snapshots:
			if not result.investment_snapshots.has(ordinal):result.investment_snapshots[ordinal]={"runs":0,"mean_families":0.0,"mean_mutations":0.0}
			var s: Dictionary=result.investment_snapshots[ordinal];s.runs+=1;s.mean_families+=int(item.snapshots[ordinal].families);s.mean_mutations+=int(item.snapshots[ordinal].mutations)
	result.mean_families/=maxi(1,selected.size());result.mean_mutations/=maxi(1,selected.size());result.mean_first_mutation_ordinal/=maxi(1,selected.size())
	for s: Dictionary in result.investment_snapshots.values():s.mean_families/=maxi(1,int(s.runs));s.mean_mutations/=maxi(1,int(s.runs))
	return result

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
		if arg.begins_with("--seeds="):seed_count=int(arg.trim_prefix("--seeds="))
		if arg=="--require-new":require_new=true
	if not output.is_absolute_path() or FileAccess.file_exists(output) or seed_count<8 or seed_count>1024:quit(2);return
	if require_new:check(Powers.ACTIVE_IDS.size()==16 and Powers.VERTICAL_IDS.size()==11 and Powers.MUTATIONS.size()==22,"Final expanded catalogue has sixteen bases, elevenIII families and twenty-two mutations")
	var cases: Array[Dictionary]=[];var groups: Dictionary={};var new_availability: Dictionary={};var actual_replays: int=0
	for policy: String in Draft.POLICIES:
		for seed_value: int in range(1,seed_count+1):
			var item: Dictionary=simulate(seed_value,policy,"custom",seed_value<=4)
			for starter: String in ["breaker","bastion","vane"]:
				var repeated: Dictionary=simulate(seed_value,policy,starter,false)
				check(item.replay_claims==repeated.replay_claims and item.ranks==repeated.ranks and item.branches==repeated.branches,"Identical seed/preferences replay exact legal claims across starter labels")
				actual_replays+=1
			item.erase("replay_claims");cases.append(item)
			for branch: String in item.branches.values():new_availability[branch]=int(new_availability.get(branch,0))+1
			if seed_value%32==0:await process_frame
		groups[policy]=group(cases,policy)
	if require_new:
		for family: String in Draft.NEW_PAIRS:
			for branch: String in Draft.NEW_PAIRS[family]:check(int(new_availability.get(branch,0))>0,branch+" is reached by legal deterministic draft policies")
	var forms: int=0
	for family: String in Powers.ACTIVE_IDS:forms+=2+Powers.mutation_choices(family).size()
	var result: Dictionary={"label":label,"checks":checks,"failures":failures,"seed_count":seed_count,"policies":Draft.POLICIES,
		"branch_preference_models":Draft.PREFERRED_BRANCHES,"runs":cases.size(),"starter_replays":actual_replays,"groups":groups,"cases":cases,
		"catalogue":{"active_families":Powers.ACTIVE_IDS.size(),"rankIII_families":Powers.VERTICAL_IDS.size(),"mutations":Powers.MUTATIONS.size(),"visible_forms":forms,"investments":Powers.investment_capacity(),"family_cap":Powers.FAMILY_CAP},
		"new_branch_availability":new_availability,"collection_opened":false,"live_quota":false,
		"scope":"Seeded real RunContext offers, actual eligibility and current claim IDs. Five declared analytical choice policies and attributed elimination-XP fixtures complete legal machines; no private forced offers/ranks or live gameplay quotas. Three additional starter-label replays per case verify no hard starter classes. Availability and selected breadth/depth describe these choice models, not natural XP timing, player preference, universal-pick balance or combat survival. Runtime gameplay fixture evidence is recorded separately on the same final source boundary."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(Draft.portable(result),"\t"))
	print("MUTATION_DRAFT_STUDY_%s runs=%d starter_replays=%d checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",cases.size(),actual_replays,checks,failures.size()]);quit(0 if failures.is_empty() else 1)
