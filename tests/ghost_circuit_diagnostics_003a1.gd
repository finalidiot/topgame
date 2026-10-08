extends RefCounted
## Offline QA observer of the same connected paid geometry. Never changes state.
static func analyse(runtime: RefCounted, owner: Dictionary, trace_emitted: bool) -> Dictionary:
	var tuning: Dictionary={"speed":112.0,"continuity":26.0,"emit_gap":6.0,"preview":70.0,"closure":38.0,"age":.85,"perimeter":180.0,"area":1300.0,"extent":32.0,"gap_ratio":.22,"cooldown":3.5}
	var constants: Dictionary={}
	var script: Script=runtime.get_script()
	while script!=null:
		constants.merge(script.get_script_constant_map(),false)
		script=script.get_base_script()
	for field: String in tuning:
		var key: String="GHOST_"+field.to_upper()
		if constants.has(key): tuning[field]=float(constants[key])
	var state: Dictionary=runtime._state(owner)
	var result: Dictionary={"time":runtime.time,"speed":Vector2(owner.vel).length(),"emitted":trace_emitted,"reason":"none","tuning":tuning}
	if runtime.time < float(state.circuit_ready): result.reason="cooldown"; return result
	if result.speed <= float(tuning.speed): result.reason="speed"; return result
	var route: Array[Vector2]=[]; var stamps: Array[float]=[]; var broken: int=0
	for trace: Dictionary in runtime.traces:
		if int(trace.owner_entity_id)!=int(owner.entity_id) or float(trace.created_at)<=float(state.circuit_after): continue
		if not route.is_empty() and route.back().distance_to(Vector2(trace.points[0])) > float(tuning.continuity): route.clear(); stamps.clear(); broken+=1
		for point: Vector2 in trace.points:
			if route.is_empty() or route.back().distance_to(point)>=3.0: route.append(point); stamps.append(float(trace.created_at))
	result.route_points=route.size(); result.broken_segments=broken
	var current: Array=state.trace_path
	if route.size()<8 or current.is_empty(): result.reason="paid_route_too_short"; return result
	if route.back().distance_to(Vector2(current[0]))>float(tuning.continuity): result.reason="disconnected_current"; return result
	for point: Vector2 in current:
		if route.back().distance_to(point)>=3.0: route.append(point); stamps.append(runtime.time)
	while route.size()>224: route.pop_front(); stamps.pop_front()
	if route.size()<10: result.reason="route_points"; return result
	if route.back().distance_to(Vector2(owner.pos))>float(tuning.emit_gap): result.reason="unemitted_live_tip"; return result
	var candidate: Dictionary={}; var best: float=float(tuning.preview); var geometries: int=0; var aged: int=0; var min_raw_gap: float=INF
	for index: int in range(route.size()-8):
		if runtime.time-stamps[index] < float(tuning.age): continue
		aged+=1
		var socket: Vector2=Geometry2D.get_closest_point_to_segment(owner.pos,route[index],route[index+1])
		var gap: float=socket.distance_to(Vector2(owner.pos)); min_raw_gap=minf(min_raw_gap,gap)
		if gap>best: continue
		var polygon:=PackedVector2Array([socket]); polygon.append_array(PackedVector2Array(route.slice(index+1)))
		var perimeter: float=0; var signed_area: float=0; var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for vertex: int in range(polygon.size()):
			var next: Vector2=polygon[(vertex+1)%polygon.size()]; perimeter+=polygon[vertex].distance_to(next); signed_area+=polygon[vertex].cross(next); bounds=bounds.expand(polygon[vertex])
		var area: float=absf(signed_area)*.5
		if perimeter<float(tuning.perimeter) or area<float(tuning.area) or bounds.size.x<float(tuning.extent) or bounds.size.y<float(tuning.extent) or gap/perimeter>float(tuning.gap_ratio): continue
		geometries+=1; best=gap
		candidate={"gap":gap,"perimeter":perimeter,"area":area,"bounds":bounds.size,"age":runtime.time-stamps[index],"points":polygon.size(),"socket":socket,"position":Vector2(owner.pos)}
	result.aged_segments=aged; result.geometry_candidates=geometries; result.minimum_raw_gap=min_raw_gap if is_finite(min_raw_gap) else -1
	if candidate.is_empty(): result.reason="no_old_segment" if aged==0 else ("outside_preview" if min_raw_gap>float(tuning.preview) else "invalid_area_perimeter_extent"); return result
	result.candidate=candidate
	result.reason="unpaid_frame" if not trace_emitted else ("closure_gap" if float(candidate.gap)>float(tuning.closure) else "qualifies")
	return result
