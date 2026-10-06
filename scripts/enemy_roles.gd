extends RefCounted
## Four physics movement policies, two elite treatments, two authored bosses.
const BUILDS: Dictionary = {
	"hunter":{"blade":"smash","ratchet":"low","bit":"flat"},
	"flanker":{"blade":"hook","ratchet":"mid","bit":"rubber"},
	"bulwark":{"blade":"guard","ratchet":"low","bit":"ball"},
	"harasser":{"blade":"balance","ratchet":"high","bit":"needle"}
}
const ELITES: Dictionary = {
	"ballast":{"mass":1.55,"speed":0.76,"acceleration":0.8,"recovery":1.4},
	"hotwire":{"mass":0.9,"speed":1.17,"acceleration":1.3,"recovery":0.65,"spin_drain":1.15}
}
const BOSSES: Dictionary = {
	"anvil":{"mass":2.0,"speed":0.8,"acceleration":0.85,"recovery":1.6,"spin_drain":0.58},
	"reaper":{"mass":1.35,"speed":1.12,"acceleration":1.18,"recovery":0.9,"spin_drain":0.62}
}

static func configure(f: Dictionary, event: Dictionary) -> void:
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

static func direction(f: Dictionary, player: Dictionary, time: float) -> Vector2:
	if player.is_empty(): return Vector2.ZERO
	var pos: Vector2 = f.pos
	var offset: Vector2 = Vector2(player.pos)-pos
	var distance: float = offset.length()
	var toward: Vector2 = offset.normalized()
	var side: Vector2 = toward.orthogonal() * (1.0 if int(f.entity_id)%2 == 0 else -1.0)
	var phase: float = fmod(time+float(f.role_phase),5.0)
	var desired: Vector2 = toward
	# The opening keeps its familiar role movement. Threat maturity adds physical
	# commitment, not damage/HP multipliers or a timer keyed to player inactivity.
	if time >= 35.0:
		return _committed_direction(f,player,time)
	match str(f.role):
		"hunter": desired = (offset+Vector2(player.vel)*0.16).normalized()
		"flanker": desired = toward*clampf((distance-57.0)/75.0,-0.4,0.85)+side*0.85
		"bulwark":
			var hold: Vector2 = Vector2(player.pos).limit_length(48.0)
			desired = (hold-pos).limit_length(40.0)/40.0*0.72
			if distance < 45.0: desired = toward*0.45
		"harasser": desired = toward*(0.92 if phase < 1.6 else (-0.55 if distance < 70.0 else 0.4))+side*0.65
	if f.archetype == "anvil":
		# Visible slow centre hold, then a committed radial shove every six seconds.
		var beat: float = fmod(time+float(f.role_phase),6.0)
		if beat > 4.8: desired = toward
	elif f.archetype == "reaper":
		# Alternates broad orbit and a cutting approach; never reads future input.
		if phase > 3.5: desired = (offset+Vector2(player.vel)*0.22).normalized()
	var edge: float = maxf(pos.length(),absf(pos.x-pos.y)*0.75)
	if edge > 145.0: desired = desired.lerp(-pos.normalized(),clampf((edge-145.0)/40.0,0.0,0.92))
	return desired.limit_length(0.95)

static func _attack_beat(f: Dictionary, time: float) -> Dictionary:
	var role: String = str(f.role)
	var cycle: float = {"hunter":4.2,"flanker":4.8,"bulwark":5.8,"harasser":3.6}.get(role,4.2)
	if str(f.archetype) == "anvil": cycle = 6.2
	elif str(f.archetype) == "reaper": cycle = 4.7
	var maturity: float = clampf((time-35.0)/325.0,0.0,1.0)
	cycle *= lerpf(1.0,0.84,maturity)
	var clock: float = time+float(f.role_phase)
	return {"cycle":floori(clock/cycle),"phase":fposmod(clock,cycle)/cycle,"maturity":maturity}

static func _committed_direction(f: Dictionary, player: Dictionary, time: float) -> Vector2:
	var pos: Vector2 = f.pos
	var offset: Vector2 = Vector2(player.pos)-pos
	var distance: float = offset.length()
	var toward: Vector2 = offset.normalized()
	var side_sign: float = 1.0 if int(f.entity_id)%2 == 0 else -1.0
	var side: Vector2 = toward.orthogonal()*side_sign
	var beat: Dictionary = _attack_beat(f,time)
	var phase: float = beat.phase
	var setup_end: float = 0.30 if str(f.role) == "bulwark" else (0.34 if str(f.role) == "flanker" else 0.22)
	var commit_end: float = 0.82 if str(f.role) == "bulwark" else (0.78 if str(f.role) == "flanker" else 0.70)
	if str(f.archetype) == "anvil": setup_end = 0.34; commit_end = 0.88
	elif str(f.archetype) == "reaper": setup_end = 0.25; commit_end = 0.82
	var desired: Vector2
	if phase < setup_end:
		f["role_attack_state"] = "set_up"
		# Build a short run-up from a real, reachable lane. Adjacent hostile IDs
		# use different radial sectors; only the observed present position is read.
		var lane: float = float(int(f.entity_id)%8)*TAU/8.0+side_sign*0.12
		var radius: float = 88.0 if str(f.role) == "bulwark" else 72.0
		var staging: Vector2 = Vector2(player.pos).limit_length(72.0)+Vector2.RIGHT.rotated(lane)*radius
		staging = staging.limit_length(137.0)
		var lane_direction: Vector2 = (staging-pos).normalized()
		# Hunters still chase between commitments; specialists occupy their flank.
		if str(f.role) == "hunter": desired = toward*0.74+side*0.22 if distance > 52.0 else -toward*0.76+side*0.34
		else: desired = lane_direction*0.94
	elif phase < commit_end:
		f["role_attack_state"] = "committed"
		if int(f.get("role_commit_cycle",-1)) != int(beat.cycle):
			# One imperfect sampled heading per strike. Once committed it cannot
			# swivel to follow dodges or reverse onto the player after crossing them.
			var lead: Vector2 = (Vector2(player.vel)*0.14).limit_length(22.0)
			var error: Vector2 = Vector2(sin(float(f.entity_id)*2.17+float(beat.cycle)*1.31),cos(float(f.entity_id)*1.43+float(beat.cycle)*1.77))*5.0
			f["role_commit_heading"] = (offset+lead+error).normalized()
			f["role_commit_cycle"] = int(beat.cycle)
			desired = Vector2(f.role_commit_heading)*0.95
		else: desired = Vector2(f.role_commit_heading)*0.95
	else:
		f["role_attack_state"] = "recover"
		# Pull out far enough to gain momentum again; do not pin a fortress at
		# low speed forever. Recovery windows remain real openings for the player.
		desired = -toward*0.68+side*0.52 if distance < 78.0 else toward*0.54+side*0.38
	var edge: float = maxf(pos.length(),absf(pos.x-pos.y)*0.75)
	if edge > 145.0 and desired.dot(pos) > 0.0:
		desired = desired.lerp(-pos.normalized(),clampf((edge-145.0)/35.0,0.0,0.96))
	return desired.limit_length(0.95)

static func wants_burst(f: Dictionary, target: Dictionary, time: float) -> bool:
	var distance: float = Vector2(f.pos).distance_to(target.pos)
	if Vector2(f.pos).length() > 143.0: return false
	if time >= 35.0:
		var beat: Dictionary = _attack_beat(f,time)
		if str(f.get("role_attack_state","")) != "committed": return false
		var heading: Vector2 = Vector2(f.get("role_commit_heading",Vector2.ZERO))
		var toward: Vector2 = (Vector2(target.pos)-Vector2(f.pos)).normalized()
		# Burst only into the sampled strike corridor, never while retreating or
		# after a successful dodge has already put the target behind the attacker.
		return float(beat.phase) < 0.66 and distance >= 28.0 and distance < (126.0 if str(f.role) == "bulwark" else 112.0) and heading.dot(toward) > 0.72
	if f.archetype == "anvil": return fmod(time+float(f.role_phase),6.0) > 4.8 and distance < 110.0
	if f.archetype == "reaper": return fmod(time+float(f.role_phase),5.0) > 3.5 and distance < 115.0
	match str(f.role):
		"bulwark": return false
		"flanker": return distance > 65.0 and distance < 105.0
		"harasser": return distance < 80.0 and fmod(time+float(f.role_phase),5.0) < 1.6
	return distance < 105.0
