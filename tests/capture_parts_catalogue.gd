extends SceneTree
## Labelled assembly review. Launch and every movement/contact/RPM tick use
## the real battle model. Only legal assembly, seed and controls are supplied.
const Battle = preload("res://tests/measured_presentation_battle.gd")
const Physics = preload("res://scripts/battle.gd")
const Parts = preload("res://scripts/parts.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const SCENARIOS: Array[Dictionary] = [
	{"name":"HEAVY STRIKER", "build":{"blade":"hammerfall","ratchet":"kickback","bit":"claw"},"policy":"aggressive","note":"Aligned hits / sideways recoil / grip breaks at speed"},
	{"name":"DEFENSIVE ANCHOR", "build":{"blade":"puck","ratchet":"ballast","bit":"tripod"},"policy":"defensive","note":"Compact reach / heavy core / planted foot"},
	{"name":"FAST DRIFTER", "build":{"blade":"outrigger","ratchet":"high","bit":"skate"},"policy":"drift","note":"Wide reach / low grip / momentum carries through arcs"},
	{"name":"UNSTABLE HEAVY ATTACKER", "build":{"blade":"lopsider","ratchet":"offset","bit":"chisel"},"policy":"aggressive","note":"Off-centre mass / leverage / directional foot"},
	{"name":"BALANCED GRINDER", "build":{"blade":"sawtooth","ratchet":"flex","bit":"ball"},"policy":"hybrid","note":"Repeated pressure / shock flex / forgiving roll"},
	{"name":"STRANGE HYBRID", "build":{"blade":"crescent","ratchet":"scrap","bit":"eccentric"},"policy":"aggressive","note":"Scoop transfer / warped connector / rhythmic grip"},
	{"name":"FREE-SPIN PRECISION", "build":{"blade":"fork","ratchet":"flywheel","bit":"freewheel"},"policy":"hybrid","note":"Recessed strikes / rotational inertia / weak control"}
]
var manifest: String = ""
var frame_dir: String = ""
var selection: int = -1
var seconds: float = 6.0
var diagnostic: bool = false

func _initialize() -> void: call_deferred("run")

func label(text: String, at: Vector2, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.position = at
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	root.add_child(result)
	return result

func control(b: Node2D, policy: String, tick: int) -> Dictionary:
	if policy != "drift": return Bot.input(b, policy, tick)
	var p: Dictionary = b.player_entity()
	var pos: Vector2 = p.pos
	var radial: Vector2 = pos.normalized() if pos.length() > 1.0 else Vector2.RIGHT
	var tangent: Vector2 = radial.orthogonal()
	var desired: Vector2 = tangent * 130.0 + radial * (78.0 - pos.length()) * 2.0
	# A feedback steering controller supplies ordinary input only. It never
	# assigns velocity or position; poor grip/recoil is visible in the route.
	var steering: Vector2 = (desired - Vector2(p.vel)).normalized() * 0.68
	var screen: Vector2 = Vector2(steering.x-steering.y,(steering.x+steering.y)*0.5).normalized()*steering.length()
	return {"direction":screen,"burst":false,"brake":pos.length()>149.0}

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): manifest = arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frame_dir = arg.trim_prefix("--frames=")
		if arg.begins_with("--scenario="): selection = int(arg.trim_prefix("--scenario="))
		if arg.begins_with("--seconds="): seconds = clampf(float(arg.trim_prefix("--seconds=")),1.0,9.0)
		if arg == "--diagnostic": diagnostic = true
	if manifest.is_empty():
		push_error("Supply an external --manifest= output; no save paths are opened")
		quit(2)
		return
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(640,360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty(): DirAccess.make_dir_recursive_absolute(frame_dir)
	var runs: Array[Dictionary] = []
	for index: int in range(SCENARIOS.size()):
		if selection >= 0 and index != selection: continue
		var scenario: Dictionary = SCENARIOS[index]
		assert(Parts.validate_build(scenario.build) == scenario.build, "Review uses legal final components")
		var b: Node2D = Battle.new()
		root.add_child(b)
		b.set_physics_process(false)
		b.screen_shake_enabled = false
		b.begin(scenario.build,{"blade":"balance","ratchet":"mid","bit":"ball"},1,421)
		# Countdown and launch are real ticks, omitted from the short review cut.
		var warmup: int = 0
		while b.battle_status != "battle" and warmup < 300:
			b.test_step(Physics.FIXED_DT)
			warmup += 1
		assert(b.battle_status == "battle")
		var title: Label = label("002C.5.2 / " + str(scenario.name),Vector2(12,5),12,Color("e4ebd6"))
		var assembly: Label = label(Parts.title(scenario.build),Vector2(12,23),10,Color("d4b886"))
		var note: Label = label(str(scenario.note),Vector2(12,325),9,Color("e4ebd6"))
		var cause: Label = label("CONTROLLED ASSEMBLY / REAL COMBAT / INPUTS ONLY / NO SAVE WRITES",Vector2(12,341),8,Color("bbc8cf"))
		var rows: Array[Dictionary] = []
		var captured: int = 0
		for tick: int in range(roundi(seconds*60.0)):
			var c: Dictionary = control(b,str(scenario.policy),tick)
			b.test_step(Physics.FIXED_DT,c.direction,c.burst,c.brake)
			var p: Dictionary = b.player_entity()
			if tick%30 == 0:
				rows.append({"tick":tick,"time":b.elapsed,"rpm":p.rpm,"speed":Vector2(p.vel).length(),"wobble":p.wobble,"position":[p.pos.x,p.pos.y],"velocity":[p.vel.x,p.vel.y],"hits":b.hits,"status":b.battle_status})
			if not diagnostic:
				b.queue_redraw()
				await process_frame
				if not frame_dir.is_empty() and tick in [59,179,299]:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(frame_dir.path_join("%02d-%03d.png"%[index,tick]))
			captured += 1
		var draws: Array = b.draw_samples.duplicate()
		draws.sort()
		runs.append({"scenario":scenario,"seed":421,"warmup_ticks":warmup,"capture_frames":captured,
			"duration_seconds":float(captured)/60.0,"rows":rows,"actual_contacts":b.hits,
			"draw_samples":draws.size(),"draw_submit_p95_ms":draws[int((draws.size()-1)*0.95)] if not draws.is_empty() else 0.0,
			"result":b.last_result.duplicate(true)})
		for item: Label in [title,assembly,note,cause]: item.free()
		b.free()
		print("PARTS_CAPTURE ",scenario.name," frames=",captured," real_contacts=",runs[-1].actual_contacts)
	var file: FileAccess = FileAccess.open(manifest,FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"authenticity":"Legal controlled assemblies, same initial opponent/seed, real launch ticks then steering/burst/brake inputs. No position/velocity/RPM/contact/outcome injection. No collection or preference files opened.","native_view":[640,360],"nearest_output":[1280,720],"fps":60,"diagnostic":diagnostic,"runs":runs},"\t"))
	file.close()
	print("PARTS_CAPTURE_PASS runs=",runs.size())
	quit(0)
