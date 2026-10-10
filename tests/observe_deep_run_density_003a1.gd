extends SceneTree
const Model = preload("res://tests/director_density_model_003a1.gd")
const Director = preload("res://scripts/threat_director.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var output: String="";var label: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
	if not output.is_absolute_path() or FileAccess.file_exists(output):push_error("Fresh external report required");quit(2);return
	var cases: Array[Dictionary]=[]
	for policy: String in ["quick","durable"]:
		for seed_value: int in [421,7341,2026,99,123,77]:cases.append(Model.simulate(seed_value,policy))
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"label":label,"scope":"Independent actual seeded Director decide/cleared/limits calls at0.25s through1200s. Census actor lifetimes/warning reservations are explicit fixtures, not natural combat survival, damage, player input or rewards. Swarm counts are reserved full-fixture occupancy, not observed native moving small bodies. Separate movie runs ordinary fixed60Hz physics at declared accelerated starting-clock stages.","seeds":[421,7341,2026,99,123,77],"policies":["quick","durable"],"tuning":Director.TUNING,"cases":cases},"\t"));file.close()
	print("DEEP_RUN_DENSITY_OBSERVATION_PASS label=%s cases=%d"%[label,cases.size()]);quit(0)
