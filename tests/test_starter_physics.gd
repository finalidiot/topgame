extends SceneTree
## Measure authored identities through the same motion and contact hooks used
## by live combat. Powers are absent to isolate physical identity differences.
const Battle = preload("res://scripts/battle.gd")
const Parts = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")
const Encounters = preload("res://scripts/encounters.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _battle(identity: String, variant: String) -> Node2D:
	var b = Battle.new()
	var build: Dictionary = Starters.build_for(identity)
	if variant == "duel":
		b.begin(build, Parts.DEFAULT_BUILD, 1, 421)
	elif variant == "duel_with_identity":
		b.begin_encounter(build, {"opponent_build":Parts.DEFAULT_BUILD, "seed":421, "starter_id":identity})
	else:
		var encounter: Dictionary = Encounters.for_slot(1, 421)
		encounter["starter_id"] = identity if variant == "authored" else "custom"
		b.begin_encounter(build, encounter)
	b.battle_status = "battle"
	b.set_physics_process(false)
	return b

func _motion(identity: String, variant: String) -> Dictionary:
	var b: Node2D = _battle(identity, variant)
	var p: Dictionary = b.player_entity()
	p.pos = Vector2.ZERO
	p.vel = Vector2.ZERO
	for _tick: int in range(60): b._update_fighter(p, Vector2.RIGHT, false, Battle.FIXED_DT)
	var speed: float = Vector2(p.vel).length()
	var spin_spent: float = 1.0 - float(p.rpm)
	p.pos = Vector2.ZERO
	p.vel = Vector2.ZERO
	p.rpm = 0.8
	p.wobble = 0.7
	for _tick: int in range(30): b._update_fighter(p, Vector2.ZERO, false, Battle.FIXED_DT)
	var recovered: float = 0.7 - float(p.wobble)
	p.pos = Vector2(145.0, 0.0)
	p.vel = Vector2.ZERO
	p.rpm = 1.0
	p.wobble = 0.0
	for _tick: int in range(15): b._update_fighter(p, Vector2.ZERO, false, Battle.FIXED_DT)
	var orbit_velocity: float = Vector2(p.vel).y
	var bank_velocity: float = -Vector2(p.vel).x
	var result: Dictionary = {"speed_1s":speed, "spin_spent_1s":spin_spent,
		"wobble_recovered_500ms":recovered, "orbit_velocity_250ms":orbit_velocity,
		"bank_velocity_250ms":bank_velocity, "mass":float(p.mass)}
	b.free()
	return result

func _collision(identity: String, variant: String) -> Dictionary:
	var b: Node2D = _battle(identity, variant)
	var p: Dictionary = b.player_entity()
	var enemy: Dictionary = b.entity(2)
	p.pos = Vector2.ZERO
	enemy.pos = Vector2(24.0, 0.0)
	p.vel = Vector2(130.0, 0.0)
	enemy.vel = Vector2(-130.0, 0.0)
	b._resolve_pair_records(p, enemy)
	var result: Dictionary = {"player_recoil":(Vector2(p.vel) - Vector2(130.0, 0.0)).length(),
		"enemy_recoil":(Vector2(enemy.vel) - Vector2(-130.0, 0.0)).length(),
		"enemy_spin_loss":1.0 - float(enemy.rpm), "player_spin_loss":1.0 - float(p.rpm),
		"player_wobble":float(p.wobble), "enemy_wobble":float(enemy.wobble)}
	b.free()
	return result

func _run() -> void:
	var motion: Dictionary = {}
	var collisions: Dictionary = {}
	var report: Dictionary = {"scope":"Deterministic physical motion/contact measurements without Run Powers. Authored Run handling compared with the same neutral custom Run and Quick Duel assemblies.", "starters":{}}
	for identity: String in Starters.IDS:
		var authored: Node2D = _battle(identity, "authored")
		check(authored.player_entity().starter_id == identity and authored.player_entity().build == Starters.build_for(identity), "Authored identity uses its exact selected physical assembly")
		check(authored.player_entity().handling == Starters.HANDLING[identity], "Authored Run carries only its own handling profile")
		check(authored.entity(2).get("handling", {}).is_empty(), "Starter profile does not modify the rival")
		check(authored.player_entity().powers.is_empty(), "Physical measurements cannot be confused with power effects")
		authored.free()
		var duel: Node2D = _battle(identity, "duel")
		check(duel.player_entity().get("handling", {}).is_empty(), "Quick Duel uses unmodified catalogue physics for the same assembly")
		duel.free()
		var run_motion: Dictionary = _motion(identity, "authored")
		var duel_motion: Dictionary = _motion(identity, "duel")
		var neutral_motion: Dictionary = _motion(identity, "custom")
		var inherited_motion: Dictionary = _motion(identity, "duel_with_identity")
		var run_collision: Dictionary = _collision(identity, "authored")
		var duel_collision: Dictionary = _collision(identity, "duel")
		var neutral_collision: Dictionary = _collision(identity, "custom")
		var inherited_collision: Dictionary = _collision(identity, "duel_with_identity")
		check(duel_motion == neutral_motion and duel_collision == neutral_collision, "Custom Run and Quick Duel preserve identical neutral motion/contact results for %s" % identity)
		check(duel_motion == inherited_motion and duel_collision == inherited_collision, "Stray starter identity on a non-Run descriptor cannot activate handling for %s" % identity)
		motion[identity] = run_motion
		collisions[identity] = run_collision
		match identity:
			"breaker":
				check(run_motion.speed_1s > duel_motion.speed_1s * 1.20, "Breaker profile measurably accelerates faster than its neutral assembly")
				check(run_collision.enemy_spin_loss > duel_collision.enemy_spin_loss * 1.20, "Breaker impacts inflict substantially greater physical rival spin damage")
				check(run_collision.enemy_recoil > duel_collision.enemy_recoil, "Breaker profile hits physically harder without requiring a power")
				check(run_motion.orbit_velocity_250ms > duel_motion.orbit_velocity_250ms, "Breaker naturally takes wider restless attack lines")
			"bastion":
				check(run_motion.speed_1s < duel_motion.speed_1s * 0.85, "Bastion is deliberately less explosive than its neutral assembly")
				check(run_collision.player_recoil < duel_collision.player_recoil * 0.90, "Bastion's added physical mass resists displacement in the same collision")
				check(run_motion.wobble_recovered_500ms > duel_motion.wobble_recovered_500ms * 1.20, "Bastion recovers physical stability faster after the same disturbance")
				check(run_motion.orbit_velocity_250ms < duel_motion.orbit_velocity_250ms * 0.5, "Bastion stays more centred than a neutral counterpart")
			"vane":
				check(run_motion.speed_1s > duel_motion.speed_1s * 1.10, "Vane profile repositions more quickly than its neutral assembly")
				check(run_motion.spin_spent_1s < duel_motion.spin_spent_1s, "Vane's technique profile improves physical spin efficiency")
				check(run_motion.orbit_velocity_250ms > duel_motion.orbit_velocity_250ms * 1.4, "Vane's profile creates a stronger curved approach")
				check(run_motion.wobble_recovered_500ms > duel_motion.wobble_recovered_500ms, "Vane remains responsive after a glancing disturbance")
		var ratios: Dictionary = {"speed":float(run_motion.speed_1s) / float(duel_motion.speed_1s),
			"spin_drain":float(run_motion.spin_spent_1s) / float(duel_motion.spin_spent_1s),
			"wobble_recovery":float(run_motion.wobble_recovered_500ms) / float(duel_motion.wobble_recovered_500ms),
			"player_recoil":float(run_collision.player_recoil) / float(duel_collision.player_recoil),
			"enemy_recoil":float(run_collision.enemy_recoil) / float(duel_collision.enemy_recoil),
			"enemy_spin_damage":float(run_collision.enemy_spin_loss) / float(duel_collision.enemy_spin_loss)}
		report.starters[identity] = {"assembly":Starters.build_for(identity), "handling":Starters.HANDLING[identity].duplicate(true),
			"run_motion":run_motion, "neutral_motion":duel_motion, "run_collision":run_collision,
			"neutral_collision":duel_collision, "ratios_run_to_neutral":ratios,
			"custom_matches_quick_duel":duel_motion == neutral_motion and duel_collision == neutral_collision,
			"stray_identity_matches_quick_duel":duel_motion == inherited_motion and duel_collision == inherited_collision}
		print("PROFILE_SUMMARY ", identity, " ", JSON.stringify(ratios))
	check(motion.breaker.speed_1s > motion.bastion.speed_1s * 1.5 and motion.vane.speed_1s > motion.bastion.speed_1s * 1.5, "Authored mobility identities are substantially faster than Bastion")
	check(collisions.breaker.enemy_spin_loss > collisions.vane.enemy_spin_loss and collisions.vane.enemy_spin_loss > collisions.bastion.enemy_spin_loss, "The three authored identities have ordered aggression in identical physical hits")
	check(motion.bastion.wobble_recovered_500ms > motion.vane.wobble_recovered_500ms and motion.vane.wobble_recovered_500ms > motion.breaker.wobble_recovered_500ms, "The three authored identities remain distinct through actual recovery behavior")
	check(motion.breaker.spin_spent_1s > motion.vane.spin_spent_1s and motion.vane.spin_spent_1s > motion.bastion.spin_spent_1s, "Risk, mobility efficiency and defence retain distinct spin costs")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var destination: String = argument.trim_prefix("--report=")
			var output: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
			check(output != null, "Requested starter physics report can be saved")
			if output != null:
				output.store_string(JSON.stringify(report, "\t"))
				output.close()
				print("STARTER_PHYSICS_REPORT ", destination)
	print("STARTER_PHYSICS_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
