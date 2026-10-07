extends Node2D
## Render the same native game inside an integer-scaled, cutout-safe surface.
const Game = preload("res://scripts/main.gd")
const NATIVE = Vector2i(640,360)
var surface: SubViewportContainer
var game_view: SubViewport

static func fit_surface(available: Rect2i) -> Rect2i:
	var scale: int = maxi(1,mini(available.size.x/NATIVE.x,available.size.y/NATIVE.y))
	var size: Vector2i = NATIVE*scale
	return Rect2i(available.position+(available.size-size)/2,size)

func _ready() -> void:
	if not OS.has_feature("mobile"):
		add_child(Game.new())
		return
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
	game_view.add_child(Game.new())

func _fit() -> void:
	var screen: Rect2i = Rect2i(Vector2i.ZERO,get_window().size)
	var safe: Rect2i = DisplayServer.get_display_safe_area().intersection(screen)
	if safe.size.x < NATIVE.x or safe.size.y < NATIVE.y: safe = screen
	var area: Rect2i = fit_surface(safe)
	surface.position = Vector2(area.position)
	surface.size = Vector2(NATIVE)
	surface.scale = Vector2(float(area.size.x)/NATIVE.x,float(area.size.y)/NATIVE.y)
