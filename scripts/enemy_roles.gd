extends RefCounted
## Four physics movement policies, two elite treatments, two authored bosses.
const BUILDS: Dictionary = {
	"hunter":{"blade":"smash","ratchet":"low","bit":"flat"},
	"flanker":{"blade":"hook","ratchet":"mid","bit":"rubber"},
	"bulwark":{"blade":"guard","ratchet":"low","bit":"ball"},
	"harasser":{"blade":"balance","ratchet":"high","bit":"needle"}
}
const COMMIT_START_SECONDS: float = 28.0
const COMMIT_MATURITY_SECONDS: float = 325.0
const ELITES: Dictionary = {
	"ballast":{"mass":1.55,"speed":0.76,"acceleration":0.8,"recovery":1.4},
	"hotwire":{"mass":0.9,"speed":1.17,"acceleration":1.3,"recovery":0.65,"spin_drain":1.15}
}
const BOSSES: Dictionary = {
	"anvil":{"mass":2.0,"speed":0.8,"acceleration":0.85,"recovery":1.6,"spin_drain":0.58},
	"reaper":{"mass":1.35,"speed":1.12,"acceleration":1.18,"recovery":0.9,"spin_drain":0.62}
}

static func configure(f: Dictionary, event: Dictionary) -> void:
	f.erase("pilot")
	f["role"] = event.role
	f["enemy_kind"] = event.kind
	f["archetype"] = event.key
	f["name"] = event.name
	f["event_serial"] = event.serial
	f["pressure_cost"] = event.cost
	# Irrational offsets spread the setup/commit beats instead of queueing all
	# later full tops on the same four repeating phases.
	f["role_phase"] = fposmod(float(int(f.entity_id))*1.6180339,5.6)
	f["role_commit_cycle"] = -1
	f["role_commit_heading"] = Vector2.ZERO
	f["role_attack_state"] = "approach"
	var handling: Dictionary = {}
	if event.role == "bulwark": handling = {"speed":0.68,"acceleration":0.72,"mass":1.2,"recovery":1.2}
	elif event.role == "harasser": handling = {"speed":1.07,"acceleration":1.13}
	var modifier: Dictionary = BOSSES.get(event.key,ELITES.get(event.key,{}))
	for key: String in modifier: handling[key] = float(handling.get(key,1.0))*float(modifier[key])
	# Bounded modest late handling scaling; pressure/composition do most of the work.
	var scale: float = 1.0+0.16*(1.0-exp(-maxi(0,int(event.get("tier_at_entry",0))-4)/10.0))
	handling["acceleration"] = float(handling.get("acceleration",1.0))*scale
	f["handling"] = handling
	f.mass *= float(handling.get("mass",1.0))
	if event.kind == "boss": f.radius *= 1.22

const STATES: Array[String] = ["assess","position","setup","commit","follow_through","recover","defend","retreat"]
const MAX_NEIGHBORS: int = 8
const MAX_HISTORY: int = 12

static func maturity(time: float) -> float:
	return clampf((time-COMMIT_START_SECONDS)/COMMIT_MATURITY_SECONDS,0.0,1.0)

static func decision_interval(f: Dictionary, time: float) -> float:
	# Bounded observable reactions, staggered without consuming any game RNG.
	var stagger: float = float(int(f.get("entity_id",2))%5)*0.008
	return lerpf(0.34,0.16,maturity(time))+stagger

static func build_tendencies(f: Dictionary) -> Dictionary:
	var stats: Dictionary = f.get("stats",{})
	var physical: Dictionary = f.get("part_physics",{})
	var speed: float = float(stats.get("speed",5.0))*float(physical.get("speed",1.0))
	var grip: float = float(stats.get("grip",5.0))*float(physical.get("control",1.0))
	var stamina: float = float(stats.get("stamina",5.0))/maxf(0.4,float(physical.get("rpm_drain",1.0)))
	var inertia: float = sqrt(maxf(0.18,float(physical.get("inertia",1.0))))
	return {"attack":clampf((float(stats.get("power",5.0))*0.65+speed*0.35)*float(physical.get("impact",1.0))/10.0,0.15,1.0),
		"defence":clampf((float(stats.get("stability",5.0))*0.5+float(f.get("mass",7.0))*0.35+stamina*0.15)*inertia/10.0,0.15,1.0),
		"mobile":clampf((speed*0.55+grip*0.45)/inertia/10.0,0.15,1.0),"stamina":clampf(stamina/10.0,0.15,1.0),
		"recovery":clampf(float(physical.get("wobble_recovery",1.0))*float(stats.get("stability",5.0))/10.0,0.15,1.0),
		"runup":clampf(42.0+speed*3.0+float(stats.get("power",5.0))*1.7,52.0,92.0)}

static func edge_clearance(pos: Vector2, arena: Dictionary={}) -> float:
	return minf(minf(float(arena.get("axis",166.0))-absf(pos.x),float(arena.get("axis",166.0))-absf(pos.y)),
		minf((float(arena.get("sum",270.0))-absf(pos.x+pos.y))/sqrt(2.0),(float(arena.get("gate",264.0))-absf(pos.x-pos.y))/sqrt(2.0)))

static func _pilot(f: Dictionary, time: float) -> Dictionary:
	if f.has("pilot"): return f.pilot
	var p: Dictionary = {"state":"assess","entered":time,"deadline":time,"last_time":-INF,"decisions":0,"transitions":0,
		"commit_serial":0,"heading":Vector2.ZERO,"goal":Vector2.ZERO,"side":1.0 if int(f.get("entity_id",2))%2==0 else -1.0,
		"profile":build_tendencies(f),"desired":Vector2.ZERO,"history":[],"last_contact":-INF,"contact_serial":0,"counter_used":0,
		"state_contacts":0,"attack_attempts":0,"failed_commits":0,"recoveries":0,"stuck_count":0,"stuck_anchor":Vector2(f.pos),"stuck_since":time,
		"last_target_position":Vector2.ZERO,"last_target_velocity":Vector2.ZERO,"target_burst_until":-INF,"target_vulnerable":false,
		"lane_clear":true,"clearance":edge_clearance(f.pos),"brake_intent":false,"burst_intent":false,"arena":{},"power_intent":{},
		"power_control":{"anchor_reposition":false,"sink_ready":-INF,"orbit_ready":-INF,"orbit_hold_until":-INF,"orbit_center":Vector2.ZERO,
			"last_burst_seen":-INF,"burst_ready":-INF}}
	f["pilot"] = p
	return p

static func _enter(p: Dictionary, state: String, time: float, duration: float, reason: String) -> void:
	p.state=state;p.entered=time;p.deadline=time+duration;p.transitions+=1
	p.stuck_anchor=p.get("own_position",p.stuck_anchor);p.stuck_since=time
	p.history.append({"state":state,"time":time,"reason":reason})
	if p.history.size()>MAX_HISTORY:p.history.pop_front()
	if state=="recover":p.recoveries+=1

static func _safe_goal(goal: Vector2) -> Vector2:
	# Intent waypoint only. The actual top remains subject to unchanged walls,
	# inertia, brakes and ring-outs; no position correction enters the solver.
	return goal.limit_length(125.0).clamp(Vector2(-139,-139),Vector2(139,139))

static func _holds_ground(p: Dictionary) -> bool:
	# Actual machine dominance can override a chasing role. A stable, slow
	# assembly should still claim ground when assigned the Hunter role.
	return float(p.profile.defence)-float(p.profile.attack)>0.22 and float(p.profile.mobile)<0.60

static func _burst_budget(p: Dictionary) -> float:
	# A reserve threshold alone lets an efficient stamina machine Burst MORE.
	# This is an intentional budget since the last OBSERVED physical activation,
	# in addition to the unchanged four-second mechanic and a useful opportunity.
	if _holds_ground(p) or float(p.profile.stamina)>0.72:
		return 4.0+float(p.profile.stamina)*4.0+float(p.profile.defence)*1.8
	return 4.0

static func _brake_rate(f: Dictionary) -> float:
	var grip: float=float(f.get("stats",{}).get("grip",5.0))
	var physical: Dictionary=f.get("part_physics",{})
	return maxf(2.0,0.54+grip*0.030+(3.8+grip*0.20)*float(physical.get("brake",1.0)))

static func _forecast_clearance(f: Dictionary, p: Dictionary, time: float, velocity: Vector2) -> float:
	# Approximate own stopping travel includes the next decision's latency and
	# ordinary Brake drag. It observes no player intent and changes no physics.
	var horizon: float=decision_interval(f,time)+1.0/_brake_rate(f)
	return edge_clearance(Vector2(f.pos)+velocity*horizon,p.arena)

static func _edge_danger(f: Dictionary, p: Dictionary, time: float) -> bool:
	var velocity: Vector2=f.get("vel",Vector2.ZERO)
	var margin: float=9.0+float(p.profile.defence)*10.0-float(p.profile.attack)*4.0
	return Vector2(f.pos).dot(velocity)>150.0 and _forecast_clearance(f,p,time,velocity)<margin

static func _strike_alignment(f: Dictionary, target: Dictionary) -> float:
	var velocity: Vector2=f.get("vel",Vector2.ZERO)
	if velocity.length()<42.0:return 1.0
	return velocity.normalized().dot((Vector2(target.pos)-Vector2(f.pos)).normalized())

static func _lane_clear(f: Dictionary, target: Dictionary, neighbors: Array) -> bool:
	var start: Vector2=f.pos
	var finish: Vector2=target.pos
	var offset: Vector2=finish-start
	for index: int in range(mini(MAX_NEIGHBORS,neighbors.size())):
		var neighbor: Dictionary=neighbors[index]
		if int(neighbor.get("entity_id",-1))==int(f.get("entity_id",2)):continue
		var other: Vector2=neighbor.get("pos",Vector2.ZERO)
		var t: float=(other-start).dot(offset)/maxf(1.0,offset.length_squared())
		if t<=0.08 or t>=0.92:continue
		var nearest: Vector2=Geometry2D.get_closest_point_to_segment(other,start,finish)
		if other.distance_to(nearest)<float(f.get("radius",12.0))+float(neighbor.get("radius",12.0))+7.0:return false
	return true

static func _position_goal(f: Dictionary, target: Dictionary, p: Dictionary, neighbors: Array) -> Vector2:
	var toward: Vector2=(Vector2(target.pos)-Vector2(f.pos)).normalized()
	if toward.length_squared()<0.01:toward=Vector2.LEFT
	var side: Vector2=toward.orthogonal()*float(p.side)
	var role: String=str(f.get("role","hunter"))
	var goal: Vector2
	if _holds_ground(p):return Vector2(target.pos).limit_length(32.0)
	match role:
		"bulwark":goal=Vector2(target.pos).limit_length(28.0)
		"flanker":goal=Vector2(target.pos)+side*(60.0+float(p.profile.mobile)*25.0)-toward*18.0
		"harasser":goal=Vector2(target.pos)+side*58.0-toward*36.0
		_:goal=Vector2(target.pos)-toward*float(p.profile.runup)+side*(12.0+clampf((float(p.profile.mobile)-0.60)*4.0,0.0,1.0)*38.0)
	for index: int in range(mini(MAX_NEIGHBORS,neighbors.size())):
		var neighbor: Dictionary=neighbors[index]
		if int(neighbor.get("entity_id",-1))==int(f.get("entity_id",2)):continue
		var other: Vector2=neighbor.get("pos",Vector2.ZERO)
		var state: String=str(neighbor.get("state",""))
		var heading: Vector2=neighbor.get("commit_heading",neighbor.get("heading",Vector2.ZERO))
		if other.distance_to(goal)<35.0 or (role=="flanker" and state in ["commit","follow_through"] and heading.dot(toward)>0.72):
			goal+=side*27.0
	return _safe_goal(goal)

static func _commit(f: Dictionary, target: Dictionary, p: Dictionary, time: float) -> void:
	p.commit_serial+=1;p.attack_attempts+=1;p.state_contacts=0
	var skill: float=maturity(time)
	var lead: Vector2=(Vector2(target.get("vel",Vector2.ZERO))*lerpf(0.09,0.19,skill)).limit_length(lerpf(9.0,22.0,skill))
	var sample: float=sin(float(f.get("entity_id",2))*2.17+float(p.commit_serial)*1.31+float(f.get("event_serial",0))*0.73)
	var error: float=sample*lerpf(0.19,0.045,skill)
	p.heading=(Vector2(target.pos)-Vector2(f.pos)+lead).normalized().rotated(error)
	if p.heading.length_squared()<0.01:p.heading=Vector2.LEFT
	var duration: float=lerpf(0.68,0.46,skill)
	if str(f.get("role",""))=="harasser":duration*=0.64
	if str(f.get("archetype",""))=="anvil":duration*=1.25
	_enter(p,"commit",time,duration,"observed lane / finite sampled strike")

static func _select(f: Dictionary, target: Dictionary, p: Dictionary, time: float, neighbors: Array) -> void:
	var rpm: float=float(f.get("rpm",1.0))
	var wobble: float=float(f.get("wobble",0.0))
	var role: String=str(f.get("role","hunter"))
	if rpm<0.19 or wobble>0.72:
		p.goal=Vector2(f.pos).limit_length(42.0)
		_enter(p,"retreat",time,1.8,"reserve / wobble survival");return
	if (role=="bulwark" or _holds_ground(p)) and (Vector2(f.pos).length()<55.0 or Vector2(f.pos).distance_to(target.pos)<58.0):
		p.goal=Vector2(target.pos).limit_length(28.0)
		_enter(p,"defend",time,lerpf(2.2,1.3,maturity(time)),"claim useful ground");return
	p.goal=_position_goal(f,target,p,neighbors)
	var ghost: bool=str(f.get("power_mutations",{}).get("afterimage",""))=="ghost_circuit"
	p.power_control.orbit_center=Vector2(target.pos).limit_length(62.0)
	_enter(p,"position",time,3.6 if ghost else lerpf(1.45,0.88,maturity(time)),"reachable role / build lane")

static func _incoming(f: Dictionary, target: Dictionary) -> bool:
	var offset: Vector2=Vector2(f.pos)-Vector2(target.pos)
	var distance: float=offset.length()
	var closing: float=(Vector2(target.get("vel",Vector2.ZERO))-Vector2(f.get("vel",Vector2.ZERO))).dot(offset.normalized())
	return distance<100.0 and closing>45.0 and distance/maxf(1.0,closing)<0.7

static func _transition(f: Dictionary, target: Dictionary, p: Dictionary, time: float, neighbors: Array) -> void:
	var pos: Vector2=f.pos
	var velocity: Vector2=f.get("vel",Vector2.ZERO)
	var distance: float=pos.distance_to(target.pos)
	var age: float=time-float(p.entered)
	var role: String=str(f.get("role","hunter"))
	var reserve_danger: bool=float(f.get("rpm",1.0))<0.19 or float(f.get("wobble",0.0))>0.72
	if bool(p.power_control.anchor_reposition):
		if p.state not in ["retreat","assess"]:_enter(p,"retreat",time,1.8,"real Anchor stress/quota reposition")
		elif time>=float(p.deadline):_enter(p,"assess",time,0.0,"finite Anchor reposition re-assessment")
		if p.state=="assess":_enter(p,"retreat",time,1.8,"continue real released rotation until recovered")
		return
	if reserve_danger and p.state not in ["retreat","assess"]:
		_enter(p,"retreat",time,1.8,"observed reserve / wobble danger");return
	if _edge_danger(f,p,time) and p.state not in ["defend","retreat","commit","follow_through"]:
		p.goal=pos.limit_length(42.0);_enter(p,"defend",time,0.72,"actual outward edge exposure");return
	match str(p.state):
		"assess":_select(f,target,p,time,neighbors)
		"position":
			var opportunity: bool=p.target_vulnerable or (float(p.target_burst_until)>time and distance<90.0)
			var ready: bool=pos.distance_to(p.goal)<22.0 or (role=="hunter" and not _holds_ground(p) and distance>float(p.profile.runup)*0.78 and distance<120.0)
			var ghost: bool=str(f.get("power_mutations",{}).get("afterimage",""))=="ghost_circuit"
			if ((not ghost and (ready or opportunity)) or time>=float(p.deadline)) and distance<145.0:
				_enter(p,"setup",time,lerpf(0.70,0.34,maturity(time)),"lane reached / exposed target / bounded setup")
			elif time>=float(p.deadline):_enter(p,"assess",time,0.0,"distant lane re-evaluation")
		"setup":
			if time>=float(p.deadline):
				var aligned: bool=_strike_alignment(f,target)>0.68
				var maximum_setup: float=lerpf(1.65,1.20,maturity(time))
				if p.lane_clear and distance>22.0 and distance<145.0 and aligned and not _edge_danger(f,p,time):_commit(f,target,p,time)
				elif age>=maximum_setup:_enter(p,"recover",time,0.85,"finite poor lane / real velocity not straightened")
		"commit":
			var passed: bool=(Vector2(target.pos)-pos).dot(Vector2(p.heading))< -16.0
			if time>=float(p.deadline) or passed or (int(p.state_contacts)>0 and age>0.16):
				_enter(p,"follow_through",time,lerpf(0.58,0.38,maturity(time)),"real contact / overshoot / finite strike")
		"follow_through":
			if time>=float(p.deadline):
				if int(p.state_contacts)==0:p.failed_commits+=1
				_enter(p,"recover",time,lerpf(1.2,0.80,maturity(time)),"physical pull-out after strike")
		"recover":
			if time>=float(p.deadline):_enter(p,"assess",time,0.0,"recovered / choose next lane")
		"defend":
			var counter: bool=int(p.contact_serial)>int(p.counter_used) and time-float(p.last_contact)<1.6
			if counter and distance>22.0 and not reserve_danger and float(p.clearance)>20.0:
				p.counter_used=p.contact_serial;_enter(p,"setup",time,lerpf(0.52,0.28,maturity(time)),"counter real received contact")
			elif p.target_vulnerable and not _incoming(f,target) and distance<105.0 and age>0.4:
				_enter(p,"setup",time,0.42,"counter observed instability")
			elif time>=float(p.deadline):
				if (role=="bulwark" or _holds_ground(p)) and distance<105.0 and not _incoming(f,target) and p.lane_clear and not reserve_danger:
					_enter(p,"setup",time,0.55,"ground secured / measured shove")
				else:_enter(p,"assess",time,0.0,"finite brace / re-evaluate safety")
		"retreat":
			if time>=float(p.deadline):_enter(p,"assess",time,0.0,"finite survival re-assessment")
	if p.state in ["position","setup"] and time-float(p.stuck_since)>1.8:
		if pos.distance_to(p.stuck_anchor)<5.0 and velocity.length()<8.0:
			p.stuck_count+=1;p.side=-float(p.side)
			_enter(p,"recover",time,0.75,"observed stalled lane / turn out")
		else:p.stuck_anchor=pos;p.stuck_since=time

static func _steering(f: Dictionary, target: Dictionary, p: Dictionary, time: float) -> Vector2:
	var pos: Vector2=f.pos
	var velocity: Vector2=f.get("vel",Vector2.ZERO)
	var offset: Vector2=Vector2(target.pos)-pos
	var distance: float=offset.length()
	var toward: Vector2=offset.normalized()
	var side: Vector2=toward.orthogonal()*float(p.side)
	var role: String=str(f.get("role","hunter"))
	var desired: Vector2=Vector2.ZERO
	if bool(p.power_control.anchor_reposition):
		var radial: Vector2=pos.normalized() if pos.length()>4.0 else Vector2.RIGHT.rotated(float(f.get("entity_id",2)))
		# Actual released travel outside the canonical82-unit rearm circle. This
		# is merely steering; the runtime earns cooling/quota from real motion.
		return (radial*clampf((103.0-pos.length())/30.0,-0.45,0.85)+radial.orthogonal()*float(p.side)*0.72).limit_length(0.95)
	match str(p.state):
		"position":
			if _holds_ground(p):desired=((Vector2(p.goal)-pos)*0.035-velocity*0.008).limit_length(0.64)
			elif role=="hunter":desired=toward*0.78+side*(0.20+clampf((float(p.profile.mobile)-0.60)*2.0,0.0,0.20)) if distance>float(p.profile.runup)*0.78 else (Vector2(p.goal)-pos).normalized()*0.8
			elif role=="bulwark":desired=((Vector2(p.goal)-pos)*0.035-velocity*0.008).limit_length(0.68)
			elif role=="flanker":desired=side*(0.66+float(p.profile.mobile)*0.26)+toward*clampf((distance-76.0)/70.0,-0.45,0.65)
			else:desired=(Vector2(p.goal)-pos).normalized()*0.67+side*0.24
		"setup":
			if velocity.length()>80.0 and _strike_alignment(f,target)<0.55:
				# A lateral Brake would enter Orbit drift and retain the unwanted
				# tangent. Straight Brake first sheds real speed, then steering turns.
				desired=velocity.normalized()*0.20
			elif "momentum_bank" in f.get("powers",[]) and velocity.length()>75.0 and float(f.get("momentum_charge",0.0))<70.0:
				# Straight steered Brake stores genuine lost speed. A lateral Brake
				# would instead enter Orbit Drive drift and cannot bank that loss.
				desired=velocity.normalized()*0.36
			elif role=="bulwark" or _holds_ground(p):desired=toward*0.40-velocity*0.004
			elif distance<40.0:desired=-toward*0.60+side*0.44
			else:desired=toward*(0.65+float(p.profile.attack)*0.18)+side*(0.28 if role=="flanker" else 0.10)
		"commit":desired=Vector2(p.heading)*0.95
		"follow_through":desired=Vector2(p.heading)*0.75
		"recover":
			var exit_line: Vector2=-toward*0.64+side*0.54 if distance<86.0 else side*0.54+toward*0.30
			desired=((Vector2(p.goal)-pos)*0.028-velocity*0.009).limit_length(0.52) if _holds_ground(p) else velocity.normalized()*0.32+exit_line*0.62
		"defend":
			desired=((Vector2(p.goal)-pos)*0.03-velocity*0.007).limit_length(0.60)
			if float(p.clearance)<20.0:desired=-pos.normalized()*0.74
		"retreat":
			desired=-pos.normalized()*0.48-toward*0.24+side*0.18
			desired=desired.limit_length(0.32 if float(f.get("rpm",1.0))<0.12 else 0.57)
	# Strong native anchor ownership changes position preference, not physics.
	if "dead_centre" in f.get("powers",[]) and p.state in ["position","defend"] and pos.length()<45.0:
		desired=(Vector2(p.goal)-pos).limit_length(20.0)/80.0-velocity*0.005
	var ghost: bool=str(f.get("power_mutations",{}).get("afterimage",""))=="ghost_circuit"
	if "orbit_drive" in f.get("powers",[]) or ghost:
		if p.state=="position" and role!="bulwark":desired=side*0.86+toward*clampf((distance-72.0)/80.0,-0.35,0.55)
		if ghost and p.state=="position":
			var radial: Vector2=pos-Vector2(p.power_control.orbit_center)
			if radial.length()<1.0:radial=Vector2.RIGHT
			desired=radial.normalized().orthogonal()*float(p.side)*0.94-radial.normalized()*clampf((radial.length()-54.0)/42.0,-0.48,0.54)
			var advice: Dictionary=f.get("ghost_route_advice",{})
			if bool(advice.get("paid_visible_live",false)) and float(advice.get("expires_at",-1.0))>time and float(p.clearance)>38.0 and float(f.get("rpm",0.0))>.22:
				# Actual live route advice supplies a reachable tail/socket only.
				# Ordinary acceleration, edge safety and the locked attack pilot
				# still govern the movement; no route or activation is fabricated.
				var hijack_offset: Vector2=Vector2(advice.point)-pos
				if hijack_offset.length()>3.0 and hijack_offset.length()<90.0:
					desired=(hijack_offset.normalized()*.92-velocity*.0018).limit_length(.95)
	if _edge_danger(f,p,time):
		if p.state in ["commit","follow_through"]:
			# Keep the locked trajectory while ordinary Brake sheds momentum.
			desired=Vector2(p.heading)*0.12
		elif "orbit_drive" in f.get("powers",[]) and velocity.length()>=80.0:
			# Straight braking avoids converting a safety stop into a long drift.
			desired=velocity.normalized()*0.12
		else:desired=(-pos.normalized()*0.68-velocity.normalized()*0.20).limit_length(0.85)
	elif p.state not in ["commit","follow_through"] and float(p.clearance)<38.0 and desired.dot(pos)>0.0:
		desired=desired.lerp(-pos.normalized(),clampf((38.0-float(p.clearance))/35.0,0.0,0.90))
	return desired.limit_length(0.95)

static func _brake(f: Dictionary, target: Dictionary, p: Dictionary) -> bool:
	var velocity: Vector2=f.get("vel",Vector2.ZERO)
	if _edge_danger(f,p,float(p.last_time)):return true
	if float(p.clearance)<22.0 and Vector2(f.pos).dot(velocity)>350.0:return true
	var defence: float=float(p.profile.defence)
	if _incoming(f,target) and (str(f.get("role",""))=="bulwark" or defence>0.72):return true
	if p.state=="defend":return velocity.length()>12.0 or _incoming(f,target)
	if p.state=="setup" and velocity.length()>80.0 and _strike_alignment(f,target)<0.55:return true
	if p.state=="setup" and defence>0.70:return velocity.length()>38.0 and not p.target_vulnerable
	return p.state in ["recover","retreat"] and float(f.get("wobble",0.0))>0.48 and velocity.length()>28.0

static func _power_brake(f: Dictionary, p: Dictionary, time: float, normal_brake: bool) -> bool:
	var owned: Array=f.get("powers",[])
	var speed: float=Vector2(f.get("vel",Vector2.ZERO)).length()
	if _edge_danger(f,p,time):return true
	if bool(p.power_control.anchor_reposition) and float(p.clearance)>22.0:return false
	if "impact_sink" in owned and float(f.get("sink_charge",0.0))>=15.0 and speed<=115.0 and time>=float(p.power_control.sink_ready):
		# Release a held brake first; only a later fresh physical press can vent
		# the real reservoir. No stored charge or activation is fabricated.
		if bool(p.brake_intent):return false
		p.power_control.sink_ready=time+1.5
		return true
	if "momentum_bank" in owned and p.state=="setup" and speed>75.0 and float(f.get("momentum_charge",0.0))<70.0:return true
	if "orbit_drive" in owned and p.state in ["position","recover"] and speed>=80.0:
		var turn: float=absf(Vector2(f.vel).normalized().angle_to(Vector2(p.desired).normalized()))
		if turn>=0.12 and turn<2.25 and float(p.clearance)>28.0:
			if time<float(p.power_control.orbit_hold_until):return true
			if time>=float(p.power_control.orbit_ready):
				p.power_control.orbit_hold_until=time+decision_interval(f,time)
				p.power_control.orbit_ready=time+lerpf(1.05,0.75,maturity(time))
				return true
	return normal_brake

static func direction(f: Dictionary, target: Dictionary, time: float, context: Dictionary={}) -> Vector2:
	if target.is_empty():return Vector2.ZERO
	var p: Dictionary=_pilot(f,time)
	if time<=float(p.last_time):return p.desired
	p.last_time=time;p.decisions+=1;p.own_position=Vector2(f.pos)
	p.arena=context.get("arena",{})
	p.clearance=edge_clearance(f.pos,p.arena)
	var neighbors: Array=context.get("neighbors",[])
	p.lane_clear=_lane_clear(f,target,neighbors)
	p.target_vulnerable=float(target.get("rpm",1.0))<0.42 or float(target.get("wobble",0.0))>0.42 or float(target.get("burst_time",0.0))>0.04
	if float(target.get("anchor_charge",0.0))>0.55 and float(target.get("anchor_stress",0.0))<0.45:p.target_vulnerable=false
	if float(target.get("burst_time",0.0))>0.04:p.target_burst_until=time+0.90
	if float(f.get("burst_time",0.0))>0.0 and time-float(p.power_control.last_burst_seen)>1.0:
		p.power_control.last_burst_seen=time;p.power_control.burst_ready=time+_burst_budget(p)
	if "dead_centre" in f.get("powers",[]):
		var stress: float=float(f.get("anchor_stress",0.0))
		var quota: float=float(f.get("anchor_recovery_remaining",0.20))
		if stress>=0.55 or quota<=0.03:p.power_control.anchor_reposition=true
		elif bool(p.power_control.anchor_reposition) and stress<=0.30 and quota>=0.18 and not bool(f.get("anchor_overloaded",false)):
			p.power_control.anchor_reposition=false
			_enter(p,"assess",time,0.0,"real Anchor cooling/rearm complete")
	_transition(f,target,p,time,neighbors)
	p.desired=_steering(f,target,p,time)
	p.brake_intent=_power_brake(f,p,time,_brake(f,target,p))
	p.burst_intent=p.state=="commit" and p.lane_clear and not p.brake_intent
	p.last_target_position=Vector2(target.pos);p.last_target_velocity=Vector2(target.get("vel",Vector2.ZERO))
	p.power_intent={"holding_ground":p.state=="defend","orbiting":p.state=="position" and str(f.get("role","")) in ["flanker","harasser"],
		"committed_lane":p.burst_intent,"stored_force_release":float(f.get("stored_force",0.0))>0.0 and p.state=="commit"}
	f["role_attack_state"]="committed" if p.state in ["commit","follow_through"] else ("recover" if p.state in ["recover","retreat"] else "set_up")
	f["role_commit_heading"]=p.heading;f["role_commit_cycle"]=p.commit_serial
	return p.desired

static func wants_burst(f: Dictionary, target: Dictionary, time: float) -> bool:
	if target.is_empty() or not f.has("pilot"):return false
	var p: Dictionary=f.pilot
	if not p.burst_intent or p.state!="commit" or time-float(p.entered)>0.48:return false
	if time<float(p.power_control.burst_ready):return false
	if float(f.get("cooldown",0.0))>0.0 or float(f.get("burst_time",0.0))>0.0:return false
	var threshold: float=0.15+float(p.profile.stamina)*0.10+float(p.profile.defence)*0.065
	if float(f.get("rpm",1.0))<threshold or float(f.get("wobble",0.0))>0.56:return false
	if (_holds_ground(p) or float(p.profile.stamina)>0.72) and not p.target_vulnerable and time-float(p.last_contact)>1.8:return false
	var offset: Vector2=Vector2(target.pos)-Vector2(f.pos)
	var heading: Vector2=p.heading
	if offset.length()<26.0 or offset.length()>125.0 or heading.dot(offset.normalized())<lerpf(0.82,0.72,maturity(time)):return false
	var velocity: Vector2=f.get("vel",Vector2.ZERO)
	if velocity.length()>30.0 and velocity.normalized().dot(heading)<0.55:return false
	var push: float=67.0+float(f.get("stats",{}).get("grip",5.0))*3.0
	if "momentum_bank" in f.get("powers",[]):push+=float(f.get("momentum_charge",0.0))
	var projected_velocity: Vector2=velocity+heading*push
	var safe_margin: float=8.0+float(p.profile.defence)*13.0-float(p.profile.attack)*7.0
	if _forecast_clearance(f,p,time,projected_velocity)<safe_margin:return false
	if str(f.get("role",""))=="bulwark" and not p.target_vulnerable and time-float(p.last_contact)>1.8:return false
	return true

static func wants_brake(f: Dictionary, _target: Dictionary, _time: float) -> bool:
	return bool(f.get("pilot",{}).get("brake_intent",false))

static func observe_contact(f: Dictionary, _target: Dictionary, time: float, severity: float) -> void:
	if severity<0.16:return
	var p: Dictionary=_pilot(f,time)
	p.last_contact=time;p.contact_serial+=1;p.state_contacts+=1

static func decision_snapshot(f: Dictionary) -> Dictionary:
	return f.get("pilot",{}).duplicate(true)
