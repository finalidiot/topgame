extends "res://tests/observe_run_ramp.gd"
## Same actual Main input/offer policy replays the whole opening deterministically.
const Save = preload("res://scripts/collection_save.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func player_fingerprint() -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		result[suffix] = FileAccess.get_sha256(Save.DEFAULT_PATH + suffix) if FileAccess.file_exists(Save.DEFAULT_PATH + suffix) else ""
	result.preferences = FileAccess.get_sha256("user://prototype.cfg") if FileAccess.file_exists("user://prototype.cfg") else ""
	return result

func run() -> void:
	var report: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	var qa: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa.is_empty(): qa = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	var base: String = qa.path_join("003A.1/temp/run-ramp-replay-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(base)
	var before: Dictionary = player_fingerprint()
	horizon = 85.0
	collection_prefix = base.path_join("first")
	var first: Dictionary = observe(CASES[0], 421)
	collection_prefix = base.path_join("second")
	var second: Dictionary = observe(CASES[0], 421)
	check(first == second,"Same seed, assembly, normal earned offers and controls replay every natural combat/pressure/XP observation exactly")
	check(first.first_meaningful_contact > 0.0 and first.first_meaningful_contact < 20.0,"Opening meaningful rival pressure remains present before mixed escalation")
	check(first.first_commit >= 0.65 and first.first_commit < 12.0,"First rival visibly positions/sets up before its finite observed-state commitment")
	check(first.first_overlap >= 28.0 and first.first_overlap < 50.0,"Actual mixed overlap waits through the opening, then arrives promptly")
	check(first.draft_count > 2 and first.level > 2,"Actual combat XP produces multiple ordinary investments without injected powers")
	for draft: Dictionary in first.drafts:
		check(str(draft.choice) in draft.offer,"Every investment comes from its seeded legal offer")
		if float(draft.time) > 0.0: check(int(draft.total_xp) > 0,"Every later draft follows actual earned XP")
	for entry: Dictionary in first.entries:
		if str(entry.kind) == "swarm": check(float(entry.time) >= 28.0,"No instant opening swarm admission")
	check(player_fingerprint() == before,"Natural replay leaves the actual player's collection/backups/preferences unchanged")
	if not report.is_empty():
		assert(report.is_absolute_path() and not FileAccess.file_exists(report))
		var file: FileAccess = FileAccess.open(report, FileAccess.WRITE)
		file.store_string(JSON.stringify(portable({"checks":checks,"failures":failures,"source":"Actual production Main/Director, two identical natural opening-to85s Runs, isolated collections, legal fixed controls, earned XP/offers only","sample":first}), "\t"))
		file.close()
	print("RUN_RAMP_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
