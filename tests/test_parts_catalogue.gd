extends SceneTree
## Catalogue validity + physical observable tests. Real saves are never loaded.
const Parts = preload("res://scripts/parts.gd")
const Physics = preload("res://scripts/part_physics.gd")
const Battle = preload("res://scripts/battle.gd")
const Starters = preload("res://scripts/starters.gd")
const Encounters = preload("res://scripts/encounters.gd")
var checks: int = 0
var failures: Array[String] = []
var report_path: String = "user://002c5_2_parts_tests.json"
var observations: Dictionary = {}

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL: "+label)

func build(blade: String = "balance", ratchet: String = "mid", bit: String = "ball") -> Dictionary:
	return {"blade":blade,"ratchet":ratchet,"bit":bit}

func battle(assembly: Dictionary) -> Node2D:
	var b = Battle.new()
	root.add_child(b); b.set_physics_process(false); b.set_process(false)
	b.begin(assembly,build("guard"),1,73519)
	b.battle_status = "battle"
	return b

func finite(fighter: Dictionary) -> bool:
	return Vector2(fighter.pos).is_finite() and Vector2(fighter.vel).is_finite() and is_finite(float(fighter.rpm)) and is_finite(float(fighter.wobble)) and float(fighter.mass) > 0.0

func motion_probe(assembly: Dictionary) -> Dictionary:
	var b: Node2D = battle(assembly)
	var p: Dictionary = b.player_entity()
	p.pos = Vector2.ZERO; p.vel = Vector2.ZERO; p.wobble = 0.6
	var result: Dictionary = {"mean_speed":0.0,"peak_speed":0.0,"rpm_retention":0.0,"drive_speed":0.0,"coast_speed":0.0,"brake_speed":0.0,"control_response":0.0,"recovery":0.0,"wobble":0.0,"finite":true}
	for tick: int in range(210):
		var input: Vector2 = Vector2.RIGHT if tick < 60 else Vector2.ZERO if tick < 120 else Vector2.UP
		b._update_fighter(p,input,tick >= 180,Battle.FIXED_DT)
		result.mean_speed += Vector2(p.vel).length()/210.0
		result.peak_speed = maxf(result.peak_speed,Vector2(p.vel).length())
		result.finite = result.finite and finite(p)
		if tick == 59: result.drive_speed = Vector2(p.vel).length(); result.recovery = 0.6-float(p.wobble)
		if tick == 119: result.coast_speed = Vector2(p.vel).length()
		if tick == 179: result.control_response = -Vector2(p.vel).y
	result.brake_speed = Vector2(p.vel).length(); result.rpm_retention = p.rpm; result.wobble = p.wobble
	b.free()
	return result

func contact_probe(assembly: Dictionary, angle: float = 0.0, lateral: float = 0.0, repeats: int = 1) -> Dictionary:
	var b: Node2D = battle(assembly)
	var p: Dictionary = b.player_entity()
	var e: Dictionary = b.entity(2)
	var result: Dictionary = {"opponent_damage":0.0,"own_damage":0.0,"recoil":0.0,"delivery":0.0,"lateral_delivery":0.0,"sequence":[],"finite":true}
	for index: int in range(repeats):
		b.elapsed = float(index)*0.2; b._pair_cooldowns.clear()
		p.spin_angle = angle; p.pos = Vector2(-8,0); p.vel = Vector2(160,lateral); p.rpm = 0.8; p.wobble = 0.0
		e.pos = Vector2(8,0); e.vel = Vector2(-60,0); e.rpm = 0.8; e.wobble = 0.0
		b.resolve_pair(1,2)
		result.opponent_damage += 0.8-float(e.rpm); result.own_damage += 0.8-float(p.rpm)
		result.sequence.append(0.8-float(e.rpm))
		result.recoil = Vector2(p.vel).distance_to(Vector2(160,lateral))
		result.delivery = Vector2(e.vel).distance_to(Vector2(-60,0)); result.lateral_delivery = absf(Vector2(e.vel).y)
		result.finite = result.finite and finite(p) and finite(e)
	b.free()
	return result

func wall_probe(assembly: Dictionary) -> Dictionary:
	var b: Node2D = battle(assembly)
	var p: Dictionary = b.player_entity()
	p.pos = Vector2(170,50); p.vel = Vector2(250,0); p.rpm = 0.8
	b._resolve_boundary(p)
	var result: Dictionary = {"speed":Vector2(p.vel).length(),"sideways":absf(Vector2(p.vel).y),"rpm_loss":0.8-float(p.rpm)}
	b.free()
	return result

func peak_contact_probe(assembly: Dictionary) -> Dictionary:
	var physical: Dictionary = Parts.derive_physics(assembly)
	var angles: Array[float] = [0.0,PI/4,PI/2,PI*3.0/4.0,PI,PI*5.0/4.0,PI*3.0/2.0,PI*7.0/4.0,-float(physical.profile_angle)]
	for point: float in physical.contact_points: angles.append(-float(physical.profile_angle)-point)
	var best: Dictionary = {}
	for angle: float in angles:
		var sample: Dictionary = contact_probe(assembly,angle)
		if best.is_empty() or float(sample.opponent_damage) > float(best.opponent_damage):
			best = sample; best["spin_angle"] = angle
	return best

func _catalogue() -> void:
	check(Parts.BLADE_IDS.size() == 11 and Parts.RATCHET_IDS.size() == 9 and Parts.BIT_IDS.size() == 11,"31 distinct permanent components")
	var rarity_counts: Dictionary = {}
	var count: int = 0
	for category: String in Parts.PARTS:
		for id: String in Parts.PARTS[category]:
			var data: Dictionary = Parts.PARTS[category][id]
			check(data.id == id and data.category == category and data.rarity in Parts.RARITIES,"Stable metadata "+category+"/"+id)
			check(not str(data.description).is_empty() and not str(data.mechanical_identity).is_empty() and not str(data.tradeoff).is_empty(),"Readable identity and tradeoff "+id)
			check(ResourceLoader.exists(Parts.texture_path(category,id)),"Runtime sprite "+id)
			if category == "blade": check(ResourceLoader.exists(data.visual.spin),"Spin sprite "+id)
			rarity_counts[data.rarity] = int(rarity_counts.get(data.rarity,0))+1
			count += 1
	check(count == 31 and int(rarity_counts.LEGENDARY) == 1 and int(rarity_counts.TRASH) == 1,"Healthy rarity distribution with specialised extremes")
	observations["rarity_distribution"] = rarity_counts
	var legal: Array[Dictionary] = Parts.all_builds()
	check(legal.size() == 1089,"All 1089 cross-category assemblies are legal")
	var b: Node2D = battle(build())
	for assembly: Dictionary in legal:
		check(Parts.validate_build(assembly) == assembly,"Legal assembly "+Parts.title(assembly))
		var p: Dictionary = b._make_fighter(assembly,1,"player","player",Vector2.ZERO,Vector2.ZERO,RandomNumberGenerator.new())
		check(finite(p) and float(p.radius) >= 8 and float(p.radius) <= 17,"Finite constructed assembly "+Parts.title(assembly))
		for value: float in Parts.derive(assembly).values(): check(is_finite(value) and value >= 1 and value <= 10,"Bounded assembly ratings")
	b.free()

func _identities() -> void:
	var baseline: Dictionary = motion_probe(build())
	observations["baseline_motion"] = baseline
	var new_observations: Dictionary = {}
	for category: String in Parts.PARTS:
		for id: String in Parts.PARTS[category]:
			if bool(Parts.PARTS[category][id].legacy): continue
			var assembly: Dictionary = build(); assembly[category] = id
			var motion: Dictionary = motion_probe(assembly)
			var contact: Dictionary = contact_probe(assembly,0.0,0.0,5)
			var wall: Dictionary = wall_probe(assembly)
			new_observations[id] = {"motion":motion,"contact":contact,"wall":wall}
			check(motion.finite and contact.finite and motion.peak_speed <= Battle.RosterRuntime.SPEED_CLAMP+0.001 and motion.rpm_retention > 0.0 and motion.rpm_retention <= 1.0,"Finite meaningful new part "+id)
			var greatest_change: float = 0.0
			for key: String in ["drive_speed","coast_speed","brake_speed","control_response","recovery"]:
				greatest_change = maxf(greatest_change,absf(float(motion[key])-float(baseline[key]))/maxf(0.1,absf(float(baseline[key]))))
			var base_contact: Dictionary = contact_probe(build(),0.0,0.0,5)
			for key: String in ["opponent_damage","own_damage","recoil","delivery","lateral_delivery"]:
				greatest_change = maxf(greatest_change,absf(float(contact[key])-float(base_contact[key]))/maxf(0.1,absf(float(base_contact[key]))))
			check(greatest_change >= 0.10,"At least one observable effect >=10% for "+id)
	observations["individual_new_parts"] = new_observations
	check(contact_probe(build("hammerfall"),0.0).opponent_damage > contact_probe(build("hammerfall"),PI/2).opponent_damage*1.8,"Hammerfall aligned lobes hit harder than recessed shoulders")
	check(contact_probe(build("lopsider"),PI).opponent_damage > contact_probe(build("lopsider"),0.0).opponent_damage*2.0,"Lopsider heavy cast disc hits on its actual left-facing mass")
	check(contact_probe(build("fork"),-0.5404195002705842).opponent_damage > contact_probe(build("fork"),0.0).opponent_damage*1.6,"Fork tine windows hit harder than the face recess")
	check(contact_probe(build("crescent"),0.0,150).lateral_delivery > contact_probe(build("hook"),0.0,150).lateral_delivery*2.5,"Crescent creates strong lateral contact transfer")
	var grind: Dictionary = contact_probe(build("sawtooth"),0.0,0.0,5)
	check(float(grind.sequence[4]) > float(grind.sequence[0])*1.14,"Sawtooth repeated contact builds pressure")
	check(grind.own_damage > contact_probe(build(),0.0,0.0,5).own_damage*1.3,"Grinding contact spends the owner's RPM")
	check(new_observations.ballast.contact.recoil < contact_probe(build()).recoil*0.9,"Ballast weight resists actual collision displacement")
	check(new_observations.flex.contact.own_damage < contact_probe(build(),0.0,0.0,5).own_damage*0.75,"Flex absorbs real collision spin loss")
	check(new_observations.kickback.contact.recoil > contact_probe(build()).recoil*1.25,"Kickback accepts greater physical recoil")
	check(new_observations.flywheel.motion.drive_speed < baseline.drive_speed*0.85 and new_observations.flywheel.contact.own_damage < contact_probe(build(),0.0,0.0,5).own_damage*0.75,"Flywheel conserves collision spin at a real response cost")
	check(new_observations.scrap.wall.sideways > 50.0,"Scrap warped collar adds odd wall escape angle")
	check(new_observations.skate.motion.coast_speed/new_observations.skate.motion.drive_speed > baseline.coast_speed/baseline.drive_speed*1.25,"Skate retains momentum through release")
	check(new_observations.tripod.motion.brake_speed < baseline.brake_speed*0.72,"Tripod has conspicuous braking authority")
	check(new_observations.freewheel.motion.rpm_retention > baseline.rpm_retention and new_observations.freewheel.motion.control_response < baseline.control_response*0.85,"Freewheel efficiency costs directional response")
	var p: Dictionary = battle(build("balance","mid","claw")).player_entity()
	p.vel = Vector2(90,0)
	var slow: float = Physics.grip(p,0.0)
	p.vel = Vector2(200,0)
	check(slow > Physics.grip(p,0.0)*3.0,"Claw grip collapses above its authored threshold")
	# The host is released after both coefficient probes, no world or save writes.
	for node: Node in root.get_children():
		if node.get_script() == Battle: node.free()
	var eccentric: Dictionary = Parts.derive_physics(build("balance","mid","eccentric"))
	var e: Dictionary = {"part_physics":eccentric,"vel":Vector2.ZERO}
	check(Physics.grip(e,0.15625) > Physics.grip(e,0.46875)*4.0,"Eccentric has distinct repeating bite and release windows")

func _tunnelling_and_starters() -> void:
	var b: Node2D = battle(build("puck","scrap","skate"))
	var p: Dictionary = b.player_entity(); var e: Dictionary = b.entity(2)
	p.pos = Vector2(-12,0); e.pos = Vector2(12,0)
	p.vel = Vector2(500,0); e.vel = Vector2(-500,0)
	b.test_step(Battle.FIXED_DT,Vector2.ZERO)
	check(b.hits > 0 and Vector2(p.pos).x < Vector2(e.pos).x,"Fast compact new top cannot tunnel through its opponent")
	check(finite(p) and finite(e),"High opposing speeds stay finite")
	b.free()
	for starter: String in ["breaker","bastion","vane"]:
		var initial: Dictionary = Starters.get_starter(starter).assembly
		for category: String in Parts.PARTS:
			for id: String in Parts.PARTS[category]:
				if bool(Parts.PARTS[category][id].legacy): continue
				var assembly: Dictionary = initial.duplicate(); assembly[category] = id
				var instance: Node2D = battle(assembly)
				for tick: int in range(30): instance.test_step(Battle.FIXED_DT,Vector2(0.15,0.1))
				check(finite(instance.player_entity()),"Starter compatible with "+starter+" / "+id)
				instance.free()
	# A planted, efficient assembly remains finite and spends spin even without
	# input. Permanent component coefficients cannot create renewable reserve.
	var anchor: Node2D = battle(build("puck","flywheel","tripod"))
	var planted: Dictionary = anchor.player_entity()
	planted.pos = Vector2.ZERO; planted.vel = Vector2.ZERO
	for tick: int in range(7200): anchor._update_fighter(planted,Vector2.ZERO,true,Battle.FIXED_DT)
	check(float(planted.rpm) <= 0.045 and finite(planted),"Stationary high-inertia centre build still exhausts finite RPM")
	anchor.free()

func _swarm_components() -> void:
	var b: Node2D = battle(build("crescent"))
	var p: Dictionary = b.player_entity()
	var small: Dictionary = b.swarm.add_small(40,Vector2(15,0))
	p.pos = Vector2.ZERO; p.vel = Vector2(220,0); p.spin_angle = 0.0
	b.resolve_pair(1,40)
	check(b.hits == 0 and Vector2(small.pos).x == 15.0,"Crescent open mouth does not collide like its closed outer rim against small tops")
	p.spin_angle = PI
	b.resolve_pair(1,40)
	check(b.hits == 1 and Vector2(small.vel).length() > 0.0,"Crescent closed rim really reaches a small opponent")
	b.free()
	b = battle(build("sawtooth")); p = b.player_entity()
	small = b.swarm.add_small(40,Vector2(14,0))
	p.pos = Vector2.ZERO; p.vel = Vector2(220,0)
	b.resolve_pair(1,40)
	check(is_equal_approx(float(b._pair_cooldowns["1:40"]),0.12),"Sawtooth contact cadence applies to actual small-body contacts")
	b.free()
	# Numeric reference for the exact legacy neutral full-v-small solver.
	b = battle(build()); p = b.player_entity(); small = b.swarm.add_small(40,Vector2(14,0))
	p.pos = Vector2.ZERO; p.vel = Vector2(220,0); small.vel = Vector2.ZERO
	var inv_a: float = b.powers.inverse_mass(p); var inv_b: float = b.powers.inverse_mass(small)
	var impulse: float = (1.65*220.0+7.0)/(inv_a+inv_b)
	var expected_p: Vector2 = (Vector2(220,0)-Vector2.RIGHT*impulse*inv_a).limit_length(400.0)
	var expected_s: Vector2 = (Vector2.RIGHT*impulse*inv_b).limit_length(400.0)
	b.resolve_pair(1,40)
	check(Vector2(p.vel) == expected_p and Vector2(small.vel) == expected_s and float(b._pair_cooldowns["1:40"]) == 0.24,"Legacy small-body impulse and cooldown retain exact neutral arithmetic")
	b.free()

func _continuous_new_parts() -> void:
	var reports: Array[Dictionary] = []
	var saw_small: bool = false
	var made_small_contact: bool = false
	for seed: int in [205252,90512]:
		var b: Node2D = battle(build("puck","flex","tripod"))
		b.begin_run(build("puck","flex","tripod"),Encounters.for_run_event(1,seed),seed)
		b.battle_status = "battle"
		b.player_entity().vel = b.player_entity().launch_velocity
		b.entity(2).vel = b.entity(2).launch_velocity
		var counts: Dictionary = {"small_contacts":0,"peak_small":0,"finite":true}
		b.contact_accepted.connect(func(first: int, second: int) -> void:
			if str(b.entity(first).get("combatant_type","")) == "small_top" or str(b.entity(second).get("combatant_type","")) == "small_top": counts.small_contacts += 1)
		for tick: int in range(5400):
			var p: Dictionary = b.player_entity()
			var pos: Vector2 = p.pos
			var desired: Vector2 = -pos.normalized()*clampf(pos.length()/70.0,0.10,0.65)
			var screen: Vector2 = Vector2(desired.x-desired.y,(desired.x+desired.y)*0.5).normalized()*desired.length()
			b.test_step(Battle.FIXED_DT,screen,false,pos.length() > 80.0 and pos.dot(Vector2(p.vel)) > 0.0)
			counts.peak_small = maxi(int(counts.peak_small),b.swarm.active_count())
			for fighter: Dictionary in b.fighters: counts.finite = counts.finite and finite(fighter)
			if b.battle_status == "finished": break
		saw_small = saw_small or int(counts.peak_small) > 0
		made_small_contact = made_small_contact or int(counts.small_contacts) > 0
		check(counts.finite and float(b.player_entity().rpm) >= 0.0 and float(b.player_entity().rpm) <= 1.0,"New permanent components stay finite through actual continuous threat admission "+str(seed))
		reports.append({"seed":seed,"seconds":b.elapsed,"peak_small":counts.peak_small,"small_contacts":counts.small_contacts,"rpm":b.player_entity().rpm,"economy":b.continuous.economy.snapshot(),"director":b.continuous.director.history.duplicate(true)})
		b.free()
	check(saw_small and made_small_contact,"New assembled top meets naturally admitted swarms in continuous Run")
	observations["continuous_run_with_new_parts"] = reports

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): report_path = argument.trim_prefix("--out=")
	_catalogue(); _identities(); _tunnelling_and_starters(); _swarm_components(); _continuous_new_parts()
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"real_save_accessed":false}
	var file = FileAccess.open(report_path,FileAccess.WRITE)
	if file == null: print("Could not write report: ",report_path); quit(1); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("Parts catalogue: %d checks, %d failures; %s" % [checks,failures.size(),report_path])
	quit(0 if failures.is_empty() else 1)
