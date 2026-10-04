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
	f["role_phase"] = float(int(f.entity_id)%4)*0.7
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
	var pos: Vector2 = f.pos
	var offset: Vector2 = Vector2(player.pos)-pos
	var distance: float = offset.length()
	var toward: Vector2 = offset.normalized()
	var side: Vector2 = toward.orthogonal() * (1.0 if int(f.entity_id)%2 == 0 else -1.0)
	var phase: float = fmod(time+float(f.role_phase),5.0)
	var desired: Vector2 = toward
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

static func wants_burst(f: Dictionary, target: Dictionary, time: float) -> bool:
	var distance: float = Vector2(f.pos).distance_to(target.pos)
	if Vector2(f.pos).length() > 143.0: return false
	if f.archetype == "anvil": return fmod(time+float(f.role_phase),6.0) > 4.8 and distance < 110.0
	if f.archetype == "reaper": return fmod(time+float(f.role_phase),5.0) > 3.5 and distance < 115.0
	match str(f.role):
		"bulwark": return false
		"flanker": return distance > 65.0 and distance < 105.0
		"harasser": return distance < 80.0 and fmod(time+float(f.role_phase),5.0) < 1.6
	return distance < 105.0
