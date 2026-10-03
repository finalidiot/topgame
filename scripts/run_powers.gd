extends RefCounted
class_name RunPowerCatalog

## Catalogue identity stays stable as the implemented draft pool grows.
## Physical Blade / Ratchet / Bit ratings remain exclusively in parts.gd.
const IDS: Array[String] = [
	"impact_wake", "second_wind", "redline", "iron_comet", "dead_centre", "afterimage",
	"reversal", "chain_impact", "slip_gear", "rim_runner", "flywheel_cache", "crosscut"
]
const ACTIVE_IDS: Array[String] = ["impact_wake", "second_wind", "redline", "iron_comet", "afterimage", "chain_impact"]
const ICON_SHEET: String = "res://assets/powers/icons.png"
const CONDITIONS: Dictionary = {
	"impact_wake":"Heavy contact / 1.25 s cooldown",
	"second_wind":"Low spin or severe wobble / once per battle",
	"redline":"Burst at 35%+ spin / extra spin cost",
	"iron_comet":"Hard wall rebound / spend within 2 s",
	"afterimage":"High speed / each trace spends spin",
	"chain_impact":"Credited eliminations / heavy hit then Burst"
}
const DEFINITIONS: Dictionary = {
	"impact_wake": {"id":"impact_wake", "name":"Impact Wake", "description":"Heavy contacts send a pressure ring through nearby tops.", "short_label":"WAKE", "tags":["impact"], "icon":"", "active":true},
	"second_wind": {"id":"second_wind", "name":"Second Wind", "description":"Once each battle, near spin-out triggers a dramatic recovery.", "short_label":"WIND", "tags":["recovery"], "icon":"", "active":true},
	"redline": {"id":"redline", "name":"Redline", "description":"Burst drives beyond safe spin, then leaves you unstable.", "short_label":"RED", "tags":["burst", "risk"], "icon":"", "active":true},
	"iron_comet": {"id":"iron_comet", "name":"Iron Comet", "description":"A hard wall rebound charges your next real hit.", "short_label":"COMET", "tags":["wall", "impact"], "icon":"", "active":true},
	"dead_centre": {"id":"dead_centre", "name":"Dead Centre", "description":"Holding the centre builds an anchor that heavy hits can break.", "short_label":"CENTRE", "tags":["position"], "icon":"", "active":false},
	"afterimage": {"id":"afterimage", "name":"Afterimage", "description":"Fast movement leaves brief physical pressure traces.", "short_label":"ECHO", "tags":["mobility"], "icon":"", "active":true},
	"reversal": {"id":"reversal", "name":"Reversal", "description":"Brake after a hard unstable hit to turn recoil into recovery.", "short_label":"REV", "tags":["brake", "recovery"], "icon":"", "active":false},
	"chain_impact": {"id":"chain_impact", "name":"Chain Impact", "description":"Thrown tops chain pressure pulses; heavy duel hits prime a Burst follow-through.", "short_label":"CHAIN", "tags":["impact", "burst"], "icon":"", "active":true},
	"slip_gear": {"id":"slip_gear", "name":"Slip Gear", "description":"Brake, turn, then Burst to release stored momentum.", "short_label":"SLIP", "tags":["brake", "mobility"], "icon":"", "active":false},
	"rim_runner": {"id":"rim_runner", "name":"Rim Runner", "description":"Brake along a solid wall to ride its edge and choose your exit.", "short_label":"RIM", "tags":["brake", "wall"], "icon":"", "active":false},
	"flywheel_cache": {"id":"flywheel_cache", "name":"Flywheel Cache", "description":"Bank a little early spin and release it when reserve gets low.", "short_label":"CACHE", "tags":["reserve", "recovery"], "icon":"", "active":false},
	"crosscut": {"id":"crosscut", "name":"Crosscut", "description":"Steering through a glancing hit spends spin for a sideways shear.", "short_label":"CUT", "tags":["impact", "mobility"], "icon":"", "active":false}
}

static func get_power(power_id: String) -> Dictionary:
	var power: Dictionary = DEFINITIONS.get(power_id, {}).duplicate(true)
	if power.is_empty(): return power
	power.active = power_id in ACTIVE_IDS
	power.icon = ICON_SHEET if power.active else ""
	power["icon_frame"] = ACTIVE_IDS.find(power_id)
	power["condition"] = CONDITIONS.get(power_id, "")
	return power

static func display_names(power_ids: Array) -> Array[String]:
	var names: Array[String] = []
	for power_id: String in power_ids:
		if DEFINITIONS.has(power_id): names.append(str(DEFINITIONS[power_id].name))
	return names
