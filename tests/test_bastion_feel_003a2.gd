extends SceneTree
## Focused handling/audio contracts. Physical tuples used for accepted-contact
## unit boundaries are declared fixtures, not natural survival/showcase proof.
## No collection/save object is created and no player profile is accessed.
const Battle = preload("res://scripts/battle.gd")
const Starters = preload("res://scripts/starters.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Fixture = preload("res://tests/mutation_physics_fixture_003a2.gd")
const Sound = preload("res://scripts/sound.gd")
const Touch = preload("res://scripts/touch_controls.gd")
const BASE_ACCELERATION: float = 0.72
const BASE_PROFILE: Dictionary = {"acceleration":0.72,"speed":0.78,"mass":1.35,"impact":1.0,"spin_drain":1.0,"orbit":0.25,"bank":1.35,"recovery":1.3}
var checks: int = 0
var failures: Array[String] = []
var observations: Dictionary = {}
var output: String = ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func near(a: float,b: float) -> bool: return absf(a-b)<0.000001
func count(b: Node2D,key: String) -> int: return int(b.powers.defence.counters.get(key,0))
func neutral() -> void:
	for action: String in ["move_left","move_right","move_up","move_down","burst","brake"]: Input.action_release(action)
func physical(b: Node2D) -> Dictionary:
	var actors: Array = b.fighters.duplicate(true)
	for f: Dictionary in actors:
		# Only the declared experiment metadata is omitted. All other handling,
		# actor fields, control/state/cost/outcome data retain exact comparison.
		if f.has("handling"): f.handling.erase("acceleration")
	return {"actors":actors,"elapsed":b.elapsed,"status":b.battle_status,"hits":b.hits,
		"result":b.last_result.duplicate(true),"pairs":b._pair_cooldowns.duplicate(true),
		"powers":b.powers._states.duplicate(true),"power_events":b.powers.events.duplicate(true),
		"defence":b.powers.defence.states.duplicate(true),"roster":b.roster.states.duplicate(true),
		"ecology":b.roster.ecology.states.duplicate(true),"economy":b.continuous.economy.snapshot(),
		"director":b.continuous.director.history.duplicate(true)}
func make_run(acceleration: float,seed_value: int,invested: bool) -> Node2D:
	var b: Node2D=Battle.new();root.add_child(b);b.visible=false;b.set_process(false);b.set_physics_process(false)
	var d: Dictionary=Encounters.for_run_event(1,seed_value);d.starter_id="bastion"
	if invested:
		d.player_power_ids=["dead_centre","impact_sink","anchor_exchange","crash_guard"]
		d.player_power_ranks={"dead_centre":2,"impact_sink":2,"anchor_exchange":2,"crash_guard":2}
	b.begin_run(Starters.build_for("bastion"),d,seed_value)
	for tick: int in range(300):
		if b.battle_status=="battle":break
		b.test_step(Battle.FIXED_DT)
	check(b.battle_status=="battle","Actual READY completes before the handling comparison")
	b.player_entity().handling.acceleration=acceleration
	return b
func clock(b: Node2D) -> void:
	check(near(b.elapsed,b.powers.time) and near(b.elapsed,b.roster.time) and near(b.elapsed,b.roster.ecology.time) and near(b.elapsed,b.powers.defence.time),"All live mechanics use the same advancing fixed-tick epoch")
func handling() -> void:
	var chosen: Dictionary=Starters.HANDLING.bastion.duplicate(true)
	var unchanged: Dictionary=chosen.duplicate(true);unchanged.acceleration=BASE_ACCELERATION
	check(unchanged==BASE_PROFILE,"Only Bastion steering acceleration differs from the accepted profile")
	check(float(chosen.acceleration)==0.82,"Chosen .82 candidate remains below neutral acceleration")
	check(Starters.build_for("bastion")=={"blade":"guard","ratchet":"low","bit":"ball"},"Bastion remains the actual authored assembly")
	var rows: Array=[]
	for invested: bool in [false,true]:
		for seed_value: int in [421,937]:
			var before: Node2D=make_run(BASE_ACCELERATION,seed_value,invested)
			var after: Node2D=make_run(float(chosen.acceleration),seed_value,invested)
			var before_contacts: Array=[];var after_contacts: Array=[]
			before.full_top_impact_accepted.connect(func(e: Dictionary)->void:before_contacts.append(e.duplicate(true)))
			after.full_top_impact_accepted.connect(func(e: Dictionary)->void:after_contacts.append(e.duplicate(true)))
			check(physical(before)==physical(after),"Zero-input pair starts with identical physical and accounting state")
			var ticks: int=0
			for tick: int in range(7200):
				before.test_step(Battle.FIXED_DT,Vector2.ZERO,false,false)
				after.test_step(Battle.FIXED_DT,Vector2.ZERO,false,false)
				check(physical(before)==physical(after),"No-input actor/RPM/contact/outcome trajectory remains exact")
				check(before_contacts==after_contacts,"Accepted zero-input contact impulses and losses remain exact")
				ticks=tick+1
				if before.battle_status=="finished" and after.battle_status=="finished":break
			clock(before);clock(after)
			rows.append({"seed":seed_value,"initial_invested_loadout":invested,"fixed_step_calls":ticks,"seconds":before.elapsed,"contacts":before_contacts.size(),"result":before.last_result.duplicate(true),"final_rpm":before.player_entity().rpm,"exact":physical(before)==physical(after)})
			before.free();after.free()
	observations.zero_input=rows
	observations.handling={"before":BASE_PROFILE,"candidate":chosen,"zero_input_benefit":false}
func mapped_vectors() -> void:
	neutral()
	var provider: Node2D=Touch.new();root.add_child(provider);provider.set_enabled(true)
	var key:=InputEventKey.new();key.keycode=KEY_D;key.physical_keycode=KEY_D;key.pressed=true
	Input.parse_input_event(key)
	for frame: int in range(2):await process_frame
	var keyboard: Vector2=provider.sample().direction
	key.pressed=false;Input.parse_input_event(key)
	for frame: int in range(2):await process_frame
	var pad:=InputEventJoypadMotion.new();pad.device=7;pad.axis=JOY_AXIS_LEFT_X;pad.axis_value=1.0;Input.parse_input_event(pad)
	for frame: int in range(2):await process_frame
	var controller: Vector2=provider.sample().direction
	pad.axis_value=0.0;Input.parse_input_event(pad)
	for frame: int in range(2):await process_frame
	var origin: Vector2=Rect2(provider.layout_snapshot().steering_rect).get_center()
	var finger:=InputEventScreenTouch.new();finger.index=9;finger.position=origin;finger.pressed=true
	check(provider.handle_touch(finger),"Real touch ownership acquires a steering contact")
	var drag:=InputEventScreenDrag.new();drag.index=9;drag.position=origin+Vector2(Touch.MAX_RADIUS,0);provider.handle_touch(drag)
	var touch_vector: Vector2=provider.sample().direction
	check(keyboard==Vector2.RIGHT and controller==keyboard and touch_vector==keyboard,"Keyboard/controller/touch providers deliver the identical literal normalized steering vector")
	finger.pressed=false;provider.handle_touch(finger);neutral()
	check(provider.sample().direction==Vector2.ZERO,"Released mapped inputs leave no stale steering")
	observations.input={"keyboard":keyboard,"controller":controller,"touch":touch_vector,"scope":"Synthetic Godot mapped events; no physical hardware acceptance"}
	provider.free()
func unit(family: String,branch: String,owner: int=1) -> Node2D:
	return Fixture.create(root,family,branch,owner)
func actual_hit(b: Node2D,owner: int=1) -> void:
	# This is an explicit accepted-contact boundary tuple, not a frame hold.
	var p: Dictionary=b.entity(owner);var rival: Dictionary=b.entity(2 if owner==1 else 1)
	p.pos=Vector2.ZERO;p.vel=Vector2.ZERO
	rival.pos=Vector2(24,0);rival.vel=Vector2(-160,0)
	b.resolve_pair(int(p.entity_id),int(rival.entity_id))
func earned_states() -> void:
	for owner: int in [1,2]:
		var sink: Node2D=unit("impact_sink","return_spring",owner);var p: Dictionary=sink.entity(owner)
		for tick: int in range(15):sink.fixture_step(Vector2.ZERO,false,true)
		check(count(sink,"sink_return")==0 and float(p.sink_charge)==0.0,"Empty and held Brake never fabricates stored force or a counter")
		actual_hit(sink,owner)
		check(float(p.sink_charge)>=15.0 and count(sink,"sink_store")==1,"Canonical accepted recoil earns real finite Sink store")
		check(float(p.sink_charge)<=150.0,"Actual recoil storage retains its finite owner capacity")
		for tick: int in range(15):sink.fixture_step(Vector2.ZERO,false,true)
		check(count(sink,"sink_return")==0,"Held Brake after a hit cannot fabricate a fresh vent edge")
		sink.fixture_step(Vector2.ZERO,false,false)
		var before: float=p.rpm
		sink.fixture_step(Vector2.ZERO,false,true)
		check(count(sink,"sink_return")==1 and float(p.sink_charge)==0.0,"A real fresh low-speed Brake consumes the earned reservoir exactly once")
		check(float(p.rpm)<before-.0079,"Return Spring pays its real .008 counter cost plus ordinary running costs")
		for tick: int in range(30):sink.fixture_step(Vector2.ZERO,false,true)
		check(count(sink,"sink_return")==1,"Held/empty Brake cannot repeat a paid counter")
		clock(sink);sink.free()
		var anchor: Node2D=unit("anchor_exchange","slip_anchor",owner);p=anchor.entity(owner)
		for tick: int in range(45):anchor.fixture_step(Vector2.RIGHT*.2,false,true)
		check(float(p.exchange_charge)>=.60,"Deliberate paid Brake earns actual portable footing")
		before=p.rpm;anchor.fixture_step(Vector2.RIGHT*.7,false,false)
		check(count(anchor,"exchange_release")==1 and float(p.exchange_charge)==0.0 and float(anchor.powers.defence.state(p).carry)>0.0,"Aimed fresh release carries finite earned brace without a free reserve gain")
		check(float(p.rpm)<before,"Portable release preserves ordinary RPM attrition")
		anchor.fixture_step(Vector2.RIGHT*.2,false,false)
		check(float(p.exchange_carry)>0.0,"Next fixed-tick publication exposes the still-live earned carry")
		for tick: int in range(24):anchor.fixture_step(Vector2.RIGHT*.2,false,false)
		check(float(p.exchange_carry)==0.0 and count(anchor,"exchange_release")==1,"Release carry expires and cannot retrigger from an empty brace")
		clock(anchor);anchor.free()
		var counter: Node2D=unit("dead_centre","counterweight",owner);p=counter.entity(owner)
		for tick: int in range(90):counter.fixture_step(Vector2.RIGHT*.2,false,true)
		check(float(p.anchor_charge)>=.70 and float(p.stored_force)==0.0,"Floor engagement is earned by controls and stores no force before impact")
		actual_hit(counter,owner)
		check(float(p.stored_force)>=12.0 and float(p.stored_force)<=150.0,"Accepted anchored force earns bounded Counterweight storage")
		counter.fixture_step(Vector2.RIGHT*.7,false,false);before=p.rpm
		counter.fixture_step(Vector2.RIGHT*.7,true,false)
		check(float(p.stored_force)==0.0 and float(p.anchor_charge)==0.0 and int(counter.powers.counters.get("counterweight_release",0))==1,"Aimed accepted Burst consumes force once and breaks the floor hold")
		check(float(p.rpm)<before-.0129 and float(p.cooldown)>3.9,"Counterweight release retains the ordinary paid Burst/cooldown")
		counter.fixture_step(Vector2.RIGHT*.7,true,false)
		check(int(counter.powers.counters.get("counterweight_release",0))==1,"Empty/cooldown Burst cannot repeat Counterweight release")
		clock(counter);counter.free()
		var reactive: Node2D=unit("crash_guard","reactive_plating",owner);p=reactive.entity(owner)
		actual_hit(reactive,owner)
		check(float(p.reactive_force)>0.0 and int(reactive.roster.ecology.counters.get("reactive_charge",0))==1,"A true canonical heavy incoming contact earns the short plating window")
		check(int(reactive.roster.ecology.counters.get("reactive_counter",0))==0,"The charge contact cannot spend its own newly earned counter")
		for tick: int in range(60):reactive.fixture_step(Vector2.ZERO,false,false)
		check(float(p.reactive_force)==0.0 and int(reactive.roster.ecology.counters.get("reactive_counter",0))==0,"Unused plating expires without an automatic counter")
		clock(reactive);reactive.free()

func audio() -> void:
	var sources: Dictionary={}
	for path: String in ["res://scripts/starters.gd","res://scripts/sound.gd","res://scripts/battle.gd","res://scripts/power_runtime.gd","res://scripts/defence_runtime.gd"]:sources[path]=FileAccess.get_file_as_bytes(path)
	var b: Node2D=make_run(BASE_ACCELERATION,421,false);var frozen: Dictionary=physical(b)
	var sound: Node=Sound.new();root.add_child(sound);sound.set_process(false)
	check(sound.channels.size()==8 and Sound.MAX_CHANNELS==8 and near(Sound.MIX_PEAK_BUDGET,.62),"Defensive cues retain the existing eight-channel and headroom budgets")
	var expected: Dictionary={"gyro_lock_set":["anchor",-16.,.55],"gyro_lock_break":["anchor_break",-17.,.35],"sink_store":["counterweight_store",-17.,.35],"sink_vent":["momentum_release",-14.,.60],"sink_return":["counterweight_release",-13.,.60],"exchange_set":["crash_guard",-16.,.55],"exchange_release":["momentum_release",-15.,.40]}
	check(Sound.DEFENCE_CUES.size()==7,"Exactly the seven actual defence events receive named routing")
	for kind: String in expected:
		var cue: Dictionary=Sound.DEFENCE_CUES.get(kind,{})
		check(cue.get("sample","")==expected[kind][0] and near(float(cue.get("gain",0)),expected[kind][1]) and near(float(cue.get("cooldown",0)),expected[kind][2]) and int(cue.get("priority",0))==2,"Named defensive cue uses bounded quiet existing sample: "+kind)
		sound.audio_time+=2.0;sound.play_sound(kind)
		check(int(sound.played_counts.get(kind,0))==1,"Actual semantic cue is no longer silently dropped: "+kind)
		check(sound.channels[sound.current].stream==Sound.SOUNDS[cue.sample] and sound.channel_priority[sound.current]==2 and near(sound._channel_base_db[sound.current],float(cue.gain)),"Actual sample, priority and pre-headroom gain preserve semantic identity")
		sound.play_sound(kind)
		check(int(sound.played_counts[kind])==1,"Same-key cooldown suppresses duplicate cue")
		for player: AudioStreamPlayer in sound.channels:player.stop()
		var muted_counts: Dictionary=sound.played_counts.duplicate(true);sound.muted=true;sound.audio_time+=2.0;sound.play_sound(kind)
		check(sound.played_counts==muted_counts,"Mute prevents named cue playback")
		sound.muted=false
	for kind: String in expected:sound.audio_time+=2.0;sound.play_sound(kind)
	sound._apply_headroom(0.0)
	check(sound.audio_snapshot().active<=8 and float(sound.audio_snapshot().worst_case_sfx_peak)<=.620001,"Simultaneous earned defence cues remain bounded and within phase-independent headroom")
	for player: AudioStreamPlayer in sound.channels:player.stop()
	for index: int in range(8):sound.audio_time+=1.0;sound.play_sound("metal_extreme")
	var prior: Dictionary=sound.played_counts.duplicate(true);sound.audio_time+=1.0;sound.play_sound("sink_return")
	check(sound.played_counts==prior,"Quiet defence cue cannot evict any occupied high-priority impact channel")
	check(physical(b)==frozen,"Playback changes no live actor, RPM, contact, power, Director or outcome state")
	for path: String in sources:check(FileAccess.get_file_as_bytes(path)==sources[path],"Playback never changes its gameplay or audio source")
	observations.audio=sound.audio_snapshot();observations.audio.semantic_keys=expected.keys()
	for player: AudioStreamPlayer in sound.channels:player.stop();player.stream=null
	sound._grind_player.stop();sound._grind_player.stream=null
	# AudioServer owns deferred playback references. The retained audio suite
	# drains these after explicit stop before freeing its bounded player nodes.
	await create_timer(.60).timeout
	sound.free();b.free()
	await process_frame
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	if not output.is_empty() and (not output.is_absolute_path() or FileAccess.file_exists(output) or not output.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/")):
		push_error("Fresh external003A.2 report required");quit(2);return
	neutral();handling();await mapped_vectors();earned_states();await audio();neutral()
	if not output.is_empty():
		var file=FileAccess.open(output,FileAccess.WRITE)
		if file==null:push_error("Cannot write fresh evidence");quit(2);return
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"Synthetic mapped events, exact fixed-tick no-input Run pairs, actual accepted-contact unit tuples and real AudioStream routing. Unit contact tuples and known live loadouts are declared QA fixtures; no natural survival, hardware audio, player profile or human acceptance claim."},"\t"));file.close()
	print("BASTION_FEEL_003A2_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()]);quit(0 if failures.is_empty() else 1)
