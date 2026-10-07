extends Node2D
## Run-only reroll chips. Floor contact uses actual swept player movement;
## the simulation clock freezes pickups during drafts, pause and hit stop.
signal reroll_collected(id: String)
const Seeds = preload("res://scripts/seed_utils.gd")
const MAX_PICKUPS: int = 2
const COLLECT_RADIUS: float = 14.0
const LIFETIME: float = 16.0
const EXPIRY_WARNING: float = 2.5
const SPRITE: String = "res://assets/powers/feedback_002c5_2/pickup.png"
var _battle: WeakRef
var _run: WeakRef
var items: Array[Dictionary] = []
var _receipts: Array[int] = []
var _sequence: int = 0
var _clock: float = 0.0
var _previous_position: Vector2 = Vector2.ZERO
var _texture: Texture2D
# The parent Battle paints the floor pass before complete rigs. A child canvas
# draws after its parent; that old ordering made a floor chip cover a top.
var render_in_battle: bool = false
var reduced_flashing: bool = false
var expired_count: int = 0

func setup(battle: Node2D, run: RefCounted) -> void:
	clear()
	_battle = weakref(battle)
	_run = weakref(run)
	_clock = float(battle.elapsed)
	_previous_position = Vector2(battle.player_entity().get("pos", Vector2.ZERO))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(SPRITE): _texture = load(SPRITE)

func clear() -> void:
	items.clear()
	_receipts.clear()
	_sequence = 0
	_clock = 0.0
	expired_count = 0
	_battle = null
	_run = null
	queue_redraw()

func notify_clear(summary: Dictionary) -> bool:
	var battle: Node2D = _battle.get_ref() if _battle != null else null
	var run: RefCounted = _run.get_ref() if _run != null else null
	if battle == null or run == null or not run.is_active() or battle.continuous == null: return false
	if summary != battle.continuous.last_clear or int(summary.get("run_seed", -1)) != run.run_seed: return false
	var serial: int = int(summary.get("threat", 0))
	if serial <= 0 or serial in _receipts: return false
	_receipts.append(serial)
	if _receipts.size() > 128: _receipts.pop_front()
	var clears: int = int(battle.continuous.threats_cleared)
	if (clears - 1) % 3 != 0 and str(summary.get("kind", "")) != "boss": return false
	if items.size() >= MAX_PICKUPS: return false
	_sequence += 1
	var points: Array[Vector2] = [Vector2(-65, 0), Vector2(65, 0), Vector2(0, 65), Vector2(0, -65), Vector2(95, -35), Vector2(-95, 35), Vector2(35, 95), Vector2(-35, -95)]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Seeds.derive(run.run_seed, "reroll_pickup/%d" % _sequence)
	var index: int = rng.randi_range(0, points.size() - 1)
	var player: Vector2 = Vector2(battle.player_entity().pos)
	for offset: int in range(points.size()):
		var point: Vector2 = points[(index + offset) % points.size()]
		if point.distance_to(player) < 30.0: continue
		items.append({"id":"reroll/%d/%d" % [run.run_seed, _sequence], "pos":point, "born":float(battle.elapsed)})
		queue_redraw()
		return true
	return false

func _process(_delta: float) -> void:
	update_simulation()

func update_simulation() -> void:
	var battle: Node2D = _battle.get_ref() if _battle != null else null
	var run: RefCounted = _run.get_ref() if _run != null else null
	if battle == null or run == null or not run.is_active() or battle.paused or battle.battle_status != "battle": return
	var player: Dictionary = battle.player_entity()
	if player.is_empty() or not str(player.get("outcome", "")).is_empty(): return
	var now: float = float(battle.elapsed)
	if now <= _clock: return
	var position_world: Vector2 = Vector2(player.pos)
	for index: int in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[index]
		if now - float(item.born) >= LIFETIME:
			items.remove_at(index)
			expired_count += 1
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(item.pos), _previous_position, position_world)
		if closest.distance_to(Vector2(item.pos)) <= COLLECT_RADIUS and run.collect_reroll_pickup(str(item.id)):
			items.remove_at(index)
			battle.event_sfx.emit("card_select")
			reroll_collected.emit(str(item.id))
	_clock = now
	_previous_position = position_world
	queue_redraw()

func _draw() -> void:
	if not render_in_battle: draw_floor(self)

static func expiry_alpha(age: float, reduce_flashing: bool = false) -> float:
	if age >= LIFETIME: return 0.0
	if age < LIFETIME - EXPIRY_WARNING: return 1.0
	var remaining: float = clampf((LIFETIME - age) / EXPIRY_WARNING, 0.0, 1.0)
	# One soft pulse per second, local to this tiny floor token. Accessible mode
	# uses a continuous fade and preserves the full readable warning interval.
	return lerpf(0.35, 0.86, remaining) if reduce_flashing else lerpf(0.42, 0.96, 0.5 + 0.5 * cos(age * TAU))

func presentation_snapshot() -> Dictionary:
	var presentation: Array[Dictionary] = []
	for item: Dictionary in items:
		var age: float = maxf(0.0, _clock - float(item.born))
		presentation.append({"id":item.id,"pos":item.pos,"age":age,"warning":age >= LIFETIME - EXPIRY_WARNING,"alpha":expiry_alpha(age,reduced_flashing)})
	return {"active":presentation,"maximum":MAX_PICKUPS,"lifetime":LIFETIME,"warning_seconds":EXPIRY_WARNING,"collect_radius":COLLECT_RADIUS,"expired":expired_count,"draw_before_rigs":render_in_battle}

func draw_floor(canvas: CanvasItem) -> void:
	var battle: Node2D = _battle.get_ref() if _battle != null else null
	if battle == null: return
	for item: Dictionary in items:
		var floor_position: Vector2 = battle.project(Vector2(item.pos)).round()
		var tint: Color = Color.WHITE
		tint.a = expiry_alpha(maxf(0.0,_clock - float(item.born)),reduced_flashing)
		# Native asset already includes contact shadow and its 12,10 floor pivot.
		# No hover offset, UI ring or world-height lift is added here.
		if _texture != null:
			canvas.draw_texture(_texture, floor_position - Vector2(12, 10), tint)
		else:
			canvas.draw_rect(Rect2(floor_position - Vector2(5, 4), Vector2(10, 6)), tint, false, 1.0)
