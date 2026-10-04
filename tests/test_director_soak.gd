extends SceneTree
## Deliberately protected-player load fixture, NOT survival/balance evidence.
## Enemy physics/director/powers are real. Only player RPM and ring-out are guarded.
class ProtectedBattle extends "res://scripts/battle.gd":
	var saves: int = 0
	func _check_result() -> void:
		var p: Dictionary = player_entity()
		p.rpm = 0.8
		p.energy = 0.8
		super._check_result()
	func _resolve_boundary(f: Dictionary) -> void:
		super._resolve_boundary(f)
		if f.entity_id == player_entity_id and f.outcome == "ring_out":
			saves += 1
			f.outcome = ""
			f.pos = Vector2(f.pos).limit_length(140.0)
			f.vel = -Vector2(f.pos).normalized()*50.0
			f.height = 0.0
			f.height_vel = 0.0
const Starters = preload("res://scripts/starters.gd")
const Powers = preload("res://scripts/run_powers.gd")
const Encounters = preload("res://scripts/encounters.gd")
var results: Array[Dictionary] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for starter: String in Starters.IDS:
		var b: ProtectedBattle = ProtectedBattle.new()
		root.add_child(b)
		b.set_physics_process(false)
		b.particles_enabled = false
		var descriptor: Dictionary = Encounters.for_slot(1,421)
		descriptor["starter_id"] = starter
		descriptor["player_power_ids"] = Powers.ACTIVE_IDS.duplicate()
		descriptor["player_power_ranks"] = {"redline":3,"afterimage":3,"dead_centre":3}
		descriptor["player_power_mutations"] = {"redline":"runaway","afterimage":"slipstream","dead_centre":"counterweight"}
		b.begin_run(Starters.build_for(starter),descriptor,421)
		b.continuous.progression_level = 13
		var p: Dictionary = b.player_entity()
		var result: Dictionary = {"starter":starter,"seed":421,"events":0,"bosses":0,"elites":0,"swarms":0,"max_full":0,"max_reserved_full":0,"max_bosses":0,"max_small":0,"max_active":0,"max_retained":0,"max_states":0,"max_fx":0,"max_traces":0}
		b.threat_started.connect(func(event: Dictionary) -> void:
			result.events += 1
			if event.kind == "boss": result.bosses += 1
			if event.kind == "elite": result.elites += 1
			if event.kind == "swarm": result.swarms += 1)
		var direction: Vector2 = Vector2.ZERO
		var tick: int = 0
		while b.elapsed < 900.0 and tick < 125000:
			var burst: bool = false
			if tick%12 == 0:
				var target: Dictionary = b._target_for(p)
				var aim: Vector2 = -Vector2(p.pos)
				if not target.is_empty(): aim = Vector2(target.pos)-Vector2(p.pos)
				if Vector2(p.pos).length() > 140.0: aim = -Vector2(p.pos)
				direction = Vector2(aim.x-aim.y,(aim.x+aim.y)*0.5).normalized()*0.86
				burst = p.cooldown <= 0.0 and Vector2(p.pos).length() < 135.0
			b.test_step(b.FIXED_DT,direction,burst,false)
			assert(is_same(p,b.player_entity()) and b.battle_status != "finished")
			var c: Dictionary = b.continuous.census()
			var limit: Dictionary = b.continuous.Director.limits(b.elapsed,13)
			assert(c.pressure <= limit.budget+0.001 and c.full <= limit.full and c.elites <= limit.elites and c.bosses <= limit.bosses and c.total <= limit.total)
			var active: int = 0
			for f: Dictionary in b.fighters:
				if str(f.outcome).is_empty(): active += 1
			result.max_active = maxi(result.max_active,active)
			var live_full: int = int(c.full)-(1 if not b.continuous.pending.is_empty() and b.continuous.pending.kind != "swarm" else 0)
			result.max_full = maxi(result.max_full,live_full)
			result.max_reserved_full = maxi(result.max_reserved_full,c.full)
			result.max_bosses = maxi(result.max_bosses,c.bosses)
			result.max_small = maxi(result.max_small,c.small)
			result.max_retained = maxi(result.max_retained,b.fighters.size())
			result.max_states = maxi(result.max_states,b.powers._states.size())
			result.max_fx = maxi(result.max_fx,b._power_fx.size())
			result.max_traces = maxi(result.max_traces,b.powers.traces.size())
			tick += 1
		result["seconds"] = b.elapsed
		result["tier"] = b.continuous.Director.tier_at(b.elapsed)
		result["ringout_saves"] = b.saves
		result["clears"] = b.continuous.threats_cleared
		result["bosses_defeated"] = b.continuous.bosses_defeated
		assert(b.elapsed >= 900.0 and result.tier > 4 and result.bosses > 0 and result.elites > 0 and result.swarms > 0)
		print("DIRECTOR_SOAK_PASS ",JSON.stringify(result))
		results.append(result)
		b.free()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--report="),FileAccess.WRITE)
			file.store_string(JSON.stringify({"scope":"Protected-player 900-second real-physics load fixture. Player reserve is held at 0.8, ring-outs intercepted, full build installed. Not natural survival or balance evidence.","runs":results},"\t"))
	quit()
