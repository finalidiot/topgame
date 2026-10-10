extends Node

const SOUNDS: Dictionary = {
	"metal_light": preload("res://assets/audio/impact_003a1/metal_light.wav"),
	"metal_normal": preload("res://assets/audio/impact_003a1/metal_normal.wav"),
	"metal_clang": preload("res://assets/audio/impact_003a1/metal_clang.wav"),
	"metal_edge": preload("res://assets/audio/impact_003a1/metal_edge.wav"),
	"metal_scrape": preload("res://assets/audio/impact_003a1/metal_scrape.wav"),
	"metal_massive": preload("res://assets/audio/impact_003a1/metal_massive.wav"),
	"metal_extreme": preload("res://assets/audio/impact_003a1/metal_extreme.wav"),
	"metal_crack": preload("res://assets/audio/impact_003a1/metal_crack.wav"),
	"metal_grind": preload("res://assets/audio/impact_003a1/metal_grind.wav"),
	"metal_wall": preload("res://assets/audio/impact_003a1/metal_wall.wav"),
	"metal_takedown": preload("res://assets/audio/impact_003a1/metal_takedown.wav"),
	"pickup_collect": preload("res://assets/audio/pickup_collect.wav"),
	"packet_land": preload("res://assets/audio/shop_003a/packet_land.wav"),
	"packet_crinkle": preload("res://assets/audio/shop_003a/packet_crinkle.wav"),
	"packet_tear": preload("res://assets/audio/shop_003a/packet_tear.wav"),
	"packet_spill": preload("res://assets/audio/shop_003a/packet_spill.wav"),
	"packet_clink": preload("res://assets/audio/shop_003a/packet_clink.wav"),
	"packet_new": preload("res://assets/audio/shop_003a/packet_new.wav"),
	"packet_rare": preload("res://assets/audio/shop_003a/packet_rare.wav"),
	"packet_recycle": preload("res://assets/audio/shop_003a/packet_recycle.wav"),
	"redline_overcap":preload("res://assets/audio/redline_overcap.wav"),
	"redline_heat":preload("res://assets/audio/redline_heat.wav"),
	"clutch_activate":preload("res://assets/audio/clutch_activate.wav"),
	"clutch_recover":preload("res://assets/audio/clutch_recover.wav"),
	"high_gear_surge":preload("res://assets/audio/high_gear_surge.wav"),
	"ghost_preview":preload("res://assets/audio/ghost_preview.wav"),
	"momentum_release":preload("res://assets/audio/momentum_release.wav"),
	"crash_guard":preload("res://assets/audio/crash_guard.wav"),
	"crosscut":preload("res://assets/audio/crosscut.wav"),
	"boss_port":preload("res://assets/audio/boss_port.wav"),
	"boss_payoff":preload("res://assets/audio/boss_payoff.wav"),
	"rpm_reclaim":preload("res://assets/audio/rpm_reclaim.wav"),
	"low_rpm":preload("res://assets/audio/low_rpm.wav"),
	"breakneck_recovery":preload("res://assets/audio/breakneck_recovery.wav"),

	"hit":preload("res://assets/audio/hit.wav"), "heavy":preload("res://assets/audio/heavy.wav"),
	"wall":preload("res://assets/audio/wall.wav"), "burst":preload("res://assets/audio/burst.wav"),
	"launch":preload("res://assets/audio/launch.wav"), "scrape":preload("res://assets/audio/scrape.wav"),
	"ring_out":preload("res://assets/audio/ring_out.wav"), "spin_out":preload("res://assets/audio/spin_out.wav"),
	"ui":preload("res://assets/audio/ui.wav"), "win":preload("res://assets/audio/win.wav"), "loss":preload("res://assets/audio/loss.wav"),
	"power_wake": preload("res://assets/audio/power_wake.wav"),
	"redline": preload("res://assets/audio/redline.wav"),
	"comet_charge": preload("res://assets/audio/iron_comet_charge.wav"),
	"comet_release": preload("res://assets/audio/iron_comet_release.wav"),
	"second_wind": preload("res://assets/audio/second_wind.wav"),
	"chain": preload("res://assets/audio/chain.wav"),
	"wave": preload("res://assets/audio/wave.wav"),
	"afterimage": preload("res://assets/audio/afterimage.wav"),
	"acquire": preload("res://assets/audio/acquire.wav"),
	"ui_focus": preload("res://assets/audio/ui_focus.wav"),
	"card_select": preload("res://assets/audio/card_select.wav"),
	"near_level": preload("res://assets/audio/near_level.wav"),
	"level_up": preload("res://assets/audio/level_up.wav"),
	"resume": preload("res://assets/audio/resume.wav"),
	"rank_up": preload("res://assets/audio/rank_up.wav"),
	"mutation_available": preload("res://assets/audio/mutation_available.wav"),
	"mutation_select": preload("res://assets/audio/mutation_select.wav"),
	"redline_ii": preload("res://assets/audio/redline_ii.wav"),
	"runaway": preload("res://assets/audio/runaway.wav"),
	"runaway_hit": preload("res://assets/audio/runaway_hit.wav"),
	"breakneck_charge": preload("res://assets/audio/breakneck_charge.wav"),
	"breakneck_impact": preload("res://assets/audio/breakneck_impact.wav"),
	"anchor": preload("res://assets/audio/anchor.wav"),
	"anchor_break": preload("res://assets/audio/anchor_break.wav"),
	"bulwark_impact": preload("res://assets/audio/bulwark_impact.wav"),
	"counterweight_store": preload("res://assets/audio/counterweight_store.wav"),
	"counterweight_release": preload("res://assets/audio/counterweight_release.wav"),
	"afterimage_ii": preload("res://assets/audio/afterimage_ii.wav"),
	"ghost_closure": preload("res://assets/audio/ghost_latch.wav"),
	"ghost_activation": preload("res://assets/audio/ghost_activation.wav"),
	"slipstream_cross": preload("res://assets/audio/slipstream_cross.wav")
}
const MAX_CHANNELS: int = 8
const SFX_BUS: String = "SFX"
const MIX_PEAK_BUDGET: float = 0.62
const GRIND_DB: float = -29.0
const IMPACT_GAIN: Dictionary = {"metal_light":-22.0,"metal_normal":-16.0,"metal_edge":-19.0,"metal_scrape":-26.0,"metal_clang":-10.0,"metal_massive":-8.0,"metal_extreme":-6.0,"metal_crack":-15.0,"metal_wall":-16.0,"metal_takedown":-7.0}
const IMPACT_COOLDOWN: Dictionary = {"metal_light":0.08,"metal_normal":0.10,"metal_clang":0.12,"metal_edge":0.08,"metal_scrape":0.16,"metal_massive":0.28,"metal_extreme":0.35,"metal_crack":0.22,"hit":0.08}
const PRIORITY: Dictionary = {"pickup_collect":5,"boss_port":6,"boss_payoff":6,"rpm_reclaim":3,"low_rpm":2,"breakneck_recovery":3,"scrape": 0, "small_hit": 0, "afterimage": 1, "hit": 1, "wall": 1, "burst": 2, "heavy": 3, "power_wake": 3, "chain": 3, "redline": 4, "comet_charge": 3, "comet_release": 4, "wave": 4, "launch": 4, "ring_out": 4, "spin_out": 3, "second_wind": 5, "win": 6, "loss": 6, "acquire": 6, "ui": 6, "ui_focus": 5, "card_select": 6, "near_level": 4, "level_up": 7, "resume": 6,
	"rank_up": 7, "mutation_available": 8, "mutation_select": 8,
	"redline_ii": 4, "runaway": 4, "runaway_hit": 3,
	"breakneck_charge": 5, "breakneck_impact": 5,
	"anchor": 3, "anchor_break": 3, "bulwark_impact": 5,
	"counterweight_store": 3, "counterweight_release": 5,
	"afterimage_ii": 1, "ghost_closure": 5, "ghost_activation": 5, "slipstream_cross": 3,
	"redline_overcap":4,"redline_heat":3,"clutch_activate":4,"clutch_recover":5,
	"high_gear_surge":3,"ghost_preview":1,"momentum_release":3,"crash_guard":3,"crosscut":3,
	"packet_land":5,"packet_crinkle":5,"packet_tear":6,"packet_spill":6,
	"packet_clink":5,"packet_new":6,"packet_rare":6,"packet_recycle":5}
const COOLDOWN: Dictionary = {"metal_light":0.045,"metal_clang":0.075,"metal_edge":0.055,"metal_scrape":0.10,"metal_massive":0.28,"metal_takedown":0.20,"metal_wall":0.09,"pickup_collect":0.0,"boss_port":1.0,"boss_payoff":1.0,"rpm_reclaim":0.45,"low_rpm":4.0,"breakneck_recovery":0.3,"small_hit": 0.12, "scrape": 0.08, "afterimage": 0.16, "chain": 0.10, "power_wake": 0.06, "ui_focus": 0.055, "card_select": 0.12, "near_level": 0.45, "level_up": 0.25, "resume": 0.20,
	"rank_up": 0.25, "mutation_available": 0.40, "mutation_select": 0.35,
	"redline_ii": 0.25, "runaway": 0.55, "runaway_hit": 0.16,
	"breakneck_charge": 0.25, "breakneck_impact": 0.20,
	"anchor": 0.45, "anchor_break": 0.25, "bulwark_impact": 0.22,
	"counterweight_store": 0.28, "counterweight_release": 0.28,
	"afterimage_ii": 0.22, "ghost_closure": 0.40, "ghost_activation": 0.35, "slipstream_cross": 0.30,
	"redline_overcap":1.0,"redline_heat":2.5,"clutch_activate":1.5,"clutch_recover":1.0,
	"high_gear_surge":0.4,"ghost_preview":0.65,"momentum_release":0.4,"crash_guard":0.6,"crosscut":0.6,
	"packet_land":0.10,"packet_crinkle":0.10,"packet_tear":0.30,"packet_spill":0.15,
	"packet_clink":0.065,"packet_new":0.15,"packet_rare":0.30,"packet_recycle":0.10}
var channels: Array[AudioStreamPlayer] = []
var current: int = 0
var muted: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var audio_time: float = 0.0
var last_played: Dictionary = {}
var channel_priority: Array[int] = []
var channel_started: Array[float] = []
var played_counts: Dictionary = {}
var suppressed_count: int = 0
var grind_provider: Callable
var _grind_player: AudioStreamPlayer
var _grind_target: float = 0.0
var _grind_level: float = 0.0
var _grind_pitch: float = 1.0
var _grind_target_pitch: float = 1.0
var _grind_starts: int = 0
var _grind_stops: int = 0
var _channel_base_db: Array[float] = []
var _headroom_db: float = 0.0
var _peak_bound: float = 0.0

func _ready() -> void:
	rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(SFX_BUS) < 0:
		AudioServer.add_bus()
		var slot: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(slot, SFX_BUS)
		AudioServer.set_bus_send(slot, "Master")
	for i: int in range(MAX_CHANNELS):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		channels.append(player)
		channel_priority.append(-1)
		channel_started.append(-1.0)
		_channel_base_db.append(-3.0)
	_grind_player = AudioStreamPlayer.new()
	_grind_player.bus = SFX_BUS
	var loop: AudioStreamWAV = SOUNDS.metal_grind.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = loop.data.size()/2
	_grind_player.stream = loop
	_grind_player.volume_db = -80.0
	add_child(_grind_player)

func _process(delta: float) -> void:
	audio_time += delta
	if grind_provider.is_valid():
		var state: Variant = grind_provider.call()
		set_grind_state(state if state is Dictionary else {"active":false})
	elif not grind_provider.is_null(): set_grind_state({"active":false})
	advance_grind(delta)
	_apply_headroom(delta)

func set_grind_state(state: Dictionary) -> void:
	_grind_target = clampf(float(state.get("strength",0.0)),0.0,1.0) if bool(state.get("active",false)) else 0.0
	_grind_target_pitch = clampf(float(state.get("pitch",1.0)),0.90,1.08)

func advance_grind(delta: float) -> void:
	if not is_instance_valid(_grind_player): return
	var target: float = 0.0 if muted else _grind_target
	var response: float = 0.08 if target>_grind_level else 0.18
	_grind_level = lerpf(_grind_level,target,1.0-exp(-maxf(0.0,delta)/response))
	_grind_pitch = lerpf(_grind_pitch,_grind_target_pitch,1.0-exp(-maxf(0.0,delta)/0.12))
	_grind_player.pitch_scale = _grind_pitch
	if _grind_level>0.002 and not muted:
		if not _grind_player.playing:
			_grind_player.play()
			_grind_starts += 1
	elif _grind_player.playing:
		_grind_player.stop()
		_grind_stops += 1
	_grind_player.volume_db = GRIND_DB+linear_to_db(maxf(0.0001,_grind_level))+_headroom_db

## Full-scale worst-case sum, independent of sample phase. Every active SFX
## (including the single friction loop) shares one finite headroom allowance.
## Music retains its accepted PCM, synchronized transport and separate trim.
func _apply_headroom(delta: float, incoming: int = -1) -> void:
	var bound: float = 0.0
	for i: int in range(channels.size()):
		if channels[i].playing or i==incoming: bound += db_to_linear(_channel_base_db[i])
	if is_instance_valid(_grind_player) and _grind_player.playing: bound += db_to_linear(GRIND_DB)*_grind_level
	var target: float = linear_to_db(minf(1.0,MIX_PEAK_BUDGET/maxf(0.0001,bound)))
	_headroom_db = target if target<_headroom_db else move_toward(_headroom_db,target,maxf(0.0,delta)*12.0)
	_peak_bound = bound*db_to_linear(_headroom_db)
	for i: int in range(channels.size()): channels[i].volume_db = _channel_base_db[i]+_headroom_db
	if is_instance_valid(_grind_player): _grind_player.volume_db = GRIND_DB+linear_to_db(maxf(0.0001,_grind_level))+_headroom_db

func apply_settings(settings: Dictionary) -> void:
	muted = bool(settings.get("muted", false))
	AudioServer.set_bus_mute(0, muted)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(settings.get("volume", 0.65)))))
	var bus: int = AudioServer.get_bus_index(SFX_BUS)
	if bus >= 0:
		var gain: float = clampf(float(settings.get("sfx_volume", 1.0)), 0.0, 1.0)
		AudioServer.set_bus_mute(bus, gain <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.001, gain)))

func play_sound(kind: String) -> void:
	if muted or channels.is_empty(): return
	if kind == "metal_grind": return # The contact envelope owns its one loop.
	var aliases: Dictionary = {"boss_warning":"boss_port","boss_entry":"boss_port","impact":"hit", "light_impact":"hit", "heavy_impact":"heavy", "collision":"hit", "bounce":"wall", "land":"wall", "countdown":"ui", "victory":"win", "defeat":"loss", "impact_wake":"power_wake", "chain_impact":"chain", "swarm_wave":"wave", "small_contact":"small_hit", "small_small":"small_hit", "iron_comet":"comet_charge", "power_acquired":"acquire", "card_focus":"ui_focus", "power_selected":"card_select", "progression_near":"near_level", "round_resume":"resume"}
	var key: String = str(aliases.get(kind, kind))
	# Legacy callers keep their intent; physical families replace their samples.
	var sample_key: String = {"hit":"metal_light","small_hit":"metal_light","heavy":"metal_clang","wall":"metal_wall","scrape":"metal_scrape"}.get(key,key)
	if not SOUNDS.has(sample_key): return
	if audio_time - float(last_played.get(key, -100.0)) < float(IMPACT_COOLDOWN.get(key,COOLDOWN.get(key, 0.0))):
		suppressed_count += 1
		return
	var priority: int = int({"metal_light":1,"metal_normal":2,"metal_clang":4,"metal_edge":1,"metal_scrape":0,"metal_massive":6,"metal_extreme":7,"metal_crack":5,"metal_takedown":6,"metal_wall":2}.get(key,PRIORITY.get(key, 2)))
	var slot: int = -1
	# Use a free channel first; otherwise replace the oldest least-important cue.
	# Twelve small-top contacts can never steal a recovery or acquisition cue.
	for i: int in range(channels.size()):
		if not channels[i].playing:
			slot = i
			break
	if slot < 0:
		for i: int in range(channels.size()):
			if channel_priority[i] > priority:
				continue
			if slot < 0 or channel_priority[i] < channel_priority[slot] or (channel_priority[i] == channel_priority[slot] and channel_started[i] < channel_started[slot]):
				slot = i
	if slot < 0:
		suppressed_count += 1
		return
	last_played[key] = audio_time
	channel_priority[slot] = priority
	channel_started[slot] = audio_time
	played_counts[key] = int(played_counts.get(key, 0)) + 1
	current = slot
	var player: AudioStreamPlayer = channels[slot]
	player.stop()
	player.stream = SOUNDS[sample_key]
	player.pitch_scale = rng.randf_range(0.97,1.04) if sample_key.begins_with("metal_") else 1.0
	player.volume_db = -3.0
	if key == "small_hit":
		player.volume_db = -15.0
	elif key == "scrape":
		player.volume_db = -8.0
	elif key == "afterimage":
		player.volume_db = -10.0
	elif key == "ui_focus":
		player.volume_db = -10.0
	elif key == "near_level":
		player.volume_db = -8.0
	elif key == "level_up":
		player.volume_db = -3.5
	elif key in ["card_select", "resume"]:
		player.volume_db = -4.5
	elif key in ["power_wake", "redline", "comet_charge", "comet_release", "second_wind", "chain", "wave", "acquire"]:
		player.volume_db = -4.5
	elif key in ["rank_up", "mutation_select", "breakneck_impact", "bulwark_impact", "counterweight_release"]:
		player.volume_db = -4.5
	elif key in ["anchor", "anchor_break", "counterweight_store", "runaway_hit", "slipstream_cross"]:
		player.volume_db = -7.0
	elif key == "afterimage_ii":
		player.volume_db = -12.0
	elif key == "runaway":
		player.volume_db = -7.5
	elif key == "mutation_available":
		player.volume_db = -5.0
	elif key in ["redline_ii", "breakneck_charge", "ghost_closure", "ghost_activation"]:
		player.volume_db = -6.0
	if key in ["rpm_reclaim","low_rpm"]: player.volume_db = -10.0
	if key == "breakneck_recovery": player.volume_db = -8.0
	if key in ["redline_overcap","clutch_recover","high_gear_surge","momentum_release"]: player.volume_db=-6.0
	if key in ["redline_heat","clutch_activate","crash_guard","crosscut"]: player.volume_db=-9.0
	if key=="ghost_preview": player.volume_db=-15.0
	if key=="pickup_collect": player.volume_db=-7.0
	if key in ["packet_land", "packet_clink", "packet_new", "packet_recycle"]: player.volume_db = -7.0
	if key in ["packet_crinkle", "packet_spill"]: player.volume_db = -5.5
	if key == "packet_tear": player.volume_db = -4.5
	if key == "packet_rare": player.volume_db = -7.5
	if kind == "boss_warning":
		player.pitch_scale = 0.68
		player.volume_db = -3.0
	if sample_key.begins_with("metal_"):
		player.volume_db = -26.0 if key == "small_hit" else float(IMPACT_GAIN.get(sample_key,-16.0))
	_channel_base_db[slot] = player.volume_db
	_apply_headroom(0.0,slot)
	player.play()

func audio_snapshot() -> Dictionary:
	var active: int = 0
	for channel: AudioStreamPlayer in channels:
		if channel.playing:
			active += 1
	return {"active": active, "cap": MAX_CHANNELS, "played": played_counts.duplicate(), "suppressed": suppressed_count,
		"grind_active":is_instance_valid(_grind_player) and _grind_player.playing,"grind_level":_grind_level,"grind_starts":_grind_starts,"grind_stops":_grind_stops,
		"headroom_db":_headroom_db,"worst_case_sfx_peak":_peak_bound,"peak_budget":MIX_PEAK_BUDGET}
