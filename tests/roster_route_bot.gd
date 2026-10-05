extends RefCounted
## A deliberately drawn route and preview-following inputs, never fake procs.
## All steering is expressed through the ordinary screen input transform.
static func input(b: Node2D, tick: int, follow_preview: bool = true, radius: float = 85.0, pace: float = 145.0) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var pos: Vector2 = p.pos
	var velocity: Vector2 = p.vel
	var radial: Vector2 = pos.normalized() if pos.length() > 1.0 else Vector2.RIGHT
	var tangent: Vector2 = Vector2(-radial.y,radial.x)
	var route: Vector2 = tangent*pace+radial*(radius-pos.length())*2.0
	var thrust: Vector2 = (route-velocity)*4.0+route*0.75-radial*(pace*pace/radius)
	var preview: Dictionary = p.get("ghost_preview",{})
	if follow_preview and not preview.is_empty() and float(preview.get("expires_at",0.0)) >= b.powers.time:
		var gap: Vector2 = Vector2(preview.a)-pos
		if gap.length() > 5.0:
			# The visible socket is the goal. A velocity controller steers into it
			# without braking away the meaningful-speed closing trace.
			var heading: Vector2 = gap.normalized()
			var current: Vector2 = velocity.normalized()
			if current.length_squared() > 0.5: heading = current.lerp(heading,0.70).normalized()
			var desired: Vector2 = heading*pace
			thrust = (desired-velocity)*4.5+desired*0.80
	var available: float = (123.0+float(p.stats.grip)*17.0)*float(p.handling.get("acceleration",1.0))
	var world: Vector2 = thrust.limit_length(available)/available
	return {"direction":Vector2(world.x-world.y,(world.x+world.y)*0.5).normalized()*world.length(),"brake":false,"burst":false,"preview_followed":follow_preview and not preview.is_empty()}

static func inspect(b: Node2D) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var timestamps: Array[float] = []
	var points: int = 0
	var gaps: float = 0.0
	var last: Vector2 = Vector2.ZERO
	for trace: Dictionary in b.powers.traces:
		if int(trace.owner_entity_id) != int(p.entity_id): continue
		timestamps.append(float(trace.created_at))
		points += trace.points.size()
		if timestamps.size() > 1: gaps = maxf(gaps,last.distance_to(Vector2(trace.points[0])))
		last = trace.points.back()
	var preview: Dictionary = p.get("ghost_preview",{})
	return {"time":b.elapsed,"rpm":p.rpm,"speed":Vector2(p.vel).length(),"radius":Vector2(p.pos).length(),"trace_count":timestamps.size(),"trace_span":timestamps.back()-timestamps.front() if timestamps.size() > 1 else 0.0,"points":points,"connected_gap_max":gaps,"preview_gap":Vector2(preview.a).distance_to(p.pos) if not preview.is_empty() else -1.0,"preview_strength":preview.get("strength",0.0),"ghost":p.get("power_mutations",{}).get("afterimage","") == "ghost_circuit"}
