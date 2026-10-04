extends RefCounted
## Seeded pressure policy. No scene access, physics RNG, player healing or outcomes.
const Seeds = preload("res://scripts/seed_utils.gd")
const TUNING: Dictionary = {
	"tier_seconds":[0.0,35.0,100.0,210.0,360.0], "overdrive_seconds":120.0,
	"budgets":[2.8,6.0,10.0,13.0,16.0], "overdrive_budget_step":1.25,
	"full_caps":[1,2,3,4,5], "elite_cap":2, "small_cap":10, "total_cap":16,
	"boss_cooldown":78.0, "late_boss_cooldown":56.0, "same_boss_cooldown":180.0, "swarm_cooldown":34.0,
	"elite_cooldown":18.0, "boss_warning":2.2, "normal_warning":0.65,
	"breath_min":2.0, "breath_max":4.0, "busy_limit":55.0,
	"cadence_min":[12.0,8.0,7.0,6.0,5.0], "cadence_max":[17.0,12.0,11.0,9.0,8.0]
}
const EVENTS: Array[Dictionary] = [
	{"key":"hunter","kind":"rival","role":"hunter","name":"HUNTER","cost":2.6,"tier":0,"weight":1.0},
	{"key":"bulwark","kind":"rival","role":"bulwark","name":"BULWARK","cost":2.8,"tier":0,"weight":0.8},
	{"key":"flanker","kind":"specialist","role":"flanker","name":"FLANKER","cost":3.0,"tier":1,"weight":1.3},
	{"key":"harasser","kind":"specialist","role":"harasser","name":"HARASSER","cost":3.0,"tier":1,"weight":1.3},
	{"key":"ammunition","kind":"swarm","role":"swarm","name":"AMMUNITION WAVES","cost":4.0,"tier":1,"weight":2.6},
	{"key":"ballast","kind":"elite","role":"bulwark","name":"BALLAST ELITE","cost":4.6,"tier":2,"weight":1.5},
	{"key":"hotwire","kind":"elite","role":"hunter","name":"HOTWIRE ELITE","cost":4.5,"tier":2,"weight":1.5},
	{"key":"anvil","kind":"boss","role":"bulwark","name":"THE ANVIL","cost":7.0,"tier":2,"weight":2.2},
	{"key":"reaper","kind":"boss","role":"flanker","name":"RED REAPER","cost":7.0,"tier":2,"weight":2.2}
]
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var run_seed: int = 0
var serial: int = 1
var next_decision: float = 12.0
var calm_until: float = 0.0
var last_breath: float = 0.0
var draining: bool = false
var recent: Array[String] = ["hunter"]
var last_by_key: Dictionary = {"hunter":0.0}
var last_by_kind: Dictionary = {"rival":0.0}
var fast_clears: int = 0
var active: Dictionary = {1:{"time":0.0,"kind":"rival"}}
var history: Array[Dictionary] = []

func setup(seed_value: int) -> void:
	run_seed = seed_value
	rng.seed = Seeds.derive(seed_value,"threat_director/v1")
	next_decision = rng.randf_range(12.0,17.0)

static func tier_at(time: float) -> int:
	var tier: int = 0
	for boundary: float in TUNING.tier_seconds:
		if time >= boundary: tier += 1
	return maxi(0,tier-1) + maxi(0,floori((time-360.0)/float(TUNING.overdrive_seconds)))

static func limits(time: float, investments: int = 1) -> Dictionary:
	var tier: int = tier_at(time)
	var row: int = mini(4,tier)
	return {"tier":tier,"budget":float(TUNING.budgets[row])+maxi(0,tier-4)*float(TUNING.overdrive_budget_step)+(minf(0.6,maxi(0,investments-4)*0.07) if tier > 0 else 0.0),
		"full":int(TUNING.full_caps[row]),"elites":int(TUNING.elite_cap),"bosses":2 if tier >= 4 else 1,
		"small":int(TUNING.small_cap),"total":int(TUNING.total_cap)}

func candidates(time: float, census: Dictionary, investments: int) -> Array[Dictionary]:
	var limit: Dictionary = limits(time,investments)
	var choices: Array[Dictionary] = []
	for definition: Dictionary in EVENTS:
		var event: Dictionary = definition.duplicate(true)
		if int(event.tier) > int(limit.tier): continue
		if event.kind == "swarm":
			event["small_cap"] = 6 if int(limit.tier) == 1 else 10
			event.cost = float(event.small_cap)*0.5 # Reserve the peak, including unspawned waves.
			if bool(census.get("swarm",false)) or time-float(last_by_kind.get("swarm",-1000.0)) < float(TUNING.swarm_cooldown): continue
			if int(census.total)+int(event.small_cap) > int(limit.total): continue
		else:
			if int(census.full) >= int(limit.full) or int(census.total)+1 > int(limit.total): continue
		if event.kind == "elite" and (int(census.elites) >= int(limit.elites) or time-float(last_by_kind.get("elite",-1000.0)) < float(TUNING.elite_cooldown)): continue
		if event.kind == "boss":
			if int(census.bosses) >= int(limit.bosses) or time-float(last_by_kind.get("boss",-1000.0)) < (float(TUNING.late_boss_cooldown) if int(limit.tier) >= 4 else float(TUNING.boss_cooldown)): continue
			if time-float(last_by_key.get(event.key,-1000.0)) < float(TUNING.same_boss_cooldown): continue
		if float(census.pressure)+float(event.cost) > float(limit.budget)+0.00001: continue
		if recent.size() >= 2 and recent[-1] == event.key and recent[-2] == event.key: continue
		var appearances: int = recent.count(str(event.key))
		event.weight = float(event.weight)/float(1+appearances*3)
		# More combinations late, not endless extra bodies or HP multiplication.
		if event.kind in ["elite","boss"]: event.weight *= 1.0+minf(1.0,maxi(0,int(limit.tier)-2)*0.16)
		choices.append(event)
	return choices

func decide(time: float, census: Dictionary, investments: int = 1) -> Dictionary:
	if time < calm_until or time < next_decision: return {}
	var limit: Dictionary = limits(time,investments)
	if time-last_breath >= float(TUNING.busy_limit): draining = true
	if draining:
		if float(census.pressure) <= float(limit.budget)*0.45:
			calm_until = time+rng.randf_range(3.0,5.0)
			last_breath = time
			draining = false
		return {}
	next_decision = time+0.75
	var choices: Array[Dictionary] = candidates(time,census,investments)
	if choices.is_empty(): return {}
	var total: float = 0.0
	for event: Dictionary in choices: total += float(event.weight)
	var selection_state: int = rng.state
	var roll: float = rng.randf()*total
	var chosen: Dictionary = choices.back()
	for event: Dictionary in choices:
		roll -= float(event.weight)
		if roll < 0.0: chosen = event; break
	serial += 1
	chosen["serial"] = serial
	chosen["run_seed"] = run_seed
	chosen["time"] = time
	chosen["tier_at_entry"] = limit.tier
	chosen["warning"] = float(TUNING.boss_warning if chosen.kind == "boss" else TUNING.normal_warning)
	recent.append(chosen.key)
	if recent.size() > 6: recent.pop_front()
	last_by_key[chosen.key] = time
	last_by_kind[chosen.kind] = time
	active[serial] = {"time":time,"kind":chosen.kind}
	history.append({"serial":serial,"key":chosen.key,"time":snappedf(time,0.01),"tier":limit.tier,"pressure_before":snappedf(census.pressure,0.01),"budget":limit.budget,"census":census.duplicate(true),"investments":investments,"rng_before_choice":str(selection_state)})
	if history.size() > 128: history.pop_front()
	var row: int = mini(4,int(limit.tier))
	var acceleration: float = 1.0-minf(0.2,fast_clears*0.05)
	var overdrive: float = 0.6+0.4/(1.0+maxi(0,int(limit.tier)-4)*0.05)
	next_decision = time+rng.randf_range(TUNING.cadence_min[row],TUNING.cadence_max[row])*acceleration*overdrive
	if chosen.kind == "boss": next_decision = maxf(next_decision,time+10.0)
	return chosen

func cleared(event_serial: int, time: float, empty: bool) -> bool:
	if not active.has(event_serial): return false
	var record: Dictionary = active[event_serial]
	active.erase(event_serial)
	var duration: float = time-float(record.time)
	fast_clears = mini(4,fast_clears+1) if duration < 12.0 else maxi(0,fast_clears-1)
	if empty or record.kind == "boss":
		calm_until = maxf(calm_until,time+rng.randf_range(TUNING.breath_min,TUNING.breath_max))
		last_breath = time
		# Empty arenas return promptly even if the normal cadence was longer.
		if empty:
			next_decision = calm_until
			draining = false
	return true
