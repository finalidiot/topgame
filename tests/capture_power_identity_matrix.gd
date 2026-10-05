extends SceneTree
## Explicit static visual fixtures at native game scale, never balance evidence.
## Authored cards/icons are shown alongside these actual arena render states.
const B = preload("res://scripts/battle.gd")
const E = preload("res://scripts/encounters.gd")
const S = preload("res://scripts/starters.gd")
const C = preload("res://scripts/run_powers.gd")
const I = preload("res://scripts/power_identity.gd")
var output: String = ""
var checks: int = 0

func _initialize() -> void: call_deferred("run")

func pose(b: Node2D, family: String, rank: int, branch: String) -> void:
	var p: Dictionary = b.player_entity()
	p.pos = Vector2.ZERO; p.height = 0.0; p.vel = Vector2(145,-80)
	b.entity(2).pos = Vector2(46,-8); b.entity(2).height = 0.0
	b.entity(2).vel = Vector2(15,7)
	b._power_fx.clear(); b._visual_time = 0.15
	match family:
		"impact_wake":
			b.add_power_fx("impact_wake",Vector2.ZERO,Vector2.RIGHT)
			b._power_fx[-1].age = 0.14
		"redline":
			p.redline_time = 0.8; p.redline_active_rank = rank; p.redline_active_mutation = branch
			p.redline_heading = p.vel.normalized(); p.redline_heat = 0.86 if branch == "runaway" else 0.56
			p.runaway_heat = p.redline_heat; p.rpm = 1.18; p.vel = Vector2(230,-90)
			if branch == "breakneck":
				p.redline_commit_time = 0.30
				b.add_power_fx("breakneck_impact",Vector2.ZERO,p.vel.normalized()); b._power_fx[-1].age = 0.11
		"iron_comet":
			p.iron_comet_time = 1.8; p.vel = Vector2(230,-65)
			b.add_power_fx("comet_release",Vector2(10,0),p.vel.normalized()); b._power_fx[-1].age = 0.16
		"dead_centre":
			p.vel = Vector2.ZERO; p.anchor_charge = 0.95; p.stored_force = 115.0
			if branch == "counterweight":
				b.add_power_fx("counterweight_release",Vector2.ZERO,Vector2.RIGHT); b._power_fx[-1].age = 0.14
			elif branch == "bulwark":
				b.add_power_fx("bulwark_impact",Vector2.ZERO,Vector2.RIGHT); b._power_fx[-1].age = 0.18
		"afterimage":
			var points: Array[Vector2] = [Vector2(-58,-12),Vector2(-26,-48),Vector2(34,-38),Vector2(51,8),Vector2(9,45),Vector2(-44,31)]
			var trace: Dictionary = {"owner_entity_id":int(p.entity_id),"points":points,"a":points[0],"b":points[-1],"life":3.0,"max_life":5.0,"rank":rank,"mutation":branch,"energized":branch == "ghost_circuit"}
			if branch == "ghost_circuit":
				trace.circuit_points = points; trace.presentation_circuit_age = 0.18
				p.ghost_preview = {"a":points[0],"b":points[-1],"strength":0.80}
			b.powers.traces.clear(); b.powers.traces.append(trace)
			if branch == "slipstream":
				p.slipstream_time = 0.35
				b.add_power_fx("slipstream_cross",Vector2(18,-20),p.vel.normalized()); b._power_fx[-1].age = 0.12
		"chain_impact":
			b.entity(2).pos = Vector2(31,-15)
			b.add_power_fx("chain_impact",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":int(p.entity_id),"receiver_entity_ids":[2]})
			b._power_fx[-1].age = 0.18
		"clutch":
			p.rpm = 0.23; p.wobble = 0.62; p.clutch_active = true; p.clutch_time = 3.0
			if rank >= 2: p.clutch_recovery_time = 0.22
		"high_gear": p.vel = Vector2(275,-110)
		"orbit_drive": p.drift_active = true; p.orbit_charge = 0.82; p.vel = Vector2(145,-125)
		"crash_guard":
			p.guard_time = 0.9
			b.add_power_fx("crash_guard",Vector2.ZERO,Vector2.LEFT); b._power_fx[-1].age = 0.14
		"momentum_bank":
			p.momentum_charge = (150.0 if rank >= 2 else 95.0)*0.88
			p.vel = Vector2(65,-25)
		"predator_line":
			p.hunt_stacks = 3 if rank >= 2 else 1; p.hunt_target = 2
			b.entity(2).pos = Vector2(65,-28)
		"crosscut":
			b.entity(2).pos = Vector2(20,8)
			b.add_power_fx("crosscut",Vector2(8,4),Vector2(0,1)); b._power_fx[-1].age = 0.16

func capture_state(family: String, rank: int, branch: String = "") -> void:
	var b = B.new(); root.add_child(b); b.set_physics_process(false); b.set_process(false)
	var d: Dictionary = E.for_run_event(1,421)
	d.player_power_ids = [family]; d.player_power_ranks = {family:rank}
	d.player_power_mutations = {family:branch} if not branch.is_empty() else {}
	d.starter_id = "bastion" if family in ["dead_centre","clutch","crash_guard"] else "vane"
	d.ability_rebalance = true
	b.begin_run(S.build_for(str(d.starter_id)),d,421); b.battle_status = "battle"
	b.continuous.pending.clear()
	pose(b,family,rank,branch)
	var before: Dictionary = b.player_entity().duplicate(true)
	var state_before: Dictionary = b.roster.states.duplicate(true)
	var name: String = branch if not branch.is_empty() else family+("_ii" if rank >= 2 else "")
	b.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw; await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	rendered.save_png(output.path_join(name+"_arena.png"))
	var center: Vector2i = Vector2i(b.project(Vector2.ZERO))+Vector2i(5,-10)
	rendered.get_region(Rect2i(center-Vector2i(96,56),Vector2i(192,112))).save_png(output.path_join(name+"_gameplay.png"))
	assert(before == b.player_entity(),"Draw changes no physical fields: "+name)
	assert(state_before == b.roster.states,"Draw changes no power counters/cooldowns: "+name)
	checks += 2
	b.free()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	assert(not output.is_empty())
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(640,360); root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	for family: String in C.ACTIVE_IDS:
		assert(not I.family_info(family).is_empty(),"All active families have native identity assets")
		await capture_state(family,1)
		await capture_state(family,2)
		for branch: String in C.MUTATION_BRANCHES.get(family,[]): await capture_state(family,3,branch)
	print("POWER_IDENTITY_MATRIX_PASS native640x360 states=34 draw_isolation_checks=",checks," explicit_visual_fixtures=true")
	quit()
