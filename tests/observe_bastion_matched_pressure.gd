extends "res://tests/observe_bastion_active_defence.gd"
## Supplemental synthetic Director-choice replay. Native warmup, actual physics,
## warning/safe-entry admission, cap checks, RPM and outcomes remain in use.
const NativeDirector = preload("res://scripts/threat_director.gd")
const Roles = preload("res://scripts/enemy_roles.gd")
var reference_path: String = ""
var nominal_schedule: Array[Dictionary] = []
var replay_details: Array[Dictionary] = []
var replay_runtimes: Array[RefCounted] = []

class MatchedDirector extends "res://scripts/threat_director.gd":
	var schedule: Array[Dictionary] = []
	var replay_start: float = 360.0
	var index: int = 0
	var offers: Array[Dictionary] = []
	var admissions: Array[Dictionary] = []
	var cap_wait_ticks: Dictionary = {}
	func decide(clock: float, census: Dictionary, investments: int = 1) -> Dictionary:
		if clock < replay_start: return super.decide(clock,census,investments)
		if index >= schedule.size(): return {}
		var nominal: Dictionary = schedule[index]
		if clock + 0.000001 < float(nominal.not_before): return {}
		var limit: Dictionary = limits(clock,investments)
		var reason: String = ""
		if float(census.pressure)+float(nominal.cost) > float(limit.budget)+0.000001: reason = "pressure_budget"
		elif nominal.kind == "swarm":
			if bool(census.swarm): reason = "existing_swarm"
			elif int(census.total)+int(nominal.small_cap) > int(limit.total): reason = "total_cap"
		else:
			if int(census.full)+1 > int(limit.full): reason = "full_cap"
			elif int(census.total)+1 > int(limit.total): reason = "total_cap"
			elif nominal.kind == "elite" and int(census.elites)+1 > int(limit.elites): reason = "elite_cap"
			elif nominal.kind == "boss" and int(census.bosses)+1 > int(limit.bosses): reason = "boss_cap"
		if not reason.is_empty():
			var key: String = str(nominal.serial)+"/"+reason
			cap_wait_ticks[key] = int(cap_wait_ticks.get(key,0))+1
			return {}
		var event: Dictionary = nominal.duplicate(true)
		event.erase("not_before")
		event["time"] = clock
		event["run_seed"] = run_seed
		serial = int(event.serial)
		active[serial] = {"time":clock,"kind":event.kind}
		last_by_key[event.key] = clock
		last_by_kind[event.kind] = clock
		var offered: Dictionary = {"serial":serial,"key":event.key,"kind":event.kind,"role":event.role,"name":event.name,
			"cost":event.cost,"tier_at_entry":event.tier_at_entry,"small_cap":event.get("small_cap",0),"warning":event.warning,
			"nominal_not_before":nominal.not_before,"actual_decision_time":clock,"census_before":census.duplicate(true),"limits":limit}
		offers.append(offered)
		history.append({"serial":serial,"key":event.key,"time":clock,"tier":event.tier_at_entry,"investments":investments,
			"budget":limit.budget,"pressure_before":census.pressure,"synthetic_fixed_order":true})
		index += 1
		return event

func make_battle(seed_value: int, starter: String, stage: String) -> Node2D:
	var b: Node2D = super.make_battle(seed_value,starter,stage)
	var replay: MatchedDirector = MatchedDirector.new()
	replay.setup(seed_value)
	replay.schedule = nominal_schedule.duplicate(true)
	replay.replay_start = warmup
	replay_runtimes.append(replay)
	b.continuous.director = replay
	# This test-only pacing fixture cannot qualify permanent payout; it never
	# creates Main/CollectionSave or settles a Run. RPM uses the normal economy.
	b.continuous.reward_fixture = true
	b.threat_started.connect(func(_entry: Dictionary) -> void:
		if b.elapsed < warmup or replay.offers.is_empty(): return
		var offer: Dictionary = replay.offers[-1].duplicate(true)
		var live_event: Dictionary = b.continuous.events[int(offer.serial)]
		var ids: Array = live_event.ids
		var first: Dictionary = b.entity(int(ids[0]))
		offer["actual_admission_time"] = b.elapsed
		offer["entity_ids"] = ids.duplicate()
		offer["opponent_build"] = Roles.BUILDS.get(str(offer.role),Roles.BUILDS.hunter).duplicate(true) if offer.kind != "swarm" else {}
		offer["actual_initial_mass"] = first.get("mass",null)
		offer["actual_initial_handling"] = first.get("handling",{}).duplicate(true)
		replay.admissions.append(offer))
	return b

func load_schedule() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
	if not parsed is Dictionary: return false
	var reference: Dictionary = {}
	for candidate: Dictionary in parsed.get("samples",[]):
		if candidate.seed == 421 and candidate.stage == "heavy" and candidate.policy == "zero_input": reference = candidate; break
	if reference.is_empty() or not bool(reference.mature_handoff_reached): return false
	for choice: Dictionary in reference.director_history:
		if float(choice.time) < warmup: continue
		var definition: Dictionary = {}
		for event: Dictionary in NativeDirector.EVENTS:
			if event.key == choice.key: definition = event.duplicate(true); break
		if definition.is_empty(): return false
		definition["serial"] = int(choice.serial)
		definition["not_before"] = float(choice.time)
		definition["tier_at_entry"] = int(choice.tier)
		definition["warning"] = float(NativeDirector.TUNING.boss_warning if definition.kind == "boss" else NativeDirector.TUNING.normal_warning)
		if definition.kind == "swarm":
			definition["small_cap"] = 6 if int(choice.tier) == 1 else 10
			definition.cost = float(definition.small_cap)*0.5
		nominal_schedule.append(definition)
	return not nominal_schedule.is_empty()

func observation(seed_value: int, starter: String, stage: String, policy: String) -> Dictionary:
	var row: Dictionary = super.observation(seed_value,starter,stage,policy)
	var replay: RefCounted = replay_runtimes[-1]
	replay_details.append({"policy":policy,"offers":replay.offers.duplicate(true),"admissions":replay.admissions.duplicate(true),
		"cap_wait_ticks":replay.cap_wait_ticks.duplicate(),"offered_count":replay.index,"nominal_count":replay.schedule.size()})
	return row

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
		if argument.begins_with("--reference="): reference_path = argument.trim_prefix("--reference=")
	if not output.is_absolute_path() or FileAccess.file_exists(output) or not reference_path.is_absolute_path():
		push_error("Fresh external report and existing natural reference required"); quit(2); return
	opening_time = 0.0; warmup = 360.0; horizon = 300.0; handling_override = {}
	if not load_schedule(): push_error("Cannot build fixed parameter schedule from genuine seed421 heavy AFK reference"); quit(2); return
	for policy: String in ["zero_input","minimal_active"]:
		samples.append(observation(421,"bastion","heavy",policy))
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Cannot preserve supplemental report"); quit(2); return
	file.store_string(JSON.stringify({"schema":"003a1-fixed-parameter-order-supplement-v1",
		"scope":"Supplemental synthetic Director-choice replay with real360s warmup and300s observed fixed ticks. Ordered event identities,roles,costs,tiers,serials and earliest-choice times come from a preserved genuine heavy seed421 AFK trajectory. Cap/pressure eligibility and original warning/safe-port admission may delay choices/entries. Physics,AI,RPM,input and natural outcomes are unchanged; no damage/reserve/death injection.",
		"reference":reference_path,"nominal_schedule":nominal_schedule,"samples":samples,"replay_details":replay_details,
		"limitations":["This is an explicit exogenous event-choice fixture, not the production adaptive Director selection law.","No extra events are invented after the source AFK trajectory ends. Primary multi-seed natural studies remain acceptance evidence.","Real admission timing,spawn ports,contacts and survival may diverge under actual controls; ordered fixed specifications are compared only over shared lifetime.","Permanent reward eligibility is explicitly invalidated at opening; no player collection is opened or settled."]},"\t")); file.close()
	print("BASTION_MATCHED_PRESSURE_COMPLETE samples=%d nominal_events=%d" % [samples.size(),nominal_schedule.size()]); quit(0)
