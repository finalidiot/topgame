extends RefCounted
class_name PacketEconomy
## Pure, data-driven packet sampling. UI odds use this exact algorithm's pools.
const Catalog = preload("res://scripts/parts.gd")
const DATA_PATH: String = "res://assets/data/packet_economy.json"
const CATEGORIES: Array[String] = ["blade", "ratchet", "bit"]
static var _config: Dictionary = _load_config()

static func _load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return value if value is Dictionary else {}

static func config() -> Dictionary:
	return _config.duplicate(true)

static func packet_cost(kind: String) -> int:
	if not validate_config().is_empty(): return 0
	return int(_config.packets.get(kind, {}).get("cost", 0))

static func packet_name(kind: String) -> String:
	if not validate_config().is_empty(): return ""
	return str(_config.packets.get(kind, {}).get("name", ""))

static func validate_config() -> Array[String]:
	var errors: Array[String] = []
	var schema: Variant = _config.get("schema_version", null)
	if not (schema is int or schema is float) or float(schema) != 1.0: errors.append("Unsupported economy schema")
	if _config.get("categories", []) != ["blade", "ratchet", "bit"]: errors.append("Packet categories must match three physical slots")
	if str(_config.get("guarantee_min_rarity", "")) != "UNCOMMON": errors.append("Unsupported guarantee minimum")
	if _config.get("max_balance", null) != 1000000000: errors.append("Unsupported wallet bound")
	for key: String in ["rarity_weights", "duplicate_salvage"]:
		if not _config.get(key, null) is Dictionary:
			errors.append("Missing " + key)
			continue
		for rarity: String in Catalog.RARITIES:
			var value: Variant = _config[key].get(rarity, null)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) <= 0 or float(value) > 1000000:
				errors.append("Invalid " + key + "/" + rarity)
	var products: Variant = _config.get("packets", null)
	if not products is Dictionary:
		errors.append("Missing packet products")
		return errors
	for kind: String in ["standard", "reclaimed"]:
		var product: Variant = products.get(kind, null)
		if not product is Dictionary:
			errors.append("Missing packet product " + kind)
			continue
		var cost: Variant = product.get("cost", null)
		if not (cost is int or cost is float) or not is_finite(float(cost)) or float(cost) != floorf(float(cost)) or float(cost) <= 0 or float(cost) > 1000000000: errors.append("Invalid packet cost")
		if product.get("currency", "") != ("credits" if kind == "standard" else "salvage"): errors.append("Invalid packet currency")
	var reward: Variant = _config.get("reward", null)
	if not reward is Dictionary:
		errors.append("Missing reward model")
	else:
		for key: String in ["threat_clear", "elite_clear", "boss_clear", "max_run_payout"]:
			var value: Variant = reward.get(key, null)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) <= 0 or float(value) > 1000000: errors.append("Invalid reward model")
	return errors

static func eligible_ids(category: String = "") -> Array[String]:
	var result: Array[String] = []
	for cat: String in CATEGORIES:
		if not category.is_empty() and category != cat: continue
		for id: String in Catalog.PARTS[cat]:
			if bool(Catalog.PARTS[cat][id].get("pack_eligible", false)):
				result.append(cat + ":" + id)
	return result

static func _pool(category: String, high: bool = false, unowned: bool = false, ownership: Array = []) -> Dictionary:
	var pool: Dictionary = {}
	var minimum: int = Catalog.RARITIES.find(str(_config.guarantee_min_rarity)) if high else 0
	for id: String in Catalog.PARTS[category]:
		var row: Dictionary = Catalog.PARTS[category][id]
		if not bool(row.get("pack_eligible", false)) or (unowned and category + ":" + id in ownership): continue
		var rarity: String = str(row.rarity)
		if Catalog.RARITIES.find(rarity) < minimum or float(_config.rarity_weights.get(rarity, 0)) <= 0: continue
		if not pool.has(rarity): pool[rarity] = []
		pool[rarity].append(id)
	return pool

static func _probabilities(pool: Dictionary) -> Dictionary:
	var total: float = 0.0
	for rarity: String in pool: total += float(_config.rarity_weights[rarity])
	var result: Dictionary = {}
	for rarity: String in Catalog.RARITIES:
		result[rarity] = float(_config.rarity_weights[rarity]) / total if pool.has(rarity) and total > 0 else 0.0
	return result

static func _draw(pool: Dictionary, rng: RandomNumberGenerator) -> String:
	var total: float = 0.0
	for rarity: String in pool: total += float(_config.rarity_weights[rarity])
	var roll: float = rng.randf() * total
	for rarity: String in pool:
		roll -= float(_config.rarity_weights[rarity])
		if roll < 0:
			return str(pool[rarity][rng.randi_range(0, pool[rarity].size() - 1)])
	# Floating-point boundary only, never an unavailable-rarity fallback.
	var ids: Array = pool.values().back()
	return str(ids[rng.randi_range(0, ids.size() - 1)])

static func _plans(kind: String, ownership: Array) -> Array[Dictionary]:
	if not _config.packets.has(kind): return []
	var high_categories: Array[String] = []
	var new_categories: Array[String] = []
	for category: String in CATEGORIES:
		if _pool(category).is_empty(): return []
		if not _pool(category, true).is_empty(): high_categories.append(category)
		if not _pool(category, false, true, ownership).is_empty(): new_categories.append(category)
	if high_categories.is_empty(): return []
	var plans: Array[Dictionary] = []
	if kind == "reclaimed" and not new_categories.is_empty():
		for fresh: String in new_categories:
			var other_high: Array[String] = []
			for category: String in high_categories:
				if category != fresh: other_high.append(category)
			# A future catalogue with only one high category remains feasible if
			# its unowned pool itself supplies the Uncommon+ guarantee.
			if other_high.is_empty():
				if _pool(fresh, true, true, ownership).is_empty(): return []
				plans.append({"fresh":fresh, "high":fresh, "probability":1.0 / new_categories.size()})
			else:
				for high: String in other_high:
					plans.append({"fresh":fresh, "high":high, "probability":1.0 / new_categories.size() / other_high.size()})
	else:
		for high: String in high_categories: plans.append({"fresh":"", "high":high, "probability":1.0 / high_categories.size()})
	return plans

static func generate(kind: String, ownership: Array, rng: RandomNumberGenerator = null) -> Dictionary:
	if not validate_config().is_empty(): return {"ok":false,"status":"invalid_economy"}
	var plans: Array[Dictionary] = _plans(kind, ownership)
	if plans.is_empty(): return {"ok":false, "status":"unavailable_pool"}
	var source: RandomNumberGenerator = rng
	if source == null:
		source = RandomNumberGenerator.new()
		source.randomize()
	var roll: float = source.randf()
	var selected: Dictionary = plans.back()
	for plan: Dictionary in plans:
		roll -= float(plan.probability)
		if roll < 0: selected = plan; break
	var rows: Array[Dictionary] = []
	var salvage_total: int = 0
	for category: String in CATEGORIES:
		var id: String = _draw(_pool(category, category == selected.high, category == selected.fresh, ownership), source)
		var qualified: String = category + ":" + id
		var rarity: String = Catalog.rarity(category, id)
		var fresh: bool = qualified not in ownership
		var salvage: int = 0 if fresh else int(_config.duplicate_salvage[rarity])
		salvage_total += salvage
		rows.append({"category":category, "id":id, "part_id":qualified, "rarity":rarity, "new":fresh, "salvage":salvage})
	return {"ok":true, "status":"generated", "rows":rows, "total_salvage":salvage_total}

static func rarity_odds(kind: String = "standard", ownership: Array = []) -> Dictionary:
	if not validate_config().is_empty(): return {"kind":kind,"categories":{},"error":"invalid_economy"}
	var result: Dictionary = {"kind":kind, "categories":{}, "rarity_weights":_config.rarity_weights.duplicate(true),
		"guarantee":str(_config.guarantee_min_rarity) + "+", "new_guarantee":kind == "reclaimed" and not _unowned_ids(ownership).is_empty(),
		"rules":_config.rules.get(kind, ""), "missing_rarity_rule":_config.rules.missing_rarity}
	var plans: Array[Dictionary] = _plans(kind, ownership)
	for category: String in CATEGORIES:
		var odds: Dictionary = {}
		for rarity: String in Catalog.RARITIES: odds[rarity] = 0.0
		for plan: Dictionary in plans:
			var probabilities: Dictionary = _probabilities(_pool(category, category == plan.high, category == plan.fresh, ownership))
			for rarity: String in Catalog.RARITIES: odds[rarity] += float(plan.probability) * float(probabilities[rarity])
		result.categories[category] = odds
	return result

static func _unowned_ids(ownership: Array) -> Array[String]:
	var result: Array[String] = []
	for id: String in eligible_ids():
		if id not in ownership: result.append(id)
	return result

static func run_reward(outcome: Dictionary) -> Dictionary:
	var zero: Dictionary = {"credits":0, "breakdown":{"threats":0,"elites":0,"bosses":0}, "eligible":false}
	if not validate_config().is_empty(): return zero
	if str(outcome.get("reward_provenance", "")) != "earned-clear-v1" or bool(outcome.get("reward_fixture", true)) or bool(outcome.get("aborted", false)): return zero
	var counts: Array[int] = []
	for key: String in ["earned_threats_cleared", "earned_elites_cleared", "earned_bosses_cleared"]:
		var value: Variant = outcome.get(key, -1)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) < 0 or float(value) > 1000000: return zero
		counts.append(int(value))
	if counts[1] + counts[2] > counts[0]: return zero
	var reward: Dictionary = _config.reward
	var breakdown: Dictionary = {"threats":counts[0] * int(reward.threat_clear), "elites":counts[1] * int(reward.elite_clear), "bosses":counts[2] * int(reward.boss_clear)}
	return {"credits":mini(int(reward.max_run_payout), int(breakdown.threats) + int(breakdown.elites) + int(breakdown.bosses)), "breakdown":breakdown, "eligible":true}
