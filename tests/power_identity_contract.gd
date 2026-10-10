extends RefCounted
## Shared assertions for the active C5 identity contract. Historical atlas
## integrity is checked separately in the retained presentation suites.
const Identity = preload("res://scripts/power_identity.gd")
const Catalog = preload("res://scripts/run_powers.gd")
const Visuals = preload("res://scripts/power_visuals.gd")
const Defence = preload("res://scripts/defence_art.gd")
const Ecology = preload("res://scripts/ecology_art.gd")

static func catalog_art(check: Callable, art_id: String, supplied: Dictionary = {}) -> void:
	var authored: Dictionary = Identity.art(art_id)
	var is_defence: bool = authored.is_empty() and not Defence.art(art_id).is_empty()
	if is_defence: authored = Defence.art(art_id)
	var is_ecology: bool = authored.is_empty() and not Ecology.art(art_id).is_empty()
	if is_ecology: authored = Ecology.art(art_id)
	check.call(not authored.is_empty(), art_id + " active per-family identity exists")
	if authored.is_empty(): return
	var power: Dictionary = supplied
	if power.is_empty():
		power = Catalog.get_mutation(art_id) if Catalog.MUTATIONS.has(art_id) else (Catalog.get_owned_power(art_id.trim_suffix("_ii"), 2) if art_id.ends_with("_ii") else Catalog.get_power(art_id))
	var family: Dictionary = Ecology.meta().families[authored.family] if is_ecology else (Defence.meta().families[authored.family] if is_defence else Identity.family_info(str(authored.family)))
	var cards: Dictionary = family.cards
	var icons: Dictionary = family.icons
	check.call(power.source_tag == art_id and power.card_texture == cards.texture and power.icon == icons.texture, art_id + " catalogue selects its family masters")
	var poses: int = 6 if is_ecology else 12
	check.call(int(power.card_cell) == 64 and int(power.card_frames) == poses and int(power.card_row) == int(authored.card_row), art_id + " exact native card poses mapped")
	check.call(int(power.card_static_frame) >= 0 and int(power.card_static_frame) < poses, art_id + " readable static pose is bounded")
	check.call(power.card_durations_ms == authored.card_durations_ms and power.card_durations_ms.size() == poses, art_id + " catalogue retains individually authored timings")
	if is_ecology:
		var tag: Dictionary = cards.tags[art_id]
		check.call(int(cards.columns) == 6 and int(cards.frame_count) == 12 and int(tag.from) == int(authored.card_row) * 6 and int(tag.to) == int(authored.card_row) * 6 + 5, art_id + " separate six-pose siblings occupy exact native atlas rows")
	check.call(Visuals.icon_texture(art_id) == (Defence.texture(str(icons.texture)) if is_defence else Identity.texture(str(icons.texture))) and Visuals.icon_region(art_id) == Rect2(int(authored.icon_frame) * 16, 0, 16, 16), art_id + " independent native HUD icon selected")
	check.call(str(cards.source) != str(icons.source) and cards.cell == [64.0, 64.0] and icons.cell == [16.0, 16.0], art_id + " cards and icons are independently editable sources")
