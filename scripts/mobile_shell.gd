extends Node2D
## Full physical Android client, uniformly projected into a responsive logical
## surface. The separate combat SubViewport remains 640x360 inside Main.
const Game = preload("res://scripts/main.gd")
const Layout = preload("res://scripts/combat_hud_layout.gd")
const NATIVE = Vector2i(800,480)
var surface: SubViewportContainer
var game_view: SubViewport
var content: Node
var _display_layout: Dictionary = {}

static func fit_surface(available: Rect2i) -> Rect2i:
	# Compatibility accessor now means full client coverage, not a5:3 island.
	return available

func _ready() -> void:
	if not OS.has_feature("mobile"):
		add_child(Game.new())
		return
	mount_mobile_surface(Game.new())

func mount_mobile_surface(game: Node) -> void:
	# Window pixels are the physical outer surface. EXPAND is applied exactly
	# once by mobile_canvas below; a second Window stretch would distort input.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_factor = 1.0
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	get_window().content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	content = game
	surface = SubViewportContainer.new()
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(surface)
	game_view = SubViewport.new()
	game_view.disable_3d = true
	game_view.handle_input_locally = true
	game_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface.add_child(game_view)
	get_window().size_changed.connect(_fit)
	_fit()
	game_view.add_child(game)

func _process(_dt: float) -> void:
	# Android can change insets without changing client size after returning
	# from a gesture/system UI overlay. Refit is inert while values are stable.
	if is_instance_valid(game_view): _fit()

func _fit() -> void:
	var client: Vector2i = get_window().size
	var safe: Rect2i = Rect2i(Vector2i.ZERO,client)
	if OS.has_feature("mobile"):
		safe = DisplayServer.get_display_safe_area()
	apply_display_layout(client,safe)

## Public physical projection also used by declared display/cutout QA fixtures.
## It only changes presentation and never starts/resets/steps a combat world.
func apply_display_layout(display_size: Vector2i, safe_area: Rect2i) -> Dictionary:
	var layout: Dictionary = Layout.mobile_canvas(display_size,safe_area)
	if _display_layout == layout: return layout
	_display_layout = layout
	if not is_instance_valid(surface) or not is_instance_valid(game_view): return layout
	game_view.size = layout.canvas_size
	surface.position = Vector2.ZERO
	surface.size = Vector2(layout.canvas_size)
	surface.scale = Vector2.ONE*float(layout.ui_scale)
	if is_instance_valid(content) and content.has_method("set_mobile_presentation"):
		content.set_mobile_presentation(Vector2(layout.canvas_size),layout.safe_rect)
	return layout

func layout_snapshot() -> Dictionary:
	return _display_layout.duplicate(true)
