extends "res://tests/observe_ghost_physics_003a1.gd"
## Actual solver proof; no post-setup resource/pose/velocity/route writes.
var checks: int=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	var cases: Array[Dictionary]=[]
	for kind: String in ["self","hijack"]:
		for closer: int in [1,2]:
			var b: Node2D=setup_fixture(kind,closer);var immutable: Array[Dictionary]=[];var seen: Dictionary={};var paid: Dictionary={1:0.0,2:0.0}
			for tick: int in range(600):
				b.fixture_step()
				for trace: Dictionary in b.powers.traces:
					var key: int=int(trace.cause.event_id)
					if not seen.has(key):
						seen[key]=true;paid[int(trace.owner_entity_id)]+=float(trace.paid_rpm)
						immutable.append({"trace":trace,"owner":trace.owner_entity_id,"team":trace.team_id,"cause":trace.cause.duplicate(true),"points":trace.points.duplicate()})
			var counters: Dictionary=b.powers.counters
			check(int(counters.get("ghost_closure",0))>0,"Actual paid movement closes "+kind+" for owner"+str(closer))
			check(int(counters.get("ghost_activation",0))>0,"Actual enclosed hostile receives physical circuit effect")
			check(float(paid[closer])>0.0,"Closer paid ordinary Afterimage RPM rather than invisible geometry")
			check(str(b.entity(closer).outcome).is_empty(),"Live closer owns activation")
			var preserved: bool=true;var consumed: int=0
			for row: Dictionary in immutable:
				var trace: Dictionary=row.trace
				preserved=preserved and trace.owner_entity_id==row.owner and trace.team_id==row.team and trace.cause==row.cause and trace.points==row.points
				consumed+=trace.get("ghost_used_edges",[]).size()
			check(preserved,"Actual solver closure preserves all original trace provenance and authored path")
			check(consumed>0,"Actual closure consumes precise paid sections")
			if kind=="hijack":
				check(int(counters.get("ghost_hijack",0))==1,"One actual hostile hijack; used route cannot be farmed during repeated steering")
				check(b.source_released and b.attached,"Closer physically reaches actual paid tail through ordinary acceleration")
				check(float(paid[b.source_id])>0.0,"Hostile source created and paid its live geometry")
				var attribution: bool=false
				for event: Dictionary in b.powers.events:
					if event.kind=="ghost_hijack" and int(event.owner)==closer and int(event.target)==b.source_id:attribution=true
				check(attribution,"Hijack attribution belongs to closer, with original owner as route source")
			cases.append({"kind":kind,"closer":closer,"paid_rpm":paid,"consumed_edge_intervals":consumed,"trace_provenance_unchanged":preserved,"counters":counters.duplicate(true),"events":b.powers.events.duplicate(true),"diagnostics":b.powers.ghost_route_diagnostics(),"controls":b.control_rows,"economy":b.continuous.economy.snapshot()});b.free()
	if not report_path.is_empty():
		var f:=FileAccess.open(report_path,FileAccess.WRITE);check(f!=null,"External report can be opened")
		if f!=null:f.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"cases":cases,"authenticity":"Legal initial Vane/Afterimage+HighGear build and pose/velocity fixtures; subsequent sampled player/NPC steering only, neutral buttons, canonical Battle60Hz solver/costs/powers. Controlled geometry proof, not natural Run/pilot balance."},"\t"));f.close()
	print("GHOST_PHYSICS_TEST ",checks," checks, ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
