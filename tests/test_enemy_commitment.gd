extends SceneTree
const Roles = preload("res://scripts/enemy_roles.gd")
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func fighter(role: String, id: int = 2, archetype: String = "") -> Dictionary:
	return {"pos":Vector2(80,0), "entity_id":id, "role":role, "archetype":role if archetype.is_empty() else archetype, "role_phase":float(id)*0.7}

func _run() -> void:
	var player: Dictionary = {"pos":Vector2.ZERO,"vel":Vector2(14,0)}
	for role: String in Roles.BUILDS:
		for id: int in range(2,18):
			var f: Dictionary = fighter(role,id)
			var committed: bool = false
			var recovering: bool = false
			var setup: bool = false
			for tick: int in range(240):
				var time: float = 600.0+float(tick)*0.05
				var d: Vector2 = Roles.direction(f,player,time)
				check(d.is_finite() and d.length() <= 0.951,"Finite bounded mature role steering")
				committed = committed or f.role_attack_state == "committed"
				recovering = recovering or f.role_attack_state == "recover"
				setup = setup or f.role_attack_state == "set_up"
				if f.role_attack_state != "committed": check(not Roles.wants_burst(f,player,time),"No Burst while setting up or recovering")
			check(committed and recovering and setup,"Every later role has finite setup, committed attack and recovery")
			check(f.size() <= 9 and f.pilot.size()<=36 and f.pilot.history.size()<=Roles.MAX_HISTORY,"Per-enemy decision state and recent history remain bounded")
	_test_sampled_commitment()
	_test_entry_ties()
	print("ENEMY_COMMITMENT_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)

func _test_sampled_commitment() -> void:
	for role: String in Roles.BUILDS:
		var f: Dictionary = fighter(role)
		var p: Dictionary = {"pos":Vector2.ZERO,"vel":Vector2.ZERO}
		var time: float = 600.0
		while time < 610.0:
			Roles.direction(f,p,time)
			# The human-requested observed-state layer supersedes periodic beats.
			if f.pilot.state == "commit" and time-float(f.pilot.entered)>0.16: break
			time += 0.01
		var heading: Vector2 = f.role_commit_heading
		check(heading.x < -0.95,"Real run-up points through the observed target")
		p.pos = Vector2(0,60)
		p.vel = Vector2(250,0)
		var held: Vector2 = Roles.direction(f,p,time+0.05)
		check(held.normalized().is_equal_approx(heading),"A committed enemy cannot track a dodge or read future input")
		f.pos = Vector2(-30,0)
		p.pos = Vector2.ZERO
		check(Roles.direction(f,p,time+0.10).normalized().x < -0.95 and f.pilot.state=="follow_through","Committed heading physically follows through after crossing the player")
		check(not Roles.wants_burst(f,p,time+0.10),"Enemy cannot Burst backward onto a passed target")
	var heavy: Dictionary = fighter("bulwark",2,"anvil")
	var opening: Vector2 = Roles.direction(heavy,{"pos":Vector2.ZERO,"vel":Vector2.ZERO},2.5)
	check(opening.length() <= 0.73 and heavy.pilot.state=="position","First heavy rival uses restrained readable positioning")
	check(Roles.ELITES.ballast.mass == 1.55 and Roles.BOSSES.anvil.mass == 2.0,"Existing physical mass tradeoffs stay exact")

func _test_entry_ties() -> void:
	var b: Node2D = Battle.new()
	root.add_child(b)
	b.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1,421)
	descriptor.starter_id = "bastion"
	b.begin_run(Starters.build_for("bastion"),descriptor,421)
	b.player_entity().pos = Vector2.ZERO
	b.entity(2).outcome = "declared_port_unit_fixture"
	var ports: Dictionary = {}
	for serial: int in range(2,10):
		b.continuous.pending = {"serial":serial}
		var port: Vector2 = b.continuous._safe_entry()
		ports[str(port)] = true
		check(port.is_finite() and port.distance_to(b.player_entity().pos) >= 60.0,"Entry port retains physical player clearance")
	check(ports.size() == 4,"Equal-safe centre entries use all four real ports")
	b.player_entity().pos = Vector2(115,30)
	for serial: int in range(2,10):
		b.continuous.pending = {"serial":serial}
		check(b.continuous._safe_entry() == Vector2(-115,-30),"Tie rotation never overrides the truly furthest safe port")
	b.free()
