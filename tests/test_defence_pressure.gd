extends "res://tests/observe_defence_pressure.gd"
## A real invested-build comparison observed for up to660seconds. Natural
## outcomes and named costs/returns remain evidence, not guaranteed immortality.
## The separate90-Run before/after study is the broader balance acceptance scope.
var checks: int = 0
var failures: int = 0
const Director = preload("res://scripts/threat_director.gd")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func total(values: Dictionary) -> float:
	var amount: float=0.0
	for value: float in values.values():amount+=value
	return amount

func _run() -> void:
	horizon = 660.0
	var afk: Dictionary = observe(421,"zero_input")
	var active: Dictionary = observe(421,"active_centre")
	check(afk.finite and active.finite,"Long strong defence comparison remains finite")
	check(afk.input_seconds == 0.0 and afk.brake_seconds == 0.0 and afk.burst_presses == 0,"No-input observation really supplies no controls")
	check(afk.ended_naturally and afk.reason in ["spin_out","ring_out"],"No-input fixture eventually resolves through real physics")
	check(float(afk.survival_seconds) < 600.0,"Ten-minute zero-input stability is no longer predictable in the audited reproduction")
	check(afk.economy.gains.combat_reclamation == 0.0,"AFK cannot reclaim active contact RPM")
	for source: String in ["elimination","elite","boss"]:
		check(float(afk.economy.gains.get(source,0.0)) == 0.0,"Passive physical effects cannot renew "+source+" RPM")
	check(float(afk.economy.gains.get("dead_centre",0.0)) <= 0.280001,"Existing finite anchor quota stays intact")
	check(afk.peak_full <= 5 and afk.peak_small <= 10 and active.peak_full <= 5 and active.peak_small <= 10,"Actual pressure retains existing population caps")
	check(afk.sectors_hit >= 4 and active.sectors_hit >= 4,"Actual contacts arrive from multiple directions")
	# Smart pilots, shared full-top costs and real enemy packages can defeat an
	# invested active build. Keep the660s observation horizon, not a survival or
	# reserve floor; never require admissions after a physical defeat.
	for row: Dictionary in [afk,active]:
		var ledger: Dictionary=row.economy
		check(absf(float(ledger.starting_rpm)-total(ledger.losses)+total(ledger.gains)-float(row.rpm))<.00001,"The %s terminal reserve closes through actual named gains and losses"%row.policy)
		check(float(ledger.losses.passive)>0.0 and float(ledger.losses.collisions)>0.0 and not row.impacts.is_empty(),"The %s fixture pays real passive and physical contact pressure"%row.policy)
		var natural: bool=bool(row.ended_naturally) and row.reason in ["spin_out","ring_out"]
		var censored: bool=not bool(row.ended_naturally) and row.reason=="observation_horizon" and float(row.survival_seconds)>=horizon
		check(natural or censored,"The %s result is an actual physical outcome or an honestly completed observation horizon"%row.policy)
		check(row.reason!="spin_out" or float(row.rpm)<=.045,"A %s spin-out agrees with the actual shared full-top reserve threshold"%row.policy)
		var admission_chronology: bool=not row.director.is_empty()
		var previous_admission: float=-INF
		for event: Dictionary in row.director:
			# Director history records time to0.01s; retain its real precision when
			# a decision falls directly beside a tier boundary or final live tick.
			var time: float=float(event.time)
			admission_chronology=admission_chronology and time>=previous_admission and time<=float(row.survival_seconds)+.005 and int(event.tier)>=Director.tier_at(time-.005) and int(event.tier)<=Director.tier_at(time+.005)
			previous_admission=time
		row["tier_at_end"]=Director.tier_at(float(row.survival_seconds))
		row["last_admitted_tier"]=int(row.director[-1].tier) if not row.director.is_empty() else -1
		check(admission_chronology and int(row.last_admitted_tier)<=int(row.tier_at_end),"The %s natural admissions match their actual times and do not exceed the physically reached tier"%row.policy)
	check(active.seed==afk.seed and active.branch==afk.branch and active.director_investments==afk.director_investments and active.fixture==afk.fixture,"Both policies retain the identical declared invested fixture and seed; changed exposure and outcomes remain observations")
	active["policy_classification"]="Legacy continuous centre steering; no deliberate vent/rearm, Brake or Burst. This is not skilled active-defence acceptance."
	var comparison: Dictionary={"afk_survival_seconds":afk.survival_seconds,"legacy_control_survival_seconds":active.survival_seconds,"afk_player_contacts":afk.impacts.size(),"legacy_control_player_contacts":active.impacts.size(),"afk_contacts_per_live_second":float(afk.impacts.size())/float(afk.survival_seconds),"legacy_control_contacts_per_live_second":float(active.impacts.size())/float(active.survival_seconds),"afk_centre_seconds":afk.centre_seconds,"legacy_control_centre_seconds":active.centre_seconds,"afk_named_gains":afk.economy.gains,"legacy_control_named_gains":active.economy.gains,"control_seconds":active.input_seconds,"brake_seconds":active.brake_seconds,"burst_presses":active.burst_presses,"survival_order_is_not_a_contract":true}
	check(float(active.input_seconds)>0.0 and float(active.input_seconds)<=float(active.survival_seconds)+.00001,"The active comparison supplies real control for its observed live ticks")
	var recorded_control: bool=false
	var recorded_anchor: bool=false
	for trace: Dictionary in active.trace:
		recorded_control=recorded_control or Vector2(trace.direction[0],trace.direction[1]).length()>0.0 or bool(trace.brake) or bool(trace.burst)
		recorded_anchor=recorded_anchor or float(trace.anchor)>=.25
	check(recorded_control and float(active.economy.losses.movement)>0.0,"Recorded active steering has actual named movement cost")
	check(active.centre_seconds>active.survival_seconds*.90,"Active defensive centre hold retains the original90% occupancy contract for its actual lifetime")
	check(recorded_anchor and float(active.economy.gains.dead_centre)>0.0,"The invested player actually anchors and uses its paid finite power recovery")
	check(float(active.economy.gains.combat_reclamation)>0.0 and float(active.economy.gains.elimination)+float(active.economy.gains.elite)+float(active.economy.gains.boss)>0.0,"Controlled physical defence retains named earned contact and attributed elimination recovery without a guaranteed amount")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"horizon_seconds":horizon,"scope":"One exact invested-Bulwark paired reproduction with actual natural outcomes, named closed ledgers, controls, recovery sources and reached tiers. Legacy steering supplies no intentional vent/rearm, Brake or Burst; it cannot establish universal active-superiority. No guaranteed lifetime, terminal reserve, admission count or recovery amount. Separate matched legal vent/rearm sustain observations supply the broader measured balance boundary.","comparison":comparison,"samples":[afk,active]},"\t")); file.close()
	print("DEFENCE_PRESSURE_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
