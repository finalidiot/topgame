extends SceneTree
## Finite headless fixture geometry search; no production mechanic tuning.
const Fixture = preload("res://tests/ecology_showcase_fixture_003a2.gd")
const Draft = preload("res://tests/mutation_draft_policy_003a2.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var output: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	if not output.is_absolute_path() or FileAccess.file_exists(output):quit(2);return
	var rows: Array[Dictionary]=[];var found: bool=false
	for boost: float in [.30,.50,.70]:
		for lead: float in [.25,.50,.75,1.0,1.25,1.50]:
			var spec: Dictionary=Fixture.SPECS[6].duplicate(true);spec.tangent_boost=boost;spec.npc_lead=lead
			var scene: Dictionary=Fixture.create(root,spec);var b: Node2D=scene.battle
			for tick: int in range(600):
				Fixture.step(scene,tick)
				if int(b.roster.ecology.counters.get("centrifuge_hit",0))>0:found=true;break
			rows.append({"boost":boost,"lead":lead,"counters":b.roster.ecology.counters.duplicate(),"contacts":scene.contacts,"peak_orbit":scene.peak_orbit,"final":b.fixture_snapshot()});b.free()
			if found:break
		if found:break
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(Draft.portable({"found":found,"cases":rows}),"\t"));file.close()
	print("CENTRIFUGE_SEARCH found=",found," cases=",rows.size());quit(0)
