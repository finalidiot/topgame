extends Control
## Visualises an already saved payout. Contains no economic API or save reference.
signal cue(kind: String)
const FrontEnd = preload("res://scripts/front_end.gd")
const CHIP: String = "res://assets/ui/human_feedback003a/credit_chip.png"
const DURATION: float = 0.9
var earned: int = 0
var old_balance: int = 0
var new_balance: int = 0
var running: bool = false
var elapsed: float = 0.0
var displayed_wallet: int = 0
var _chip: Texture2D
var _ticks: int = 0
var _earnings: Label
var _wallet: Label

func configure(amount: int, saved_wallet: int, animate: bool = true) -> void:
	earned = maxi(0, amount)
	new_balance = maxi(0, saved_wallet)
	old_balance = maxi(0, new_balance - earned)
	elapsed = 0.0
	_ticks = 0
	running = animate and earned > 0
	displayed_wallet = old_balance if running else new_balance
	if is_node_ready(): _update_labels()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(CHIP): _chip = load(CHIP)
	_earnings = _label(Vector2(12, 4), Vector2(178, 16), FrontEnd.TEXT)
	_wallet = _label(Vector2(201, 22), Vector2(136, 16), FrontEnd.BLUE)
	_update_labels()

func _label(at: Vector2, dimensions: Vector2, color: Color) -> Label:
	var node: Label = Label.new()
	node.position = at
	node.size = dimensions
	node.add_theme_font_override("font", FrontEnd.pixel_font())
	node.add_theme_font_size_override("font_size", 10)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node

func finish() -> void:
	if not running: return
	running = false
	elapsed = DURATION
	displayed_wallet = new_balance
	_update_labels()
	cue.emit("packet_new")
	queue_redraw()

func _process(delta: float) -> void:
	if not running: return
	elapsed = minf(DURATION, elapsed + delta)
	var fraction: float = clampf(elapsed / DURATION, 0.0, 1.0)
	displayed_wallet = mini(new_balance, old_balance + floori(earned * fraction))
	var tick: int = floori(fraction * 4.0)
	if tick > _ticks:
		_ticks = tick
		if tick < 4: cue.emit("packet_clink")
	_update_labels()
	if elapsed >= DURATION: finish()
	queue_redraw()

func _update_labels() -> void:
	if not is_instance_valid(_earnings): return
	_earnings.text = "RUN EARNINGS +%d" % earned
	_wallet.text = "WALLET %d" % displayed_wallet
	set_meta("old_balance", old_balance)
	set_meta("saved_balance", new_balance)

func _draw() -> void:
	if not running or _chip == null: return
	# Six physical markers represent the transfer even at the maximum reward.
	for index: int in range(6):
		var progress: float = clampf((elapsed / DURATION - index * 0.055) / 0.68, 0.0, 1.0)
		if progress <= 0.0 or progress >= 1.0: continue
		var point: Vector2 = Vector2(145, 12).lerp(Vector2(290, 12), progress)
		point.y -= sin(progress * PI) * (8 + index % 3)
		var frame: int = int(elapsed * 15 + index) % 4
		draw_texture_rect_region(_chip, Rect2(point.round() - Vector2(8, 8), Vector2(16, 16)), Rect2(frame * 16, 0, 16, 16))
