extends SceneTree
## Declared initial actor admissions/positions isolate reaction sampling. All
## reserve, Burst, cooldown and movement updates use the actual Run solver.
## No damage, reserve, charge or outcomes are assigned by this fixture.
const Battle = preload("res://scripts/battle.gd")
const Run = preload("res://scripts/run_context.gd")
const Roles = preload("res://scripts/enemy_roles.gd")
const BUILD: Dictionary = {"blade":"guard","ratchet":"low","bit":"ball"}
const OWNER_ID: int = 4
const FIXED_TICKS_TO_REACTION: int = 23

class SamplingBattle extends "res://scripts/battle.gd":
	var activation: Dictionary = {}
	var observation: Dictionary = {}
	func _update_ai(rival: Dictionary, dt: float, context: Dictionary = {}) -> void:
		var sampled: bool = rival.has("role") and float(rival.ai_clock)-dt <= 0.0
		var remaining: float = float(rival.burst_time)
		super._update_ai(rival,dt,context)
		if int(rival.entity_id) != 4 or not sampled: return
		if activation.is_empty():
			# A single initial input request is delivered at the real decision
			# boundary, before this same fixed tick integrates movement. The
			# method pays ordinary reserve and sets the ordinary four-second gate.
			var reserve: float = float(rival.rpm)
			var deadline: float = float(rival.pilot.power_control.burst_ready)
			_attempt_burst(rival,Vector2.LEFT)
			activation = {"time":elapsed,"reserve_before":reserve,"reserve_after":float(rival.rpm),
				"remaining":float(rival.burst_time),"cooldown":float(rival.cooldown),
				"decision_interval":float(rival.ai_clock),"budget_was_unset":is_inf(deadline),
				"position":Vector2(rival.pos),"velocity":Vector2(rival.vel)}
		elif observation.is_empty():
			var deadline: float = float(rival.pilot.power_control.burst_ready)
			var last_seen: float = float(rival.pilot.power_control.last_burst_seen)
			observation = {"time":elapsed,"remaining_before_movement":remaining,
				"budget_set":not is_inf(deadline),"budget_deadline":deadline if not is_inf(deadline) else "unset",
				"last_burst_seen":last_seen if not is_inf(last_seen) else "unset",
				"position":Vector2(rival.pos),"velocity":Vector2(rival.vel),"reserve":float(rival.rpm)}

var checks: int = 0
var failures: Array[String] = []
var report: String = ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = portable(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(portable(item))
		return result
	return value

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	if not report.is_empty() and (not report.is_absolute_path() or FileAccess.file_exists(report) or not (report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/") or report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/"))):
		push_error("A fresh external QA report is required"); quit(2); return
	var context = Run.new()
	context.start(BUILD,421,"bastion")
	var battle := SamplingBattle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.begin_run(BUILD,context.current_encounter(),context.run_seed)
	# Starting scenario coordinates only. Countdown, launch and every subsequent
	# actor update remain normal; these positions are never written again.
	battle.player_entity().pos = Vector2(-80,60)
	battle.entity(2).pos = Vector2(120,60)
	for tick: int in range(240):
		if battle.battle_status == "battle": break
		battle.test_step(Battle.FIXED_DT)
	check(battle.battle_status == "battle" and battle.elapsed == 0.0,"The ordinary countdown/launch reaches the live Run before any sampling fixture")
	# Two explicit initial admissions use production descriptor/build/ownership
	# construction to reach the slowest ID stagger. They are scenario fixtures,
	# not evidence that the Director naturally chose these two events.
	for event: Dictionary in [
		{"serial":2,"kind":"rival","role":"hunter","key":"hunter","name":"SAMPLING SETUP","cost":2.6,"tier_at_entry":0},
		{"serial":3,"kind":"rival","role":"bulwark","key":"bulwark","name":"SAMPLING OWNER","cost":2.6,"tier_at_entry":0}]:
		battle.continuous._admit(event,Vector2(-120,-70) if int(event.serial) == 2 else Vector2(60,-70))
	var owner: Dictionary = battle.entity(OWNER_ID)
	check(not owner.is_empty() and owner.role == "bulwark" and owner.combatant_type == "full_top","Owner ID 4 is a canonically admitted full role top")
	check(owner.rpm == 1.0 and owner.powers.is_empty(),"The ordinary constructor supplies initial reserve; no power, reserve or charge is injected")
	battle.test_step(Battle.FIXED_DT)
	var activation: Dictionary = battle.activation
	check(not activation.is_empty() and is_equal_approx(float(activation.reserve_before)-float(activation.reserve_after),0.013),"The actual accepted Burst pays the same 0.013 reserve cost")
	check(is_equal_approx(float(activation.remaining),0.42) and float(activation.cooldown) == Battle.BURST_COOLDOWN,"Actual Burst sets the ordinary duration and mechanical cooldown")
	check(bool(activation.budget_was_unset) and is_equal_approx(float(activation.decision_interval),0.372),"The slow early ID stagger has no fabricated conservation deadline before activation")
	for tick: int in range(FIXED_TICKS_TO_REACTION): battle.test_step(Battle.FIXED_DT)
	var observed: Dictionary = battle.observation
	check(not observed.is_empty() and is_equal_approx(float(observed.time)-float(activation.time),Battle.FIXED_DT*FIXED_TICKS_TO_REACTION),"The next ordinary reaction occurs after exactly 23 fixed ticks")
	check(float(observed.remaining_before_movement) > 0.0 and float(observed.remaining_before_movement) < 0.04 and is_equal_approx(float(observed.remaining_before_movement),0.42-Battle.FIXED_DT*24.0+Battle.FIXED_DT),"A genuine positive 0.0367-second remainder is visible at that decision boundary")
	check(bool(observed.budget_set) and is_equal_approx(float(observed.get("budget_deadline",0.0)),float(observed.time)+Roles._burst_budget(owner.pilot)),"The real sampled activation sets the finite build-specific conservation budget")
	check(observed.last_burst_seen is float and is_equal_approx(float(observed.last_burst_seen),float(observed.time)),"The observation is stamped from real activation state rather than attack intent")
	check(owner.rpm < float(activation.reserve_after) and owner.cooldown > 3.0 and is_same(owner,battle.entity(OWNER_ID)),"Ordinary running costs and cooldown advance on the unchanged canonical owner")
	var reserve_before_retry: float = owner.rpm
	var velocity_before_retry: Vector2 = owner.vel
	battle._attempt_burst(owner,Vector2.RIGHT)
	check(owner.rpm == reserve_before_retry and owner.vel == velocity_before_retry,"The conservation observation never bypasses the paid mechanical Burst cooldown")
	if not report.is_empty():
		var file := FileAccess.open(report,FileAccess.WRITE)
		file.store_string(JSON.stringify(portable({"checks":checks,"failures":failures,"seed":421,"scope":"Declared initial positions and two normal actor-admission fixtures isolate an actual paid Burst and ordinary 23-tick reaction sampling. No reserve, charge, damage or outcomes assigned; no natural Director difficulty or human input claim.","owner_id":OWNER_ID,"activation":activation,"observation":observed,"fixed_ticks_after_activation":FIXED_TICKS_TO_REACTION,"final_owner_reserve":owner.rpm,"final_owner_cooldown":owner.cooldown,"final_owner_position":Vector2(owner.pos)}),"\t")); file.close()
	print("ENEMY_BURST_SAMPLING_003A1_%s checks=%d failures=%d observed_remaining=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),str(observed.get("remaining_before_movement","missing"))])
	battle.free()
	quit(0 if failures.is_empty() else 1)
