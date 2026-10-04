extends "res://tests/test_escalation_visual_playthrough.gd"
## Explicit opening build/pose presets. Thereafter only controller inputs.
## Real continuous physics, enemy AI, RPM costs and gains; no injected procs.
const Sound = preload("res://scripts/sound.gd")
var family: String="redline"
var output: String=""
func _initialise_fixture(b: Node2D, sc: Dictionary) -> void:
	var d: Dictionary=Encounters.for_run_event(1,421)
	d.starter_id=sc.starter
	d.player_power_ids=[sc.power,sc.support]
	d.player_power_ranks={str(sc.power):sc.get("rank",3),str(sc.support):1}
	d.player_power_mutations={str(sc.power):sc.branch} if not str(sc.branch).is_empty() else {}
	b.begin_run(Starters.build_for(sc.starter),d,421)
	b.battle_status="battle"
	var p: Dictionary=b.player_entity()
	if sc.policy=="centre_brake": p.pos=Vector2.ZERO;p.vel=Vector2.ZERO
	elif sc.policy=="orbit": p.pos=Vector2(132,0);p.vel=Vector2.ZERO
	b.powers._state(p).trace_origin=p.pos
	b.powers._state(p).trace_path=[Vector2(p.pos)]
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--family="): family=arg.trim_prefix("--family=")
		if arg.begins_with("--manifest="): output=arg.trim_prefix("--manifest=")
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(640,360)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var sound=Sound.new();root.add_child(sound);sound.apply_settings({"volume":0.65,"muted":false})
	var presets: Array=[]
	if family=="redline":
		for rank: int in [1,2,3]: presets.append({"starter":"breaker","power":"redline","branch":"breakneck" if rank==3 else "","support":"impact_wake","rank":rank,"policy":"pursuit_burst","seconds":6.0,"label":"REDLINE "+["I","II","BREAKNECK"][rank-1]})
	elif family=="dead_centre":
		presets=[{"starter":"bastion","power":"dead_centre","branch":"bulwark","support":"second_wind","rank":3,"policy":"centre_brake","seconds":14.0,"label":"BULWARK / ANCHOR -> RECEIVE -> REPEL"}]
	else:
		for rank: int in [1,2,3]: presets.append({"starter":"vane","power":"afterimage","branch":"ghost_circuit" if rank==3 else "","support":"iron_comet","rank":rank,"policy":"orbit","seconds":7.0,"label":"AFTERIMAGE "+["I","II","GHOST CIRCUIT"][rank-1]})
	var rows: Array=[]
	for sc: Dictionary in presets:
		var b: Node2D=Battle.new();root.add_child(b);b.set_physics_process(false)
		_initialise_fixture(b,sc)
		b.event_sfx.connect(sound.play_sound)
		var label=Label.new();label.position=Vector2(12,8);label.add_theme_font_size_override("font_size",13);root.add_child(label)
		var p: Dictionary=b.player_entity()
		for tick: int in range(int(float(sc.seconds)*60.0)):
			var input: Dictionary=_controls(b,sc)
			b.test_step(Physics.FIXED_DT,input.direction,input.burst,input.brake)
			label.text="%s\nRPM %04d / 9000  |  %.1fs\nCONTROLLED OPENING PRESET - REAL COMBAT"%[sc.label,roundi(float(p.rpm)*9000.0),b.elapsed]
			label.modulate=Color("ffad79") if float(p.rpm)<.25 else Color("e2e8d5")
			b.queue_redraw()
			assert(is_same(p,b.player_entity()))
			await process_frame
		rows.append({"preset":sc,"procs":b.powers.counters.duplicate(),"events":b.powers.events.duplicate(true),"rpm":b.continuous.economy.snapshot(),"elapsed":b.elapsed,"result":b.last_result})
		label.free();b.free()
	if not output.is_empty():
		var file=FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify({"authenticity":"Explicit opening presets separated by visible cuts. Full RPM at launch. Only steering/Burst/brake after setup; actual continuous mechanics, no fabricated results.","runs":rows},"\t"))
	print("SIGNATURE_CAPTURE ",family)
	quit()
