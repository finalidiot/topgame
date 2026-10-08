extends RefCounted
## Native-pixel edge reservations shared by the HUD and world spin bars.
## The mobile action rail preserves the accepted hold-and-drag controls.
const VIEW = Rect2(0, 0, 640, 360)
const TOP_EDGE = Rect2(0, 0, 640, 86)
const BOTTOM_EDGE = Rect2(0, 288, 640, 72)
const MOBILE_ACTION_RAIL = Rect2(544, 228, 88, 126)
const PLAY_REGION = Rect2(22, 86, 596, 202)
const MOBILE_PLAY_REGION = Rect2(22, 86, 518, 202)

static func play_region(mobile: bool = false) -> Rect2:
	return MOBILE_PLAY_REGION if mobile else PLAY_REGION

static func world_bar_allowed(rect: Rect2, mobile: bool = false) -> bool:
	return VIEW.encloses(rect) and not rect.intersects(TOP_EDGE) and not rect.intersects(BOTTOM_EDGE) and not (mobile and rect.intersects(MOBILE_ACTION_RAIL))

static func snapshot(mobile: bool = false) -> Dictionary:
	return {"native_view": [640, 360], "play_region": play_region(mobile), "top_edge": TOP_EDGE,
		"bottom_edge": BOTTOM_EDGE, "mobile_action_rail": MOBILE_ACTION_RAIL if mobile else Rect2(),
		"mobile_layout": mobile, "scope": "Permanent HUD uses edge reservations; temporary READY/launch announcements occur outside live combat."}
