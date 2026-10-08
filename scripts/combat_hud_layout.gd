extends RefCounted
## Canonical world pixels occupy their own viewport; permanent HUD has real margins.
const VIEW = Rect2(0, 0, 800, 480)
const ARENA_VIEW = Rect2(0, 0, 640, 360)
const ARENA_ORIGIN = Vector2(80, 60)
const TOP_EDGE = Rect2(0, 0, 800, 60)
const BOTTOM_EDGE = Rect2(0, 420, 800, 60)
const LEFT_EDGE = Rect2(0, 60, 80, 360)
const RIGHT_EDGE = Rect2(720, 60, 80, 360)
const PLAY_REGION = Rect2(80, 60, 640, 360)
const MOBILE_PLAY_REGION = PLAY_REGION
const MOBILE_ACTION_RAIL = Rect2(724, 294, 72, 120)

static func play_region(_mobile: bool = false) -> Rect2:
	return PLAY_REGION

static func world_bar_allowed(rect: Rect2, _mobile: bool = false) -> bool:
	return ARENA_VIEW.encloses(rect)

static func arena_point(root_point: Vector2) -> Vector2:
	return root_point - ARENA_ORIGIN

static func menu_point(root_point: Vector2) -> Vector2:
	return root_point - ARENA_ORIGIN

static func integer_fit(display_size: Vector2i) -> Dictionary:
	var multiple: int = maxi(1, floori(minf(float(display_size.x) / VIEW.size.x, float(display_size.y) / VIEW.size.y)))
	var extent: Vector2i = Vector2i(VIEW.size) * multiple
	return {"scale":multiple, "canvas_pixels":extent, "arena_pixels":Vector2i(640,360)*multiple,
		"letterbox":Vector2i((display_size-extent)/2), "nearest_neighbour":true, "world_dimensions_changed":false}

static func snapshot(mobile: bool = false) -> Dictionary:
	return {"native_view":[800,480], "arena_native_view":[640,360], "arena_origin":ARENA_ORIGIN,
		"play_region":PLAY_REGION, "top_edge":TOP_EDGE, "bottom_edge":BOTTOM_EDGE,
		"left_edge":LEFT_EDGE, "right_edge":RIGHT_EDGE, "mobile_action_rail":MOBILE_ACTION_RAIL if mobile else Rect2(),
		"mobile_layout":mobile, "scope":"Native world viewport, fixed isometric camera and physics; permanent HUD frames the separate 640x360 arena."}
