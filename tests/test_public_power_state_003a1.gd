extends SceneTree
## Genuine draft acquisition seams while READY is paused. The public getter
## must derive immediate capacity without advancing or changing combat state.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var output: String = ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); push_error(text)

func make_battle(opening_rank: int) -> Node2D:
	var b: Node2D = Battle.new()
	root.add_child(b); b.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1, 421)
	descriptor.starter_id = "bastion"
	descriptor.player_power_ids = ["impact_sink"] if opening_rank > 0 else []
	descriptor.player_power_ranks = {"impact_sink":opening_rank} if opening_rank > 0 else {}
	b.begin_run(Starters.build_for("bastion"), descriptor, 421)
	b.battle_status = "reentry" # Explicit UI seam; this is not a survival fixture.
	b.set_paused(true)
	return b

func physical_state(b: Node2D) -> Dictionary:
	return {"elapsed":b.elapsed,"paused":b.paused,"status":b.battle_status,
		"fighter":b.player_entity().duplicate(true),"powers":b.powers._states.duplicate(true),
		"power_clock":b.powers.time,"defence":b.powers.defence.states.duplicate(true),
		"defence_clock":b.powers.defence.time,"roster":b.roster.states.duplicate(true),
		"economy":b.continuous.economy.snapshot()}

func inspect_capacity(b: Node2D, expected: float, label: String) -> void:
	var before: Dictionary = physical_state(b)
	var actual: Dictionary = {}
	for read: int in range(60): actual = b.powers.public_state(b.player_entity())
	check(actual.sink.owned and is_equal_approx(float(actual.sink.capacity),expected), label + " shows its authoritative current-rank Sink capacity before GO")
	check(actual.sink.stored == 0.0 and actual.sink.ratio == 0.0, label + " cannot invent stored incoming force")
	check(before == physical_state(b), label + " public reads preserve all clocks, reserve, physical and mechanism state")
	b.test_step(Battle.FIXED_DT,Vector2.RIGHT,true,true)
	check(before == physical_state(b), label + " paused READY cannot spend, move or mature the power")
	observations.append({"seam":label,"expected_capacity":expected,"actual":actual.sink,"cached_fighter_capacity":b.player_entity().get("sink_capacity",0.0),"paused":b.paused,"status":b.battle_status})

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	if not output.is_absolute_path() or FileAccess.file_exists(output): push_error("Fresh explicit external test report required"); quit(2); return
	var fresh: Node2D = make_battle(0)
	check(not fresh.powers.public_state(fresh.player_entity()).sink.owned,"Unowned Sink has no stateful meter")
	check(fresh.acquire_run_power("impact_sink",1),"A real first-rank acquisition succeeds during the paused transition")
	inspect_capacity(fresh,90.0,"Fresh Rank I acquisition")
	check(fresh.acquire_run_power("impact_sink",2),"A real Rank II upgrade succeeds without a live simulation tick")
	inspect_capacity(fresh,150.0,"Immediate Rank II draft upgrade")
	check(fresh.acquire_run_power("impact_sink",3,"shock_bleed"),"A real legal Rank III mutation succeeds while READY is paused")
	inspect_capacity(fresh,150.0,"Immediate Shock Bleed mutation")
	fresh.free()
	var upgraded: Node2D = make_battle(1)
	check(upgraded.player_entity().sink_capacity == 90.0,"Opening rankI fixture has the normal cached capacity")
	check(upgraded.acquire_run_power("impact_sink",2),"Existing ownership upgrades through the production acquisition method")
	inspect_capacity(upgraded,150.0,"Rank II with an existing Rank I cache")
	upgraded.free()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"Production acquire_run_power in a declared paused READY seam; repeated public-state reads must be pure and immediately reflect current ownership/rank.","collection_accessed":false},"\t"))
	print("PUBLIC_POWER_STATE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
