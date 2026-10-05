extends "res://tests/test_parts_legacy.gd"
## Keep the old fixture/test intact. This diagnostic deliberately compares only
## the unchanged ratings, isolated collision and wall responses. Player motion
## is measured as different, not relabelled as historically equivalent.
var retention_checks: int = 0
var retained_sections: int = 0
var changed_motion: int = 0
var rows: Array[Dictionary] = []

func _same(first: Variant, second: Variant) -> bool:
	return JSON.stringify(JSON.parse_string(JSON.stringify(first))) == JSON.stringify(second)

func _retention_check(ok: bool, label: String) -> void:
	retention_checks += 1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_retention_check(fixture.source_sha == "3d52a55d9d9bc154b50b3b1c90255f7ff0e62148", "Retained fixture still identifies the verified infrastructure parent")
	for expected: Dictionary in fixture.assemblies:
		var current: Dictionary = _sample(expected.build)
		var row: Dictionary = {"build":expected.build, "motion_changed":not _same(current.motion, expected.motion)}
		for section: String in ["stats", "contact", "wall"]:
			row[section+"_equal"] = _same(current[section], expected[section])
			_retention_check(row[section+"_equal"], "Original physical "+section+" remains exact: "+Parts.title(expected.build))
			if row[section+"_equal"]: retained_sections += 1
		if row.motion_changed: changed_motion += 1
		rows.append(row)
	_retention_check(rows.size() == 48 and retained_sections == 144, "All48 original assemblies retain their stats, isolated contact and wall response")
	_retention_check(changed_motion == 48, "All48 frozen movement trajectories are intentionally superseded by the requested drifting correction")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			_retention_check(file != null, "Explicit external retention report is writable")
			if file != null: file.store_string(JSON.stringify({"checks":retention_checks,"failures":failures,"fixture_sha":fixture.source_sha,"retained_sections":retained_sections,"changed_motion":changed_motion,"historical_trajectory_equivalence":false,"assemblies":rows}, "\t"))
	print("FEEDBACK_PARTS_RETENTION_%s checks=%d failures=%d retained_sections=%d changed_motion=%d historical_trajectory_equivalence=false" % ["PASS" if failures.is_empty() else "FAIL", retention_checks, failures.size(), retained_sections, changed_motion])
	quit(0 if failures.is_empty() else 1)
