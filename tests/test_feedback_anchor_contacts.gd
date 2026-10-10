extends SceneTree
## Compare real full/small contact solvers with exactly one shield hook disabled.
## Charge and inverse mass are identical in both; no save/profile is opened.
const Battle = preload("res://scripts/battle.gd")
const BUILD: Dictionary = {"blade":"balance", "ratchet":"mid", "bit":"ball"}

class NoShieldRuntime extends "res://scripts/power_runtime.gd":
	func incoming_rpm_scale(_fighter: Dictionary) -> float: return 1.0
	func incoming_wobble_scale(_fighter: Dictionary) -> float: return 1.0

var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var report_path: String = ""

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func _contact(small: bool, baseline: bool, rank_value: int, mutation: String, charged: bool = true, modern: bool = true, owned: bool = true) -> Dictionary:
	var battle: Node2D = Battle.new()
	root.add_child(battle); battle.set_physics_process(false)
	battle.begin(BUILD, BUILD, 1, 520535)
	battle.battle_status = "battle"; battle.ability_rebalance = modern
	if baseline:
		battle.powers = NoShieldRuntime.new()
		battle.powers.setup(battle)
	var player: Dictionary = battle.player_entity()
	player.powers = ["dead_centre"] if owned else []
	player.power_ranks = {"dead_centre":rank_value} if owned else {}
	player.power_mutations = {"dead_centre":mutation} if not mutation.is_empty() else {}
	player.anchor_charge = 1.0 if charged else 0.0; player.anchor_maturity = 1.0
	player.pos = Vector2(-8.0, 0.0); player.vel = Vector2(45.0, 0.0)
	player.rpm = 0.80; player.wobble = 0.20
	var other: Dictionary = battle.swarm.add_small(30, Vector2(8.0,0.0)) if small else battle.entity(2)
	other.pos = Vector2(8.0, 0.0); other.vel = Vector2(-45.0,0.0)
	other.rpm = 0.22 if small else 0.80; other.wobble = 0.20
	var before_rpm: float = float(player.rpm)
	var before_other: float = float(other.rpm)
	var before_wobble: float = float(player.wobble)
	var scale: float = battle.powers.incoming_rpm_scale(player)
	var wobble_scale: float = battle.powers.incoming_wobble_scale(player)
	battle.resolve_pair(1, int(other.entity_id))
	var result: Dictionary = {"small":small, "rank":rank_value, "mutation":mutation, "scale":scale, "wobble_scale":wobble_scale,
		"received_loss":before_rpm-float(player.rpm), "received_wobble":float(player.wobble)-before_wobble,
		"outgoing_loss":before_other-float(other.rpm), "player_velocity":player.vel, "other_velocity":other.vel,
		"after_charge":float(player.anchor_charge), "hits":battle.hits, "swarm_budget":battle.swarm.contact_budget}
	battle.free()
	return result

func _test_shields() -> void:
	for small: bool in [false, true]:
		for state: Dictionary in [{"rank":1,"mutation":""}, {"rank":2,"mutation":""}, {"rank":3,"mutation":"bulwark"}, {"rank":3,"mutation":"counterweight"}]:
			var reference: Dictionary = _contact(small, true, state.rank, state.mutation)
			var protected: Dictionary = _contact(small, false, state.rank, state.mutation)
			observations.append({"baseline":reference, "shield":protected})
			var label: String = ("small" if small else "full") + "/" + str(state)
			check(int(protected.hits) == 1 and int(reference.hits) == 1, "Both fixtures accept a genuine contact: "+label)
			check(float(reference.received_loss) > 0.0 and float(protected.received_loss) > 0.0, "Floor brace reduces real damage without immunity: "+label)
			check(is_equal_approx(float(protected.received_loss), float(reference.received_loss)*float(protected.scale)), "Pre-contact shield factor reaches RPM solver exactly: "+label)
			if float(reference.received_wobble) > 0.0:
				check(is_equal_approx(float(protected.received_wobble), float(reference.received_wobble)*float(protected.wobble_scale)), "Independent preserved stability factor reaches incoming wobble: "+label)
			check(protected.player_velocity == reference.player_velocity and protected.other_velocity == reference.other_velocity, "Shield factor does not secretly change contact impulse: "+label)
			check(is_equal_approx(float(protected.outgoing_loss), float(reference.outgoing_loss)), "Shield factor does not alter outgoing attack: "+label)
			check(float(protected.after_charge) < 1.0, "Accepted contact still chips or breaks anchoring: "+label)
			if small:
				check(protected.swarm_budget == reference.swarm_budget, "Shield does not inflate the swarm damage budget: "+label)
	for scenario: Dictionary in [{"charged":false,"modern":true,"owned":true}, {"charged":true,"modern":false,"owned":true}, {"charged":true,"modern":true,"owned":false}]:
		for small: bool in [false,true]:
			var reference: Dictionary = _contact(small, true, 1, "", scenario.charged, scenario.modern, scenario.owned)
			var neutral: Dictionary = _contact(small, false, 1, "", scenario.charged, scenario.modern, scenario.owned)
			check(float(neutral.scale) == 1.0 and neutral == reference, "Legacy/unowned/uncharged contacts remain exact: "+str(scenario)+"/"+str(small))

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
	_test_shields()
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		check(file != null, "Explicit external QA report is writable")
		if file != null: file.store_string(JSON.stringify({"checks":checks, "failures":failures, "contacts":observations}, "\t"))
	print("FEEDBACK_ANCHOR_CONTACT_TEST_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
