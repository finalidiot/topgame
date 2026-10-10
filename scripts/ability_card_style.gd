extends RefCounted
## Run investment semantics only. Art identity and permanent part rarity are separate.
const BODY: Color = Color("e3e8dc")
const BASE_ACCENT: Color = Color("bdcbd3")
const UPGRADE_ACCENT: Color = Color("64d8ef")
const MUTATION_ACCENT: Color = Color("d49bf1")
const BASE_BORDER: Color = Color("526776")

static func get_card_tier_style(rank: int = 1, mutation: String = "") -> Dictionary:
	var tier: String = "mutation" if rank >= 3 or not mutation.is_empty() else ("rank_ii" if rank == 2 else "power")
	var accent: Color = MUTATION_ACCENT if tier == "mutation" else (UPGRADE_ACCENT if tier == "rank_ii" else BASE_ACCENT)
	return {"tier":tier, "badge":{"power":"POWER", "rank_ii":"RANK II", "mutation":"MUTATION"}[tier],
		"title_color":BODY if tier == "power" else accent, "accent_color":accent, "body_color":BODY,
		"border_color":BASE_BORDER if tier == "power" else accent, "border_width":1 if tier == "power" else 2,
		"focus_width":2 if tier == "power" else 3, "tier_marks":1 if tier == "power" else (2 if tier == "rank_ii" else 3),
		"reveal_intensity":0 if tier == "power" else (1 if tier == "rank_ii" else 2)}

static func frame_style(style: Dictionary, focused: bool = false) -> StyleBoxFlat:
	# A border-only UI overlay preserves the authored metal plate and illustration.
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.draw_center = false
	frame.anti_aliasing = false
	frame.border_color = style.accent_color if focused else style.border_color
	frame.set_border_width_all(int(style.focus_width if focused else style.border_width))
	return frame
