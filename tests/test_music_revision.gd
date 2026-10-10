extends SceneTree
## Protect the human-liked PCM and bounded lead form using actual imported data.
const Music = preload("res://scripts/music.gd")
const PRESERVED: Dictionary = {
	"workshop":"5f389ddff9f71e39d2afd2ba6647ee4e66ab654d543f057c25cb9f30069aab21",
	"run_base":"d556305faf1a92b385091647d0b2a01548462002c717b19c5e84eff371848ca6"
}
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func digest(bytes: PackedByteArray) -> String:
	var hash_context: HashingContext = HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256); hash_context.update(bytes)
	return hash_context.finish().hex_encode()
func run() -> void:
	var score: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Music.ASSET_ROOT + "foundation_score.json"))
	var manifest: Dictionary = Music.asset_metadata()
	var revision: Dictionary = score.human_feedback_revision
	var music: Node = Music.new(); root.add_child(music)
	check(music.music_snapshot().asset_errors.is_empty(), "All revised and preserved stems import on the accepted exact grid")
	var stream: AudioStreamSynchronized = music.synchronized_stream()
	for index: int in range(Music.STEM_NAMES.size()):
		var name: String = Music.STEM_NAMES[index]
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(Music.ASSET_ROOT + name + ".wav")
		var wav: AudioStreamWAV = stream.get_sync_stream(index)
		check(bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(36, 40).get_string_from_ascii() == "data", "Composer WAV has a declared PCM data chunk: " + name)
		check(digest(wav.data) == digest(bytes.slice(44)), "Imported native PCM exactly matches authored WAV: " + name)
		check(wav.data.size() == 1428837 * 4 and wav.mix_rate == 32000 and wav.stereo, "The five stems retain the accepted stereo 32k frame grid: " + name)
		check(int(manifest.stems[name].clipped_samples) == 0 and float(manifest.stems[name].boundary_step) == 0.0, "PCM review reports no clipping and exact loop seam: " + name)
		if PRESERVED.has(name):
			check(digest(bytes) == PRESERVED[name], "Human-liked source bytes are preserved against fixed accepted hashes: " + name)
			check(revision.preserved.wav_sha256[name] == PRESERVED[name], "Editable score preserves provenance independently of a refreshed manifest: " + name)
	for name: String in ["title", "run_pressure", "run_boss"]:
		var arrangement: Dictionary = revision.arrangements[name]
		check(arrangement.sections.size() == 32, "Rhythmic form covers the complete authored cycle: " + name)
		check(arrangement.lead_break_bars.size() <= 2 and arrangement.hook_bars.size() <= 8, "Lead punctuation and hooks leave substantial riff-only space: " + name)
		var events: Dictionary = manifest.grid.instrument_events[name]
		check(int(events.chug) > 500 and int(events.bass) > 250 and int(events.lead) < 70, "Actual generated arrangement is led by low riffs and bass: " + name)
	check(revision.arrangements.run_boss.lead_break_bars.is_empty(), "Boss escalation adds heavy-band energy without a continuous solo")
	check(float(manifest.adaptive_vertex_maximum_peak) <= 0.7001, "All adaptive gain cube vertices retain clipping headroom")
	for context: String in ["workshop", "result", "run"]:
		music.set_context(context)
		var target: Array = music.music_snapshot().targets
		check(target == ([0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0] if context == "workshop" else ([0.0, 0.65, 0.0, 0.0, 0.0, 0.0, 0.0] if context == "result" else [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])), "Menu routing remains exact; opening uses its new authored half-time arrangement: " + context)
	check(music.music_snapshot().transport_starts == 0, "Read-only preservation test opens no native audio device")
	music.free()
	print("MUSIC_REVISION_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
