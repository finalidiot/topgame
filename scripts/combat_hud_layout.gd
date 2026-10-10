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
	# Text uses discrete native-pixel scales. Large monitors
	# spend their additional room on the arena and spacing rather than giant HUD.
	# HD clients spend their room on the actual play view. Increase UI scale only
	# on substantially larger monitors, rather than shrinking a maximised arena.
	var ui_scale: float = 2.0 if client_size.x >= 3840 and client_size.y >= 2160 else (1.5 if client_size.x >= 2560 and client_size.y >= 1440 else 1.0)
	var canvas: Vector2i = Vector2i(maxi(800,floori(client_size.x/ui_scale)),maxi(480,floori(client_size.y/ui_scale)))
	return {"ui_scale":ui_scale,"canvas_size":canvas,"client_size":client_size,
		"native_window_managed_by_os":true,"changes_window_mode":false}

static func responsive(canvas_size: Vector2, mobile: bool = false, safe_rect: Rect2 = Rect2()) -> Dictionary:
	if mobile: return mobile_responsive(canvas_size,safe_rect)
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

## EXPAND projection: one scalar covers the physical client, with at most one
## logical pixel of clipped raster overscan. Insets never reduce the background.
static func mobile_canvas(display_size: Vector2i, physical_safe: Rect2i = Rect2i()) -> Dictionary:
	var physical: Vector2i = Vector2i(maxi(1,display_size.x),maxi(1,display_size.y))
	var ui_scale: float = minf(float(physical.x)/800.0,float(physical.y)/480.0)
	var visible: Vector2 = Vector2(physical)/ui_scale
	var canvas: Vector2i = Vector2i(ceili(visible.x-0.000001),ceili(visible.y-0.000001))
	var screen: Rect2i = Rect2i(Vector2i.ZERO,physical)
	var safe: Rect2i = physical_safe.intersection(screen)
	if safe.size.x <= 0 or safe.size.y <= 0: safe = screen
	return {"canvas_size":canvas,"logical_visible_size":visible,"ui_scale":ui_scale,
		"client_size":physical,"physical_safe_area":safe,
		"safe_rect":Rect2(Vector2(safe.position)/ui_scale,Vector2(safe.size)/ui_scale),
		"presentation_pixels":Rect2(Vector2.ZERO,Vector2(canvas)*ui_scale),
		"clipped_overscan_pixels":Vector2(canvas)*ui_scale-Vector2(physical),
		"unused_physical_area":0.0,"uniform_scale":true,"nearest_neighbour":true,
		"content_scale_policy":"expand_fractional_uniform","world_dimensions_changed":false}

static func _mobile_reference(canvas_size: Vector2, requested_safe: Rect2 = Rect2()) -> Dictionary:
	var extent: Vector2 = Vector2(maxf(1.0,canvas_size.x),maxf(1.0,canvas_size.y))
	var bounds: Rect2 = Rect2(Vector2.ZERO,extent)
	var safe: Rect2 = requested_safe.intersection(bounds)
	if safe.size.x <= 0.0 or safe.size.y <= 0.0: safe = bounds
	var wide: bool = safe.size.x >= 940.0 and safe.size.y >= 440.0
	var result: Dictionary
	if not wide:
		# Retain the readable reference HUD at narrower ratios. Actual safe
		# coordinates still govern every panel and the far-right action rail.
		result = responsive(safe.size,false)
		var arena: Rect2 = result.arena_rect
		arena.position += safe.position
		# Very small/inset surfaces fit rather than crop the fixed combat world.
		var arena_scale: float = minf(maxf(1.0,safe.size.x-160.0)/640.0,maxf(1.0,safe.size.y-120.0)/360.0)
		arena.size = ARENA_VIEW.size*arena_scale
		arena.position = safe.position+(safe.size-arena.size)*0.5
		result.arena_rect = arena
		result.arena_scale = arena_scale
		for key: String in result.regions:
			var region: Rect2 = result.regions[key]
			region.position += safe.position
			result.regions[key] = region
		result.state_left += safe.position
		result.state_right += safe.position
		result.right_x += safe.position.x
		result.progress_x += safe.position.x
		result.bottom_y += safe.position.y
		result.powers_y += safe.position.y
		var rail_x: float = safe.end.x-76.0
		var actions_y: float = minf(arena.position.y+234.0,safe.end.y-126.0)
		result.burst_rect = Rect2(rail_x,actions_y,70,52)
		result.brake_rect = Rect2(rail_x,actions_y+60.0,70,52)
		result.powers_columns = 7
		result.regions["power_note"] = Rect2(safe.position+Vector2(86,safe.size.y-56.0),Vector2(136,18))
		result.regions["powers"] = Rect2(safe.position+Vector2(safe.size.x*0.5-112.0,safe.size.y-56.0),Vector2(224,22))
		result.regions["rerolls"] = Rect2(safe.position+Vector2(6,safe.size.y-55.0),Vector2(74,24))
		result.regions["pause"] = Rect2(safe.position+Vector2(6,8),Vector2(68,24))
		result.regions["impact"] = Rect2(Vector2(result.state_left)+Vector2(0,172),Vector2(result.state_width,68))
	else:
		# Wide phones put persistent decisions beside the arena, reclaiming its
		# height without putting interactive controls over world pixels.
		var reserve: float = clampf(safe.size.x*0.115,108.0,152.0)
		var rail_width: float = reserve-12.0
		var left_x: float = safe.position.x+6.0
		var right_x: float = safe.end.x-reserve+6.0
		var arena_scale: float = minf((safe.size.x-reserve*2.0-16.0)/640.0,(safe.size.y-12.0)/360.0)
		var arena_size: Vector2 = ARENA_VIEW.size*arena_scale
		var arena: Rect2 = Rect2(safe.position+(safe.size-arena_size)*0.5,arena_size)
		var bottom: float = safe.end.y
		var regions: Dictionary = {
			"player_reserve":Rect2(left_x,safe.position.y+6,rail_width,48),
			"pressure":Rect2(right_x,safe.position.y+6,rail_width,48),
			"clock":Rect2(left_x,safe.position.y+60,rail_width,48),
			"state_left":Rect2(left_x,safe.position.y+146,rail_width,144),
			"state_right":Rect2(right_x,safe.position.y+66,rail_width,144),
			"impact":Rect2(left_x,safe.position.y+296,rail_width,44),
			"burst":Rect2(right_x,bottom-214,rail_width,28),
			"progress":Rect2(right_x,bottom-180,rail_width,40),
			"power_note":Rect2(left_x,bottom-136,rail_width,18),
			"powers":Rect2(left_x,bottom-112,rail_width,72),
			"powers_rerolls":Rect2(left_x,bottom-136,rail_width,132),
			"rerolls":Rect2(left_x,bottom-28,rail_width,24),
			"pause":Rect2(left_x,safe.position.y+114,rail_width,26)}
		result = {"arena_rect":arena,"arena_scale":arena_scale,"regions":regions,
			"state_left":regions.state_left.position,"state_right":regions.state_right.position,"state_width":rail_width,
			"top_width":rail_width,"right_x":right_x,"burst_width":rail_width,
			"progress_x":right_x,"progress_width":rail_width,"bottom_y":bottom-180,
			"powers_y":regions.powers.position.y,"powers_columns":maxi(1,floori(rail_width/32.0)),
			"burst_rect":Rect2(right_x,bottom-134,rail_width,52),"brake_rect":Rect2(right_x,bottom-74,rail_width,52)}
	var menu_scale: float = minf(1.0,minf(safe.size.x/640.0,safe.size.y/360.0))
	result["menu_scale"] = menu_scale
	result["menu_origin"] = safe.position+(safe.size-ARENA_VIEW.size*menu_scale)*0.5
	result["canvas_size"] = extent
	result["safe_rect"] = safe
	result["steering_rect"] = Rect2(result.arena_rect).intersection(safe)
	result["mobile_layout"] = true
	result["mobile_wide"] = wide
	result["nearest_neighbour"] = true
	result["world_dimensions_changed"] = false
	result.regions["burst_button"] = result.burst_rect
	result.regions["brake_button"] = result.brake_rect
	result.regions["announcement"] = Rect2(Vector2(result.arena_rect.get_center().x-175.0,result.arena_rect.position.y+result.arena_rect.size.y*0.36),Vector2(350,64))
	return result

## HUD text/panels have their own uniform safe transform. This also fits devices
## whose camera/navigation insets leave less than the reference480 logical pixels.
static func mobile_responsive(canvas_size: Vector2, requested_safe: Rect2 = Rect2()) -> Dictionary:
	var extent: Vector2 = Vector2(maxf(1.0,canvas_size.x),maxf(1.0,canvas_size.y))
	var safe: Rect2 = requested_safe.intersection(Rect2(Vector2.ZERO,extent))
	if safe.size.x <= 0.0 or safe.size.y <= 0.0: safe = Rect2(Vector2.ZERO,extent)
	var hud_scale: float = minf(1.0,minf(safe.size.x/800.0,safe.size.y/480.0))
	var reference: Dictionary = _mobile_reference(safe.size/hud_scale,Rect2(Vector2.ZERO,safe.size/hud_scale))
	var result: Dictionary = reference.duplicate(true)
	for key: String in result.regions:
		var area: Rect2 = result.regions[key]
		result.regions[key] = Rect2(safe.position+area.position*hud_scale,area.size*hud_scale)
	for key: String in ["arena_rect","burst_rect","brake_rect","steering_rect"]:
		var area: Rect2 = result[key]
		result[key] = Rect2(safe.position+area.position*hud_scale,area.size*hud_scale)
	for key: String in ["state_left","state_right","menu_origin"]:
		result[key] = safe.position+Vector2(result[key])*hud_scale
	for key: String in ["arena_scale","state_width","top_width","burst_width","progress_width","menu_scale"]:
		result[key] = float(result[key])*hud_scale
	for key: String in ["right_x","progress_x"]: result[key] = safe.position.x+float(result[key])*hud_scale
	for key: String in ["bottom_y","powers_y"]: result[key] = safe.position.y+float(result[key])*hud_scale
	result["canvas_size"] = extent
	result["safe_rect"] = safe
	result["hud_scale"] = hud_scale
	result["hud_origin"] = safe.position
	result["hud_layout"] = reference
	result["menu_scale"] = minf(1.0,minf(safe.size.x/640.0,safe.size.y/360.0))
	result["menu_origin"] = safe.position+(safe.size-ARENA_VIEW.size*float(result.menu_scale))*0.5
	return result
