extends SceneTree
## An actual launched Run must create and collect a chip without outcome fixtures.
const Battle = preload("res://scripts/battle.gd")
const Run = preload("res://scripts/run_context.gd")
const Pickups = preload("res://scripts/run_pickups.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const BUILD: Dictionary = {"blade":"hammerfall","ratchet":"kickback","bit":"claw"}
var created: int = 0
var collected: int = 0
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var run = Run.new()
	run.start(BUILD,421)
	check(run.choose_power(run.pending_draft_id,run.pending_offer[0]),"A seeded offered power starts the Run")
	var battle = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.begin_run(BUILD,run.current_encounter(),run.run_seed)
	var pickups = Pickups.new()
	battle.add_child(pickups)
	pickups.set_process(false)
	pickups.setup(battle,run)
	battle.threat_cleared.connect(func(summary: Dictionary) -> void:
		if pickups.notify_clear(summary): created += 1)
	pickups.reroll_collected.connect(func(_id: String) -> void: collected += 1)
	var stepped: int = 0
	for tick: int in range(60*180):
		var controls: Dictionary = Bot.input(battle,"aggressive",tick)
		if not pickups.items.is_empty():
			var player: Dictionary = battle.player_entity()
			var difference: Vector2 = Vector2(pickups.items[0].pos) - Vector2(player.pos)
			var desired: Vector2 = difference.limit_length(60.0)*2.0-Vector2(player.vel)*0.60
			var world: Vector2 = desired.limit_length(100.0)/100.0
			controls = {"direction":Vector2(world.x-world.y,(world.x+world.y)*0.5),"burst":false,"brake":difference.length()<22.0 and Vector2(player.vel).length()>65.0}
		battle.test_step(Battle.FIXED_DT,controls.direction,controls.burst,controls.brake)
		pickups.update_simulation()
		stepped += 1
		if collected > 0 or battle.battle_status == "finished": break
	check(battle.hits > 0 and battle.continuous.threats_cleared > 0,"Real combat, rather than direct outcome assignment, clears a threat")
	check(created > 0,"Real threat notification creates a floor chip")
	check(collected == 1 and run.rerolls_collected == 1 and run.reroll_charges == 2,"Real steering through the spawned floor chip grants one charge")
	print("LIVE_PICKUP_DETAILS ticks=%d time=%.2f hits=%d threats=%d chips=%d collected=%d" % [stepped,battle.elapsed,battle.hits,battle.continuous.threats_cleared,created,collected])
	battle.free()
	print("FEEDBACK_LIVE_PICKUP_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
