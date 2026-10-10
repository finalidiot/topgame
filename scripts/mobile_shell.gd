extends Node2D
## Render the same native game inside an integer-scaled, cutout-safe surface.
const Game = preload("res://scripts/main.gd")
const NATIVE = Vector2i(800,480)
var surface: SubViewportContainer
var game_view: SubViewport

static func fit_surface(available: Rect2i) -> Rect2i:
	var scale: int = mini(available.size.x/NATIVE.x,available.size.y/NATIVE.y)
	# Whole authored pixels whenever the display fits. Smaller safe surfaces
	# use a bounded uniform5:3 fit rather than cropping either HUD margin.
	var size: Vector2i = NATIVE*scale if scale>=1 else Vector2i(5,3)*maxi(0,mini(available.size.x/5,available.size.y/3))
	return Rect2i(available.position+(available.size-size)/2,size)

func _ready() -> void:
	if not OS.has_feature("mobile"):
		add_child(Game.new())
		return
	mount_mobile_surface(Game.new())

## Production Android and isolated nested-viewport tests share this exact path.
## The caller supplies the content; this method never creates or opens a save.
func mount_mobile_surface(content: Node) -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_factor = 1.0
	surface = SubViewportContainer.new()
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(surface)
	game_view = SubViewport.new()
	game_view.size = NATIVE
	game_view.disable_3d = true
	game_view.handle_input_locally = true
	game_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface.add_child(game_view)
	get_window().size_changed.connect(_fit)
	_fit()
	game_view.add_child(content)

func _fit() -> void:
	var screen: Rect2i = Rect2i(Vector2i.ZERO,get_window().size)
	var safe: Rect2i = DisplayServer.get_display_safe_area().intersection(screen)
	if safe.size.x <= 0 or safe.size.y <= 0: safe = screen
	var area: Rect2i = fit_surface(safe)
	surface.position = Vector2(area.position)
	surface.size = Vector2(NATIVE)
	surface.scale = Vector2(float(area.size.x)/NATIVE.x,float(area.size.y)/NATIVE.y)
