extends "res://tests/observe_dead_centre_stress.gd"
## Preserve the accepted fortress physics while verifying shared reserve pressure
## and the revised physical Stress / deliberate recovery loop.
## Mature observations use real fixed ticks/ledgers, with no death deadline.
const Economy = preload("res://scripts/spin_economy.gd")
const Runtime = preload("res://scripts/power_runtime.gd")
const Powers = preload("res://scripts/run_powers.gd")
const EXPECTED_PROFILES: Dictionary = {
	"breaker":{"acceleration":1.32,"speed":1.20,"mass":1.0,"impact":1.30,"spin_drain":1.0,"orbit":1.5,"bank":0.85,"recovery":1.0},
	"bastion":{"acceleration":0.72,"speed":0.78,"mass":1.35,"impact":1.0,"spin_drain":1.0,"orbit":0.25,"bank":1.35,"recovery":1.3},
	"vane":{"acceleration":1.18,"speed":1.12,"mass":0.94,"impact":1.05,"spin_drain":0.82,"orbit":1.6,"bank":1.0,"recovery":1.15}
}
var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func total(values: Dictionary) -> float:
	var result: float = 0.0
	for value: float in values.values(): result += value
	return result

func normalized(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func pack(p: Dictionary) -> Dictionary:
	return {"pos":[p.pos.x,p.pos.y],"vel":[p.vel.x,p.vel.y],"rpm":p.rpm,"wobble":p.wobble,"mass":p.mass,"radius":p.radius}

func identity_and_costs() -> void:
	check(Starters.HANDLING == EXPECTED_PROFILES,"Accepted physical handling and starter identities remain exact under shared economy tuning")
	check(Starters.build_for("bastion") == {"blade":"guard","ratchet":"low","bit":"ball"},"The authored fortress remains Guard / Low / Ball")
	var b: Node2D = make_battle(421,"bastion","stock")
	var p: Dictionary = b.player_entity()
	var e: RefCounted = b.continuous.economy
	var base: float = maxf(Economy.TUNING.passive_floor,Economy.TUNING.passive_base-float(p.stats.stamina)*Economy.TUNING.stamina_credit)
	# Explicit unit reserve resets isolate cost arithmetic, not survival evidence.
	p.rpm = 0.8
	e.running_costs(p,0.0,Vector2.ZERO,false,1.0,1.0)
	check(is_equal_approx(0.8-float(p.rpm),base),"Idle Bastion pays the normal stamina-based passive cost without a starter discount")
	var passive_before: float = e.losses.passive
	p.rpm = 0.8
	b.continuous.observe_input(0.4,Vector2(0.24,0))
	e.running_costs(p,0.0,Vector2(0.24,0),false,1.0,1.0)
	check(is_equal_approx(float(e.losses.passive)-passive_before,base),"Deliberate control leaves the same passive cost; activity is not a hidden drain switch")
	check(e.losses.keys() == ["passive","movement","burst","braking","powers","redline","collisions","walls","wobble","steering"],"The existing physical loss ledger separates Redline spending and has no AFK penalty")
	measurements.normal_cost = {"passive_per_second":base,"handling":p.handling.duplicate(true),"assembly":p.build.duplicate(true)}
	b.free()

func neutral_parts_retention() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parts_legacy_002c5_1.json"))
	var expected: Dictionary = {}
	for row: Dictionary in fixture.assemblies:
		if row.build == Starters.build_for("bastion"): expected = row; break
	check(not expected.is_empty(),"The immutable parent fixture includes the exact Guard / Low / Ball assembly")
	var b: Node2D = Battle.new(); root.add_child(b); b.set_physics_process(false)
	b.begin(Starters.build_for("bastion"),{"blade":"guard","ratchet":"mid","bit":"ball"},1,421)
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity(); var enemy: Dictionary = b.entity(2)
	check(p.handling.is_empty(),"Neutral Guard / Low / Ball retains catalogue physics without a starter layer")
	check(normalized(Parts.derive(p.build)) == normalized(expected.stats),"Original defensive part ratings remain exact")
	p.pos = Vector2(-10,0); p.vel = Vector2(160,50); p.rpm = 0.8; p.wobble = 0.1
	enemy.pos = Vector2(10,0); enemy.vel = Vector2(-60,-10); enemy.rpm = 0.8; enemy.wobble = 0.1
	b.resolve_pair(1,2)
	var contact: Dictionary = {"player":pack(p),"enemy":pack(enemy),"hits":b.hits}
	check(normalized(contact) == normalized(expected.contact),"Neutral Guard / Low / Ball retains the frozen real contact response")
	p.pos = Vector2(170,50); p.vel = Vector2(300,50); p.rpm = 0.8; p.wobble = 0.1
	b._resolve_boundary(p)
	check(normalized(pack(p)) == normalized(expected.wall),"Neutral Guard / Low / Ball retains the frozen wall response")
	measurements.neutral_parts = {"fixture_source":fixture.source_sha,"stats":expected.stats,"contact":contact,"wall":pack(p)}
	b.free()

func paired_attrition() -> void:
	warmup = 504.0; horizon = 329.0; opening_time = 0.0
	var afk: Dictionary = observation(421,"bastion","legacy_bulwark","zero_input")
	var active: Dictionary = observation(421,"bastion","legacy_bulwark","minimal_active")
	check(afk.mature_handoff_reached and active.mature_handoff_reached,"Both declared invested fixtures reach mature pressure through every real warmup tick")
	check(afk.handoff == active.handoff,"Seed, fighters, power states, ledgers, Director and RNG agree exactly before paired input policies diverge")
	check(afk.input_seconds == 0.0 and afk.brake_seconds == 0.0 and afk.control_modes.keys() == ["hands_off"],"The five-minute no-input policy supplies literally zero controls")
	check(afk.finite and active.finite,"Both live mature-pressure observations retain finite physics")
	for row: Dictionary in [afk,active]:
		var net: float = float(row.final_rpm)-float(row.handoff.rpm)
		check(absf(net-(total(row.mature_gains)-total(row.mature_losses))) < 0.00001,"The mature %s reserve change closes through named production gains and losses" % row.policy)
		check(float(row.mature_losses.passive) > 0.0 and float(row.mature_losses.collisions) > 0.0,"Actual %s pressure spends both passive and contact reserve" % row.policy)
		check(row.mature_contacts > 30 and row.mature_heavy_contacts > 0,"The %s observation receives genuine repeated mature and heavy contacts" % row.policy)
		check(row.peak_full <= 5 and row.peak_small <= 10,"The %s study keeps accepted Director population caps" % row.policy)
		var bounded_controls: bool = true
		for trace: Dictionary in row.trace:
			if trace.phase != "mature": continue
			var magnitude: float = Vector2(trace.direction[0],trace.direction[1]).length()
			bounded_controls = bounded_controls and magnitude <= 0.550001
			if row.policy == "zero_input": bounded_controls = bounded_controls and magnitude == 0.0 and not trace.brake
		check(bounded_controls,"The %s recorded policy supplies only its declared zero/modest control magnitudes" % row.policy)
	check(float(afk.final_rpm) < float(afk.handoff.rpm)-0.30,"Zero input loses a meaningful reserve fraction under five-minute mature pressure")
	check(afk.ended_naturally or afk.mature_seconds >= 300.0,"The no-input observation ends naturally or records the complete five-minute window")
	var late_reserve: float = float(afk.final_rpm)
	for trace: Dictionary in afk.trace:
		if trace.phase == "mature" and float(trace.time) >= float(afk.run_seconds)-120.0:
			late_reserve = float(trace.rpm); break
	check(afk.ended_naturally or float(afk.final_rpm) < late_reserve-0.05,"The surviving hands-off fortress still loses reserve in the final two-minute window instead of reaching a plateau")
	check(float(afk.mature_gains.get("dead_centre",0.0)) <= float(afk.handoff.power_state.anchor_recovery_remaining)+0.00001,"A hands-off hold cannot mint another finite Dead Centre quota")
	# Genuine warmup controls may retain the accepted three-second eligibility
	# window. Never clear that state to manufacture a stricter no-input result.
	var expired_window: Dictionary = {}
	for trace: Dictionary in afk.trace:
		if trace.phase == "mature" and float(trace.time) > float(afk.handoff.time)+3.0:
			expired_window = trace; break
	check(not expired_window.is_empty(),"The real no-input trace includes observations after warmup participation expires")
	for source: String in ["combat_reclamation","elimination","elite","boss"]:
		var late_gain: float = float(afk.whole_run_economy.gains.get(source,0.0))-float(expired_window.get("gains",{}).get(source,0.0))
		check(late_gain == 0.0,"No-input physical defence cannot renew %s RPM after the genuine warmup control window" % source)
	# Both policies may end in spin-out. Compare reserve on their last exact
	# shared living trace, retaining the original benefit instead of comparing
	# two physical terminal thresholds as though they were the same-time state.
	var shared_active: Dictionary={}
	var shared_afk: Dictionary={}
	var afk_trace_times: Dictionary={}
	for trace: Dictionary in afk.trace:
		if trace.phase=="mature" and (not afk.ended_naturally or float(trace.time)<float(afk.run_seconds)):afk_trace_times[trace.time]=trace
	for trace: Dictionary in active.trace:
		if trace.phase=="mature" and (not active.ended_naturally or float(trace.time)<float(active.run_seconds)) and afk_trace_times.has(trace.time):shared_active=trace;shared_afk=afk_trace_times[trace.time]
	check(not shared_active.is_empty() and float(shared_active.rpm)>float(shared_afk.get("rpm",1.0))+.30 and active.mature_seconds>=afk.mature_seconds,"Modest actual defence retains the original reserve benefit at an exact shared living timestamp")
	measurements.shared_living_comparison={"active":shared_active,"hands_off":shared_afk,"preserved_reserve_advantage":.30}
	# The newly longer vent/rearm window intentionally requires actual movement.
	# Keep the original quiet-defence duty cap instead of silently weakening it
	# to allow near-continuous input; account that active recovery separately.
	var recovery_seconds: float = 0.0
	# Incoming denial can send the real actor to the rim. The unchanged bot's
	# sampled boundary_correction is an inward safety return, not centre holding.
	for mode: String in ["short_release_vent","leave_centre","outside_recharge","reestablish_centre","boundary_correction"]:
		recovery_seconds += float(active.control_modes.get(mode,0.0))
	var holding_seconds: float = maxf(0.0,float(active.mature_seconds)-recovery_seconds)
	var holding_input_seconds: float = maxf(0.0,float(active.input_seconds)-recovery_seconds)
	check(float(active.input_seconds) > 0.0 and float(active.input_seconds) < float(active.mature_seconds) and holding_seconds > 0.0 and holding_input_seconds < holding_seconds*0.75,"Minimal centre defence stays intermittent; required vent/rearm motion is accounted separately")
	measurements.control_duty = {"total_input_seconds":active.input_seconds,"observed_seconds":active.mature_seconds,"recovery_movement_seconds":recovery_seconds,"safety_return_seconds":active.control_modes.get("boundary_correction",0.0),"centre_hold_seconds":holding_seconds,"centre_hold_input_seconds":holding_input_seconds,"centre_hold_input_fraction":holding_input_seconds/holding_seconds,"preserved_nonrecovery_duty_cap":0.75}
	check(float(active.mature_gains.get("elimination",0.0))+float(active.mature_gains.get("elite",0.0))+float(active.mature_gains.get("boss",0.0)) > 0.0,"Active defence earns legitimate attributed elimination recovery without a guaranteed kill amount")
	# Real denial/pressure can require longer outside recovery. Total occupancy
	# is not a guaranteed percentage; require the actual paid physical cycle
	# back to connected central ground without weakening the hold-duty contract.
	var rearm_exit: Dictionary={}
	var rearm_return: Dictionary={}
	var reconnected_hold: Dictionary={}
	var maximum_sampled_progress: float=0.0
	for trace: Dictionary in active.trace:
		if trace.phase!="mature":continue
		maximum_sampled_progress=maxf(maximum_sampled_progress,float(trace.powers.anchor_rearm_progress))
		if rearm_exit.is_empty() and trace.mode=="outside_recharge" and float(trace.radius)>=Runtime.ANCHOR_REARM_RADIUS and float(trace.powers.anchor_rearm_progress)>0.0 and Vector2(trace.direction[0],trace.direction[1]).length()>=.35 and float(trace.speed)>=35.0:
			rearm_exit=trace.duplicate(true)
		elif not rearm_exit.is_empty() and rearm_return.is_empty() and trace.mode=="reestablish_centre" and float(trace.powers.anchor_recovery_remaining)>float(rearm_exit.powers.anchor_recovery_remaining):
			rearm_return=trace.duplicate(true)
		elif not rearm_return.is_empty() and reconnected_hold.is_empty() and trace.mode in ["rest","small_correction","brief_brake"] and float(trace.radius)<=Runtime.ANCHOR_RECOVERY_RADIUS and bool(trace.powers.anchor_central_hold) and float(trace.powers.anchor_strength)>0.0:
			reconnected_hold=trace.duplicate(true)
	var completed: bool=not rearm_exit.is_empty() and not rearm_return.is_empty() and not reconnected_hold.is_empty()
	var interrupted: bool=not completed and not rearm_exit.is_empty() and maximum_sampled_progress>0.0 and active.ended_naturally and active.reason in ["spin_out","ring_out"]
	check(completed or interrupted,"Paid observed rearm/return either reconnects central ground or is honestly interrupted by an actual physical defeat")
	measurements.centre_recovery_cycle={"status":"completed" if completed else ("physical_defeat_interrupted" if interrupted else "unproven"),"maximum_sampled_rearm_progress":maximum_sampled_progress,"outside_rearm":rearm_exit,"paid_quota_return":rearm_return,"reconnected_central_hold":reconnected_hold,"physical_outcome":active.reason,"total_centre_seconds":active.centre_seconds,"total_observed_seconds":active.mature_seconds,"guaranteed_occupancy_percentage":false,"capability_scope":"Exact six-second/radius/quota/reconnection semantics are tested independently; this natural-pressure observation never grants completion from ownership."}
	check(float(afk.final_power_diagnostics.anchor_stress_peak) >= 0.80,"Real incoming and outgoing work overloads the unattended anchor")
	check(float(active.final_power_diagnostics.anchor_stress_vented) > float(active.handoff.power_runtime[1].anchor_stress_vented),"Actual controlled release vents Stress beyond the shared warmup state")
	check(float(active.final_power_diagnostics.anchor_stress_peak) < float(afk.final_power_diagnostics.anchor_stress_peak),"Managing the same physical mechanism limits active Stress compared with AFK")
	measurements.paired = [afk,active]

func preserved_reload_contract() -> void:
	check(Runtime.ANCHOR_REARM_RADIUS == 82.0 and Runtime.ANCHOR_REARM_SECONDS == 6.0,"Dead Centre preserves its outside radius and requires six seconds of deliberate movement to reload")
	var description: String = str(Powers.DEFINITIONS.dead_centre.description).to_lower()
	check(description.contains("stress") and description.contains("vent") and description.contains("reload"),"Player-visible Dead Centre instructions explain physical Stress, deliberate venting and finite reload")
	# Semantic quota/contact/rearm mechanics are exercised by current
	# test_power_feedback and test_anchor_rearm_003a1; this records a real pair.

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
	if output.is_empty() or not output.is_absolute_path() or FileAccess.file_exists(output):
		push_error("A fresh explicit external report is required"); quit(2); return
	identity_and_costs()
	neutral_parts_retention()
	paired_attrition()
	preserved_reload_contract()
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	check(file != null,"The isolated hotfix contract report can be preserved")
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"One exact real mature-pressure paired regression plus untouched physical catalogue and cost contracts. No mandatory death time or universal seed guarantee.","measurements":measurements},"\t")); file.close()
	print("BASTION_ACTIVE_DEFENCE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
