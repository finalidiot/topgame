extends SceneTree
## Declared immutable packet receipts; actual viewport/root touch ingress.
## Paid transactions are covered by frontend_interactions separately.
const Menus=preload("res://scripts/menus.gd")
const Economy=preload("res://scripts/packet_economy.gd")
const Combat=preload("res://scripts/combat_hud_layout.gd")
var menus:Control
var checks:int=0
var failures:Array[String]=[]
var actions:Array=[]
var observations:Array=[]
var report:String=""
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func settle()->void:
	await process_frame;await process_frame
func point(local:Vector2)->Vector2:
	return root.get_final_transform()*menus._packet_view.get_global_transform_with_canvas()*local
func touch(local:Vector2,pressed:bool,index:int=4,canceled:bool=false)->void:
	var event:=InputEventScreenTouch.new()
	event.position=point(local);event.index=index;event.pressed=pressed;event.canceled=canceled
	root.push_input(event,false);await settle()
func drag(local:Vector2,index:int=4)->void:
	var event:=InputEventScreenDrag.new()
	event.position=point(local);event.index=index
	root.push_input(event,false);await settle()
func fixture(quantity:int)->void:
	var rng:=RandomNumberGenerator.new();rng.seed=7341
	var rolled:Dictionary=Economy.generate_batch("standard",quantity,[],rng)
	var receipt:Dictionary={"id":"read_only_touch_fixture","request_nonce":"read_only_touch_fixture","kind":"standard","currency":"credits","cost":Economy.packet_cost("standard")*quantity,"status":"pending","quantity":quantity,"cursor":0,"rows":rolled.rows,"packets":rolled.packets,"total_salvage":rolled.total_salvage}
	menus.show_packet_open(receipt,{"credits":1000,"salvage":0})
	menus._packet_view.set_process(false);await settle();actions.clear()
	check(menus._packet_view.phase=="SEALED" and not menus._packet_view.opening,"Actual declared packet starts sealed")
func cases(label:String)->void:
	for quantity:int in [1,3,5]:
		await fixture(quantity)
		var sealed:Dictionary=menus._packet_receipt.duplicate(true)
		var start:Vector2=Vector2(320,180)
		await touch(start,true)
		check(menus._packet_touch_index==4 and menus._packet_touch_origin.is_equal_approx(start),label+": actual PacketView transform acquires native pouch")
		await drag(start+Vector2(41.5,0))
		check(actions.is_empty() and not menus._packet_view.opening,label+": below42 native pixels cannot tear")
		await drag(start+Vector2(42.0,0))
		check(actions.count("packet_tear")==1 and menus._packet_view.opening,label+": crossing42 native pixels tears once")
		check(menus._packet_touch_index==-1,label+": tear consumes finger ownership")
		await drag(start+Vector2(80,0));await touch(start,false)
		check(actions.count("packet_tear")==1 and menus._packet_receipt==sealed,label+": drag/release cannot repeat or mutate paid rows")
		observations.append({"label":label,"quantity":quantity,"presentation":menus.presentation_snapshot(),"packet_transform":menus._packet_view.get_global_transform_with_canvas(),"viewport_final_transform":root.get_final_transform(),"physical_start":point(start)})
	await fixture(1)
	await touch(Vector2(222,180),true)
	check(menus._packet_touch_index==4,"Single pouch includes exact native left boundary")
	await touch(Vector2(222,180),false)
	await touch(Vector2(418,180),true)
	check(menus._packet_touch_index==-1,"Single pouch excludes exact native right boundary")
	await touch(Vector2(418,180),false)
	await touch(Vector2(200,180),true);await drag(Vector2(280,180));await touch(Vector2(200,180),false)
	check(actions.is_empty() and menus._packet_touch_index==-1,"Outside single pouch cannot own/tear")
	await fixture(5)
	await touch(Vector2(90,180),true);await drag(Vector2(170,180));await touch(Vector2(90,180),false)
	check(actions.is_empty() and menus._packet_touch_index==-1,"Outside batch bench cannot own/tear")
	await touch(Vector2(320,180),true)
	await drag(Vector2(400,180),9);await touch(Vector2(320,180),false,9)
	check(menus._packet_touch_index==4 and actions.is_empty(),"Different finger cannot tear or release acquired pouch")
	await touch(Vector2(320,180),false)
	await drag(Vector2(400,180))
	check(actions.is_empty() and menus._packet_touch_index==-1,"Matching release retires packet gesture")
	await touch(Vector2(320,180),true);await touch(Vector2(320,180),false,4,true);await drag(Vector2(400,180))
	check(actions.is_empty() and menus._packet_touch_index==-1,"Canceled contact cannot later tear")
	await touch(Vector2(320,180),true)
	var packet_id:int=menus._packet_view.get_instance_id()
	var receipt_before:Dictionary=menus._packet_receipt.duplicate(true)
	var canvas:Vector2=menus._presentation_canvas
	menus.set_presentation_canvas(canvas-Vector2(24,12),menus._presentation_safe);await settle()
	check(menus._packet_view.get_instance_id()==packet_id and menus._packet_receipt==receipt_before and menus._packet_touch_index==4,"Resize preserves real packet/receipt and native gesture ownership")
	await drag(Vector2(362.25,180));await touch(Vector2(362.25,180),false)
	check(actions.count("packet_tear")==1 and menus._packet_view.opening,"Held gesture resolves correctly through resized component transform")
	menus.set_presentation_canvas(canvas,menus._presentation_safe)
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
	if not report.is_empty() and (not report.is_absolute_path() or not report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/") or FileAccess.file_exists(report)):quit(2);return
	Input.use_accumulated_input=false
	menus=Menus.new();root.add_child(menus);menus.set_process(false)
	menus.action.connect(func(intent:String,_payload:Variant)->void:
		actions.append(intent)
		if intent=="packet_tear":menus.tear_packet())
	await settle()
	for physical:Vector2i in [Vector2i(800,480),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=physical
		var canvas:Vector2=Vector2(physical)/(1.5 if physical.x==2560 else 1.0)
		root.content_scale_size=Vector2i(canvas);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		menus.mobile_hud=false;menus.set_presentation_canvas(canvas);await cases("desktop "+str(physical))
	root.size=Vector2i(2400,960);root.content_scale_size=Vector2i(1200,480)
	var safe:Rect2=Rect2(56,18,1088,444)
	menus.mobile_hud=true;menus.set_presentation_canvas(Vector2(1200,480),safe);await cases("preserved mobile safe")
	var accepted:Dictionary=Combat.responsive(Vector2(1200,480),true,safe)
	check(menus._content.position==accepted.menu_origin and menus._content.scale==Vector2.ONE*accepted.menu_scale,"Mobile packet retains accepted centered uniform transform")
	if not report.is_empty():
		var file:=FileAccess.open(report,FileAccess.WRITE)
		check(file!=null,"Fresh external packet-touch report opens")
		if file!=null:file.store_string(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"observations":observations,"scope":"Root coordinate synthetic touch/drag through actual PacketView and viewport transforms; declared immutable receipts; no player/save/ownership/transaction writes or physical Android acceptance"},"\t"));file.close()
	print("FRONTEND_PACKET_TOUCH_003A2_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	menus.free();quit(0 if failures.is_empty() else 1)
