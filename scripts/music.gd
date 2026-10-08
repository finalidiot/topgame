extends Node
## Original synchronized presentation music. Rhythmic pressure and broad hooks
## carry escalation; the authored score reserves high leads for brief breaks.
## The five accepted source loops retain exact PCM. Two additional authored
## arrangements make early combat breathe, with a separate mid-Run answer.
## Inputs are copied scalar values
## from existing Run observations; this node has no combat host/RNG/save access.
const ASSET_ROOT: String = "res://assets/audio/music/"
const STEM_NAMES: Array[String] = ["title", "workshop", "run_base", "run_pressure", "run_boss", "run_opening", "run_motion"]
const VARIATION_MANIFEST: String = ASSET_ROOT + "run_arrangement_003a1_manifest.json"
const BUS_NAME: StringName = &"Music"
const BUS_TRIM_DB: float = -8.0
const SILENCE_DB: float = -80.0
const MAX_EVENTS: int = 64
const DUCK_SECONDS: float = 0.18
const DUCK_DB: float = -4.0
## Arrangement maturity uses observed Run milestones, not this node's clock.
## The final floor leaves headroom for a real boss/danger surge above it.
const PROGRESSION_STAGES: Array[Dictionary] = [
	{"name":"opening", "seconds":0.0, "tier":0, "clears":0, "pressure":0.0, "boss":0.0},
	{"name":"drive", "seconds":35.0, "tier":1, "clears":2, "pressure":0.25, "boss":0.0},
	{"name":"lead", "seconds":100.0, "tier":2, "clears":4, "pressure":0.5, "boss":0.25},
	{"name":"anthem", "seconds":210.0, "tier":3, "clears":7, "pressure":0.75, "boss":0.5},
	{"name":"full", "seconds":360.0, "tier":4, "clears":10, "pressure":0.75, "boss":0.75}
]

var _player: AudioStreamPlayer
var _stream: AudioStreamSynchronized
var _playback_enabled: bool = false
var _context: String = "silent"
var _paused: bool = false
var _music_volume: float = 0.55
var _music_muted: bool = false
var _gains: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _targets: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _run_targets: Dictionary = {"pressure": 0.0, "boss": 0.0, "reason": "opening"}
var _stable_run: Dictionary = {"pressure": 0.0, "boss": 0.0, "reason": "opening"}
var _candidate_key: String = ""
var _candidate_age: float = 0.0
var _last_adaptive_change: float = -10.0
var _duck_left: float = 0.0
var _duck_duration: float = DUCK_SECONDS
var _duck_strength: float = DUCK_DB
var _clock: float = 0.0
var _starts: int = 0
var _events: Array[Dictionary] = []
var _asset_errors: Array[String] = []
var _manifest: Dictionary = {}
var _run_seed: int = 0
var _has_run_seed: bool = false
var _progression: Dictionary = {"stage":0, "name":"opening", "pressure_floor":0.0, "boss_floor":0.0,
	"elapsed":0.0, "tier":0, "threats_cleared":0, "run_seed":0, "continuous":false}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	_load_stream()
	_player = AudioStreamPlayer.new()
	_player.bus = BUS_NAME
	_player.stream = _stream
	_player.max_polyphony = 1
	add_child(_player)
	_apply_bus_gain()
	if _playback_enabled: _start_transport()

func _exit_tree() -> void:
	if _player != null: _player.stop()

func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) < 0:
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS_NAME)
		AudioServer.set_bus_send(index, &"Master")

func _load_stream() -> void:
	_stream = AudioStreamSynchronized.new()
	_stream.stream_count = STEM_NAMES.size()
	_manifest = asset_metadata()
	var expected: int = int(_manifest.get("grid", {}).get("frames", 0))
	for index: int in range(STEM_NAMES.size()):
		var path: String = ASSET_ROOT + STEM_NAMES[index] + ".wav"
		var source: Resource = load(path)
		if not source is AudioStreamWAV:
			_asset_errors.append(path)
			continue
		# Runtime loop metadata is exact PCM frames, independent of editor trim,
		# normalization or automatic WAV endpoint detection.
		var wave: AudioStreamWAV = source.duplicate()
		wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wave.loop_begin = 0
		wave.loop_end = expected
		if wave.format != AudioStreamWAV.FORMAT_16_BITS or not wave.stereo or wave.mix_rate != 32000 or wave.data.size() != expected * 4:
			_asset_errors.append("Invalid PCM grid: " + path)
		_stream.set_sync_stream(index, wave)
		_stream.set_sync_stream_volume(index, SILENCE_DB)

static func asset_metadata() -> Dictionary:
	var base: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSET_ROOT + "manifest.json"))
	if not base is Dictionary: return {}
	var variation: Variant = JSON.parse_string(FileAccess.get_file_as_string(VARIATION_MANIFEST))
	if variation is Dictionary:
		base.stems.merge(variation.get("stems", {}))
		base["run_variation"] = variation
	return base

## Main must explicitly allow native playback. Headless/probe/smoke boot keeps
## this false unless an isolated audio review explicitly opts in.
func configure_playback(enabled: bool) -> void:
	_playback_enabled = enabled
	if not is_node_ready(): return
	if enabled: _start_transport()
	elif _player != null: _player.stop()

func _start_transport() -> void:
	if _player == null or _player.playing or not _asset_errors.is_empty(): return
	_player.play()
	_starts += 1
	_record("transport_started")

func _record(kind: String) -> void:
	_events.append({"kind": kind, "time": _clock, "context": _context})
	if _events.size() > MAX_EVENTS: _events.pop_front()

func set_context(context: String) -> void:
	var valid: String = context if context in ["title", "workshop", "run", "result", "silent"] else "silent"
	if valid == _context: return
	if valid == "run":
		_reset_run_progression()
	_context = valid
	_record("context")
	_rebuild_targets()

func set_paused(paused: bool) -> void:
	if _paused == paused: return
	_paused = paused
	_record("pause" if paused else "resume")
	_rebuild_targets()

## Absolute pressure keeps the opening one-rival Run in its ordinary groove.
## Director census includes a genuinely admitted pending boss, allowing the
## music to build through its real warning rather than fake a new encounter.
static func progression_targets(state: Dictionary, player_stats: Dictionary = {}) -> Dictionary:
	# Duel HUDs also have elapsed time. Only the actual continuous-Run schema
	# may build this floor; survival_time is authoritative over the HUD fallback.
	var continuous: bool = state.has("survival_time") or state.has("run_seed") or bool(state.get("director", false)) or bool(player_stats.get("continuous_run", false))
	var elapsed: float = maxf(0.0, float(state.get("survival_time", player_stats.get("elapsed", 0.0)))) if continuous else 0.0
	if not is_finite(elapsed): elapsed = 0.0
	var tier: int = maxi(0, int(state.get("limits", {}).get("tier", 0))) if continuous else 0
	var cleared: int = maxi(0, int(state.get("threats_cleared", 0))) if continuous else 0
	var stage: int = 0
	for index: int in range(1, PROGRESSION_STAGES.size()):
		var threshold: Dictionary = PROGRESSION_STAGES[index]
		if elapsed >= float(threshold.seconds) or tier >= int(threshold.tier) or cleared >= int(threshold.clears): stage = index
	var row: Dictionary = PROGRESSION_STAGES[stage]
	return {"stage":stage, "name":str(row.name), "pressure_floor":float(row.pressure), "boss_floor":float(row.boss),
		"elapsed":elapsed, "tier":tier, "threats_cleared":cleared, "run_seed":int(state.get("run_seed", 0)), "continuous":continuous}

func _reset_run_progression(record_reset: bool = false) -> void:
	_progression = progression_targets({})
	_has_run_seed = false
	_run_seed = 0
	_stable_run = {"pressure":0.0, "boss":0.0, "reason":"opening"}
	_run_targets = _stable_run.duplicate(true)
	_candidate_key = ""
	_candidate_age = 0.0
	_last_adaptive_change = -10.0
	if record_reset: _record("run_reset")
	_rebuild_targets()

func _observe_progression(state: Dictionary, player_stats: Dictionary) -> void:
	# Paused drafts/options advance envelopes and transport, never Run maturity.
	if _paused: return
	var observed: Dictionary = progression_targets(state, player_stats)
	if not bool(observed.continuous): return
	if state.has("run_seed"):
		var seed: int = int(state.run_seed)
		if _has_run_seed and seed != _run_seed: _reset_run_progression(true)
		_run_seed = seed
		_has_run_seed = true
	var previous_stage: int = int(_progression.stage)
	var stage: int = maxi(previous_stage, int(observed.stage))
	var row: Dictionary = PROGRESSION_STAGES[stage]
	_progression = {"stage":stage, "name":str(row.name), "pressure_floor":float(row.pressure), "boss_floor":float(row.boss),
		"elapsed":maxf(float(_progression.elapsed), float(observed.elapsed)), "tier":maxi(int(_progression.tier), int(observed.tier)),
		"threats_cleared":maxi(int(_progression.threats_cleared), int(observed.threats_cleared)), "run_seed":_run_seed, "continuous":true}
	if stage > previous_stage:
		_record("progression_" + str(row.name))
		_rebuild_targets()

static func adaptive_targets(state: Dictionary, player_stats: Dictionary = {}, progression: Dictionary = {}) -> Dictionary:
	var census: Dictionary = state.get("census", {})
	var limits: Dictionary = state.get("limits", {})
	var pressure: float = maxf(0.0, float(census.get("pressure", 0.0)))
	var tier: int = maxi(0, int(limits.get("tier", 0)))
	var bosses: int = maxi(0, int(census.get("bosses", 0)))
	var elites: int = maxi(0, int(census.get("elites", 0)))
	var weight: float = clampf((pressure - 4.0) / 7.0, 0.0, 1.0)
	weight = maxf(weight, clampf(float(int(census.get("active_total", 1)) - 4) / 12.0, 0.0, 0.75))
	weight = maxf(weight, minf(0.65, float(elites) * 0.35))
	var reserve: float = float(player_stats.get("player_rpm", 1.0))
	var danger: bool = reserve > 0.045 and reserve < 0.25
	var overclock: bool = bool(player_stats.get("redline_active", false)) and (float(player_stats.get("redline_heat", 0.0)) >= 0.45 or float(player_stats.get("redline_excess", 0.0)) >= 0.05)
	var investment: int = 0
	for value: Variant in player_stats.get("power_ranks", {}).values(): investment += maxi(0, int(value) - 1)
	weight = maxf(weight, clampf(float(investment - 2) * 0.045, 0.0, 0.35))
	if overclock: weight = maxf(weight, 0.5)
	if danger: weight = maxf(weight, 0.65)
	var boss: float = 1.0 if bosses > 0 else clampf(float(tier - 2) * 0.25, 0.0, 0.75) * weight
	if bosses > 0: weight = maxf(weight, 0.65)
	elif danger: boss = maxf(boss, 0.35)
	var calm: bool = bool(state.get("calm", false))
	if calm and bosses == 0 and not danger:
		weight *= 0.25
		boss *= 0.25
	var observed: Dictionary = progression_targets(state, player_stats)
	# A supplied retained snapshot is authoritative; this also prevents fresh
	# observations from maturing the instance's arrangement while it is paused.
	var stage: int = clampi(int(observed.stage) if progression.is_empty() else int(progression.get("stage", 0)), 0, PROGRESSION_STAGES.size() - 1)
	var row: Dictionary = PROGRESSION_STAGES[stage]
	# Calm/draining can release temporary density, but a mature Run retains its
	# rhythmic drive and broad hook arrangement. The two components keep their own hysteresis.
	weight = maxf(weight, float(row.pressure))
	boss = maxf(boss, float(row.boss))
	# Critical spin and a genuinely observed boss still have a musical step
	# above a mature anthem; the old fixed danger minimum alone would be below
	# the late floor and make the warning cease to change the arrangement.
	if danger or bosses > 0 or overclock: weight = maxf(weight, minf(1.0, float(row.pressure) + 0.25))
	if danger: boss = maxf(boss, minf(1.0, float(row.boss) + 0.25))
	return {"pressure": weight, "boss": boss, "absolute_pressure": pressure, "tier": tier,
		"bosses": bosses, "elites": elites, "danger": danger, "overclock": overclock, "investment": investment, "calm": calm,
		"progression_stage":stage, "pressure_floor":float(row.pressure), "boss_floor":float(row.boss),
		"reason": "boss" if bosses > 0 else ("danger" if danger else ("progression_" + str(row.name) if stage > 0 else ("late_pressure" if boss > 0.0 else ("pressure" if weight > 0.0 else "opening"))))}

func observe_run(state: Dictionary, player_stats: Dictionary = {}) -> void:
	# Main already sends this explicit empty observation when it starts/restarts
	# a Run or duel, including Restart from an existing paused Run context.
	if state.is_empty() and player_stats.is_empty():
		_reset_run_progression(true)
		_rebuild_targets()
		return
	if _paused: return
	_observe_progression(state, player_stats)
	_run_targets = adaptive_targets(state, player_stats, _progression)
	# Only a genuinely observed boss can immediately increase the boss layer.
	# Its removal still needs the ordinary stable-release window below.
	if int(_run_targets.get("bosses", 0)) > 0 and float(_stable_run.boss) < 1.0:
		_stable_run = _run_targets.duplicate(true)
		_last_adaptive_change = _clock
		_candidate_key = ""
		_record("adaptive_boss")
		_rebuild_targets()

func _settle_adaptive(dt: float) -> void:
	# Quantized musical plateaus plus a 0.10 deadband, 0.6 s attack evidence,
	# 2.5 s release evidence and 2 s hold prevent rapidly toggling census/RPM
	# observations from thrashing the arrangement. Audio transport never moves.
	var pressure: float = snappedf(float(_run_targets.pressure), 0.25)
	var boss: float = snappedf(float(_run_targets.boss), 0.25)
	if absf(pressure - float(_stable_run.pressure)) < 0.10 and absf(boss - float(_stable_run.boss)) < 0.10:
		_candidate_key = ""; _candidate_age = 0.0; return
	var key: String = "%0.2f/%0.2f" % [pressure, boss]
	if key != _candidate_key:
		_candidate_key = key
		_candidate_age = 0.0
	_candidate_age += dt
	var rising: bool = pressure > float(_stable_run.pressure) or boss > float(_stable_run.boss)
	if _candidate_age < (0.6 if rising else 2.5) or _clock - _last_adaptive_change < 2.0: return
	_stable_run = _run_targets.duplicate(true)
	_stable_run.pressure = pressure
	_stable_run.boss = boss
	_last_adaptive_change = _clock
	_candidate_key = ""
	_candidate_age = 0.0
	_record("adaptive_mix")
	_rebuild_targets()

func _rebuild_targets() -> void:
	_targets = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	match _context:
		"title": _targets[0] = 1.0
		"workshop": _targets[1] = 1.0
		"result": _targets[1] = 0.65
		"run":
			var arrangements: Array[Array] = [[0.0,1.0,0.0],[0.2,0.75,0.25],[0.6,0.25,0.55],[0.9,0.0,0.25],[1.0,0.0,0.0]]
			var arrangement: Array = arrangements[clampi(int(_progression.stage),0,4)]
			_targets[2] = float(arrangement[0])
			_targets[5] = float(arrangement[1])
			_targets[6] = float(arrangement[2])
			_targets[3] = float(_stable_run.get("pressure", 0.0))
			_targets[4] = float(_stable_run.get("boss", 0.0))
	if _paused and _context == "run":
		for index: int in range(_targets.size()): _targets[index] *= 0.35

func apply_settings(settings: Dictionary) -> void:
	_music_volume = clampf(float(settings.get("music_volume", 0.55)), 0.0, 1.0)
	_music_muted = bool(settings.get("music_muted", false))
	if is_node_ready(): _apply_bus_gain()

func notify_cue(kind: String) -> void:
	if kind in ["packet_tear", "packet_rare"]:
		# Packet foley clears a short space above the accepted workshop stem.
		# The synchronized transport and its arrangement position keep running.
		_duck_duration = 0.38 if kind == "packet_tear" else 0.48
		_duck_strength = -4.0 if kind == "packet_tear" else -2.5
		_duck_left = maxf(_duck_left, _duck_duration)
		return
	if kind == "low_rpm":
		# This existing warning is intentionally quiet. Clear its brief two-note
		# window rather than altering the accepted SFX sample/priority/gain.
		_duck_duration = 0.30
		_duck_strength = -12.0
		_duck_left = maxf(_duck_left, _duck_duration)
		return
	if kind in ["metal_clang", "metal_massive", "metal_takedown", "heavy", "heavy_impact", "breakneck_impact", "comet_release", "boss_warning", "boss_entry", "boss_payoff", "level_up", "mutation_select"]:
		if _duck_left <= 0.0:
			_duck_duration = DUCK_SECONDS
			_duck_strength = DUCK_DB
		_duck_left = maxf(_duck_left, DUCK_SECONDS)

func _process(delta: float) -> void:
	advance_presentation(delta)

## Deterministic audio-envelope seam for tests/captures; no simulation feedback.
func advance_presentation(delta: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.25)
	_clock += dt
	_settle_adaptive(dt)
	_duck_left = maxf(0.0, _duck_left - dt)
	for index: int in range(_gains.size()):
		var seconds: float = 1.2 if _targets[index] > _gains[index] else 2.4
		_gains[index] = lerpf(_gains[index], _targets[index], 1.0 - exp(-dt / seconds))
		if _stream != null: _stream.set_sync_stream_volume(index, linear_to_db(maxf(0.0001, _gains[index])))
	if is_node_ready(): _apply_bus_gain()

func _apply_bus_gain() -> void:
	var bus: int = AudioServer.get_bus_index(BUS_NAME)
	if bus < 0: return
	AudioServer.set_bus_mute(bus, _music_muted or _music_volume <= 0.0)
	var duck: float = _duck_strength * clampf(_duck_left / _duck_duration, 0.0, 1.0)
	AudioServer.set_bus_volume_db(bus, BUS_TRIM_DB + linear_to_db(maxf(0.0001, _music_volume)) + duck)

func music_snapshot() -> Dictionary:
	return {"context": _context, "paused": _paused, "playback_enabled": _playback_enabled,
		"playing": _player != null and _player.playing, "transport_starts": _starts,
		"position": _player.get_playback_position() if _player != null and _player.playing else 0.0,
		"stem_count": STEM_NAMES.size(), "gains": _gains.duplicate(), "targets": _targets.duplicate(),
		"run": _run_targets.duplicate(true), "stable_run": _stable_run.duplicate(true), "music_volume": _music_volume, "music_muted": _music_muted,
		"progression":_progression.duplicate(true), "duck_left": _duck_left, "events": _events.duplicate(true), "asset_errors": _asset_errors.duplicate()}

## Read-only resource inspection/mixer tests can instantiate independent
## playback without starting a native device/player or changing game state.
func synchronized_stream() -> AudioStreamSynchronized:
	return _stream
