extends Node

const SOUNDS: Dictionary = {
	"hit":preload("res://assets/audio/hit.wav"), "heavy":preload("res://assets/audio/heavy.wav"),
	"wall":preload("res://assets/audio/wall.wav"), "burst":preload("res://assets/audio/burst.wav"),
	"launch":preload("res://assets/audio/launch.wav"), "scrape":preload("res://assets/audio/scrape.wav"),
	"ring_out":preload("res://assets/audio/ring_out.wav"), "spin_out":preload("res://assets/audio/spin_out.wav"),
	"ui":preload("res://assets/audio/ui.wav"), "win":preload("res://assets/audio/win.wav"), "loss":preload("res://assets/audio/loss.wav"),
	"power_wake": preload("res://assets/audio/power_wake.wav"),
	"redline": preload("res://assets/audio/redline.wav"),
	"comet_charge": preload("res://assets/audio/comet_charge.wav"),
	"comet_release": preload("res://assets/audio/comet_release.wav"),
	"second_wind": preload("res://assets/audio/second_wind.wav"),
	"chain": preload("res://assets/audio/chain.wav"),
	"wave": preload("res://assets/audio/wave.wav"),
	"afterimage": preload("res://assets/audio/afterimage.wav"),
	"acquire": preload("res://assets/audio/acquire.wav"),
	"ui_focus": preload("res://assets/audio/ui_focus.wav"),
	"card_select": preload("res://assets/audio/card_select.wav"),
	"near_level": preload("res://assets/audio/near_level.wav"),
	"level_up": preload("res://assets/audio/level_up.wav"),
	"resume": preload("res://assets/audio/resume.wav")
}
const MAX_CHANNELS: int = 8
const PRIORITY: Dictionary = {"scrape": 0, "small_hit": 0, "afterimage": 1, "hit": 1, "wall": 1, "burst": 2, "heavy": 3, "power_wake": 3, "chain": 3, "redline": 4, "comet_charge": 3, "comet_release": 4, "wave": 4, "launch": 4, "ring_out": 4, "spin_out": 3, "second_wind": 5, "win": 6, "loss": 6, "acquire": 6, "ui": 6, "ui_focus": 5, "card_select": 6, "near_level": 4, "level_up": 7, "resume": 6}
const COOLDOWN: Dictionary = {"small_hit": 0.12, "scrape": 0.08, "afterimage": 0.16, "chain": 0.10, "power_wake": 0.06, "ui_focus": 0.055, "card_select": 0.12, "near_level": 0.45, "level_up": 0.25, "resume": 0.20}
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

func _ready() -> void:
	rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in range(MAX_CHANNELS):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		channels.append(player)
		channel_priority.append(-1)
		channel_started.append(-1.0)

func _process(delta: float) -> void:
	audio_time += delta

func apply_settings(settings: Dictionary) -> void:
	muted = bool(settings.get("muted", false))
	AudioServer.set_bus_mute(0, muted)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(settings.get("volume", 0.65)))))

func play_sound(kind: String) -> void:
	if muted or channels.is_empty(): return
	var aliases: Dictionary = {"impact":"hit", "light_impact":"hit", "heavy_impact":"heavy", "collision":"hit", "bounce":"wall", "land":"wall", "countdown":"ui", "victory":"win", "defeat":"loss", "impact_wake":"power_wake", "chain_impact":"chain", "swarm_wave":"wave", "small_contact":"small_hit", "small_small":"small_hit", "iron_comet":"comet_charge", "power_acquired":"acquire", "card_focus":"ui_focus", "power_selected":"card_select", "progression_near":"near_level", "round_resume":"resume"}
	var key: String = str(aliases.get(kind, kind))
	var sample_key: String = "hit" if key == "small_hit" else key
	if not SOUNDS.has(sample_key): return
	if audio_time - float(last_played.get(key, -100.0)) < float(COOLDOWN.get(key, 0.0)):
		suppressed_count += 1
		return
	var priority: int = int(PRIORITY.get(key, 2))
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
	player.pitch_scale = rng.randf_range(0.93,1.08) if key in ["hit","heavy","wall","scrape"] else 1.0
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
	player.play()

func audio_snapshot() -> Dictionary:
	var active: int = 0
	for channel: AudioStreamPlayer in channels:
		if channel.playing:
			active += 1
	return {"active": active, "cap": MAX_CHANNELS, "played": played_counts.duplicate(), "suppressed": suppressed_count}
