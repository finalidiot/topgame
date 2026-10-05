extends "res://tests/diagnose_roster_runs.gd"
## Same natural bot, Main Run and earned drafts as the roster diagnostics.
## Movie windows fast-forward real ticks from launch; never manufacture state.
var game: QuietMain
var tick: int=0
var direction: Vector2=Vector2.ZERO
var brake: bool=false
var capture_start: float=250.0
var capture_length: float=22.0
var capture_starter: String="bastion"
var capture_seed: int=421
var manifest_path: String=""
var diagnostic: bool=false
var frame_dir: String=""
func capture_step() -> void:
	var b: Node2D=game.battle
	var burst: bool=false
	if tick%12==0:
		var input: Dictionary=controls(b,style,tick)
		direction=input.direction;brake=input.brake;burst=input.burst
	b.test_step(Battle.FIXED_DT,direction,burst,brake)
	if game.screen=="level_up": game._process(.2)
	while game.screen=="reward": choose(game)
	tick+=1
func summary(b: Node2D) -> Dictionary:
	var p: Dictionary=b.player_entity()
	return {"time":b.elapsed,"rpm":p.rpm,"speed":Vector2(p.vel).length(),"wobble":p.wobble,"heat":p.get("redline_heat",0.0),"powers":game.run_context.power_ranks.duplicate(),"mutations":game.run_context.power_mutations.duplicate(),"procs":b.powers.counters.duplicate(),"threats":b.continuous.snapshot(),"economy":b.continuous.economy.snapshot(),"fx":b._power_fx.size()}
func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var ordered: Array[float]=values.duplicate();ordered.sort()
	return {"samples":ordered.size(),"median":ordered[ordered.size()/2],"p95":ordered[mini(ordered.size()-1,int(ordered.size()*.95))],"max":ordered.back()}
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): profile=arg.trim_prefix("--profile=")
		if arg.begins_with("--starter="): capture_starter=arg.trim_prefix("--starter=")
		if arg.begins_with("--seed="): capture_seed=int(arg.trim_prefix("--seed="))
		if arg.begins_with("--start="): capture_start=float(arg.trim_prefix("--start="))
		if arg.begins_with("--length="): capture_length=float(arg.trim_prefix("--length="))
		if arg.begins_with("--manifest="): manifest_path=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frame_dir=arg.trim_prefix("--frames=")
		if arg=="--diagnostic": diagnostic=true
	style=PROFILES[profile].style;override_power=PROFILES[profile].powers[0]
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(640,360);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty(): DirAccess.make_dir_recursive_absolute(frame_dir)
	game=QuietMain.new();game.smoke_mode=true;root.add_child(game);game.set_process(false)
	game.run_context.start(Starters.build_for(capture_starter),capture_seed,capture_starter);game.mode="run";opening_preference=override_power;game._show_reward();choose(game)
	var b: Node2D=game.battle;b.set_physics_process(false);b.particles_enabled=not diagnostic
	var player: Dictionary=b.player_entity()
	while (b.elapsed<capture_start or b.battle_status in ["countdown","launch"]) and game.screen!="result" and tick<150000: capture_step()
	assert(b.battle_status=="battle","Natural capture must reach window through actual survival")
	var before: Dictionary=summary(b)
	if not diagnostic: b.event_sfx.connect(func(kind: String) -> void: game.sounds.play_sound(kind))
	var label_layer=CanvasLayer.new();label_layer.layer=11;root.add_child(label_layer)
	var label=Label.new();label.position=Vector2(12,65);label.add_theme_font_size_override("font_size",9);label_layer.add_child(label)
	var rows: Array[Dictionary]=[]
	var next_sample: float=b.elapsed
	var cpu: Array[float]=[]
	var walls: Array[float]=[]
	var last_wall: int=Time.get_ticks_usec()
	var draw_samples: Array[float]=[]
	for frame: int in range(int(capture_length*60.0)):
		var began: int=Time.get_ticks_usec();capture_step();cpu.append(float(Time.get_ticks_usec()-began)/1000.0)
		assert(is_same(player,b.player_entity()),"One uninterrupted physical player")
		label.text="NATURAL EARNED RUN / %s / %s / SEED %d"%[profile.to_upper(),capture_starter.to_upper(),capture_seed]
		label.modulate=Color("ffad79") if float(player.rpm)<.28 else Color("e2e8d5")
		if b.elapsed>=next_sample: rows.append(summary(b));next_sample+=.25
		if not diagnostic:
			b.queue_redraw();await process_frame;walls.append(float(Time.get_ticks_usec()-last_wall)/1000.0);last_wall=Time.get_ticks_usec()
			if not frame_dir.is_empty() and frame%180==0:
				await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(frame_dir.path_join(profile+"-%04d.png"%frame))
		if game.screen=="result" and diagnostic: break
	var result: Dictionary={"authenticity":"Natural Main Run from full normal launch, real seeded offers/ranks/mutations, ordinary enemy AI and Threat Director. Same sampled controller and preference selector as diagnose_roster_runs. Every fast-forward tick executed; no direct RPM/enemy/proc edits, no protected outcome.","profile":profile,"starter":capture_starter,"seed":capture_seed,"before":before,"after":summary(b),"rows":rows,"drafts":draft_log,"events":b.powers.events.duplicate(true),"result":b.last_result,"simulation_ms":_stats(cpu),"draw_submission_ms":_stats(draw_samples),"frame_wall_ms":_stats(walls),"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"performance_scope":"Actual late Run window with earned build and live threats. Main does not instrument per-battle draw submission; frame interval includes movie/capture overhead. Separate measured-presentation stress fixture covers CPU draw submission."}
	if not manifest_path.is_empty(): var file=FileAccess.open(manifest_path,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"))
	print("NATURAL_ROSTER_CAPTURE ",profile," ",capture_starter," seed=",capture_seed," ",before.time," to ",b.elapsed," powers=",game.run_context.power_ranks)
	game.free();quit()
