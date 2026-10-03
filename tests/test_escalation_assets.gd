extends SceneTree
## Production source/atlas/audio contracts. These checks do not prove human feel.
const Visuals = preload("res://scripts/power_visuals.gd")
const Sound = preload("res://scripts/sound.gd")
const Cards: Texture2D = preload("res://assets/powers/escalation_cards.png")
const IDS: Array[String] = ["dead_centre", "redline_ii", "dead_centre_ii", "afterimage_ii", "runaway", "breakneck", "bulwark", "counterweight", "ghost_circuit", "slipstream"]
const TIMINGS: Array[int] = [110, 90, 75, 75, 100, 170]
const CUES: Array[String] = ["rank_up", "mutation_available", "mutation_select", "redline_ii", "runaway", "runaway_hit", "breakneck_charge", "breakneck_impact", "anchor", "anchor_break", "bulwark_impact", "counterweight_store", "counterweight_release", "afterimage_ii", "ghost_closure", "ghost_activation", "slipstream_cross"]
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)

func _run() -> void:
	var card_meta: Dictionary = Visuals._meta("escalation_cards")
	var icon_meta: Dictionary = Visuals._meta("escalation_icons")
	var fx_meta: Dictionary = Visuals._meta("escalation_effects")
	check(Cards.get_size() == Vector2(384, 640), "Ten native 64px card rows, six authored poses each")
	check(Visuals.ESCALATION_ICONS.get_size() == Vector2(160, 16), "Ten native independent 16px icons")
	check(Visuals.ESCALATION_EFFECTS.get_size() == Vector2(1024, 1920), "116 native 128px combat FX cels at eight columns")
	for group: String in ["cards", "icons", "effects"]:
		var meta: Dictionary = Visuals._meta("escalation_" + group)
		check(not meta.is_empty(), group + " separate escalation manifest exists")
		var source: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/source-art/escalation_" + ("fx" if group == "effects" else group) + "_002c.aseprite")
		check(source.size() > 128 and source.decode_u16(4) == 0xA5E0, group + " actual editable Aseprite source")
		check(source.decode_u32(0) == source.size() and source.decode_u16(12) == 32, group + " RGBA source header valid")
		check(source.decode_u16(6) == int(meta.frame_count), group + " source/atlas frame count matches")
		check(source.decode_u16(8) == int(meta.cell[0]) and source.decode_u16(10) == int(meta.cell[1]), group + " source native dimensions preserved")
		check(int(meta.pivot[0]) == int(meta.cell[0]) / 2 and int(meta.pivot[1]) == int(meta.cell[1]) / 2, group + " stable central contact pivot")
		for tag: String in meta.tags:
			var span: Dictionary = meta.tags[tag]
			check(int(span.from) >= 0 and int(span.to) < int(meta.frame_count), group + ":" + tag + " bounded tag")
			check(Visuals._frame("escalation_" + group, tag, 0.0) == int(span.from), group + ":" + tag + " starts correctly")
			check(Visuals._frame("escalation_" + group, tag, 99.0) == int(span.to), group + ":" + tag + " finite terminal pose")
	check(card_meta.layers.size() == 5 and icon_meta.layers.size() == 1 and fx_meta.layers.size() == 4, "Named editable production layers")
	var art: Image = Cards.get_image()
	for row: int in range(IDS.size()):
		var id: String = IDS[row]
		var tag: Dictionary = card_meta.tags.get(id, {})
		check(int(tag.get("from", -1)) == row * 6 and int(tag.get("to", -1)) == row * 6 + 5, id + " stable dedicated card row")
		check(Visuals.icon_texture(id) == Visuals.ESCALATION_ICONS and Visuals.icon_region(id) == Rect2(row * 16, 0, 16, 16), id + " dedicated HUD glyph")
		var first: PackedByteArray = art.get_region(Rect2i(0, row * 64, 64, 64)).get_data()
		var animated: bool = false
		for frame: int in range(6):
			check(int(card_meta.durations_ms[row * 6 + frame]) == TIMINGS[frame], id + " preserved card timing " + str(frame))
			if art.get_region(Rect2i(frame * 64, row * 64, 64, 64)).get_data() != first:
				animated = true
		check(animated, id + " animated branch illustration")
	check(Visuals.icon_texture("redline") == Visuals.ICONS and Visuals.icon_region("chain_impact") == Rect2(80, 0, 16, 16), "Legacy atlas remains compatible")
	check(int(fx_meta.tags.breakneck_charge_headings.to) - int(fx_meta.tags.breakneck_charge_headings.from) == 7, "Eight independently baked isometric charge headings")
	check(Visuals._heading(Vector2(1, -1)) == 0 and Visuals._heading(Vector2.ONE) == 2, "World direction maps to fixed isometric heading")
	var pose: Dictionary = Visuals.recovery_pose({"anchor_charge": 1.0, "power_mutations": {"dead_centre": "bulwark"}, "phase": 5}, [])
	check(float(pose.get("stance", 0.0)) == 4.0 and pose.get("lean", Vector2.ONE) == Vector2.ZERO, "Bulwark visibly settles with contact pivot fixed")
	for cue: String in CUES:
		check(Sound.SOUNDS.has(cue), cue + " dedicated audio exists")
		check(Sound.SOUNDS[cue].get_length() > 0.0 and Sound.SOUNDS[cue].get_length() <= 0.67, cue + " finite short signature")
		check(float(Sound.COOLDOWN.get(cue, 0.0)) > 0.0, cue + " explicit debounce")
	check(Sound.MAX_CHANNELS == 8, "Original eight-channel cap preserved")
	check(int(Sound.PRIORITY.mutation_select) > int(Sound.PRIORITY.heavy), "Major transformation survives crowd contacts")
	check(int(Sound.PRIORITY.counterweight_release) > int(Sound.PRIORITY.counterweight_store), "Release takes priority over storage chatter")
	var sound: Node = Sound.new()
	root.add_child(sound)
	AudioServer.set_bus_mute(0, true)
	for _i: int in range(24):
		sound.play_sound("runaway_hit")
	check(int(sound.played_counts.get("runaway_hit", 0)) == 1, "Same-frame overload contacts aggregate")
	for _i: int in range(24):
		sound.play_sound("slipstream_cross")
	check(int(sound.played_counts.get("slipstream_cross", 0)) == 1, "Repeated lane crossing cannot flood audio")
	for _i: int in range(8):
		sound.audio_time += 0.7
		sound.play_sound("mutation_select")
	var before: int = int(sound.played_counts.get("small_hit", 0))
	sound.play_sound("small_hit")
	check(int(sound.played_counts.get("small_hit", 0)) == before, "Quiet crowd cannot replace mutation confirmation")
	check(sound.channels.size() == 8 and int(sound.audio_snapshot().active) <= 8, "Escalation retains hard audio cap")
	for channel: AudioStreamPlayer in sound.channels:
		channel.stop()
	sound.free()
	# Even the dummy backend releases mixer ownership on its next mix tick.
	await create_timer(0.70).timeout
	await process_frame
	await process_frame
	print("ESCALATION_ASSETS_TEST_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
