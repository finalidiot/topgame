extends "res://tests/capture_impact_music_003a1.gd"
## Isolated native solver/audio ladder. Held grinding geometry is explicitly
## labelled; no save, progression grant or natural balance claim.
func new_battle() -> Node2D:
	var b: Node2D = super.new_battle()
	sound.grind_provider = b.grind_audio_snapshot
	return b
func frame(b: Node2D, scene: String, tick: int, feature: String = "") -> void:
	if diagnostic:
		sound.set_grind_state(b.grind_audio_snapshot())
		sound.advance_grind(Battle.FIXED_DT)
		sound._apply_headroom(Battle.FIXED_DT)
	await super.frame(b,scene,tick,feature)
func release_battle(b: Node2D) -> void:
	sound.grind_provider=Callable();sound.set_grind_state({"active":false});b.free()
func impacts() -> void:
	for spec: Dictionary in [
		{"id":"light","label":"LIGHT / RESTRAINED STEEL TICK","a":Vector2(22,0),"b":Vector2(-18,0),"cue":"metal_light"},
		{"id":"normal","label":"NORMAL / CLEAR MODERATE METAL","a":Vector2(60,0),"b":Vector2(-50,0),"cue":"metal_normal"},
		{"id":"hard","label":"HARD / HEAVY STEEL BODY","a":Vector2(130,0),"b":Vector2(-80,0),"cue":"metal_clang"},
		{"id":"massive","label":"MASSIVE / SHORT LOCAL CRACK","a":Vector2(180,0),"b":Vector2(-120,0),"cue":"metal_massive"},
		{"id":"extreme","label":"EXTREME / BEAST-WORTHY DISCHARGE","a":Vector2(390,0),"b":Vector2(-390,0),"cue":"metal_extreme"},
		{"id":"elimination","label":"ELIMINATION / DISTINCT METAL PAYOFF","a":Vector2(260,0),"b":Vector2(-200,0),"cue":""},
		{"id":"reduced","label":"EXTREME / REDUCED FLASHING","a":Vector2(390,0),"b":Vector2(-390,0),"cue":"metal_extreme"}]:
		var b: Node2D=new_battle();var p: Dictionary=b.player_entity();var e: Dictionary=b.entity(2)
		b.reduced_flashing=spec.id=="reduced"
		captions("003A.1 / "+spec.label,"REAL SOLVER / DISCLOSED INITIAL CONTACT VELOCITIES / NATIVE MUSIC + SFX / 60FPS")
		var accepted: Dictionary={}
		for tick: int in range(240):
			if tick<60:
				p.pos=Vector2(-38,0);e.pos=Vector2(38,0);p.vel=Vector2.ZERO;e.vel=Vector2.ZERO
				b._visual_time+=Battle.FIXED_DT;b._update_effects(Battle.FIXED_DT)
			elif tick==60:
				p.pos=Vector2(-10,0);e.pos=Vector2(10,0);p.vel=spec.a;e.vel=spec.b
				if spec.id=="elimination":e.rpm=.005;e.energy=e.rpm
				b.resolve_pair(1,2);accepted=b.impact_feedback.snapshot().events.back().duplicate(true)
				if spec.id=="elimination":b.test_step(Battle.FIXED_DT)
			else:b.test_step(Battle.FIXED_DT,Vector2(-.4,.2))
			await frame(b,spec.id,tick,spec.id+"_contact" if tick==61 else "")
		if not str(spec.cue).is_empty() and accepted.get("cue","")!=spec.cue:failures.append(spec.id+" actual cue="+str(accepted.get("cue","")))
		if spec.id in ["massive","extreme","reduced"] and accepted.get("crack_cue","")!="metal_crack":failures.append(spec.id+" lacked qualifying crack")
		scenes.append({"id":spec.id,"frames":240,"initial_fixture":spec,"accepted_collision":accepted,"sounds":sound.audio_snapshot(),"balance_claim":false})
		release_battle(b)
		if spec.id=="normal":await grinding()
	await concurrent_mix()
	# Stop the persistent loop explicitly before inherited native teardown.
	sound.grind_provider=Callable();sound.set_grind_state({"active":false});sound._grind_player.stop()
func grinding() -> void:
	var b: Node2D=new_battle();var p: Dictionary=b.player_entity();var e: Dictionary=b.entity(2)
	captions("003A.1 / SUSTAINED GRIND / QUIET MECHANICAL TEXTURE","HELD SURFACE-GEOMETRY FIXTURE / REAL GAP + TANGENT + CONTINUITY DETECTOR / ONE LOOP")
	var starts: int=sound.audio_snapshot().grind_starts
	for tick: int in range(360):
		var touching: bool=tick>=60 and tick<240
		var distance: float=float(p.radius)+float(e.radius)+(.5 if touching else 24.)
		p.pos=Vector2(-distance*.5,0);e.pos=Vector2(distance*.5,0)
		p.vel=Vector2(0,80) if touching else Vector2.ZERO;e.vel=Vector2(0,-40) if touching else Vector2.ZERO
		b._visual_time+=Battle.FIXED_DT;b._update_effects(Battle.FIXED_DT)
		b.impact_feedback.observe_grinding(b.fighters,Battle.FIXED_DT)
		await frame(b,"grind",tick,"grind_sustained" if tick==150 else ("grind_released" if tick==300 else ""))
	var state: Dictionary=sound.audio_snapshot()
	if state.grind_starts-starts!=1 or state.grind_active:failures.append("Grind did not start once and release after separation")
	scenes.append({"id":"grind","frames":360,"held_geometry_fixture":true,"normal_speed":0.,"tangential_speed":120.,"surface_gap":.5,"continuity_seconds":3.,"audio":state,"balance_claim":false})
	release_battle(b)
func concurrent_mix() -> void:
	var b: Node2D=new_battle();b.set_paused(true)
	captions("003A.1 / CONCURRENT MIX HEADROOM","EIGHT-SFX STRESS FIXTURE / ACTUAL PHASE-INDEPENDENT MIX BUDGET / MUSIC PCM UNCHANGED")
	for tick: int in range(180):
		if tick==60:
			for key: String in ["metal_normal","metal_clang","metal_edge","metal_scrape","metal_massive","metal_extreme","metal_crack","metal_takedown"]:cue(key)
			if sound.audio_snapshot().worst_case_sfx_peak>Sound.MIX_PEAK_BUDGET+.000001:failures.append("Concurrent SFX headroom exceeded")
		await frame(b,"concurrent",tick,"concurrent_headroom" if tick==61 else "")
	scenes.append({"id":"concurrent","frames":180,"audio_stress_fixture":true,"sounds":sound.audio_snapshot(),"balance_claim":false});release_battle(b)
