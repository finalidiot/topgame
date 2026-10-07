extends SceneTree
## Filter fixtures are presentation-only. Live cases below use legal initial
## builds/powers and ordinary controls, comparing exact simulation with/without.
const Beasts = preload("res://scripts/beast_manifestations.gd")
const Battle = preload("res://scripts/battle.gd")
const Review = preload("res://tests/capture_beast_manifestations.gd")
var checks: int = 0
var failures: Array[String] = []
var measurements: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func filter_cases() -> void:
	var state: Dictionary = Beasts.orientation_state(Vector2.RIGHT)
	for tick: int in range(180):
		state = Beasts.orientation_step(state, Vector2.RIGHT.rotated(sin(float(tick)) * 0.15) * 90.0, Battle.FIXED_DT)
	check(state.responses == 0 and state.direction == Vector2.RIGHT and not state.mirror, "Steady travel and small corrections leave authored facing entirely stable")
	for tick: int in range(5): state = Beasts.orientation_step(state, Vector2.LEFT * 90.0, Battle.FIXED_DT)
	check(state.responses == 0 and not state.mirror, "A significant turn requires its full sustained heading hold")
	state = Beasts.orientation_step(state, Vector2.LEFT * 90.0, Battle.FIXED_DT)
	check(state.responses == 1 and state.mirror and state.direction == Vector2.LEFT, "A held meaningful left turn commits one complete-frame mirror")
	for tick: int in range(12): state = Beasts.orientation_step(state, Vector2.RIGHT * 90.0, Battle.FIXED_DT)
	check(state.responses == 1 and state.mirror, "Settle lock prevents immediate opposite-facing flicker")
	for tick: int in range(8): state = Beasts.orientation_step(state, Vector2.RIGHT * 90.0, Battle.FIXED_DT)
	check(state.responses == 2 and not state.mirror and state.direction == Vector2.RIGHT, "A sustained opposite turn responds after settle without continuous tracking")
	for tick: int in range(60): state = Beasts.orientation_step(state, Vector2.RIGHT * 90.0, Battle.FIXED_DT)
	check(state.responses == 2 and is_zero_approx(float(state.settle_remaining)), "Stable new travel settles and resumes untouched authored behavior")
	var stable: Dictionary = state.duplicate(true)
	for tick: int in range(120): state = Beasts.orientation_step(state, Vector2.LEFT * (0.5 if tick % 2 == 0 else 15.0), Battle.FIXED_DT)
	check(state.direction == stable.direction and state.mirror == stable.mirror and state.responses == stable.responses, "Near-stationary and subthreshold movement retain last meaningful facing")
	state = Beasts.orientation_step(state, Vector2(NAN, INF), Battle.FIXED_DT)
	check(state.direction == stable.direction and state.responses == stable.responses, "Invalid velocity cannot contaminate presentation heading")
	check(Beasts.orientation_step(state, Vector2.LEFT * 90.0, NAN) == state and Beasts.orientation_step(state, Vector2.LEFT * 90.0, -1.0) == state, "Invalid or negative time cannot advance filter state")
	var vertical: Vector2 = Vector2.ONE.normalized()
	state = Beasts.orientation_state(Vector2.LEFT)
	for tick: int in range(60): state = Beasts.orientation_step(state, vertical.rotated(0.03 if tick % 2 == 0 else -0.03) * 90.0, Battle.FIXED_DT)
	check(state.mirror and state.responses == 0, "Projected vertical deadzone retains meaningful heading and facing rather than toggling left/right")
	state = Beasts.orientation_state(Vector2.UP)
	for tick: int in range(90): state = Beasts.orientation_step(state, Vector2.UP.rotated(-float(tick) * PI / 180.0) * 90.0, Battle.FIXED_DT)
	check(state.mirror and state.responses == 1, "A gradual left turn crosses the vertical seam without silently consuming its facing response")
	state = Beasts.orientation_state(Vector2.RIGHT)
	for tick: int in range(120): state = Beasts.orientation_step(state, Vector2.LEFT.rotated(0.5 if tick % 2 == 0 else -0.5) * 90.0, Battle.FIXED_DT)
	check(state.responses == 0 and not state.mirror, "Incoherent rapidly alternating turn candidates never earn a response")
	state = Beasts.orientation_state(Vector2.RIGHT)
	state = Beasts.orientation_step(state, Vector2.RIGHT.rotated(deg_to_rad(-46.0))*90.0, Battle.FIXED_DT)
	for tick: int in range(5): state = Beasts.orientation_step(state, Vector2.RIGHT.rotated(deg_to_rad(-40.0))*90.0, Battle.FIXED_DT)
	check(state.responses == 1, "A turn that entered at 45 degrees retains its candidate within the 30-to-45-degree hysteresis band")
	state = Beasts.orientation_state(Vector2.RIGHT)
	state = Beasts.orientation_step(state, Vector2.RIGHT.rotated(deg_to_rad(-46.0))*90.0, Battle.FIXED_DT)
	state = Beasts.orientation_step(state, Vector2.RIGHT.rotated(deg_to_rad(-29.0))*90.0, Battle.FIXED_DT)
	for tick: int in range(20): state = Beasts.orientation_step(state, Vector2.RIGHT.rotated(deg_to_rad(-40.0))*90.0, Battle.FIXED_DT)
	check(state.responses == 0 and Vector2(state.candidate) == Vector2.ZERO, "Crossing the exit threshold cancels a turn; the intermediate band cannot restart it")
	measurements.append({"case":"filter","state":Review.portable(state),"enter_degrees":rad_to_deg(Beasts.ORIENTATION_ENTER),"exit_degrees":rad_to_deg(Beasts.ORIENTATION_EXIT),"hold_seconds":Beasts.ORIENTATION_HOLD,"settle_seconds":Beasts.ORIENTATION_SETTLE})

func prepare(s: Dictionary, enabled: bool) -> Node2D:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_process(false); battle.set_physics_process(false)
	battle.beast_manifestations_enabled = enabled
	battle.begin_run(s.build, Review.descriptor(s), int(s.seed))
	for tick: int in range(300):
		if battle.battle_status == "battle": break
		battle.test_step(Battle.FIXED_DT)
	check(battle.battle_status == "battle", "Legal orientation case passes real countdown")
	return battle

func live_cases() -> void:
	for s: Dictionary in Review.SCENARIOS:
		var shown: Node2D = prepare(s, true)
		var hidden: Node2D = prepare(s, false)
		var instances: int = 0
		var responses: int = 0
		for tick: int in range(roundi(float(s.seconds) * 60.0)):
			var control: Dictionary = Review.controls(shown, str(s.policy), tick)
			shown.test_step(Battle.FIXED_DT, control.direction, control.burst, control.brake)
			hidden.test_step(Battle.FIXED_DT, control.direction, control.burst, control.brake)
			check(shown.snapshot() == hidden.snapshot() and shown.continuous.economy.snapshot() == hidden.continuous.economy.snapshot(), "Direction response preserves exact positions/collisions/timing/RPM/reserve")
			check(shown.powers.events == hidden.powers.events and shown.continuous.director.history == hidden.continuous.director.history, "Direction response preserves small powers and admission decisions")
			for item: Dictionary in shown.beast_presentation_snapshot().active:
				instances += 1
				var geometry: Dictionary = shown.beasts.draw_geometry_for(item)
				var point: Vector2 = shown.project(Vector2(shown.entity(int(item.owner_entity_id)).pos), float(shown.entity(int(item.owner_entity_id)).height)) if item.follow_owner else shown.project(Vector2(item.world_pos))
				var rect: Rect2 = geometry.rect
				check(absf(rect.position.x + 64.0 - point.x) <= 0.501 and absf(rect.position.y + 96.0 + float(geometry.lift) - point.y) <= 0.501, "Native filtered root retains actual projected floor pivot")
				responses = maxi(responses, int(item.orientation_responses))
		var frozen: Dictionary = shown.beast_presentation_snapshot()
		shown.set_paused(true)
		for tick: int in range(12): shown.test_step(Battle.FIXED_DT, Vector2.LEFT, true, true)
		check(shown.beast_presentation_snapshot() == frozen, "Pause freezes facing candidates and settle state")
		shown.set_paused(false)
		shown.beasts.finish()
		check(shown.beast_presentation_snapshot().orientations.is_empty(), "Outcome clears orientation state")
		shown.beasts.reset()
		check(shown.beast_presentation_snapshot().orientations.is_empty(), "Reset clears orientation state")
		measurements.append({"beast":s.identity, "actual_visible_frames":instances, "max_responses":responses, "actual_contacts":shown.hits})
		shown.free(); hidden.free()

func motion_fixture_event(id: int = 1) -> Dictionary:
	return {"collision_id":id, "first_entity_id":1, "second_entity_id":2, "impulse":(Beasts.EXTREME_IMPACT_SCORE + 1.0) / 300.0,
		"closing":300.0, "normal":Vector2.RIGHT, "position":Vector2(12.0,18.0), "first_velocity":Vector2.RIGHT * 90.0}

func authored_completion_stress() -> void:
	# Explicit root/animation fixtures are separate from naturally rare review
	# collisions. Facing cannot control clocks, phase changes or frame playback.
	var turns: Array[float] = [0.0, 0.3375, 0.492, 0.52, 0.61, 0.76, 1.06, 1.30, -1.0, -2.0, -3.0]
	for s: Dictionary in Review.SCENARIOS:
		for turn_at: float in turns:
			var b: Node2D = prepare(s, true)
			var p: Dictionary = b.player_entity()
			check(b.beasts.accept_impact(motion_fixture_event()), "Qualifying presentation fixture begins exactly one authored movement")
			var frames: Dictionary = {}; var phases: Dictionary = {}
			var age: float = 0.0
			var previous_frame: int = -1
			var travel_mirror: bool = false
			var travel_started: bool = false
			var pending_seen: bool = false
			for tick: int in range(190):
				var snap: Dictionary = b.beast_presentation_snapshot()
				if snap.count == 0: break
				var item: Dictionary = snap.active[0]
				var frame: int = b.beasts.frame_for(item.beast, item.phase, item.phase_age)
				frames[frame] = true; phases[str(item.phase)] = true
				check(frame >= previous_frame, "Facing changes never rewind/reset authored frame timeline")
				check(float(item.age) + 0.000001 >= age and item.instance_id == 1 and item.collision_id == 1, "One collision retains monotonic age and instance through every phase")
				previous_frame = frame; age = float(item.age)
				if item.beast == "black_arrow" and item.phase == "travel":
					if not travel_started: travel_mirror = bool(item.orientation_mirror); travel_started = true
					check(bool(item.orientation_mirror) == travel_mirror, "Black Arrow travel/inversion retains stable root facing while timeline continues")
					if bool(item.pending_mirror) != bool(item.orientation_mirror): pending_seen = true
				if turn_at == -1.0: p.vel = Vector2.RIGHT * (90.0 if tick % 24 < 12 else -90.0)
				elif turn_at == -2.0: p.vel = Vector2.RIGHT * (90.0 if tick % 2 == 0 else -90.0)
				elif turn_at == -3.0: p.vel = Vector2.LEFT * 0.01
				else: p.vel = Vector2.LEFT * 90.0 if age >= turn_at else Vector2.RIGHT * 90.0
				if tick == 60:
					check(not b.beasts.accept_impact(motion_fixture_event(2)), "Another qualifying impact during the movement neither duplicates nor restarts it")
				b.beasts.update(1.0 / 120.0)
			check(b.beast_presentation_snapshot().count == 0 and b.beast_presentation_snapshot().spawned == 1, "All four authored movements reach clean terminal state at native duration")
			check(phases.has("prepare") and phases.has("travel") and phases.has("strike") and phases.has("recovery"), "Every direction stress retains PREPARE -> TRAVEL -> STRIKE -> RECOVERY")
			check(frames.size() == 16, "All 16 authored action keys play without deleting inversion or recovery")
			if s.identity == "black_arrow" and turn_at == 0.52: check(pending_seen, "An upside-down turn records pending facing while somersault keeps advancing")
			measurements.append({"fixture":true, "beast":s.identity, "turn_seconds":turn_at, "frames_seen":frames.keys(), "phases":phases.keys(), "last_visible_age":age, "pending_turn_during_travel":pending_seen})
			b.free()

func coarse_pause_and_terminal_stress() -> void:
	var s: Dictionary = Review.SCENARIOS[0]
	for dt: float in [1.0 / 15.0, 0.20, 0.49, 1.351, 10.0]:
		var b: Node2D = prepare(s, true)
		b.beasts.accept_impact(motion_fixture_event())
		var total: float = 0.0
		for tick: int in range(30):
			if b.beast_presentation_snapshot().count == 0: break
			b.player_entity().vel = Vector2.RIGHT * (90.0 if tick % 2 == 0 else -90.0)
			b.beasts.update(dt); total += dt
		check(b.beast_presentation_snapshot().count == 0 and total <= 1.35 + dt + 0.000001, "Coarse delta carries phase excess and resolves without held intermediate key")
		var phase_events: Array[String] = []
		for event: Dictionary in b.beast_presentation_snapshot().events:
			if event.kind == "phase": phase_events.append(str(event.phase))
		check(phase_events == ["travel", "strike", "recovery"], "Even a huge delta records every authored transition in order")
		b.free()
	var b: Node2D = prepare(s, true)
	b.beasts.accept_impact(motion_fixture_event()); b.beasts.update(0.52)
	var frozen: Dictionary = b.beast_presentation_snapshot()
	b.set_paused(true)
	for tick: int in range(20): b.beasts.update(0.25)
	check(b.beast_presentation_snapshot() == frozen, "Pause around inverted key freezes both animation and orientation together")
	b.set_paused(false); b.battle_status = "reentry"
	b.beasts.update(3.0)
	check(b.beast_presentation_snapshot() == frozen, "READY/re-entry suspends the same authored timeline intact")
	b.battle_status = "battle"; b.beasts.update(0.83)
	check(b.beast_presentation_snapshot().count == 0, "Re-entry continuation completes recovery using remaining native duration")
	b.beasts.reset(); b.beasts.accept_impact(motion_fixture_event()); b.beasts.update(0.52)
	b.player_entity().outcome = "spin_out"; b.beasts.update(0.01)
	check(b.beast_presentation_snapshot().count == 0, "Owner retirement removes an intermediate key into valid absent terminal state")
	b.player_entity().outcome = ""; b.beasts.reset(); b.beasts.accept_impact(motion_fixture_event())
	b.battle_status = "finished"; b.beasts.update(0.01)
	check(b.beast_presentation_snapshot().count == 0, "Battle outcome leaves no held intermediate key")
	b.battle_status = "battle"; b.beasts.reset(); b.reduced_flashing = false
	b.beasts.accept_impact(motion_fixture_event()); b.beasts.update(0.52)
	var ordinary: Dictionary = b.beast_presentation_snapshot()
	b.beasts.reset(); b.reduced_flashing = true
	b.beasts.accept_impact(motion_fixture_event()); b.beasts.update(0.52)
	check(b.beast_presentation_snapshot() == ordinary, "Reduced Flashing retains the same steady translucent spirit with no brightness pulse state")
	b.free()

func run() -> void:
	filter_cases()
	authored_completion_stress()
	coarse_pause_and_terminal_stress()
	live_cases()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			assert(file != null)
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}, "\t")); file.close()
	print("BEAST_ORIENTATION_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
