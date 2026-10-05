extends SceneTree
## Cosmetic blast waves must preserve the real seeded collision simulation.
const Battle = preload("res://scripts/battle.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const BUILD: Dictionary = {"blade":"hammerfall","ratchet":"kickback","bit":"claw"}
var checks: int = 0
var failures: int = 0

class WithoutBlast extends "res://scripts/battle.gd":
	func _spawn_blast_wave(_position: Vector2, _severity: float) -> void: pass

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var with_fx = Battle.new()
	var plain = WithoutBlast.new()
	root.add_child(with_fx)
	root.add_child(plain)
	with_fx.set_physics_process(false)
	plain.set_physics_process(false)
	with_fx.begin(BUILD,{"blade":"balance","ratchet":"mid","bit":"ball"},1,421)
	plain.begin(BUILD,{"blade":"balance","ratchet":"mid","bit":"ball"},1,421)
	var observed: int = 0
	for tick: int in range(3600):
		var controls: Dictionary = Bot.input(with_fx,"aggressive",tick)
		for battle: Node2D in [with_fx,plain]: battle.test_step(Battle.FIXED_DT,controls.direction,controls.burst,controls.brake)
		if not with_fx._blast_waves.is_empty(): observed += 1
		check(with_fx.hits == plain.hits and with_fx.battle_status == plain.battle_status,"Cosmetics do not change actual contacts or outcomes")
		for id: int in [with_fx.player_entity_id, 2]:
			var decorated: Dictionary = with_fx.entity(id)
			var undecorated: Dictionary = plain.entity(id)
			check(decorated.pos == undecorated.pos and decorated.vel == undecorated.vel and decorated.rpm == undecorated.rpm and decorated.wobble == undecorated.wobble,"Blast playback preserves exact seeded motion and reserve")
		check(with_fx._blast_waves.size() <= 12,"Impact instances stay bounded during real combat")
	check(observed > 0 and with_fx.hits > 0,"Real accepted collisions actually play blast waves")
	# Explicit presentation unit fixture: stress the instance budget and expiry.
	for index: int in range(80): with_fx._spawn_blast_wave(Vector2.ZERO,1.0)
	check(with_fx._blast_waves.size() == 12,"A contact storm cannot grow the blast queue")
	var before: Array = with_fx._blast_waves.duplicate(true)
	with_fx.set_paused(true)
	with_fx.test_step(0.1)
	check(with_fx._blast_waves == before,"Pause does not advance collision presentation")
	with_fx.set_paused(false)
	with_fx._update_effects(0.6)
	check(with_fx._blast_waves.is_empty(),"All contact waves expire without persistent floor clutter")
	with_fx.free()
	plain.free()
	print("FEEDBACK_EFFECTS_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
