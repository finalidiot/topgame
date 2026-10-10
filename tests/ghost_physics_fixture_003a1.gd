extends "res://scripts/battle.gd"
## QA steering fixture. Ordinary paid movement/contacts/powers are unchanged.
## The second actor receives sampled steering, not production pilot decisions.
var source_id: int=1
var closer_id: int=2
var fixture_kind: String="hijack"
var tick: int=0
var source_turn: float=0.0
var previous_angle: float=0.0
var attached: bool=false
var source_released: bool=false
var fixed_tail: Vector2=Vector2.ZERO
var fixed_socket: Vector2=Vector2.ZERO
var control_rows: Array[Dictionary]=[]
var route_observer: RefCounted=preload("res://scripts/ghost_circuit_routes.gd").new()

static func create(parent: Node, kind: String, closer: int) -> Node2D:
	var b: Node2D=load("res://tests/ghost_physics_fixture_003a1.gd").new();parent.add_child(b);b.set_process(false);b.set_physics_process(false)
	var descriptor: Dictionary=preload("res://scripts/encounters.gd").for_run_event(1,421)
	var starters=preload("res://scripts/starters.gd")
	descriptor.starter_id="vane";descriptor.opponent_build=starters.build_for("vane")
	descriptor.player_power_ids=[];descriptor.player_power_ranks={};descriptor.player_power_mutations={};descriptor.ability_rebalance=true
	b.begin_run(starters.build_for("vane"),descriptor,421)
	while b.battle_status!="battle":b.test_step(b.FIXED_DT)
	b.source_id=3-closer;b.closer_id=closer;b.fixture_kind=kind
	b.continuous.reward_fixture=true;b.continuous.director.next_decision=99999.;b.continuous.director.calm_until=99999.
	for id: int in [1,2]:
		var actor: Dictionary=b.entity(id)
		actor.powers.assign(["afterimage","high_gear"]);actor.power_ranks={"afterimage":3 if id==closer else 2,"high_gear":2};actor.power_mutations={"afterimage":"ghost_circuit"} if id==closer else {}
		actor.ability_rebalance=true;actor.pos=Vector2(85,0) if kind=="self" and id==closer else (Vector2.ZERO if kind=="self" else (Vector2(70,0) if id==b.source_id else Vector2(0,-125)))
		actor.vel=Vector2(0,133) if kind=="self" and id==closer else (Vector2.ZERO if kind=="self" or id==closer else Vector2(0,126))
		# Declared fixture buttons are neutral; steering remains ordinary movement.
		actor.ai_burst_delay=99999.;actor.trail=[]
	b.powers.setup(b);b.roster.setup(b)
	return b

func screen(world: Vector2) -> Vector2:
	return Vector2(world.x-world.y,(world.x+world.y)*.5).normalized()*minf(1.0,world.length())

func curve(actor: Dictionary, radius: float=70.0, pace: float=126.0) -> Vector2:
	var pos: Vector2=actor.pos;var vel: Vector2=actor.vel
	var radial: Vector2=pos.normalized() if pos.length()>1.0 else Vector2.RIGHT
	var tangent: Vector2=Vector2(-radial.y,radial.x)
	var route: Vector2=tangent*pace+radial*(radius-pos.length())*2.0
	var thrust: Vector2=(route-vel)*4.0+route*.75-radial*(pace*pace/radius)
	var available: float=(123.0+float(actor.stats.grip)*17.0)*float(actor.handling.get("acceleration",1.0))
	return thrust.limit_length(available)/available

func toward(actor: Dictionary, point: Vector2, pace: float=134.0) -> Vector2:
	var offset: Vector2=point-Vector2(actor.pos)
	var wanted: Vector2=offset.normalized()*minf(pace,offset.length()*4.0)
	var available: float=(123.0+float(actor.stats.grip)*17.0)*float(actor.handling.get("acceleration",1.0))
	return ((wanted-Vector2(actor.vel))*5.0+wanted*.75).limit_length(available)/available

func control(id: int) -> Vector2:
	var actor: Dictionary=entity(id)
	if fixture_kind=="self":return curve(actor,85.0,133.0) if id==closer_id else toward(actor,Vector2.ZERO,40.0)
	if id==source_id:
		return toward(actor,Vector2.ZERO,100.0) if source_released else curve(actor)
	if not source_released:return toward(actor,Vector2(0,-125),30.0)
	if not attached:return toward(actor,fixed_tail+((fixed_socket-fixed_tail).normalized()*40.0),150.0)
	return toward(actor,fixed_socket+(fixed_socket-fixed_tail).normalized()*24.0,150.0)

func _update_ai(rival: Dictionary, _dt: float, _context: Dictionary={}) -> void:
	rival.ai_direction=control(int(rival.entity_id))

func _ai_should_brake(_rival: Dictionary) -> bool:return false

func fixture_step() -> void:
	var source: Dictionary=entity(source_id);var closer: Dictionary=entity(closer_id)
	var angle: float=Vector2(source.pos).angle()
	if tick>0:source_turn+=fposmod(angle-previous_angle+PI,TAU)-PI
	previous_angle=angle
	if fixture_kind=="hijack" and not source_released and source_turn>=5.55:
		for trace: Dictionary in powers.traces:
			if int(trace.owner_entity_id)==source_id:fixed_tail=trace.b
		route_observer.rebuild(powers.traces,powers.time)
		var hint: Dictionary=route_observer.observable_hint(closer,powers.time,150.0)
		if not hint.is_empty():fixed_tail=hint.tail;fixed_socket=hint.socket;source_released=true
	if source_released and not attached and Vector2(closer.pos).distance_to(fixed_tail)<=8.0:attached=true
	var world: Vector2=control(player_entity_id)
	control_rows.append({"tick":tick,"player":world,"npc":control(2),"source_turn":source_turn,"released":source_released,"attached":attached})
	test_step(FIXED_DT,screen(world),false,false)
	tick+=1
