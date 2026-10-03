extends SceneTree
## Actual combat diagnostic: no injected victories, reserve refills or teleports.
## This records bot evidence, never substitutes for human feel acceptance.
const Battle = preload("res://scripts/battle.gd")
const Run = preload("res://scripts/run_context.gd")
var report: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run_diagnostics")
func run_diagnostics() -> void:
	for build: Dictionary in [{"blade":"guard","ratchet":"low","bit":"needle"},{"blade":"smash","ratchet":"low","bit":"flat"},{"blade":"balance","ratchet":"mid","bit":"ball"}]:
		for seed_value: int in [421,7341]:
			var context = Run.new()
			context.start(build,seed_value)
			var bouts: Array[Dictionary] = []
			while context.is_active():
				var b: Node2D = Battle.new()
				root.add_child(b)
				b.set_physics_process(false)
				b.particles_enabled = false
				b.begin_encounter(build,context.current_encounter())
				b.battle_status = "battle"
				for tick: int in range(6000):
					var p: Dictionary = b.player_entity()
					var target: Dictionary = b._target_for(p)
					var direction: Vector2 = Vector2.ZERO
					if not target.is_empty():
						var aim: Vector2 = (Vector2(target.pos)-Vector2(p.pos)).normalized()
						direction = Vector2(aim.x-aim.y,(aim.x+aim.y)*0.5).normalized()
					if Vector2(p.pos).length()>140.0:
						var toward: Vector2 = -Vector2(p.pos).normalized()
						direction = Vector2(toward.x-toward.y,(toward.x+toward.y)*0.5).normalized()
					var ready: bool = float(p.cooldown)<=0.0 and tick%8==0
					b.test_step(Battle.FIXED_DT,direction,ready,false)
					if b.battle_status=="finished": break
				var result: Dictionary = b.last_result.duplicate(true)
				result["slot"] = context.slot
				result["powers"] = context.owned_power_ids
				result["procs"] = b.powers.counters.duplicate()
				bouts.append(result)
				var descriptor: Dictionary = context.current_encounter()
				context.commit_result(descriptor.id,bool(result.get("won",false)))
				b.free()
				if not context.is_active(): break
				if not context.pending_offer.is_empty():
					var choice: String = context.pending_offer[0]
					for preferred: String in ["second_wind","impact_wake","chain_impact","redline","iron_comet","afterimage"]:
						if preferred in context.pending_offer:
							choice = preferred
							break
					context.choose_power(descriptor.id,choice)
				context.advance()
			var record: Dictionary = {"build":build,"seed":seed_value,"status":context.status,"bouts":bouts}
			report.append(record)
			print("PLAYTHROUGH ",JSON.stringify(record))
	var destination: String = "user://task002b-playthrough.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): destination = argument.trim_prefix("--report=")
	var output: FileAccess = FileAccess.open(destination,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print("PLAYTHROUGH_REPORT ",destination)
	quit()
