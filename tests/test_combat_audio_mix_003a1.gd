extends SceneTree
const Feedback = preload("res://scripts/combat_impact_feedback.gd")
const Sound = preload("res://scripts/sound.gd")
const Battle = preload("res://scripts/battle.gd")
var checks: int = 0
var failures: Array[String] = []
var report: String = ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks += 1
	if not ok: failures.append(text);push_error(text)
func hit(id: int,severity: float,closing: float,impulse: float) -> Dictionary:
	return {"collision_id":id,"severity":severity,"closing":closing,"impulse":impulse,"position":Vector2.ZERO,"contact_position":Vector2(4,8),"contact_height":11.0,"normal":Vector2.RIGHT,"first_velocity":Vector2(closing,0),"second_velocity":Vector2.ZERO,"first_entity_id":1,"second_entity_id":2,"first_position":Vector2(-12,0),"second_position":Vector2(12,0),"first_rpm_loss":0.0,"second_rpm_loss":0.0}
func bodies() -> Array[Dictionary]:
	return [{"entity_id":1,"combatant_type":"full_top","outcome":"","rpm":0.8,"radius":12.0,"height":0.0,"pos":Vector2(-12,0),"vel":Vector2(0,80)},{"entity_id":2,"combatant_type":"full_top","outcome":"","rpm":0.8,"radius":12.0,"height":0.0,"pos":Vector2(12,0),"vel":Vector2(0,-40)}]
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
	var f = Feedback.new()
	for row: Array in [[.1,50.,100.,"metal_light"],[.4,130.,500.,"metal_normal"],[.9,240.,1400.,"metal_clang"],[.9,250.,2000.,"metal_massive"],[.9,250.,4000.,"metal_extreme"]]:
		check(Feedback.audio_family(hit(1,row[0],row[1],row[2]))==row[3],"Distinct physical audio ladder: "+str(row[3]))
	check(not Feedback.qualifies_crack(hit(1,.9,250.,1999.999)) and Feedback.qualifies_crack(hit(1,.9,250.,2000.)),"Crack work threshold is exactly500000, above routine contact work")
	check(not Feedback.qualifies_crack(hit(1,.749,250.,2000.)),"A high-work but sub-hard contact cannot add lightning")
	check(not Feedback.qualifies_crack(hit(1,.9,139.,500000./139.)),"Low normal speed cannot add a hard-tier energy arc")
	check(Feedback.qualifies_crack(hit(1,.7,250.,4000.)),"Existing beast qualification still grants its extreme energy accent")
	var event: Dictionary = hit(1,.9,250.,2000.)
	var original: Dictionary = event.duplicate(true)
	check(f.accept_impact(event).crack_cue=="metal_crack" and event==original,"One accepted high-work event adds one crack without solver writes")
	check(f.snapshot().cracks.size()==1 and f.snapshot().cracks[0].position==Vector2(4,8) and f.snapshot().cracks[0].height==11.,"Arc attaches to real contact and height")
	check(f.accept_impact(event).is_empty() and f.snapshot().cracks.size()==1,"Duplicate collision cannot duplicate crack")
	event.collision_id=2
	check(f.accept_impact(event).crack_cue.is_empty(),"Adjacent high-work collisions cannot machine-gun crack accents")
	f.update(.15)
	check(f.snapshot().cracks.is_empty(),"Crack is strictly shorter than0.2seconds")
	f.update(.08);event.collision_id=3
	check(f.accept_impact(event).crack_cue=="metal_crack","A genuinely new large hit may accent after cooldown")
	var art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/powers/impact_003a1/crack_manifest.json"))
	check(art.segments.hard>=2 and art.segments.extreme<=5 and art.maximum_lifetime_seconds<.2 and not art.loop,"Native arcs have bounded authored segments and finite lifetime")
	f.reset();var tops: Array[Dictionary] = bodies();var frozen: Array = tops.duplicate(true)
	f.observe_grinding(tops,.05)
	check(not f.grind_snapshot().active,"An isolated tangential brush is not sustained grinding")
	for i: int in range(8): f.observe_grinding(tops,1./60.)
	check(f.grind_snapshot().active and f.grind_snapshot().pairs==1,"Continued near-surface tangential motion starts genuine grinding")
	check(tops==frozen,"Grinding observer never writes positions, velocity, RPM or input")
	var replay = Feedback.new();var reversed: Array[Dictionary] = [tops[1],tops[0]]
	replay.observe_grinding(reversed,.05)
	for i: int in range(8): replay.observe_grinding(reversed,1./60.)
	check(replay.grind_snapshot()==f.grind_snapshot(),"Pair ordering cannot alter grinding state")
	tops[1].pos=Vector2(60,0)
	for i: int in range(5): f.observe_grinding(tops,1./60.)
	check(not f.grind_snapshot().active,"Surface separation ends contact after a bounded jitter grace")
	for mode: String in ["stationary","normal_separation","airborne","retired"]:
		f.reset();tops=bodies()
		match mode:
			"stationary": tops[0].vel=Vector2.ZERO;tops[1].vel=Vector2.ZERO
			"normal_separation": tops[0].vel=Vector2(-100,80)
			"airborne": tops[1].height=20.
			"retired": tops[1].outcome="spin_out"
		for i: int in range(30): f.observe_grinding(tops,1./60.)
		check(not f.grind_snapshot().active,mode+" never fabricates a metal grind")
	f.reset();check(not f.grind_snapshot().active,"Restart/reset clears contact continuity")
	var s: Node = Sound.new();root.add_child(s);s.set_process(false)
	await process_frame
	s.set_grind_state({"active":true,"strength":.7,"pitch":1.04})
	for i: int in range(60): s.advance_grind(1./60.)
	check(s.audio_snapshot().grind_starts==1 and s.audio_snapshot().grind_active,"Sustained contact plays one persistent loop, never one sample per tick")
	var grind: AudioStreamWAV=s._grind_player.stream as AudioStreamWAV
	check(grind!=null and grind.format==AudioStreamWAV.FORMAT_16_BITS and grind.data.size()==64000 and grind.mix_rate==32000,"Real persistent grind import retains authored one-second mono PCM, preventing compressed-data loop truncation")
	check(grind!=null and grind.loop_begin==0 and grind.loop_end==32000 and absf(grind.get_length()-1.0)<.000001,"Actual persistent loop spans every authored PCM frame exactly once")
	var held: float = s.audio_snapshot().grind_level
	s.set_grind_state({"active":false});s.advance_grind(1./60.)
	check(s.audio_snapshot().grind_level>0 and s.audio_snapshot().grind_level<held,"Loss of contact smoothly releases the quiet loop")
	for i: int in range(90): s.advance_grind(1./60.)
	check(not s.audio_snapshot().grind_active and s.audio_snapshot().grind_stops==1,"Grind releases to silence and stops once")
	var previous: float = -100.
	for key: String in ["metal_light","metal_normal","metal_clang","metal_massive","metal_extreme"]:
		check(float(Sound.IMPACT_GAIN[key])>previous,"Impact hierarchy rises without every contact being loud: "+key)
		previous=Sound.IMPACT_GAIN[key]
	check(Sound.GRIND_DB<Sound.IMPACT_GAIN.metal_light and Sound.IMPACT_GAIN.metal_scrape<Sound.IMPACT_GAIN.metal_normal,"Grinding/friction sit beneath even ordinary metal hits")
	s.set_grind_state({"active":true,"strength":1.0,"pitch":1.0})
	for i: int in range(30):s.advance_grind(1./60.)
	for key: String in ["metal_normal","metal_clang","metal_edge","metal_scrape","metal_massive","metal_extreme","metal_crack","metal_takedown"]: s.play_sound(key)
	s._apply_headroom(0.)
	check(s.audio_snapshot().worst_case_sfx_peak<=Sound.MIX_PEAK_BUDGET+.000001,"Worst simultaneous eight cues remain inside phase-independent SFX headroom")
	check(s.audio_snapshot().active<=Sound.MAX_CHANNELS,"New impact layers keep the eight-one-shot channel budget")
	check(s.channels.size()==8 and s.get_child_count()==9 and s.audio_snapshot().grind_active,"The one persistent grind loop shares the budget with eight bounded one-shots")
	var b: Node2D = Battle.new();root.add_child(b);b.set_physics_process(false);b.set_process(false)
	b.begin({"blade":"smash","ratchet":"high","bit":"flat"},{"blade":"guard","ratchet":"low","bit":"ball"},1,421)
	b.set_paused(true)
	check(not b.grind_audio_snapshot().get("active",false),"Paused/READY integration cannot leave live grinding")
	b.free()
	for player: AudioStreamPlayer in s.channels: player.stop();player.stream=null
	s._grind_player.stop();s._grind_player.stream=null
	await create_timer(.60).timeout
	s.free()
	await process_frame
	if not report.is_empty():
		check(not FileAccess.file_exists(report),"Preserve prior audio test evidence")
		var file=FileAccess.open(report,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("COMBAT_AUDIO_MIX_003A1_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
