extends "res://tests/test_threat_director.gd"
## Native-rendered controlled composition fixtures, not pacing evidence.
var captures: String = ""
func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(frame != null and not frame.is_empty(),"Native director frame renders")
	if frame != null and not captures.is_empty(): check(frame.save_png(captures.path_join(label+".png")) == OK,"Native capture saves")
func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): captures = argument.trim_prefix("--capture-dir=")
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	root.size = Vector2i(640,360)
	var game: QuietMain = make_game()
	var b: Node2D = game.battle
	b.battle_status = "battle"
	b.elapsed = 500.0
	b.powers.time = 500.0
	b.player_entity().pos = Vector2(-40,30)
	b.entity(2).pos = Vector2(60,30)
	var boss: Dictionary = Director.EVENTS[-1].duplicate(true)
	boss["serial"] = 2
	boss["ready_at"] = 502.2
	boss["position"] = b.continuous._safe_entry()
	boss["tier_at_entry"] = 5
	b.continuous.pending = boss
	b.continuous.callout = "INCOMING: RED REAPER"
	b.continuous.callout_until = 505.0
	b._emit_hud()
	await capture("01-boss-warning-640")
	b.elapsed = 502.2
	b.continuous.director.active[2] = {"kind":"boss","time":500.0}
	check(b.continuous._admit_pending(),"Boss warning resolves to live admission")
	force_event(b,"ammunition")
	for index: int in range(8):
		b.swarm.add_small(b.continuous.next_entity_id-24+index,Vector2(cos(index*TAU/8.0),sin(index*TAU/8.0))*90.0)
	b._emit_hud()
	b.queue_redraw()
	await capture("02-boss-swarm-overlap-640")
	b.entity(2).outcome = "spin_out"
	b.entity(2).out_time = 1.0
	b.continuous._cleanup(0.0)
	force_event(b,"ballast")
	b.continuous.callout = "BALLAST ELITE"
	b._emit_hud()
	b.queue_redraw()
	await capture("03-boss-elite-swarm-640")
	root.size = Vector2i(1280,720)
	await capture("04-boss-elite-swarm-2x")
	Fixtures.defeat_player(game,"spin_out")
	await capture("05-director-result")
	game.free()
	print("DIRECTOR_VISUAL_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
