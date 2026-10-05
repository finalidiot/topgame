extends RefCounted
class_name ComponentPhysics

## Bounded reusable coefficients. Legacy assemblies opt out of new motion
## hooks, preserving the parent's exact arithmetic. No part ID in this solver.
const SCALES: Dictionary = {"mass":1.0, "acceleration":1.0, "speed":1.0, "control":1.0, "drag":1.0, "brake":1.0, "bank":1.0, "orbit":1.0, "rpm_drain":1.0, "wobble_recovery":1.0, "inertia":1.0, "impact":1.0, "recoil":1.0, "shock":1.0, "wall_restitution":1.0, "wall_retention":1.0, "wall_cost":1.0, "glancing_impact":1.0, "grip_low":1.0, "grip_high":1.0}
const ADDITIVE: Dictionary = {"radius":0.0, "lobes":0.0, "radial_depth":0.0, "profile_angle":0.0, "radius_lobes":0.0, "radius_angle":0.0, "radius_gap_angle":0.0, "radius_gap_width":0.0, "radius_gap_depth":0.0, "point_width":0.0, "aligned_impact":0.0, "glancing_recoil":0.0, "tangent_transfer":0.0, "tangent_glance":0.0, "repeat_pressure":0.0, "contact_drain":0.0, "imbalance":0.0, "sway":0.0, "centre_hold":0.0, "curve":0.0, "lateral_drag":0.0, "turn_cost":0.0, "grip_threshold":0.0, "high_speed_wobble":0.0, "grip_wave":0.0, "grip_frequency":0.0, "wall_tangent":0.0, "contact_height":0.0, "visual_height":0.0}

static func assemble(definitions: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = SCALES.duplicate()
	result.merge(ADDITIVE)
	result["enabled"] = false
	result["contact_interval"] = 0.24
	result["contact_points"] = []
	for data: Dictionary in definitions:
		result.enabled = result.enabled or not bool(data.get("legacy", false))
		var coefficients: Dictionary = data.get("physics", {})
		for key: String in coefficients:
			if SCALES.has(key): result[key] = float(result[key]) * float(coefficients[key])
			elif ADDITIVE.has(key): result[key] = float(result[key]) + float(coefficients[key])
			elif key == "contact_interval": result[key] = minf(float(result[key]), float(coefficients[key]))
			elif key == "contact_points": result[key] = coefficients[key].duplicate()
	for key: String in SCALES: result[key] = clampf(float(result[key]), 0.18, 3.0)
	result.radius = clampf(float(result.radius), 8.0, 17.0)
	result.radial_depth = clampf(float(result.radial_depth), 0.0, 0.70)
	result.radius_gap_depth = clampf(float(result.radius_gap_depth),0.0,0.70)
	result.imbalance = clampf(float(result.imbalance), 0.0, 0.14)
	result.sway = clampf(float(result.sway), 0.0, 35.0)
	return result

static func coefficients(fighter: Dictionary) -> Dictionary:
	return fighter.get("part_physics", {})

static func active(fighter: Dictionary) -> bool:
	return bool(coefficients(fighter).get("enabled", false))

static func grip(fighter: Dictionary, clock: float) -> float:
	var physical: Dictionary = coefficients(fighter)
	var result: float = 1.0
	var speed: float = Vector2(fighter.vel).length()
	if float(physical.grip_threshold) > 0.0:
		var slip: float = smoothstep(float(physical.grip_threshold)-12.0, float(physical.grip_threshold)+12.0, speed)
		result *= lerpf(float(physical.grip_low), float(physical.grip_high), slip)
	if float(physical.grip_wave) > 0.0:
		result *= 1.0 + sin(clock * TAU * float(physical.grip_frequency)) * float(physical.grip_wave)
	return clampf(result, 0.18, 1.8)

static func contact_radius(fighter: Dictionary, normal: Vector2) -> float:
	var radius: float = float(fighter.radius)
	if not active(fighter): return radius
	var physical: Dictionary = coefficients(fighter)
	var alignment: float = face_alignment(fighter,normal)
	if float(physical.radius_lobes) > 0.0:
		alignment = cos((normal.angle()-float(fighter.get("spin_angle",0.0))-float(physical.radius_angle))*float(physical.radius_lobes))
	var result: float = radius*(1.0-float(physical.radial_depth)*(1.0-alignment)*0.5)
	if float(physical.radius_gap_width) > 0.0:
		var gap: float = absf(wrapf(normal.angle()-float(fighter.get("spin_angle",0.0))-float(physical.radius_gap_angle),-PI,PI))
		result = radius*(1.0-float(physical.radius_gap_depth)*(1.0-smoothstep(0.0,float(physical.radius_gap_width),gap)))
	return maxf(5.0,result)

static func face_alignment(fighter: Dictionary, normal: Vector2) -> float:
	var physical: Dictionary = coefficients(fighter)
	var angle: float = normal.angle()-float(fighter.get("spin_angle",0.0))-float(physical.profile_angle)
	var points: Array = physical.contact_points
	if not points.is_empty():
		var best: float = 0.0
		for point: float in points:
			var difference: float = wrapf(angle-point,-PI,PI)
			best = maxf(best,exp(-pow(difference/maxf(0.08,float(physical.point_width)),2.0)))
		return best*2.0-1.0
	return cos(angle*float(physical.lobes)) if float(physical.lobes) > 0.0 else 0.0

static func contact_profile(fighter: Dictionary, normal: Vector2, relative: Vector2, now: float, other_id: int) -> Dictionary:
	var physical: Dictionary = coefficients(fighter)
	if not active(fighter):
		return {"attack":1.0,"recoil":1.0,"shock":1.0,"tangent":float(physical.get("tangent_transfer",0.0)),"own_cost":0.0,"interval":0.24}
	var aligned: float = face_alignment(fighter,normal)
	var glance: float = 1.0-clampf(absf(relative.dot(normal))/maxf(1.0,relative.length()),0.0,1.0)
	var attack: float = float(physical.impact)*(1.0+aligned*float(physical.aligned_impact))
	attack *= lerpf(1.0,float(physical.glancing_impact),glance)
	attack *= 1.0+float(physical.contact_height)*0.16
	var memory: Dictionary = fighter.get("part_contacts", {})
	var recent: Dictionary = memory.get(other_id,{"time":-10.0,"pressure":0.0})
	var pressure: float = float(recent.pressure)*exp(-maxf(0.0,now-float(recent.time))*2.1)
	attack *= 1.0+pressure*float(physical.repeat_pressure)
	return {"attack":clampf(attack,0.35,1.9),"recoil":clampf(float(physical.recoil)*(1.0+glance*float(physical.glancing_recoil)),0.45,1.7),"shock":clampf(float(physical.shock)/float(physical.inertia),0.35,1.6),"tangent":float(physical.tangent_transfer)*(1.0+glance*float(physical.tangent_glance)),"own_cost":float(physical.contact_drain)*(1.0+pressure),"interval":float(physical.contact_interval)}

static func remember_contact(fighter: Dictionary, other_id: int, now: float) -> void:
	if not active(fighter): return
	var memory: Dictionary = fighter.get("part_contacts", {})
	var previous: Dictionary = memory.get(other_id,{"time":-10.0,"pressure":0.0})
	var decayed: float = float(previous.pressure)*exp(-maxf(0.0,now-float(previous.time))*2.1)
	memory[other_id] = {"time":now,"pressure":minf(1.0,decayed+0.32)}
	if memory.size() > 12:
		var oldest: int = other_id
		var oldest_time: float = now
		for id: int in memory:
			if float(memory[id].time) < oldest_time:
				oldest = id; oldest_time = float(memory[id].time)
		memory.erase(oldest)
	fighter["part_contacts"] = memory
