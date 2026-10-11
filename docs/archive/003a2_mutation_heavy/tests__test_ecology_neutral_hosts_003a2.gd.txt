extends SceneTree
## Neutral ecology hooks preserve the accepted standalone host API. The legacy
## Host is reused unchanged: it has no powers/roster/battle_status/paused fields.
const Legacy = preload("res://tests/test_ability_rebalance.gd")
const Runtime = preload("res://scripts/power_runtime.gd")
const Roster = preload("res://scripts/roster_runtime.gd")
const Ecology = preload("res://scripts/ecology_runtime.gd")
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
func snapshot(h: RefCounted, e: RefCounted) -> Dictionary:
	return {"actors":h.fighters.duplicate(true),"effects":h.effects.duplicate(true),"impulses":h.impulses.duplicate(true),
		"gains":h.gains,"losses":h.losses,"states":e.states.duplicate(true),"counters":e.counters.duplicate()}

func neutral_hooks(f: Dictionary, label: String) -> void:
	var h: RefCounted = minimal_host(f)
	var e: RefCounted = Ecology.new(); e.setup(h)
	var canonical: RefCounted = Runtime.new()
	for family: String in Catalog.ACTIVE_IDS:
		check(e.branch(f,family) == canonical.mutation(f,family),label+" branch lookup agrees with canonical validation without a Battle API")
	check(not e.owns(f),label+" is neutral to the four new mutation families")
	var before: Dictionary = snapshot(h,e)
	e.begin_tick(1.0/60.0)
	check(near(e.time,1.0/60.0) and before == snapshot(h,e),label+" tick advances only its clock and allocates no neutral mechanisms")
	var direction: Vector2 = Vector2(.2,.7)
	var controls: Dictionary = e.controls(f,direction,true)
	check(controls.direction == direction and controls.braking and not controls.committed,label+" controls return raw input and Brake")
	var m: Dictionary = {"direction":direction,"braking":true,"speed":1.2,"acceleration":1.3,"drain":.9,"drag":.2}
	check(e.movement(f,m.duplicate(),1.0/60.0) == m,label+" movement returns the exact existing modifiers")
	var after: Vector2 = Vector2(140,50)
	check(e.velocity(f,f.vel,after,1.0/60.0) == after,label+" velocity leaves existing movement unchanged")
	var reflected: Vector2 = Vector2(-150,40)
	check(e.wall_velocity(f,Vector2(200,40),reflected,200.0,Vector2.RIGHT,f.pos) == reflected,label+" wall reflection remains exact")
	check(not e.burst(f,Vector2.UP,Vector2(180,40)),label+" Burst remains available to the accepted legacy handler")
	var response: Dictionary = e.prepare_contact(f,h.entity(2),1.3,Vector2.RIGHT,Vector2.ZERO,Vector2(-300,0),200.0)
	check(response == {"recoil":1.0,"shock":1.0,"cost":0.0},label+" contact response is exactly neutral")
	e.contact(f,h.entity(2),1.3,Vector2.RIGHT,Vector2(200,200))
	check(e.collision_cost(f) == 1.0,label+" ecology adds no guard to the accepted collision cost")
	check(before == snapshot(h,e),label+" neutral hooks change no actor/store/RPM/FX/provenance work")
	observations.append({"label":label,"neutral":not e.owns(f),"host_class":"unchanged test_ability_rebalance.Host",
		"extra_battle_properties_added":false,"state_unchanged":before == snapshot(h,e)})

func rank_and_branch_validation() -> void:
	var h: RefCounted = minimal_host(fighter(1,"",1,""))
	var e: RefCounted = Ecology.new(); e.setup(h)
	var canonical: RefCounted = Runtime.new()
	for rank_value: int in [-2,0,1,2,3,4,99]:
		for family: String in Ecology.FAMILIES:
			for branch_value: String in Catalog.mutation_choices(family):
				var f: Dictionary = fighter(1,family,rank_value,branch_value)
				var expected: String = branch_value if rank_value >= 3 else ""
				check(e.branch(f,family) == expected and e.branch(f,family) == canonical.mutation(f,family),family+" rank clamp/branch membership exactly matches the accepted canonical validator")
				check(e.owns(f) == (rank_value >= 3),family+" invalid lower ranks cannot opt into new III through metadata alone")
				if family == "momentum_bank":
					var capacity: float = 240.0 if rank_value >= 3 and branch_value == "flywheel_release" else (95.0 if rank_value <= 1 else 150.0)
					check(e.bank_capacity(f) == capacity,family+" capacity uses the same clamped owned rank without host.roster")
	var unowned: Dictionary = fighter(1,"",1,"")
	unowned.power_ranks = {"momentum_bank":99}; unowned.power_mutations = {"momentum_bank":"flywheel_release"}
	check(not e.owns(unowned) and e.branch(unowned,"momentum_bank").is_empty() and e.bank_capacity(unowned) == 150.0,"Unowned forged rank/branch metadata cannot create a240 reservoir or ecology ownership")
	check(e.states.is_empty() and e.counters.is_empty() and h.effects.is_empty() and h.losses == 0.0,"Pure rank/capacity lookups create no state, FX or RPM cost")

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
		check(near(h.losses,.009+stored*.000065) and r.ecology.states.is_empty() and r.ecology.counters.is_empty(),"Accepted Bank rank"+str(rank_value)+" retains original fee without new mechanism state")
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
		check(r.ecology.states.is_empty() and r.ecology.counters.is_empty() and h.losses == 0.0,"Accepted Orbit rank"+str(rank_value)+" adds no III state/FX/correction fee")
	check(near(observed_drive[0],observed_drive[1]),"Accepted Orbit I/II retain the same observed charge-growth rate on identical controls")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	if not output.is_absolute_path() or FileAccess.file_exists(output) or not "/gyrobrothers-qa/003a.2/manifests/" in output.replace("\\","/").to_lower(): quit(2); return
	neutral_hooks(fighter(1,"",1,""),"unowned")
	for family: String in Catalog.ACTIVE_IDS:
		for rank_value: int in [1,2]: neutral_hooks(fighter(1,family,rank_value,""),family+" rank"+str(rank_value))
		if not family in Ecology.FAMILIES:
			for branch_value: String in Catalog.mutation_choices(family): neutral_hooks(fighter(1,family,3,branch_value),branch_value+" accepted oldIII")
	for family: String in Ecology.FAMILIES:
		neutral_hooks(fighter(1,family,3,"invalid_branch"),family+" invalid branch")
		neutral_hooks(fighter(1,family,2,Catalog.mutation_choices(family)[0]),family+" uncommitted branch metadata")
	neutral_hooks(fighter(1,"iron_comet",3,"centrifuge"),"wrong-family branch")
	rank_and_branch_validation(); accepted_roster_paths()
	var report: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	check(report != null,"Neutral compatibility writes only its requested fresh external003A.2 report")
	if report != null:
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,
			"scope":"Unchanged accepted minimal Host API; all active I/II, fourteen accepted old III, invalid/lower-rank/wrong-family/unowned metadata exercise neutral hooks. Independent exact canonical rank-clamp/branch/capacity parity and reachable accepted Bank/Orbit roster paths. New III activation requires a real Battle separately; this test does not supply extra Battle fields or claim new mutation physics/balance."},"\t"))
	print("ECOLOGY_NEUTRAL_HOSTS_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
