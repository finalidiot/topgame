extends "res://tests/observe_defence_pressure.gd"
## A real 660-second invested-build comparison. Observations remain observations:
## no fixed death-time assertion, fake defeat or guarantee for every future seed.
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

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
	check(afk.director.size() >= 20 and active.director.size() >= 20,"Mature threats enter naturally instead of stalling")
	check(not active.ended_naturally and active.survival_seconds >= 660.0,"Invested active fortress can still hold exceptionally long")
	check(active.rpm > 0.50 and active.centre_seconds > active.survival_seconds*0.95,"Active defensive centre-hold fantasy remains extremely strong")
	check(float(active.economy.gains.elimination)+float(active.economy.gains.elite)+float(active.economy.gains.boss) > 0.5,"Controlled physical defence retains earned sustain")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"One exact audited strong-Bulwark reproduction, real production physics/natural Director, no scripted outcome or timer. Other seeds and Counterweight observations have separate preserved reports.","samples":[afk,active]},"\t")); file.close()
	print("DEFENCE_PRESSURE_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
