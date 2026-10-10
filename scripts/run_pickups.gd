extends Node2D
## Run-only reroll chips. Contact uses actual floor and visible rig sweeps;
## the simulation clock freezes pickups during drafts, pause and hit stop.
signal reroll_collected(id: String)
const Seeds = preload("res://scripts/seed_utils.gd")
const Catalog = preload("res://scripts/parts.gd")
const MAX_PICKUPS: int = 2
const COLLECT_RADIUS: float = 18.0
const LIFETIME: float = 16.0
const EXPIRY_WARNING: float = 2.5
const SPRITE: String = "res://assets/powers/feedback_002c5_2/pickup.png"
const FLOOR_PIVOT: Vector2 = Vector2(12, 10)
const GROUND_CONTACT_HEIGHT: float = 3.0
const COLLECTION_SPRITE: String = "res://assets/powers/pickup_003a1/collection.png"
const COLLECTION_CELL: Vector2 = Vector2(40, 24)
const COLLECTION_PIVOT: Vector2 = Vector2(20, 12)
const COLLECTION_TIMINGS_MS: Array[int] = [30, 35, 45, 55, 65, 80]
const COLLECTION_LIFETIME: float = 0.31
var _battle: WeakRef
var _run: WeakRef
var items: Array[Dictionary] = []
var _receipts: Array[int] = []
var _sequence: int = 0
var _clock: float = 0.0
var _previous_position: Vector2 = Vector2.ZERO
var _previous_blade_origin: Vector2
var _previous_blade_bounds: Rect2
var _previous_height: float = 0.0
var _blade_bounds: Dictionary = {}
var _pickup_bounds: Rect2 = Rect2(Vector2(-9,-9),Vector2(19,15))
var _texture: Texture2D
var _collection_texture: Texture2D
var _collection_flairs: Array[Dictionary] = []
# The parent Battle paints the floor pass before complete rigs. A child canvas
# draws after its parent; that old ordering made a floor chip cover a top.
var render_in_battle: bool = false
var reduced_flashing: bool = false
var expired_count: int = 0
var capacity_suppressed_count: int = 0

func setup(battle: Node2D, run: RefCounted) -> void:
	clear()
	_battle = weakref(battle)
	_run = weakref(run)
	_clock = float(battle.elapsed)
	_previous_position = Vector2(battle.player_entity().get("pos", Vector2.ZERO))
	_sync_visible_pose(battle, battle.player_entity())
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(SPRITE):
		_texture = load(SPRITE)
		var opaque: Rect2i = _texture.get_image().get_used_rect()
		_pickup_bounds = Rect2(Vector2(opaque.position) - FLOOR_PIVOT,Vector2(opaque.size))
	if ResourceLoader.exists(COLLECTION_SPRITE): _collection_texture = load(COLLECTION_SPRITE)

func clear() -> void:
	items.clear()
	_collection_flairs.clear()
	_receipts.clear()
	_sequence = 0
	_clock = 0.0
	expired_count = 0
	capacity_suppressed_count = 0
	_blade_bounds.clear()
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
	# A capped wallet cannot accept a receipt. Do not present an impossible drop.
	if _wallet_full(run): return false
	_sequence += 1
	var points: Array[Vector2] = [Vector2(-65, 0), Vector2(65, 0), Vector2(0, 65), Vector2(0, -65), Vector2(95, -35), Vector2(-95, 35), Vector2(35, 95), Vector2(-35, -95)]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Seeds.derive(run.run_seed, "reroll_pickup/%d" % _sequence)
	var index: int = rng.randi_range(0, points.size() - 1)
	var player: Vector2 = Vector2(battle.player_entity().pos)
	for offset: int in range(points.size()):
		var point: Vector2 = points[(index + offset) % points.size()]
		if point.distance_to(player) < 30.0: continue
		if items.is_empty():
			_previous_position = player
			_sync_visible_pose(battle,battle.player_entity())
		items.append({"id":"reroll/%d/%d" % [run.run_seed, _sequence], "pos":point, "born":float(battle.elapsed)})
		queue_redraw()
		return true
	return false

func _process(_delta: float) -> void:
	# Battle observes every resolved fixed tick. This idempotent fallback serves
	# isolated scenes and presentation-only clocks, never the sole live sweep.
	update_simulation()

static func _wallet_full(run: RefCounted) -> bool:
	return int(run.reroll_charges) >= int(run.MAX_REROLLS)

func _visible_blade_bounds(player: Dictionary) -> Rect2:
	var path: String = Catalog.texture_path("blade",str(player.build.blade))
	var identity: String = str(player.get("starter_id","custom"))
	if identity in ["breaker","bastion","vane"]:
		path = "res://assets/top/starters/%s_spin.png" % identity
	if _blade_bounds.has(path): return _blade_bounds[path]
	var bounds: Rect2 = Rect2(Vector2(7,18),Vector2(35,20))
	if ResourceLoader.exists(path):
		var texture: Texture2D = load(path)
		var image: Image = texture.get_image()
		var first: bool = true
		# Union native spin cels once: collection reach does not flicker with
		# the rendered phase or miss a thin cel when frame rates are low.
		for frame: int in range(maxi(1,image.get_width()/48)):
			var used: Rect2i = image.get_region(Rect2i(frame*48,0,48,48)).get_used_rect()
			if not used.has_area(): continue
			var cell: Rect2 = Rect2(used)
			bounds = cell if first else bounds.merge(cell)
			first = false
	_blade_bounds[path] = bounds
	return bounds

func _sync_visible_pose(battle: Node2D, player: Dictionary) -> void:
	if player.is_empty(): return
	_previous_blade_origin = battle.full_top_render_pose(player).blade_origin
	_previous_blade_bounds = _visible_blade_bounds(player)
	_previous_height = float(player.get("height",0.0))

static func swept_visible_overlap(from_origin: Vector2, to_origin: Vector2, blade_bounds: Rect2, pickup_bounds: Rect2) -> bool:
	# Sweep two native opaque bounds in the SAME raster basis as Battle's
	# assembled blade. Correct the blade/floor pivot disagreement without
	# increasing the world radius, moving the chip or attracting it.
	var valid_origins: Rect2 = Rect2(pickup_bounds.position - blade_bounds.end,
		pickup_bounds.size + blade_bounds.size)
	var delta: Vector2 = to_origin - from_origin
	var enter: float = 0.0
	var leave: float = 1.0
	for axis: int in range(2):
		if absf(delta[axis]) < 0.000001:
			if from_origin[axis] < valid_origins.position[axis] or from_origin[axis] > valid_origins.end[axis]: return false
		else:
			var a: float = (valid_origins.position[axis]-from_origin[axis])/delta[axis]
			var b: float = (valid_origins.end[axis]-from_origin[axis])/delta[axis]
			enter = maxf(enter,minf(a,b));leave = minf(leave,maxf(a,b))
			if enter > leave: return false
	return true

func update_simulation() -> void:
	var battle: Node2D = _battle.get_ref() if _battle != null else null
	var run: RefCounted = _run.get_ref() if _run != null else null
	if battle == null or run == null: return
	var player: Dictionary = battle.player_entity()
	if not run.is_active() or battle.paused or battle.battle_status != "battle":
		# READY/pause never collect or age a chip. Sync geometry so repositioned
		# paused fixtures cannot invent a long sweep when live play resumes.
		if not player.is_empty():
			_previous_position = Vector2(player.pos)
			if not items.is_empty(): _sync_visible_pose(battle,player)
		return
	if player.is_empty() or not str(player.get("outcome", "")).is_empty(): return
	var now: float = float(battle.elapsed)
	if now <= _clock: return
	var position_world: Vector2 = Vector2(player.pos)
	if items.is_empty() and _collection_flairs.is_empty():
		_clock = now
		_previous_position = position_world
		_previous_height = float(player.get("height",0.0))
		return
	var blade_origin: Vector2 = battle.full_top_render_pose(player).blade_origin
	var blade_bounds: Rect2 = _visible_blade_bounds(player).merge(_previous_blade_bounds)
	var height: float = float(player.get("height",0.0))
	# Ordinary impact hops peak below three units. A genuinely airborne rig
	# cannot collect a floor chip just because perspective places it over one.
	var from_world: Vector2 = _previous_position if _previous_height <= GROUND_CONTACT_HEIGHT else position_world
	var from_blade: Vector2 = _previous_blade_origin if _previous_height <= GROUND_CONTACT_HEIGHT else blade_origin
	for index: int in range(_collection_flairs.size() - 1, -1, -1):
		if now - float(_collection_flairs[index].born) >= COLLECTION_LIFETIME:
			_collection_flairs.remove_at(index)
	for index: int in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[index]
		if _wallet_full(run):
			items.remove_at(index)
			capacity_suppressed_count += 1
			continue
		if now - float(item.born) >= LIFETIME:
			items.remove_at(index)
			expired_count += 1
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(item.pos), from_world, position_world)
		var visible_bounds: Rect2 = Rect2(battle.project(Vector2(item.pos)).round() + _pickup_bounds.position,_pickup_bounds.size)
		var contact: bool = height <= GROUND_CONTACT_HEIGHT and (closest.distance_to(Vector2(item.pos)) <= COLLECT_RADIUS or swept_visible_overlap(from_blade,blade_origin,blade_bounds,visible_bounds))
		if contact and run.collect_reroll_pickup(str(item.id)):
			items.remove_at(index)
			# Real contact pays once. The tiny authored response stays at the floor
			# pickup, never follows the rotor or attracts an uncollected chip.
			if _collection_flairs.size() >= MAX_PICKUPS: _collection_flairs.pop_front()
			_collection_flairs.append({"id":item.id,"pos":item.pos,"born":now})
			battle.event_sfx.emit("pickup_collect")
			reroll_collected.emit(str(item.id))
	_clock = now
	_previous_position = position_world
	_previous_blade_origin = blade_origin
	_previous_blade_bounds = _visible_blade_bounds(player)
	_previous_height = height
	# Reverse iteration can fill the wallet after another chip was visited.
	# Suppress the other chip in this tick, before a draft can freeze gameplay.
	if _wallet_full(run) and not items.is_empty():
		capacity_suppressed_count += items.size()
		items.clear()
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

static func collection_frame(age: float) -> int:
	if age < 0.0 or age >= COLLECTION_LIFETIME: return -1
	var end: float = 0.0
	for frame: int in range(COLLECTION_TIMINGS_MS.size()):
		end += float(COLLECTION_TIMINGS_MS[frame]) / 1000.0
		if age < end: return frame
	return -1

func presentation_snapshot() -> Dictionary:
	var presentation: Array[Dictionary] = []
	for item: Dictionary in items:
		var age: float = maxf(0.0, _clock - float(item.born))
		presentation.append({"id":item.id,"pos":item.pos,"age":age,"warning":age >= LIFETIME - EXPIRY_WARNING,"alpha":expiry_alpha(age,reduced_flashing)})
	var flairs: Array[Dictionary] = []
	for flair: Dictionary in _collection_flairs:
		var age: float = maxf(0.0, _clock - float(flair.born))
		flairs.append({"id":flair.id,"pos":flair.pos,"age":age,"frame":collection_frame(age)})
	return {"active":presentation,"maximum":MAX_PICKUPS,"lifetime":LIFETIME,"warning_seconds":EXPIRY_WARNING,"collect_radius":COLLECT_RADIUS,"expired":expired_count,"draw_before_rigs":render_in_battle,"collection_flairs":flairs,"collection_lifetime":COLLECTION_LIFETIME,"attraction":false,
		"visible_contact":"native blade cel envelope / shared Battle render pose / fixed-tick sweep","capacity_suppressed":capacity_suppressed_count}

func draw_floor(canvas: CanvasItem) -> void:
	var battle: Node2D = _battle.get_ref() if _battle != null else null
	if battle == null: return
	var run: RefCounted = _run.get_ref() if _run != null else null
	# Also keep frozen READY/pause rendering honest if a QA fixture fills the
	# wallet, without aging items or manufacturing a collection receipt.
	var show_items: bool = run != null and run.is_active() and not _wallet_full(run)
	for item: Dictionary in items:
		if not show_items: break
		var floor_position: Vector2 = battle.project(Vector2(item.pos)).round()
		var tint: Color = Color.WHITE
		tint.a = expiry_alpha(maxf(0.0,_clock - float(item.born)),reduced_flashing)
		# Native asset already includes contact shadow and its 12,10 floor pivot.
		# No hover offset, UI ring or world-height lift is added here.
		if _texture != null:
			canvas.draw_texture(_texture, floor_position - FLOOR_PIVOT, tint)
		else:
			canvas.draw_rect(Rect2(floor_position - Vector2(5, 4), Vector2(10, 6)), tint, false, 1.0)
	if _collection_texture == null: return
	for flair: Dictionary in _collection_flairs:
		var frame: int = collection_frame(maxf(0.0, _clock - float(flair.born)))
		if frame < 0: continue
		var floor_position: Vector2 = battle.project(Vector2(flair.pos)).round()
		canvas.draw_texture_rect_region(_collection_texture, Rect2(floor_position - COLLECTION_PIVOT, COLLECTION_CELL), Rect2(Vector2(float(frame) * COLLECTION_CELL.x, 0), COLLECTION_CELL))
