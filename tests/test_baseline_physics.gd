extends SceneTree
## Optional differential test against actual Task 001 battle source.
## Checkout d551867966a1711d83ddf064f06d5f6f6ffc56ae separately and pass:
## -- --baseline-source=<absolute-baseline-checkout>/scripts/battle.gd
## Controls both bodies directly to isolate equations from intentionally changed AI RNG.
const NewBattle = preload("res://scripts/battle.gd")
const Parts = preload("res://scripts/parts.gd")
const FIELDS = ["pos", "vel", "rpm", "energy", "wobble", "cooldown", "burst_time", "height", "height_vel", "impact_time", "impact_strength"]
var checks = 0
var failures = 0
func _initialize():
	call_deferred("_run")
func _run():
	var baseline_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-source="):
			baseline_path = argument.trim_prefix("--baseline-source=")
	if baseline_path.is_empty() or not FileAccess.file_exists(baseline_path):
		push_error("Pass -- --baseline-source=<baseline checkout>/scripts/battle.gd")
		quit(2)
		return
	var old_script = GDScript.new()
	old_script.source_code = FileAccess.get_file_as_string(baseline_path).replace("class_name PrototypeBattle", "")
	if old_script.reload() != OK:
		quit(2)
		return
	for blade in Parts.BLADE_IDS:
		for ratchet in Parts.RATCHET_IDS:
			for bit in Parts.BIT_IDS:
				var build = {"blade": blade, "ratchet": ratchet, "bit": bit}
				var opponent = {"blade": "hook", "ratchet": "low", "bit": "rubber"}
				var old = old_script.new()
				var new = NewBattle.new()
				root.add_child(old)
				root.add_child(new)
				old.set_physics_process(false)
				new.set_physics_process(false)
				for b in [old, new]:
					b.begin(build, opponent, 1, 421)
					b.battle_status = "battle"
					b.test_set_state(0, {"pos": Vector2(-70, 45), "vel": Vector2(30, 80), "rpm": 0.75, "wobble": 0.3})
					b.test_set_state(1, {"pos": Vector2(80, -60), "vel": Vector2(-50, 30), "rpm": 0.45, "wobble": 0.2})
				for frame in range(120):
					for b in [old, new]:
						if frame == 35:
							b._attempt_burst(b.fighters[0], Vector2(-0.5, 0.5))
						for side in range(2):
							b._update_fighter(b.fighters[side], Vector2(sin(frame * 0.13), cos(frame * 0.09)).limit_length(), frame % 40 > 25, 1.0 / 60.0)
							b._resolve_boundary(b.fighters[side])
					_compare(old, new, str(build) + " movement tick " + str(frame))
				for b in [old, new]:
					b.test_set_state(0, {"pos": Vector2(-10, 0), "vel": Vector2(130, 20), "rpm": 0.9, "wobble": 0.2, "burst_time": 0.1})
					b.test_set_state(1, {"pos": Vector2(10, 0), "vel": Vector2(-100, 30), "rpm": 0.7, "wobble": 0.3})
					b._resolve_contact()
				_compare(old, new, str(build) + " contact")
				old.free()
				new.free()
	print("Baseline differential: ", checks, " field comparisons across 48 assemblies, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func _compare(old, new, label):
	for side in range(2):
		for field in FIELDS:
			checks += 1
			if old.fighters[side][field] != new.fighters[side][field]:
				failures += 1
				if failures < 6:
					print("FAIL ", label, " ", field, " ", old.fighters[side][field], " / ", new.fighters[side][field])
