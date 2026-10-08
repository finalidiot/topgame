extends RefCounted
## Saved native Aseprite frames, independent icons and physical floor fixtures.
## This read-only renderer never creates or changes gameplay state.
const PATH: String = "res://assets/powers/defence003a/manifest.json"
static var metadata: Dictionary = {}
static var textures: Dictionary = {}

static func meta() -> Dictionary:
	if metadata.is_empty() and FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: metadata = parsed
	return metadata

static func art(id: String) -> Dictionary: return meta().get("art", {}).get(id, {}).duplicate(true)

static func texture(path: String) -> Texture2D:
	if not textures.has(path): textures[path] = load(path)
	return textures[path] as Texture2D

static func draw_cel(canvas: CanvasItem, family: String, tag: String, at: Vector2, age: float, alpha: float = 1.0, stage: int = -1) -> bool:
	var m: Dictionary = meta().get("families", {}).get(family, {}).get("fx", {})
	var span: Dictionary = m.get("tags", {}).get(tag, {})
	if span.is_empty(): return false
	var frame: int = int(span.to)
	if stage >= 0: frame = int(span.from) + clampi(stage, 0, int(span.to) - int(span.from))
	else:
		var left: float = maxf(0.0, age) * 1000.0
		for index: int in range(int(span.from), int(span.to) + 1):
			left -= float(m.durations_ms[index])
			if left < 0.0: frame = index; break
	var size: Vector2 = Vector2(m.cell[0], m.cell[1])
	var pivot: Vector2 = Vector2(m.pivot[0], m.pivot[1])
	var source: Rect2 = Rect2(Vector2(frame % int(m.columns) * size.x, floori(float(frame) / float(m.columns)) * size.y), size)
	canvas.draw_texture_rect_region(texture(str(m.texture)), Rect2((at - pivot).round(), size), source, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	return true

static func effect(canvas: CanvasItem, data: Dictionary, at: Vector2) -> bool:
	var kind: String = str(data.get("kind", ""))
	var definition: Dictionary = meta().get("events", {}).get(kind, {})
	if definition.is_empty(): return false
	var f: Dictionary = meta().families[definition.family].fx
	var span: Dictionary = f.tags[definition.tag]
	var duration: float = 0.0
	for index: int in range(int(span.from), int(span.to) + 1): duration += float(f.durations_ms[index]) / 1000.0
	var progress: float = clampf(float(data.get("age", 0.0)) / maxf(0.001, float(data.get("duration", 0.4))), 0.0, 1.0)
	return draw_cel(canvas, str(definition.family), str(definition.tag), at, progress * duration)

static func sink_visual_state(f: Dictionary, clock: float) -> Dictionary:
	var ratio: float = clampf(float(f.get("sink_charge",0.0))/maxf(1.0,float(f.get("sink_capacity",90.0))),0.0,1.0)
	var base: int = clampi(int(ceilf(ratio*7.0)),1,7)
	# Existing native fittings compress one discrete key as accumulated force
	# loads them. Full stays full; lower fittings show staggered breathing.
	var phase: float = fposmod(maxf(0.0,clock)*(0.8+ratio*0.7),1.0)
	var key: int = maxi(1,base-(1 if base>=3 and phase<0.20 else 0))
	return {"state":"EMPTY" if ratio<=0.02 else ("FULL" if ratio>=0.90 else "PARTIAL"),"ratio":ratio,"stage":key,"alpha":0.46+ratio*0.32+sin(phase*TAU)*0.06,"phase":phase}

static func aura(canvas: CanvasItem, f: Dictionary, at: Vector2, clock: float = 0.0) -> void:
	if not str(f.get("outcome", "")).is_empty(): return
	var floor_at: Vector2 = at + Vector2(0.0, float(f.get("height", 0.0)))
	var gyro: float = float(f.get("gyro_charge", 0.0))
	if gyro > 0.10: draw_cel(canvas, "gyro_lock", "lock", floor_at, 0.0, 0.45 + gyro * 0.40, clampi(int(ceilf(gyro * 7.0)), 1, 7))
	var sink: Dictionary = sink_visual_state(f,clock)
	if str(sink.state)!="EMPTY": draw_cel(canvas,"impact_sink","stored",floor_at,0.0,float(sink.alpha),int(sink.stage))
	var brace: float = maxf(float(f.get("exchange_charge", 0.0)), float(f.get("exchange_carry", 0.0)))
	if brace > 0.10: draw_cel(canvas, "anchor_exchange", "brace", floor_at, 0.0, 0.45 + brace * 0.45, clampi(int(ceilf(brace * 7.0)), 1, 7))
