extends RefCounted
class_name StarterCatalog
## Real assemblies plus authored Run-only handling profiles. Garage/Quick Duel
## remain the unmodified physical part catalogue.

const Parts = preload("res://scripts/parts.gd")
const IDS: Array[String] = ["breaker", "bastion", "vane"]
const HANDLING: Dictionary = {
	"breaker":{"acceleration":1.32,"speed":1.20,"mass":1.0,"impact":1.30,"spin_drain":1.0,"orbit":1.5,"bank":0.85,"recovery":1.0},
	# Guard / Low / Ball already provide stamina. Keep fortress weight and
	# recovery, but spend the normal reserve cost instead of a free 10% discount.
	"bastion":{"acceleration":0.72,"speed":0.78,"mass":1.35,"impact":1.0,"spin_drain":1.0,"orbit":0.25,"bank":1.35,"recovery":1.3},
	"vane":{"acceleration":1.18,"speed":1.12,"mass":0.94,"impact":1.05,"spin_drain":0.82,"orbit":1.6,"bank":1.0,"recovery":1.15}
}
const DEFINITIONS: Dictionary = {
	"breaker": {
		"id":"breaker", "name":"BREAKER", "role":"AGGRESSION / IMPACT / SPEED", "accent":Color("ee765e"),
		"tagline":"FAST. VIOLENT. BURNS HOT.", "strengths":"Hard hits. Wide attacking lines.", "weakness":"Burns spin. Risky recovery.",
		"assembly":{"blade":"smash", "ratchet":"high", "bit":"flat"}, "motion":"restless"
	},
	"bastion": {
		"id":"bastion", "name":"BASTION", "role":"DEFENCE / CONTROL / STABILITY", "accent":Color("64b6f4"),
		"tagline":"HEAVY. STABLE. HARD TO MOVE.", "strengths":"Holds centre. Forgives mistakes.", "weakness":"Slow to chase. Less explosive.",
		"assembly":{"blade":"guard", "ratchet":"low", "bit":"ball"}, "motion":"anchored"
	},
	"vane": {
		"id":"vane", "name":"VANE", "role":"TECHNIQUE / MOBILITY / GRIP", "accent":Color("83d89a"),
		"tagline":"MOBILE. EFFICIENT. HARD TO PIN DOWN.", "strengths":"Clean turns. Glancing attacks.", "weakness":"Grip spends spin. Less planted.",
		"assembly":{"blade":"hook", "ratchet":"mid", "bit":"rubber"}, "motion":"orbiting"
	}
}

static func get_starter(starter_id: String) -> Dictionary:
	var entry: Dictionary = DEFINITIONS.get(starter_id, {}).duplicate(true)
	if not entry.is_empty(): entry["stats"] = Parts.derive(entry.assembly)
	return entry

static func build_for(starter_id: String) -> Dictionary:
	return get_starter(starter_id).get("assembly", Parts.DEFAULT_BUILD).duplicate(true)

static func display_name(starter_id: String) -> String:
	return str(DEFINITIONS.get(starter_id, {}).get("name", "CUSTOM"))

## Current components determine Run identity. The saved first starter records
## ownership history, not a permanent class. Exact authored assemblies retain
## their prototype handling; mixed builds use the physical part catalogue.
static func identity_for_build(build: Dictionary) -> String:
	for id: String in IDS:
		if build == build_for(id): return id
	return "custom"
