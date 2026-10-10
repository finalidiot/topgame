extends Node2D
## Finger ownership is independent of mouse emulation and of menu confirmation.
const FrontEnd = preload("res://scripts/front_end.gd")
const CombatLayout = preload("res://scripts/combat_hud_layout.gd")
const BURST_RECT = Rect2(724, 294, 70, 52)
const BRAKE_RECT = Rect2(724, 354, 70, 52)
const MAX_RADIUS: float = 52.0
const DEADZONE: float = 8.0
var enabled: bool = false
var show_controls: bool = OS.has_feature("mobile")
var steering_finger: int = -1
var origin: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
var owners: Dictionary = {}
var blocked: Dictionary = {}
var _was_burst: bool = false
var _layout: Dictionary = {"canvas_size":Vector2(800,480), "safe_rect":CombatLayout.VIEW,
	"arena_rect":CombatLayout.PLAY_REGION, "steering_rect":CombatLayout.PLAY_REGION,
	"burst_rect":BURST_RECT, "brake_rect":BRAKE_RECT}

func configure_layout(layout: Dictionary) -> Dictionary:
	# Rotation or a changed cutout must never retarget a still-held contact.
	# Repeated identical layout publication leaves prepared steering intact.
	var canvas: Vector2 = layout.get("canvas_size",CombatLayout.VIEW.size)
	var safe: Rect2 = layout.get("safe_rect",Rect2(Vector2.ZERO,canvas))
	var arena: Rect2 = layout.get("arena_rect",CombatLayout.PLAY_REGION)
	var actions_y: float = minf(arena.position.y+234.0,safe.end.y-126.0)
	var next: Dictionary = {"canvas_size":canvas,"safe_rect":safe,"arena_rect":arena,
		"burst_rect":layout.get("burst_rect",Rect2(safe.end.x-76.0,actions_y,70,52)),
		"brake_rect":layout.get("brake_rect",Rect2(safe.end.x-76.0,actions_y+60.0,70,52))}
	next["steering_rect"] = layout.get("steering_rect",Rect2(next.arena_rect).intersection(Rect2(next.safe_rect)))
	if next != _layout:
		clear()
		_layout = next
	queue_redraw()
	return layout_snapshot()

func layout_snapshot() -> Dictionary:
	return _layout.duplicate(true)

func set_enabled(value: bool) -> void:
	if enabled and not value: clear()
	enabled = value
	queue_redraw()

func clear() -> void:
	for finger: int in owners: blocked[finger] = true
	owners.clear()
	steering_finger = -1
	direction = Vector2.ZERO
	_was_burst = false
	queue_redraw()

func reset_actions() -> void:
	for finger: int in owners.keys():
		if owners[finger] != "steer":
			blocked[finger] = true
			owners.erase(finger)
	_was_burst = false
	queue_redraw()

func action_down(action: String) -> bool:
	return action in owners.values()

func sample() -> Dictionary:
	return {"direction": direction if steering_finger >= 0 else Input.get_vector("move_left", "move_right", "move_up", "move_down"),
		"burst": action_down("burst") or Input.is_action_pressed("burst"),
		"brake": action_down("brake") or Input.is_action_pressed("brake")}

static func valid_gameplay_point(point: Vector2, layout: Dictionary = {}) -> bool:
	# HUD, margins and the opposite-thumb actions never acquire a steering finger.
	var play: Rect2 = layout.get("steering_rect",layout.get("arena_rect",CombatLayout.PLAY_REGION))
	var safe: Rect2 = layout.get("safe_rect",Rect2(Vector2.ZERO,layout.get("canvas_size",CombatLayout.VIEW.size)))
	var burst: Rect2 = layout.get("burst_rect",BURST_RECT)
	var brake: Rect2 = layout.get("brake_rect",BRAKE_RECT)
	return safe.has_point(point) and play.has_point(point) and not burst.has_point(point) and not brake.has_point(point)

func handle_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var finger: int = event.index
		if not event.pressed or event.canceled:
			blocked.erase(finger)
			var owned: bool = owners.has(finger)
			owners.erase(finger)
			if steering_finger == finger:
				steering_finger = -1
				direction = Vector2.ZERO
			queue_redraw()
			return owned
		if not enabled or blocked.has(finger) or owners.has(finger): return false
		show_controls = true
		if not Rect2(_layout.safe_rect).has_point(event.position): return false
		if Rect2(_layout.burst_rect).has_point(event.position): owners[finger] = "burst"
		elif Rect2(_layout.brake_rect).has_point(event.position): owners[finger] = "brake"
		elif steering_finger < 0 and valid_gameplay_point(event.position,_layout):
			steering_finger = finger
			origin = event.position
			direction = Vector2.ZERO
			owners[finger] = "steer"
		else: return false
		queue_redraw()
		return true
	if event is InputEventScreenDrag and enabled and owners.has(event.index):
		if event.index == steering_finger:
			var offset: Vector2 = event.position - origin
			var magnitude: float = clampf((offset.length() - DEADZONE) / (MAX_RADIUS - DEADZONE), 0.0, 1.0)
			direction = offset.normalized() * magnitude
		return true
	return false

func _input(event: InputEvent) -> void:
	if handle_touch(event): get_viewport().set_input_as_handled()

func _draw() -> void:
	if not enabled or not show_controls: return
	var font: Font = FrontEnd.pixel_font()
	for item: Array in [["burst", _layout.burst_rect], ["brake", _layout.brake_rect]]:
		var rect: Rect2 = item[1]
		draw_style_box(FrontEnd.authored_style("button_caps", "PRESSED" if action_down(item[0]) else "NORMAL"), rect)
		if font != null:
			draw_string(font, rect.position + Vector2(10, 30), str(item[0]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20, 10, FrontEnd.TEXT)
