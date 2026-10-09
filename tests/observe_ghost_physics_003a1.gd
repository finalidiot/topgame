extends SceneTree
const Fixture=preload("res://tests/ghost_physics_fixture_003a1.gd")
const Encounters=preload("res://scripts/encounters.gd")
const Starters=preload("res://scripts/starters.gd")
var report_path: String=""
func _initialize() -> void:call_deferred("run")

func setup_fixture(kind: String,closer: int) -> Node2D:
	return Fixture.create(root,kind,closer)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	var cases: Array[Dictionary]=[]
	for kind: String in ["self","hijack"]:
		for closer: int in [1,2]:
			var b: Node2D=setup_fixture(kind,closer);var rows: Array[Dictionary]=[]
			for tick: int in range(600):
				b.fixture_step()
				if tick%6==0:rows.append({"tick":tick,"time":b.elapsed,"source":b.entity(b.source_id).duplicate(true),"closer":b.entity(closer).duplicate(true),"diagnostics":b.powers.ghost_route_diagnostics(),"counters":b.powers.counters.duplicate(true)})
			cases.append({"kind":kind,"closer":closer,"source_released":b.source_released,"attached":b.attached,"turn":b.source_turn,"fixed_tail":b.fixed_tail,"fixed_socket":b.fixed_socket,"counters":b.powers.counters.duplicate(true),"events":b.powers.events.duplicate(true),"rows":rows,"controls":b.control_rows,"result":b.last_result});b.free()
	if not report_path.is_empty():
		var f:=FileAccess.open(report_path,FileAccess.WRITE);f.store_string(JSON.stringify(cases,"\t"));f.close()
	for row: Dictionary in cases:print("GHOST_PHYSICS ",row.kind," closer=",row.closer," released=",row.source_released," attached=",row.attached," turn=",row.turn," counters=",row.counters)
	quit()
