extends RefCounted
## Bounded cosmetic punctuation for exceptionally severe full-top collisions.
## This controller only reads its host/fighters. It never calls a gameplay
## hook, writes a fighter, or spends any random stream.

const MANIFEST_PATH: String = "res://assets/powers/beasts_002c5_2/manifest.json"
const ASSET_ROOT: String = "res://assets/powers/beasts_002c5_2/"
const MAX_LIVE: int = 1
const OWNER_COOLDOWN: float = 4.0
const GLOBAL_COOLDOWN: float = 1.6
const MAX_INSTANCE_SECONDS: float = 4.0
const MAX_HISTORY: int = 96
# Fixed production value is calibrated by the deterministic natural Run study.
# Canonical normal impulse × relative closing speed is an impact work proxy,
# not physical joules/dissipated energy. Natural Run study: 4,292 meaningful
# contacts, 32 exceptional qualifiers. No moving live percentile or build gate.
const EXTREME_IMPACT_SCORE: float = 1000000.0
const MOTION_PHASES: Array[String] = ["prepare", "travel", "strike", "recovery"]
const ORIENTATION_MIN_SPEED: float = 16.0
const ORIENTATION_ENTER: float = PI / 4.0
const ORIENTATION_EXIT: float = PI / 6.0
const ORIENTATION_CANDIDATE_CONE: float = PI / 9.0
const ORIENTATION_HOLD: float = 0.10
const ORIENTATION_SETTLE: float = 0.22
const ORIENTATION_FACING_DEADZONE: float = 0.24
const BLADE_BEASTS: Dictionary = {
	"smash": "black_arrow", "lopsider": "black_arrow", "fork": "black_arrow",
	"hammerfall": "iron_bull", "sawtooth": "iron_bull", "puck": "iron_bull",
	"guard": "stone_tortoise",
	"balance": "coil_dragon", "outrigger": "coil_dragon", "hook": "coil_dragon", "crescent": "coil_dragon"}
var _host_ref: WeakRef
var _enabled: bool = true
var _active: Array[Dictionary] = []
var _owner_ready: Dictionary = {}
var _seen_collisions: Dictionary = {}
var _latest_collision_id: int = 0
var _global_ready: float = 0.0
var _orientations: Dictionary = {}
var _metadata: Dictionary = {}
var _textures: Dictionary = {}
var _assets_loaded: bool = false
var _clock: float = 0.0
var _sequence: int = 0
var _spawned: int = 0
var _suppressed: int = 0
var _peak_live: int = 0
var _qualified: int = 0
var _contacts: int = 0
var _duplicates: int = 0
var _events: Array[Dictionary] = []

static func beast_for_blade(blade: String) -> String:
	return str(BLADE_BEASTS.get(blade, ""))

static func display_name_for_blade(blade: String) -> String:
	return str({"black_arrow": "Black Arrow", "iron_bull": "Iron Bull", "stone_tortoise": "Stone Tortoise", "coil_dragon": "Coil Dragon"}.get(beast_for_blade(blade), ""))

func setup(battle: Object) -> void:
	_host_ref = weakref(battle)
	reset()
	_load_assets()

func reset() -> void:
	_active.clear()
	_owner_ready.clear()
	_seen_collisions.clear()
	_latest_collision_id = 0
	_global_ready = 0.0
	_orientations.clear()
	_events.clear()
	_clock = 0.0
	_sequence = 0
	_spawned = 0
	_suppressed = 0
	_peak_live = 0
	_qualified = 0
	_contacts = 0
	_duplicates = 0

func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_active.clear()
		_orientations.clear()

func finish() -> void:
	for item: Dictionary in _active: _record("expired", item, "battle_end")
	_active.clear()
	_orientations.clear()

func _host() -> Object:
	return _host_ref.get_ref() if _host_ref != null else null

func _live_owner(owner: Dictionary) -> bool:
	return not owner.is_empty() and str(owner.get("outcome", "")).is_empty() and str(owner.get("combatant_type", "")) == "full_top"

static func _facing(direction: Vector2, previous: bool) -> bool:
	# Isometric screen heading, independent of the authored frame's floor pivot.
	var screen: Vector2 = Vector2(direction.x - direction.y, (direction.x + direction.y) * 0.5).normalized()
	if absf(screen.x) < ORIENTATION_FACING_DEADZONE: return previous
	return screen.x < 0.0

static func orientation_state(direction: Vector2) -> Dictionary:
	var stable: Vector2 = direction.normalized() if direction.is_finite() and direction.length_squared() > 0.000001 else Vector2.RIGHT
	return {"direction": stable, "mirror": _facing(stable, false), "candidate": Vector2.ZERO,
		"candidate_seconds": 0.0, "settle_remaining": 0.0, "responses": 0}

## One bounded facing response to a sustained turn. This only transforms the
## complete native frame by its existing mirror path; it never retimes frames,
## tracks every heading, rotates pixels or changes any simulated owner state.
static func orientation_step(previous: Dictionary, velocity: Vector2, dt: float) -> Dictionary:
	var state: Dictionary = previous.duplicate(true)
	if state.is_empty(): state = orientation_state(velocity)
	if not is_finite(dt) or dt <= 0.0: return state
	state.settle_remaining = maxf(0.0, float(state.settle_remaining) - dt)
	if not velocity.is_finite() or velocity.length_squared() < ORIENTATION_MIN_SPEED * ORIENTATION_MIN_SPEED:
		state.candidate = Vector2.ZERO
		state.candidate_seconds = 0.0
		return state
	var heading: Vector2 = velocity.normalized()
	# Do not absorb a gradual turn at the projected vertical seam. Retaining the
	# last meaningful heading here lets the later clear left/right travel earn
	# its response, rather than silently consuming the threshold inside deadzone.
	var screen: Vector2 = Vector2(heading.x - heading.y, (heading.x + heading.y) * 0.5).normalized()
	if absf(screen.x) < ORIENTATION_FACING_DEADZONE:
		state.candidate = Vector2.ZERO
		state.candidate_seconds = 0.0
		return state
	var angle: float = absf(Vector2(state.direction).angle_to(heading))
	if angle <= ORIENTATION_EXIT:
		state.candidate = Vector2.ZERO
		state.candidate_seconds = 0.0
		return state
	# Once a turn enters at 45 degrees, the 30-degree exit threshold keeps its
	# candidate alive through small corrections around the entry boundary.
	if angle < ORIENTATION_ENTER and Vector2(state.candidate) == Vector2.ZERO: return state
	if float(state.settle_remaining) > 0.0: return state
	var candidate: Vector2 = state.candidate
	if candidate == Vector2.ZERO or absf(candidate.angle_to(heading)) > ORIENTATION_CANDIDATE_CONE:
		state.candidate = heading
		state.candidate_seconds = 0.0
	state.candidate_seconds = float(state.candidate_seconds) + dt
	if float(state.candidate_seconds) + 0.000001 >= ORIENTATION_HOLD:
		state.direction = Vector2(state.candidate)
		state.mirror = _facing(Vector2(state.direction), bool(state.mirror))
		state.candidate = Vector2.ZERO
		state.candidate_seconds = 0.0
		state.settle_remaining = ORIENTATION_SETTLE
		state.responses = int(state.responses) + 1
	return state

func _owner_orientation(owner: Dictionary, initial_direction: Vector2) -> Dictionary:
	var id: int = int(owner.entity_id)
	if not _orientations.has(id): _orientations[id] = orientation_state(initial_direction)
	return _orientations[id]

func _observe_orientations(dt: float) -> void:
	var host: Object = _host()
	for id: int in _orientations.keys():
		var owner: Dictionary = host.entity(id)
		if not _live_owner(owner):
			_orientations.erase(id)
			continue
		_orientations[id] = orientation_step(_orientations[id], Vector2(owner.vel), dt)
	for item: Dictionary in _active:
		var owner: Dictionary = host.entity(int(item.owner_entity_id))
		if not _live_owner(owner): continue
		var state: Dictionary = _owner_orientation(owner, Vector2(item.direction))
		if int(state.responses) > int(item.get("orientation_responses", 0)):
			_record("direction_pending" if _unsafe_turn(item) else "direction_response", item, "sustained_turn")
		item.pending_direction = Vector2(state.direction)
		item.pending_mirror = bool(state.mirror)
		item.orientation_responses = int(state.responses)
		item.orientation_settle = float(state.settle_remaining)
		_apply_pending_facing(item)

func _unsafe_turn(item: Dictionary) -> bool:
	# Black Arrow's complete rotating travel sequence stays on one root facing.
	# The first strike key is the safe horizontal opening after the somersault.
	return str(item.beast) == "black_arrow" and str(item.phase) == "travel"

func _apply_pending_facing(item: Dictionary) -> void:
	if _unsafe_turn(item): return
	var changed: bool = bool(item.orientation_mirror) != bool(item.pending_mirror)
	item.direction = Vector2(item.pending_direction)
	item.orientation_mirror = bool(item.pending_mirror)
	if changed: _record("facing_applied", item, "safe_authored_key")

func _load_assets() -> void:
	if _assets_loaded or not FileAccess.file_exists(MANIFEST_PATH): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary: return
	_metadata = parsed.get("effects", {})
	if not _metadata is Dictionary: _metadata = {}
	for beast: String in _metadata:
		var path: String = str(_metadata[beast].get("texture", ""))
		if not path.begins_with("res://"): path = ASSET_ROOT + path
		if ResourceLoader.exists(path):
			var resource: Resource = load(path)
			if resource is Texture2D: _textures[beast] = resource
	_assets_loaded = true

func _tag_seconds(beast: String, phase: String, fallback: float = 0.28) -> float:
	var meta: Dictionary = _metadata.get(beast, {})
	var tags: Dictionary = meta.get("tags", {})
	if not tags.has(phase): return fallback
	var durations: Array = meta.get("durations_ms", [])
	var total: float = 0.0
	for index: int in range(int(tags[phase].get("from", 0)), int(tags[phase].get("to", 0)) + 1):
		if index >= 0 and index < durations.size(): total += maxf(1.0, float(durations[index])) / 1000.0
	return maxf(total, 0.001) if total > 0.0 else fallback

## Atlas timing remains authored milliseconds, including unequal durations.
func frame_for(beast: String, phase: String, age: float, loop: bool = false) -> int:
	_load_assets()
	var meta: Dictionary = _metadata.get(beast, {})
	var tags: Dictionary = meta.get("tags", {})
	if not tags.has(phase): return 0
	var first: int = int(tags[phase].get("from", 0))
	var last: int = int(tags[phase].get("to", first))
	var durations: Array = meta.get("durations_ms", [])
	var remaining: float = maxf(0.0, age)
	if loop: remaining = fmod(remaining, _tag_seconds(beast, phase))
	for index: int in range(first, last + 1):
		if index >= durations.size(): return first
		remaining -= maxf(1.0, float(durations[index])) / 1000.0
		if remaining < 0.0: return index
	return last

func _record(kind: String, item: Dictionary = {}, reason: String = "") -> void:
	var event: Dictionary = {"kind": kind, "time": _clock, "reason": reason}
	for key: String in ["instance_id", "collision_id", "owner_entity_id", "beast", "trigger", "phase", "impact", "impulse", "closing", "impact_score"]:
		if item.has(key): event[key] = item[key]
	_events.append(event)
	if _events.size() > MAX_HISTORY: _events.pop_front()

func _suppress(reason: String, event: Dictionary = {}) -> void:
	_suppressed += 1
	_record("suppressed", event, reason)

## The already computed normal solver impulse incorporates both effective
## masses/component modifiers. Multiplying by genuine closing speed distinguishes
## violent motion from huge effective mass merely pressing slowly at contact.
## No power state, build label or rolling sample participates in qualification.
static func impact_metric(event: Dictionary) -> float:
	return float(event.get("impulse", 0.0)) * float(event.get("closing", 0.0))

static func qualifies_impact(event: Dictionary) -> bool:
	var score: float = impact_metric(event)
	var impulse: float = float(event.get("impulse", 0.0))
	var closing: float = float(event.get("closing", 0.0))
	return is_finite(score) and is_finite(impulse) and is_finite(closing) and impulse > 0.0 and closing > 0.0 and score >= EXTREME_IMPACT_SCORE

func _presentation_owner(event: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	# The local player's huge received force is equally valid as delivered force.
	# Otherwise use incoming normal momentum; an exact tie uses stable entity ID.
	var player_id: int = int(_host().player_entity_id)
	if int(first.entity_id) == player_id: return first
	if int(second.entity_id) == player_id: return second
	var first_momentum: float = float(event.get("first_normal_speed", 0.0)) * float(event.get("first_effective_mass", 0.0))
	var second_momentum: float = float(event.get("second_normal_speed", 0.0)) * float(event.get("second_effective_mass", 0.0))
	if not is_equal_approx(first_momentum, second_momentum): return first if first_momentum > second_momentum else second
	return first if int(first.entity_id) < int(second.entity_id) else second

## The canonical full-top solver supplies one monotonic event identity after
## accepting a real contact. Suppressed events are consumed too, so replaying
## that identity after a cooldown can never allocate another giant silhouette.
func accept_impact(event: Dictionary) -> bool:
	var host: Object = _host()
	if not _enabled or host == null or bool(host.paused) or str(host.battle_status) != "battle": return false
	var collision_id: int = int(event.get("collision_id", 0))
	var first: Dictionary = host.entity(int(event.get("first_entity_id", 0)))
	var second: Dictionary = host.entity(int(event.get("second_entity_id", 0)))
	var normal: Vector2 = Vector2(event.get("normal", Vector2.ZERO))
	var position: Vector2 = Vector2(event.get("position", Vector2.ZERO))
	if collision_id <= 0 or not _live_owner(first) or not _live_owner(second) or int(first.entity_id) == int(second.entity_id): return false
	if not normal.is_finite() or normal.length_squared() < 0.000001 or not position.is_finite(): return false
	if collision_id <= _latest_collision_id:
		_duplicates += 1
		_record("duplicate", event, "collision_already_consumed")
		return false
	_latest_collision_id = collision_id
	_seen_collisions[collision_id] = true
	if _seen_collisions.size() > MAX_HISTORY: _seen_collisions.erase(_seen_collisions.keys()[0])
	_contacts += 1
	if not qualifies_impact(event): return false
	_qualified += 1
	var owner: Dictionary = _presentation_owner(event, first, second)
	var owner_id: int = int(owner.entity_id)
	if _active.size() >= MAX_LIVE:
		_suppress("live_budget", event)
		return false
	if _clock < float(_owner_ready.get(owner_id, 0.0)):
		_suppress("owner_cooldown", event)
		return false
	if _clock < _global_ready:
		_suppress("global_cooldown", event)
		return false
	var beast: String = beast_for_blade(str(owner.get("build", {}).get("blade", "")))
	if beast.is_empty(): return false
	_load_assets()
	var velocity: Vector2 = Vector2(event.get("first_velocity" if owner_id == int(first.entity_id) else "second_velocity", owner.vel))
	var direction: Vector2 = velocity.normalized() if velocity.is_finite() and velocity.length_squared() >= ORIENTATION_MIN_SPEED * ORIENTATION_MIN_SPEED else (normal if owner_id == int(first.entity_id) else -normal)
	# Each new authored performance starts with this collision's facing; previous
	# performances cannot drag a stale root candidate into the new timeline.
	_orientations[owner_id] = orientation_state(direction)
	var orientation: Dictionary = _orientations[owner_id]
	_sequence += 1
	var item: Dictionary = {"instance_id": _sequence, "collision_id": collision_id, "beast": beast, "owner_entity_id": owner_id,
		"trigger": "extreme_impact", "phase": "prepare", "phase_age": 0.0, "phase_duration": _tag_seconds(beast, "prepare"),
		"age": 0.0, "world_pos": Vector2(owner.pos), "impact_pos": position, "direction": direction,
		"impulse": float(event.impulse), "closing": float(event.closing), "impact_score": impact_metric(event),
		"strength": clampf(impact_metric(event) / EXTREME_IMPACT_SCORE, 1.0, 3.0), "rank": 1,
		"player": owner_id == int(host.player_entity_id), "impact": true, "follow_owner": true,
		"orientation_mirror": bool(orientation.mirror), "orientation_responses": 0, "orientation_settle": 0.0,
		"pending_direction": direction, "pending_mirror": bool(orientation.mirror)}
	_active.append(item)
	_owner_ready[owner_id] = _clock + OWNER_COOLDOWN
	_global_ready = _clock + GLOBAL_COOLDOWN
	_spawned += 1
	_peak_live = maxi(_peak_live, _active.size())
	_record("spawned", item)
	return true

## Existing power-specific small VFX retain their ordinary Battle path. Semantic
## charge, maturity, activation, impact and recovery hooks never summon a beast.
func accept_event(_kind: String, _pos: Vector2, _direction: Vector2, _strength: float, _provenance: Dictionary) -> void:
	pass

func _phase(item: Dictionary, phase: String) -> void:
	item.phase = phase
	item.phase_duration = _tag_seconds(str(item.beast), phase)
	# This brief automatic reaction stays attached to its real spinning top. The
	# old collision point is provenance/ordinary contact VFX, never a delayed
	# authored strike jumping back to an empty piece of arena.
	item.follow_owner = true
	_apply_pending_facing(item)
	_record("phase", item)

func update(dt: float) -> void:
	var host: Object = _host()
	if not _enabled or host == null or bool(host.paused) or not is_finite(dt) or dt <= 0.0: return
	# Pause/draft and countdown/re-entry suspend the performance intact. A real
	# terminal battle result removes it; beginning a new battle calls reset().
	if str(host.battle_status) == "finished":
		finish()
		return
	if str(host.battle_status) != "battle": return
	_clock += dt
	_observe_orientations(dt)
	for index: int in range(_active.size() - 1, -1, -1):
		var item: Dictionary = _active[index]
		var owner: Dictionary = host.entity(int(item.owner_entity_id))
		if not _live_owner(owner):
			_record("expired", item, "owner_retired")
			_active.remove_at(index)
			continue
		item.age = float(item.age) + dt
		item.phase_age = float(item.phase_age) + dt
		if bool(item.follow_owner): item.world_pos = Vector2(owner.pos)
		# Always consume authored phase duration, retaining excess delta. A coarse
		# frame may cross several keys/phases; it cannot hold an intermediate pose
		# or reset the clock. All four phases belong to one collision instance.
		var resolved: bool = false
		for transition: int in range(MOTION_PHASES.size()):
			if float(item.phase_age) + 0.000000001 < float(item.phase_duration): break
			item.phase_age = maxf(0.0, float(item.phase_age) - float(item.phase_duration))
			var next_index: int = MOTION_PHASES.find(str(item.phase)) + 1
			if next_index >= MOTION_PHASES.size():
				_record("expired", item, "resolved")
				_active.remove_at(index)
				resolved = true
				break
			_phase(item, MOTION_PHASES[next_index])
		if not resolved and float(item.age) >= MAX_INSTANCE_SECONDS:
			_record("expired", item, "lifetime_budget")
			_active.remove_at(index)
	# Presentation owner IDs remain bounded by current live performers/cooldowns.
	for id: int in _orientations.keys():
		var retained: bool = false
		for item: Dictionary in _active:
			if int(item.owner_entity_id) == id: retained = true; break
		if not retained: _orientations.erase(id)
	for id: int in _owner_ready.keys():
		if _clock >= float(_owner_ready[id]) or not _live_owner(host.entity(id)): _owner_ready.erase(id)

## Read-only geometry shared by rendering and attachment diagnostics. Godot
## flips a negative destination width inside the same positive-area footprint;
## it does not translate the rectangle's origin by the signed width.
func draw_geometry_for(item: Dictionary) -> Dictionary:
	_load_assets()
	var host: Object = _host()
	if host == null: return {}
	var meta: Dictionary = _metadata.get(str(item.get("beast", "")), {})
	var owner: Dictionary = host.entity(int(item.get("owner_entity_id", 0)))
	if meta.is_empty() or not _live_owner(owner): return {}
	var size: Vector2 = Vector2(float(meta.cell[0]), float(meta.cell[1]))
	var pivot: Vector2 = Vector2(float(meta.pivot[0]), float(meta.pivot[1]))
	var height: float = float(owner.get("height", 0.0)) if bool(item.follow_owner) else 0.0
	var world_pos: Vector2 = Vector2(owner.pos) if bool(item.follow_owner) else Vector2(item.world_pos)
	var point: Vector2 = host.project(world_pos, height)
	var owner_point: Vector2 = host.project(Vector2(owner.pos), float(owner.get("height", 0.0)))
	var lift: float = 0.0
	if str(item.phase) == "prepare": lift = 12.0 * clampf(float(item.phase_age) / maxf(0.001, float(item.phase_duration)), 0.0, 1.0)
	elif str(item.phase) == "travel": lift = 12.0
	var direction: Vector2 = Vector2(item.direction)
	var mirror: bool = bool(item.get("orientation_mirror", direction.x - direction.y < -0.001))
	var mirrored_pivot: Vector2 = Vector2(size.x - pivot.x, pivot.y) if mirror else pivot
	var anchor: Vector2 = point - Vector2(0.0, lift)
	var rect: Rect2 = Rect2((anchor - mirrored_pivot).round(), Vector2(-size.x if mirror else size.x, size.y))
	return {"rect": rect, "projected_owner_point": owner_point, "projected_point": point,
		"anchor": anchor, "lift": lift, "mirror": mirror, "pivot": pivot, "size": size}

## This pass is called before every opaque top body. Native 128 px cells use
## only translation/mirroring, so rank strengthens alpha rather than size/count.
func draw(canvas: CanvasItem) -> void:
	if not _enabled or _host() == null: return
	_load_assets()
	for item: Dictionary in _active:
		var texture: Texture2D = _textures.get(str(item.beast))
		var meta: Dictionary = _metadata.get(str(item.beast), {})
		if texture == null or meta.is_empty(): continue
		var geometry: Dictionary = draw_geometry_for(item)
		if geometry.is_empty(): continue
		var phase: String = str(item.phase)
		var phase_age: float = float(item.phase_age)
		var frame: int = frame_for(str(item.beast), phase, phase_age)
		var size: Vector2 = geometry.size
		var columns: int = maxi(1, int(meta.columns))
		var source: Rect2 = Rect2(Vector2(float(frame % columns) * size.x, floorf(float(frame) / float(columns)) * size.y), size)
		# Only the spectral figure rises. The real rig, contact plane and height
		# remain exactly as simulated during Comet/Breakneck preparation.
		var alpha: float = (0.60 if bool(item.player) else 0.40) + minf(0.04, float(item.strength) * 0.015)
		if phase == "prepare": alpha *= lerpf(0.30, 1.0, clampf(phase_age / maxf(0.001, float(item.phase_duration)), 0.0, 1.0))
		if phase == "recovery": alpha *= clampf(1.0 - phase_age / maxf(0.001, float(item.phase_duration)), 0.0, 1.0)
		canvas.draw_texture_rect_region(texture, geometry.rect, source, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 0.78)))

## Separate diagnostics never enter the combat snapshot or its replay contract.
func snapshot() -> Dictionary:
	var active: Array[Dictionary] = _active.duplicate(true)
	for item: Dictionary in active:
		if bool(item.follow_owner) and _host() != null:
			var owner: Dictionary = _host().entity(int(item.owner_entity_id))
			if not owner.is_empty(): item.world_pos = Vector2(owner.pos)
	return {"enabled": _enabled, "count": _active.size(), "max_live": MAX_LIVE, "peak_live": _peak_live,
		"spawned": _spawned, "suppressed": _suppressed, "cooldown_seconds": OWNER_COOLDOWN,
		"global_cooldown_seconds": GLOBAL_COOLDOWN, "extreme_threshold": EXTREME_IMPACT_SCORE, "impact_metric": "canonical_normal_impulse_times_closing_speed",
		"accepted_full_top_contacts": _contacts, "qualified": _qualified, "duplicates": _duplicates, "dedup_entries": _seen_collisions.size(),
		"max_instance_seconds": MAX_INSTANCE_SECONDS, "active": active, "events": _events.duplicate(true), "orientations": _orientations.duplicate(true)}
