extends Node
## Presentation-only feedback. The output boundary can be replaced by a mock.
## No fighter writes, random numbers, deferred event queue or phone vibration.
const Bindings = preload("res://scripts/controller_bindings.gd")
const ImpactFeedback = preload("res://scripts/combat_impact_feedback.gd")
const SEGMENT: float = 0.075
const OUTPUT_INTERVAL: float = 0.04
const MAX_HISTORY: int = 64
const PROFILES: Dictionary = {
	"light":{"weak":0.10,"strong":0.04,"duration":0.04,"priority":1,"cooldown":0.16},
	"normal":{"weak":0.32,"strong":0.25,"duration":0.09,"priority":2,"cooldown":0.10},
	"burst":{"weak":0.25,"strong":0.15,"duration":0.07,"priority":2,"cooldown":0.12},
	"brace":{"weak":0.40,"strong":0.57,"duration":0.12,"priority":4,"cooldown":0.16},
	"hard_delivered":{"weak":0.70,"strong":0.42,"duration":0.14,"priority":4,"cooldown":0.16},
	"hard_received":{"weak":0.48,"strong":0.80,"duration":0.20,"priority":5,"cooldown":0.20},
	"takedown":{"weak":0.63,"strong":0.52,"duration":0.18,"priority":6,"cooldown":0.25},
	"elite_takedown":{"weak":0.70,"strong":0.73,"duration":0.25,"priority":6,"cooldown":0.30},
	"boss_takedown":{"weak":0.80,"strong":0.90,"duration":0.30,"priority":7,"cooldown":0.35},
	"extreme":{"weak":0.90,"strong":0.96,"duration":0.30,"priority":8,"cooldown":0.30},
	"test":{"weak":0.35,"strong":0.30,"duration":0.16,"priority":9,"cooldown":0.40}
}

class NativeOutput extends RefCounted:
	func connected(device: int) -> bool:
		return device >= 0 and device in Input.get_connected_joypads()
	func supported(device: int) -> bool:
		# Branding/layout is unrelated to the current driver's motor capability.
		return connected(device) and Input.has_method("has_joy_vibration") and bool(Input.call("has_joy_vibration", device))
	func start(device: int, weak: float, strong: float, duration: float) -> void:
		Input.start_joy_vibration(device, weak, strong, duration)
	func stop(device: int) -> void:
		Input.stop_joy_vibration(device)

var output: RefCounted = NativeOutput.new()
var enabled: bool = true
var intensity: float = 0.55
var active_device: int = -1
var _focused: bool = true
var _backgrounded: bool = false
var _gameplay: bool = false
var _clock: float = 0.0
var _output_ready: float = 0.0
var _quiet_until: float = 0.0
var _pulse: Dictionary = {}
var _cooldowns: Dictionary = {}
var _last_collision: int = 0
var _last_burst: int = 0
var _eliminations: Dictionary = {}
var _history: Array[Dictionary] = []
var _live_output: bool = false
var _grind_target: float = 0.0
var _grind_level: float = 0.0
var _grind_until: float = 0.0
## Magnitude-weighted seconds; caps repeated impacts without banking a backlog.
var _work_credit: float = 0.60

func _ready() -> void:
	Input.joy_connection_changed.connect(connection_changed)

func _input(event: InputEvent) -> void:
	if _backgrounded: return
	# A meaningful input may re-engage desktop focus through Main's existing
	# input path. Observe its owner now, before that same input resumes play.
	var device: int = Bindings.control_device_for_event(event)
	if device != -2: set_active_device(device)

func _process(delta: float) -> void:
	update(delta)

func configure(values: Dictionary) -> void:
	enabled = bool(values.get("controller_rumble", true))
	var value: Variant = values.get("rumble_intensity", 0.55)
	intensity = clampf(float(value), 0.0, 1.0) if (value is float or value is int) and is_finite(float(value)) else 0.55
	if not enabled or intensity <= 0.0: clear("disabled")

func set_active_device(device: int) -> void:
	var selected: int = device if output.connected(device) else -1
	if selected == active_device: return
	clear("ownership_change")
	active_device = selected

func connection_changed(device: int, connected: bool) -> void:
	if not connected and device == active_device:
		clear("disconnect")
		active_device = -1
	# Reconnecting requires a fresh meaningful input; old ownership is retired.

func set_focus(value: bool) -> void:
	_focused = value
	if not value: clear("background")

func set_gameplay_active(value: bool) -> void:
	if _gameplay == value: return
	_gameplay = value
	if not value: clear("blocking_context")

func reset() -> void:
	clear("run_reset")
	_gameplay = false
	_last_collision = 0
	_last_burst = 0
	_eliminations.clear()
	_cooldowns.clear()
	_quiet_until = 0.0
	_work_credit = 0.60

func clear(reason: String = "lifecycle") -> void:
	_pulse.clear()
	_grind_target = 0.0
	_grind_level = 0.0
	_grind_until = 0.0
	if active_device >= 0: output.stop(active_device)
	_live_output = false
	_record({"stop":reason,"device":active_device})

func _available() -> bool:
	return enabled and intensity > 0.0 and _focused and active_device >= 0 and output.connected(active_device) and output.supported(active_device)

func test_pulse() -> String:
	if not enabled or intensity <= 0.0: return "Rumble is Off."
	if active_device < 0 or not output.connected(active_device): return "Use a connected controller first."
	if not _focused or not output.supported(active_device): return "This connection reports no rumble support."
	if not _request("test", true): return "Wait briefly before testing again."
	return "Short rumble requested. Confirm the controller response."

func accept_impact(event: Dictionary) -> bool:
	var id: int = int(event.get("collision_id", 0))
	if id <= _last_collision: return false
	_last_collision = id
	var first_player: bool = bool(event.get("first_player", false))
	var second_player: bool = bool(event.get("second_player", false))
	if first_player == second_player: return false
	var severity: float = float(event.get("severity", 0.0))
	if not is_finite(severity) or severity <= 0.0: return false
	var profile_id: String = "light" if severity < 0.32 else "normal"
	if ImpactFeedback.tier(event) == "extreme": profile_id = "extreme"
	elif severity >= 0.75:
		var prefix: String = "first" if first_player else "second"
		var other: String = "second" if first_player else "first"
		var own_momentum: float = float(event.get(prefix+"_normal_speed",0.0))*float(event.get(prefix+"_effective_mass",1.0))
		var other_momentum: float = float(event.get(other+"_normal_speed",0.0))*float(event.get(other+"_effective_mass",1.0))
		var absorbed: bool = float(event.get(prefix+"_absorption",0.0)) >= 0.08
		profile_id = "brace" if absorbed else ("hard_received" if other_momentum >= own_momentum else "hard_delivered")
	return _request(profile_id)

func accept_event(event: Dictionary, finishing: bool = false) -> bool:
	if not bool(event.get("player_attributed", false)): return false
	var kind: String = str(event.get("kind", ""))
	if kind == "burst":
		var id: int = int(event.get("event_id",0))
		if id <= _last_burst: return false
		_last_burst = id
		return _request("burst")
	if kind == "takedown":
		var id: int = int(event.get("entity_id",0))
		if id <= 0 or _eliminations.has(id): return false
		_eliminations[id] = true
		while _eliminations.size() > 256: _eliminations.erase(_eliminations.keys()[0])
		var enemy_kind: String = str(event.get("enemy_kind",""))
		return _request("boss_takedown" if enemy_kind == "boss" else ("elite_takedown" if enemy_kind == "elite" else "takedown"), finishing)
	return false

func observe_grind(state: Dictionary) -> void:
	if not _gameplay or not _available():
		_grind_target = 0.0
		return
	var strength: float = float(state.get("strength",0.0))
	_grind_target = clampf(strength,0.0,1.0) if bool(state.get("active",false)) and is_finite(strength) else 0.0
	_grind_until = _clock + 0.10

func _request(profile_id: String, explicit: bool = false) -> bool:
	if not _available() or (not _gameplay and not explicit) or not PROFILES.has(profile_id): return false
	var profile: Dictionary = PROFILES[profile_id]
	if _clock < float(_cooldowns.get(profile_id,0.0)): return false
	# Ordinary events leave a brief quiet gap instead of joining into buzzing.
	# A more important impact can still interrupt an active lower-priority pulse.
	if _pulse.is_empty() and not explicit and _clock < _quiet_until: return false
	# A stronger pulse may preempt. Equal/lower events never extend the tail.
	if not _pulse.is_empty() and int(profile.priority) <= int(_pulse.priority): return false
	var cost: float = float(profile.duration)*maxf(float(profile.weak),float(profile.strong))
	if _work_credit < cost: return false
	_work_credit -= cost
	_cooldowns[profile_id] = _clock + float(profile.cooldown)
	_pulse = profile.duplicate()
	_pulse["profile"] = profile_id
	_pulse["started"] = _clock
	_quiet_until = _clock + float(profile.duration) + 0.055
	_record({"profile":profile_id,"device":active_device,"weak":float(profile.weak)*intensity,"strong":float(profile.strong)*intensity,"duration":profile.duration})
	_render_output(true)
	return true

func update(delta: float) -> void:
	var dt: float = maxf(0.0,delta) if is_finite(delta) else 0.0
	_clock += dt
	_work_credit = minf(0.60,_work_credit + dt*0.24)
	if active_device >= 0 and not output.connected(active_device): connection_changed(active_device,false)
	if not _available():
		if _live_output or not _pulse.is_empty(): clear("unavailable")
		return
	if not _pulse.is_empty() and _clock-float(_pulse.started) >= float(_pulse.duration): _pulse.clear()
	if not _gameplay or _clock > _grind_until: _grind_target = 0.0
	_grind_level = move_toward(_grind_level,_grind_target,dt*(8.0 if _grind_target > _grind_level else 25.0))
	_render_output()

func _envelope() -> float:
	var age: float = _clock-float(_pulse.started)
	var duration: float = float(_pulse.duration)
	if str(_pulse.profile).ends_with("takedown"):
		if age < duration*0.25: return 0.65
		if age < duration*0.40: return 0.0
		return clampf((duration-age)/(duration*0.20),0.0,1.0)
	var body: float = 0.62 if str(_pulse.profile) == "hard_received" else 0.78
	return (1.0 if age < minf(0.04,duration*0.25) else body)*clampf((duration-age)/minf(0.045,duration*0.5),0.0,1.0)

func _render_output(force: bool = false) -> void:
	if not force and _clock < _output_ready: return
	_output_ready = _clock + OUTPUT_INTERVAL
	var weak: float = 0.0
	var strong: float = 0.0
	var duration: float = SEGMENT
	if not _pulse.is_empty():
		var envelope: float = _envelope()
		weak = float(_pulse.weak)*envelope
		strong = float(_pulse.strong)*envelope
		duration = minf(SEGMENT,float(_pulse.duration)-(_clock-float(_pulse.started)))
		# A finisher's first beat must expire before its quiet interval, even
		# when a slow render frame skips across that interval entirely.
		if str(_pulse.profile).ends_with("takedown") and _clock-float(_pulse.started) < float(_pulse.duration)*0.25:
			duration = minf(duration,float(_pulse.duration)*0.25-(_clock-float(_pulse.started)))
	elif _grind_level > 0.001:
		# Quiet texture follows real sliding contact, without a cosmetic RNG.
		var texture: float = 0.80+0.20*sin(_clock*48.0)
		weak = _grind_level*0.11*texture
		strong = _grind_level*0.045*texture
	weak = clampf(weak*intensity,0.0,1.0)
	strong = clampf(strong*intensity,0.0,1.0)
	if maxf(weak,strong) > 0.0001 and duration > 0.0:
		output.start(active_device,weak,strong,maxf(0.001,duration))
		_live_output = true
	elif _live_output:
		output.stop(active_device)
		_live_output = false

func _record(event: Dictionary) -> void:
	_history.append(event)
	if _history.size() > MAX_HISTORY: _history.pop_front()

func snapshot() -> Dictionary:
	return {"active_device":active_device,"enabled":enabled,"intensity":intensity,"gameplay":_gameplay,"focused":_focused,
		"pulse":_pulse.duplicate(true),"grind_level":_grind_level,"history":_history.duplicate(true),"queue_size":0,
		"work_credit":_work_credit,"output_live":_live_output,"segment_cap":SEGMENT,"minimum_ordinary_gap":0.055,"gameplay_writes":0}

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_backgrounded = true
		set_focus(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT: set_focus(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_backgrounded = false
		set_focus(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and not _backgrounded: set_focus(true)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST: clear("quit")

func _exit_tree() -> void:
	clear("teardown")
