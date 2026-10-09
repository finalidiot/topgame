extends Node2D
## Quiet presentation-only deck reuses the editable native metal plate artwork.
## It never reads actors, changes the world, or intercepts input.
const FrontEnd = preload("res://scripts/front_end.gd")
var extent: Vector2 = Vector2(800,480)
var arena: Rect2 = Rect2(80,60,640,360)
var deck: StyleBoxTexture
var casing: StyleBoxTexture

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	deck = FrontEnd.authored_style("metal_plate","NORMAL") as StyleBoxTexture
	casing = FrontEnd.authored_style("inspection_frame","INSPECTION") as StyleBoxTexture
	if deck != null: deck.modulate_color = Color(0.50,0.55,0.59,1.0)
	if casing != null: casing.modulate_color = Color(0.68,0.73,0.77,1.0)
	queue_redraw()

func set_layout(layout: Dictionary) -> void:
	if extent == Vector2(layout.canvas_size) and arena == Rect2(layout.arena_rect): return
	extent = layout.canvas_size
	arena = layout.arena_rect
	queue_redraw()

func _draw() -> void:
	# A two-pixel overscan covers fractional stretch rounding at the client edge.
	draw_rect(Rect2(Vector2(-2,-2),extent+Vector2(4,4)),Color("10151f"))
	# One continuous restrained casing. Repeated tiles made unused space look
	# busy without making the actual arena larger; the native view gets priority.
	if deck != null: deck.draw(get_canvas_item(),Rect2(Vector2(-2,-2),extent+Vector2(4,4)))
	if casing != null: casing.draw(get_canvas_item(),arena.grow(9.0))

func diagnostic_snapshot() -> Dictionary:
	return {"extent":extent,"arena":arena,"authored_texture":FrontEnd.AUTHORED_ROOT+"metal_plate.png",
		"native_master":"res://assets/source-art/human_feedback003a/metal_plate.aseprite",
		"nearest_neighbour":true,"input_interception":false,"world_changes":false}
