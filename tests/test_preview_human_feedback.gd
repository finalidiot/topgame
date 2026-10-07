extends SceneTree
## Actual imported alpha/composition centring and bounded presentation contracts.
const Preview = preload("res://scripts/top_preview.gd")
const FrontSkin = preload("res://scripts/front_end.gd")
const Parts = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: Array[String] = []
var images: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func pixels(path: String) -> Image:
	if not images.has(path):
		var texture: Texture2D = load(path)
		var image: Image = texture.get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		images[path] = image
	return images[path]
func independently_composed_union(preview: Control) -> Rect2:
	var bit: Image = pixels(Parts.texture_path("bit", preview.build.bit))
	var ratchet: Image = pixels(Parts.texture_path("ratchet", preview.build.ratchet))
	var blade_path: String = "res://assets/top/starters/%s_spin.png" % preview.identity if not preview.identity.is_empty() else "res://assets/top/parts/blades/%s_spin.png" % preview.build.blade
	var blade: Image = pixels(blade_path)
	var height: int = int(Parts.visual_height(preview.build))
	var union: Rect2 = Rect2()
	for index: int in range(8):
		var canvas: Image = Image.create(72, 88, false, Image.FORMAT_RGBA8)
		canvas.blend_rect(bit, Rect2i(0, 0, 48, 48), Vector2i(12, 24))
		canvas.blend_rect(ratchet, Rect2i(0, 0, 48, 48), Vector2i(12, 24))
		canvas.blend_rect(blade, Rect2i(index * 48, 0, 48, 48), Vector2i(12, 24 + height))
		var occupied: Rect2 = Rect2(canvas.get_used_rect())
		occupied.position -= Vector2(12, 24)
		union = union.merge(occupied) if union.has_area() else occupied
	return union
func test_assemblies() -> void:
	var preview: Control = Preview.new()
	preview.size = Vector2(220, 178)
	preview.animated = false
	for blade: String in Parts.PARTS.blade:
		for ratchet: String in Parts.PARTS.ratchet:
			for bit: String in Parts.PARTS.bit:
				preview.set_collection_build({"blade":blade, "ratchet":ratchet, "bit":bit})
				var geometry: Dictionary = preview.assembly_geometry()
				var actual: Rect2 = independently_composed_union(preview)
				check(geometry.bounds == actual, "Actual eight-frame alpha composition agrees with stable assembly bounds: " + blade + "/" + ratchet + "/" + bit)
				for scale_factor: float in [1.0, 2.0, 3.0, 4.0]:
					preview.preview_scale = scale_factor
					var placed: Vector2 = preview.preview_origin() + actual.get_center() * scale_factor
					check(absf(placed.x - preview.size.x * 0.5) <= 0.501 and absf(placed.y - preview.size.y * 0.5) <= 0.501, "Visible assembly centre is on the display at integer pixel scales: " + blade)
				check(geometry.height == Parts.visual_height(preview.build), "Preview centring retains the real stack height")
	for id: String in Starters.IDS:
		preview.set_collection_build(Starters.build_for(id))
		check(preview.identity == id and preview.assembly_geometry().blade_path == "res://assets/top/starters/%s_spin.png" % id, "Each starter keeps accepted authored enamel and source pixels: " + id)
		check(preview.assembly_geometry().bounds == independently_composed_union(preview), "Starter's actual assembled silhouette is centred as one composition: " + id)
	preview.free()
func test_ambient() -> void:
	var preview: Control = Preview.new()
	for id: String in ["breaker", "bastion"]:
		preview.identity = id
		var first: Array = preview.ambient_samples(0.35)
		var next: Array = preview.ambient_samples(0.45)
		check(first.size() == 1 and next.size() == 1, "Starter flecks use sparse finite emissions: " + id)
		check(float(next[0].alpha) < float(first[0].alpha), "Starter fleck fades as it leaves/is absorbed: " + id)
		check(float(next[0].radius) > float(first[0].radius) if id == "breaker" else float(next[0].radius) < float(first[0].radius), "Hot fragments go out; controlled blue flecks go in: " + id)
		check(preview.ambient_samples(0.0).is_empty() and preview.ambient_samples(2.3).is_empty(), "Ambient identity has actual quiet sections: " + id)
		for step: int in range(600):
			check(preview.ambient_samples(float(step) / 60.0).size() <= 2, "Analytic ambient budget stays bounded without accumulating nodes")
	preview.identity = "vane"
	check(preview.ambient_samples(0.4).is_empty(), "Vane retains its separate accepted orbit treatment")
	preview.free()
func test_skin() -> void:
	var theme: Theme = FrontSkin.make_theme()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style: StyleBox = theme.get_stylebox(state, "Button")
		check(style is StyleBoxTexture, "Menu button uses saved authored pixel caps: " + state)
		check(style.get_content_margin(SIDE_TOP) == 2 and style.get_content_margin(SIDE_BOTTOM) == 2, "Native button margins retain readable compact controls")
	check(FrontSkin.plate(Color.WHITE, Color.WHITE, 0) is StyleBoxFlat, "Thin combat meters keep their exact scalar fill geometry")
	check(FrontSkin.authored_style("inspection_frame", "INSPECTION") is StyleBoxTexture, "Structured ability inspection uses a distinct authored frame")
	var texture: Texture2D = load(FrontSkin.BACKGROUND_PATH)
	var background: Image = texture.get_image()
	for x: int in [28, 31, 130, 230, 254, 450, 618]:
		for y: int in [67, 72, 198, 251, 269, 290, 309, 321]:
			check(background.get_pixel(640 + x, y) == Color("141e27"), "Shared menu source has no display bay/corners or content-crossing divider")
func run() -> void:
	test_assemblies()
	test_ambient()
	test_skin()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var output: FileAccess = FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			assert(output != null)
			output.store_string(JSON.stringify({"checks":checks,"failures":failures,"assemblies":1089,"actual_alpha_composition":true,"no_save_or_gameplay_mutation":true}, "\t"))
			output.close()
	print("HUMAN_FEEDBACK_PREVIEW_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
