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

static func desktop_canvas(client_size: Vector2i) -> Dictionary:
	# Text stays at one or two native pixels per authored pixel. Large monitors
	# spend their additional room on the arena and spacing rather than giant HUD.
	var ui_scale: int = mini(2,maxi(1,floori(minf(float(client_size.x)/800.0,float(client_size.y)/480.0))))
	var canvas: Vector2i = Vector2i(maxi(800,client_size.x/ui_scale),maxi(480,client_size.y/ui_scale))
	return {"ui_scale":ui_scale,"canvas_size":canvas,"client_size":client_size,
		"native_window_managed_by_os":true,"changes_window_mode":false}

static func responsive(canvas_size: Vector2, mobile: bool = false) -> Dictionary:
	var extent: Vector2 = VIEW.size if mobile else Vector2(maxf(800.0,canvas_size.x),maxf(480.0,canvas_size.y)).floor()
	var available: Vector2 = extent-Vector2(160,120)
	var arena_scale: float = minf(available.x/640.0,available.y/360.0)
	# Prefer an integer when it uses at least90% of the possible arena area.
	# Otherwise nearest-neighbour uniform fitting makes useful client area count.
	var integer_scale: float = floorf(arena_scale)
	if integer_scale/arena_scale >= 0.95: arena_scale=integer_scale
	if mobile: arena_scale=1.0
	var arena_size: Vector2 = ARENA_VIEW.size*arena_scale
	var arena_origin: Vector2 = ((extent-arena_size)*0.5).floor()
	var play: Rect2 = Rect2(arena_origin,arena_size)
	var rail_width: float = maxf(68.0,minf(144.0,arena_origin.x-12.0))
	var rail_y: float = arena_origin.y+16.0
	var left_rail: Vector2 = Vector2(6,rail_y)
	var right_rail: Vector2 = Vector2(extent.x-rail_width-6.0,rail_y)
	var top_width: float = floorf((extent.x-304.0)*0.5)
	var right_x: float = extent.x-86.0-top_width
	var burst_width: float = floorf(available.x*0.35)
	var progress_x: float = 102.0+burst_width
	var bottom_y: float = extent.y-30.0
	return {"canvas_size":extent,"arena_rect":play,"arena_scale":arena_scale,
		"menu_origin":((extent-ARENA_VIEW.size)*0.5).floor(),
		"state_left":left_rail,"state_right":right_rail,"state_width":rail_width,
		"top_width":top_width,"right_x":right_x,"burst_width":burst_width,
		"progress_x":progress_x,"progress_width":extent.x-86.0-progress_x,
		"bottom_y":bottom_y,"powers_y":extent.y-56.0,
		"regions":{"player_reserve":Rect2(86,6,top_width,48),"pressure":Rect2(right_x,6,top_width,48),
			"clock":Rect2(extent.x*0.5-64.0,6,128,48),
			"powers_rerolls":Rect2(6,extent.y-56.0,extent.x-92.0,22),
			"burst":Rect2(86,bottom_y,burst_width,28),
			"progress":Rect2(progress_x,bottom_y,extent.x-86.0-progress_x,28),
			"state_left":Rect2(left_rail,Vector2(rail_width,144)),
			"state_right":Rect2(right_rail,Vector2(rail_width,144))},
		"nearest_neighbour":true,"world_dimensions_changed":false,"mobile_layout":mobile}
