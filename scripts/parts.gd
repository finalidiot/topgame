extends RefCounted
class_name PartCatalog

## Stable IDs remain the save protocol. Definitions are runtime content, never
## ownership: extending this catalogue cannot grant a component to a save.
const DATA_PATH: String = "res://assets/data/parts_catalogue.json"
const BLADE_IDS: Array[String] = ["balance", "smash", "guard", "hook", "hammerfall", "sawtooth", "puck", "outrigger", "lopsider", "crescent", "fork"]
const RATCHET_IDS: Array[String] = ["low", "mid", "high", "ballast", "flex", "kickback", "offset", "flywheel", "scrap"]
const BIT_IDS: Array[String] = ["needle", "ball", "flat", "rubber", "skate", "claw", "freewheel", "eccentric", "chisel", "tripod", "groove"]
const RARITIES: Array[String] = ["TRASH", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]
const STAT_IDS: Array[String] = ["power", "stamina", "grip", "speed", "stability", "mass"]
const DEFAULT_BUILD: Dictionary = {"blade": "balance", "ratchet": "mid", "bit": "ball"}
const Physical = preload("res://scripts/part_physics.gd")
static var PARTS: Dictionary = _load_definitions()

static func _load_definitions() -> Dictionary:
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	assert(decoded is Dictionary and int(decoded.get("schema_version", 0)) == 1, "Invalid part catalogue content")
	return decoded["categories"]

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

static func derive_physics(build: Dictionary) -> Dictionary:
	var clean: Dictionary = validate_build(build)
	var definitions: Array[Dictionary] = []
	for category: String in ["blade", "ratchet", "bit"]:
		definitions.append(PARTS[category][clean[category]])
	return Physical.assemble(definitions)

static func title(build: Dictionary) -> String:
	var clean: Dictionary = validate_build(build)
	return "%s / %s / %s" % [PARTS.blade[clean.blade].name, PARTS.ratchet[clean.ratchet].name, PARTS.bit[clean.bit].name]

static func texture_path(category: String, id: String) -> String:
	if PARTS.has(category) and PARTS[category].has(id): return str(PARTS[category][id].visual.sprite)
	var folder: String = {"blade": "blades", "ratchet": "ratchets", "bit": "bits"}.get(category, "blades")
	return "res://assets/top/parts/%s/%s.png" % [folder, id]

static func description(category: String, id: String) -> String:
	return str(PARTS.get(category, {}).get(id, {}).get("description", ""))

static func rarity(category: String, id: String) -> String:
	return str(PARTS.get(category, {}).get(id, {}).get("rarity", "COMMON"))

static func visual_height(build: Dictionary) -> float:
	var clean: Dictionary = validate_build(build)
	return float(PARTS.ratchet[clean.ratchet].physics.get("visual_height", 0.0))

static func all_builds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for blade: String in BLADE_IDS:
		for ratchet: String in RATCHET_IDS:
			for bit: String in BIT_IDS:
				result.append({"blade": blade, "ratchet": ratchet, "bit": bit})
	return result
