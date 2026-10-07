extends SceneTree
## Read-only Battle review. Pickups are real threat-clear drops and normal
## steering; arena stages are explicitly labelled clock-offset visual fixtures.
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Run = preload("res://scripts/run_context.gd")
const Pickups = preload("res://scripts/run_pickups.gd")
const Arena = preload("res://scripts/arena_presentation.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const BUILD: Dictionary = {"blade":"hammerfall","ratchet":"kickback","bit":"claw"}
const OWNED: Array[String] = ["dead_centre","clutch","crash_guard","iron_comet","impact_wake","chain_impact","momentum_bank"]
const RANKS: Dictionary = {"dead_centre":3,"clutch":2,"crash_guard":2,"iron_comet":2,"impact_wake":2,"chain_impact":2,"momentum_bank":2}
var mode: String = "pickups"
var output: String = ""
var frames: String = ""
var diagnostic: bool = false
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var feature_frames: Dictionary = {}
var labels: Array[Label] = []
var movie_frames: int = 0
var actual_clears: Array[Dictionary] = []

static func portable(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = portable(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(portable(item))
		return result
	return value
static func input_to(point: Vector2, b: Node2D, strength: float = 1.0) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var offset: Vector2 = point-Vector2(p.pos)
	var desired: Vector2 = offset.limit_length(80.0)*2.1-Vector2(p.vel)*0.9
	var world: Vector2 = desired.limit_length(120.0)/120.0*strength
	return {"direction":Vector2(world.x-world.y,(world.x+world.y)*0.5).limit_length(1.0),"burst":false,"brake":offset.length()<26.0 and Vector2(p.vel).length()>40.0}
func make_label(text: String, pos: Vector2, ink: Color = Color("e4ebd6")) -> Label:
	var label: Label = Label.new();label.text=text;label.position=pos
	label.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"));label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_color",ink);root.add_child(label);labels.append(label);return label
func captions(title: String, note: String) -> void:
	for label: Label in labels: label.free()
	labels.clear()
	make_label(title,Vector2(12,57),Color("e5be66"))
	make_label(note,Vector2(12,72))
	make_label("LEGAL INVESTED INITIAL FIXTURE / REAL SOLVER + INPUTS / NO SAVE WRITES",Vector2(12,342),Color("b0bec6"))
func _initialize() -> void: call_deferred("run")
func new_battle() -> Node2D:
	var b: Node2D = Battle.new();root.add_child(b);b.set_process(false);b.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1,421)
	descriptor.player_power_ids = OWNED.duplicate();descriptor.player_power_ranks = RANKS.duplicate();descriptor.player_power_mutations={"dead_centre":"bulwark"}
	descriptor.starter_id="custom";descriptor.ability_rebalance=true
	b.begin_run(BUILD,descriptor,421)
	var count: int = 0
	while b.battle_status != "battle" and count < 300: b.test_step(Battle.FIXED_DT);count+=1
	return b
func step(b: Node2D, tokens: Node2D, controls: Dictionary) -> void:
	b.test_step(Battle.FIXED_DT,controls.direction,controls.burst,controls.brake)
	if tokens != null: tokens.update_simulation()
func record(b: Node2D, tokens: Node2D, controls: Dictionary, phase: String, feature: String = "") -> void:
	var p: Dictionary = b.player_entity()
	var pickup: Dictionary = tokens.presentation_snapshot() if tokens != null else {}
	rows.append({"movie_frame":movie_frames,"phase":phase,"run_elapsed":b.elapsed,"position":p.pos,"velocity":p.vel,"input":controls,"rpm":p.rpm,"status":b.battle_status,"hits":b.hits,"threats":b.continuous.threats_cleared,"pickup":pickup,"arena":b.arena_presentation.last_snapshot.duplicate(true),"fighters":b.fighters.size()})
	if not diagnostic:
		b.queue_redraw();if tokens != null: tokens.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		if not feature.is_empty() and not feature_frames.has(feature) and not frames.is_empty():
			var im: Image = root.get_texture().get_image();im.resize(640,360,Image.INTERPOLATE_NEAREST)
			var path: String = frames.path_join(feature+".png")
			if im.save_png(path)!=OK:failures.append("Could not save native frame "+feature)
			feature_frames[feature]={"path":path,"movie_frame":movie_frames,"time":b.elapsed,"pickup":portable(pickup)}
	movie_frames += 1
func await_drop(b: Node2D, tokens: Node2D, max_ticks: int = 18000) -> int:
	var ticks: int = 0
	while tokens.items.is_empty() and b.battle_status=="battle" and ticks<max_ticks:
		step(b,tokens,Bot.input(b,"hybrid",ticks));ticks+=1
	return ticks
func pickup_review() -> Dictionary:
	var b: Node2D = new_battle()
	var run_context: RefCounted = Run.new();run_context.start(BUILD,421)
	if not run_context.choose_power(run_context.pending_draft_id,run_context.pending_offer[0]): failures.append("Opening legal Run offer could not be committed")
	var tokens: Node2D = Pickups.new();b.add_child(tokens);tokens.set_process(false);tokens.setup(b,run_context)
	tokens.render_in_battle=true;b.floor_pickups=tokens
	b.threat_cleared.connect(func(summary: Dictionary) -> void:
		if tokens.notify_clear(summary):actual_clears.append(summary.duplicate(true)))
	var warmup: int = await_drop(b,tokens)
	if tokens.items.is_empty():failures.append("Real seeded combat never earned a floor resource");b.free();return {}
	var first: Dictionary = tokens.items[0].duplicate(true)
	captions("003A GROUNDED PICKUPS / LEAVE CENTRE FOR A REAL RESOURCE","NATIVE CONTACT PIVOT / TOKEN IS BELOW COMPLETE MACHINES")
	var collected: bool = false
	for tick: int in range(540):
		var controls: Dictionary = input_to(Vector2(first.pos),b)
		step(b,tokens,controls)
		await record(b,tokens,controls,"leave_centre", "floor_before_collection" if tick==0 else ("floor_contact" if Vector2(b.player_entity().pos).distance_to(first.pos)<22.0 and run_context.rerolls_collected==0 else ("collected" if run_context.rerolls_collected>0 else "")))
		if run_context.rerolls_collected>0:
			collected=true
			for hold: int in range(120):
				controls = input_to(Vector2.ZERO,b);step(b,tokens,controls);await record(b,tokens,controls,"return_centre")
			break
		if b.battle_status!="battle":break
	if not collected:failures.append("Actual steering never crossed and collected the live chip")
	var warmup_second: int = await_drop(b,tokens)
	if tokens.items.is_empty():failures.append("Real subsequent combat never earned an expiry observation resource");b.free();return {}
	var second: Dictionary = tokens.items[0].duplicate(true)
	var start_collected: int = run_context.rerolls_collected
	var start_expired: int = tokens.expired_count
	captions("003A GROUNDED PICKUPS / HOLD CENTRE AND LET THIS ONE GO","16 SIMULATION SECONDS / FINAL 2.5 SECONDS SOFT WARNING")
	for tick: int in range(1200):
		var controls: Dictionary = input_to(Vector2.ZERO,b,0.65)
		step(b,tokens,controls)
		var warning: bool = not tokens.items.is_empty() and float(tokens.presentation_snapshot().active[0].age)>=Pickups.LIFETIME-Pickups.EXPIRY_WARNING
		var feature: String = "expiry_warning" if warning else ("expired_floor" if tokens.expired_count>start_expired else ("hold_centre_decision" if tick==0 else ""))
		await record(b,tokens,controls,"hold_centre",feature)
		if tokens.expired_count>start_expired:
			for hold: int in range(120):
				controls = input_to(Vector2.ZERO,b,0.65);step(b,tokens,controls);await record(b,tokens,controls,"expired_floor")
			break
		if b.battle_status!="battle":break
	if tokens.expired_count<=start_expired:failures.append("Left resource did not expire during live recorded simulation")
	if run_context.rerolls_collected!=start_collected:failures.append("Expiry scene unexpectedly collected instead of leaving the floor resource")
	var result: Dictionary={"initial_build":BUILD,"initial_powers":OWNED,"ranks":RANKS,"mutation":{"dead_centre":"bulwark"},"seed":421,"warmup_ticks_omitted":warmup,"between_scenes_ticks_omitted":warmup_second,"first_drop":first,"second_drop":second,"actual_spawn_clear_summaries":actual_clears,"collected":run_context.rerolls_collected,"expired":tokens.expired_count,"hits":b.hits,"final_time":b.elapsed,"final_status":b.battle_status,"art_preserved":Pickups.SPRITE}
	b.free();return result
func arena_review() -> Dictionary:
	var cases: Array[Dictionary] = [
		{"stage":"EARLY","time":30.0,"reduced":false,"quality":1.0},
		{"stage":"MID","time":240.0,"reduced":false,"quality":1.0},
		{"stage":"LATE","time":420.0,"reduced":false,"quality":1.0},
		{"stage":"EXTREME","time":560.0,"reduced":false,"quality":1.0},
		{"stage":"EXTREME / REDUCED FLASHING","time":560.0,"reduced":true,"quality":1.0},
		{"stage":"EXTREME / MOBILE QUALITY","time":560.0,"reduced":false,"quality":0.60}]
	var scenes: Array[Dictionary] = []
	for index: int in range(cases.size()):
		var scenario: Dictionary = cases[index]
		var b: Node2D = new_battle()
		# Explicit presentation-clock fixture. This is not survival/Director
		# acceptance: only the facility stage and combat readability are judged.
		b.elapsed=float(scenario.time);b.reduced_flashing=bool(scenario.reduced);b.presentation_quality=float(scenario.quality)
		captions("003A ARENA ESCALATION / "+str(scenario.stage),"CLOCK-OFFSET VISUAL FIXTURE / SAME ARENA + BUILD / REAL COMBAT")
		var max_fighters: int = 0;var peak_draws: int = 0;var live_frames: int = 0
		for tick: int in range(480):
			var controls: Dictionary = Bot.input(b,"hybrid",tick)
			step(b,null,controls)
			await record(b,null,controls,str(scenario.stage),str(scenario.stage).to_lower().replace(" / ","_").replace(" ","_") if tick==120 else "")
			max_fighters=maxi(max_fighters,b.fighters.size());peak_draws=maxi(peak_draws,b.arena_presentation.actual_draw_calls)
			if b.battle_status=="battle":live_frames+=1
		if not diagnostic and peak_draws<=0:failures.append("Production arena renderer never drew imported native fixtures")
		if peak_draws> (Arena.MOBILE_MAX_DRAW_CALLS if float(scenario.quality)<0.75 else Arena.MAX_DRAW_CALLS):failures.append("Arena draw budget exceeded")
		scenes.append({"stage":scenario.stage,"clock_fixture":scenario.time,"reduced_flashing":scenario.reduced,"quality":scenario.quality,"movie_frames":480,"live_combat_frames":live_frames,"peak_fighters":max_fighters,"peak_arena_draws":peak_draws,"hits":b.hits,"final_status":b.battle_status})
		b.free()
	return {"scenes":scenes,"initial_build":BUILD,"initial_powers":OWNED,"ranks":RANKS,"seed":421,"clock_fixture_explicit":true,"balance_claim":false}
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="):frames=arg.trim_prefix("--frames=")
		if arg=="--diagnostic":diagnostic=true
	if output.is_empty() or mode not in ["pickups","arena"]:push_error("Supply external --manifest and --mode=pickups|arena");quit(2);return
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames.is_empty():DirAccess.make_dir_recursive_absolute(frames)
	var scenario: Dictionary = await pickup_review() if mode=="pickups" else await arena_review()
	var report: Dictionary={"mode":mode,"failures":failures,"scenario":scenario,"rows":rows,"feature_frames":feature_frames,"movie_frames":movie_frames,"fps":60,"native_view":[640,360],"collection_opened":false,"main_created":false,"diagnostic":diagnostic,"authenticity":"Legal seven-family invested initial fixture. Pickups are production drops from actual cleared threats, with ordinary steering/Burst/Brake through the real fixed solver and exact production lifetime/collection. Only arena stage review uses labelled clock offsets; it makes no survival or Director balance claim. No collection/preferences/economy/profile writes."}
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Could not write external manifest");quit(2);return
	file.store_string(JSON.stringify(portable(report),"\t"));file.close()
	print("ARENA_ACCEPTANCE_CAPTURE_%s mode=%s frames=%d" % ["PASS" if failures.is_empty() else "FAIL",mode,movie_frames]);quit(0 if failures.is_empty() else 1)
