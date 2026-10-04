extends "res://scripts/power_runtime.gd"
## Read-only instrumentation around the exact production closure call.
var closure_rows: Array[Dictionary] = []
func _modern_circuit(owner: Dictionary, trace_emitted: bool) -> void:
	var previous: Dictionary = owner.get("ghost_preview",{}).duplicate()
	var previous_gap: float = Vector2(previous.a).distance_to(owner.pos) if not previous.is_empty() else -1.0
	var before_closures: int = int(counters.get("ghost_closure",0))
	super._modern_circuit(owner,trace_emitted)
	var next: Dictionary = owner.get("ghost_preview",{})
	var next_gap: float = Vector2(next.a).distance_to(owner.pos) if not next.is_empty() else -1.0
	if closure_rows.size() < 240 and ((trace_emitted and previous_gap > 0.0 and previous_gap <= 45.0) or int(counters.get("ghost_closure",0)) > before_closures):
		var owned: Array[Dictionary] = []
		for trace: Dictionary in traces:
			if int(trace.owner_entity_id) == int(owner.entity_id): owned.append(trace)
		closure_rows.append({"time":time,"emitted":trace_emitted,"speed":Vector2(owner.vel).length(),"previous_gap":previous_gap,"next_gap":next_gap,"count":owned.size(),"span":float(owned.back().created_at)-float(owned.front().created_at) if owned.size() > 1 else 0.0,"path_points":_state(owner).trace_path.size(),"closed":int(counters.get("ghost_closure",0)) > before_closures})
