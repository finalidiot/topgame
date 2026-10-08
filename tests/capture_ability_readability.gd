extends SceneTree
## Native production inspection panels; explicit state fixtures, no profile open.
const Inspector = preload("res://scripts/ability_inspection.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const Catalog = preload("res://scripts/run_powers.gd")
var frames: String = ""
var output: String = ""
var captured: Array[Dictionary] = []
var canvas: Control
var panel: Control
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="): frames = arg.trim_prefix("--frames=")
		if arg.begins_with("--manifest="): output = arg.trim_prefix("--manifest=")
	if frames.is_empty() or output.is_empty(): push_error("Fresh external frames and manifest required"); quit(2); return
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	DirAccess.make_dir_recursive_absolute(frames)
	canvas = Control.new()
	canvas.size = Vector2(640, 360)
	root.add_child(canvas)
	var background: ColorRect = ColorRect.new()
	background.size = canvas.size
	background.color = FrontEnd.INK
	canvas.add_child(background)
	panel = Inspector.new()
	panel.position = Vector2(226, 59)
	panel.size = Vector2(188, 242)
	canvas.add_child(panel)
	for id: String in ["dead_centre", "orbit_drive", "redline", "impact_sink", "anchor_exchange", "impact_wake", "high_gear"]:
		panel.inspect(id, 1)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image = root.get_texture().get_image()
		if pixels.get_size() != Vector2i(640, 360): push_error("Native capture size mismatch"); quit(2); return
		var path: String = frames.path_join(id + ".png")
		if FileAccess.file_exists(path) or pixels.save_png(path) != OK: push_error("Refuse missing/overwritten capture"); quit(2); return
		captured.append({"power":id, "rank":1, "path":path, "panel_rect":[226,59,188,242], "viewport":[640,360], "reading":panel.breakdown})
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"images":captured, "scope":"Actual production 188x242 inspection controls at native640x360, Rank I descriptions. UI presentation fixture; no gameplay, collection or device-acceptance claim.", "failures":[]}, "\t"))
	file.close()
	print("ABILITY_READABILITY_CAPTURE_PASS images=%d" % captured.size())
	quit(0)
