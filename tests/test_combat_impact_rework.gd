extends SceneTree
const Feedback = preload("res://scripts/combat_impact_feedback.gd")
const Battle = preload("res://scripts/battle.gd")
const Sound = preload("res://scripts/sound.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func event(id: int, severity: float, closing: float, impulse: float) -> Dictionary:
	return {"collision_id":id,"severity":severity,"closing":closing,"impulse":impulse,"position":Vector2.ZERO,
		"contact_position":Vector2(4,8),"normal":Vector2.RIGHT,"first_velocity":Vector2(closing,0),"second_velocity":Vector2.ZERO,
		"first_entity_id":1,"second_entity_id":2,"first_position":Vector2(-12,0),"second_position":Vector2(12,0),
		"first_rpm_loss":0.0,"second_rpm_loss":0.0}
func run() -> void:
	var f = Feedback.new()
	for row: Array in [[0.08,40.0,100.0,"light",0.0],[0.4,100.0,400.0,"strong",1.0/60.0],[0.9,200.0,2000.0,"hard",3.0/60.0],[1.0,250.0,4000.0,"extreme",4.0/60.0]]:
		f.reset()
		var e: Dictionary = event(1,row[0],row[1],row[2])
		var original: Dictionary = e.duplicate(true)
		var result: Dictionary = f.accept_impact(e)
		check(result.tier == row[3] and is_equal_approx(result.hold,row[4]),"Physical tier and bounded hold: "+str(row[3]))
		check(e == original,"Presentation never edits solver event")
		check(f.snapshot().sparks.size() == 1 and f.snapshot().sparks[0].position == Vector2(4,8),"Authored sparks attach to actual contact point")
		check(f.accept_impact(e).is_empty() and f.snapshot().sparks.size() == 1,"One accepted collision cannot duplicate feedback")
	var glance: Dictionary = event(2,0.5,110,400)
	glance.first_velocity = Vector2(110,100)
	check(Feedback.audio_family(glance) == "metal_edge","Glancing blade angle selects edge rake")
	glance.first_velocity = Vector2(110,220)
	check(Feedback.audio_family(glance) == "metal_scrape","Strong tangential slip selects grinding steel")
	check(Feedback.tier(event(3,1,250,3999.99)) == "hard","Just below canonical beast work threshold remains hard")
	check(Feedback.tier(event(3,0.7,250,4000)) == "extreme","Extreme shares exact existing physical beast qualification")
	f.reset(); f.numbers_enabled = true
	var e: Dictionary = event(1,0.9,210,1000)
	e.first_rpm_loss = 239.9/9000.0; e.second_rpm_loss = 240.1/9000.0
	f.accept_impact(e)
	check(f.snapshot().numbers.size() == 1 and f.snapshot().numbers[0].entity_id == 2 and f.snapshot().numbers[0].amount == 240,"Numbers gate actual meaningful RPM loss, rounded only for display")
	f.accept_impact(event(2,0.9,210,1000))
	check(f.snapshot().numbers.size() == 1,"Zero loss never invents damage")
	e.collision_id = 3; e.second_rpm_loss = 0.1
	check(float(f.accept_impact(e).hold) == 0.0,"Immediate repeated contact receives sparks/audio without repeated theatre")
	check(f.snapshot().numbers.size() == 1,"Per-top number cooldown suppresses spam")
	f.update(0.61); e.collision_id = 4; f.accept_impact(e)
	check(f.snapshot().numbers.size() == 2,"Meaningful number may return after cooldown")
	for id: int in range(5,45):
		var many: Dictionary = event(id,0.9,200,1000)
		many.first_entity_id = id; many.first_rpm_loss = 0.08
		f.accept_impact(many)
	check(f.snapshot().sparks.size() <= Feedback.MAX_SPARK_EVENTS and f.snapshot().numbers.size() <= Feedback.MAX_NUMBERS,"Crowds stay inside authored spray and number budgets")
	f.update(1.0)
	check(f.snapshot().sparks.is_empty() and f.snapshot().numbers.is_empty(),"All transient presentations expire")
	var target: Dictionary = {"entity_id":10,"combatant_type":"full_top","outcome":"ring_out","enemy_kind":"elite","pos":Vector2(80,40),"vel":Vector2(100,0)}
	check(f.accept_elimination(target).cue == "metal_takedown" and f.confirmation() == "ELITE RING OUT","Physical full-top elimination has distinct payoff and HUD confirmation")
	check(f.accept_elimination(target).is_empty(),"Elimination deduplicates across outcome/finish hooks")
	target.entity_id = 11; target.outcome = "natural_retirement"
	check(f.accept_elimination(target).is_empty(),"Threat cleanup is never a physical takedown")
	target.entity_id = 12; target.outcome = "spin_out"; target.combatant_type = "small_top"
	check(f.accept_elimination(target).is_empty(),"Small bodies never trigger giant full-top defeat feedback")
	f.update(1.0); check(f.confirmation().is_empty(),"Confirmation clears cleanly")
	for name: String in ["metal_light","metal_clang","metal_edge","metal_scrape","metal_massive","metal_wall","metal_takedown"]:
		check(Sound.SOUNDS.has(name),"Original impact family embedded: "+name)
		var wav: AudioStreamWAV = Sound.SOUNDS[name]
		check(wav.get_length() > 0.05 and wav.get_length() < 0.5,"Fast noncinematic original steel cue: "+name)
	var b: Node2D = Battle.new(); root.add_child(b); b.set_physics_process(false)
	b.begin({"blade":"smash","ratchet":"high","bit":"flat"},{"blade":"guard","ratchet":"low","bit":"ball"},1,421)
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity(); var enemy: Dictionary = b.entity(2)
	p.pos = Vector2(-10,0); enemy.pos = Vector2(10,0)
	p.vel = Vector2(200,80); enemy.vel = Vector2(-80,0)
	var before_a: float = p.rpm; var before_b: float = enemy.rpm
	b.resolve_pair(1,2)
	var accepted: Dictionary = b.impact_feedback.snapshot().events.back()
	check(is_equal_approx(float(accepted.first_rpm_loss),before_a-float(p.rpm)) and is_equal_approx(float(accepted.second_rpm_loss),before_b-float(enemy.rpm)),"Integration reports exact solver reserve loss")
	check(b.hits == 1 and not b.impact_feedback.snapshot().sparks.is_empty(),"Real accepted collision emits authored contact presentation")
	var frozen: Dictionary = b.impact_feedback.snapshot()
	b.set_paused(true)
	for i: int in range(100): b.test_step(Battle.FIXED_DT)
	check(b.impact_feedback.snapshot() == frozen,"Paused/draft state freezes transient feedback timelines")
	b.free()
	print("COMBAT_IMPACT_REWORK_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
