extends "res://tests/test_parts_catalogue.gd"
## Deterministic stratified study, actual 60 Hz solver and legal controls only.
## This diagnostic is not a human-feel acceptance or a balance ranking.
var study_path: String = "user://002c5_2_parts_matrix.json"
var study_builds: Array[Dictionary] = []
var assembly_keys: Dictionary = {}
var rows: Array[Dictionary] = []
var matches: Array[Dictionary] = []
var warnings: Array[String] = []
var component_probes: Dictionary = {}

func include(assembly: Dictionary, reason: String) -> void:
	var key: String = Parts.title(assembly)
	if assembly_keys.has(key): return
	assembly_keys[key] = true
	study_builds.append({"build":assembly,"stratum":reason})

func _select() -> void:
	include(build(),"neutral baseline")
	for category: String in Parts.PARTS:
		for id: String in Parts.PARTS[category]:
			if bool(Parts.PARTS[category][id].legacy): continue
			var assembly: Dictionary = build(); assembly[category] = id
			include(assembly,"isolated new "+category)
	for entry: Array in [["hammerfall","kickback","claw"],["puck","ballast","tripod"],["outrigger","kickback","skate"],["lopsider","offset","claw"],["crescent","flywheel","groove"],["fork","flex","chisel"],["sawtooth","ballast","rubber"],["lopsider","scrap","eccentric"],["guard","flywheel","freewheel"],["smash","offset","groove"]]:
		include(build(entry[0],entry[1],entry[2]),"extreme or specialised hybrid")
	for starter: String in ["breaker","bastion","vane"]:
		var base: Dictionary = Starters.build_for(starter)
		include(base,"existing starter "+starter)
		for pair: Array in [["blade","hammerfall"],["blade","crescent"],["ratchet","flex"],["ratchet","offset"],["bit","skate"],["bit","tripod"]]:
			var assembly: Dictionary = base.duplicate(); assembly[pair[0]] = pair[1]
			include(assembly,"starter with new "+pair[0])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2052052
	while study_builds.size() < 72:
		include(build(Parts.BLADE_IDS[rng.randi_range(0,10)],Parts.RATCHET_IDS[rng.randi_range(0,8)],Parts.BIT_IDS[rng.randi_range(0,10)]),"fixed-seed random stratification")

func _world_to_screen(direction: Vector2) -> Vector2:
	return Vector2(direction.x-direction.y,(direction.x+direction.y)*0.5).normalized()*direction.length()

func _policy(b: Node2D, policy: String, clock: float) -> Dictionary:
	var p: Dictionary = b.player_entity(); var e: Dictionary = b.entity(2)
	var pos: Vector2 = p.pos
	var desired: Vector2 = Vector2.ZERO
	var brake: bool = false
	var distance: float = pos.distance_to(e.pos)
	match policy:
		"pursuit": desired = (Vector2(e.pos)+Vector2(e.vel)*0.10-pos).normalized()*0.83
		"centre":
			desired = -pos.normalized()*clampf(pos.length()/100.0,0.18,0.48)
			brake = pos.length() > 80.0 and pos.dot(Vector2(p.vel)) > 0.0
		"orbit":
			var radial: Vector2 = pos.normalized() if pos.length() > 5.0 else Vector2.RIGHT
			desired = (radial.orthogonal()*0.80-radial*clampf((pos.length()-85.0)/70.0,-0.40,0.80)).limit_length(0.93)
	if pos.length() > 145.0 or absf(pos.x-pos.y) > 215.0:
		desired = desired.lerp(-pos.normalized()*0.9,0.77)
		brake = pos.dot(Vector2(p.vel)) > 0.0
	return {"direction":_world_to_screen(desired),"burst":policy == "pursuit" and distance > 35.0 and distance < 90.0 and pos.length() < 125.0 and int(clock*60.0)%30 == 0,"brake":brake}

func _bout(assembly: Dictionary, seed: int, policy: String) -> Dictionary:
	var b: Node2D = battle(assembly)
	b.begin(assembly,build("smash","low","flat"),2,seed); b.battle_status = "battle"
	b.player_entity().vel = b.player_entity().launch_velocity
	b.entity(2).vel = b.entity(2).launch_velocity
	var p: Dictionary = b.player_entity()
	var result: Dictionary = {"build":assembly,"seed":seed,"policy":policy,"mean_speed":0.0,"peak_speed":0.0,"mean_wobble":0.0,"centre_occupancy":0.0,"wall_exposure":0.0,"max_wall_lock_seconds":0.0,"survival_seconds":0.0,"rpm_retention":0.0,"hits":0,"won":false,"reason":"study_horizon","finite":true,"step_mean_us":0.0,"step_peak_us":0}
	var samples: int = 0
	var wall_lock: float = 0.0
	var max_lock: float = 0.0
	var total_us: int = 0
	for tick: int in range(1080):
		var input: Dictionary = _policy(b,policy,float(tick)/60.0)
		var before: int = Time.get_ticks_usec()
		b.test_step(Battle.FIXED_DT,input.direction,bool(input.burst),bool(input.brake))
		var cost: int = Time.get_ticks_usec()-before
		total_us += cost; result.step_peak_us = maxi(int(result.step_peak_us),cost)
		samples += 1
		var speed: float = Vector2(p.vel).length()
		result.mean_speed += speed; result.peak_speed = maxf(result.peak_speed,speed)
		result.mean_wobble += float(p.wobble)
		if Vector2(p.pos).length() < 55.0: result.centre_occupancy += 1.0
		var near_wall: bool = Vector2(p.pos).length() > 145.0 or absf(Vector2(p.pos).x-Vector2(p.pos).y) > 215.0
		if near_wall: result.wall_exposure += 1.0
		wall_lock = wall_lock+Battle.FIXED_DT if near_wall and speed < 8.0 else 0.0
		max_lock = maxf(max_lock,wall_lock)
		result.finite = result.finite and finite(p) and finite(b.entity(2)) and float(p.rpm) >= 0.0 and float(p.rpm) <= 1.000001
		if b.battle_status == "finished": break
	result.mean_speed /= float(samples); result.mean_wobble /= float(samples)
	result.centre_occupancy /= float(samples); result.wall_exposure /= float(samples)
	result.max_wall_lock_seconds = max_lock; result.survival_seconds = b.elapsed; result.rpm_retention = p.rpm
	result.hits = b.hits; result.step_mean_us = float(total_us)/float(samples)
	result["enemy_rpm"] = float(b.entity(2).rpm)
	result["rpm_margin"] = float(p.rpm)-float(b.entity(2).rpm)
	if not b.last_result.is_empty(): result.won = b.last_result.won; result.reason = b.last_result.reason
	check(result.finite,"Finite study bout "+Parts.title(assembly)+" / "+str(seed))
	check(result.peak_speed <= Battle.RosterRuntime.SPEED_CLAMP+0.001,"Finite speed ceiling in study bout")
	check(max_lock < 3.0,"No permanent wall lock under recovery policy")
	check(not (result.reason == "ring_out" and result.survival_seconds < 0.5),"No immediate unavoidable self ring-out")
	b.free()
	return result

func _summarise() -> Dictionary:
	var per_part: Dictionary = {}
	for match_row: Dictionary in matches:
		for category: String in ["blade","ratchet","bit"]:
			var id: String = match_row.build[category]
			var key: String = category+"/"+id
			if not per_part.has(key): per_part[key] = {"appearances":0,"wins":0,"completed_bouts":0,"mean_speed":0.0,"mean_rpm":0.0,"mean_rpm_margin":0.0,"centre_occupancy":0.0,"wall_exposure":0.0}
			var entry: Dictionary = per_part[key]
			entry.appearances += 1; entry.wins += 1 if match_row.won else 0
			entry.completed_bouts += 1 if str(match_row.reason) != "study_horizon" else 0
			entry.mean_speed += float(match_row.mean_speed); entry.mean_rpm += float(match_row.rpm_retention)
			entry.mean_rpm_margin += float(match_row.rpm_margin)
			entry.centre_occupancy += float(match_row.centre_occupancy); entry.wall_exposure += float(match_row.wall_exposure)
	for key: String in per_part:
		var entry: Dictionary = per_part[key]
		for field: String in ["mean_speed","mean_rpm","mean_rpm_margin","centre_occupancy","wall_exposure"]: entry[field] /= float(entry.appearances)
		entry["completed_win_fraction"] = float(entry.wins)/float(entry.completed_bouts) if int(entry.completed_bouts) > 0 else null
		if int(entry.completed_bouts) >= 8 and float(entry.completed_win_fraction) >= 0.90: warnings.append("High completed-bout win fraction: "+key+"; inspect with human policies, not a universal ranking")
		if int(entry.completed_bouts) >= 8 and float(entry.completed_win_fraction) <= 0.10: warnings.append("Low completed-bout win fraction: "+key+"; inspect the policy match before judging specialised components")
	var sum_us: float = 0.0; var peak_us: int = 0
	for result: Dictionary in matches: sum_us += float(result.step_mean_us); peak_us = maxi(peak_us,int(result.step_peak_us))
	var dominance: Dictionary = _probe_dominance()
	return {"assemblies":rows.size(),"bouts":matches.size(),"per_part":per_part,"probe_dominance":dominance,"mean_step_us":sum_us/float(matches.size()),"worst_observed_step_us":peak_us,"warnings":warnings,"ranking_limit":"Stratified samples are confounded by assembly and policy; horizon survival is not a win. Probe Pareto results test recorded dimensions only. Human feel remains required."}

func _probe_dominance() -> Dictionary:
	var dominance: Dictionary = {}
	for category: String in Parts.PARTS:
		var data: Dictionary = component_probes[category]
		for id: String in data:
			var dominated_by: Array[String] = []
			for other: String in data:
				if id == other: continue
				var all_better: bool = true
				var meaningful: bool = false
				for key: String in data[id].objectives:
					var current: float = data[id].objectives[key]
					var rival: float = data[other].objectives[key]
					if rival < current-0.000001: all_better = false
					if rival > current+maxf(0.001,absf(current)*0.10): meaningful = true
				if all_better and meaningful: dominated_by.append(other)
			dominance[category+"/"+id] = dominated_by
	return dominance

func _component_probes() -> void:
	for category: String in Parts.PARTS:
		component_probes[category] = {}
		for id: String in Parts.PARTS[category]:
			var assembly: Dictionary = build(); assembly[category] = id
			var motion: Dictionary = motion_probe(assembly)
			var direct: Dictionary = contact_probe(assembly)
			var peak: Dictionary = peak_contact_probe(assembly)
			var recessed: Dictionary = contact_probe(assembly,PI/2)
			var glance: Dictionary = contact_probe(assembly,0.0,160.0)
			var repeated: Dictionary = contact_probe(assembly,0.0,0.0,5)
			var wall: Dictionary = wall_probe(assembly)
			# Benefit dimensions are deliberately separate. A large contact radius
			# is reach and exposure simultaneously; no score hides that tradeoff.
			var physical: Dictionary = Parts.derive_physics(assembly)
			component_probes[category][id] = {"motion":motion,"direct":direct,"peak":peak,"recessed":recessed,"glance":glance,"repeated":repeated,"wall":wall,"objectives":{"response":motion.control_response,"pace":motion.drive_speed,"coast_retention":motion.coast_speed/maxf(1.0,float(motion.drive_speed)),"brake_authority":-float(motion.brake_speed),"spin_efficiency":motion.rpm_retention,"stability":-float(motion.wobble),"peak_contact_damage":peak.opponent_damage,"sustained_damage":repeated.opponent_damage,"collision_efficiency":-float(repeated.own_damage),"recoil_resistance":-float(glance.recoil),"lateral_transfer":glance.lateral_delivery,"reach":physical.radius,"compactness":-float(physical.radius),"wall_spin_cost":-float(wall.rpm_loss)}}

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): study_path = argument.trim_prefix("--out=")
	_select()
	_component_probes()
	var index: int = 0
	for selected: Dictionary in study_builds:
		var assembly: Dictionary = selected.build
		rows.append({"build":assembly,"name":Parts.title(assembly),"stratum":selected.stratum,"ratings":Parts.derive(assembly),"physics":Parts.derive_physics(assembly),"motion":motion_probe(assembly),"contact_aligned":contact_probe(assembly),"contact_peak":peak_contact_probe(assembly),"contact_recessed":contact_probe(assembly,PI/2),"contact_glancing":contact_probe(assembly,0.0,160.0),"contact_repeated":contact_probe(assembly,0.0,0.0,5),"wall":wall_probe(assembly)})
		matches.append(_bout(assembly,205200+index,"pursuit"))
		matches.append(_bout(assembly,205600+index,"centre" if index%2 == 0 else "orbit"))
		index += 1
		if index%12 == 0: print("Assembly study: ",index," / ",study_builds.size())
	var report: Dictionary = {"task":"002C.5.2","seed":2052052,"catalogue":Parts.PARTS,"catalogue_counts":{"blade":11,"ratchet":9,"bit":11},"legal_assemblies":1089,"checks":checks,"failures":failures,"summary":_summarise(),"component_probes":component_probes,"assemblies":rows,"bouts":matches,"real_save_accessed":false,"horizon_seconds":18.0,"physics_dt":Battle.FIXED_DT}
	var file = FileAccess.open(study_path,FileAccess.WRITE)
	if file == null: print("Could not write study report: ",study_path); quit(1); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("Assembly study complete: %d assemblies, %d bouts, %d checks, %d failures; %s" % [rows.size(),matches.size(),checks,failures.size(),study_path])
	quit(0 if failures.is_empty() else 1)
