extends SceneTree
## Legal claim IDs and production Battle acquisition; no collection is opened.
const Draft = preload("res://tests/mutation_draft_policy_003a2.gd")
const Run = preload("res://scripts/run_context.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Battle = preload("res://scripts/battle.gd")
const Starters = preload("res://scripts/starters.gd")
const Encounters = preload("res://scripts/encounters.gd")
var checks: int=0
var failures: Array[String]=[]
var rows: Array[Dictionary]=[]
var output: String=""

func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func physical(b: Node2D) -> Dictionary:
	var f: Dictionary=b.player_entity()
	return {"time":b.elapsed,"power_time":b.powers.time,"roster_time":b.roster.time,
		"pos":f.pos,"vel":f.vel,"rpm":f.rpm,"wobble":f.wobble,"outcome":f.outcome,
		"radius":f.radius,"mass":f.mass,"build":f.build.duplicate(true),"economy":b.continuous.economy.snapshot()}
func acquire(family: String, branch: String) -> void:
	var seed_value: int=Draft.seeded_opening(family)
	check(seed_value>0,family+" has a normal seeded opening offer")
	if seed_value<0:return
	var run: RefCounted=Run.new();run.start(Starters.build_for("vane"),seed_value,"vane")
	var b: Node2D=Battle.new();root.add_child(b);b.set_process(false);b.set_physics_process(false)
	var d: Dictionary=Encounters.for_run_event(1,seed_value);d.starter_id="vane"
	b.begin_run(Starters.build_for("vane"),d,seed_value);b.set_paused(true)
	var identity: Dictionary=b.player_entity();var origin: Dictionary=physical(b)
	var installed: Array[Dictionary]=[];var ordinal: int=0
	while ordinal<32:
		if run.pending_offer.is_empty():break
		var choice: String=family if family in run.pending_offer else Draft.choose_offer(run,"hybrid",ordinal)
		var rank_before: int=int(run.power_ranks.get(choice,0));var token: String=run.pending_draft_id
		if choice==family and rank_before==2:
			check(not b.acquire_run_power(family,3,"not_a_branch"),branch+" rejects an invalid branch without installation")
			check(not run.choose_mutation(token,branch),branch+" cannot bypass the pending mutation choice")
			check(run.choose_power(token,family),branch+" opens RankIII using a genuine offered claim")
			check(run.pending_mutation_offer==Powers.mutation_choices(family) and run.pending_mutation_offer.size()==2,branch+" offers both real siblings")
			check(int(run.power_ranks[family])==2,branch+" does not commit a partial RankIII")
			check(not run.choose_mutation("stale/"+token,branch),branch+" rejects a stale choice token")
			check(run.choose_mutation(token,branch),branch+" commits the selected legal sibling")
			check(b.acquire_run_power(family,3,branch),branch+" installs through the production Battle method")
			installed.append({"ordinal":ordinal+1,"token":token,"id":family,"rank":3,"branch":branch})
			var other: String=str(Draft.NEW_PAIRS[family][1] if branch==Draft.NEW_PAIRS[family][0] else Draft.NEW_PAIRS[family][0])
			check(not run.choose_mutation(token,other) and not b.acquire_run_power(family,3,other),branch+" excludes its sibling and duplicate acquisition")
			check(not Powers.can_progress(family,3,branch) and Powers.get_offer(family,3,branch).is_empty(),branch+" completes the family rather than reopening a fourth investment")
			check(not family in run.pending_offer,branch+" is absent from subsequent normal offers")
			check(run.power_mutations[family]==branch and identity.power_mutations[family]==branch,branch+" preserves selected identity in both authoritative owners")
			check(is_same(identity,b.player_entity()),branch+" preserves the exact live player object")
			check(origin==physical(b),branch+" paused acquisition changes no physics, economy, reserve or clocks")
			var prior: Dictionary=physical(b)
			for read: int in range(60):b.powers.public_state(identity)
			check(prior==physical(b),branch+" repeated public inspection is pure")
			rows.append({"family":family,"branch":branch,"seed":seed_value,"claims":installed,"run_rank":run.power_ranks[family],"player_rank":identity.power_ranks[family],"initial":origin,"final":physical(b),"siblings":Powers.mutation_choices(family)})
			b.free();return
		var result: Dictionary=Draft.claim(run,choice,"hybrid",ordinal)
		check(bool(result.accepted),branch+" setup uses only a current legal offer")
		if not result.accepted:break
		check(b.acquire_run_power(choice,int(result.rank),str(result.branch)),branch+" mirrors each genuine Run claim through Battle")
		check(not run.choose_power(token,choice),branch+" duplicate callbacks cannot spend the same claim twice")
		installed.append(result)
		if ordinal==0:check(Draft.award_declared_xp(run)>0,branch+" queues levels through declared attributed XP events")
		ordinal+=1
	check(false,branch+" was not reached through the legal draft")
	b.free()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	if not output.is_absolute_path() or FileAccess.file_exists(output):quit(2);return
	check(Powers.ACTIVE_IDS.size()==16 and Powers.VERTICAL_IDS.size()==11,"Sixteen bases and eleven developed families")
	check(Powers.MUTATIONS.size()==22 and Powers.investment_capacity()==43 and Powers.FAMILY_CAP==7,"Twenty-two sibling choices retain seven machine slots and forty-three catalogue investments")
	var forms: int=0
	for id: String in Powers.ACTIVE_IDS:
		forms+=2+Powers.mutation_choices(id).size()
	check(forms==54,"Fifty-four visible base/rank/branch forms")
	for family: String in Draft.NEW_PAIRS:
		check(Powers.mutation_choices(family)==Draft.NEW_PAIRS[family],family+" matches the agreed behavioral pair")
		for branch: String in Draft.NEW_PAIRS[family]:acquire(family,branch)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(Draft.portable({"checks":checks,"failures":failures,"acquisitions":rows,
		"scope":"All eight new branches through genuine seeded RunContext offers, current claim IDs and production acquire_run_power during paused READY. Attributed XP events are declared level-queue fixtures, not natural won combat. No Main/profile/collection opened; no live physics or balance claim."}),"\t"))
	print("MUTATION_ACQUISITION_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()]);quit(0 if failures.is_empty() else 1)
