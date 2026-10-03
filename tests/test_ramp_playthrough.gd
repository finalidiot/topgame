extends SceneTree
## Actual seeded combat with sampled, imperfect pursuit controls. No victories,
## refills, position resets or power procs are injected. Bot evidence only.
const Battle = preload("res://scripts/battle.gd")
const Run = preload("res://scripts/run_context.gd")
const Starters = preload("res://scripts/starters.gd")
const Parts = preload("res://scripts/parts.gd")
var report: Dictionary = {"scope":"Deterministic sampled bot combat; active combat seconds exclude countdown and all choices. This is not a human playtest.", "runs":[], "swarm":[], "assemblies":[]}

func _initialize() -> void: call_deferred("_run")

func _pick(offer: Array) -> String:
	for preferred: String in ["iron_comet", "redline", "impact_wake", "second_wind", "afterimage", "chain_impact"]:
		if preferred in offer: return preferred
	return str(offer[0])

func _play(starter_id: String, seed_value: int, swarm_only: bool = false) -> Dictionary:
	var context = Run.new()
	context.start(Starters.build_for(starter_id), seed_value, starter_id)
	context.choose_power(context.pending_draft_id, _pick(context.pending_offer))
	if swarm_only: context.slot = 3
	var record: Dictionary = {"starter":starter_id, "seed":seed_value, "initial_power":context.owned_power_ids[0], "choices":[], "bouts":[], "powers_at_60":0, "first_level_seconds":-1.0}
	var active_seconds: float = 0.0
	var first_minute_seen: bool = false
	var ticks: int = 0
	while context.is_active() and ticks < 24000:
		var b = Battle.new()
		root.add_child(b)
		b.set_physics_process(false)
		b.particles_enabled = false
		b.begin_encounter(context.selected_build, context.current_encounter())
		b.battle_status = "battle"
		b.progression_events.connect(func(events: Array) -> void:
			if b.battle_status == "finished" and not bool(b.last_result.get("won",false)): return
			for event: Dictionary in events: context.award_xp(event)
			if not context.pending_offer.is_empty(): b.set_paused(true))
		var direction: Vector2 = Vector2.ZERO
		var burst_ready: bool = false
		var brake: bool = false
		for local_tick: int in range(6600):
			ticks += 1
			var p: Dictionary = b.player_entity()
			# Aim is sampled at 5Hz, with a small deterministic angular error.
			if local_tick % 12 == 0:
				var target: Dictionary = b._target_for(p)
				var aim: Vector2 = Vector2.ZERO
				var distance: float = INF
				if not target.is_empty():
					var offset: Vector2 = Vector2(target.pos) - Vector2(p.pos)
					distance = offset.length()
					aim = offset.normalized().rotated(sin(float(local_tick) * 0.047) * 0.16)
				if Vector2(p.pos).length() > 143.0: aim = -Vector2(p.pos).normalized()
				direction = Vector2(aim.x - aim.y, (aim.x + aim.y) * 0.5).normalized() * 0.86
				brake = Vector2(p.pos).length() > 153.0
				burst_ready = float(p.cooldown) <= 0.0 and distance < 110.0 and not brake
			else: burst_ready = false
			var previous: float = b.elapsed
			b.test_step(Battle.FIXED_DT, direction, burst_ready, brake)
			active_seconds += b.elapsed - previous
			if b.paused:
				var saved: Dictionary = b.snapshot()
				b.test_step(0.25, Vector2.LEFT, true, true)
				assert(b.snapshot() == saved, "Draft freeze preserves complete encounter")
				while not context.pending_offer.is_empty():
					var power_id: String = _pick(context.pending_offer)
					var earned_level: int = context.pending_draft_level
					assert(context.choose_power(context.pending_draft_id, power_id))
					assert(b.acquire_run_power(power_id))
					record.choices.append({"active_seconds":snappedf(active_seconds,0.01), "encounter_seconds":snappedf(b.elapsed,0.01), "slot":context.slot, "level":earned_level, "power":power_id, "wave":b.swarm.wave})
					if float(record.first_level_seconds) < 0.0: record.first_level_seconds = snappedf(active_seconds,0.01)
				b.set_paused(false)
			if not first_minute_seen and active_seconds >= 60.0:
				first_minute_seen = true
				record.powers_at_60 = context.owned_power_ids.size()
			if b.battle_status == "finished": break
		var result: Dictionary = b.last_result.duplicate(true)
		result["slot"] = context.slot
		result["power_procs"] = b.powers.counters.duplicate()
		result["owned"] = context.owned_power_ids
		record.bouts.append(result)
		context.commit_result(str(context.current_encounter().id), bool(result.get("won",false)))
		b.free()
		if swarm_only or not context.advance(): break
	if not first_minute_seen: record.powers_at_60 = context.owned_power_ids.size()
	record["reached_60"] = first_minute_seen
	record["status"] = context.status
	record["active_seconds"] = snappedf(active_seconds,0.01)
	return record

func _measure_assembly(build: Dictionary) -> Dictionary:
	var b = Battle.new()
	b.begin(build, Parts.DEFAULT_BUILD, 1, 421)
	var p: Dictionary = b.player_entity()
	p.vel = Vector2.ZERO
	for _tick: int in range(60): b._update_fighter(p,Vector2.RIGHT,false,Battle.FIXED_DT)
	var acceleration_speed: float = Vector2(p.vel).length()
	var rpm_at_1: float = p.rpm
	p.pos = Vector2.ZERO
	p.vel = Vector2(120,0)
	for _tick: int in range(15): b._update_fighter(p,Vector2.ZERO,true,Battle.FIXED_DT)
	var brake_speed: float = Vector2(p.vel).length()
	p.pos = Vector2.ZERO
	p.vel = Vector2(120,0)
	for _tick: int in range(30): b._update_fighter(p,Vector2.UP,false,Battle.FIXED_DT)
	var turn_angle: float = rad_to_deg(Vector2(p.vel).angle())
	var stats: Dictionary = Parts.derive(build)
	var output: Dictionary = {"build":build, "stats":stats, "physical_mass":p.mass, "speed_after_1s":snappedf(acceleration_speed,0.01), "rpm_spent_1s":snappedf(1.0-rpm_at_1,0.0001), "speed_after_250ms_brake":snappedf(brake_speed,0.01), "turn_degrees_after_500ms":snappedf(turn_angle,0.01)}
	b.free()
	return output

func _run() -> void:
	for id: String in Starters.IDS:
		for seed_value: int in [421,7341,1609,975]:
			var run: Dictionary = _play(id,seed_value)
			report.runs.append(run)
			print("RAMP ", id, " seed=",seed_value," first=",run.first_level_seconds," powers60=",run.powers_at_60," reached60=",run.reached_60," status=",run.status)
		var wave: Dictionary = _play(id,421,true)
		report.swarm.append(wave)
		print("RAMP_SWARM ", JSON.stringify(wave))
	for build: Dictionary in [Starters.build_for("breaker"),Starters.build_for("bastion"),{"blade":"guard","ratchet":"low","bit":"needle"},Starters.build_for("vane"),{"blade":"hook","ratchet":"mid","bit":"ball"},{"blade":"balance","ratchet":"mid","bit":"rubber"}]:
		report.assemblies.append(_measure_assembly(build))
	var destination: String = "user://task002b1-ramp.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): destination = argument.trim_prefix("--report=")
	var output: FileAccess = FileAccess.open(destination,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print("RAMP_REPORT ",destination)
	quit()
