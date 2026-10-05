extends SceneTree
## Differential against the verified C5.1 battle source. New catalogue hooks
## must preserve original assemblies, seeded contacts, powers and RPM ledgers.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Bot = preload("res://tests/rpm_bot.gd")
var checks: int = 0
var failures: int = 0
var parent_script: GDScript

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures < 5: push_error(label)

func state(b: Node2D) -> Dictionary:
	var result: Dictionary = b.snapshot()
	# Component metadata is newly attached; old observable state stays exact.
	for f: Dictionary in result.entities.values():
		f.erase("part_physics")
		f.erase("spin_angle")
		f.erase("part_clock")
		f.erase("part_contacts")
	result.erase("player")
	result.erase("enemy")
	return result

func run() -> void:
	var source: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--parent-source="): source = arg.trim_prefix("--parent-source=")
	if source.is_empty() or not FileAccess.file_exists(source):
		push_error("Pass --parent-source=<verified 3d52a55 battle.gd snapshot>")
		quit(2)
		return
	parent_script = GDScript.new()
	parent_script.source_code = FileAccess.get_file_as_string(source).replace("class_name PrototypeBattle", "")
	if parent_script.reload() != OK:
		quit(2)
		return
	for starter: String in Starters.IDS:
		for seed: int in [421, 7341]:
			var old: Node2D = parent_script.new()
			var current: Node2D = Battle.new()
			for b: Node2D in [old, current]:
				root.add_child(b)
				b.set_physics_process(false)
				var descriptor: Dictionary = Encounters.for_run_event(1, seed)
				descriptor.starter_id = starter
				descriptor.player_power_ids = ["impact_wake", "chain_impact", "redline", "afterimage", "orbit_drive", "momentum_bank", "crash_guard"]
				descriptor.player_power_ranks = {"impact_wake":2,"chain_impact":2,"redline":2,"afterimage":2,"orbit_drive":2,"momentum_bank":2,"crash_guard":2}
				b.begin_run(Starters.build_for(starter), descriptor, seed)
			# Identical launch, controls and ticks; no injected contact or outcome.
			for tick: int in range(2100):
				var controls: Dictionary = Bot.input(old, "hybrid", tick)
				for b: Node2D in [old, current]:
					b.test_step(Battle.FIXED_DT, controls.direction, controls.burst, controls.brake)
				check(state(old) == state(current), "Legacy physical/AI state differs: %s/%d tick%d" % [starter, seed, tick])
				if tick % 60 == 0:
					check(old.continuous.economy.snapshot() == current.continuous.economy.snapshot(), "Legacy RPM ledger differs")
					check(old.continuous.snapshot() == current.continuous.snapshot(), "Legacy director/admission differs")
					check(old.powers.diagnostics(old.player_entity()) == current.powers.diagnostics(current.player_entity()), "Legacy power state differs")
					check(old.roster.diagnostics(old.player_entity()) == current.roster.diagnostics(current.player_entity()), "Legacy C5 roster state differs")
				if old.battle_status == "finished" or current.battle_status == "finished": break
			check(old.last_result == current.last_result, "Legacy outcome differs")
			old.free()
			current.free()
	print("Catalogue legacy Run equivalence: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
