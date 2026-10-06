extends SceneTree
## Exact lifetime/contact fixtures plus current production Main floor integration.
const Battle = preload("res://scripts/battle.gd")
const Run = preload("res://scripts/run_context.gd")
const Pickups = preload("res://scripts/run_pickups.gd")
const BUILD: Dictionary = {"blade":"guard","ratchet":"mid","bit":"ball"}
var checks: int = 0
var failures: int = 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func fixture() -> Dictionary:
	var run_context: RefCounted = Run.new()
	run_context.start(BUILD,421,"bastion")
	check(run_context.choose_power(run_context.pending_draft_id,run_context.pending_offer[0]),"Legal offered opening power is committed")
	var b: Node2D = Battle.new();root.add_child(b);b.set_physics_process(false)
	b.begin_run(BUILD,run_context.current_encounter(),421)
	# Controlled contact/lifetime test fixture; no result or collection is written.
	b.battle_status = "battle";b.elapsed = 1.0;b.player_entity().pos = Vector2.ZERO
	var tokens: Node2D = Pickups.new();b.add_child(tokens);tokens.set_process(false);tokens.setup(b,run_context)
	tokens.render_in_battle = true
	tokens.items.append({"id":"fixture/token", "pos":Vector2(65,0),"born":1.0})
	return {"battle":b,"run":run_context,"tokens":tokens}
func run() -> void:
	check(Pickups.LIFETIME >= 10.0 and Pickups.LIFETIME <= 20.0,"Floor resource has a finite useful 10–20 second lifetime")
	check(Pickups.EXPIRY_WARNING >= 2.0 and Pickups.EXPIRY_WARNING <= 3.0,"Expiry offers a readable final 2–3 seconds")
	check(Pickups.COLLECT_RADIUS == 14.0,"Collection matches the physical machine footprint rather than a broad magnet")
	var f: Dictionary = fixture()
	f.battle.elapsed += 1.0;f.battle.player_entity().pos = Vector2(50.9,0);f.tokens.update_simulation()
	check(f.tokens.items.size()==1 and f.run.rerolls_collected==0,"A machine clearly outside its 14-unit footprint cannot collect")
	f.battle.elapsed += 1.0;f.battle.player_entity().pos = Vector2(51,0);f.tokens.update_simulation()
	check(f.tokens.items.is_empty() and f.run.rerolls_collected==1,"Physical contact at the footprint edge collects once")
	f.tokens.update_simulation();check(f.run.rerolls_collected==1,"Render frames cannot duplicate pickup collection")
	f.battle.free()
	f = fixture();f.battle.elapsed += 1.0;f.battle.player_entity().pos = Vector2(95,0);f.tokens.update_simulation()
	check(f.tokens.items.is_empty() and f.run.rerolls_collected==1,"Fast real swept movement cannot tunnel over the floor resource")
	f.battle.free()
	f = fixture();f.battle.paused = true;f.battle.elapsed = 9.0;f.battle.player_entity().pos = Vector2(65,0);f.tokens.update_simulation()
	check(f.tokens.items.size()==1 and f.run.rerolls_collected==0 and float(f.tokens.presentation_snapshot().active[0].age)==0.0,"Pause freezes collection and the presentation lifetime clock")
	f.battle.free()
	f = fixture();f.battle.elapsed = 1.0+Pickups.LIFETIME-Pickups.EXPIRY_WARNING-0.01;f.tokens.update_simulation()
	check(not f.tokens.presentation_snapshot().active[0].warning,"Ordinary resource never flickers before warning")
	f.battle.elapsed += 0.02;f.tokens.update_simulation()
	check(f.tokens.presentation_snapshot().active[0].warning,"Final warning starts at the exact simulation age")
	f.battle.elapsed = 1.0+Pickups.LIFETIME;f.battle.player_entity().pos = Vector2(65,0);f.tokens.update_simulation()
	check(f.tokens.items.is_empty() and f.tokens.expired_count==1 and f.run.rerolls_collected==0,"Expired resource disappears without granting a charge even if crossed on expiry tick")
	f.battle.free()
	for tick: int in range(1601):
		var age: float = float(tick)/100.0
		var normal: float = Pickups.expiry_alpha(age,false)
		var accessible: float = Pickups.expiry_alpha(age,true)
		check(normal >= 0.0 and normal <= 1.0 and accessible >= 0.0 and accessible <= 1.0,"Expiry opacity is finite and bounded")
		if age < Pickups.LIFETIME-Pickups.EXPIRY_WARNING: check(normal==1.0 and accessible==1.0,"No ambient flash throughout ordinary lifetime")
		if age >= Pickups.LIFETIME: check(normal==0.0 and accessible==0.0,"Expired drawing cannot remain visible")
	var previous: float = 1.0
	for tick: int in range(251):
		var alpha: float = Pickups.expiry_alpha(Pickups.LIFETIME-Pickups.EXPIRY_WARNING+float(tick)/100.0,true)
		check(alpha <= previous,"Reduced Flashing warning is a continuous monotonic fade")
		previous = alpha
	var battle_code: String = FileAccess.get_file_as_string("res://scripts/battle.gd")
	var main_code: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	check("floor_pickups.draw_floor(self)" in battle_code and battle_code.find("floor_pickups.draw_floor(self)")<battle_code.find("for fighter: Dictionary in order:"),"Production Battle draws grounded tokens before complete machine rigs")
	check("floor_pickups = reroll_pickups" in main_code and "render_in_battle = true" in main_code,"Production Main suppresses late child overlay and assigns the true floor pass")
	print("GROUNDED_PICKUPS_%s checks=%d failures=%d" % ["PASS" if failures==0 else "FAIL",checks,failures]);quit(1 if failures else 0)
