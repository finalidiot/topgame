extends SceneTree
## Explicit static render fixtures: never presented as natural gameplay evidence.
const B=preload("res://tests/measured_presentation_battle.gd")
const E=preload("res://scripts/encounters.gd")
const S=preload("res://scripts/starters.gd")
const STATES: Array[String]=["redline_overcap","redline_extreme_heat","runaway_overcap","breakneck_commitment","gear_I","gear_II","terminal_velocity","flow_state","orbit_drift","clutch_danger","clutch_recover","comet_charge","comet_flight","comet_impact","comet_aftermath","ghost_preview","ghost_payoff","bank_guard_hunt"]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var out: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
	assert(not out.is_empty());DirAccess.make_dir_recursive_absolute(out)
	root.size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	for state: String in STATES:
		var b=B.new();root.add_child(b);b.set_physics_process(false)
		var d: Dictionary=E.for_run_event(1,421);d.ability_rebalance=true
		b.begin_run(S.build_for("vane" if state.begins_with("ghost") or state.begins_with("gear") or state in ["flow_state","orbit_drift"] else "breaker"),d,421);b.battle_status="battle"
		var p: Dictionary=b.player_entity();p.pos=Vector2.ZERO;p.height=0.0;p.vel=Vector2(230,30);p.phase=3
		b.entity(2).pos=Vector2(70,5);b.entity(2).height=0.0
		b._power_fx.clear();b._visual_time=.09
		if state.begins_with("redline") or state=="runaway_overcap" or state=="breakneck_commitment":
			p.redline_time=3.0;p.redline_active_rank=2;p.redline_heat=.9 if state=="redline_extreme_heat" else .6;p.runaway_heat=p.redline_heat;p.rpm=1.17;p.redline_heading=Vector2.RIGHT
			p.redline_active_mutation="runaway" if state=="runaway_overcap" else ("breakneck" if state=="breakneck_commitment" else "")
			p.redline_commit_time=.3 if state=="breakneck_commitment" else 0.0
		elif state.begins_with("gear") or state in ["terminal_velocity","flow_state"]:
			p.power_ranks={"high_gear":1 if state=="gear_I" else 2};p.power_mutations={"high_gear":state} if state in ["terminal_velocity","flow_state"] else {}
		elif state=="orbit_drift": p.orbit_charge=.9;p.drift_active=true
		elif state.begins_with("clutch"):
			p.rpm=.18;p.wobble=.65;p.clutch_active=true;p.clutch_time=2.0
			if state=="clutch_recover": p.rpm=.28;p.clutch_recovery_time=.5;b.add_power_fx("clutch_recover",Vector2.ZERO)
		elif state.begins_with("comet"):
			p.power_ranks={"iron_comet":2};p.iron_comet_time=2.7 if state=="comet_charge" else 1.0
			if state in ["comet_impact","comet_aftermath"]:
				p.iron_comet_time=0.0;b.add_power_fx("comet_release",Vector2.ZERO);b._power_fx[-1].age=.07 if state=="comet_impact" else .22
		elif state.begins_with("ghost"):
			var points: Array[Vector2]=[Vector2(-80,-10),Vector2(-20,-75),Vector2(75,-35),Vector2(60,65),Vector2(-40,70),Vector2(-75,15)]
			var t: Dictionary={"points":points,"a":points[0],"b":points[-1],"life":4.5,"max_life":5.5,"rank":2,"mutation":"ghost_circuit","energized":state=="ghost_payoff"}
			if state=="ghost_preview": p.pos=points[-1];p.ghost_preview={"a":points[0],"b":points[-1],"strength":.75}
			else: t.circuit_points=points;t.presentation_circuit_age=.12;b.entity(2).pos=Vector2(20,5)
			b.powers.traces.append(t)
		elif state=="bank_guard_hunt": p.momentum_charge=120.0;p.guard_time=.8;p.hunt_stacks=3
		var label=Label.new();label.text="STATIC VISUAL QA / "+state;label.position=Vector2(12,8);label.add_theme_font_size_override("font_size",13);root.add_child(label)
		var before: Dictionary=p.duplicate(true)
		b.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(state+".png"))
		assert(p==before,"Presentation must preserve exact physical state")
		label.free();b.free()
	print("ROSTER_MATRIX18states / native640x360 / unchangedphysics")
	quit()
