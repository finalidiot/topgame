extends SceneTree
## Corrected contract: retired mutations are historical records, never powers.
## Prior eight-branch fixture source is archived as text and results stay intact.
const Powers = preload("res://scripts/run_powers.gd")
const Fixture = preload("res://tests/mutation_physics_fixture_003a2.gd")
const Retired = preload("res://scripts/retired_power_metadata.gd")
var checks: int = 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var output: String = ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func physical(b: Node2D) -> Dictionary:
	var actors: Array[Dictionary] = []
	for f: Dictionary in b.fighters:
		actors.append({"id":f.entity_id,"pos":f.pos,"vel":f.vel,"rpm":f.rpm,"wobble":f.wobble,"outcome":f.outcome})
	return {"actors":actors,"time":b.elapsed,"status":b.battle_status,"ledger":b.continuous.economy.snapshot(),"events":b.powers.events.duplicate(true),"roster":b.roster.states.duplicate(true)}
func retired_pair(branch_id: String, owner: int) -> void:
	var family: String = str(Retired.MUTATIONS[branch_id].power_id)
	var historic: Dictionary = Powers.get_mutation(branch_id)
	check(historic.get("archived",false) and not historic.get("active",true),branch_id+" remains readable only as retired history")
	check(not branch_id in Powers.mutation_choices(family) and Powers.max_rank(family)==2,branch_id+" has no live Rank III offer")
	var retired: Node2D = Fixture.create(root,family,branch_id,owner,421)
	var parent: Node2D = Fixture.create(root,family,"",owner,421,2)
	check(retired.entity(owner).power_ranks[family]==2 and not retired.entity(owner).power_mutations.has(family),branch_id+" normalizes deterministically to its parent Rank II for owner "+str(owner))
	check(not retired.acquire_run_power(family,3,branch_id),branch_id+" cannot be acquired into a live Run")
	for tick: int in range(90):
		var direction: Vector2 = Vector2.RIGHT.rotated(float(tick)*.003)*.55
		var braking: bool = tick>=45 and tick<60
		retired.fixture_step(direction,tick==30,braking)
		parent.fixture_step(direction,tick==30,braking)
		check(physical(retired)==physical(parent),branch_id+" compatibility matches parent II physics/ledger/events at tick "+str(tick)+" owner "+str(owner))
	for effect: Dictionary in retired._power_fx:
		check(not effect.has("ecology_kind"),branch_id+" emits no retired renderer event")
	rows.append({"branch":branch_id,"owner":owner,"policy":"parent_rank_ii","fixed_ticks":90,"final":physical(retired)})
	retired.free(); parent.free()
func write_and_quit(label: String) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output=arg.trim_prefix("--report=")
	if not output.is_empty():
		if not output.is_absolute_path() or FileAccess.file_exists(output): quit(2); return
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":rows,"scope":"Declared initial ownership/pose and sampled input fixtures compare every retired ID to deterministic parent Rank II for player and NPC. Production solver/resource paths; no player save or natural-balance claim. Archived prior source remains text and prior result JSON is unchanged."},"\t"))
	print(label+"_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
func run() -> void:
	for owner: int in [1,2]:
		for branch_id: String in Retired.MUTATIONS: retired_pair(branch_id,owner)
	write_and_quit("MUTATION_RETIREMENT_PHYSICS")
