extends SceneTree
## Bounded contact/lifetime fixtures. No real player save or reserve is opened.
const Battle = preload("res://scripts/battle.gd")
const Run = preload("res://scripts/run_context.gd")
const Pickups = preload("res://scripts/run_pickups.gd")
const Sound = preload("res://scripts/sound.gd")
const BUILD: Dictionary = {"blade":"guard","ratchet":"mid","bit":"ball"}
var checks: int = 0
var failures: int = 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func fixture() -> Dictionary:
	var run_context: RefCounted = Run.new();run_context.start(BUILD,421,"bastion")
	check(run_context.choose_power(run_context.pending_draft_id,run_context.pending_offer[0]),"Actual opening draft enables fixture Run")
	var b: Node2D = Battle.new();root.add_child(b);b.set_process(false);b.set_physics_process(false)
	b.begin_run(BUILD,run_context.current_encounter(),421)
	b.battle_status="battle";b.elapsed=1.0;b.player_entity().pos=Vector2.ZERO
	var tokens: Node2D = Pickups.new();b.add_child(tokens);tokens.set_process(false);tokens.setup(b,run_context)
	tokens.render_in_battle=true;b.floor_pickups=tokens
	tokens.items.append({"id":"fixture/chip","pos":Vector2(65,0),"born":1.0})
	var cues: Array[String] = []
	b.event_sfx.connect(func(kind: String) -> void: cues.append(kind))
	return {"battle":b,"run":run_context,"tokens":tokens,"cues":cues}
func advance(f: Dictionary, seconds: float, point: Vector2) -> void:
	f.battle.elapsed += seconds;f.battle.player_entity().pos=point;f.tokens.update_simulation()
func run() -> void:
	var f: Dictionary = fixture()
	var rpm: float = f.battle.player_entity().rpm
	advance(f,0.1,Vector2(44,0))
	for i: int in range(100): advance(f,0.05,Vector2(44,0))
	check(f.tokens.items.size()==1 and f.run.rerolls_collected==0,"Stationary top three units beyond contact cannot vacuum a chip")
	check(f.tokens.items[0].pos==Vector2(65,0) and not f.tokens.presentation_snapshot().attraction,"No item attraction, passive travel or near-field pull exists")
	advance(f,0.1,Vector2(65,17))
	check(f.run.rerolls_collected==1 and f.tokens.items.is_empty(),"Slightly off-centre swept approach collects within modest forgiveness")
	check(f.battle.player_entity().rpm==rpm,"Reroll chip changes no RPM, economy or permanent currency")
	check(f.cues==["pickup_collect"],"One successful receipt emits the dedicated collection cue exactly once")
	var shown: Dictionary = f.tokens.presentation_snapshot()
	check(shown.collection_flairs.size()==1 and shown.collection_flairs[0].frame==0,"One authored floor burst begins on collection")
	check(shown.collection_flairs[0].pos==Vector2(65,0),"Flair stays at actual collected chip, not the rotor")
	f.tokens.update_simulation()
	check(f.cues.size()==1 and f.tokens.presentation_snapshot().collection_flairs.size()==1,"Repeated draw cannot duplicate audio or flair")
	f.battle.paused=true;advance(f,1.0,Vector2(70,17))
	check(f.tokens.presentation_snapshot().collection_flairs==shown.collection_flairs,"Pause freezes authored receipt clock instead of skipping its recovery")
	f.battle.paused=false;advance(f,0.01,Vector2(70,17))
	check(f.tokens.presentation_snapshot().collection_flairs.is_empty(),"Coarse resumed clock cleanly expires receipt without stale frame")
	f.tokens.items.append({"id":"fixture/chip","pos":Vector2(70,17),"born":f.battle.elapsed})
	advance(f,0.01,Vector2(70,17))
	check(f.run.rerolls_collected==1 and f.cues.size()==1 and f.tokens.presentation_snapshot().collection_flairs.is_empty(),"Duplicate paid pickup id creates neither extra charge nor theatrical receipt")
	f.battle.free()
	f=fixture();advance(f,Pickups.LIFETIME,Vector2(65,0))
	check(f.tokens.expired_count==1 and f.cues.is_empty() and f.tokens.presentation_snapshot().collection_flairs.is_empty(),"Expiry has no collection sound or burst even on the collision tick")
	f.battle.free()
	for reduced: bool in [false,true]:
		f=fixture();f.tokens.reduced_flashing=reduced;advance(f,0.1,Vector2(65,0))
		check(f.tokens.presentation_snapshot().collection_flairs[0].frame==0,"Reduced Flashing retains receipt without pulse substitution")
		var last: int = -1
		for tick: int in range(63):
			var age: float = float(tick)*0.005
			var frame: int = Pickups.collection_frame(age)
			check(frame>=last or frame==-1,"Authored animation timeline only advances")
			if frame>=0: last=frame
		check(last==5 and Pickups.collection_frame(0.31)==-1 and Pickups.collection_frame(-0.01)==-1,"All six frames finish and invalid ages hide cleanly")
		f.battle.free()
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/powers/pickup_003a1/manifest.json"))
	check(meta.native_runtime_rgba_exact and meta.floor_only and not meta.loop,"Collection uses native exported authored floor cels")
	check(int(meta.cell[0])==40 and int(meta.cell[1])==24 and int(meta.pivot[0])==20 and int(meta.pivot[1])==12 and int(meta.frame_count)==6,"Native pixel cell, floor pivot and six frames agree")
	for index: int in range(Pickups.COLLECTION_TIMINGS_MS.size()):
		check(int(meta.durations_ms[index])==Pickups.COLLECTION_TIMINGS_MS[index],"Runtime frame timing matches editable Aseprite timeline")
	check(int(meta.duration_ms)==310,"Complete authored burst remains brief")
	check(meta.filter=="nearest" and meta.layers.size()==3 and int(meta.tags.collect.from)==0 and int(meta.tags.collect.to)==5,"Native layers/tags survive export with nearest presentation")
	var sample: AudioStreamWAV = Sound.SOUNDS.pickup_collect
	check(sample.get_length()>0.1 and sample.get_length()<0.5 and sample.loop_mode==AudioStreamWAV.LOOP_DISABLED,"Distinct pickup sample is a short one-shot rather than a music/stinger loop")
	check(Sound.SOUNDS.pickup_collect.resource_path!=Sound.SOUNDS.card_select.resource_path,"Floor collection has its own sound identity")
	check(Sound.COOLDOWN.pickup_collect==0.0 and Sound.PRIORITY.pickup_collect==5,"Independent physical receipts have no artificial audio cooldown and survive lesser contact cues")
	if DisplayServer.get_name() != "headless":
		var sound: Node = Sound.new();root.add_child(sound);sound.set_process(false)
		sound.play_sound("pickup_collect");sound.play_sound("pickup_collect")
		check(sound.played_counts.get("pickup_collect",0)==2,"Two independent simultaneous physical receipts are both audible")
		check(sound.channels[sound.current].volume_db<=-6.0 and sound.channels[sound.current].pitch_scale==1.0,"Pickup audio is restrained and keeps its short authored pitch")
		sound.muted=true;sound.play_sound("pickup_collect")
		check(sound.played_counts.get("pickup_collect",0)==2,"Existing mute preference suppresses pickup cue")
		await create_timer(0.25).timeout
		sound.free()
	else:
		print("HEADLESS_AUDIO_PLAYBACK_SKIPPED: rendered movie records actual pickup playback")
	f.clear();shown.clear();sample=null
	await process_frame
	await process_frame
	print("PICKUP_FEEL_003A1_%s checks=%d failures=%d" % ["PASS" if failures==0 else "FAIL",checks,failures]);quit(1 if failures else 0)
