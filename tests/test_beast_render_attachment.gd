extends SceneTree
## Explicit presentation fixture: render the actual BeastManifestations.draw()
## through Godot, replacing only its atlas with pivot sentinels. This is an
## engine anchoring regression, never gameplay evidence or review footage.
const Battle = preload("res://scripts/battle.gd")
const BUILD: Dictionary = {"blade": "balance", "ratchet": "mid", "bit": "ball"}
const SHAKE: Vector2 = Vector2(11.0, 7.0)
var checks: int = 0
var failures: Array[String] = []
var measurements: Array[Dictionary] = []

class RenderCanvas extends Node2D:
	var controller: RefCounted
	func _draw() -> void:
		# Battle's existing camera-shake transform must survive the beast pass.
		draw_set_transform(Vector2(11.0, 7.0))
		controller.draw(self)

class LegacyShiftController extends "res://scripts/beast_manifestations.gd":
	func draw_geometry_for(item: Dictionary) -> Dictionary:
		var geometry: Dictionary = super.draw_geometry_for(item)
		if not geometry.is_empty() and bool(geometry.mirror):
			var rect: Rect2 = geometry.rect
			rect.position.x += float(geometry.size.x)
			geometry.rect = rect
		return geometry

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func sentinel_texture(meta: Dictionary) -> Texture2D:
	var image: Image = Image.create(int(meta.cell[0]) * int(meta.columns), int(meta.cell[1]) * ceili(float(meta.frame_count) / float(meta.columns)), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for frame: int in range(int(meta.frame_count)):
		var origin: Vector2i = Vector2i((frame % int(meta.columns)) * int(meta.cell[0]), (frame / int(meta.columns)) * int(meta.cell[1]))
		# A symmetric 2x2 mark has its geometric centre exactly at (64,96).
		for x: int in range(int(meta.pivot[0]) - 1, int(meta.pivot[0]) + 1):
			for y: int in range(int(meta.pivot[1]) - 1, int(meta.pivot[1]) + 1):
				image.set_pixel(origin.x + x, origin.y + y, Color(1.0, 0.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)

func purple_pixels(image: Image) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r > 0.08 and pixel.b > 0.08 and pixel.g < 0.03: points.append(Vector2(float(x) + 0.5, float(y) + 0.5))
	return points

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run this rendered anchoring regression with a real renderer, without --headless")
		quit(2); return
	var report_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	var battle: Node2D = Battle.new()
	root.add_child(battle); battle.set_physics_process(false); battle.visible = false
	battle.begin_encounter(BUILD, {"opponent_build": BUILD, "seed": 421, "player_power_ids": ["iron_comet"], "player_power_ranks": {"iron_comet": 2}})
	battle.battle_status = "battle" # Explicit presentation fixture, not a combat capture.
	var player: Dictionary = battle.player_entity()
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var canvas: RenderCanvas = RenderCanvas.new()
	canvas.controller = battle.beasts
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(canvas)
	var meta: Dictionary = battle.beasts._metadata.coil_dragon
	battle.beasts._textures.coil_dragon = sentinel_texture(meta)
	for mirrored: bool in [false, true]:
		for phase: String in ["prepare", "travel", "strike"]:
			battle.beasts.reset()
			player.comet_time = 2.0
			var direction: Vector2 = Vector2.LEFT if mirrored else Vector2.RIGHT
			battle.beasts.accept_event("comet_charge", player.pos, direction, 1.0, {"owner_entity_id": 1, "beast_trigger": true})
			if phase == "prepare": battle.beasts.update(0.125)
			elif phase == "travel": battle.beasts.update(0.3)
			else: battle.beasts.accept_event("comet_release", Vector2(18.0, -10.0), direction, 1.0, {"owner_entity_id": 1, "beast_trigger": true})
			var item: Dictionary = battle.beast_presentation_snapshot().active[0]
			var geometry: Dictionary = battle.beasts.draw_geometry_for(item)
			var ground: Vector2 = Battle.project(Vector2(18.0, -10.0)) if phase == "strike" else Battle.project(Vector2(player.pos), float(player.height))
			var lift: float = 6.0 if phase == "prepare" else (12.0 if phase == "travel" else 0.0)
			var expected: Vector2 = ground - Vector2(0.0, lift) + SHAKE
			canvas.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var pixels: Array[Vector2] = purple_pixels(viewport.get_texture().get_image())
			check(pixels.size() == 4, "Godot draws the four pivot pixels once")
			var centre: Vector2 = Vector2.ZERO
			for point: Vector2 in pixels: centre += point
			if not pixels.is_empty(): centre /= float(pixels.size())
			check(centre.distance_to(expected) < 0.01, "Rendered %s %s stays on the real projected owner/contact pivot and preserves shake" % ["mirrored" if mirrored else "normal", phase])
			check(geometry.mirror == mirrored, "The requested direction actually reaches the engine flip path")
			measurements.append({"phase": phase, "mirrored": mirrored, "pixel_count": pixels.size(), "expected": [expected.x, expected.y], "rendered": [centre.x, centre.y], "error_pixels": centre.distance_to(expected)})
	# Demonstrate that this renderer/readback test detects the actual former
	# +128 origin error, rather than only asserting our geometry helper's math.
	var legacy: RefCounted = LegacyShiftController.new()
	legacy.setup(battle)
	legacy._textures.coil_dragon = sentinel_texture(meta)
	player.comet_time = 2.0
	legacy.accept_event("comet_charge", player.pos, Vector2.LEFT, 1.0, {"owner_entity_id": 1, "beast_trigger": true})
	legacy.update(0.3)
	canvas.controller = legacy
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var legacy_pixels: Array[Vector2] = purple_pixels(viewport.get_texture().get_image())
	var legacy_centre: Vector2 = Vector2.ZERO
	for point: Vector2 in legacy_pixels: legacy_centre += point
	if not legacy_pixels.is_empty(): legacy_centre /= float(legacy_pixels.size())
	var legacy_expected: Vector2 = Battle.project(Vector2(player.pos), float(player.height)) - Vector2(0.0, 12.0) + SHAKE
	check(legacy_pixels.size() == 4 and is_equal_approx(legacy_centre.x - legacy_expected.x, 128.0), "Rendered control reproduces the former128px mirror shift")
	check(legacy_centre.distance_to(legacy_expected) > 127.0, "Attachment assertion rejects the actual former mirrored-origin defect")
	measurements.append({"legacy_shift_control": true, "expected": [legacy_expected.x, legacy_expected.y], "rendered": [legacy_centre.x, legacy_centre.y], "error_pixels": legacy_centre.distance_to(legacy_expected)})
	viewport.free(); battle.free()
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements, "fixture_policy": "Only the controller atlas is replaced by symmetric pivot sentinels; actual controller draw, fixed projection, signed-width flip and existing canvas transform execute in Godot. This is an explicit presentation fixture, not gameplay review footage."}, "\t"))
		file.close()
	print("BEAST_RENDER_ATTACHMENT_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
