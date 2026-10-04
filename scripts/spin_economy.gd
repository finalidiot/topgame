extends RefCounted
## Run-only source accounting and earned sustain. No net-loss adjustment.
## Values are fractions of a full 9000 RPM reserve. No randomness is consumed.
const TUNING = {
	"passive_base":0.0032, "stamina_credit":0.00022, "passive_floor":0.0008,
	"movement":0.0012, "acceleration":0.0010, "braking":0.0025, "wobble":0.003,
	"severity":0.32, "target_cooldown":1.4, "global_cooldown":0.35,
	"reclaim_damage":2.8, "reclaim_severity":0.026, "contact_max":0.095,
	"bucket_capacity":0.12, "bucket_rate":0.045,
	"small_capacity":0.008, "small_rate":0.002, "small_elimination":0.001,
	"redline_activation_1":0.025, "redline_activation_2":0.045, "redline_drain":0.015, "redline_heat":0.025,
	"committed_bonus":0.040,
	"elimination":0.045, "elite":0.075, "boss":0.12, "credit_seconds":12.0
}
var _host: WeakRef
var losses: Dictionary = {"passive":0.0,"movement":0.0,"burst":0.0,"braking":0.0,"powers":0.0,"collisions":0.0,"walls":0.0,"wobble":0.0}
var gains: Dictionary = {"combat_reclamation":0.0,"elimination":0.0,"elite":0.0,"boss":0.0,"second_wind":0.0,"runaway":0.0,"slipstream":0.0}
var contacts: Dictionary = {}
var credits: Dictionary = {}
var paid: Dictionary = {}
var recovery_events: Array[Dictionary] = []
var tokens: float = TUNING.bucket_capacity
var small_tokens: float = TUNING.small_capacity
var ready_at: float = 0.0
var control: float = 0.0
var minimum: float = 1.0
var below_half: float = 0.0
var below_quarter: float = 0.0
var near_out: float = 0.0
var recovery_count: int = 0
var largest: float = 0.0
var pulse_until: float = 0.0
var pulse_amount: float = 0.0
var pulse_source: String = ""

func setup(battle: Node2D) -> void: _host = weakref(battle)
func host() -> Node2D: return _host.get_ref()
func valid(f: Dictionary) -> bool:
	return host().continuous != null and host().continuous.economy == self and not f.is_empty() and is_same(host().entity(int(f.entity_id)),f)
func player(f: Dictionary) -> bool:
	return valid(f) and int(f.entity_id) == host().player_entity_id

func begin_tick(dt: float, input: Vector2) -> void:
	control = input.length()
	tokens = minf(TUNING.bucket_capacity,tokens+dt*TUNING.bucket_rate)
	small_tokens = minf(TUNING.small_capacity,small_tokens+dt*TUNING.small_rate)

func spend(f: Dictionary, amount: float, source: String) -> void:
	if not valid(f): return
	var actual: float = minf(float(f.rpm),maxf(0.0,amount))
	f.rpm = maxf(0.0,float(f.rpm)-actual)
	f.energy = f.rpm
	if player(f):
		losses[source] = float(losses.get(source,0.0))+actual
		minimum = minf(minimum,f.rpm)

func gain(f: Dictionary, amount: float, source: String, small: bool = false) -> float:
	if not player(f) or not str(f.outcome).is_empty() or host().battle_status != "battle" or host().paused: return 0.0
	var actual: float = minf(maxf(0.0,amount),1.0-float(f.rpm))
	# All small-body returns, including Runaway, share one sustained budget.
	if small: actual = minf(actual,small_tokens)
	if source != "second_wind": actual = minf(actual,tokens)
	if actual <= 0.000001: return 0.0
	if small: small_tokens -= actual
	if source != "second_wind": tokens -= actual
	f.rpm = minf(1.0,float(f.rpm)+actual)
	f.energy = f.rpm
	gains[source] = float(gains.get(source,0.0))+actual
	recovery_count += 1
	largest = maxf(largest,actual)
	var event: Dictionary = {"time":host().elapsed,"source":source,"amount":actual,"rpm":f.rpm}
	recovery_events.append(event)
	if recovery_events.size() > 128: recovery_events.pop_front()
	if actual >= 0.012:
		pulse_until = host().elapsed+0.8
		pulse_amount = actual
		pulse_source = source
	host().present_reclaim(actual,source)
	return actual

func running_costs(f: Dictionary, speed: float, input: Vector2, braking: bool, drain: float, dt: float) -> void:
	var efficiency: float = float(f.get("handling",{}).get("spin_drain",1.0))*drain
	spend(f,maxf(TUNING.passive_floor,TUNING.passive_base-float(f.stats.stamina)*TUNING.stamina_credit)*efficiency*dt,"passive")
	spend(f,(speed/230.0*TUNING.movement+input.length_squared()*TUNING.acceleration)*efficiency*dt,"movement")
	spend(f,(TUNING.braking if braking else 0.0)*efficiency*dt,"braking")
	spend(f,float(f.wobble)*TUNING.wobble*efficiency*dt,"wobble")

func credit(target: Dictionary) -> void:
	if valid(target) and target.team_id == "hostile" and str(target.outcome).is_empty(): credits[int(target.entity_id)] = host().elapsed

func contact(target: Dictionary, severity: float, damage: float, approach_speed: float, moving_speed: float = -1.0) -> void:
	var p: Dictionary = host().player_entity()
	if not valid(target) or target.team_id != "hostile" or not str(target.outcome).is_empty() or target.combatant_type == "small_top": return
	if severity < TUNING.severity or damage < 0.004: return
	# Moving into a hit OR actively steering a stable defensive reception.
	# No-input/stationary pinning cannot be a renewable source.
	if moving_speed >= 0.0 and moving_speed < 8.0: return
	if control < 0.08 or (approach_speed < 25.0 and (float(p.wobble) > 0.30 or control > 0.65)): return
	credit(target)
	var now: float = host().elapsed
	var id: int = int(target.entity_id)
	if now < ready_at or now < float(contacts.get(id,-INF)): return
	contacts[id] = now+TUNING.target_cooldown
	ready_at = now+TUNING.global_cooldown
	gain(p,minf(TUNING.contact_max,damage*TUNING.reclaim_damage+severity*TUNING.reclaim_severity+(TUNING.committed_bonus if approach_speed >= 65.0 else 0.0)),"combat_reclamation")

func outcomes() -> void:
	for f: Dictionary in host().fighters:
		if f.team_id != "hostile" or paid.has(int(f.entity_id)): continue
		if str(f.outcome).is_empty() and float(f.rpm) > 0.045: continue
		# Reserve crossing is provisional until an enemy's emergency power runs.
		# Ring-outs/confirmed outcomes cannot be rescued by Second Wind.
		if str(f.outcome).is_empty() and "second_wind" in f.get("powers",[]) and not bool(f.get("second_wind_used",false)): continue
		if not str(f.outcome).is_empty() and f.outcome not in ["impact","spin_out","ring_out"]: continue
		paid[int(f.entity_id)] = true
		var small: bool = f.combatant_type == "small_top"
		var attributed: bool = str(host().powers.cause_for(f).get("owner_id","")) == "player" if small else host().elapsed-float(credits.get(int(f.entity_id),-INF)) <= TUNING.credit_seconds
		if not attributed: continue
		var source: String = str(f.get("enemy_kind",""))
		if source not in ["elite","boss"]: source = "elimination"
		gain(host().player_entity(),TUNING.small_elimination if small else float(TUNING[source]),source,small)

func end_tick(dt: float) -> void:
	var rpm: float = host().player_entity().rpm
	minimum = minf(minimum,rpm)
	if rpm < 0.5: below_half += dt
	if rpm < 0.25: below_quarter += dt
	if rpm < 0.14: near_out += dt

func retire(id: int) -> void:
	contacts.erase(id)
	credits.erase(id)
	paid.erase(id)

func snapshot() -> Dictionary:
	var total: float = 0.0
	for value: float in gains.values(): total += value
	return {"losses":losses.duplicate(),"gains":gains.duplicate(),"starting_rpm":1.0,"minimum_rpm":minimum,"final_rpm":host().player_entity().rpm,"below_50_seconds":below_half,"below_25_seconds":below_quarter,"near_spinout_seconds":near_out,"recovery_count":recovery_count,"largest_recovery":largest,"total_recovered":total,"death":host().last_result.get("reason",""),"recent_recoveries":recovery_events.duplicate(true)}
