extends "res://tests/test_parts_catalogue.gd"
## Read-only late-pressure AFK diagnostic. Zero steering, braking and Burst;
## live director, earned RPM rules, real outcomes, no fixture health or kills.
var output_path: String = "user://002c5_2_passive_anchors.json"
var rows: Array[Dictionary] = []

func _passive(assembly: Dictionary, seed: int) -> Dictionary:
	var b: Node2D = battle(assembly)
	var descriptor: Dictionary = Encounters.for_run_event(1,seed)
	descriptor["starter_id"] = Starters.identity_for_build(assembly)
	b.begin_run(assembly,descriptor,seed)
	b.battle_status = "battle"
	b.player_entity().vel = b.player_entity().launch_velocity
	b.entity(2).vel = b.entity(2).launch_velocity
	var p: Dictionary = b.player_entity()
	var samples: int = 0
	var speed_sum: float = 0.0
	var centre_ticks: int = 0
	var peak_full: int = 0
	var peak_small: int = 0
	var valid: bool = true
	while b.battle_status == "battle" and b.elapsed < 300.0 and samples < 24000:
		b.test_step(Battle.FIXED_DT,Vector2.ZERO,false,false)
		samples += 1; speed_sum += Vector2(p.vel).length()
		if Vector2(p.pos).length() < 55.0: centre_ticks += 1
		var full: int = 0
		for fighter: Dictionary in b.fighters:
			valid = valid and finite(fighter)
			if str(fighter.outcome).is_empty() and fighter.combatant_type == "full_top" and fighter.team_id == "hostile": full += 1
		peak_full = maxi(peak_full,full); peak_small = maxi(peak_small,b.swarm.active_count())
	var report: Dictionary = {"name":Parts.title(assembly),"build":assembly,"starter_identity":str(descriptor.starter_id),"seed":seed,"survival_seconds":b.elapsed,"outcome":b.last_result.get("reason","study_horizon"),"rpm":p.rpm,"wobble":p.wobble,"mean_speed":speed_sum/maxi(1,samples),"centre_occupancy":float(centre_ticks)/maxi(1,samples),"peak_hostile_full":peak_full,"peak_small":peak_small,"hits":b.hits,"rivals_defeated":b.continuous.rivals_defeated,"small_enemies_defeated":b.continuous.small_enemies_defeated,"elites_defeated":b.continuous.elites_defeated,"bosses_defeated":b.continuous.bosses_defeated,"director":b.continuous.director.history.duplicate(true),"economy":b.continuous.economy.snapshot(),"finite":valid,"zero_input":true}
	check(valid and float(p.rpm) >= 0.0 and float(p.rpm) <= 1.0,"Finite zero-input late-pressure build "+report.name)
	check(float(report.economy.gains.combat_reclamation) == 0.0,"Zero-input assembly cannot earn active full-contact RPM "+report.name)
	check(report.outcome == "spin_out" or report.outcome == "ring_out","Zero-input anchor still loses under late pressure "+report.name)
	print("Passive anchor: ",report.name," seed=",seed," seconds=",snappedf(b.elapsed,0.01)," outcome=",report.outcome," rpm=",snappedf(float(p.rpm),0.001))
	b.free()
	return report

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output_path = argument.trim_prefix("--out=")
	for assembly: Dictionary in [build("puck","ballast","tripod"),build("puck","flex","tripod"),Starters.build_for("bastion")]:
		for seed: int in [205252,90512]: rows.append(_passive(assembly,seed))
	var report: Dictionary = {"task":"002C.5.2","policy":"zero input: no steering, brake or Burst","horizon_seconds":300,"samples":rows,"checks":checks,"failures":failures,"real_save_accessed":false,"interpretation":"A build still alive at 300 seconds is a surviving sample, not proof of infinite or unbeatable survival."}
	var file = FileAccess.open(output_path,FileAccess.WRITE)
	if file == null: print("Could not write passive study ",output_path); quit(1); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("Passive anchors: ",checks," checks, ",failures.size()," failures; ",output_path)
	quit(0 if failures.is_empty() else 1)
