extends SceneTree
## Frame-by-frame actual PacketView, declared immutable receipts, no transactions.
## Normal 60 Hz presentation clocks; separate held-confirm acceleration cases.
const Menus = preload("res://scripts/menus.gd")
var menus: Control
var report: String = ""
var frames: String = ""
var records: Array[Dictionary] = []
var images: Array[Dictionary] = []
var checks: int = 0
var failures: Array[String] = []
var extent: Vector2i = Vector2i(1280,720)
var mobile: bool = false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func settle() -> void:
	for tick: int in range(4): await process_frame
func receipt(kind: String, quantity: int) -> Dictionary:
	var rows: Array = []
	for index: int in range(quantity):
		for category: String in ["blade","ratchet","bit"]:
			var id: String = {"blade":"lopsider","ratchet":"flywheel","bit":"needle"}[category]
			rows.append({"category":category,"id":id,"new":true,"rarity":"RARE","salvage":0})
	return {"kind":kind,"quantity":quantity,"cursor":0,"rows":rows,"currency":"credits" if kind=="standard" else "salvage","credit_cost":0,"salvage_cost":0,"total_salvage":0}
func image(name: String) -> void:
	if frames.is_empty(): return
	await RenderingServer.frame_post_draw
	var target: String = frames.path_join(name+".png")
	var pixels: Image = root.get_texture().get_image()
	check(not FileAccess.file_exists(target) and pixels.save_png(target) == OK,"Fresh packet frame "+name)
	images.append({"name":name,"path":target,"sha256":FileAccess.get_sha256(target)})
func capture_case(kind: String, quantity: int, accelerated: bool, fast: bool) -> void:
	var label: String = "%s_x%d_%s" % [kind,quantity,"fast" if fast else ("accelerated" if accelerated else "normal")]
	var fixed: Dictionary=receipt(kind,quantity)
	menus.show_packet_open(fixed,{"credits":0,"salvage":0}); await settle()
	var view: Control = menus._packet_view
	view.set_process(false)
	view.elapsed=0; view.phase="SEALED"; view.queue_redraw(); await settle()
	await image(label+"_sealed")
	for tick: int in range(34): view._process(1.0/60.0)
	await image(label+"_crinkle")
	if fast:
		menus.skip_packet(); await settle(); await image(label+"_result")
		check(view.phase=="RESULT" and menus._packet_receipt==fixed,"Fast open resolves only the declared saved receipt")
		return
	menus.tear_packet()
	if accelerated: Input.action_press("ui_accept")
	for tick: int in range(220):
		view._process(1.0/60.0)
		var frame: int = view._frame_range(int(view._metadata.tags.TEAR_START.from),int(view._metadata.tags.TEAR_OPEN.to),view.elapsed)
		var tag: String = view.phase
		if view.phase=="TEAR": tag="TEAR_START" if frame<=int(view._metadata.tags.TEAR_START.to) else "TEAR_OPEN"
		records.append({"case":label,"tick":tick,"elapsed":view.elapsed,"phase":view.phase,"first_packet_tear_frame":frame,"tag":tag,"cursor":view._cursor,"receipt":menus._packet_receipt})
		# Every actual native render tick is recorded, including all tear atlas
		# transitions. The clock is driven explicitly to isolate presentation.
		view.queue_redraw()
		await process_frame
		await image(label+"_%03d"%tick)
		if view.phase=="RESULT": break
	if accelerated: Input.action_release("ui_accept")
	check(view.phase=="RESULT" and view._cursor==quantity and menus._packet_receipt==fixed,"Frame sequence settles exact receipt without debit or reward changes: "+label)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
		if arg.begins_with("--frames="): frames=arg.trim_prefix("--frames=")
		if arg.begins_with("--width="): extent.x=int(arg.trim_prefix("--width="))
		if arg.begins_with("--height="): extent.y=int(arg.trim_prefix("--height="))
		if arg=="--mobile": mobile=true
	if not report.is_absolute_path() or FileAccess.file_exists(report) or frames.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(frames)
	root.size=extent; root.content_scale_size=root.size
	menus=Menus.new(); root.add_child(menus); menus.mobile_hud=mobile
	menus.set_presentation_canvas(Vector2(extent),Rect2(56,18,extent.x-112,extent.y-36) if mobile else Rect2())
	await settle()
	for kind: String in ["standard","reclaimed"]:
		for quantity: int in [1,3]:
			await capture_case(kind,quantity,false,false)
			await capture_case(kind,quantity,true,false)
			await capture_case(kind,quantity,false,true)
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":images,"ticks":records,"extent":extent,"mobile_policy":mobile,"layout":menus.presentation_snapshot(),"packet_script_sha256":FileAccess.get_sha256(ProjectSettings.globalize_path("res://scripts/packet_view.gd")),"scope":"Full actual responsive Menus.show_packet_open page, background, viewport and atlas at every 60 Hz presentation tick. Immutable declared result receipts; no purchase/RNG/save or rewards invoked. Acceleration is a separate held-confirm synthetic fixture. Mobile policy is a Windows viewport simulation. No supplied defect screenshot exists in this request; visual root-cause conclusions require inspecting these native frames."},"\t")); file.close()
	print("PACKET_PHASES_003A2_%s checks=%d frames=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,images.size()])
	menus.free(); quit(0 if failures.is_empty() else 1)
