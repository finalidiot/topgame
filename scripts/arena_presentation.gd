extends RefCounted
## Fixed, peripheral foundry equipment. This object reads the Run clock and
## never owns combat state, random streams, timers, particles, sounds or nodes.
const ROOT: String = "res://assets/arena/escalation003a/"
const STAGES: Array[String] = ["EARLY", "BUILDING", "MID", "LATE", "EXTREME"]
const THRESHOLDS: Array[float] = [90.0, 210.0, 390.0, 540.0]
const MAX_DRAW_CALLS: int = 17
const MOBILE_MAX_DRAW_CALLS: int = 14
const MAX_SPARK_FIXTURES: int = 4
const ANCHORS: Dictionary = {
	"machinery":[Vector2(86,46),Vector2(554,46)],
	"vent":[Vector2(144,45),Vector2(496,45)],
	"display_panel":[Vector2(214,28),Vector2(426,28)],
	"warning_bank":[Vector2(43,155),Vector2(597,155),Vector2(320,327)],
	"perimeter":[Vector2(176,51),Vector2(464,51),Vector2(176,267),Vector2(464,267)],
	"sparks":[Vector2(64,139),Vector2(576,139),Vector2(309,307),Vector2(530,77)]}
static var _metadata: Dictionary = {}
static var _textures: Dictionary = {}
var last_snapshot: Dictionary = {}
var actual_draw_calls: int = 0

static func stage_for(run_elapsed: float, boss_pressure: bool = false) -> int:
	if boss_pressure: return 4
	var time: float = maxf(0.0,run_elapsed) if is_finite(run_elapsed) else 0.0
	var stage: int = 0
	for threshold: float in THRESHOLDS:
		if time >= threshold: stage += 1
	return stage

static func presentation_snapshot(run_elapsed: float, boss_pressure: bool = false, reduced_flashing: bool = false, quality: float = 1.0) -> Dictionary:
	var stage: int = stage_for(run_elapsed,boss_pressure)
	var mobile: bool = quality < 0.75
	return {"stage":STAGES[stage],"stage_id":stage,"boss":boss_pressure,"run_elapsed":maxf(0.0,run_elapsed) if is_finite(run_elapsed) else 0.0,
		"quality":clampf(quality,0.0,1.0),"reduced_flashing":reduced_flashing,
		"motion_rate":[0.65,0.85,1.10,1.45,1.80][stage],
		"fixture_alpha":[0.55,0.66,0.74,0.83,0.90][stage],
		"perimeter_active":stage >= 1,"spark_fixture_limit":0 if reduced_flashing or stage < 1 else (2 if mobile else MAX_SPARK_FIXTURES),
		"spark_period":[14.0,10.0,7.0,5.0,3.6][stage],
		"maximum_draw_calls":MOBILE_MAX_DRAW_CALLS if mobile else MAX_DRAW_CALLS,
		"nodes_created":0,"particles_created":0,"gameplay_writes":0,"floor_hazard_shapes":0,
		"warning_animation":not reduced_flashing,"peripheral_only":true}

static func _meta(name: String) -> Dictionary:
	if not _metadata.has(name):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + name + ".json")) if FileAccess.file_exists(ROOT + name + ".json") else {}
		_metadata[name] = parsed if parsed is Dictionary else {}
	return _metadata[name]

static func frame_for(name: String, tag: String, clock: float, fixed: bool = false) -> int:
	var meta: Dictionary = _meta(name)
	var span: Dictionary = meta.get("tags",{}).get(tag,{})
	if span.is_empty(): return -1
	var first: int = int(span.from)
	if fixed: return first
	var duration: float = 0.0
	for index: int in range(first,int(span.to)+1): duration += float(meta.durations_ms[index]) / 1000.0
	var remaining: float = fposmod(maxf(0.0,clock),maxf(duration,0.001))
	for index: int in range(first,int(span.to)+1):
		remaining -= float(meta.durations_ms[index]) / 1000.0
		if remaining < 0.0: return index
	return int(span.to)

func _cell(canvas: CanvasItem, name: String, tag: String, clock: float, contact: Vector2, alpha: float, fixed: bool = false) -> void:
	var meta: Dictionary = _meta(name)
	var frame: int = frame_for(name,tag,clock,fixed)
	if frame < 0: return
	var path: String = str(meta.get("texture",""))
	if not _textures.has(path):
		if not ResourceLoader.exists(path): return
		_textures[path] = load(path)
	var cell: Vector2 = Vector2(meta.cell[0],meta.cell[1])
	var pivot: Vector2 = Vector2(meta.pivot[0],meta.pivot[1])
	canvas.draw_texture_rect_region(_textures[path],Rect2((contact-pivot).round(),cell),Rect2(Vector2(frame,0)*cell,cell),Color(1,1,1,alpha))
	actual_draw_calls += 1

func draw_background(canvas: CanvasItem, run_elapsed: float, boss_pressure: bool = false, reduced_flashing: bool = false, quality: float = 1.0) -> void:
	last_snapshot = presentation_snapshot(run_elapsed,boss_pressure,reduced_flashing,quality)
	actual_draw_calls = 0
	var stage: int = int(last_snapshot.stage_id)
	var time: float = float(last_snapshot.run_elapsed)
	var motion: float = time * float(last_snapshot.motion_rate)
	var alpha: float = float(last_snapshot.fixture_alpha)
	var machine_tag: String = "IDLE" if stage < 2 else ("DRIVE" if stage < 4 else "OVERDRIVE")
	for index: int in range(ANCHORS.machinery.size()):
		_cell(canvas,"machinery",machine_tag,motion+float(index)*0.31,ANCHORS.machinery[index],alpha)
	for index: int in range(ANCHORS.vent.size()):
		_cell(canvas,"vent","HOT" if stage >= 2 else "IDLE",motion+float(index)*0.44,ANCHORS.vent[index],alpha)
	for index: int in range(1 if quality < 0.75 else 2):
		_cell(canvas,"display_panel","LOAD" if stage >= 2 else "IDLE",motion+float(index)*0.39,ANCHORS.display_panel[index],alpha)
	var bank_tag: String = "SAFE" if stage == 0 else ("BUILDING" if stage < 3 else ("WARNING" if stage == 3 else "ALARM"))
	for index: int in range(ANCHORS.warning_bank.size()):
		_cell(canvas,"warning_bank",bank_tag,time+float(index)*0.71,ANCHORS.warning_bank[index],alpha,reduced_flashing)
	if stage >= 1:
		for index: int in range(ANCHORS.perimeter.size()):
			_cell(canvas,"perimeter","LEFT" if index in [0,3] else "RIGHT",time+float(index)*0.60,ANCHORS.perimeter[index],alpha * 0.78,reduced_flashing)
	for index: int in range(int(last_snapshot.spark_fixture_limit)):
		var age: float = fposmod(time+float(index)*2.91,float(last_snapshot.spark_period))
		if age < 1.08:
			_cell(canvas,"sparks","SPARK",age,ANCHORS.sparks[index],alpha * 0.72)
	last_snapshot["actual_draw_calls"] = actual_draw_calls
