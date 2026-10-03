extends Node

const SOUNDS: Dictionary = {
	"hit":preload("res://assets/audio/hit.wav"), "heavy":preload("res://assets/audio/heavy.wav"),
	"wall":preload("res://assets/audio/wall.wav"), "burst":preload("res://assets/audio/burst.wav"),
	"launch":preload("res://assets/audio/launch.wav"), "scrape":preload("res://assets/audio/scrape.wav"),
	"ring_out":preload("res://assets/audio/ring_out.wav"), "spin_out":preload("res://assets/audio/spin_out.wav"),
	"ui":preload("res://assets/audio/ui.wav"), "win":preload("res://assets/audio/win.wav"), "loss":preload("res://assets/audio/loss.wav")
}
var channels: Array[AudioStreamPlayer] = []
var current: int = 0
var muted: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	for i: int in range(8):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		channels.append(player)

func apply_settings(settings: Dictionary) -> void:
	muted = bool(settings.get("muted", false))
	AudioServer.set_bus_mute(0, muted)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(settings.get("volume", 0.65)))))

func play_sound(kind: String) -> void:
	if muted or channels.is_empty(): return
	var aliases: Dictionary = {"impact":"hit", "light_impact":"hit", "heavy_impact":"heavy", "collision":"hit", "bounce":"wall", "land":"wall", "countdown":"ui", "victory":"win", "defeat":"loss"}
	var key: String = str(aliases.get(kind, kind))
	if not SOUNDS.has(key): return
	var player: AudioStreamPlayer = channels[current]
	current = (current+1) % channels.size()
	player.stream = SOUNDS[key]
	player.pitch_scale = rng.randf_range(0.93,1.08) if key in ["hit","heavy","wall","scrape"] else 1.0
	player.volume_db = -8.0 if key == "scrape" else -3.0
	player.play()
