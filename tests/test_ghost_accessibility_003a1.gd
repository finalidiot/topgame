extends "res://tests/observe_ghost_accessibility_003a1.gd"
## Real paid production traces from actual solver movement, plus unchanged abuse guards.
const Runtime=preload("res://scripts/power_runtime.gd")
var checks: int=0
var failures: Array=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
	if not report.is_absolute_path() or not (report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/") or report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/")) or FileAccess.file_exists(report): quit(2); return
	horizon=24
	check(Runtime.GHOST_CLOSURE==56.0,"Fixed measured closure assist is56 world units")
	check(Runtime.GHOST_SPEED==112.0 and Runtime.GHOST_CONTINUITY==26.0 and Runtime.GHOST_EMIT_GAP==6.0,"Existing paid speed/continuity/live-tip contracts remain exact")
	check(Runtime.GHOST_AREA==1300.0 and Runtime.GHOST_PERIMETER==180.0 and Runtime.GHOST_EXTENT==32.0 and Runtime.GHOST_GAP_RATIO==.22,"Meaningful physical loop geometry is unchanged")
	check(Runtime.GHOST_COOLDOWN==3.5 and Runtime.GHOST_AGE==.85,"Existing anti-spam and chronological route age remain exact")
	for config: Dictionary in configurations:
		if config.id not in ["vane_imperfect_68","custom_oval","vane_idle","vane_straight","vane_tiny"]: continue
		observe(config,421); await process_frame
		var row: Dictionary=runs[-1]
		if config.id in ["vane_idle","vane_straight","vane_tiny"]: check(row.closed_count==0,"Actual idle/straight/tiny gameplay cannot farm automatic circuits "+config.id)
		else:
			check(row.closed_count>0 and row.trace_emissions>0,"Imperfect natural solver movement produces actual paid circuit "+config.id)
			check(float(row.economy.losses.passive)+float(row.economy.losses.powers)>0 and float(row.rpm)<1.0,"Successful motion/trace physically spends reserve "+config.id)
		var last: float=-100
		for closure: Dictionary in row.closures:
			check(closure.emitted and closure.actual_closure and closure.reason=="qualifies","Closing movement must be emitted/paid before canonical closure")
			check(float(closure.candidate.gap)<=Runtime.GHOST_CLOSURE and float(closure.candidate.area)>=Runtime.GHOST_AREA and float(closure.candidate.perimeter)>=Runtime.GHOST_PERIMETER,"Actual successful polygon retains measured physical geometry")
			check(float(closure.time)-last>=Runtime.GHOST_COOLDOWN-.000001,"Actual production collisions cannot bypass same-owner circuit cooldown")
			last=float(closure.time)
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify(portable({"checks":checks,"failures":failures,"runs":runs,"scope":"Legal initial Ghost/High Gear loadouts; actual solver/AI/Director paid traces, no teleport/forced path/reserve writes."}),"\t"))
	print("GHOST_ACCESSIBILITY_003A1_", "PASS" if failures.is_empty() else "FAIL"," checks=",checks); quit(0 if failures.is_empty() else 1)
