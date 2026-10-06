extends SceneTree
## Music progression policy and real-engine cursor coverage, with native playback
## disabled. Controlled boundary observations are explicitly labelled policy
## fixtures copied from the real continuous-Run schema; they are not gameplay.

const Music = preload("res://scripts/music.gd")
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const HEALTHY: Dictionary = {"player_rpm":0.9}
const TIMES: Array[float] = [0.0, 35.0, 100.0, 210.0, 360.0]
const CLEARS: Array[int] = [0, 2, 4, 7, 10]
const NAMES: Array[String] = ["opening", "drive", "lead", "anthem", "full"]
const PRESSURE: Array[float] = [0.0, 0.25, 0.5, 0.75, 0.75]
const BOSS: Array[float] = [0.0, 0.0, 0.25, 0.5, 0.75]
var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {"boundary_observations_are_controlled_policy_fixtures":true,
	"native_audio_playback_enabled":false}
var _real_schema: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _tick(music: Node, seconds: float) -> void:
	for frame: int in range(ceili(seconds * 60.0)):
		music.advance_presentation(1.0 / 60.0)

func _music() -> Node:
	var music: Node = Music.new()
	root.add_child(music)
	music.set_process(false)
	music.set_context("run")
	music.observe_run({}, {})
	check(not bool(music.music_snapshot().playing) and int(music.music_snapshot().transport_starts) == 0, "Read-only music tests never start the native transport")
	return music

func _fixture(seconds: float = 0.0, tier: int = 0, cleared: int = 0, seed_value: int = 701) -> Dictionary:
	# Alter a detached observation, never Battle/Director/RPM state. Its actual
	# continuous schema was captured before any table entries are constructed.
	var state: Dictionary = _real_schema.duplicate(true)
	state.run_seed = seed_value
	state.survival_time = seconds
	state.limits = {"tier":tier, "budget":2.8}
	state.threats_cleared = cleared
	state.census = {"pressure":2.6, "bosses":0, "elites":0, "active_total":2}
	state.calm = false
	return state

func _stage(result: Dictionary, expected: int, context: String) -> void:
	check(int(result.stage) == expected, context + " selects its contractual stage")
	check(str(result.name) == NAMES[expected], context + " names that stage consistently")
	check(is_equal_approx(float(result.pressure_floor), PRESSURE[expected]), context + " earns its pressure floor")
	check(is_equal_approx(float(result.boss_floor), BOSS[expected]), context + " earns its independent boss/anthem floor")

func _capture_real_schema() -> void:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.begin_run({"blade":"guard", "ratchet":"mid", "bit":"needle"}, Encounters.for_run_event(1, 701), 701)
	_real_schema = battle.continuous.snapshot().duplicate(true)
	check(_real_schema.has("survival_time") and _real_schema.has("run_seed") and bool(_real_schema.get("director", false)), "Boundary fixtures begin with an actual continuous.snapshot schema")
	var before: Dictionary = battle.snapshot().duplicate(true)
	var economy_before: Dictionary = battle.continuous.economy.snapshot().duplicate(true)
	var observed_before: Dictionary = _real_schema.duplicate(true)
	var music: Node = _music()
	music.observe_run(_real_schema, {"player_rpm":battle.player_entity().rpm})
	_stage(music.music_snapshot().progression, 0, "Actual opening Run")
	check(_real_schema == observed_before and battle.snapshot() == before and battle.continuous.economy.snapshot() == economy_before, "Read-only observation cannot alter its source, actual Battle or RPM ledger")
	measurements.actual_opening = {"schema":_real_schema.duplicate(true), "progression":music.music_snapshot().progression}
	music.free()
	battle.free()

func _boundaries() -> void:
	_stage(Music.progression_targets(_fixture(), HEALTHY), 0, "Controlled opening observation")
	var table: Array[Dictionary] = []
	for stage: int in range(1, TIMES.size()):
		for route: String in ["survival_time", "director_tier", "threats_cleared"]:
			for side: int in [-1, 0, 1]:
				var state: Dictionary = _fixture()
				if route == "survival_time": state.survival_time = TIMES[stage] + float(side) * 0.001
				elif route == "director_tier": state.limits.tier = stage + side
				else: state.threats_cleared = CLEARS[stage] + side
				var expected: int = stage - 1 if side < 0 else stage
				# Tier +1 deliberately reaches the next OR boundary.
				if route == "director_tier" and side > 0: expected = mini(4, stage + 1)
				var before: Dictionary = state.duplicate(true)
				var result: Dictionary = Music.progression_targets(state, HEALTHY)
				_stage(result, expected, "Controlled %s stage%d side%d" % [route, stage, side])
				check(state == before, "Static progression policy leaves the detached boundary observation unchanged")
				table.append({"route":route, "boundary_stage":stage, "side":side, "expected":expected, "result":result})
	_stage(Music.progression_targets(_fixture(40.0, 0, 10), HEALTHY), 4, "Most advanced independent OR milestone")
	_stage(Music.progression_targets(_fixture(20000.0, 90, 900), HEALTHY), 4, "Late overdrive remains within the authored five-stage arrangement")
	measurements.boundaries = table

func _schema_gates() -> void:
	var duel: Dictionary = {"elapsed":1000.0, "limits":{"tier":4}, "threats_cleared":99,
		"census":{"pressure":2.6, "bosses":0, "elites":0, "active_total":2}}
	var result: Dictionary = Music.progression_targets(duel, {"elapsed":1000.0, "player_rpm":0.9})
	_stage(result, 0, "Duel elapsed without a continuous-Run marker")
	check(not bool(result.continuous) and float(result.elapsed) == 0.0 and int(result.tier) == 0 and int(result.threats_cleared) == 0, "Unrelated duel counters cannot earn a persistent Run music floor")
	_stage(Music.progression_targets({"survival_time":35.0}, HEALTHY), 1, "Authoritative continuous survival_time")
	_stage(Music.progression_targets({"run_seed":0}, {"elapsed":100.0}), 2, "A genuine zero Run seed still marks the continuous schema")
	_stage(Music.progression_targets({"director":true}, {"elapsed":210.0}), 3, "The explicit real Director marker enables its HUD time fallback")
	_stage(Music.progression_targets({}, {"continuous_run":true, "elapsed":360.0}), 4, "An explicit continuous HUD observation enables its elapsed fallback")
	_stage(Music.progression_targets(_fixture(1.0), {"continuous_run":true, "elapsed":999.0}), 0, "survival_time takes precedence over a larger HUD elapsed value")
	for seconds: float in [-1.0, NAN, INF]:
		var invalid: Dictionary = Music.progression_targets(_fixture(seconds, -1, -1), HEALTHY)
		_stage(invalid, 0, "Negative/nonfinite controlled observation")
		check(float(invalid.elapsed) == 0.0 and int(invalid.tier) == 0 and int(invalid.threats_cleared) == 0, "Invalid counters do not poison retained maxima or mixer gains")

func _retention_and_pause() -> void:
	var music: Node = _music()
	var earned: Dictionary = _fixture(100.0, 2, 4)
	music.observe_run(earned, HEALTHY)
	_tick(music, 3.0)
	var retained: Dictionary = music.music_snapshot().progression.duplicate(true)
	_stage(retained, 2, "Earned real-schema lead milestone")
	var calm: Dictionary = _fixture(2.0, 0, 0)
	calm.calm = true
	calm.census.pressure = 0.0
	music.observe_run(calm, HEALTHY)
	_tick(music, 4.0)
	check(music.music_snapshot().progression == retained, "Same-seed lower elapsed/tier/clears cannot erase earned monotonic maxima")
	check(music.music_snapshot().targets[3] == 0.5 and music.music_snapshot().targets[4] == 0.25, "A calm census releases temporary density only down to the earned floors")
	var authoritative: Dictionary = Music.adaptive_targets(calm, HEALTHY, retained)
	check(float(authoritative.pressure) == 0.5 and float(authoritative.boss) == 0.25, "Static adaptive policy honours the retained progression snapshot during calm")
	music.set_paused(true)
	var paused_before: Dictionary = music.music_snapshot().progression.duplicate(true)
	music.observe_run(_fixture(999.0, 20, 100), HEALTHY)
	_tick(music, 90.0)
	check(music.music_snapshot().progression == paused_before, "Paused future observations and ninety seconds of presentation ticks cannot age Run progression")
	check(is_equal_approx(float(music.music_snapshot().targets[3]), 0.5 * 0.35) and is_equal_approx(float(music.music_snapshot().targets[4]), 0.25 * 0.35), "Pause subdues retained floors without secretly switching to a later arrangement")
	music.set_paused(false)
	music.observe_run(_fixture(210.0, 3, 7), HEALTHY)
	_tick(music, 3.0)
	_stage(music.music_snapshot().progression, 3, "Resumed actual milestone observation")
	var previous_gains: Array = music.music_snapshot().gains
	check(float(previous_gains[3]) > 0.0 and float(previous_gains[4]) > 0.0, "The old Run has actual nonzero late-layer gains before testing a seed change")
	music.observe_run(_fixture(0.0, 0, 0, 702), HEALTHY)
	_stage(music.music_snapshot().progression, 0, "Different real Run seed resets arrangement maturity")
	check(float(music.music_snapshot().progression.elapsed) == 0.0 and int(music.music_snapshot().progression.run_seed) == 702, "Different seed resets counters rather than inheriting the previous Run's age")
	check(music.music_snapshot().targets[3] == 0.0 and music.music_snapshot().targets[4] == 0.0, "A changed seed immediately clears old late-layer targets even when the new stable opening already equals zero")
	check(music.music_snapshot().gains == previous_gains, "Seed reset retains actual existing gains for a graceful crossfade instead of hard-zeroing audio")
	_tick(music, 1.0)
	var faded_gains: Array = music.music_snapshot().gains
	check(float(faded_gains[3]) > 0.0 and float(faded_gains[3]) < float(previous_gains[3]), "The old pressure layer genuinely fades after seed reset")
	check(float(faded_gains[4]) > 0.0 and float(faded_gains[4]) < float(previous_gains[4]), "The old boss layer genuinely fades after seed reset")
	check(music.music_snapshot().targets[3] == 0.0 and music.music_snapshot().targets[4] == 0.0, "Presentation ticks cannot retain or resurrect stale late-layer targets for the new opening")
	music.observe_run(_fixture(360.0, 4, 10, 702), HEALTHY)
	_stage(music.music_snapshot().progression, 4, "New Run independently earns its full stage")
	_tick(music, 3.0)
	check(music.music_snapshot().targets[3] == 0.75 and music.music_snapshot().targets[4] == 0.75, "Genuine new-seed milestones can rebuild both earned targets normally after the reset")
	check(float(music.music_snapshot().gains[3]) > float(faded_gains[3]) and float(music.music_snapshot().gains[4]) > float(faded_gains[4]), "The new Run raises both actual gain envelopes normally without replacing the transport")
	music.observe_run({}, {})
	_stage(music.music_snapshot().progression, 0, "Explicit existing Main reset observation")
	check(not bool(music.music_snapshot().progression.continuous) and music.music_snapshot().targets[3] == 0.0 and music.music_snapshot().targets[4] == 0.0, "Explicit reset clears floors and pending adaptive candidates immediately")
	music.observe_run(duel_observation(), {"elapsed":999.0, "player_rpm":0.9})
	_tick(music, 4.0)
	_stage(music.music_snapshot().progression, 0, "A duel after explicit reset cannot rebuild a Run floor")
	check(int(music.music_snapshot().transport_starts) == 0 and not bool(music.music_snapshot().playing), "Pause, stage changes, seed changes and reset never start native audio in the default test configuration")
	measurements.retention = {"earned":retained, "paused":paused_before, "final":music.music_snapshot()}
	music.free()

func duel_observation() -> Dictionary:
	return {"elapsed":999.0, "census":{"pressure":2.6, "bosses":0, "elites":0, "active_total":2}, "limits":{"tier":0}}

func _temporary_surges() -> void:
	var music: Node = _music()
	var calm: Dictionary = _fixture(100.0, 2, 4)
	calm.calm = true
	calm.census.pressure = 0.0
	music.observe_run(calm, HEALTHY)
	_tick(music, 4.0)
	var mature: Dictionary = music.music_snapshot().progression.duplicate(true)
	var boss: Dictionary = calm.duplicate(true)
	boss.calm = false
	boss.census = {"pressure":14.0, "bosses":1, "elites":1, "active_total":9}
	var gains_before: Array = music.music_snapshot().gains
	music.observe_run(boss, HEALTHY)
	check(music.music_snapshot().targets[3] == 1.0 and music.music_snapshot().targets[4] == 1.0, "A genuinely reported boss temporarily intensifies above the earned lead floors")
	check(music.music_snapshot().gains == gains_before, "Boss target changes do not jump actual gain envelopes")
	music.advance_presentation(1.0 / 60.0)
	check(float(music.music_snapshot().gains[3]) > float(gains_before[3]) and float(music.music_snapshot().gains[3]) - float(gains_before[3]) < 0.02, "The actual pressure gain attacks through a small bounded ramp")
	music.observe_run(calm, HEALTHY)
	_tick(music, 2.3)
	check(music.music_snapshot().targets[4] == 1.0, "Boss release waits for sustained calm rather than dropping on one absent census")
	_tick(music, 0.4)
	check(music.music_snapshot().targets[3] == 0.5 and music.music_snapshot().targets[4] == 0.25, "Boss release hysteresis settles at the earned stage rather than the opening arrangement")
	check(music.music_snapshot().progression == mature, "A temporary boss surge does not fabricate survival, tier or clear progression")
	_tick(music, 2.1)
	var danger: Dictionary = Music.adaptive_targets(calm, {"player_rpm":0.17}, mature)
	check(float(danger.pressure) > 0.5 and float(danger.boss) > 0.25 and bool(danger.danger), "Actual low reserve may still rise above the retained floors")
	music.observe_run(calm, {"player_rpm":0.17})
	_tick(music, 0.8)
	check(float(music.music_snapshot().targets[3]) > 0.5, "A sustained danger observation earns only its temporary pressure plateau")
	music.observe_run(calm, HEALTHY)
	_tick(music, 2.3)
	check(float(music.music_snapshot().targets[3]) > 0.5, "Recovered reserve still respects release hysteresis")
	_tick(music, 0.4)
	check(music.music_snapshot().targets[3] == 0.5 and music.music_snapshot().targets[4] == 0.25, "Recovered reserve calms only to the earned lead arrangement")
	check(music.music_snapshot().progression == mature, "Danger/recovery never ages or downgrades the true Run milestone")
	measurements.surges = music.music_snapshot()
	music.free()

func _real_observations() -> void:
	var runs: Array[Dictionary] = []
	for seed_value: int in [701, 702]:
		var battle: Node2D = Battle.new()
		root.add_child(battle)
		battle.set_physics_process(false)
		battle.begin_run({"blade":"guard", "ratchet":"mid", "bit":"needle"}, Encounters.for_run_event(1, seed_value), seed_value)
		var music: Node = _music()
		var maximum_time: float = 0.0
		var maximum_stage: int = 0
		var samples: int = 0
		var steps: int = 0
		for frame: int in range(90 * 60):
			# Real deterministic replay. No outcome/RPM/Director/census injection.
			var direction: Vector2 = Vector2(cos(float(frame) / 180.0), sin(float(frame) / 180.0)) * 0.35
			battle.test_step(1.0 / 60.0, direction, false, false)
			steps += 1
			if frame % 60 == 0:
				var state: Dictionary = battle.continuous.snapshot().duplicate(true)
				var before: Dictionary = battle.snapshot().duplicate(true)
				var economy: Dictionary = battle.continuous.economy.snapshot().duplicate(true)
				var director_rng: int = battle.continuous.director.rng.state
				music.observe_run(state, {"player_rpm":battle.player_entity().rpm, "continuous_run":true})
				check(battle.snapshot() == before and battle.continuous.economy.snapshot() == economy and battle.continuous.director.rng.state == director_rng, "Progression observes actual replay without changing entities, RPM or Director RNG")
				var earned: Dictionary = Music.progression_targets(state, {"player_rpm":battle.player_entity().rpm})
				var current: Dictionary = music.music_snapshot().progression
				check(int(current.stage) >= int(earned.stage) and int(current.stage) >= maximum_stage, "Real Run observations retain every actually earned milestone monotonically")
				maximum_stage = int(current.stage)
				maximum_time = maxf(maximum_time, float(state.survival_time))
				samples += 1
			music.advance_presentation(1.0 / 60.0)
			if battle.battle_status == "finished": break
		check(int(music.music_snapshot().transport_starts) == 0, "Actual replay observations still never start default native playback")
		runs.append({"seed":seed_value, "observations":samples, "fixed_steps":steps,
			"actual_survival_time":maximum_time, "actual_maximum_stage":maximum_stage,
			"crossed_actual_35_seconds":maximum_time >= 35.0, "outcome":battle.last_result.duplicate(true),
			"progression":music.music_snapshot().progression})
		music.free()
		battle.free()
	measurements.actual_fixed_step_runs = runs

func _late_surges() -> void:
	var results: Array[Dictionary] = []
	for cause: String in ["danger", "overclock", "boss"]:
		var music: Node = _music()
		var calm: Dictionary = _fixture(360.0, 4, 10)
		calm.calm = true
		calm.census.pressure = 0.0
		music.observe_run(calm, HEALTHY)
		_tick(music, 4.0)
		var mature: Dictionary = music.music_snapshot().progression.duplicate(true)
		_stage(mature, 4, "Earned full arrangement before controlled " + cause)
		check(music.music_snapshot().targets[3] == 0.75 and music.music_snapshot().targets[4] == 0.75, "Full-stage calm retains headroom for a temporary late surge")
		var observed: Dictionary = calm.duplicate(true)
		var stats: Dictionary = HEALTHY.duplicate(true)
		var expected_boss: float = 0.75
		if cause == "danger":
			stats.player_rpm = 0.17
			expected_boss = 1.0
		elif cause == "overclock":
			stats.redline_active = true
			stats.redline_heat = 0.7
		else:
			observed.census = {"pressure":8.0, "bosses":1, "elites":0, "active_total":3}
			observed.calm = false
			expected_boss = 1.0
		var source_before: Dictionary = observed.duplicate(true)
		var stats_before: Dictionary = stats.duplicate(true)
		var target: Dictionary = Music.adaptive_targets(observed, stats, mature)
		check(float(target.pressure) == 1.0 and float(target.pressure) > float(mature.pressure_floor), "Controlled late " + cause + " still rises above the earned pressure floor")
		check(float(target.boss) == expected_boss, "Controlled late " + cause + " uses its truthful independent boss-layer surge")
		check(observed == source_before and stats == stats_before, "Late-surge policy observations remain read-only")
		music.observe_run(observed, stats)
		_tick(music, 1.0)
		check(music.music_snapshot().targets[3] == 1.0 and music.music_snapshot().targets[4] == expected_boss, "Actual mixer settles into the controlled late " + cause + " surge")
		check(music.music_snapshot().progression == mature, "A late " + cause + " surge adds no fabricated Run progress")
		music.observe_run(calm, HEALTHY)
		_tick(music, 2.3)
		check(music.music_snapshot().targets[3] == 1.0, "Late " + cause + " release still waits for sustained clear evidence")
		_tick(music, 0.4)
		check(music.music_snapshot().targets[3] == 0.75 and music.music_snapshot().targets[4] == 0.75, "Late " + cause + " releases back to earned full floors after hysteresis")
		check(music.music_snapshot().progression == mature, "Releasing late " + cause + " preserves every earned milestone maximum")
		check(int(music.music_snapshot().transport_starts) == 0, "Late " + cause + " never starts or replaces the default audio transport")
		results.append({"cause":cause, "controlled_policy_fixture":true, "temporary_target":target,
			"earned_progression":mature, "after_release":music.music_snapshot()})
		music.free()
	measurements.late_surges = results

func _engine_cursor_continuity() -> void:
	var music: Node = _music()
	check(music.music_snapshot().asset_errors.is_empty(), "Current stems import as the exact current PCM grid")
	var stream: AudioStreamSynchronized = music.synchronized_stream()
	var count: int = stream.stream_count
	var duration: float = stream.get_length()
	var refs: Array[AudioStreamPlayback] = []
	for index: int in range(count):
		var wav: AudioStreamWAV = stream.get_sync_stream(index)
		check(is_equal_approx(wav.get_length(), duration) and wav.loop_begin == 0 and wav.loop_end == wav.data.size() / 4, "Every current stem has the same actual PCM cursor/loop grid")
		var reference: AudioStreamPlayback = wav.instantiate_playback()
		reference.start(duration - 0.025)
		refs.append(reference)
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	playback.start(duration - 0.025)
	var maximum_error: float = 0.0
	var energy: float = 0.0
	for stage: int in range(TIMES.size()):
		music.observe_run(_fixture(TIMES[stage], stage, CLEARS[stage]), HEALTHY)
		_tick(music, 4.0)
		var gains: Array = music.music_snapshot().gains
		var actual: PackedVector2Array = playback.mix_audio(1.0, 2048)
		var separate: Array[PackedVector2Array] = []
		for reference: AudioStreamPlayback in refs: separate.append(reference.mix_audio(1.0, 2048))
		for frame: int in range(actual.size()):
			var expected: Vector2 = Vector2.ZERO
			for index: int in range(count): expected += separate[index][frame] * maxf(0.0001, float(gains[index]))
			maximum_error = maxf(maximum_error, actual[frame].distance_to(expected))
			energy += actual[frame].length_squared()
		for reference: AudioStreamPlayback in refs:
			check(absf(reference.get_playback_position() - playback.get_playback_position()) < 0.000002, "Every stem cursor stays phase-aligned while an earned arrangement changes its gain")
	check(maximum_error < 0.00001 and energy > 0.01, "Actual synchronized PCM mix follows uninterrupted reference cursors with real ramped progression gains")
	check(playback.get_playback_position() > 0.05 and playback.get_playback_position() < 1.0, "Progression gain changes preserve the actual shared seamless loop crossing")
	check(int(music.music_snapshot().transport_starts) == 0 and not bool(music.music_snapshot().playing), "Reference mixing does not start or restart the Music node's native transport")
	measurements.engine_cursor = {"maximum_sample_error":maximum_error, "sample_energy":energy,
		"mixed_frames":10240, "current_loop_seconds":duration, "stem_count":count,
		"wrapped_position":playback.get_playback_position()}
	for reference: AudioStreamPlayback in refs: reference.stop()
	playback.stop()
	music.free()

func _write_report() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--report=") and not argument.begins_with("--out="): continue
		var path: String = argument.get_slice("=", 1).replace("\\", "/").simplify_path()
		var configured: String = OS.get_environment("TOPGAME_QA_ROOT")
		var qa_root: String = configured if not configured.is_empty() else ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
		var prefix: String = qa_root.replace("\\", "/").simplify_path().path_join("002C.6/manifests").to_lower() + "/"
		check(path.is_absolute_path() and path.to_lower().begins_with(prefix) and path.get_extension().to_lower() == "json", "Music escalation report is scoped to external task QA manifests")
		if not path.is_absolute_path() or not path.to_lower().begins_with(prefix) or path.get_extension().to_lower() != "json": continue
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		check(file != null, "External music escalation result file can be written")
		if file != null:
			file.store_string(JSON.stringify({"checks":checks, "failures":failures, "measurements":measurements}, "\t"))
			file.close()

func _run() -> void:
	_capture_real_schema()
	_boundaries()
	_schema_gates()
	_retention_and_pause()
	_temporary_surges()
	_late_surges()
	_real_observations()
	_engine_cursor_continuity()
	_write_report()
	print("MUSIC_ESCALATION_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
