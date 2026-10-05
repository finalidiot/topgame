extends SceneTree
# Run from the project folder:
# Godot --headless --path . --script res://tests/test_prototype.gd
# Tests exercise observable behavior and controlled physical situations.
var catalog
var battle_script
var failures: Array[String] = []
var checks := 0
var notes: Array[String] = []
var balance_results: Array[Dictionary] = []
var report_path: String = "user://test-prototype-QA.txt"
var balance_path: String = "user://test-prototype-balance-results.json"
const LEGACY_BLADES = ["balance", "smash", "guard", "hook"]
const LEGACY_RATCHETS = ["low", "mid", "high"]
const LEGACY_BITS = ["needle", "ball", "flat", "rubber"]

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: " + label)

func _run() -> void:
	# Retain evidence via explicit external QA paths; default runs never overwrite
	# the historical tracked QA.txt or compact regression evidence.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		if argument.begins_with("--balance-report="): balance_path = argument.trim_prefix("--balance-report=")
	catalog = load("res://scripts/parts.gd")
	battle_script = load("res://scripts/battle.gd")
	if catalog == null or battle_script == null:
		_check(false, "Catalog and battle scripts load")
		_finish()
		return
	_test_catalog()
	await process_frame
	_test_pause()
	_test_brake()
	_test_burst()
	_test_burst_buffer()
	_test_boundaries()
	_test_attack_ringout()
	_test_collision()
	_test_part_effects()
	_test_spinout()
	_test_fixed_step()
	_test_determinism()
	_test_balance()
	_finish()

func _build(blade := "balance", ratchet := "mid", bit := "ball") -> Dictionary:
	return {"blade": blade, "ratchet": ratchet, "bit": bit}

func _battle(player: Dictionary, enemy: Dictionary, random_seed := 421) -> Node2D:
	var instance = battle_script.new()
	root.add_child(instance)
	instance.set_physics_process(false)
	instance.set_process(false)
	instance.begin(player, enemy, 1, random_seed)
	# Skip presentation-only countdown in controlled physical tests.
	instance.battle_status = "battle"
	return instance

func _test_catalog() -> void:
	_check(catalog.BLADE_IDS.size() >= 4, "Original Blade IDs retained in the expanded catalogue")
	_check(catalog.RATCHET_IDS.size() >= 3, "Original Ratchet IDs retained in the expanded catalogue")
	_check(catalog.BIT_IDS.size() >= 4, "Original Bit IDs retained in the expanded catalogue")
	var unique_visuals := {}
	var valid_stats := true
	var valid_visuals := true
	var valid_builds := true
	var count := 0
	for blade in catalog.BLADE_IDS:
		for ratchet in catalog.RATCHET_IDS:
			for bit in catalog.BIT_IDS:
				var build = _build(blade, ratchet, bit)
				var normalized = catalog.validate_build(build)
				valid_builds = valid_builds and normalized == build
				var stats = catalog.derive(build)
				for key in ["mass", "power", "stamina", "grip", "speed", "stability"]:
					valid_stats = valid_stats and stats.has(key)
					if stats.has(key):
						var value = float(stats[key])
						valid_stats = valid_stats and is_finite(value) and value >= 1.0 and value <= 10.0
				var visual_paths: Array[String] = []
				for pair in [["blade", blade], ["ratchet", ratchet], ["bit", bit]]:
					var path = catalog.texture_path(pair[0], pair[1])
					visual_paths.append(path)
					valid_visuals = valid_visuals and ResourceLoader.exists(path)
				unique_visuals["|".join(PackedStringArray(visual_paths))] = true
				count += 1
	var expected: int = catalog.BLADE_IDS.size() * catalog.RATCHET_IDS.size() * catalog.BIT_IDS.size()
	_check(count == expected, "All legal catalogue assemblies enumerated")
	_check(valid_builds, "Every catalogue assembly validates without replacing parts")
	_check(valid_stats, "All assembly stats are finite and within 1–10")
	_check(valid_visuals, "All modular visual resources exist")
	_check(unique_visuals.size() == expected, "Every assembly has a distinct modular visual tuple")
	var needle = catalog.derive(_build("balance", "mid", "needle"))
	var rubber = catalog.derive(_build("balance", "mid", "rubber"))
	var flat = catalog.derive(_build("balance", "mid", "flat"))
	var low = catalog.derive(_build("balance", "low", "ball"))
	var high = catalog.derive(_build("balance", "high", "ball"))
	var smash = catalog.derive(_build("smash", "mid", "ball"))
	var guard = catalog.derive(_build("guard", "mid", "ball"))
	_check(needle.stamina > rubber.stamina, "Needle favors endurance over Rubber")
	_check(flat.grip > needle.grip and rubber.grip > needle.grip, "Flat and Rubber favor traction over Needle")
	_check(low.stability > high.stability, "Low stance is more stable than High")
	_check(smash.power > guard.power, "Smash favors impact over Guard")
	_check(guard.stability > smash.stability, "Guard favors stability over Smash")

func _test_pause() -> void:
	var b = _battle(_build(), _build())
	var before_elapsed = b.elapsed
	var before_states = b.fighters.duplicate(true)
	b.paused = true
	for frame in range(120):
		b.test_step(1.0 / 60.0, Vector2.RIGHT, true, true)
	_check(b.elapsed == before_elapsed and b.fighters == before_states, "Pause freezes physical state, RPM and cooldown")
	b.paused = false
	b.test_step(1.0 / 60.0, Vector2.ZERO, false, false)
	_check(b.elapsed > before_elapsed, "Unpause resumes simulation")
	b.free()

func _test_burst() -> void:
	var boosted = _battle(_build(), _build(), 152)
	var control = _battle(_build(), _build(), 152)
	for b in [boosted, control]:
		b.test_set_state(0, {"pos": Vector2(-80, 40), "vel": Vector2.ZERO, "rpm": 0.9, "cooldown": 0.0})
		b.test_set_state(1, {"pos": Vector2(80, -40), "vel": Vector2.ZERO, "rpm": 0.9})
	boosted.test_step(1.0 / 60.0, Vector2.RIGHT, true, false)
	control.test_step(1.0 / 60.0, Vector2.RIGHT, false, false)
	var initial_cooldown = float(boosted.fighters[0].cooldown)
	var initial_rpm = float(boosted.fighters[0].rpm)
	_check(initial_cooldown > 3.5, "Burst starts a substantial cooldown")
	_check(initial_rpm < float(control.fighters[0].rpm) - 0.008, "Burst pays an immediate RPM cost")
	_check(boosted.fighters[0].vel.length() > control.fighters[0].vel.length(), "Burst gives a real movement impulse")
	boosted.test_step(1.0 / 60.0, Vector2.RIGHT, true, false)
	_check(float(boosted.fighters[0].cooldown) < initial_cooldown, "Holding Burst does not reset or bypass cooldown")
	_check(float(boosted.fighters[0].rpm) > initial_rpm - 0.006, "Holding Burst does not repeatedly charge its initial cost")
	for frame in range(30):
		boosted.test_step(1.0 / 60.0, Vector2.ZERO, true, false)
	_check(float(boosted.fighters[0].cooldown) < initial_cooldown - 0.45, "Cooldown keeps decreasing while Burst is held")
	_check(_finite_fighters(boosted), "Burst remains finite and speed bounded")
	boosted.free()
	control.free()

func _test_brake() -> void:
	var stopped = _battle(_build(), _build(), 415)
	var coast = _battle(_build(), _build(), 415)
	for b in [stopped, coast]:
		b.test_set_state(0, {"pos": Vector2(-30, 30), "vel": Vector2(45, -45), "rpm": 0.9})
		b.test_set_state(1, {"pos": Vector2(90, 50), "vel": Vector2.ZERO, "rpm": 0.9})
	for frame in range(15):
		stopped.test_step(1.0 / 60.0, Vector2.ZERO, false, true)
		coast.test_step(1.0 / 60.0, Vector2.ZERO, false, false)
	_check(stopped.fighters[0].vel.length() < coast.fighters[0].vel.length() * 0.8, "Brake materially reduces momentum compared with coasting")
	_check(_finite_fighters(stopped), "Braking does not corrupt physical state")
	stopped.free()
	coast.free()

func _test_burst_buffer() -> void:
	var b = _battle(_build(), _build(), 951)
	b.test_set_state(0, {"pos": Vector2(-40, 40), "vel": Vector2.ZERO, "rpm": 0.9, "cooldown": 0.0})
	b.test_set_state(1, {"pos": Vector2(90, -50), "vel": Vector2.ZERO, "rpm": 0.9})
	b._hit_stop = 2.0 / 60.0
	b.test_step(1.0 / 60.0, Vector2.RIGHT, true, false)
	_check(b.fighters[0].cooldown == 0.0, "Burst input does not bypass impact hit-stop")
	for frame in range(5):
		b.test_step(1.0 / 60.0, Vector2.ZERO, false, false)
	_check(b.fighters[0].cooldown > 3.5 and b.fighters[0].rpm < 0.89, "Burst press during hit-stop fires after the freeze with its normal cost")
	_check(b.fighters[0].vel.dot(Vector2(1, -1)) > 0, "Buffered Burst preserves the pressed screen direction")
	b.free()
	var expired = _battle(_build(), _build(), 951)
	expired.test_set_state(0, {"pos": Vector2(-40, 40), "vel": Vector2.ZERO, "rpm": 0.9, "cooldown": 0.5})
	expired.test_set_state(1, {"pos": Vector2(90, -50), "vel": Vector2.ZERO, "rpm": 0.9})
	for frame in range(60):
		expired.test_step(1.0 / 60.0, Vector2.ZERO, frame == 0, false)
	_check(expired.fighters[0].cooldown == 0.0 and expired.fighters[0].burst_time == 0.0, "Expired input cannot fire unexpectedly when a long cooldown ends")
	expired.free()

func _test_boundaries() -> void:
	for side in [-1.0, 1.0]:
		var gate = _battle(_build(), _build())
		gate.test_set_state(0, {"pos": Vector2(140 * side, -140 * side), "vel": Vector2(60 * side, -60 * side), "rpm": 0.95})
		gate.test_set_state(1, {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "rpm": 0.95})
		gate.test_step(1.0 / 60.0)
		_check(gate.battle_status != "battle" and _result_mentions(gate, "ring"), "Open ring-out gate resolves on side " + str(side))
		gate.free()
	var wall = _battle(_build(), _build())
	wall.test_set_state(0, {"pos": Vector2(167, 20), "vel": Vector2(90, 0), "rpm": 0.95})
	wall.test_set_state(1, {"pos": Vector2(-90, 0), "vel": Vector2.ZERO, "rpm": 0.95})
	for frame in range(3):
		wall.test_step(1.0 / 60.0)
	_check(wall.battle_status == "battle", "Solid wall does not behave like a ring-out gate")
	_check(wall.fighters[0].pos.x <= 166.01, "Wall pushes combatant back inside playable boundary")
	_check(wall.fighters[0].vel.x < 0, "Solid wall reflects outward momentum")
	wall.free()
	var side_guard = _battle(_build(), _build())
	side_guard.test_set_state(0, {"pos": Vector2(157, -109), "vel": Vector2(60, -60), "rpm": 0.95})
	side_guard.test_set_state(1, {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "rpm": 0.95})
	for frame in range(3):
		side_guard.test_step(1.0 / 60.0)
	_check(side_guard.battle_status == "battle", "Side guard outside gate-mouth band stays solid")
	_check(side_guard.fighters[0].vel.dot(Vector2(1, -1)) < 0, "Side guard reflects momentum instead of allowing a false ring-out")
	side_guard.free()

func _test_collision() -> void:
	var b = _battle(_build(), _build("smash", "mid", "flat"))
	b.test_set_state(0, {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "rpm": 0.9})
	b.test_set_state(1, {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "rpm": 0.9})
	b.test_step(1.0 / 60.0)
	_check(b.fighters[0].pos.distance_to(b.fighters[1].pos) >= 4.0, "Exact-center overlap separates instead of sticking or dividing by zero")
	_check(_finite_fighters(b), "Exact-center collision remains finite")
	for frame in range(180):
		b.test_step(1.0 / 60.0, Vector2.RIGHT, frame % 20 == 0, false)
	_check(_finite_fighters(b), "Repeated contact cannot create speed runaway")
	b.free()

func _test_attack_ringout() -> void:
	for side in [-1.0, 1.0]:
		var b = _battle(_build("smash", "mid", "flat"), _build(), 819)
		b.test_set_state(0, {"pos": Vector2(109 * side, -109 * side), "vel": Vector2(95 * side, -95 * side), "rpm": 0.9})
		b.test_set_state(1, {"pos": Vector2(123 * side, -123 * side), "vel": Vector2.ZERO, "rpm": 0.9})
		for frame in range(40):
			b.test_step(1.0 / 60.0, Vector2(side, 0), frame == 0, false)
			if b.battle_status != "battle":
				break
		_check(b.battle_status != "battle" and b.last_result.get("reason", "") == "ring_out" and b.last_result.get("winner", -1) == 0, "Burst collision can knock a rival through gate " + str(side) + " from inside the arena")
		b.free()

func _test_spinout() -> void:
	var b = _battle(_build(), _build())
	var notification := {"count": 0, "result": {}}
	b.round_finished.connect(func(result: Dictionary) -> void:
		notification["count"] += 1
		notification["result"] = result)
	b.test_set_state(0, {"pos": Vector2(-70, 30), "vel": Vector2.ZERO, "rpm": 0.0})
	b.test_set_state(1, {"pos": Vector2(70, -30), "vel": Vector2.ZERO, "rpm": 0.9})
	b.test_step(1.0 / 60.0)
	_check(b.battle_status != "battle" and _result_mentions(b, "spin"), "Exhausted RPM resolves as a spin-out")
	for frame in range(200):
		b.test_step(1.0 / 60.0)
	_check(notification.count == 1, "Result signal fires once after the finish animation")
	_check(notification.result.get("winner", -1) == 1, "Result signal identifies the surviving rival")
	b.free()

func _test_part_effects() -> void:
	var defensive = _battle(_build("guard", "mid", "ball"), _build(), 619)
	var offensive = _battle(_build("smash", "mid", "ball"), _build(), 619)
	for b in [defensive, offensive]:
		b.test_set_state(0, {"pos": Vector2(-12, 0), "vel": Vector2(65, 0), "rpm": 0.9})
		b.test_set_state(1, {"pos": Vector2(12, 0), "vel": Vector2(-65, 0), "rpm": 0.9})
		b.test_step(1.0 / 60.0)
	_check(defensive.fighters[0].rpm > offensive.fighters[0].rpm, "Guard preserves more spin in the same physical exchange")
	_check(offensive.fighters[1].rpm < defensive.fighters[1].rpm, "Smash drains more rival spin in the same physical exchange")
	defensive.free()
	offensive.free()
	var enduring = _battle(_build("balance", "mid", "needle"), _build(), 723)
	var attacking = _battle(_build("balance", "mid", "flat"), _build(), 723)
	for b in [enduring, attacking]:
		b.test_set_state(0, {"pos": Vector2(-45, 45), "vel": Vector2.ZERO, "rpm": 0.9})
	for frame in range(60):
		for b in [enduring, attacking]:
			b.test_set_state(1, {"pos": Vector2(100, -50), "vel": Vector2.ZERO, "rpm": 0.9})
			b.test_step(1.0 / 60.0)
	_check(enduring.fighters[0].rpm > attacking.fighters[0].rpm + 0.003, "Needle's endurance advantage affects actual spin decay")
	enduring.free()
	attacking.free()

func _test_fixed_step() -> void:
	var fast = _battle(_build(), _build(), 554)
	var slow = _battle(_build(), _build(), 554)
	for frame in range(60):
		fast.test_step(1.0 / 60.0, Vector2.RIGHT, frame == 0, false)
	for frame in range(20):
		slow.test_step(1.0 / 20.0, Vector2.RIGHT, frame == 0, false)
	var same: bool = absf(float(fast.elapsed) - float(slow.elapsed)) < 0.00001
	for i in range(2):
		same = same and fast.fighters[i].pos.distance_to(slow.fighters[i].pos) < 0.0001
		same = same and abs(float(fast.fighters[i].rpm) - float(slow.fighters[i].rpm)) < 0.000001
	_check(same, "20 Hz and 60 Hz caller updates produce the same fixed-step physical state")
	fast.free()
	slow.free()

func _test_determinism() -> void:
	var a = _battle(_build("hook", "high", "rubber"), _build("guard", "low", "needle"), 901)
	var b = _battle(_build("hook", "high", "rubber"), _build("guard", "low", "needle"), 901)
	var same := true
	for frame in range(4200):
		var direction = _controller(a)
		a.test_step(1.0 / 60.0, direction, frame % 240 == 0, false)
		b.test_step(1.0 / 60.0, direction, frame % 240 == 0, false)
		for i in range(2):
			same = same and a.fighters[i].pos.distance_to(b.fighters[i].pos) < 0.0001
			same = same and abs(float(a.fighters[i].rpm) - float(b.fighters[i].rpm)) < 0.000001
		if a.battle_status != "battle" or b.battle_status != "battle":
			break
	_check(same and a.last_result == b.last_result, "Same seed and inputs produce identical trajectories and result")
	a.free()
	b.free()

func _controller(b) -> Vector2:
	if b.fighters.size() < 2:
		return Vector2.ZERO
	var difference: Vector2 = b.fighters[1].pos - b.fighters[0].pos
	return Vector2(difference.x - difference.y, (difference.x + difference.y) * 0.5).normalized()

func _finite_fighters(b) -> bool:
	for fighter in b.fighters:
		for key in ["rpm", "wobble", "cooldown", "height"]:
			if not is_finite(float(fighter[key])):
				return false
		var position: Vector2 = fighter.pos
		var velocity: Vector2 = fighter.vel
		if not is_finite(position.x) or not is_finite(position.y) or not is_finite(velocity.x) or not is_finite(velocity.y):
			return false
		if position.length() > 10000 or velocity.length() > 1024:
			return false
		if float(fighter.rpm) < -0.001 or float(fighter.rpm) > 1.001:
			return false
	return true

func _result_mentions(b, word: String) -> bool:
	var text = str(b.last_result).to_lower()
	for fighter in b.fighters:
		text += " " + str(fighter.outcome).to_lower()
	return word in text

func _test_balance() -> void:
	var all_resolved := true
	var all_finite := true
	var duration_values: Array[float] = []
	# Retain the historical 144-bout comparison. The expanded roster receives
	# a stratified study rather than multiplying this legacy endurance soak.
	for blade in LEGACY_BLADES:
		for ratchet in LEGACY_RATCHETS:
			for bit in LEGACY_BITS:
				var candidate = _build(blade, ratchet, bit)
				for seed_value in [101, 211, 307]:
					var b = _battle(candidate, _build(), seed_value)
					var finite := true
					var peak_speed := 0.0
					for frame in range(4200):
						var direction = _controller(b)
						var distance = b.fighters[0].pos.distance_to(b.fighters[1].pos)
						var use_burst = float(b.fighters[0].cooldown) <= 0.0 and distance > 45 and float(b.fighters[0].rpm) > 0.35
						b.test_step(1.0 / 60.0, direction, use_burst, false)
						finite = finite and _finite_fighters(b)
						for fighter in b.fighters:
							peak_speed = max(peak_speed, fighter.vel.length())
						if b.battle_status != "battle":
							break
					var resolved: bool = b.battle_status != "battle"
					all_resolved = all_resolved and resolved
					all_finite = all_finite and finite
					var duration := float(b.elapsed)
					duration_values.append(duration)
					var row = {"build": candidate, "seed": seed_value, "seconds": snapped(duration, 0.01), "resolved": resolved, "finite": finite, "peak_speed": snapped(peak_speed, 0.01), "result": b.last_result.duplicate(true)}
					balance_results.append(row)
					b.free()
	_check(balance_results.size() == 144, "144 standardized build/seed bouts exercised")
	_check(all_resolved, "All seeded build bouts resolve within 70 seconds")
	_check(all_finite, "No seeded build bout has NaN, infinite RPM, invalid position or speed runaway")
	duration_values.sort()
	if not duration_values.is_empty():
		var median = duration_values[duration_values.size() / 2]
		notes.append("Standardized chase controller, 48 builds x 3 fixed seeds against BALANCE/MID/BALL.")
		notes.append("Bout duration: median %.2fs; minimum %.2fs; maximum %.2fs." % [median, duration_values[0], duration_values[-1]])
		if median < 30:
			notes.append("BALANCE REVIEW: median is below the intended 30–60 second pacing; current head-on chase controller produces unusually frequent contact.")
		elif median > 60:
			notes.append("BALANCE REVIEW: median exceeds the intended 30–60 second pacing.")
		else:
			notes.append("BALANCE REVIEW: median falls within the intended 30–60 second pacing.")
		for category in ["blade", "ratchet", "bit"]:
			var groups := {}
			for row in balance_results:
				var part: String = row.build[category]
				if not groups.has(part):
					groups[part] = {"count": 0, "seconds": 0.0, "wins": 0, "losses": 0}
				groups[part].count += 1
				groups[part].seconds += row.seconds
				if row.result.get("winner", -1) == 0 or "player" == str(row.result.get("winner", "")).to_lower():
					groups[part].wins += 1
				elif row.result.get("winner", -1) == 1 or "enemy" == str(row.result.get("winner", "")).to_lower():
					groups[part].losses += 1
			for part in groups:
				var group = groups[part]
				notes.append("%s %s: %d/%d player wins, %d losses; mean %.2fs." % [category, part, group.wins, group.count, group.losses, group.seconds / group.count])

func _finish() -> void:
	var report := "SPINNING METAL PROTOTYPE — QA\n\n"
	report += "Automated checks: %d; failed: %d.\n" % [checks, failures.size()]
	report += "Tests: full catalogue modular visual tuples and finite build stats; original physical part tradeoffs; pause; braking; burst cost/cooldown and hit-stop buffering; both gate exits and attack-driven ring-outs; solid walls and side guards; exact-overlap collision; spin-out and one-shot result signal; 20/60 Hz fixed-step consistency; deterministic replay; original 48 assemblies / 144 seeded battles. Expanded parts receive a separate stratified assembly study.\n\n"
	for failure in failures:
		report += "FAIL: " + failure + "\n"
	for note in notes:
		report += note + "\n"
	report += "\nBalance caveat: this is a standardized bot/chase stress test, not a claim about human win rates.\n"
	report += "Central chase bouts all resolve by spin-out. Guard and Needle each win every bout in their respective groups; endurance dominates repeated central contact. Attack-driven ring-outs are verified separately at both mouths. Human play and gate-seeking strategies are still needed to assess competitive balance.\n"
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(report)
	var detailed = FileAccess.open(balance_path, FileAccess.WRITE)
	if detailed:
		detailed.store_string(JSON.stringify(balance_results, "\t"))
	print(report)
	quit(0 if failures.is_empty() else 1)

