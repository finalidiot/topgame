extends SceneTree
## Disclosed invested opening; all observed clocks, admissions, forces, reserve
## spending and gains are production rules. Observation never edits live state.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Parts = preload("res://scripts/parts.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const PowerGuide = preload("res://scripts/run_powers.gd")
const STAGES: Dictionary = {
	"meter_combo":{"ranks":{"dead_centre":2,"orbit_drive":2,"impact_sink":2,"redline":2,"crash_guard":2,"impact_wake":2,"high_gear":2},"mutations":{}},
	"without_dc":{"ranks":{"crash_guard":2,"clutch":2,"momentum_bank":2,"impact_wake":2,"iron_comet":2,"crosscut":2},"mutations":{}},
	"dc_redline":{"ranks":{"dead_centre":3,"redline":2,"crash_guard":2,"clutch":2,"momentum_bank":2,"impact_wake":2,"iron_comet":2},"mutations":{"dead_centre":"bulwark"}},
	"redline_only":{"ranks":{"redline":2,"crash_guard":2,"clutch":2,"momentum_bank":2,"impact_wake":2,"iron_comet":2,"crosscut":2},"mutations":{}},
	"stock":{"ranks":{},"mutations":{}},
	"moderate":{"ranks":{"dead_centre":1,"crash_guard":1,"momentum_bank":1},"mutations":{}},
	"heavy":{"ranks":{"dead_centre":2,"crash_guard":2,"clutch":2,"momentum_bank":2,"gyro_lock":2,"impact_sink":2,"anchor_exchange":2},"mutations":{}},
	"extreme":{"ranks":{"dead_centre":3,"crash_guard":2,"clutch":2,"momentum_bank":2,"gyro_lock":3,"impact_sink":3,"anchor_exchange":3},"mutations":{"dead_centre":"bulwark","gyro_lock":"keel","impact_sink":"shock_bleed","anchor_exchange":"deep_footing"}},
	"extreme_wind":{"ranks":{"dead_centre":3,"crash_guard":2,"clutch":2,"second_wind":1,"gyro_lock":3,"impact_sink":3,"anchor_exchange":3},"mutations":{"dead_centre":"counterweight","gyro_lock":"flywheel","impact_sink":"shock_bleed","anchor_exchange":"deep_footing"}},
	"counterweight":{"ranks":{"dead_centre":3,"crash_guard":2,"clutch":2,"momentum_bank":2,"gyro_lock":3,"impact_sink":3,"anchor_exchange":3},"mutations":{"dead_centre":"counterweight","gyro_lock":"flywheel","impact_sink":"return_spring","anchor_exchange":"slip_anchor"}},
	"legacy_bulwark":{"ranks":{"dead_centre":3,"crash_guard":2,"clutch":2,"momentum_bank":2,"impact_wake":2,"iron_comet":2,"crosscut":2},"mutations":{"dead_centre":"bulwark"}}
}
var warmup: float = 504.0
var opening_time: float = 0.0
var horizon: float = 329.0
var trace_interval: float = 5.0
var seeds: Array[int] = [421,7341,2026]
var stages: Array[String] = ["without_dc","legacy_bulwark","dc_redline","extreme"]
var starters: Array[String] = ["bastion"]
var policies: Array[String] = ["zero_input","minimal_active"]
var investments: int = 15
var output: String = ""
var source_label: String = ""
var handling_override: Dictionary = {}
var samples: Array[Dictionary] = []

class StudyBattle extends Battle:
	var update_readings: Dictionary = {}
	var opening_clock: float = 0.0
	func begin_run(player_build: Dictionary, descriptor: Dictionary, run_seed: int) -> void:
		super.begin_run(player_build,descriptor,run_seed)
		# Optional disclosed synthetic mature context, inside initialization.
		# The natural common-warmup study leaves this at zero.
		if opening_clock <= 0.0: return
		elapsed = opening_clock
		powers.time = opening_clock
		powers.defence.time = opening_clock
		roster.time = opening_clock
		continuous.threat_started_at = opening_clock
		continuous.events[1].time = opening_clock
		continuous.director.active[1].time = opening_clock
		continuous.director.next_decision += opening_clock
		continuous.director.last_breath = opening_clock
		continuous.director.last_by_key.hunter = opening_clock
		continuous.director.last_by_kind.rival = opening_clock
	func _update_fighter(fighter: Dictionary, direction: Vector2, braking: bool, dt: float) -> void:
		var watched: bool = int(fighter.entity_id) == player_entity_id and continuous != null
		var before_wobble: float = float(fighter.wobble)
		var before_passive: float = float(continuous.economy.losses.passive) if watched else 0.0
		super._update_fighter(fighter,direction,braking,dt)
		if not watched: return
		var actual: float = float(continuous.economy.losses.passive)-before_passive
		var base: float = maxf(continuous.economy.TUNING.passive_floor,continuous.economy.TUNING.passive_base-float(fighter.stats.stamina)*continuous.economy.TUNING.stamina_credit)
		update_readings = {"actual_passive_per_second":actual/dt,"effective_drain":actual/dt/base,
			"wobble_before_update":before_wobble,"wobble_after_update":fighter.wobble,
			"wobble_removed_in_update":maxf(0.0,before_wobble-float(fighter.wobble)),
			"effective_mass":1.0/powers.inverse_mass(fighter),"incoming_rpm_scale":powers.incoming_rpm_scale(fighter),
			"roster_collision_cost":roster.collision_cost(fighter)}

func _initialize() -> void: call_deferred("_run")

func make_battle(seed_value: int, starter: String, stage: String) -> Node2D:
	assert(STAGES[stage].ranks.size() <= PowerGuide.FAMILY_CAP, "Declared study build must fit the real power family cap")
	var b: Node2D = StudyBattle.new()
	b.opening_clock = opening_time
	root.add_child(b)
	b.set_physics_process(false)
	var d: Dictionary = Encounters.for_run_event(1,seed_value)
	var build: Dictionary = Starters.build_for(starter if starter in Starters.IDS else "bastion")
	if starter == "custom_defence": build = {"blade":"guard","ratchet":"ballast","bit":"tripod"}
	d.starter_id = starter if starter in Starters.IDS else "custom"
	d.player_power_ids = STAGES[stage].ranks.keys()
	d.player_power_ranks = STAGES[stage].ranks.duplicate(true)
	d.player_power_mutations = STAGES[stage].mutations.duplicate(true)
	b.begin_run(build,d,seed_value)
	# Explicit opening fixture only: investment budget, centre placement and
	# launch velocity. No reserve or clock top-up before or after handoff.
	b.continuous.progression_level = investments
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	p.pos = Vector2.ZERO
	p.vel = Vector2.ZERO
	b.entity(2).vel = b.entity(2).launch_velocity
	if not handling_override.is_empty():
		var old_mass_scale: float = float(p.handling.get("mass",1.0))
		p.handling.merge(handling_override,true)
		p.mass = float(p.mass)/old_mass_scale*float(p.handling.get("mass",1.0))
	return b

func project_input(world: Vector2) -> Vector2:
	return Vector2(world.x-world.y,(world.x+world.y)*0.5).normalized()*world.length()

func controls(b: Node2D, policy: String, tick: int, state: Dictionary) -> Dictionary:
	if policy == "zero_input": return {"direction":Vector2.ZERO,"burst":false,"brake":false,"mode":"hands_off"}
	if policy == "legacy_warmup" or policy == "legacy_active":
		var old: Dictionary = Bot.input(b,"defensive",tick)
		old.mode = "legacy_common_warmup" if policy == "warmup" else "legacy_constant_steering"
		return old
	if b.elapsed < float(state.get("next_sample",-INF)): return state.controls
	state.next_sample = b.elapsed+0.25
	var p: Dictionary = b.player_entity()
	var position: Vector2 = p.pos
	var velocity: Vector2 = p.vel
	var radius: float = position.length()
	var recharge: String = str(state.get("recharge","none"))
	var stress: float = float(p.get("anchor_stress",0.0))
	if recharge == "none" and stress >= 0.55:
		# Stress needs a short controlled release, not a recovery lap. Only an
		# exhausted RPM quota requires the existing wider outside recharge.
		recharge = "vent" if float(p.get("anchor_recovery_remaining",0.0)) >= 0.06 else "outward"
		state.recharge_heading = position.normalized() if radius > 8.0 else Vector2.ONE.normalized()
	# Decisions use only public player/HUD state. No enemy target or lookahead.
	if recharge == "none" and float(p.get("anchor_recovery_remaining",1.0)) <= 0.015 and float(p.rpm) < 0.78:
		recharge = "outward"
		state.recharge_heading = position.normalized() if radius > 8.0 else Vector2.ONE.normalized()
	if recharge == "vent" and stress <= 0.12: recharge = "return"
	elif recharge in ["outward","rotate"] and stress <= 0.12 and float(p.get("anchor_recovery_remaining",1.0)) >= 0.19: recharge = "return"
	if recharge == "return" and radius <= 28.0: recharge = "none"
	var direction: Vector2 = Vector2.ZERO
	var burst: bool = false
	var brake: bool = false
	var mode: String = "rest"
	if recharge == "vent":
		if radius < 32.0:
			direction = Vector2(state.recharge_heading)*0.45
		elif radius > 65.0:
			direction = (-position*1.2-velocity*0.5).normalized()*0.45
		else:
			var tangent: Vector2 = position.orthogonal().normalized()
			direction = (tangent-position.normalized()*clampf((radius-45.0)/15.0,-0.5,0.5)).normalized()*0.45
		mode = "short_release_vent"
	elif recharge == "outward":
		direction = Vector2(state.recharge_heading)*0.55
		if radius >= 91.0: recharge = "rotate"
		mode = "leave_centre"
	elif recharge == "rotate":
		var tangent: Vector2 = Vector2(-position.y,position.x).normalized()
		direction = (tangent-position.normalized()*clampf((radius-98.0)/24.0,-0.6,0.6)).normalized()*0.55
		mode = "outside_recharge"
	elif recharge == "return":
		direction = (-position*0.9-velocity*0.35).normalized()*0.40
		mode = "reestablish_centre"
	else:
		if policy != "recharge_only" and (radius > 8.0 or fmod(b.elapsed,2.0) < 0.75):
			var desired: Vector2 = -position*0.9-velocity*0.35
			if desired.length() < 1.0: desired = Vector2.RIGHT.rotated(b.elapsed*0.30)
			direction = desired.normalized()*0.24
			mode = "small_correction"
		var stored_ready: bool = float(p.get("sink_charge",0.0)) >= 15.0
		var recent_heavy: bool = float(p.get("impact_time",0.0)) > 0.20 and float(p.get("impact_strength",0.0)) >= 0.75
		if policy != "recharge_only" and velocity.length() <= 120.0 and (stored_ready or recent_heavy) and b.elapsed >= float(state.get("brake_ready",0.0)):
			brake = true
			state.brake_ready = b.elapsed+6.0
			mode = "brief_brake"
	if stage_redline(p) and recharge == "outward" and stress <= 0.70 and float(p.cooldown) <= 0.0 and fmod(b.elapsed,18.0) < 0.30:
		burst = true
		mode = "redline_release"
	# The player can see the open gates and their own momentum. A sampled
	# inward correction/brief Brake catches an unsafe excursion; it neither
	# targets enemies nor overrides real incoming force or a natural outcome.
	if radius >= 138.0:
		direction = (-position*1.2-velocity*0.5).normalized()*0.55
		brake = velocity.dot(position.normalized()) > 25.0 or velocity.length() > 110.0
		burst = false
		mode = "boundary_correction"
	state.recharge = recharge
	state.controls = {"direction":project_input(direction),"burst":burst,"brake":brake,"mode":mode}
	return state.controls

func stage_redline(p: Dictionary) -> bool:
	return "redline" in p.get("powers",[])

func difference(current: Dictionary, previous: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in current: result[key] = float(current[key])-float(previous.get(key,0.0))
	return result

func public_power_state(p: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["anchor_stress","anchor_load","anchor_strength","anchor_venting","redline_time","redline_heat","redline_overcap","orbit_charge","drift_active","anchor_charge","anchor_maturity","anchor_hold_seconds","anchor_recovery_remaining","anchor_rearm_progress","anchor_recovery_rate","anchor_central_hold","anchor_pull_strength","stored_force","gyro_charge","sink_charge","sink_capacity","exchange_charge","exchange_carry","clutch_active","guard_time","momentum_charge","second_wind_used"]:
		result[key] = p.get(key,0.0)
	return result

func random_state(b: Node2D) -> Dictionary:
	var ai: Dictionary = {}
	for id: int in b._ai_rngs: ai[str(id)] = str(b._ai_rngs[id].state)
	return {"simulation":str(b._simulation_rng.state),"cosmetic":str(b._cosmetic_rng.state),"director":str(b.continuous.director.rng.state),"ai":ai}

func observation(seed_value: int, starter: String, stage: String, policy: String) -> Dictionary:
	var b: Node2D = make_battle(seed_value,starter,stage)
	var p: Dictionary = b.player_entity()
	var row: Dictionary = {"seed":seed_value,"starter":starter,"stage":stage,"policy":policy,"initial_build":p.build.duplicate(true),"stats":p.stats.duplicate(true),"physical":p.part_physics.duplicate(true),"handling":p.handling.duplicate(true),"base_mass":p.mass,"power_ranks":p.power_ranks.duplicate(true),"mutations":p.power_mutations.duplicate(true),"director_investments":investments,"trace":[],"contacts":[],"full_impacts":[],"centre_seconds":0.0,"input_seconds":0.0,"brake_seconds":0.0,"peak_radius":0.0,"radius_integral":0.0,"wobble_integral":0.0,"mass_integral":0.0,"collision_scale_integral":0.0,"wobble_removed":0.0,"mature_contacts":0,"mature_heavy_contacts":0,"peak_full":0,"peak_small":0,"drain_seconds":0.0,"control_modes":{},"finite":true,"mature_minimum_rpm":1.0,"mature_above_75_seconds":0.0,"mature_above_50_seconds":0.0}
	var tick: int = 0
	var next_trace: float = opening_time
	var started: bool = false
	var start_economy: Dictionary = {}
	var start_power_procs: Dictionary = {}
	var start_defence_procs: Dictionary = {}
	var start_roster_procs: Dictionary = {}
	var state: Dictionary = {}
	var observation_start: float = opening_time+warmup
	b.contact_accepted.connect(func(a: int, c: int) -> void:
		if a != 1 and c != 1: return
		var enemy: Dictionary = b.entity(c if a == 1 else a)
		if enemy.is_empty(): return
		if row.has("handoff"): row.mature_contacts += 1
		row.contacts.append({"time":b.elapsed,"entity":enemy.entity_id,"kind":enemy.get("enemy_kind","swarm"),"role":enemy.get("role","swarm"),"small":enemy.combatant_type == "small_top","radius":Vector2(p.pos).length()})
	)
	b.full_top_impact_accepted.connect(func(event: Dictionary) -> void:
		if int(event.first_entity_id) != 1 and int(event.second_entity_id) != 1: return
		var e: Dictionary = event.duplicate(true)
		var player_first: bool = int(event.first_entity_id) == 1
		var enemy: Dictionary = b.entity(int(event.second_entity_id if player_first else event.first_entity_id))
		e["enemy_kind"] = enemy.get("enemy_kind","")
		e["enemy_role"] = enemy.get("role","")
		e["player_effective_mass"] = event.first_effective_mass if player_first else event.second_effective_mass
		e["player_rpm"] = p.rpm
		e["player_wobble"] = p.wobble
		e["player_radius"] = Vector2(p.pos).length()
		e["power_state"] = public_power_state(p)
		if row.has("handoff") and float(event.severity) >= 0.75: row.mature_heavy_contacts += 1
		row.full_impacts.append(e)
	)
	while b.battle_status == "battle" and b.elapsed < observation_start+horizon and tick < int((warmup+horizon)*120.0):
		if not started and b.elapsed >= observation_start:
			started = true
			start_economy = b.continuous.economy.snapshot()
			start_power_procs = b.powers.counters.duplicate()
			start_defence_procs = b.powers.defence.counters.duplicate()
			start_roster_procs = b.roster.counters.duplicate()
			row["handoff"] = {"time":b.elapsed,"rpm":p.rpm,"wobble":p.wobble,"position":p.pos,"velocity":p.vel,"power_state":public_power_state(p),"director":b.continuous.snapshot(),"economy":start_economy.duplicate(true),"battle":b.snapshot(),"power_runtime":b.powers._states.duplicate(true),"defence_runtime":b.powers.defence.states.duplicate(true),"roster_runtime":b.roster.states.duplicate(true),"rng":random_state(b)}
		var c: Dictionary = controls(b,policy if started else "warmup",tick,state)
		var time_before: float = b.elapsed
		b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		var dt: float = b.elapsed-time_before
		var radius: float = Vector2(p.pos).length()
		var census: Dictionary = b.continuous.census()
		if started:
			row.mature_minimum_rpm = minf(float(row.mature_minimum_rpm),float(p.rpm))
			if float(p.rpm) >= 0.75: row.mature_above_75_seconds += dt
			if float(p.rpm) >= 0.50: row.mature_above_50_seconds += dt
			if Vector2(c.direction).length() > 0.01: row.input_seconds += dt
			if c.brake: row.brake_seconds += dt
			if radius <= 58.0: row.centre_seconds += dt
			if b.continuous.director.draining: row.drain_seconds += dt
			row.peak_radius = maxf(row.peak_radius,radius)
			row.radius_integral += radius*dt
			row.wobble_integral += float(p.wobble)*dt
			row.mass_integral += float(b.update_readings.get("effective_mass",p.mass))*dt
			row.collision_scale_integral += float(b.update_readings.get("incoming_rpm_scale",1.0))*dt
			row.wobble_removed += float(b.update_readings.get("wobble_removed_in_update",0.0)) if dt > 0.0 else 0.0
			row.control_modes[c.mode] = float(row.control_modes.get(c.mode,0.0))+dt
			row.peak_full = maxi(row.peak_full,int(census.active_full))
			row.peak_small = maxi(row.peak_small,b.swarm.active_count())
		row.finite = row.finite and Vector2(p.pos).is_finite() and Vector2(p.vel).is_finite() and is_finite(float(p.rpm))
		if b.elapsed >= next_trace or b.battle_status == "finished":
			row.trace.append({"time":b.elapsed,"phase":"mature" if started else "common_warmup","rpm":p.rpm,"wobble":p.wobble,"radius":radius,"speed":Vector2(p.vel).length(),"census":census,"tier":b.continuous.director.tier_at(b.elapsed),"draining":b.continuous.director.draining,"powers":public_power_state(p),"update":b.update_readings.duplicate(),"direction":[c.direction.x,c.direction.y],"brake":c.brake,"mode":c.mode,"losses":b.continuous.economy.losses.duplicate(),"gains":b.continuous.economy.gains.duplicate()})
			next_trace += trace_interval
		tick += 1
	var economy: Dictionary = b.continuous.economy.snapshot()
	var duration: float = maxf(0.0,b.elapsed-observation_start)
	row.merge({"run_seconds":b.elapsed,"mature_seconds":duration,"mature_handoff_reached":started,"reason":b.last_result.get("reason","observation_horizon"),"ended_naturally":b.battle_status == "finished","final_rpm":p.rpm,"final_wobble":p.wobble,"final_radius":Vector2(p.pos).length(),"minimum_rpm_whole_run":economy.minimum_rpm,"whole_run_economy":economy,"mature_losses":difference(economy.losses,start_economy.get("losses",{})) if started else {},"mature_gains":difference(economy.gains,start_economy.get("gains",{})) if started else {},"power_procs":difference(b.powers.counters,start_power_procs) if started else b.powers.counters.duplicate(),"defence_procs":difference(b.powers.defence.counters,start_defence_procs) if started else b.powers.defence.counters.duplicate(),"roster_procs":difference(b.roster.counters,start_roster_procs) if started else b.roster.counters.duplicate(),"final_power_diagnostics":b.powers.diagnostics(p),"final_power_state":public_power_state(p),"final_defence_state":b.powers.defence.diagnostics(p),"director_history":b.continuous.director.history.duplicate(true),"simulation_ticks":tick,"mean_radius":float(row.radius_integral)/duration if duration > 0 else 0.0,"mean_wobble":float(row.wobble_integral)/duration if duration > 0 else 0.0,"mean_effective_mass":float(row.mass_integral)/duration if duration > 0 else p.mass,"mean_incoming_rpm_scale":float(row.collision_scale_integral)/duration if duration > 0 else 1.0})
	print("BASTION_STUDY seed=%d starter=%s stage=%s policy=%s run=%.2f mature=%.2f reason=%s rpm=%.4f contacts=%d heavy=%d radius=%.2f" % [seed_value,starter,stage,policy,b.elapsed,duration,row.reason,p.rpm,row.mature_contacts,row.mature_heavy_contacts,row.peak_radius])
	b.free()
	return row

func write_report() -> bool:
	var report: Dictionary = {"schema":"003a1-dead-centre-physical-stress-study-v3","fixture_family_cap":PowerGuide.FAMILY_CAP,"legal_family_cap_enforced":true,"human_afk_fixture":{"input_stopped_seconds":504,"run_ended_seconds":833,"literal_afk_seconds":329,"exact_human_build_recovered":false},"scope":"Declared invested centre opening followed by real production physics/Director throughout; identical sampled public-state stress-aware defensive controls for warmup, then paired no-input or modest public-state defensive policy. No clocks/RPM reset, forces, gains, losses, enemy admissions or outcomes edited during observed ticks.","opening_mode":"synthetic_mature_pressure_context" if opening_time > 0.0 else "natural_run_common_warmup","opening_clock_seconds":opening_time,"source_label":source_label,"warmup_seconds":warmup,"mature_horizon_seconds":horizon,"trace_interval":trace_interval,"handling_override":handling_override,"policy":{"sample_seconds":0.25,"correction_magnitude":0.24,"correction_on_seconds":0.75,"correction_period":2.0,"continuous_correction_outside_radius":8.0,"brake_max_seconds":0.25,"brake_cooldown_seconds":6.0,"recharge_outward_magnitude":0.55,"recharge_radius":91.0,"recharge_rotation_magnitude":0.55,"reestablish_magnitude":0.40,"short_release_magnitude":0.45,"short_release_radius":45.0,"boundary_correction_radius":138.0,"boundary_brake":"Outward speed above25 or total speed above110","stress_release_threshold":0.55,"stress_return_threshold":0.12,"burst":"Redline outward release only, sampled eighteen-second window","enemy_targeting":false},"samples":samples}
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	return true

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
		if arg.begins_with("--label="): source_label = arg.trim_prefix("--label=")
		if arg.begins_with("--horizon="): horizon = clampf(float(arg.trim_prefix("--horizon=")),1.0,1200.0)
		if arg.begins_with("--warmup="): warmup = clampf(float(arg.trim_prefix("--warmup=")),0.0,720.0)
		if arg.begins_with("--opening-time="): opening_time = clampf(float(arg.trim_prefix("--opening-time=")),0.0,720.0)
		if arg.begins_with("--seed="): seeds = [int(arg.trim_prefix("--seed="))]
		if arg.begins_with("--stage="): stages.assign(arg.trim_prefix("--stage=").split(","))
		if arg.begins_with("--starter="): starters.assign(arg.trim_prefix("--starter=").split(","))
		if arg.begins_with("--policy="): policies.assign(arg.trim_prefix("--policy=").split(","))
		if arg.begins_with("--investments="): investments = clampi(int(arg.trim_prefix("--investments=")),1,21)
		if arg.begins_with("--handling="):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--handling=")))
			if parsed is Dictionary: handling_override = parsed
	if output.is_empty() or not output.is_absolute_path(): push_error("Explicit external report path required"); quit(2); return
	if FileAccess.file_exists(output): push_error("Refusing to overwrite preserved study report"); quit(2); return
	for stage: String in stages:
		if not STAGES.has(stage): push_error("Unknown stage: "+stage); quit(2); return
	for policy: String in policies:
		if policy not in ["zero_input","minimal_active","legacy_active","recharge_only","legacy_warmup"]: push_error("Unknown policy: "+policy); quit(2); return
	for starter: String in starters:
		for stage: String in stages:
			for seed_value: int in seeds:
				for policy: String in policies:
					samples.append(observation(seed_value,starter,stage,policy))
					if not write_report(): push_error("Cannot write external report"); quit(2); return
	quit(0)
