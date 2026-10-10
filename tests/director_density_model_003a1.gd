extends RefCounted
## Independent census-lifetime fixture. Calls the REAL Director at every0.25s;
## it is not combat, survival, damage, reward or player-input evidence.
const Director = preload("res://scripts/threat_director.gd")
const Seeds = preload("res://scripts/seed_utils.gd")
const STEP: float = 0.25

static func census(events: Array[Dictionary], time: float) -> Dictionary:
	var c: Dictionary={"pressure":0.0,"full":0,"small":0,"elites":0,"bosses":0,"total":1,"swarm":false,"active_full":0,"active_small":0,"active_bosses":0,"active_elites":0}
	for event: Dictionary in events:
		c.pressure+=float(event.cost)
		var admitted: bool=time>=float(event.ready_at)
		if event.kind=="swarm":
			c.swarm=true;c.small+=int(event.small_cap)
			if admitted:c.active_small+=int(event.small_cap)
		else:
			c.full+=1
			if admitted:c.active_full+=1
		if event.kind=="elite":
			c.elites+=1
			if admitted:c.active_elites+=1
		if event.kind=="boss":
			c.bosses+=1
			if admitted:c.active_bosses+=1
	c.total+=int(c.full)+int(c.small)
	c["active_total"]=1+int(c.active_full)+int(c.active_small)
	return c

static func lifetime(seed_value: int, event: Dictionary, policy: String) -> float:
	if event.kind=="swarm":return 32.0
	var rng: RandomNumberGenerator=RandomNumberGenerator.new()
	rng.seed=Seeds.derive(seed_value,"deep_density_lifetime/%s/%d"%[policy,int(event.serial)])
	if policy=="quick":return rng.randf_range(21.0,40.0)+(30.0 if event.kind=="boss" else (10.0 if event.kind=="elite" else 0.0))
	# A durable census exposes upper composition limits without pretending a
	# real player survived it. Finite clear times are identical policy/seed in
	# before and after. Bosses clear earlier than durable support so post-boss
	# fifth/sixth admissions are actually exercised.
	return rng.randf_range(80.0,110.0) if event.kind=="boss" else rng.randf_range(120.0,180.0)

static func simulate(seed_value: int, policy: String, seconds: float=1200.0) -> Dictionary:
	var director: RefCounted=Director.new();director.setup(seed_value)
	var live: Array[Dictionary]=[{"serial":1,"kind":"rival","key":"hunter","cost":2.6,"ready_at":0.0,"expires":27.0}]
	var result: Dictionary={"seed":seed_value,"policy":policy,"seconds":seconds,"trace":[],"admissions":[],"violations":[],"first_five":null,"first_six":null,"peak_full":1,"peak_small":0,"peak_total":2,"grandfather_samples":0}
	var bins: Array[Dictionary]=[]
	for name: String in ["0–5 minutes","5–10 minutes","10–15 minutes","15+ minutes"]:
		bins.append({"range":name,"samples":0,"active_full_sum":0,"peak_active_full":0,"peak_active_small":0,"peak_total_bodies":0,"peak_elites":0,"peak_bosses":0,"tiers":[],"full_caps":[],"budget_min":INF,"budget_max":0.0,"admissions":0,"admission_intervals":[]})
	var last_admission: float=-1.0
	for tick: int in range(int(seconds/STEP)+1):
		var time: float=float(tick)*STEP
		for index: int in range(live.size()-1,-1,-1):
			if time>=float(live[index].expires):
				var ended: Dictionary=live[index];live.remove_at(index)
				director.cleared(int(ended.serial),time,live.is_empty())
		var c: Dictionary=census(live,time)
		var investments: int=mini(13,1+int(time/25.0))
		var limit: Dictionary=Director.limits(time,investments)
		var grandfather: bool=int(c.small)>int(limit.small) or int(c.bosses)>int(limit.bosses)
		if grandfather:result.grandfather_samples+=1
		if float(c.pressure)>float(limit.budget)+0.00001 or int(c.full)>int(limit.full) or int(c.total)>int(limit.total):result.violations.append({"time":time,"kind":"hard_population_or_budget","census":c,"limits":limit})
		if int(c.small)>10 or int(c.elites)>2 or int(c.bosses)>2:result.violations.append({"time":time,"kind":"global_existing_ceiling","census":c})
		if int(c.active_full)>=5 and result.first_five==null:result.first_five=time
		if int(c.active_full)>=6 and result.first_six==null:result.first_six=time
		result.peak_full=maxi(int(result.peak_full),int(c.active_full));result.peak_small=maxi(int(result.peak_small),int(c.active_small));result.peak_total=maxi(int(result.peak_total),int(c.active_total))
		var bin_index: int=mini(3,int(time/300.0));var bin: Dictionary=bins[bin_index]
		bin.samples+=1;bin.active_full_sum+=int(c.active_full)
		bin.peak_active_full=maxi(int(bin.peak_active_full),int(c.active_full));bin.peak_active_small=maxi(int(bin.peak_active_small),int(c.active_small));bin.peak_total_bodies=maxi(int(bin.peak_total_bodies),int(c.active_total))
		bin.peak_elites=maxi(int(bin.peak_elites),int(c.active_elites));bin.peak_bosses=maxi(int(bin.peak_bosses),int(c.active_bosses))
		if not int(limit.tier) in bin.tiers:bin.tiers.append(int(limit.tier))
		if not int(limit.full) in bin.full_caps:bin.full_caps.append(int(limit.full))
		bin.budget_min=minf(float(bin.budget_min),float(limit.budget));bin.budget_max=maxf(float(bin.budget_max),float(limit.budget))
		if tick%4==0:result.trace.append({"time":time,"tier":limit.tier,"full_cap":limit.full,"composition_full_cap":mini(int(limit.full),4) if bool(limit.get("deep",false)) and (int(c.bosses)>0 or bool(c.swarm)) else int(limit.full),"active_full":c.active_full,"reserved_full":c.full,"active_swarm_bodies":c.active_small,"reserved_swarm_bodies":c.small,"active_elites":c.active_elites,"active_bosses":c.active_bosses,"active_total_bodies":c.active_total,"reserved_total_bodies":c.total,"pressure":c.pressure,"pressure_budget":limit.budget,"admission_small_target":limit.small,"admission_boss_target":limit.bosses,"grandfathered_old_reservation":grandfather,"next_decision":director.next_decision,"calm":director.draining or time<director.calm_until})
		# ContinuousRun holds one warning reservation before admitting another.
		if live.any(func(event: Dictionary) -> bool:return time<float(event.ready_at)):continue
		var event: Dictionary=director.decide(time,c,investments)
		if event.is_empty():continue
		event["ready_at"]=time+float(event.warning);event["expires"]=float(event.ready_at)+lifetime(seed_value,event,policy)
		event["admission_limits"]=limit.duplicate(true)
		live.append(event)
		var record: Dictionary={"time":time,"ready_at":event.ready_at,"expires":event.expires,"serial":event.serial,"kind":event.kind,"key":event.key,"cost":event.cost,"small_cap":event.get("small_cap",0),"limits":limit,"census_before":c,"next_decision":director.next_decision}
		result.admissions.append(record);bin.admissions+=1
		if last_admission>=0.0:bin.admission_intervals.append(time-last_admission)
		last_admission=time
	for bin: Dictionary in bins:bin["average_active_full"]=float(bin.active_full_sum)/maxi(1,int(bin.samples))
	result["ranges"]=bins
	result["bounded_state"]={"active":director.active.size(),"history":director.history.size(),"recent":director.recent.size()}
	return result
