extends Node2D
## Actual RPM, attached to stable contact pivots. Presentation never writes combat.
const Layout = preload("res://scripts/combat_hud_layout.gd")
const MAX_BARS: int = 16
const NORMAL_SIZE = Vector2(34, 5)
const BOSS_SIZE = Vector2(46, 7)
var host: Node2D
var enabled: bool = true
var mobile_layout: bool = OS.has_feature("mobile")
var _last: Dictionary = {}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1

func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	if not value: _last = {"bars": [], "enabled": false}
	queue_redraw()

func _process(_delta: float) -> void:
	if enabled and is_instance_valid(host) and host.visible: queue_redraw()

static func _priority(fighter: Dictionary, player_id: int) -> int:
	if int(fighter.get("entity_id", -1)) == player_id: return 0
	return 1 if str(fighter.get("enemy_kind", "")) == "boss" else (2 if str(fighter.get("enemy_kind", "")) == "elite" else 3)

static func layout(fighters: Array, player_id: int, mobile: bool = false, visual_offset: Vector2 = Vector2.ZERO) -> Dictionary:
	var ordered: Array[Dictionary] = []
	var omitted: Dictionary = {"small": 0, "retired": 0, "offscreen": 0, "hud": 0, "crowd": 0}
	for fighter: Dictionary in fighters:
		if str(fighter.get("combatant_type", "full_top")) == "small_top": omitted.small += 1; continue
		if not str(fighter.get("outcome", "")).is_empty() or not is_finite(float(fighter.get("rpm", 0.0))) or float(fighter.get("rpm", 0.0)) <= 0.0: omitted.retired += 1; continue
		var world: Vector2 = fighter.get("pos", Vector2(INF, INF))
		if not world.is_finite(): omitted.offscreen += 1; continue
		ordered.append(fighter)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = _priority(a, player_id); var pb: int = _priority(b, player_id)
		return int(a.get("entity_id", 0)) < int(b.get("entity_id", 0)) if pa == pb else pa < pb)
	var bars: Array[Dictionary] = []
	for fighter: Dictionary in ordered:
		var world: Vector2 = fighter.pos
		var contact: Vector2 = Vector2(320.0 + world.x - world.y, 165.0 + (world.x + world.y) * 0.5 - float(fighter.get("height", 0.0))).round() + visual_offset
		if not Layout.ARENA_VIEW.has_point(contact): omitted.offscreen += 1; continue
		var boss: bool = str(fighter.get("enemy_kind", "")) == "boss"
		var size: Vector2 = BOSS_SIZE if boss else NORMAL_SIZE
		var base: float = 53.0 if boss else (46.0 if str(fighter.get("enemy_kind", "")) == "elite" else 33.0)
		var rect: Rect2 = Rect2()
		var accepted: bool = false
		var hud_blocked: bool = false
		for lane: int in range(3):
			var candidate: Rect2 = Rect2((contact - Vector2(size.x * 0.5, base + lane * 8.0)).round(), size)
			if not Layout.world_bar_allowed(candidate, mobile): hud_blocked = true; continue
			var overlaps: bool = false
			for other: Dictionary in bars:
				if candidate.grow(2.0).intersects(other.rect): overlaps = true; break
			if not overlaps: rect = candidate; accepted = true; break
		if not accepted or bars.size() >= MAX_BARS:
			omitted["hud" if hud_blocked else "crowd"] += 1
			continue
		var player: bool = int(fighter.get("entity_id", -1)) == player_id
		var rpm: float = clampf(float(fighter.rpm), 0.0, 1.0)
		var color: Color = Color("83cfda") if player else (Color("d8b77d") if boss else (Color("d79874") if str(fighter.get("enemy_kind", "")) == "elite" else Color("c29380")))
		if rpm < 0.25: color = Color("d76c60")
		elif rpm < 0.50: color = color.lerp(Color("d2a268"), 0.45)
		bars.append({"id": int(fighter.entity_id), "rect": rect, "contact": contact, "value": rpm,
			"raw_rpm": float(fighter.rpm), "color": color, "player": player, "boss": boss,
			"overdrive": float(fighter.rpm) > 1.0})
	return {"bars": bars, "omitted": omitted, "maximum": MAX_BARS, "mobile_layout": mobile,
		"gameplay_writes": 0, "owns_timers": false, "reduced_flashing_pulses": 0,
		"visual_offset": visual_offset, "attachment": "rounded projected ground contact, actual height and canonical Battle presentation offset; no wobble/lean tracking", "lane_policy": "player, boss, elite, stable entity ID; at most three upward lanes then omit"}

func diagnostic_snapshot() -> Dictionary:
	return _last.duplicate(true)

func _draw() -> void:
	if not enabled or not is_instance_valid(host): _last = {"bars": [], "enabled": false}; return
	var visual_offset: Vector2 = host.presentation_offset() if host.has_method("presentation_offset") else Vector2.ZERO
	_last = layout(host.fighters, int(host.player_entity_id), mobile_layout, visual_offset)
	_last["enabled"] = true
	for bar: Dictionary in _last.bars:
		var rect: Rect2 = bar.rect
		draw_rect(rect, Color("15222c"))
		draw_rect(rect, Color("ab9b73") if bar.boss else Color("4c626d"), false, 1.0)
		var inside: Rect2 = Rect2(rect.position + Vector2.ONE, rect.size - Vector2(2, 2))
		draw_rect(Rect2(inside.position, Vector2(roundf(inside.size.x * float(bar.value)), inside.size.y)), bar.color)
		if bar.overdrive: draw_line(rect.position + Vector2(1, 0), rect.position + Vector2(rect.size.x - 2, 0), Color("e4a46a"))
		if bar.player: draw_rect(Rect2(rect.position + Vector2(-2, 1), Vector2(1, rect.size.y - 2)), Color("b9e0dc"))
