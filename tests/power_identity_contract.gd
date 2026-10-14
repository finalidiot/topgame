extends RefCounted
## Shared assertions for the active C5 identity contract. Historical atlas
## integrity is checked separately in the retained presentation suites.
const Identity = preload("res://scripts/power_identity.gd")
const Catalog = preload("res://scripts/run_powers.gd")
const Visuals = preload("res://scripts/power_visuals.gd")
const Defence = preload("res://scripts/defence_art.gd")

static func catalog_art(check: Callable, art_id: String, supplied: Dictionary = {}) -> void:
	var base: Dictionary = Catalog.BaseArt.art(art_id)
	if not base.is_empty():
		var power: Dictionary = Catalog.get_owned_power(art_id.trim_suffix("_ii"), 2) if art_id.ends_with("_ii") else Catalog.get_power(art_id)
		check.call(power.source_tag == art_id and power.card_texture == base.card_texture and power.card_row == base.card_row, art_id + " native vector card source and row agree")
		check.call(ResourceLoader.exists(base.card_texture) and ResourceLoader.exists(base.icon), art_id + " native editable vector identity assets imported")
		check.call(Visuals.icon_region(art_id) == Rect2(int(base.icon_frame)*16,0,16,16) and Visuals.icon_texture(art_id) == load(base.icon), art_id + " vector icon selected independently")
		check.call(power.card_frames == 6 and power.card_durations_ms.size() == 6, art_id + " six bounded poses")
		return
	var authored: Dictionary = Identity.art(art_id)
	var is_defence: bool = authored.is_empty() and not Defence.art(art_id).is_empty()
	if is_defence: authored = Defence.art(art_id)
	check.call(not authored.is_empty(), art_id + " active per-family identity exists")
	if authored.is_empty(): return
	var power: Dictionary = supplied
	if power.is_empty():
		power = Catalog.get_mutation(art_id) if Catalog.MUTATIONS.has(art_id) else (Catalog.get_owned_power(art_id.trim_suffix("_ii"), 2) if art_id.ends_with("_ii") else Catalog.get_power(art_id))
	var family: Dictionary = Defence.meta().families[authored.family] if is_defence else Identity.family_info(str(authored.family))
	var cards: Dictionary = family.cards
	var icons: Dictionary = family.icons
	check.call(power.source_tag == art_id and power.card_texture == cards.texture and power.icon == icons.texture, art_id + " catalogue selects its family masters")
	var poses: int = 12
	check.call(int(power.card_cell) == 64 and int(power.card_frames) == poses and int(power.card_row) == int(authored.card_row), art_id + " exact native card poses mapped")
	check.call(int(power.card_static_frame) >= 0 and int(power.card_static_frame) < poses, art_id + " readable static pose is bounded")
	check.call(power.card_durations_ms == authored.card_durations_ms and power.card_durations_ms.size() == poses, art_id + " catalogue retains individually authored timings")
	check.call(Visuals.icon_texture(art_id) == (Defence.texture(str(icons.texture)) if is_defence else Identity.texture(str(icons.texture))) and Visuals.icon_region(art_id) == Rect2(int(authored.icon_frame) * 16, 0, 16, 16), art_id + " independent native HUD icon selected")
	check.call(str(cards.source) != str(icons.source) and cards.cell == [64.0, 64.0] and icons.cell == [16.0, 16.0], art_id + " cards and icons are independently editable sources")
