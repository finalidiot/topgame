extends SceneTree
const V = preload("res://scripts/signature_visuals.gd")
const B = preload("res://scripts/battle.gd")
const E = preload("res://scripts/encounters.gd")
const S = preload("res://scripts/starters.gd")
var checks: int = 0
var failures: int = 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures+=1;push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for family: String in V.SHEETS:
		var m: Dictionary = V.meta(family)
		check(m.cell==[96.0,80.0] and m.pivot==[48.0,48.0],"Fixed native canvas/pivot")
		check(m.layers.size()==4,"Editable named normal layers")
		check(FileAccess.file_exists("res://"+str(m.source)),"Production source preserved")
		var source: PackedByteArray=FileAccess.get_file_as_bytes("res://"+str(m.source))
		check(source.decode_u16(4)==0xA5E0 and source.decode_u16(12)==32,"Native RGBA Aseprite header")
		check(source.decode_u16(6)==int(m.frame_count) and source.decode_u32(0)==source.size(),"Source frame count and byte integrity")
		for tag: String in m.tags:
			check(int(m.tags[tag].to)-int(m.tags[tag].from)==5,"Six deliberate key cels")
			check(V.frame(family,tag,0.0)==int(m.tags[tag].from),"First cel")
			check(V.frame(family,tag,99.0,false)==int(m.tags[tag].to),"Terminal cel")
			for frame: int in range(int(m.tags[tag].from),int(m.tags[tag].to)+1): check(int(m.durations_ms[frame]) in [60,45,55,80,100,140],"Authored stepped timing")
	check(V.redline_tag({"redline_active_rank":1})=="rank1_active","Rank I")
	check(V.redline_tag({"redline_active_rank":2})=="rank2_active","Rank II")
	check(V.redline_tag({"redline_active_rank":1,"power_ranks":{"redline":3},"redline_active_mutation":"","power_mutations":{"redline":"runaway"}})=="rank1_active","Paid activation remains same through draft")
	check(V.redline_tag({"redline_active_mutation":"runaway","runaway_heat":0.8})=="runaway_high","Real heat selects overload")
	check(V.redline_tag({"redline_active_mutation":"breakneck"})=="breakneck_charge","Committed pose")
	check(V.anchor_tag({"power_ranks":{"dead_centre":2},"anchor_charge":0.8})=="anchor_full","Full anchor visible")
	check(V.anchor_tag({"power_mutations":{"dead_centre":"counterweight"}})=="counterweight_store","Storage not a generic shield")
	var previous: float = -1.0
	for tier: String in ["light","meaningful","heavy","signature"]:
		check(V.impact_hold(tier)>previous,"Strict hold hierarchy")
		previous=V.impact_hold(tier)
	check(V.impact_hold("signature")<=0.05,"Signature hold capped three fixed ticks")
	var b = B.new()
	root.add_child(b)
	b.set_physics_process(false)
	b.begin_run(S.build_for("breaker"),E.for_run_event(1,421),421)
	b.battle_status="battle"
	var player: Dictionary=b.player_entity()
	var before: Dictionary=player.duplicate(true)
	for i: int in range(100): b.add_power_fx("contact_heavy",Vector2.ZERO)
	check(b._power_fx.size()==32,"Effects bounded under saturation")
	check(player==before,"Presentation events cannot modify fighter physics")
	b._power_fx.clear()
	for i: int in range(100): b.present_reclaim(.001,"elimination")
	check(b._power_fx.is_empty(),"Small/tiny recovery spam silent")
	b.present_reclaim(.03,"combat_reclamation")
	b.present_reclaim(.05,"boss")
	check(b._power_fx.size()==1 and b._power_fx[0].kind=="rpm_reclaim","Meaningful reclaim globally throttled")
	b.present_reclaim(.18,"second_wind")
	check(b._power_fx.size()==1,"Emergency event does not duplicate ordinary reclaim")
	b.paused=true
	var fx: Array=b._power_fx.duplicate(true)
	b.test_step(B.FIXED_DT,Vector2.RIGHT,true)
	check(player==before and b._power_fx==fx,"Draft/pause changes neither RPM nor animation")
	b.paused=false
	var enemy: Dictionary=b.entity(2)
	enemy.enemy_kind="boss";enemy.outcome="spin_out"
	b.continuous.observe_outcomes()
	b.continuous.observe_outcomes()
	check(b.continuous.bosses_defeated==1,"Boss reward presentation counted once")
	var count: int=0
	for effect: Dictionary in b._power_fx:
		if effect.kind=="boss_defeat": count+=1
	check(count==1 and is_same(player,b.player_entity()) and player==before,"Boss collapse preserves same physical player")
	b._hit_stop=0.0
	for i: int in range(20): b.add_power_fx("bulwark_impact",Vector2.ZERO)
	check(b._hit_stop==0.0,"Swarm or standalone presentation events cannot request signature hold")
	b._presentation_full_contact=true
	b.add_power_fx("bulwark_impact",Vector2.ZERO)
	check(is_equal_approx(b._hit_stop,3.0/60.0),"Full-size signature contact gets three fixed ticks")
	b._presentation_full_contact=false
	b.free()
	var pair: Array=[]
	for index: int in range(2):
		var host=B.new();root.add_child(host);host.set_physics_process(false)
		var descriptor: Dictionary=E.for_run_event(1,7341)
		descriptor.player_power_ids=["redline"]
		descriptor.player_power_ranks={"redline":3}
		descriptor.player_power_mutations={"redline":"breakneck"}
		host.begin_run(S.build_for("breaker"),descriptor,7341)
		host.battle_status="battle"
		host.particles_enabled=index==0;host.screen_shake_enabled=index==0
		var cues: Array=[]
		host.event_sfx.connect(func(kind: String) -> void: cues.append([host.elapsed,kind]))
		pair.append({"host":host,"cues":cues,"player":host.player_entity()})
	for tick: int in range(480):
		for item: Dictionary in pair: item.host.test_step(B.FIXED_DT,Vector2(sin(tick*.021),cos(tick*.027)),tick%240==0)
		for field: String in ["pos","vel","rpm","wobble","cooldown","height"]:
			check(pair[0].player[field]==pair[1].player[field],"Particles/shake do not affect physics "+field)
	check(pair[0].cues==pair[1].cues,"Seeded presentation events repeat independently of cosmetic quality")
	for item: Dictionary in pair:
		check(is_same(item.player,item.host.player_entity()),"Same player across visual activity")
		item.host.free()
	print("SIGNATURE_PRESENTATION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
