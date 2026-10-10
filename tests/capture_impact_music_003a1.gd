extends SceneTree
## Review uses real collision/mixer/renderers. Labelled initial conditions and
## music observations are QA fixtures; no Main/save/profile is ever opened.
const Battle = preload("res://scripts/battle.gd")
const Music = preload("res://scripts/music.gd")
const Sound = preload("res://scripts/sound.gd")
var mode: String = "impacts"
var output: String = ""
var frame_dir: String = ""
var diagnostic: bool = false
var movie_frames: int = 0
var rows: Array[Dictionary] = []
var scenes: Array[Dictionary] = []
var features: Dictionary = {}
var failures: Array[String] = []
var labels: Array[Label] = []
var music: Node
var sound: Node

func _initialize() -> void:call_deferred("run")
func captions(title: String, subtitle: String) -> void:
	for label: Label in labels:label.free()
	labels.clear()
	for item: Dictionary in [{"text":title,"pos":Vector2(8,362),"color":Color("e6b96f")},{"text":subtitle,"pos":Vector2(8,377),"color":Color("b3c8cb")}]:
		var label := Label.new();label.text=item.text;label.position=item.pos
		label.add_theme_font_override("font",load("res://assets/ui/foundry_small.fnt"));label.add_theme_font_size_override("font_size",9)
		label.add_theme_color_override("font_color",item.color);root.add_child(label);labels.append(label)

func cue(kind: String) -> void:
	sound.play_sound(kind);music.notify_cue(kind)

func new_battle() -> Node2D:
	var b := Battle.new();root.add_child(b);b.set_process(false);b.set_physics_process(false)
	b.begin({"blade":"smash","ratchet":"high","bit":"flat"},{"blade":"guard","ratchet":"low","bit":"ball"},1,421)
	# Normal ready/launch completes before the initial-condition review fixture.
	while b.battle_status!="battle":b.test_step(Battle.FIXED_DT)
	b.event_sfx.connect(cue)
	return b

func frame(b: Node2D, scene: String, tick: int, feature: String = "") -> void:
	if tick%6==0 or not feature.is_empty():rows.append({"frame":movie_frames,"scene":scene,"tick":tick,"impact":b.impact_feedback.snapshot(),"beasts":b.beasts.snapshot(),"hit_stop":b._hit_stop,"shake":b._shake_strength,"music":music.music_snapshot(),"sounds":sound.played_counts.duplicate()})
	if not diagnostic:
		b.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		if not feature.is_empty():
			var path := frame_dir.path_join(feature+".png")
			if root.get_texture().get_image().get_region(Rect2i(0,0,640,400)).save_png(path)!=OK:failures.append("Could not save "+feature)
			features[feature]={"path":path,"frame":movie_frames}
	else:
		sound.audio_time+=Battle.FIXED_DT;music.advance_presentation(Battle.FIXED_DT)
	movie_frames+=1

func impacts() -> void:
	# Incoming velocities and starting reserves are disclosed initial fixtures.
	# All tiers/losses/impulses/outcomes come from the canonical collision solver.
	for spec: Dictionary in [
		{"id":"light","label":"LIGHT METAL / SMALL CONTACT","a":Vector2(22,0),"b":Vector2(-18,0),"numbers":false},
		{"id":"edge","label":"GLANCING BLADE / SLASH","a":Vector2(80,100),"b":Vector2(-30,0),"numbers":false},
		{"id":"scrape","label":"TANGENTIAL CONTACT / GRIND","a":Vector2(80,220),"b":Vector2(-30,0),"numbers":false},
		{"id":"hard","label":"HARD METAL SLAM","a":Vector2(130,0),"b":Vector2(-80,0),"numbers":false},
		{"id":"extreme","label":"EXTREME COLLISION / BEAST","a":Vector2(390,0),"b":Vector2(-390,0),"numbers":false},
		{"id":"numbers","label":"REAL RPM LOSS PROTOTYPE / ON","a":Vector2(390,0),"b":Vector2(-390,0),"numbers":true},
		{"id":"elimination","label":"FULL-TOP SPIN OUT / PAYOFF","a":Vector2(260,0),"b":Vector2(-200,0),"numbers":false},
		{"id":"reduced","label":"EXTREME / REDUCED FLASHING","a":Vector2(390,0),"b":Vector2(-390,0),"numbers":false}]:
		var b := new_battle();var p: Dictionary=b.player_entity();var e: Dictionary=b.entity(2)
		b.impact_numbers_enabled=spec.numbers;b.reduced_flashing=spec.id=="reduced"
		captions("003A.1 / "+spec.label,"REAL SOLVER / LABELLED INITIAL CONTACT FIXTURE / NORMAL 60FPS PLAYBACK")
		var accepted: Dictionary={}
		for tick: int in range(240):
			if tick<60:
				# Pre-contact arrangement is held; once contact begins it resolves.
				p.pos=Vector2(-38,0);e.pos=Vector2(38,0);p.vel=Vector2.ZERO;e.vel=Vector2.ZERO
				b._visual_time+=Battle.FIXED_DT;b._update_effects(Battle.FIXED_DT)
			elif tick==60:
				p.pos=Vector2(-10,0);e.pos=Vector2(10,0);p.vel=spec.a;e.vel=spec.b
				if spec.id=="numbers":
					# Existing legal Burst state amplifies real solver loss; no fake HP.
					p.burst_time=0.20;e.burst_time=0.20
				if spec.id=="elimination":e.rpm=0.005;e.energy=e.rpm
				b.resolve_pair(1,2)
				accepted=b.impact_feedback.snapshot().events.back().duplicate(true)
				if spec.id=="elimination":b.test_step(Battle.FIXED_DT)
			else:b.test_step(Battle.FIXED_DT,Vector2(-0.4,0.2))
			await frame(b,spec.id,tick,spec.id+"_contact" if tick==61 else "")
		if spec.id=="light" and accepted.get("tier","")!="light":failures.append("Light fixture not light")
		if spec.id=="edge" and accepted.get("cue","")!="metal_edge":failures.append("Edge fixture not angle-aware")
		if spec.id=="scrape" and accepted.get("cue","")!="metal_scrape":failures.append("Scrape fixture not tangent-aware")
		if spec.id=="hard" and accepted.get("tier","")!="hard":failures.append("Hard fixture not below beast threshold")
		if spec.id in ["extreme","numbers","reduced"] and accepted.get("tier","")!="extreme":failures.append("Extreme fixture not qualifying")
		scenes.append({"id":spec.id,"frames":240,"initial_fixture":spec,"accepted_collision":accepted,"beasts":b.beasts.snapshot(),"impact":b.impact_feedback.snapshot(),"outcome":e.outcome,"balance_claim":false});b.free()

func music_review() -> void:
	var b := new_battle();b.set_paused(true)
	for spec: Dictionary in [{"id":"early","time":10.0,"pressure":2.0,"bosses":0,"tier":0,"label":"EARLY / HALF-TIME BREATHING ROOM"},{"id":"mid","time":120.0,"pressure":8.0,"bosses":0,"tier":2,"label":"MID / MOTION RIFF + DRIVE"},{"id":"late","time":250.0,"pressure":10.0,"bosses":0,"tier":3,"label":"LATE / ANTHEM + FULL RHYTHM"},{"id":"extreme","time":390.0,"pressure":15.0,"bosses":1,"tier":4,"label":"EXTREME / ACCEPTED FULL-BAND IDENTITY"}]:
		captions("003A.1 MUSIC / "+spec.label,"ACTUAL SEVEN-STEM GODOT MIX / LABELLED RUN OBSERVATIONS / NO TIME OR PITCH STRETCH")
		music.observe_run({"survival_time":spec.time,"run_seed":421,"census":{"pressure":spec.pressure,"bosses":spec.bosses},"limits":{"tier":spec.tier}}, {"player_rpm":0.8})
		for tick: int in range(900):
			await frame(b,spec.id,tick,spec.id+"_music" if tick==240 else "")
		scenes.append({"id":spec.id,"frames":900,"observations_fixture":spec,"music":music.music_snapshot()})
	if music.music_snapshot().transport_starts!=1:failures.append("Music transport restarted during transitions")
	b.free()

func portable(value: Variant) -> Variant:
	if value is Vector2:return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=portable(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(portable(item))
		return result
	return value

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="):frame_dir=arg.trim_prefix("--frames=")
		if arg=="--diagnostic":diagnostic=true
	if output.is_empty() or mode not in ["impacts","music"]:quit(2);return
	root.size=Vector2i(640,400);root.content_scale_size=Vector2i(640,400);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty():DirAccess.make_dir_recursive_absolute(frame_dir)
	sound=Sound.new();root.add_child(sound);sound.rng.seed=421;sound.apply_settings({"volume":0.65,"sfx_volume":1.0})
	music=Music.new();root.add_child(music);music.configure_playback(not diagnostic);music.set_context("run")
	if mode=="impacts":await impacts()
	else:await music_review()
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(portable({"task":"003A.1 combat/audio review","mode":mode,"diagnostic":diagnostic,"movie_frames":movie_frames,"scenes":scenes,"rows":rows,"features":features,"failures":failures,"native_gameplay":[640,360],"native_caption_canvas":[640,400],"main_created":false,"collection_opened":false,"authenticity":"Labelled initial conditions/observations; actual production collision solver, renderers, synchronized Music and Sound nodes. No profile opened. Normal60FPS without editorial slow motion. Not natural balance evidence."}),"\t"));file.close()
	# Explicitly stop native mixer playback before tree teardown. Otherwise an
	# engine playback resource can survive exit even when the movie completed.
	music.configure_playback(false)
	for channel: AudioStreamPlayer in sound.channels:channel.stop()
	music.free();sound.free()
	for label: Label in labels:label.free()
	labels.clear()
	await process_frame
	print("IMPACT_MUSIC_CAPTURE_%s frames=%d" % ["PASS" if failures.is_empty() else "FAIL",movie_frames]);quit(0 if failures.is_empty() else 1)
