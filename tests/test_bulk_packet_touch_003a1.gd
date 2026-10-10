extends SceneTree
## Mapped root-screen touch events against actual centred native packet UI.
## Receipts are declared presentation fixtures. No Main/save/wallet is opened.
const Menus = preload("res://scripts/menus.gd")
const Economy = preload("res://scripts/packet_economy.gd")
const OLD_SEAM = Rect2(222, 72, 196, 205)
const BATCH_BENCH = Rect2(100, 72, 440, 205)
var menus: Control
var checks: int = 0
var failures: Array[String] = []
var actions: Array[Dictionary] = []
var observations: Array[Dictionary] = []
var settled_count: int = 0
var report: String = ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func settle() -> void:
	await process_frame
	await process_frame

func fixture(quantity: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7341
	var roll: Dictionary = Economy.generate_batch("standard", quantity, [], rng)
	var receipt: Dictionary = {"id":"packet-1", "request_nonce":"packet-1", "kind":"standard", "currency":"credits",
		"cost":Economy.packet_cost("standard") * quantity, "status":"pending", "rows":roll.rows,
		"total_salvage":roll.total_salvage, "quantity":quantity, "packets":roll.packets, "cursor":0}
	menus.show_packet_open(receipt, {"credits":1000, "salvage":0})
	menus._packet_view.set_process(false)
	menus._packet_view.settled.connect(func() -> void: settled_count += 1)
	await settle()
	actions.clear()
	settled_count = 0
	check(menus._content.position == Vector2(80,60), "Packet menu retains centred native origin")
	check(menus._packet_view.phase == "SEALED" and not menus._packet_view.opening, "Declared packet fixture starts sealed")

func touch(local: Vector2, pressed: bool, index: int = 4, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = menus._content.get_global_transform_with_canvas() * local
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	await settle()

func drag(local: Vector2, index: int = 4) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = menus._content.get_global_transform_with_canvas() * local
	Input.parse_input_event(event)
	await settle()

func count_action(name: String) -> int:
	var count: int = 0
	for row: Dictionary in actions:
		if row.name == name: count += 1
	return count

func opening_case(quantity: int, start: Vector2, direction: float, name: String) -> void:
	await fixture(quantity)
	var receipt_before: Dictionary = menus._packet_receipt.duplicate(true)
	await touch(start, true)
	var acquired: bool = menus._packet_touch_index == 4
	observations.append({"case":name,"quantity":quantity,"local_point":start,"root_point":start+Vector2(80,60),
		"old_seam_contains":OLD_SEAM.has_point(start),"batch_bench_contains":BATCH_BENCH.has_point(start),"acquired":acquired})
	check(acquired, name+": the visible pouch acquires its own touch")
	if not acquired:
		await touch(start, false)
		return
	check(menus._packet_touch_origin == start, name+": root-screen point converts exactly to native menu point")
	await drag(start+Vector2(41.5*direction,0))
	check(count_action("packet_tear") == 0 and not menus._packet_view.opening, name+": below42 native pixels does not tear")
	await drag(start+Vector2(42.0*direction,0))
	check(count_action("packet_tear") == 1 and menus._packet_view.opening, name+": exactly42 native pixels tears once")
	check(menus._packet_touch_index == -1, name+": opening consumes the gesture owner")
	await drag(start+Vector2(95.0*direction,0))
	await touch(start+Vector2(95.0*direction,0), false)
	check(count_action("packet_tear") == 1, name+": subsequent drag/release cannot tear twice")
	menus._packet_view._process(8.0)
	await settle()
	check(menus._packet_view.phase == "RESULT" and settled_count == 1, name+": actual packet timeline settles exactly once")
	check(menus._packet_controls.size() == 4, name+": one result control row is created")
	await touch(start, true)
	await drag(start+Vector2(80,0))
	await touch(start, false)
	menus.skip_packet()
	menus._packet_view._process(8.0)
	await settle()
	check(count_action("packet_tear") == 1 and settled_count == 1 and menus._packet_controls.size() == 4, name+": result touch/skip cannot double-finish")
	check(menus._packet_receipt == receipt_before, name+": touch presentation preserves immutable paid rows")

func rejected_case(quantity: int, start: Vector2, name: String) -> void:
	await fixture(quantity)
	await touch(start, true)
	check(menus._packet_touch_index == -1, name+": outside acquisition region does not own touch")
	await drag(start+Vector2(70,0))
	await touch(start, false)
	check(count_action("packet_tear") == 0 and not menus._packet_view.opening, name+": outside drag cannot open a packet")

func release_cases() -> void:
	await fixture(5)
	var start := Vector2(320,180)
	await touch(start, true)
	await touch(start, false, 9)
	check(menus._packet_touch_index == 4, "Another finger release does not discard acquired packet touch")
	await drag(start+Vector2(80,0), 9)
	check(count_action("packet_tear") == 0, "Another finger cannot tear acquired packet")
	await touch(start, false)
	check(menus._packet_touch_index == -1, "Matching release clears packet gesture")
	await drag(start+Vector2(80,0))
	check(count_action("packet_tear") == 0, "Drag after release cannot tear")
	await touch(start, true)
	await touch(start, false, 4, true)
	check(menus._packet_touch_index == -1, "Canceled release clears packet gesture")
	await drag(start+Vector2(80,0))
	check(count_action("packet_tear") == 0, "Drag after cancellation cannot tear")
	await touch(start, true)
	menus.show_help()
	await settle()
	check(menus._packet_touch_index == -1, "Changing menu clears unfinished packet gesture")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	if not report.is_empty() and (not report.is_absolute_path() or not (report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/") or report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/")) or FileAccess.file_exists(report)):
		quit(2); return
	root.size = Vector2i(800,480)
	root.content_scale_size = Vector2i(800,480)
	Input.use_accumulated_input = false
	menus = Menus.new()
	root.add_child(menus)
	menus.set_process(false)
	menus.action.connect(func(name: String, value: Variant) -> void:
		actions.append({"name":name,"value":value})
		if name == "packet_tear": menus.tear_packet())
	await settle()
	await opening_case(1,Vector2(320,180),1,"x1 rightward original seam")
	await opening_case(1,Vector2(222,180),-1,"x1 inclusive original left boundary")
	for point: Vector2 in [Vector2(221.5,180),Vector2(418,180),Vector2(320,71.5),Vector2(320,277)]:
		await rejected_case(1,point,"x1 original bounds "+str(point))
	for row: Array in [[3,Vector2(206,190),-1,"x3 outer left pouch"],[3,Vector2(434,190),1,"x3 outer right pouch"],
		[5,Vector2(156,190),-1,"x5 outer left pouch"],[5,Vector2(484,190),1,"x5 outer right pouch"]]:
		await opening_case(row[0],row[1],row[2],row[3])
	for quantity: int in [3,5]:
		await rejected_case(quantity,Vector2(99.5,180),"x%d outside batch left" % quantity)
		await rejected_case(quantity,Vector2(540,180),"x%d outside batch right" % quantity)
	await release_cases()
	var data: Dictionary = {"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations,
		"scope":"Production Menus + PacketView, mapped root-screen touch/drag events. Declared packet receipts are presentation fixtures; no Main, player saves, ownership or wallets opened.",
		"expected_regions":{"x1":"Rect2(222,72,196,205)","x3_x5":"Rect2(100,72,440,205)","native_threshold":42,"root_origin":[80,60]},
		"physical_android_acceptance":false}
	if not report.is_empty():
		var file := FileAccess.open(report,FileAccess.WRITE)
		file.store_string(JSON.stringify(data,"\t"))
		file.close()
	print("BULK_PACKET_TOUCH_%s checks=%d failures=%d" % [data.status.to_upper(),checks,failures.size()])
	menus.free()
	quit(0 if failures.is_empty() else 1)
