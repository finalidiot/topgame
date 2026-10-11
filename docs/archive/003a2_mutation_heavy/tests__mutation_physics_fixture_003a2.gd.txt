extends "res://scripts/battle.gd"
## Legal initial loadout/pose fixtures with sampled ordinary controls afterward.
const Draft003A2 = preload("res://tests/mutation_draft_policy_003a2.gd")
var fixture_controls: Dictionary={}
var fixture_owner: int=1

static func create(parent: Node, family: String, mutation_id: String, owner: int=1, seed_value: int=421) -> Node2D:
	var b: Node2D=load("res://tests/mutation_physics_fixture_003a2.gd").new()
	parent.add_child(b);b.set_process(false);b.set_physics_process(false);b.visible=false
	var d: Dictionary=preload("res://scripts/encounters.gd").for_run_event(1,seed_value)
	var starters=preload("res://scripts/starters.gd")
	d.starter_id="vane";d.opponent_build=starters.build_for("vane");d.ability_rebalance=true
	d.player_power_ids=[family] if owner==1 else [];d.player_power_ranks={family:3} if owner==1 else {};d.player_power_mutations={family:mutation_id} if owner==1 else {}
	b.begin_run(starters.build_for("vane"),d,seed_value)
	for ready: int in range(300):
		if b.battle_status=="battle":break
		b.test_step(b.FIXED_DT)
	b.fixture_owner=owner;b.ability_rebalance=true
	b.continuous.reward_fixture=true;b.continuous.director.next_decision=99999.;b.continuous.director.calm_until=99999.
	for id: int in [1,2]:
		var f: Dictionary=b.entity(id)
		f.powers=[family] if id==owner else [];f.power_ranks={family:3} if id==owner else {};f.power_mutations={family:mutation_id} if id==owner else {}
		f.ai_burst_delay=99999.;f.erase("role");f.erase("pilot")
		f.pos=Vector2.ZERO if id==owner else Vector2(100,45);f.vel=Vector2.ZERO
	b.powers.setup(b);b.roster.setup(b)
	# Drain READY before applying any mature-clock fixture. All clocks share an
	# epoch, including the new helper; later time comes only from fixed steps.
	b.elapsed=0.0;b.powers.time=0.0;b.roster.time=0.0;b.roster.ecology.time=0.0
	return b

func _update_ai(rival: Dictionary, _dt: float, _context: Dictionary={}) -> void:
	rival.ai_direction=Vector2(fixture_controls.get(int(rival.entity_id),{}).get("direction",Vector2.ZERO))
func _ai_should_brake(rival: Dictionary) -> bool:return bool(fixture_controls.get(int(rival.entity_id),{}).get("brake",false))
func fixture_step(world_direction: Vector2=Vector2.ZERO, burst: bool=false, brake: bool=false) -> void:
	fixture_controls[fixture_owner]={"direction":world_direction,"brake":brake}
	if fixture_owner!=player_entity_id and burst and battle_status=="battle" and not paused:
		_attempt_burst(entity(fixture_owner),world_direction.normalized())
	var world: Vector2=world_direction if fixture_owner==player_entity_id else Vector2.ZERO
	var screen: Vector2=Vector2(world.x-world.y,(world.x+world.y)*.5).normalized()*minf(1.0,world.length())
	test_step(FIXED_DT,screen,burst if fixture_owner==player_entity_id else false,brake if fixture_owner==player_entity_id else false)

func fixture_snapshot() -> Dictionary:
	var actors: Array[Dictionary]=[]
	for f: Dictionary in fighters:
		actors.append({"id":f.entity_id,"pos":f.pos,"vel":f.vel,"rpm":f.rpm,"wobble":f.wobble,"outcome":f.outcome,
			"powers":f.powers.duplicate(),"ranks":f.power_ranks.duplicate(true),"branches":f.power_mutations.duplicate(true)})
	return {"elapsed":elapsed,"power_time":powers.time,"roster_time":roster.time,"ecology_time":roster.ecology.time,
		"actors":actors,"counters":roster.ecology.counters.duplicate(true),"ecology":roster.ecology.states.duplicate(true),
		"roster":roster.states.duplicate(true),"power_events":powers.events.duplicate(true),"economy":continuous.economy.snapshot(),"status":battle_status}
