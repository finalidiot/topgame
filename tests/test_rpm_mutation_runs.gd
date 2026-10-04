extends "res://tests/test_rpm_playthrough.gd"
## Additional natural cases for the non-default costly mutation branch.
func _run() -> void:
	style = "aggressive"
	override_power = "redline"
	mutation_preference = "breakneck"
	for starter: String in Starters.IDS:
		var result: Dictionary = play(starter,7341)
		report.runs.append(result)
		print("RPM_BREAKNECK %s seconds=%.2f reason=%s powers_spent=%.3f mutation=%s" % [starter,result.survival_time,result.reason,result.rpm.losses.powers,result.mutations])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="),FileAccess.WRITE)
			file.store_string(JSON.stringify(report))
	quit()
