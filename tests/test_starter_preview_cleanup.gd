extends SceneTree
## Rendered regression: preview marks, accepted Vane and protected native art.
## Run with a real rendering driver; the headless dummy cannot read pixels.
const Preview = preload("res://scripts/top_preview.gd")
const Starters = preload("res://scripts/starters.gd")

class AssemblyOnlyPreview extends "res://scripts/top_preview.gd":
	func _draw_identity_motion(_origin: Vector2, _factor: float) -> void:
		pass

const PROTECTED_HASHES: Dictionary = {
	"res://assets/source-art/starter_blade_accents_002b1.aseprite":"b30e1f2ee67673d4811126f503d8058273ef9437f1232fd81ba6e5d2bcaefe7f",
	"res://assets/source-art/blade_rotation_family.aseprite":"7524341f88a0892c1d9010e7927e9d16862299ef38e61658929341cd3e2cf926",
	"res://assets/top/starters/breaker_spin.png":"ce81b4342f40bb15365ac39ae140b1bada7328718dfb9a0e114e83588a878406",
	"res://assets/top/starters/bastion_spin.png":"f304d6f0534397cbedc4da2bd05dd4830ab3e51bd51af7d0b06d7e355f680e0c",
	"res://assets/top/starters/vane_spin.png":"ff35b9f5e73f5d1a99989fb40c70e2dabeb8aab3ab176a0f5bb54aab6c22fd94"
}
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func fixture(id: String, clock: float, animated: bool, assembly_only: bool, ceremony: bool = false) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(300,180) if ceremony else Vector2i(192,144)
	viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var preview: Control=AssemblyOnlyPreview.new() if assembly_only else Preview.new()
	preview.size=Vector2(170,138) if ceremony else Vector2(192,144)
	preview.position=Vector2(65,20) if ceremony else Vector2.ZERO
	viewport.add_child(preview)
	var starter: Dictionary=Starters.get_starter(id)
	preview.set_build(starter.assembly)
	preview.set_identity(id,starter.accent)
	preview.animated=animated
	preview.preview_scale=4.0 if ceremony else 3.0
	preview.set_process(false)
	preview._clock=clock
	preview.queue_redraw()
	check(preview.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"Preview retains native nearest filtering")
	check(preview.build==Starters.build_for(id),"Rendering preserves the exact legal assembly")
	return viewport

func test_native_ceremony_containment() -> void:
	# The real ceremony owns a 170x138 preview at 4x inside a 192px card. The
	# original larger fixture alone failed to catch neighbouring-card leaks.
	var preview_area: Rect2i = Rect2i(65,20,170,138)
	var card_area: Rect2i = Rect2i(54,0,192,180)
	for id: String in ["breaker", "bastion"]:
		var total_visible: int = 0
		for clock: float in [0.0,0.32,0.35,0.4,0.6,0.7,1.1,1.4,1.45,1.6,1.98,2.7,3.12,3.51,3.96,4.2]:
			var actual: SubViewport = fixture(id,clock,true,false,true)
			var assembly: SubViewport = fixture(id,clock,true,true,true)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var image: Image = actual.get_texture().get_image()
			var body: Image = assembly.get_texture().get_image()
			check(image.get_size()==Vector2i(300,180) and body.get_size()==Vector2i(300,180),"Ceremony regression reads actual native rendered pixels")
			var outside_preview: int = 0
			var outside_card: int = 0
			for y: int in range(image.get_height()):
				for x: int in range(image.get_width()):
					if image.get_pixel(x,y)==body.get_pixel(x,y): continue
					total_visible += 1
					if not preview_area.has_point(Vector2i(x,y)): outside_preview += 1
					if not card_area.has_point(Vector2i(x,y)): outside_card += 1
			check(outside_preview==0,"New %s ambient flecks stay inside their actual 170px ceremony preview at %.2f" % [id,clock])
			check(outside_card==0,"New %s flecks never enter neighbouring machine cards at%.2f" % [id,clock])
			actual.free()
			assembly.free()
		check(total_visible>0,"Containment preserves visible intentional %s ambient identity" % id)

func run() -> void:
	for path: String in PROTECTED_HASHES:
		check(FileAccess.get_sha256(path)==PROTECTED_HASHES[path],"Accepted native source/runtime bytes are preserved: "+path)
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/top/starters/manifest.json"))
	check(metadata is Dictionary and int(metadata.cell[0])==48 and int(metadata.cell[1])==48 and int(metadata.pivot[0])==24 and int(metadata.pivot[1])==40,"Starter native cell and physical contact pivot are preserved")
	for id: String in Starters.IDS:
		var texture: Texture2D=load("res://assets/top/starters/%s_spin.png"%id)
		check(texture!=null and texture.get_size()==Vector2(384,48),"All eight native spin keys load: "+id)
		for animated: bool in [false,true]:
			for clock: float in [0.0,0.37,1.1]:
				var actual: SubViewport=fixture(id,clock,animated,false)
				var assembly: SubViewport=fixture(id,clock,animated,true)
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var image: Image=actual.get_texture().get_image()
				var body: Image=assembly.get_texture().get_image()
				check(image.get_size()==Vector2i(192,144) and body.get_size()==Vector2i(192,144),"The regression reads actual rendered pixels")
				if image.get_size()==Vector2i(192,144) and body.get_size()==Vector2i(192,144):
					var same: bool=image.get_data()==body.get_data()
					if id=="vane":
						# The accepted clock1.1 orbit lies behind the opaque assembly.
						# Clocks0/.37 expose it beside the rig; both states are legitimate.
						check(not same if clock<1.0 else same,"Vane retains visible orbit dots and normal opaque occlusion (%.2f animated=%s)"%[clock,str(animated)])
					else:
						var preview: Control = actual.get_child(0)
						var emitted: Array[Dictionary] = preview.ambient_samples(clock)
						check(same if emitted.is_empty() else not same,"Intentional bounded %s flecks appear only during authored sparse emission windows (%.2f animated=%s)"%[id,clock,str(animated)])
				actual.free()
				assembly.free()
	await test_native_ceremony_containment()
	print("STARTER_PREVIEW_CLEANUP_%s checks=%d failures=%d"%["PASS" if failures==0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
