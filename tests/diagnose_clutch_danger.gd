extends "res://tests/diagnose_roster_runs.gd"
## Natural earned-draft counterpart to the controlled comeback starting build.
## Main's real offers and normal combat are retained. Only sampled player input
## creates danger and pursues recovery; there are no body/reserve/outcome edits.
var observed: Dictionary = {}
var observing: bool = false

func screen_direction(world: Vector2) -> Vector2:
	if world.length() <= 0.001: return Vector2.ZERO
	return Vector2(world.x-world.y,(world.x+world.y)*0.5).normalized()*minf(1.0,world.length())

func controls(b: Node2D, _playstyle: String, tick: int) -> Dictionary:
	var p: Dictionary = b.player_entity()
	if not observing:
		observing = true
		var observations: Dictionary = observed
		b.contact_accepted.connect(func(first: int, second: int) -> void:
			if int(p.entity_id) not in [first,second] or float(p.get("clutch_time",0.0)) <= 0.0 or observations.danger_contacts.size() >= 32: return
			var state: Dictionary = b.powers._states.get(int(p.entity_id),{})
			var other: Dictionary = b.entity(second if first == int(p.entity_id) else first)
			observations.danger_contacts.append({"time":b.elapsed,"approach_rpm":state.get("motion_rpm",p.rpm),"after_rpm":p.rpm,"speed":state.get("motion_speed",0.0),"severity":p.impact_strength,"input":state.get("motion_input",0.0),"rank":b.powers.rank(p,"clutch"),"target_kind":other.get("combatant_type","retired"),"clutch_active":p.get("clutch_active",false),"tokens":b.continuous.economy.tokens}))
		b.event_sfx.connect(func(kind: String) -> void:
			if kind in ["clutch_activate","clutch_recover"]:
				observations.events.append({"kind":kind,"time":b.elapsed,"rpm":p.rpm,"rank":b.powers.rank(p,"clutch")}))
	if float(observed.clutch_acquired_at) < 0.0 and b.powers.rank(p,"clutch") > 0:
		observed.clutch_acquired_at = b.elapsed
	if float(p.rpm) <= 0.28 and float(observed.danger_at) < 0.0:
		observed.danger_at = b.elapsed
		observed.clutch_rank_at_first_danger = b.powers.rank(p,"clutch")
	var c: Dictionary
	if float(observed.danger_at) < 0.0:
		# Match the controlled comeback policy: riding the paid brake with
		# weak central correction cannot qualify for ordinary contact reclaim.
		c = {"direction":screen_direction((-Vector2(p.pos)-Vector2(p.vel)*0.4).normalized()*0.06),"brake":true,"burst":false}
	else:
		c = Bot.input(b,"aggressive",tick)
		observed.recovery_peak_after_danger = maxf(float(observed.recovery_peak_after_danger),float(p.rpm))
	# This is steering input, not position protection; ring-outs remain live.
	if Vector2(p.pos).length() > 145.0:
		c.direction = screen_direction(-Vector2(p.pos).normalized()*0.80)
		c.brake = true
	return c

func _run() -> void:
	# Supply --report / --compact under the shared task QA workspace for retained
	# evidence. Defaults are isolated user-data diagnostics, never source files.
	var output: String = "user://task002c5-natural-clutch-danger.json"
	var compact_output: String = "user://task002c5-clutch-natural-danger-results.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
		if arg.begins_with("--compact="): compact_output = arg.trim_prefix("--compact=")
	profile = "comeback"
	style = "aggressive"
	override_power = "clutch"
	sample_limit = 300.0
	report["scope"] = "Natural Main draft offers with Clutch-first existing comeback preferences; full RPM launch, ordinary AI/director/economy and inputs only. Paid braking and weak correction until actual RPM <=0.28, then aggressive pursuit with normal edge correction. No injected ranks, reserve/body edits, loss protection or outcome injection. Not human acceptance."
	report["diagnostic_ceiling_seconds"] = sample_limit
	report["controller_sampling_ticks"] = 12
	report["seed"] = 7341
	var compact: Dictionary = {"scope":report.scope,"diagnostic_ceiling_seconds":sample_limit,"controller_sampling_ticks":12,"seed":7341,"runs":[]}
	for starter: String in Starters.IDS:
		observed = {"danger_at":-1.0,"clutch_acquired_at":-1.0,"clutch_rank_at_first_danger":0,"recovery_peak_after_danger":0.0,"danger_contacts":[],"events":[]}
		observing = false
		draft_log.clear()
		var row: Dictionary = play(starter,7341)
		row["profile"] = "natural_clutch_danger"
		row["drafts"] = draft_log.duplicate(true)
		row["danger_observation"] = observed.duplicate(true)
		report.runs.append(row)
		compact.runs.append({"starter":starter,"seed":7341,"survival_time":row.survival_time,"reason":row.reason,"level":row.level,"powers":row.powers,"ranks":row.ranks,"mutations":row.mutations,"drafts":row.drafts,"remaining_rpm":row.remaining_rpm,"minimum_rpm":row.rpm.minimum_rpm,"clutch_activations":int(row.power_procs.get("clutch_activate",0)),"clutch_catches":int(row.power_procs.get("clutch_recover",0)),"clutch_gain":float(row.rpm.gains.get("clutch",0.0)),"danger_observation":row.danger_observation,"accounting_error":row.accounting_error})
		for target: String in [output,compact_output]:
			var file: FileAccess = FileAccess.open(target,FileAccess.WRITE)
			assert(file != null,"Clutch diagnostic evidence must be writable")
			file.store_string(JSON.stringify(report if target == output else compact,"\t"))
			file.close()
		print("CLUTCH_NATURAL %s seed=7341 seconds=%.2f reason=%s rank=%d danger=%.2f minimum=%.3f catches=%d earned_gain=%.3f" % [starter,row.survival_time,row.reason,int(row.ranks.get("clutch",0)),observed.danger_at,row.rpm.minimum_rpm,int(row.power_procs.get("clutch_recover",0)),float(row.rpm.gains.get("clutch",0.0))])
	print("CLUTCH_NATURAL_DONE samples=",report.runs.size())
	quit()
