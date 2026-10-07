extends SceneTree
## The real packet sampler drives both contracts and deterministic progression.
const Economy = preload("res://scripts/packet_economy.gd")
const Catalog = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: int = 0
var report_path: String = ""
var cohort: int = 3000
var report: Dictionary = {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		elif arg.begins_with("--cohort="): cohort = clampi(int(arg.trim_prefix("--cohort=")), 100, 10000)
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	_contracts()
	_randomness()
	_progression()
	report.checks = checks
	report.failures = failures
	report.status = "passed" if failures == 0 else "failed"
	if not report_path.is_empty():
		check(report_path.is_absolute_path() and not FileAccess.file_exists(report_path), "External evidence path is new and absolute")
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
		else: check(false, "Evidence file opens")
	print("PACKET_ECONOMY_%s checks=%d failures=%d cohort=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures, cohort])
	quit(1 if failures else 0)

func _contract_packet(packet: Dictionary, owned: Array, reclaimed: bool) -> void:
	check(bool(packet.ok), "Valid sampler returns a packet")
	check(packet.rows.size() == 3, "Exact three physical parts")
	var high: int = 0
	var fresh: int = 0
	var total: int = 0
	for index: int in range(3):
		var row: Dictionary = packet.rows[index]
		check(str(row.category) == Economy.CATEGORIES[index], "Exactly one component per category in fixed order")
		check(str(row.part_id) in Economy.eligible_ids(), "No ineligible content appears")
		check(bool(row.new) == (str(row.part_id) not in owned), "NEW reports actual ownership")
		if Catalog.RARITIES.find(str(row.rarity)) >= 2: high += 1
		if bool(row.new): fresh += 1
		total += int(row.salvage)
	check(high >= 1, "Uncommon+ guarantee always honored")
	check(total == int(packet.total_salvage), "Conversion total matches visible rows")
	if reclaimed and owned.size() < Economy.eligible_ids().size(): check(fresh >= 1, "Reclaimed guarantees collection progress")

func _contracts() -> void:
	check(Economy.eligible_ids().size() == 31, "All current ordinary catalogue parts are eligible")
	var config: Dictionary = Economy.config()
	check(config.currency_name == "CREDITS" and config.salvage_name == "SALVAGE", "Grounded currency names avoid SCRAP part collision")
	var maxima: int = 0
	for category: String in Economy.CATEGORIES:
		var maximum: int = 0
		for id: String in Catalog.PARTS[category]:
			maximum = maxi(maximum, int(config.duplicate_salvage[Catalog.rarity(category, id)]))
		maxima += maximum
	check(Economy.packet_cost("reclaimed") > maxima, "Reclaimed cost exceeds even worst eligible duplicate packet")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 003001
	for missing: String in Economy.eligible_ids():
		var owned: Array[String] = Economy.eligible_ids()
		owned.erase(missing)
		for attempt: int in range(8):
			var packet: Dictionary = Economy.generate("reclaimed", owned, rng)
			_contract_packet(packet, owned, true)
			check(packet.rows.any(func(row: Dictionary) -> bool: return str(row.part_id) == missing), "Every final missing part is guaranteed, including Legendary")
	_contract_packet(Economy.generate("reclaimed", Economy.eligible_ids(), rng), Economy.eligible_ids(), true)
	check(not Economy.generate("unknown", [], rng).ok, "Unknown product refuses rather than falling back")
	# Add a future signature ID to the actual catalogue and prove exclusion.
	Catalog.PARTS.blade["future_signature"] = {"rarity":"LEGENDARY","pack_eligible":false,"acquisition_source":"boss_signature"}
	check("blade:future_signature" not in Economy.eligible_ids(), "Future signature parts explicitly excluded")
	for sample: int in range(100):
		check(Economy.generate("standard", [], rng).rows[0].id != "future_signature", "Ineligible future piece cannot appear")
	Catalog.PARTS.blade.erase("future_signature")
	var before: Dictionary = Catalog.PARTS.ratchet.duplicate(true)
	for id: String in Catalog.PARTS.ratchet: Catalog.PARTS.ratchet[id].pack_eligible = false
	check(not Economy.generate("standard", [], rng).ok, "Missing category refuses purchase deliberately")
	Catalog.PARTS.ratchet = before
	var first: RandomNumberGenerator = RandomNumberGenerator.new()
	var second: RandomNumberGenerator = RandomNumberGenerator.new()
	first.seed = 81173
	second.seed = 81173
	for sample: int in range(50): check(Economy.generate("standard", [], first) == Economy.generate("standard", [], second), "Injected QA seed deterministic")
	var production: Dictionary = {}
	for sample: int in range(20): production[JSON.stringify(Economy.generate("standard", []).rows)] = true
	check(production.size() > 1, "Production entropy is not accidentally a fixed QA seed")
	report.economy = config
	report.standard_odds = Economy.rarity_odds("standard")
	report.anti_loop = {"cost":Economy.packet_cost("reclaimed"), "worst_possible_salvage_return":maxima, "worst_net_return":maxima - Economy.packet_cost("reclaimed")}

func _randomness() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 73209901
	var seen: Dictionary = {}
	var rarity_count: Dictionary = {}
	var sample_count: int = 30000
	for category: String in Economy.CATEGORIES:
		rarity_count[category] = {}
		for rarity: String in Catalog.RARITIES: rarity_count[category][rarity] = 0
	for sample: int in range(sample_count):
		var packet: Dictionary = Economy.generate("standard", [], rng)
		if sample < 250: _contract_packet(packet, [], false)
		for row: Dictionary in packet.rows:
			seen[str(row.part_id)] = true
			rarity_count[row.category][row.rarity] += 1
	check(seen.size() == 31, "Every eligible part appears in substantial seeded sample")
	var expected: Dictionary = Economy.rarity_odds("standard").categories
	var observed: Dictionary = {}
	for category: String in Economy.CATEGORIES:
		observed[category] = {}
		for rarity: String in Catalog.RARITIES:
			var frequency: float = float(rarity_count[category][rarity]) / sample_count
			observed[category][rarity] = frequency
			check(absf(frequency - float(expected[category][rarity])) < 0.009, "Production-derived displayed odds match observed category frequency")
	report.randomness = {"packets":sample_count,"seed":73209901,"seen_eligible_parts":seen.size(),"observed_odds":observed,"absolute_tolerance":0.009}

func _stats(values: Array) -> Dictionary:
	values.sort()
	var sum: float = 0
	for value: Variant in values: sum += float(value)
	return {"median":values[floori((values.size()-1)*0.5)], "p75":values[floori((values.size()-1)*0.75)], "p90":values[floori((values.size()-1)*0.9)], "worst_tested":values.back(), "mean":sum / values.size()}

func _starter(index: int) -> Array[String]:
	var build: Dictionary = Starters.build_for(Starters.IDS[index % 3])
	var result: Array[String] = []
	for category: String in Economy.CATEGORIES: result.append(category + ":" + str(build[category]))
	return result

func _progression() -> void:
	var milestones: Dictionary = {"25_percent":8,"50_percent":16,"75_percent":24,"90_percent":28,"complete":31}
	var metrics: Dictionary = {}
	for key: String in milestones: metrics[key] = {"packets":[],"credits_spent":[],"duplicates":[],"salvage_earned":[],"reclaimed_used":[],"standard_used":[]}
	var early_yields: Array = []
	for player: int in range(cohort):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 3001000 + player * 7919
		var owned: Array[String] = _starter(player)
		var earned_salvage: int = 0
		var salvage: int = 0
		var duplicates: int = 0
		var standard: int = 0
		var reclaimed: int = 0
		var packets: int = 0
		var reached: Dictionary = {}
		while owned.size() < 31 and packets < 1000:
			var kind: String = "reclaimed" if salvage >= Economy.packet_cost("reclaimed") else "standard"
			if kind == "reclaimed":
				salvage -= Economy.packet_cost(kind)
				reclaimed += 1
			else: standard += 1
			var packet: Dictionary = Economy.generate(kind, owned, rng)
			var new_count: int = 0
			for row: Dictionary in packet.rows:
				if bool(row.new):
					owned.append(str(row.part_id))
					new_count += 1
				else: duplicates += 1
			if kind == "standard" and standard <= 3: early_yields.append(new_count)
			packets += 1
			salvage += int(packet.total_salvage)
			earned_salvage += int(packet.total_salvage)
			for key: String in milestones:
				if owned.size() < int(milestones[key]) or reached.has(key): continue
				reached[key] = true
				var values: Dictionary = {"packets":packets,"credits_spent":standard * Economy.packet_cost("standard"),"duplicates":duplicates,"salvage_earned":earned_salvage,"reclaimed_used":reclaimed,"standard_used":standard}
				for field: String in values: metrics[key][field].append(values[field])
		check(owned.size() == 31, "Every bounded tested cohort player completes through real sampler plus salvage")
	var distributions: Dictionary = {}
	for key: String in milestones:
		distributions[key] = {"owned_threshold":milestones[key]}
		for field: String in metrics[key]: distributions[key][field] = _stats(metrics[key][field])
	report.collection_completion = {"cohort":cohort,"seed_rule":"3001000 + player * 7919", "policy":"Cycle the three real starters; purchase reclaimed whenever affordable, otherwise standard; no other grants.", "distributions":distributions,"first_three_standard_new_yield":_stats(early_yields)}
	# Independent, shuffled ownership stages expose early/mid/late yields rather
	# than assuming a particular missing rarity at a late milestone.
	var stages: Dictionary = {}
	for owned_count: int in [3, 8, 16, 24, 28, 30, 31]:
		var totals: Dictionary = {"standard":[],"reclaimed":[]}
		var duplicate_returns: Dictionary = {"standard":[],"reclaimed":[]}
		for sample: int in range(2000):
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = 9001000 + owned_count * 100000 + sample * 53
			var shuffled: Array[String] = Economy.eligible_ids()
			for index: int in range(shuffled.size()-1, 0, -1):
				var other: int = rng.randi_range(0,index)
				var saved: String = shuffled[index]
				shuffled[index] = shuffled[other]
				shuffled[other] = saved
			var owned: Array = _starter(sample) if owned_count == 3 else shuffled.slice(0,owned_count)
			for kind: String in ["standard", "reclaimed"]:
				var packet: Dictionary = Economy.generate(kind,owned,rng)
				var fresh: int = 0
				for row: Dictionary in packet.rows:
					if bool(row.new): fresh += 1
				totals[kind].append(fresh)
				duplicate_returns[kind].append(packet.total_salvage)
		var row: Dictionary = {}
		for kind: String in totals:
			var at_least_one: int = 0
			var multiple: int = 0
			for value: int in totals[kind]:
				if value > 0: at_least_one += 1
				if value > 1: multiple += 1
			row[kind] = {"new_yield":_stats(totals[kind]),"any_new_probability":at_least_one / 2000.0,"multiple_new_probability":multiple / 2000.0,"salvage_return":_stats(duplicate_returns[kind])}
		stages[str(owned_count)] = row
		check(float(row.reclaimed.salvage_return.mean) < Economy.packet_cost("reclaimed"), "Reclaimed expected return is negative at every ownership stage")
		if owned_count < 31: check(row.reclaimed.any_new_probability == 1.0, "Reclaimed progress remains guaranteed in cohort stage")
	report.ownership_stages = {"samples_per_stage":2000,"stages":stages}
	report.anti_loop.complete_collection_expected_return = float(stages["31"].reclaimed.salvage_return.mean)
	report.anti_loop.complete_collection_expected_net = float(stages["31"].reclaimed.salvage_return.mean) - Economy.packet_cost("reclaimed")
