extends SceneTree
## New native-card/source/audio production contracts. No combat state changes.
const Powers = preload("res://scripts/run_powers.gd")
const Visuals = preload("res://scripts/power_visuals.gd")
const Sound = preload("res://scripts/sound.gd")
const Cards: Texture2D = preload("res://assets/powers/cards.png")
const StarterSheets: Dictionary = {
	"breaker": preload("res://assets/top/starters/breaker_spin.png"),
	"bastion": preload("res://assets/top/starters/bastion_spin.png"),
	"vane": preload("res://assets/top/starters/vane_spin.png")
}
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
	var meta: Dictionary = Visuals._meta("cards")
	check(not meta.is_empty(), "New card manifest exists")
	check(Cards.get_size() == Vector2(384, 384), "Six columns / six rows of native 64px art")
	check(int(meta.cell[0]) == 64 and int(meta.cell[1]) == 64, "Native card cell size")
	check(int(meta.pivot[0]) == 32 and int(meta.pivot[1]) == 32, "Stable contact pivot")
	check(int(meta.get("frame_count", 0)) == 36, "Thirty-six authored card cels")
	check(meta.get("layers", []).size() == 5, "Five named editable production layers")
	var art: Image = Cards.get_image()
	var source: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/source-art/power_cards_002b1.aseprite")
	check(source.size() > 128, "Editable Aseprite master is supplied")
	if source.size() > 128:
		check(source.decode_u16(4) == 0xA5E0, "Aseprite master file magic")
		check(source.decode_u16(6) == 36 and source.decode_u16(8) == 64 and source.decode_u16(10) == 64, "Source has all frames at native dimensions")
		check(source.decode_u16(12) == 32 and source.decode_u32(0) == source.size(), "RGBA source header length valid")
	for row: int in range(Powers.LEGACY_ART_IDS.size()):
		var id: String = Powers.LEGACY_ART_IDS[row]
		var power: Dictionary = Powers.get_power(id)
		var tag: Dictionary = meta.tags.get(id, {})
		check(int(tag.get("from", -1)) == row * 6 and int(tag.get("to", -1)) == row * 6 + 5, id + " stable source tag")
		check(int(power.card_row) == row and int(power.card_frames) == 6, id + " card/catalog row mapping")
		check(int(power.card_static_frame) >= 0 and int(power.card_static_frame) < 6, id + " readable non-focused authored pose")
		check(power.card_texture == Powers.CARD_SHEET and not str(power.category).is_empty() and not str(power.card_copy).is_empty(), id + " production card data")
		check(Visuals._frame("cards", id, 0.0) == row * 6 and Visuals._frame("cards", id, 99.0) == row * 6 + 5, id + " animation bounds")
		var different: bool = false
		var first: PackedByteArray = art.get_region(Rect2i(0, row * 64, 64, 64)).get_data()
		for frame: int in range(6):
			check(int(meta.durations_ms[row * 6 + frame]) == int(power.card_durations_ms[frame]), id + " source timing " + str(frame))
			if art.get_region(Rect2i(frame * 64, row * 64, 64, 64)).get_data() != first:
				different = true
		check(different, id + " authored poses genuinely animate")
		check(Visuals.icon_region(id) == Rect2(row * 16, 0, 16, 16), id + " legacy HUD icon stays compatible")
	for cue: String in ["ui_focus", "card_select", "near_level", "level_up", "resume"]:
		check(Sound.SOUNDS.has(cue), cue + " audio cue loaded")
		check(Sound.SOUNDS[cue].get_length() > 0.0 and Sound.SOUNDS[cue].get_length() <= 0.50, cue + " finite short audio")
		check(float(Sound.COOLDOWN.get(cue, 0.0)) > 0.0, cue + " duplicate cue debounce")
	check(not Sound.SOUNDS.has("xp"), "No XP increment sound spam")
	check(int(Sound.PRIORITY.level_up) > int(Sound.PRIORITY.heavy), "Level milestone survives contact audio")
	check(Sound.MAX_CHANNELS == 8, "Existing audio channel cap preserved")
	var starter_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/top/starters/manifest.json"))
	check(starter_meta.layers.size() == 3 and int(starter_meta.pivot[0]) == 24 and int(starter_meta.pivot[1]) == 40, "Starter source layers and ground pivot")
	for identity: String in StarterSheets:
		var sheet: Texture2D = StarterSheets[identity]
		var original: Texture2D = load("res://assets/top/parts/blades/%s_spin.png" % str(starter_meta.starters[identity].blade))
		check(sheet.get_size() == Vector2(384,48), identity + " native eight-phase starter blade")
		var authored: Image = sheet.get_image()
		var old: Image = original.get_image()
		var same_silhouette: bool = true
		for y: int in range(48):
			for x: int in range(384):
				if authored.get_pixel(x,y).a != old.get_pixel(x,y).a:
					same_silhouette = false
		check(same_silhouette, identity + " preserves every authored blade silhouette")
	print("CARD_ASSETS_TEST_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
