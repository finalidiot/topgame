extends RefCounted
## Bounded, cosmetic manifestations driven by explicit, real power events.
## This controller only reads its host/fighters. It never calls a gameplay
## hook, writes a fighter, or spends any random stream.

const MANIFEST_PATH: String = "res://assets/powers/beasts_002c5_2/manifest.json"
const ASSET_ROOT: String = "res://assets/powers/beasts_002c5_2/"
const MAX_LIVE: int = 3
const OWNER_COOLDOWN: float = 4.0
const MAX_INSTANCE_SECONDS: float = 4.0
const MAX_HISTORY: int = 96
const BLADE_BEASTS: Dictionary = {
	"smash": "black_arrow", "lopsider": "black_arrow", "fork": "black_arrow",
	"hammerfall": "iron_bull", "sawtooth": "iron_bull", "puck": "iron_bull",
	"guard": "stone_tortoise",
	"balance": "coil_dragon", "outrigger": "coil_dragon", "hook": "coil_dragon", "crescent": "coil_dragon"}
const EVENT_POWERS: Dictionary = {
	"comet_charge": "iron_comet", "comet_release": "iron_comet",
	"breakneck_charge": "redline", "breakneck_impact": "redline", "breakneck_recovery": "redline",
	"impact_wake": "impact_wake", "anchor_mature": "dead_centre"}

var _host_ref: WeakRef
var _enabled: bool = true
var _active: Array[Dictionary] = []
var _owner_ready: Dictionary = {}
var _guard_seen: Dictionary = {}
var _metadata: Dictionary = {}
var _textures: Dictionary = {}
var _assets_loaded: bool = false
var _clock: float = 0.0
var _sequence: int = 0
var _spawned: int = 0
var _suppressed: int = 0
var _peak_live: int = 0
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
	_guard_seen.clear()
	_events.clear()
	_clock = 0.0
	_sequence = 0
	_spawned = 0
	_suppressed = 0
	_peak_live = 0

func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_active.clear()

func finish() -> void:
	for item: Dictionary in _active: _record("expired", item, "battle_end")
	_active.clear()

func _host() -> Object:
	return _host_ref.get_ref() if _host_ref != null else null

func _live_owner(owner: Dictionary) -> bool:
	return not owner.is_empty() and str(owner.get("outcome", "")).is_empty() and str(owner.get("combatant_type", "")) == "full_top"

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
	for key: String in ["instance_id", "owner_entity_id", "beast", "trigger", "phase", "impact"]:
		if item.has(key): event[key] = item[key]
	_events.append(event)
	if _events.size() > MAX_HISTORY: _events.pop_front()

func _existing(owner_id: int, trigger: String) -> Dictionary:
	for item: Dictionary in _active:
		if int(item.owner_entity_id) == owner_id and str(item.trigger) == trigger: return item
	return {}

func _suppress(reason: String) -> void:
	_suppressed += 1
	_record("suppressed", {}, reason)

func _phase(item: Dictionary, phase: String) -> void:
	item.phase = phase
	item.phase_age = 0.0
	item.phase_duration = _tag_seconds(str(item.beast), phase)
	_record("phase", item)

func _spawn(owner: Dictionary, trigger: String, phase: String, pos: Vector2, direction: Vector2, strength: float) -> Dictionary:
	var owner_id: int = int(owner.entity_id)
	# A real paid preparation takes over a still-visible generic strike/guard.
	# Reuse its slot instead of losing the committed move or adding a copy.
	for previous: Dictionary in _active:
		if int(previous.owner_entity_id) != owner_id: continue
		if trigger in ["comet_charge", "breakneck_charge"] and str(previous.trigger) in ["impact_wake", "anchor_mature"]:
			_record("superseded", previous, "real_commit_priority")
			previous.trigger = trigger
			previous.world_pos = pos
			previous.direction = direction
			previous.strength = clampf(strength, 0.0, 3.0)
			previous.rank = clampi(int(owner.get("power_ranks", {}).get(EVENT_POWERS[trigger], 1)), 1, 3)
			# Preserve allocation age: priority cannot extend the four-second
			# lifetime ceiling of an existing slot.
			previous.impact = false
			previous.follow_owner = true
			_owner_ready[owner_id] = _clock + OWNER_COOLDOWN
			_phase(previous, phase)
			_record("repurposed", previous, "real_commit_priority")
			return previous
	if _clock < float(_owner_ready.get(owner_id, 0.0)):
		_suppress("owner_cooldown")
		return {}
	# One meaningful event per owner at a time; an ongoing preparation retains
	# its slot and its resolution updates that same instance.
	for item: Dictionary in _active:
		if int(item.owner_entity_id) == owner_id:
			_suppress("owner_active")
			return {}
	var player: bool = owner_id == int(_host().player_entity_id)
	if _active.size() >= MAX_LIVE:
		var replace: int = -1
		if player:
			for index: int in range(_active.size()):
				if not bool(_active[index].player): replace = index; break
		if replace < 0:
			_suppress("live_budget")
			return {}
		_record("evicted", _active[replace], "player_priority")
		_active.remove_at(replace)
	var beast: String = beast_for_blade(str(owner.get("build", {}).get("blade", "")))
	if beast.is_empty(): return {}
	_sequence += 1
	var rank_value: int = clampi(int(owner.get("power_ranks", {}).get(EVENT_POWERS.get(trigger, ""), 1)), 1, 3)
	var item: Dictionary = {"instance_id": _sequence, "beast": beast, "owner_entity_id": owner_id,
		"trigger": trigger, "phase": phase, "phase_age": 0.0, "phase_duration": _tag_seconds(beast, phase),
		"age": 0.0, "world_pos": pos, "direction": direction, "strength": clampf(strength, 0.0, 3.0),
		"rank": rank_value, "player": player, "impact": phase == "strike", "follow_owner": phase != "strike"}
	_active.append(item)
	_owner_ready[owner_id] = _clock + OWNER_COOLDOWN
	_spawned += 1
	_peak_live = maxi(_peak_live, _active.size())
	_record("spawned", item)
	return item

## No inferred owner or acquisition preview may create a beast. Provenance is
## supplied only at the actual semantic power hooks in PowerRuntime.
func accept_event(kind: String, pos: Vector2, direction: Vector2, strength: float, provenance: Dictionary) -> void:
	var host: Object = _host()
	if not _enabled or host == null or bool(host.paused) or str(host.battle_status) != "battle": return
	if not bool(provenance.get("beast_trigger", false)) or not EVENT_POWERS.has(kind) or kind == "anchor_mature": return
	var owner: Dictionary = host.entity(int(provenance.get("owner_entity_id", 0)))
	if not _live_owner(owner) or not pos.is_finite() or not direction.is_finite(): return
	if EVENT_POWERS[kind] not in owner.get("powers", []): return
	_load_assets()
	var trigger: String = "comet_charge" if kind in ["comet_charge", "comet_release"] else ("breakneck_charge" if kind.begins_with("breakneck_") else kind)
	var item: Dictionary = _existing(int(owner.entity_id), trigger)
	match kind:
		"comet_charge", "breakneck_charge":
			if not item.is_empty(): return
			item = _spawn(owner, trigger, "prepare", Vector2(owner.pos), direction, strength)
			if not item.is_empty():
				var remaining: float = float(owner.get("comet_time", 0.0)) if kind == "comet_charge" else maxf(float(owner.get("redline_commit_time", 0.0)), float(owner.get("redline_time", 0.0)))
				item.phase_duration = minf(float(item.phase_duration), maxf(0.06, remaining * 0.5))
		"comet_release", "breakneck_impact":
			if item.is_empty(): return
			item.world_pos = pos
			item.direction = direction
			item.impact = true
			item.follow_owner = false
			_phase(item, "strike")
		"breakneck_recovery":
			if item.is_empty(): return
			# The semantic impact and recovery hooks occur in the same tick.
			# Retain the honest strike first; a miss has no strike/contact core.
			if str(item.phase) != "strike": _phase(item, "recovery")
		"impact_wake":
			_spawn(owner, trigger, "strike", pos, direction, strength)

func _armed(item: Dictionary, owner: Dictionary) -> bool:
	if str(item.trigger) == "comet_charge": return float(owner.get("comet_time", 0.0)) > 0.0
	if str(item.trigger) == "breakneck_charge":
		# The modern paid commitment field and accepted standalone overload
		# are both real timed commitments, never inferred from an ordinary Burst.
		return float(owner.get("redline_commit_time", 0.0)) > 0.0 or (str(owner.get("redline_active_mutation", "")) == "breakneck" and float(owner.get("redline_time", 0.0)) > 0.0)
	return false

func _armed_remaining(item: Dictionary, owner: Dictionary) -> float:
	if str(item.trigger) == "comet_charge": return maxf(0.0, float(owner.get("comet_time", 0.0)))
	return maxf(float(owner.get("redline_commit_time", 0.0)), float(owner.get("redline_time", 0.0)))

func _observe_guard() -> void:
	var host: Object = _host()
	var retained: Dictionary = {}
	# Read a stable ordered view, with the player's meaningful hold first.
	var owners: Array[Dictionary] = host._ordered_fighters()
	owners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.entity_id) == int(b.entity_id): return false
		if int(a.entity_id) == int(host.player_entity_id): return true
		if int(b.entity_id) == int(host.player_entity_id): return false
		return int(a.entity_id) < int(b.entity_id))
	for owner: Dictionary in owners:
		if not _live_owner(owner): continue
		var id: int = int(owner.entity_id)
		retained[id] = true
		var mature: bool = "dead_centre" in owner.get("powers", []) and bool(owner.get("anchor_central_hold", false)) and float(owner.get("anchor_hold_seconds", 0.0)) >= 6.0 - 0.000001
		if mature and not bool(_guard_seen.get(id, false)):
			if _clock < float(_owner_ready.get(id, 0.0)): continue
			var busy: bool = false
			for active: Dictionary in _active:
				if int(active.owner_entity_id) == id: busy = true; break
			if busy or (_active.size() >= MAX_LIVE and id != int(host.player_entity_id)): continue
			var guard: Dictionary = _spawn(owner, "anchor_mature", "guard", Vector2(owner.pos), Vector2(owner.vel).normalized(), 1.0)
			if not guard.is_empty(): _guard_seen[id] = true
		elif not mature: _guard_seen[id] = false
	for id: int in _guard_seen.keys():
		if not retained.has(id): _guard_seen.erase(id)
	for id: int in _owner_ready.keys():
		if not retained.has(id): _owner_ready.erase(id)

func update(dt: float) -> void:
	var host: Object = _host()
	if not _enabled or host == null or bool(host.paused): return
	if str(host.battle_status) != "battle":
		finish()
		return
	_clock += maxf(0.0, dt)
	for index: int in range(_active.size() - 1, -1, -1):
		var item: Dictionary = _active[index]
		var owner: Dictionary = host.entity(int(item.owner_entity_id))
		item.age = float(item.age) + dt
		item.phase_age = float(item.phase_age) + dt
		if not _live_owner(owner) or float(item.age) >= MAX_INSTANCE_SECONDS:
			_record("expired", item, "owner_retired" if not _live_owner(owner) else "lifetime_budget")
			_active.remove_at(index)
			continue
		if bool(item.follow_owner): item.world_pos = Vector2(owner.pos)
		match str(item.phase):
			"prepare", "travel":
				if not _armed(item, owner): _phase(item, "recovery")
				elif str(item.phase) == "prepare" and float(item.phase_age) >= float(item.phase_duration):
					_phase(item, "travel")
					# A short paid Breakneck commitment still exposes all travel
					# keys in its real remaining window, preserving authored ratios.
					item.phase_duration = minf(float(item.phase_duration), maxf(0.001, _armed_remaining(item, owner)))
			"guard":
				if not bool(owner.get("anchor_central_hold", false)) or float(owner.get("anchor_hold_seconds", 0.0)) < 6.0 - 0.000001 or float(item.phase_age) >= float(item.phase_duration): _phase(item, "recovery")
			"strike":
				if float(item.phase_age) >= float(item.phase_duration): _phase(item, "recovery")
			"recovery":
				if float(item.phase_age) >= float(item.phase_duration):
					_record("expired", item, "resolved")
					_active.remove_at(index)
	_observe_guard()

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
	var mirror: bool = direction.x - direction.y < -0.001
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
		var authored_age: float = phase_age
		if phase in ["prepare", "travel"]: authored_age *= _tag_seconds(str(item.beast), phase) / maxf(0.001, float(item.phase_duration))
		# Play the single authored committed motion once, then hold its final
		# travel key while the real charge remains armed. Never loop attacks.
		var frame: int = frame_for(str(item.beast), phase, authored_age)
		var size: Vector2 = geometry.size
		var columns: int = maxi(1, int(meta.columns))
		var source: Rect2 = Rect2(Vector2(float(frame % columns) * size.x, floorf(float(frame) / float(columns)) * size.y), size)
		# Only the spectral figure rises. The real rig, contact plane and height
		# remain exactly as simulated during Comet/Breakneck preparation.
		var alpha: float = (0.56 if bool(item.player) else 0.34) + float(int(item.rank) - 1) * 0.07 + minf(0.04, float(item.strength) * 0.015)
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
		"max_instance_seconds": MAX_INSTANCE_SECONDS, "active": active, "events": _events.duplicate(true)}
