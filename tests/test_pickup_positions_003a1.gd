extends SceneTree
## Explicit position fixtures expose world-contact, visible-rig and capacity
## failures independently. No Main, CollectionStore or player save is opened.
const Battle = preload("res://scripts/battle.gd")
const Run = preload("res://scripts/run_context.gd")
const Pickups = preload("res://scripts/run_pickups.gd")
const Catalog = preload("res://scripts/parts.gd")
const POINTS: Array[Vector2] = [Vector2(-65,0),Vector2(65,0),Vector2(0,65),Vector2(0,-65),Vector2(95,-35),Vector2(-95,35),Vector2(35,95),Vector2(-35,-95)]
const BUILD: Dictionary = {"blade":"guard","ratchet":"mid","bit":"ball"}
class ProbeBattle:
	extends Battle
	func _check_result() -> void: pass # Isolated route fixture, no opponent/result.
var rows: Array[Dictionary] = []
var checks: int = 0
var failures: Array[String] = []
var report_path: String = ""
var baseline: bool = false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);push_error(message)
static func portable(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Rect2 or value is Rect2i: return [value.position.x,value.position.y,value.size.x,value.size.y]
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value: out[str(key)]=portable(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value: out.append(portable(item))
		return out
	return value
func fixture(point: Vector2, start: Vector2, full: bool=false) -> Dictionary:
	var run_context: RefCounted = Run.new();run_context.start(BUILD,421,"bastion")
	check(run_context.choose_power(run_context.pending_draft_id,run_context.pending_offer[0]),"Legal starting draft")
	if full: run_context.reroll_charges=Run.MAX_REROLLS
	var b: Node2D = ProbeBattle.new();root.add_child(b);b.set_physics_process(false)
	b.begin_run(BUILD,run_context.current_encounter(),421)
	b.battle_status="battle";b.elapsed=1.0;b.player_entity().pos=start;b.player_entity().height=0.0
	b.player_entity().vel=Vector2.ZERO;b.player_entity().wobble=0.0
	var tokens: Node2D = Pickups.new();b.add_child(tokens);tokens.set_process(false);tokens.set_physics_process(false);tokens.setup(b,run_context)
	tokens.render_in_battle=true;b.floor_pickups=tokens
	tokens.items.append({"id":"probe/%d"%rows.size(),"pos":point,"born":1.0})
	return {"battle":b,"run":run_context,"tokens":tokens}
static func rig_bounds(b: Node2D, position_world: Vector2) -> Rect2:
	# Exact native guard blade opaque bounds (7,18)-(42,38), origin (24,40).
	# Static grounded fixture has no velocity lean, wobble, recovery or lift.
	return Rect2(Battle.project(position_world).round()+Vector2(-17,-22),Vector2(35,20))
func path_case(point: Vector2, name: String, direction: Vector2, offset: Vector2=Vector2.ZERO, full: bool=false) -> void:
	var start: Vector2 = point+offset-direction*45.0
	var finish: Vector2 = point+offset+direction*45.0
	var f: Dictionary = fixture(point,start,full)
	var path: Array[Vector2] = [start]
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point,start,finish)
	var token_bounds: Rect2 = Rect2(Battle.project(point).round()+Vector2(-9,-9),Vector2(19,15))
	var overlap_area: float = 0.0
	var overlap_position: Vector2 = closest
	for tick: int in range(1,61):
		var position_world: Vector2 = start.lerp(finish,float(tick)/60.0)
		path.append(position_world)
		var intersection: Rect2 = rig_bounds(f.battle,position_world).intersection(token_bounds)
		if intersection.has_area() and intersection.get_area()>overlap_area:
			overlap_area=intersection.get_area();overlap_position=position_world
		f.battle.player_entity().pos=position_world;f.battle.elapsed+=Battle.FIXED_DT;f.tokens.update_simulation()
	var row: Dictionary = {"point_index":POINTS.find(point),"case":name,"pickup_world":point,"pickup_projected":Battle.project(point).round(),
		"pickup_visible_bounds":token_bounds,"player_world_path":path,"closest_world_sweep":closest,"world_collection_distance":closest.distance_to(point),
		"maximum_visible_overlap_area":overlap_area,"visible_overlap_player_world":overlap_position,"visible_overlap_player_projected":Battle.project(overlap_position).round(),
		"visible_overlap_player_bounds":rig_bounds(f.battle,overlap_position),"collected":f.run.rerolls_collected>0,"remaining_items":f.tokens.items.size(),
		"initial_rerolls":Run.MAX_REROLLS if full else Run.STARTING_REROLLS,"final_rerolls":f.run.reroll_charges,"status":f.battle.battle_status,"height":0.0,
		"fixture":"Every segment is supplied world motion; production collector and projection, native asset alpha bounds, no solver/input claim"}
	rows.append(row)
	if not baseline:
		if full: check(f.tokens.items.is_empty() and f.run.rerolls_collected==0,"Full capacity cannot leave a fake visible pickup at %s"%point)
		else: check(row.collected,"Every %s path collects at %s"%[name,point])
		check(f.run.rerolls_collected<=1,"One id pays at most once")
	f.battle.free()
static func route_input(b: Node2D, target: Vector2) -> Vector2:
	var p: Dictionary = b.player_entity()
	var desired: Vector2 = ((target-Vector2(p.pos))*3.0-Vector2(p.vel)*1.3).limit_length(100.0)/100.0
	return Vector2(desired.x-desired.y,(desired.x+desired.y)*0.5).limit_length(1.0)
func cadence_case() -> void:
	var point: Vector2 = Vector2(65,0)
	var f: Dictionary = fixture(point,Vector2(20,0))
	f.battle.continuous=null;f.battle.player_entity().powers=[];f.battle.player_entity().power_ranks={}
	for fighter: Dictionary in f.battle.fighters:
		if fighter.entity_id!=f.battle.player_entity_id: fighter.outcome="fixture_retired"
	var path: Array[Vector2] = [f.battle.player_entity().pos]
	var nearest: float = INF
	for tick: int in range(360):
		var target: Vector2 = Vector2(110,0) if tick<180 else Vector2(20,0)
		f.battle.test_step(Battle.FIXED_DT,route_input(f.battle,target))
		path.append(f.battle.player_entity().pos)
		nearest=minf(nearest,Vector2(f.battle.player_entity().pos).distance_to(point))
	# No render process ran during the actual out-and-back solver path. A final
	# render-only chord sees only the start/end; fixed ticks saw real crossings.
	f.tokens.update_simulation()
	var chord: Vector2 = Geometry2D.get_closest_point_to_segment(point,path[0],path[-1])
	rows.append({"case":"out_and_back_without_render_process","point_index":1,"pickup_world":point,"pickup_projected":Battle.project(point),
		"pickup_visible_bounds":Rect2(Battle.project(point).round()+Vector2(-9,-9),Vector2(19,15)),"player_world_path":path,
		"closest_world_sweep":chord,"world_collection_distance":chord.distance_to(point),"nearest_actual_fixed_tick_distance":nearest,
		"collected":f.run.rerolls_collected==1,"remaining_items":f.tokens.items.size(),"physics_ticks":360,"render_updates":1,
		"fixture":"Actual fixed solver and waypoint steering; isolated opponent retired/result suppressed; no position/reserve rewrites within path"})
	check(nearest<5.0 and chord.distance_to(point)>30.0,"Curved/out-and-back route crosses the chip but the render-only chord does not")
	if not baseline:check(f.run.rerolls_collected==1,"Fixed tick observation collects without render-process updates")
	f.battle.free()
func lifecycle_cases() -> void:
	var f: Dictionary = fixture(Vector2(65,0),Vector2.ZERO)
	var snapshot: Dictionary = f.tokens.presentation_snapshot()
	f.battle.paused=true;f.battle.test_step(0.25,Vector2.RIGHT);f.tokens.update_simulation()
	check(f.tokens.presentation_snapshot()==snapshot and f.run.rerolls_collected==0,"Pause freezes age and receipt")
	f.battle.paused=false;f.battle.begin_reentry(1.25)
	for tick: int in range(75):f.battle.test_step(Battle.FIXED_DT,Vector2.RIGHT);f.tokens.update_simulation()
	check(f.tokens.presentation_snapshot()==snapshot and f.run.rerolls_collected==0,"READY drains real fixed ticks without pickup age or collection")
	# Observe a repositioned paused fixture and ensure it cannot create a ghost
	# sweep upon resume. Production READY does not reposition the live rig.
	f.battle.paused=true;f.battle.player_entity().pos=Vector2(110,0);f.tokens.update_simulation()
	f.battle.paused=false;f.battle.elapsed+=Battle.FIXED_DT;f.tokens.update_simulation()
	check(f.run.rerolls_collected==0,"Paused reposition cannot collect across a stale previous-position segment")
	f.battle.player_entity().height=20.0;f.battle.player_entity().pos=Vector2(65,0)
	f.battle.elapsed+=Battle.FIXED_DT;f.tokens.update_simulation()
	check(f.run.rerolls_collected==0,"Genuinely airborne player cannot collect a floor chip through projected overlap")
	f.battle.player_entity().height=0.0;f.battle.elapsed+=Battle.FIXED_DT;f.tokens.update_simulation()
	check(f.run.rerolls_collected==1,"Grounded landing at the actual chip collects")
	var receipt_id: String = str(f.tokens.presentation_snapshot().collection_flairs[0].id)
	f.tokens.items.append({"id":receipt_id,"pos":Vector2(65,0),"born":f.battle.elapsed})
	f.battle.elapsed+=Battle.FIXED_DT;f.tokens.update_simulation();f.tokens.update_simulation()
	check(f.run.rerolls_collected==1 and f.tokens.presentation_snapshot().collection_flairs.size()==1,"Duplicate receipt and duplicate tick cannot duplicate payment/flair")
	f.battle.elapsed+=Pickups.LIFETIME;f.tokens.update_simulation()
	check(f.tokens.items.is_empty() and f.tokens.expired_count==1,"Rejected duplicate still expires with no extra receipt")
	f.battle.free()
	f=fixture(Vector2(65,0),Vector2.ZERO)
	f.battle.elapsed=1.0+Pickups.LIFETIME;f.battle.player_entity().pos=Vector2(65,0);f.tokens.update_simulation()
	check(f.tokens.items.is_empty() and f.run.rerolls_collected==0 and f.tokens.expired_count==1,"Expiry wins against contact on its exact tick")
	f.battle.free()
	f=fixture(Vector2(65,0),Vector2(20,0))
	f.run.reroll_charges=Run.MAX_REROLLS-1
	f.tokens.items.append({"id":"capacity/second","pos":Vector2(65,0),"born":1.0})
	f.battle.elapsed+=Battle.FIXED_DT;f.battle.player_entity().pos=Vector2(65,0);f.tokens.update_simulation()
	check(f.tokens.items.is_empty() and f.run.rerolls_collected==1 and f.run.reroll_charges==Run.MAX_REROLLS,"Last capacity slot pays once and suppresses other impossible drop in the same tick")
	check(f.tokens.capacity_suppressed_count==1 and f.tokens.expired_count==0,"Capacity suppression is distinguished from expiry and collection")
	f.battle.continuous.threats_cleared=1
	f.battle.continuous.last_clear={"threat":1,"kind":"rival","run_seed":421}
	check(not f.tokens.notify_clear(f.battle.continuous.last_clear) and f.tokens.items.is_empty(),"Actual clear receipt cannot spawn an impossible full-wallet drop")
	f.run.reroll_charges=Run.MAX_REROLLS-1
	f.battle.continuous.last_clear={"threat":2,"kind":"rival","run_seed":421}
	check(f.tokens.notify_clear(f.battle.continuous.last_clear) and f.tokens.items.size()==1,"A later legitimate clear can spawn again after a charge is spent")
	f.battle.free()
func geometry_cases() -> void:
	var collector_api: Variant = Pickups # Baseline script has no corrected API.
	for blade: String in Catalog.BLADE_IDS:
		for ratchet: String in Catalog.RATCHET_IDS:
			var f: Dictionary = fixture(Vector2(65,0),Vector2.ZERO)
			f.battle.player_entity().starter_id="custom";f.battle.player_entity().build={"blade":blade,"ratchet":ratchet,"bit":"ball"}
			for height: float in [0.0,2.5]:
				f.battle.player_entity().height=height;f.battle.player_entity().vel=Vector2(65,35);f.battle.player_entity().wobble=0.65
				var pose: Dictionary = f.battle.full_top_render_pose(f.battle.player_entity())
				var bounds: Rect2 = f.tokens._visible_blade_bounds(f.battle.player_entity())
				var visible: Rect2 = Rect2(pose.blade_origin+bounds.position,bounds.size)
				check(visible.has_area() and visible.size.x<=48.0 and visible.size.y<=48.0,"Native blade envelope is finite and within its authored cell")
				check(collector_api.swept_visible_overlap(pose.blade_origin,pose.blade_origin,bounds,Rect2(visible.get_center()-Vector2(2,2),Vector2(4,4))),"Every build/stance uses shared actual render geometry")
				check(not collector_api.swept_visible_overlap(pose.blade_origin,pose.blade_origin,bounds,Rect2(visible.end+Vector2(1,1),Vector2(4,4))),"No collection beyond real visible bounds")
				for phase: int in range(8):
					f.battle.player_entity().phase=phase
					check(f.tokens._visible_blade_bounds(f.battle.player_entity())==bounds,"Spin phase cannot shrink/grow collection reach")
			f.battle.free()
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		if arg=="--baseline":baseline=true
	for point: Vector2 in POINTS:
		for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:path_case(point,"world_%s"%direction,direction)
		path_case(point,"visible_horizontal_forward",Vector2(1,-1).normalized(),Vector2(18,18))
		path_case(point,"visible_horizontal_reverse",Vector2(-1,1).normalized(),Vector2(18,18))
		path_case(point,"full_capacity",Vector2(1,-1).normalized(),Vector2.ZERO,true)
	cadence_case()
	if not baseline:lifecycle_cases();geometry_cases()
	var data: Dictionary = {"task":"003A.1 enemy foundation pickup correction","mode":"baseline_reproduction" if baseline else "fixed_position_matrix",
		"spawn_points":POINTS,"cases":rows,"checks":checks,"failures":failures,"radius":Pickups.COLLECT_RADIUS,
		"no_main_or_player_save_opened":true,"native_asset_bounds":"pickup RGBA nontransparent bounds x3..21,y1..15 / pivot12,10; guard blade x7..41,y18..37 / pivot24,40",
		"scope":"Explicit independent position fixtures; world and visible overlaps tested from opposite directions. Does not establish human-controller feel."}
	if not report_path.is_empty():
		var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(portable(data),"\t"));file.close()
	print("PICKUP_POSITIONS_003A1_%s checks=%d failures=%d cases=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),rows.size()])
	quit(0 if failures.is_empty() else 1)
