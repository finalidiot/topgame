extends "res://tests/test_rpm_playthrough.gd"
func _run() -> void:
	style = "aggressive"
	var first: Dictionary = play("breaker",421)
	var second: Dictionary = play("breaker",421)
	for key: String in ["entries","clears","rpm_curve","recoveries","rpm","reason","powers","ranks","mutations"]:
		assert(first[key] == second[key],"Identical seed and input must reproduce "+key)
	assert(first.accounting_error < 0.000001 and second.accounting_error < 0.000001)
	assert(first.launches == 1 and second.launches == 1)
	print("RPM_REPLAY_PASS two natural seeded Runs, exact curves/events/accounting/progression")
	quit()
