extends SceneTree
## After removing rejected III hooks, accepted Bank and Orbit retain the exact
## standalone Host API and their ordinary original rank I/II arithmetic.
const Legacy = preload("res://tests/test_ability_rebalance.gd")
const Runtime = preload("res://scripts/power_runtime.gd")
const Roster = preload("res://scripts/roster_runtime.gd")
const Catalog = preload("res://scripts/run_powers.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var output: String = ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func near(a: float, b: float) -> bool: return absf(a-b) < 0.000001
func fighter(id: int, family: String, rank_value: int, branch_value: String) -> Dictionary:
	return {"entity_id":id,"owner_id":"player" if id == 1 else "rival","team_id":"player" if id == 1 else "hostile",
		"combatant_type":"full_top","pos":Vector2.ZERO if id == 1 else Vector2(20,0),"vel":Vector2(180,40),
		"radius":12.0,"mass":8.0,"rpm":1.0,"energy":1.0,"wobble":0.0,"outcome":"",
		"powers":[] if family.is_empty() else [family],"power_ranks":{} if family.is_empty() else {family:rank_value},
		"power_mutations":{} if family.is_empty() or branch_value.is_empty() else {family:branch_value},
		"burst_time":0.0,"height":0.0,"height_vel":0.0}
func minimal_host(f: Dictionary) -> RefCounted:
	var h: RefCounted = Legacy.Host.new()
	h.fighters.assign([f,fighter(2,"",1,"")])
	return h
func accepted_roster_paths() -> void:
	for rank_value: int in [1,2]:
		var p: Dictionary = fighter(1,"momentum_bank",rank_value,"")
		var h: RefCounted = minimal_host(p)
		var r: RefCounted = Roster.new(); r.setup(h)
		r.begin_tick(1.0/60.0)
		r.movement(p,{"direction":Vector2.RIGHT,"braking":true,"speed":1.0,"acceleration":1.0,"drain":1.0,"drag":0.0},1.0/60.0)
		p.vel = r.velocity(p,Vector2(200,0),Vector2(160,0),1.0/60.0)
		var stored: float = 24.8 if rank_value == 1 else 34.0
		check(near(float(r.state(p).bank),stored),"Accepted Bank rank"+str(rank_value)+" stores actual lost brake motion with the original rate")
		r.burst(p,Vector2.RIGHT,Vector2(200,0))
		check(Vector2(p.vel).distance_to(Vector2(160.0+stored,0)) < 0.00001 and near(float(r.state(p).bank),0.0),"Accepted Bank rank"+str(rank_value)+" legacy release remains reachable through the original host")
		check(near(h.losses,.009+stored*.000065),"Accepted Bank rank"+str(rank_value)+" retains original fee without new mechanism state")
	var observed_drive: Array[float] = []
	for rank_value: int in [1,2]:
		var p: Dictionary = fighter(1,"orbit_drive",rank_value,"")
		var h: RefCounted = minimal_host(p)
		var r: RefCounted = Roster.new(); r.setup(h)
		for tick: int in range(70):
			var before: Vector2 = Vector2.RIGHT.rotated(float(tick)/60.0)*180.0
			p.vel = before
			r.movement(p,{"direction":before.normalized().rotated(.5),"braking":true,"acceleration":1.0,"speed":1.0,"drag":0.0,"drain":1.0},1.0/60.0)
			r.velocity(p,before,before.rotated(1.0/60.0),1.0/60.0)
		check(float(p.orbit_charge) > 0.0 and p.drift_active,"Accepted Orbit rank"+str(rank_value)+" still earns real Brake-turn charge through the minimal host")
		observed_drive.append(float(p.orbit_charge))
		check(h.losses == 0.0,"Accepted Orbit rank"+str(rank_value)+" adds no III state/FX/correction fee")
	check(near(observed_drive[0],observed_drive[1]),"Accepted Orbit I/II retain the same observed charge-growth rate on identical controls")

func run() -> void:
	accepted_roster_paths()
	var p: Dictionary=fighter(1,"momentum_bank",2,"")
	var h: RefCounted=minimal_host(p)
	var r: RefCounted=Roster.new();r.setup(h)
	r.state(p).bank=150.0;r.begin_tick(1.0)
	check(near(float(r.state(p).bank),143.0),"Accepted Bank II retains seven units per second leakage")
	check(r.get("ecology")==null,"Roster contains no rejected mutation runtime boundary")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	if not output.is_empty():
		if not output.is_absolute_path() or FileAccess.file_exists(output):quit(2);return
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Original standalone Host reused unchanged. Accepted Bank I/II store real braking loss, release ordinary paid Burst stock and leak at original rate. Accepted Orbit I/II retain identical charge growth. Retired hook tests archived as text and old results preserved."},"\t"))
	print("ACCEPTED_ROSTER_HOSTS_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
