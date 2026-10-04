extends SceneTree
## STATIC VISUAL FIXTURES, not gameplay videos or mechanics acceptance.
const Battle=preload("res://tests/measured_presentation_battle.gd")
const E=preload("res://scripts/encounters.gd")
const S=preload("res://scripts/starters.gd")
const STATES: Array[String]=["redline_1","redline_2","runaway","breakneck_charge","breakneck_impact","breakneck_recovery","anchor_build","anchor_full","bulwark_impact","counterweight_store","counterweight_release","afterimage_1","afterimage_2","ghost_closure","slipstream_cross","contact_heavy","elite_entry","anvil_entry","reaper_entry","boss_defeat","low_rpm","rpm_reclaim","second_wind"]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var out: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
	assert(not out.is_empty())
	DirAccess.make_dir_recursive_absolute(out)
	root.size=Vector2i(640,360)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	for state: String in STATES:
		var b=Battle.new();root.add_child(b);b.set_physics_process(false)
		var d: Dictionary=E.for_run_event(1,421)
		var starter: String="bastion" if state.begins_with("anchor") or state.begins_with("bulwark") or state.begins_with("counterweight") else ("vane" if state.begins_with("afterimage") or state.begins_with("ghost") or state.begins_with("slipstream") else "breaker")
		d.starter_id=starter
		b.begin_run(S.build_for(starter),d,421);b.battle_status="battle"
		var p: Dictionary=b.player_entity();p.pos=Vector2.ZERO;p.height=0.0;p.vel=Vector2(80,30)
		b.entity(2).pos=Vector2(65,5);b.entity(2).height=0.0
		b._power_fx.clear();b._visual_time=.09
		if state.begins_with("redline") or state=="runaway" or state=="breakneck_charge":
			p.redline_time=.5;p.redline_active_rank=1 if state=="redline_1" else 2
			p.redline_active_mutation="runaway" if state=="runaway" else ("breakneck" if state=="breakneck_charge" else "")
			p.runaway_heat=.8;p.redline_heading=Vector2.RIGHT
		elif state.begins_with("anchor") or state.begins_with("counterweight") or state=="bulwark_impact":
			p.anchor_charge=.4 if state=="anchor_build" else 1.0;p.power_ranks={"dead_centre":2};p.vel=Vector2.ZERO
			p.power_mutations={"dead_centre":"counterweight" if state.begins_with("counterweight") else ("bulwark" if state=="bulwark_impact" else "")}
			p.stored_force=120.0
		elif state.begins_with("afterimage") or state=="ghost_closure":
			var points: Array[Vector2]=[Vector2(-70,0),Vector2(0,-65),Vector2(80,-20),Vector2(65,65),Vector2(-40,75),Vector2(-70,0)]
			var t: Dictionary={"points":points,"a":points[0],"b":points[-1],"life":3.0,"max_life":5.0,"rank":1 if state=="afterimage_1" else 2,"mutation":"ghost_circuit" if state=="ghost_closure" else "","energized":state=="ghost_closure"}
			if state=="ghost_closure": t.circuit_points=points;t.presentation_circuit_age=.13
			b.powers.traces.append(t)
		elif state in ["anvil_entry","reaper_entry","elite_entry"]:
			var enemy: Dictionary=b.entity(2)
			enemy.enemy_kind="elite" if state=="elite_entry" else "boss"
			enemy.archetype="ballast" if state=="elite_entry" else state.trim_suffix("_entry")
			b.continuous.pending={"kind":enemy.enemy_kind,"position":Vector2(-65,-10),"ready_at":1.0}
		elif state=="low_rpm": p.rpm=.12;p.wobble=.82;b._visual_time=.06
		if state in ["breakneck_impact","breakneck_recovery","bulwark_impact","counterweight_release","slipstream_cross","contact_heavy","boss_defeat","rpm_reclaim","second_wind"]:
			b.add_power_fx(state,Vector2.ZERO,Vector2.RIGHT)
			b._power_fx[-1].age=.13 if state!="second_wind" else .34
		var before: Dictionary=p.duplicate(true)
		var label=Label.new();label.text="STATIC VISUAL QA / "+state;label.position=Vector2(12,8);label.add_theme_font_size_override("font_size",13);root.add_child(label)
		b.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(state+".png"))
		assert(p==before,"Draw must not modify physical state")
		label.free();b.free()
	print("SIGNATURE_MATRIX 23 states / unchanged physics / native 640x360")
	quit()
