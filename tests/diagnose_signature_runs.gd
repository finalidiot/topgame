extends "res://tests/test_rpm_playthrough.gd"
## Small natural replay sample to locate honest boss/comeback movie windows.
func _run() -> void:
	style="aggressive";override_power="dead_centre"
	for starter: String in ["vane","bastion"]:
		var r: Dictionary=play(starter,7341)
		report.runs.append(r)
		print("SIGNATURE_NATURAL ",starter," seconds=",r.survival_time," bosses=",r.bosses_defeated)
	var path: String="user://task002c4-natural-runs.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): path=arg.trim_prefix("--report=")
	var file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	quit()
