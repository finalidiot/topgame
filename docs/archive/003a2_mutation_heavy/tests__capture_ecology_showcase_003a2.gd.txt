extends "res://tests/capture_impact_music_003a1.gd"
## Actual fixed ticks after disclosed legal loadout/pose, with sampled controls.
const EcologyFixture = preload("res://tests/ecology_showcase_fixture_003a2.gd")
const DraftPolicy = preload("res://tests/mutation_draft_policy_003a2.gd")
var actor_samples: Array[Dictionary]=[]
var only_scene: String=""

func play_ecology(spec: Dictionary) -> void:
	var scene: Dictionary=EcologyFixture.create(root,spec);var b: Node2D=scene.battle
	b.visible=not diagnostic;b.event_sfx.connect(cue);sound.grind_provider=b.grind_audio_snapshot
	var seen: Dictionary={}
	for tick: int in range(600):
		var control: Dictionary=EcologyFixture.step(scene,tick)
		var feature: String=""
		for kind: String in b.roster.ecology.counters:
			if int(b.roster.ecology.counters[kind])>int(seen.get(kind,0)):
				seen[kind]=b.roster.ecology.counters[kind];feature=str(spec.id)+"_"+kind+"_%d"%int(seen[kind])
		if tick in [0,120,300,599] and feature.is_empty():feature=str(spec.id)+"_%04d"%tick
		if tick%6==0 or not feature.is_empty():actor_samples.append({"scene":spec.id,"tick":tick,"frame":movie_frames,"controls":control,"state":b.fixture_snapshot()})
		captions("003A.2 / "+str(spec.title),"LEGAL INITIAL LOADOUT + POSE / CONTROLS + REAL SOLVER / COSTS, CONTACTS, EXITS")
		await frame(b,str(spec.id),tick,feature)
	for kind: String in spec.events:
		if int(b.roster.ecology.counters.get(kind,0))==0:failures.append(str(spec.id)+" missing real "+kind)
	for kind: String in spec.get("existing_events",[]):
		if int(b.powers.counters.get(kind,0))==0:failures.append(str(spec.id)+" missing existing paid "+kind)
	if spec.id=="endurance" and (float(scene.peak_orbit)<1.0 or int(scene.flow_frames)<60):failures.append("endurance did not earn full DRIVE through actual curve")
	if spec.id=="endurance" and int(b.powers.counters.get("orbit_full_recovery",0))==0:failures.append("endurance did not earn actual capped full-flow recovery")
	if int(scene.clock_failures)>0:failures.append(str(spec.id)+" clocks diverged")
	scenes.append({"id":spec.id,"family":spec.family,"branch":spec.branch,"frames":600,"initial":scene.initial,"control_history":scene.controls,"contacts":scene.contacts,"peak_orbit":scene.peak_orbit,"peak_bank":scene.peak_bank,"flow_frames":scene.flow_frames,"existing_power_counters":b.powers.counters.duplicate(),"final":b.fixture_snapshot(),"clock_failures":scene.clock_failures,"balance_claim":false})
	sound.grind_provider=Callable();sound.set_grind_state({"active":false});b.free()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="):frame_dir=arg.trim_prefix("--frames=")
		if arg=="--diagnostic":diagnostic=true
		if arg.begins_with("--scene="):only_scene=arg.trim_prefix("--scene=")
	if output.is_empty() or not output.is_absolute_path() or FileAccess.file_exists(output):quit(2);return
	root.size=Vector2i(640,400);root.content_scale_size=Vector2i(640,400);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty():DirAccess.make_dir_recursive_absolute(frame_dir)
	sound=Sound.new();root.add_child(sound);sound.rng.seed=421;sound.apply_settings({"volume":.65,"sfx_volume":1.0})
	music=Music.new();root.add_child(music);music.configure_playback(not diagnostic);music.set_context("run")
	for spec: Dictionary in EcologyFixture.SPECS:
		if only_scene.is_empty() or only_scene==spec.id:await play_ecology(spec)
	music.configure_playback(false);sound.grind_provider=Callable();sound._grind_player.stop()
	for channel: AudioStreamPlayer in sound.channels:channel.stop();channel.stream=null
	for label: Label in labels:label.free()
	labels.clear()
	var tail: int=0
	if not diagnostic:
		for tick: int in range(36):await process_frame;movie_frames+=1;tail+=1
	music.free();sound.free();await process_frame
	var data: Dictionary={"task":"003A.2 actual ecology showcase","diagnostic":diagnostic,"movie_frames":movie_frames,"tail_frames":tail,"scenes":scenes,"actor_samples":actor_samples,"audio_feedback_rows":rows,"features":features,"failures":failures,"native_gameplay":[640,360],"native_caption_canvas":[640,400],"main_created":false,"collection_opened":false,"authenticity":"Eight legal initial loadout/position/velocity fixtures; only sampled ordinary controls after initialization. Actual 60Hz Battle solver, family costs, hooks, power causes and renderer. No charges/activation/poses/reserves/outcomes written after initialization. NPC neutral/chase controls are disclosed, Director extra admissions suspended. Not natural draft, pilot or survival evidence."}
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Fresh QA manifest parent must exist");quit(2);return
	file.store_string(JSON.stringify(DraftPolicy.portable(data),"\t"));file.close()
	print("ECOLOGY_SHOWCASE_%s frames=%d failures=%s"%["PASS" if failures.is_empty() else "FAIL",movie_frames,failures]);quit(0 if failures.is_empty() else 1)
