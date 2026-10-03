extends RefCounted
class_name PartCatalog

## One rig, forty-eight combinations. Values are readable garage ratings;
## battle.gd converts them into physical coefficients in world u/v space.
const BLADE_IDS: Array[String] = ["balance", "smash", "guard", "hook"]
const RATCHET_IDS: Array[String] = ["low", "mid", "high"]
const BIT_IDS: Array[String] = ["needle", "ball", "flat", "rubber"]
const STAT_IDS: Array[String] = ["power", "stamina", "grip", "speed", "stability", "mass"]
const DEFAULT_BUILD: Dictionary = {"blade": "balance", "ratchet": "mid", "bit": "ball"}

const PARTS: Dictionary = {
	"blade": {
		"balance": {"name": "BALANCE", "description": "A steady all-rounder. Enough punch to attack; enough reserve to recover.", "stats": {"mass": 6.0, "power": 6.0, "stamina": 6.0, "grip": 5.0, "speed": 6.0, "stability": 6.0}},
		"smash": {"name": "SMASH", "description": "Heavy impact lobes turn clean approaches into strong knockback. Spend your spin wisely.", "stats": {"mass": 8.0, "power": 9.0, "stamina": 4.0, "grip": 4.0, "speed": 6.0, "stability": 4.0}},
		"guard": {"name": "GUARD", "description": "A heavy closed ring that resists impact and preserves spin. Slower to chase a fleeing rival.", "stats": {"mass": 9.0, "power": 4.0, "stamina": 8.0, "grip": 5.0, "speed": 3.0, "stability": 8.0}},
		"hook": {"name": "HOOK", "description": "Fast, asymmetric contact edges reward glancing attacks. Keep moving to protect your balance.", "stats": {"mass": 5.0, "power": 8.0, "stamina": 5.0, "grip": 5.0, "speed": 7.0, "stability": 5.0}}
	},
	"ratchet": {
		"low": {"name": "LOW", "description": "A planted stance. Extra stability and reserve, with slightly less pace.", "stats": {"mass": 0.2, "power": 0.0, "stamina": 0.4, "grip": 0.2, "speed": -0.3, "stability": 1.2}},
		"mid": {"name": "MID", "description": "The shared starter stance. Predictable contact height and balanced handling.", "stats": {"mass": 0.0, "power": 0.0, "stamina": 0.0, "grip": 0.0, "speed": 0.0, "stability": 0.0}},
		"high": {"name": "HIGH", "description": "Raises the blade for stronger contact. Extra reach trades away wobble resistance.", "stats": {"mass": 0.5, "power": 1.0, "stamina": -0.4, "grip": 0.0, "speed": 0.3, "stability": -1.2}}
	},
	"bit": {
		"needle": {"name": "NEEDLE", "description": "Efficient point contact keeps spin alive. Gentle steering, loose grip and a narrow recovery margin.", "stats": {"mass": -0.3, "power": -0.4, "stamina": 1.6, "grip": -2.3, "speed": -1.0, "stability": -0.7}},
		"ball": {"name": "BALL", "description": "Rounded contact rolls smoothly through the dish. Forgiving handling and a little extra reserve.", "stats": {"mass": 0.0, "power": 0.0, "stamina": 0.3, "grip": 0.0, "speed": 0.0, "stability": 0.5}},
		"flat": {"name": "FLAT", "description": "Broad contact runs fast and hits hard. Burns reserve quickly during a long chase.", "stats": {"mass": 0.2, "power": 0.6, "stamina": -1.5, "grip": 0.8, "speed": 2.0, "stability": -0.4}},
		"rubber": {"name": "RUBBER", "description": "Strong grip delivers responsive turns and controlled braking. The price is higher spin loss.", "stats": {"mass": 0.3, "power": 0.4, "stamina": -1.2, "grip": 2.0, "speed": 0.8, "stability": 1.0}}
	}
}

static func validate_build(build: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for category: String in ["blade", "ratchet", "bit"]:
		var candidate: String = str(build.get(category, DEFAULT_BUILD[category]))
		var choices: Dictionary = PARTS[category]
		result[category] = candidate if choices.has(candidate) else DEFAULT_BUILD[category]
	return result

static func derive(build: Dictionary) -> Dictionary:
	var clean: Dictionary = validate_build(build)
	var result: Dictionary = {}
	var blade: Dictionary = PARTS["blade"][clean["blade"]]["stats"]
	var ratchet: Dictionary = PARTS["ratchet"][clean["ratchet"]]["stats"]
	var bit: Dictionary = PARTS["bit"][clean["bit"]]["stats"]
	for stat: String in STAT_IDS:
		result[stat] = clampf(float(blade[stat]) + float(ratchet[stat]) + float(bit[stat]), 1.0, 10.0)
	return result

static func title(build: Dictionary) -> String:
	var clean: Dictionary = validate_build(build)
	return "%s / %s / %s" % [str(clean["blade"]).to_upper(), str(clean["ratchet"]).to_upper(), str(clean["bit"]).to_upper()]

static func texture_path(category: String, id: String) -> String:
	var folder: String = {"blade": "blades", "ratchet": "ratchets", "bit": "bits"}.get(category, "blades")
	return "res://assets/top/parts/%s/%s.png" % [folder, id]

static func description(category: String, id: String) -> String:
	if not PARTS.has(category):
		return ""
	var options: Dictionary = PARTS[category]
	if not options.has(id):
		return ""
	return str(options[id]["description"])

static func all_builds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for blade: String in BLADE_IDS:
		for ratchet: String in RATCHET_IDS:
			for bit: String in BIT_IDS:
				result.append({"blade": blade, "ratchet": ratchet, "bit": bit})
	return result
