extends "res://tests/test_ability_rebalance.gd"
## Semantic prescribed-motion host: real paid runtime emission/geometry/cause,
## not a solver or balance claim. Separate native fixture proves real physics.
var cases: Array[Dictionary]=[]

func crossing(closer_id: int, ghost: bool=true, expired: bool=false, competing: bool=false, dual_route: bool=false) -> Dictionary:
	var source_id: int=2 if closer_id==1 else 1
	var tail: Vector2=Vector2(cos(TAU*.82),sin(TAU*.82))*56.0
	var h: Host=Host.new()
	for id: int in [1,2]:
		h.fighters.append(fighter(id,"afterimage",3 if id==closer_id and ghost else 2,"ghost_circuit" if id==closer_id and ghost else "",tail if id==closer_id else Vector2(56,0)))
	var ally: Dictionary=fighter(5,"",1,"",Vector2.ZERO);ally.team_id=h.entity(closer_id).team_id;h.fighters.append(ally)
	if dual_route:
		var source: Dictionary=fighter(3,"afterimage",2,"",Vector2(56,0));source.team_id=h.entity(source_id).team_id;h.fighters.append(source)
	if competing:
		var other: Dictionary=fighter(4,"afterimage",3,"ghost_circuit",tail);other.team_id=h.entity(closer_id).team_id;h.fighters.append(other)
	h.runtime=Runtime.new();h.runtime.setup(h)
	for tick: int in range(97):
		h.runtime.begin_tick(1.0/60.0)
		var angle: float=TAU*.82*float(tick)/96.0
		for id: int in [source_id,3] if dual_route else [source_id]:
			var source: Dictionary=h.entity(id);source.pos=Vector2(cos(angle),sin(angle))*56.0;source.vel=Vector2(-sin(angle),cos(angle))*200.0
			h.runtime.movement_control(source,source.vel.normalized(),false,1.0/60.0)
		h.runtime.after_movement();h.runtime.flush_contact_powers()
	# Explicit semantic target placement checks inclusion/provenance separately
	# from the fixed native movie, where every position comes from the solver.
	for id: int in [source_id,3] if dual_route else [source_id]:h.entity(id).pos=Vector2.ZERO;h.entity(id).vel=Vector2.ZERO
	var visible_tail: Vector2=tail
	for trace: Dictionary in h.runtime.traces:
		if int(trace.owner_entity_id)==source_id:visible_tail=trace.b
	# First reach the actual last PAID visible endpoint. The original drawer's
	# final un-emitted buffer is intentionally unavailable to a hijacker.
	for tick: int in range(1,13):
		h.runtime.begin_tick(1.0/60.0)
		for id: int in [closer_id,4] if competing else [closer_id]:
			var actor: Dictionary=h.entity(id);actor.pos=tail.lerp(visible_tail,float(tick)/12.0);actor.vel=(visible_tail-tail).normalized()*160.0
			h.runtime.movement_control(actor,actor.vel.normalized(),false,1.0/60.0)
		h.runtime.after_movement();h.runtime.flush_contact_powers()
	tail=visible_tail
	var original: Array[Dictionary]=[]
	for trace: Dictionary in h.runtime.traces:original.append({"trace":trace,"owner":trace.owner_entity_id,"owner_id":trace.owner_id,"team":trace.team_id,"cause":trace.cause.duplicate(true),"points":trace.points.duplicate()})
	if expired:
		for tick: int in range(360):h.runtime.begin_tick(1.0/60.0);h.runtime.after_movement()
	var before_rpm: float=float(h.entity(closer_id).rpm)
	for tick: int in range(1,31):
		h.runtime.begin_tick(1.0/60.0)
		var point: Vector2=tail.lerp(Vector2(56,0),float(tick)/30.0)
		for id: int in [closer_id,4] if competing else [closer_id]:
			var actor: Dictionary=h.entity(id);actor.pos=point;actor.vel=(Vector2(56,0)-tail).normalized()*160.0
			h.runtime.movement_control(actor,actor.vel.normalized(),false,1.0/60.0)
		h.runtime.after_movement();h.runtime.flush_contact_powers()
	var ghost_impulses: Array[Dictionary]=[]
	for impulse: Dictionary in h.impulses:
		if impulse.cause.kind=="ghost_circuit":ghost_impulses.append(impulse)
	var provenance: bool=true;var consumed: int=0
	for row: Dictionary in original:
		var trace: Dictionary=row.trace
		provenance=provenance and int(trace.owner_entity_id)==int(row.owner) and trace.owner_id==row.owner_id and trace.team_id==row.team and trace.cause==row.cause and trace.points==row.points
		for used: Dictionary in trace.get("ghost_used_edges",[]):
			consumed+=1;check(float(used.lo)>=0.0 and float(used.hi)<=1.0 and float(used.lo)<float(used.hi),"Consumed interval belongs to an exact original paid edge")
	var owners: Array[int]=[]
	for event: Dictionary in h.runtime.events:
		if event.kind=="ghost_hijack":owners.append(int(event.owner))
	return {"h":h,"source":source_id,"closer":closer_id,"ghost_impulses":ghost_impulses,"provenance":provenance,"consumed_edges":consumed,"activation_owners":owners,"closer_paid_movement":before_rpm-float(h.entity(closer_id).rpm),"diagnostics":h.runtime.ghost_route_diagnostics()}

func _run() -> void:
	for owner_id: int in [1,2]:
		var self_host: Host=Host.new();self_host.fighters=[fighter(1,"afterimage",3 if owner_id==1 else 2,"ghost_circuit" if owner_id==1 else "",Vector2(52,0) if owner_id==1 else Vector2.ZERO),fighter(2,"afterimage",3 if owner_id==2 else 2,"ghost_circuit" if owner_id==2 else "",Vector2(52,0) if owner_id==2 else Vector2.ZERO)]
		self_host.runtime=Runtime.new();self_host.runtime.setup(self_host)
		for tick: int in range(91):
			self_host.runtime.begin_tick(1.0/60.0);var angle: float=TAU*float(tick)/90.0;var actor: Dictionary=self_host.entity(owner_id)
			actor.pos=Vector2(cos(angle),sin(angle))*52.0;actor.vel=Vector2(-sin(angle),cos(angle))*200.0
			self_host.runtime.after_movement();self_host.runtime.flush_contact_powers()
		check(int(self_host.runtime.counters.get("ghost_closure",0))==1,"Player/enemy closes its own actual paid live route")
	for closer_id: int in [1,2]:
		var row: Dictionary=crossing(closer_id)
		var h: Host=row.h
		check(int(h.runtime.counters.get("ghost_hijack",0))==1,"Player/enemy physically bridges a hostile paid live route")
		check(row.provenance and int(row.consumed_edges)>0,"Hijack consumes used sections while preserving original trace ownership/cause/points")
		check(not row.ghost_impulses.is_empty(),"Original hostile route owner inside its stolen circuit receives the real activation")
		for impulse: Dictionary in row.ghost_impulses:
			check(int(impulse.cause.owner_entity_id)==closer_id and impulse.cause.owner_id==h.entity(closer_id).owner_id and impulse.cause.team_id==h.entity(closer_id).team_id and not bool(impulse.cause.primary),"Circuit impulse cause belongs to the actual closer")
			check(int(impulse.target)!=closer_id and int(impulse.target)!=5,"Closer and same-team actor never receive their own circuit activation")
		check(float(h.entity(int(row.source)).wobble)>.10 and float(h.entity(int(row.source)).rpm)<1.0,"Hijacked original owner is physically destabilised and loses bounded RPM")
		check(float(h.entity(5).rpm)==1.0 and float(h.entity(5).wobble)==0.0,"Same-team enclosed actor is safe")
		check(float(h.runtime._state(h.entity(closer_id)).circuit_ready)>h.runtime.time,"Closure cooldown belongs to the closer")
		check(row.closer_paid_movement>0.0,"The closing movement emits real visible RPM-paid geometry")
		cases.append({"closer":closer_id,"source":row.source,"closures":h.runtime.counters.get("ghost_closure",0),"hijacks":h.runtime.counters.get("ghost_hijack",0),"provenance":row.provenance,"consumed_edges":row.consumed_edges,"diagnostics":row.diagnostics})
	for config: Dictionary in [{"ghost":false,"expired":false},{"ghost":true,"expired":true}]:
		var row: Dictionary=crossing(1,config.ghost,config.expired)
		check(int(row.h.runtime.counters.get("ghost_hijack",0))==0,"No ownership or expired geometry cannot hijack")
	var simultaneous: Dictionary=crossing(1,true,false,true)
	check(simultaneous.activation_owners==[1],"Two simultaneous eligible Ghost owners cannot farm the same consumed geometry")
	var multiple: Dictionary=crossing(1,true,false,false,true)
	var choice: int=-1
	for event: Dictionary in multiple.h.runtime.events:
		if event.kind=="ghost_hijack":choice=int(event.target)
	check(choice==2,"Equal live routes choose the stable original owner ID")
	check(int(multiple.diagnostics.live_traces)<=Runtime.MAX_ALL_TRACES,"Multiple live routes retain the hard trace cap")
	print("GHOST_CIRCUIT_HIJACK_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var path: String=argument.trim_prefix("--report=");if FileAccess.file_exists(path):quit(2);return
			var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"scope":"Prescribed-motion semantic host uses real paid emission and immutable provenance. Actual solver/native movie is separate."},"\t"));file.close()
	quit(0 if failures.is_empty() else 1)
