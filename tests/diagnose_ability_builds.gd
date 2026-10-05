extends SceneTree
## Deterministic controlled starting investments, genuine full-spin launch,
## real director/AI/physics/economy and input only thereafter. This supplements
## ordinary draft runs; it does not claim these starting builds were earned.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const PROFILES: Dictionary = {
	"overclock": {"starter":"breaker", "powers":["redline","high_gear","predator_line","impact_wake"], "ranks":{"redline":3,"high_gear":2,"predator_line":2,"impact_wake":2}, "mutations":{"redline":"runaway"}},
	"breakneck": {"starter":"breaker", "powers":["redline","iron_comet","impact_wake"], "ranks":{"redline":3,"iron_comet":2,"impact_wake":2}, "mutations":{"redline":"breakneck"}},
	"speed": {"starter":"vane", "powers":["high_gear","orbit_drive","afterimage"], "ranks":{"high_gear":3,"orbit_drive":2,"afterimage":2}, "mutations":{"high_gear":"terminal_velocity"}},
	"defence": {"starter":"bastion", "powers":["dead_centre","crash_guard","clutch","momentum_bank"], "ranks":{"dead_centre":3,"crash_guard":2,"clutch":2,"momentum_bank":2}, "mutations":{"dead_centre":"counterweight"}},
	"route": {"starter":"vane", "powers":["afterimage","high_gear","orbit_drive","crash_guard"], "ranks":{"afterimage":3,"high_gear":2,"orbit_drive":2,"crash_guard":2}, "mutations":{"afterimage":"ghost_circuit"}},
	"impact": {"starter":"breaker", "powers":["iron_comet","impact_wake","chain_impact","crosscut"], "ranks":{"iron_comet":2,"impact_wake":2,"chain_impact":2,"crosscut":2}, "mutations":{}},
	"comeback": {"starter":"bastion", "powers":["clutch"], "ranks":{"clutch":2}, "mutations":{}},
	"hybrid": {"starter":"vane", "powers":["high_gear","orbit_drive","momentum_bank","dead_centre","crosscut"], "ranks":{"high_gear":3,"orbit_drive":2,"momentum_bank":2,"dead_centre":2,"crosscut":2}, "mutations":{"high_gear":"flow_state"}}
}
var runs: Array[Dictionary] = []
var ceiling: float = 220.0

func _initialize() -> void: call_deferred("run")
func screen_direction(world: Vector2) -> Vector2:
	if world.length() <= 0.001: return Vector2.ZERO
	return Vector2(world.x-world.y, (world.x+world.y)*0.5).normalized()*minf(1.0, world.length())

func curve_control(b: Node2D, radius: float = 85.0) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var angle: float = Vector2(p.pos).angle()
	var goal: Vector2 = Vector2.RIGHT.rotated(angle + 0.65)*radius
	var desired: Vector2 = (goal-Vector2(p.pos))*5.0-Vector2(p.vel)*0.6
	return {"direction":screen_direction(desired.normalized()*0.82),"burst":false,"brake":false}

func controls(b: Node2D, profile: String, tick: int, progress: Dictionary) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var target: Dictionary = b._target_for(p)
	var c: Dictionary = Bot.input(b,"aggressive",tick)
	if profile == "defence":
		c = Bot.input(b,"defensive",tick)
		c.direction = Vector2(c.direction).normalized()*0.24
		c.burst = float(p.get("stored_force",0.0)) >= 45.0 and not target.is_empty() and Vector2(p.pos).distance_to(target.pos) < 90.0 and float(p.cooldown) <= 0.0
	elif profile in ["route","speed"]:
		c = curve_control(b)
		if profile == "speed": c.burst = float(p.cooldown) <= 0.0 and fmod(b.elapsed,12.0) < 0.20
	elif profile == "impact":
		# Deliberately bank on the closed east/west wall, then use the earned
		# charge in normal combat. This never changes position or enemy state.
		if float(p.iron_comet_time) <= 0.0 and fmod(b.elapsed,9.0) < 2.3:
			var goal: Vector2 = Vector2(165.0 if float(p.pos.x) >= 0.0 else -165.0, 20.0)
			c.direction = screen_direction((goal-Vector2(p.pos)).normalized()*0.92)
			c.brake = false
			c.burst = float(p.cooldown) <= 0.0
	elif profile == "comeback":
		if float(p.rpm) <= 0.28 and float(progress.danger_at) < 0.0: progress.danger_at = b.elapsed
		if float(progress.danger_at) < 0.0:
			# Waste spin by riding the brake and correcting weakly. Weak input
			# cannot reclaim normal contacts. Danger is genuinely earned.
			c.direction = screen_direction((-Vector2(p.pos)-Vector2(p.vel)*0.4).normalized()*0.06)
			c.brake = true
			c.burst = false
		else:
			c = Bot.input(b,"aggressive",tick)
			if float(p.rpm) > float(progress.recovery_peak): progress.recovery_peak = p.rpm
	elif profile == "hybrid":
		var phase: float = fmod(b.elapsed,12.0)
		if phase < 0.8:
			c = curve_control(b,80.0)
			c.brake = Vector2(p.vel).length() >= 100.0
		elif phase < 1.6:
			c.direction = screen_direction(Vector2(p.vel).normalized()*0.24)
			c.brake = true
			c.burst = false
		elif phase < 4.0:
			c = Bot.input(b,"defensive",tick)
			c.direction = Vector2(c.direction).normalized()*0.24
			c.brake = Vector2(p.vel).length() > 65.0
		else:
			c = Bot.input(b,"aggressive",tick)
			c.burst = float(p.cooldown) <= 0.0 and (float(p.get("momentum_charge",0.0)) >= 30.0 or bool(c.burst))
	elif profile == "breakneck":
		# Alternate deliberately committed target pursuit with a risky early
		# point-forward strike. Misses remain genuine solver outcomes.
		if b.powers.redline_active(p) and float(p.cooldown) <= 0.0:
			c.burst = true
			if int(progress.strike_cycles)%2 == 0:
				c.direction = screen_direction(Vector2.RIGHT.rotated(b.elapsed*0.47)*0.92)
			progress.strike_cycles += 1
	# Normal correction tries to steer inward; it provides no gate immunity.
	if Vector2(p.pos).length() > 145.0 and profile != "impact":
		c.direction = screen_direction(-Vector2(p.pos).normalized()*0.80)
		c.brake = profile not in ["overclock","breakneck"]
	return c

func simulate(profile: String, seed_value: int) -> Dictionary:
	var config: Dictionary = PROFILES[profile]
	var b: Node2D = Battle.new()
	root.add_child(b)
	b.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1,seed_value)
	descriptor.starter_id = config.starter
	descriptor.player_power_ids = config.powers.duplicate()
	descriptor.player_power_ranks = config.ranks.duplicate()
	descriptor.player_power_mutations = config.mutations.duplicate()
	b.begin_run(Starters.build_for(config.starter),descriptor,seed_value)
	b.battle_status = "battle"
	b.particles_enabled = false
	var identity: Dictionary = b.player_entity()
	var progress: Dictionary = {"danger_at":-1.0,"recovery_peak":0.0,"strike_cycles":0}
	var peak_entities: int = b.fighters.size()
	var preview_seconds: float = 0.0
	var peak_traces: int = 0
	var danger_contacts: Array[Dictionary] = []
	b.contact_accepted.connect(func(first: int, second: int) -> void:
		if profile != "comeback" or int(identity.entity_id) not in [first, second] or float(identity.get("clutch_time",0.0)) <= 0.0 or danger_contacts.size() >= 20: return
		var state: Dictionary = b.powers._state(identity)
		danger_contacts.append({"time":b.elapsed,"approach_rpm":state.motion_rpm,"after_rpm":identity.rpm,"speed":state.motion_speed,"severity":identity.impact_strength,"input":state.motion_input,"clutch_active":identity.clutch_active,"tokens":b.continuous.economy.tokens}))
	var c: Dictionary = {"direction":Vector2.ZERO,"burst":false,"brake":false}
	for tick: int in range(int(ceiling*80.0)):
		if b.elapsed >= ceiling or b.battle_status == "finished": break
		if tick%6 == 0: c = controls(b,profile,tick,progress)
		else: c.burst = false
		var before: float = b.elapsed
		b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		assert(is_same(identity,b.player_entity()),"Diagnostic inputs cannot relaunch the player")
		peak_entities = maxi(peak_entities,b.fighters.size())
		peak_traces = maxi(peak_traces,b.powers.traces.size())
		if not identity.get("ghost_preview",{}).is_empty(): preview_seconds += b.elapsed-before
	var economy: Dictionary = b.continuous.economy.snapshot()
	var loss: float = 0.0
	for value: float in economy.losses.values(): loss += value
	var row: Dictionary = {"profile":profile,"seed":seed_value,"starter":config.starter,"starting_powers":config.powers,"starting_ranks":config.ranks,"starting_mutations":config.mutations,"seconds":b.elapsed,"reason":b.last_result.get("reason","diagnostic_ceiling"),"rpm":identity.rpm,"minimum_rpm":economy.minimum_rpm,"danger_at":progress.danger_at,"recovery_peak_after_danger":progress.recovery_peak,"power_procs":b.powers.counters.duplicate(),"redline":b.powers.diagnostics(identity),"roster":b.roster.diagnostics(identity),"director":b.continuous.snapshot(),"economy":economy,"peak_entities":peak_entities,"peak_traces":peak_traces,"ghost_preview_seconds":preview_seconds,"accounting_error":absf(1.0+float(economy.total_recovered)-loss-float(identity.rpm))}
	assert(float(row.accounting_error) < 0.000001,"Controlled build still obeys the real RPM ledger")
	row["danger_contacts"] = danger_contacts
	b.free()
	return row

func run() -> void:
	var profiles: Array = PROFILES.keys()
	var seeds: Array = [421,7341]
	var output: String = "user://task002c5-builds.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--profiles="): profiles = Array(arg.trim_prefix("--profiles=").split(","))
		if arg.begins_with("--ceiling="): ceiling = float(arg.trim_prefix("--ceiling="))
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
		if arg == "--quick": seeds = [421]
	for profile: String in profiles:
		for seed_value: int in seeds:
			var row: Dictionary = simulate(profile,seed_value)
			runs.append(row)
			var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
			file.store_string(JSON.stringify({"scope":"Controlled starting investments, genuine full-RPM launch, real continuous director/AI/economy; only inputs thereafter. No earned-draft claim, no loss protection, no injected proc or outcomes. Diagnostic ceilings are not game limits.","runs":runs},"\t"))
			file.close()
			print("ABILITY_BUILD %s seed=%d %.2fs %s rpm=%.3f min=%.3f overcap=%.2fs circuits=%d clutch=%d drift=%.2fs breakneck_hits=%d misses=%d" % [profile,seed_value,row.seconds,row.reason,row.rpm,row.minimum_rpm,float(row.redline.overcap_seconds),int(row.power_procs.get("ghost_closure",0)),int(row.power_procs.get("clutch_recover",0)),float(row.roster.drift_seconds),int(row.power_procs.get("breakneck_impact",0)),int(row.redline.failed_commitments)])
	print("ABILITY_BUILD_DONE samples=",runs.size())
	quit()
