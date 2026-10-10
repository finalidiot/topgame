extends RefCounted
## Authored ownership only. Pilots activate the ordinary movement/Burst/Brake
## hooks; no package supplies reserve, hidden damage or scripted outcomes.
const Catalog = preload("res://scripts/run_powers.gd")
const PACKAGES: Dictionary = {
	"hunter":["redline","momentum_bank"],
	"bulwark":["dead_centre","impact_sink"],
	"flanker":["orbit_drive","afterimage"],
	"harasser":["high_gear","afterimage"],
	"hotwire":["redline","momentum_bank","predator_line"],
	"ballast":["dead_centre","impact_sink","anchor_exchange"],
	"anvil":["dead_centre","impact_sink","anchor_exchange","crash_guard"],
	"reaper":["afterimage","orbit_drive","high_gear","crosscut"]
}

static func for_event(event: Dictionary) -> Dictionary:
	if str(event.get("kind","rival")) == "swarm": return {"ids":[],"ranks":{},"mutations":{},"identity":"ammunition"}
	var tier: int = maxi(0,int(event.get("tier_at_entry",0)))
	var kind: String = str(event.get("kind","rival"))
	var identity: String = str(event.get("key",event.get("role","hunter")))
	var source: Array = PACKAGES.get(identity,PACKAGES.get(event.get("role","hunter"),PACKAGES.hunter))
	var count: int = 0 if tier == 0 else (1 if tier == 1 else 2)
	if kind in ["elite","boss"]: count = source.size()
	var ids: Array[String] = []
	var ranks: Dictionary = {}
	var mutations: Dictionary = {}
	for index: int in range(mini(count,source.size())):
		var id: String = str(source[index])
		assert(id in Catalog.ACTIVE_IDS)
		ids.append(id)
		ranks[id] = 2 if kind in ["elite","boss"] or tier >= 4 else 1
	# Signature mutations use the same authored legal rank-three branches.
	if identity == "hotwire" or (identity == "hunter" and tier >= 5):
		ranks["redline"] = 3; mutations["redline"] = "breakneck"
	elif identity == "anvil":
		ranks["dead_centre"] = 3; mutations["dead_centre"] = "counterweight"
	elif identity == "reaper":
		ranks["afterimage"] = 3; mutations["afterimage"] = "ghost_circuit"
	# Only the fortress specialist receives the new automatic severe-hit
	# response. Ordinary packages and their accepted piloting stay unchanged.
	if identity == "anvil" and kind in ["elite","boss"] and "crash_guard" in ids:
		ranks["crash_guard"] = 3; mutations["crash_guard"] = "sacrificial_damper"
	return {"ids":ids,"ranks":ranks,"mutations":mutations,"identity":identity}

static func apply(fighter: Dictionary, event: Dictionary) -> void:
	var package: Dictionary = for_event(event)
	fighter.powers = package.ids.duplicate()
	fighter.power_ranks = package.ranks.duplicate(true)
	fighter.power_mutations = package.mutations.duplicate(true)
	fighter["enemy_power_package"] = package.identity
