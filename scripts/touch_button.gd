extends Button
## Small menu caps keep a minimum44px touch target on the native phone surface.
var touch_targets: bool = OS.has_feature("mobile")
func _has_point(point: Vector2) -> bool:
	var area = Rect2(Vector2.ZERO,size)
	if not touch_targets: return area.has_point(point)
	var extra: Vector2 = (Vector2(44,44)-size).max(Vector2.ZERO)*0.5
	if not area.grow_individual(extra.x,extra.y,extra.x,extra.y).has_point(point): return false
	# Closely spaced controls select the nearest centre, never two actions.
	var global_point: Vector2 = get_global_transform()*point
	var distance: float = global_point.distance_squared_to(get_global_rect().get_center())
	for sibling: Node in get_parent().get_children():
		if sibling == self or not sibling is Button or not sibling.is_visible_in_tree() or sibling.disabled: continue
		var sibling_area: Rect2 = sibling.get_global_rect()
		var sibling_extra: Vector2 = (Vector2(44,44)-sibling_area.size).max(Vector2.ZERO)*0.5
		if sibling_area.grow_individual(sibling_extra.x,sibling_extra.y,sibling_extra.x,sibling_extra.y).has_point(global_point) and global_point.distance_squared_to(sibling_area.get_center()) < distance: return false
	return true
