extends SceneTree
## Labelled initial powers/assemblies and real warmup controls. Every shown
## position, reserve, contact, effect, target reaction and outcome is simulated.
## No collection, preferences or saved Run state is opened by this harness.
const Physics = preload("res://scripts/battle.gd")
const Parts = preload("res://scripts/parts.gd")
const Menus = preload("res://scripts/menus.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Bot = preload("res://tests/rpm_bot.gd")
const Run = preload("res://scripts/run_context.gd")
const Pickups = preload("res://scripts/run_pickups.gd")

class CaptureBattle extends "res://tests/measured_presentation_battle.gd":
	var blast_count: int = 0
	var blast_tags: Dictionary = {}
	var drift_sparks_emitted: int = 0
	var recorded_gains: Dictionary = {}
	var gain_events: Array[Dictionary] = []
	func _spawn_blast_wave(at: Vector2, strength: float) -> void:
		var before: int = _blast_waves.size()
		super._spawn_blast_wave(at, strength)
		if strength >= 0.18 and at.is_finite() and _blast_waves.size() >= before:
			blast_count += 1
			var tag: String = str(_blast_waves.back().tag)
			blast_tags[tag] = int(blast_tags.get(tag, 0)) + 1
	func _update_drift_tip(f: Dictionary, direction: Vector2, velocity: Vector2, braking: bool, grip: float, dt: float) -> void:
		var before: int = 0
		for particle: Dictionary in _particles:
			if particle.get("kind", "") == "drift": before += 1
		super._update_drift_tip(f, direction, velocity, braking, grip, dt)
		var after: int = 0
		for particle: Dictionary in _particles:
			if particle.get("kind", "") == "drift": after += 1
		drift_sparks_emitted += maxi(0, after-before)
	func gain_rpm(f: Dictionary, amount: float, source: String, small: bool = false) -> float:
		var actual: float = super.gain_rpm(f, amount, source, small)
		if int(f.entity_id) == player_entity_id and actual > 0.0:
			recorded_gains[source] = float(recorded_gains.get(source, 0.0)) + actual
			gain_events.append({"time":elapsed, "source":source, "amount":actual, "rpm":f.rpm})
		return actual

const SCENARIOS: Array[Dictionary] = [
	{"name":"DRIFT / BIT SPARKS", "build":{"blade":"balance","ratchet":"mid","bit":"flat"}, "powers":[], "ranks":{}, "mutations":{}, "policy":"tight_drift", "seconds":7, "warmup":360, "seed":421, "note":"Actual lateral slip keeps momentum and scrapes sparks from the bit"},
	{"name":"REDLINE / REAL OVERDRIVE METER", "build":{"blade":"balance","ratchet":"mid","bit":"flat"}, "powers":["redline"], "ranks":{"redline":2}, "mutations":{}, "policy":"overdrive", "seconds":7, "warmup":0, "seed":421, "note":"Burst activates Redline; actual motion/contact gains extend the RPM bar"},
	{"name":"AFTERIMAGE / LASTING PAID ROUTE", "build":{"blade":"outrigger","ratchet":"high","bit":"skate"}, "powers":["afterimage"], "ranks":{"afterimage":2}, "mutations":{}, "policy":"drift", "seconds":7, "warmup":0, "seed":421, "note":"Real movement pays for a route that stays usable for up to 4.6 seconds"},
	{"name":"DEAD CENTRE / HOLD, BRACE AND RECOVER", "build":{"blade":"guard","ratchet":"ballast","bit":"tripod"}, "powers":["dead_centre"], "ranks":{"dead_centre":2}, "mutations":{}, "policy":"anchor", "seconds":9, "warmup":480, "seed":421, "two_rivals":true, "note":"Paid bursts spend reserve before a real central hold; opponents remain live"},
	{"name":"CONTACT / PHYSICAL BLAST WAVES", "build":{"blade":"hammerfall","ratchet":"kickback","bit":"flat"}, "powers":[], "ranks":{}, "mutations":{}, "policy":"aggressive", "seconds":7, "warmup":0, "seed":421, "note":"Actual collision impulse produces contact flashes and travelling floor waves"},
	{"name":"RAMPED ATTACK / COMMITTED CONTACT", "build":{"blade":"lopsider","ratchet":"offset","bit":"claw"}, "powers":["redline","impact_wake","iron_comet"], "ranks":{"redline":2,"impact_wake":2,"iron_comet":2}, "mutations":{}, "policy":"aggressive", "seconds":7, "warmup":0, "seed":421, "note":"Controlled rank-II setup; only real bursts, steering and impacts drive effects"},
	{"name":"REROLL CHIP / REAL FLOOR COLLECTION", "build":{"blade":"hammerfall","ratchet":"kickback","bit":"claw"}, "powers":[], "ranks":{}, "mutations":{}, "policy":"pickup", "seconds":6, "warmup":1540, "seed":421, "note":"A genuine cleared threat drops a chip; driving through it gains a Run reroll"}
]

var manifest_path: String = ""
var frame_dir: String = ""
var diagnostic: bool = false
var selection: int = -1
var seed_override: int = -1
var warmup_override: int = -1
var seconds_override: float = -1.0

func _initialize() -> void: call_deferred("run")

func label(text: String, at: Vector2, size: int, tint: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.position = at
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", tint)
	root.add_child(result)
	return result

func screen_input(world: Vector2, intensity: float = 1.0) -> Vector2:
	return Vector2(world.x-world.y,(world.x+world.y)*0.5).normalized()*intensity

func controls(b: Node2D, policy: String, tick: int, warmup: bool = false) -> Dictionary:
	var player: Dictionary = b.player_entity()
	var pos: Vector2 = player.pos
	var velocity: Vector2 = player.vel
	if policy == "anchor":
		if warmup:
			var orbit: Vector2 = pos.normalized().orthogonal() if pos.length() > 1.0 else Vector2.UP
			var steer: Vector2 = orbit*110.0 + pos.normalized()*(75.0-pos.length())*2.0 - velocity*0.55
			return {"direction":screen_input(steer,0.8),"burst":tick%150==0 and float(player.cooldown)<=0.0,"brake":pos.length()>146.0}
		if pos.length() > 28.0 or velocity.length() > 25.0:
			var toward: Vector2 = -pos*2.0-velocity*0.65
			return {"direction":screen_input(toward,clampf(pos.length()/55.0,0.18,0.75)),"burst":false,"brake":pos.length()<46.0 or velocity.length()>80.0}
		return {"direction":Vector2.ZERO,"burst":false,"brake":true}
	if policy == "drift" or policy == "tight_drift" or policy == "overdrive":
		var radial: Vector2 = pos.normalized() if pos.length()>1.0 else Vector2.RIGHT
		var tangent: Vector2 = radial.orthogonal()
		var desired: Vector2 = tangent*165.0+radial*(72.0-pos.length())*2.3
		if policy=="tight_drift": desired=tangent*160.0+radial*(50.0-pos.length())*5.0
		var steer: Vector2 = (desired-velocity).normalized()*(0.95 if policy=="tight_drift" else 0.78)
		return {"direction":screen_input(steer,steer.length()),"burst":policy=="overdrive" and tick%210==0 and float(player.cooldown)<=0.0,"brake":pos.length()>(118.0 if policy=="tight_drift" else 149.0)}
	return Bot.input(b,policy,tick)

func point(v: Vector2) -> Array[float]: return [v.x,v.y]

func pickup_controls(b: Node2D, pickups: Node2D, tick: int) -> Dictionary:
	var c: Dictionary=Bot.input(b,"aggressive",tick)
	if not pickups.items.is_empty():
		var p: Dictionary=b.player_entity()
		var offset: Vector2=Vector2(pickups.items[0].pos)-Vector2(p.pos)
		var desired: Vector2=offset.limit_length(60.0)*2.0-Vector2(p.vel)*0.60
		var world: Vector2=desired.limit_length(100.0)/100.0
		c={"direction":Vector2(world.x-world.y,(world.x+world.y)*0.5),"burst":false,"brake":offset.length()<22.0 and Vector2(p.vel).length()>65.0}
	return c

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="): manifest_path=argument.trim_prefix("--manifest=")
		if argument.begins_with("--frames="): frame_dir=argument.trim_prefix("--frames=")
		if argument.begins_with("--scenario="): selection=int(argument.trim_prefix("--scenario="))
		if argument.begins_with("--seed="): seed_override=int(argument.trim_prefix("--seed="))
		if argument.begins_with("--warmup="): warmup_override=int(argument.trim_prefix("--warmup="))
		if argument.begins_with("--seconds="): seconds_override=float(argument.trim_prefix("--seconds="))
		if argument=="--diagnostic": diagnostic=true
	if manifest_path.is_empty():
		push_error("Supply an external --manifest output; no save paths are opened")
		quit(2)
		return
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(640,360)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty(): DirAccess.make_dir_recursive_absolute(frame_dir)
	var runs: Array[Dictionary] = []
	for index: int in range(SCENARIOS.size()):
		if selection>=0 and index!=selection: continue
		var scenario: Dictionary = SCENARIOS[index].duplicate(true)
		if seed_override>=0: scenario.seed=seed_override
		if warmup_override>=0: scenario.warmup=warmup_override
		if seconds_override>0.0: scenario.seconds=seconds_override
		assert(Parts.validate_build(scenario.build)==scenario.build)
		var b: CaptureBattle = CaptureBattle.new()
		root.add_child(b)
		b.set_physics_process(false)
		b.screen_shake_enabled=true
		var menu: Control = Menus.new()
		root.add_child(menu)
		var run_context = Run.new()
		var pickup_layer: Node2D = Pickups.new()
		var pickup_mode: bool = scenario.policy=="pickup"
		if pickup_mode:
			run_context.start(scenario.build,int(scenario.seed))
			assert(run_context.choose_power(run_context.pending_draft_id,run_context.pending_offer[0]))
		b.hud_updated.connect(func(stats: Dictionary) -> void:
			var enriched: Dictionary = stats.duplicate(true)
			var p: Dictionary = b.player_entity()
			enriched.owned_power_ids=p.powers.duplicate()
			enriched.power_ranks=p.power_ranks.duplicate(true)
			enriched.power_mutations=p.power_mutations.duplicate(true)
			enriched.starter_id=p.starter_id
			if pickup_mode:
				enriched.is_run=true
				enriched.rerolls=run_context.reroll_charges
			menu.show_hud(enriched))
		var descriptor: Dictionary = Encounters.for_run_event(1,int(scenario.seed))
		descriptor.ability_rebalance=true
		descriptor.player_power_ids=scenario.powers
		descriptor.player_power_ranks=scenario.ranks
		descriptor.player_power_mutations=scenario.mutations
		descriptor.starter_id="bastion" if scenario.policy=="anchor" else "custom"
		descriptor.opponent_build={"blade":"guard","ratchet":"mid","bit":"ball"}
		b.begin_run(scenario.build,run_context.current_encounter() if pickup_mode else descriptor,int(scenario.seed))
		if pickup_mode:
			b.add_child(pickup_layer)
			pickup_layer.set_process(false)
			pickup_layer.setup(b,run_context)
			b.threat_cleared.connect(func(summary: Dictionary) -> void: pickup_layer.notify_clear(summary))
		if bool(scenario.get("two_rivals",false)):
			# Supported initial setup before countdown: a second genuine AI rival.
			assert(b.add_full_top({"blade":"balance","ratchet":"mid","bit":"ball"},30,"hostile","review_rival_2",Vector2(85,35),Vector2(-42,-28)))
		var launch_ticks: int = 0
		while b.battle_status!="battle" and launch_ticks<300:
			b.test_step(Physics.FIXED_DT)
			launch_ticks+=1
		assert(b.battle_status=="battle")
		for tick: int in range(int(scenario.warmup)):
			var c: Dictionary = pickup_controls(b,pickup_layer,tick) if pickup_mode else controls(b,str(scenario.policy),tick,true)
			b.test_step(Physics.FIXED_DT,c.direction,c.burst,c.brake)
			if pickup_mode: pickup_layer.update_simulation()
		var before_gains: Dictionary = b.recorded_gains.duplicate(true)
		var contact_start: int = b.hits
		var blast_start: int = b.blast_count
		var spark_start: int = b.drift_sparks_emitted
		var title: Label=label("002C.5.2 FEEDBACK / "+str(scenario.name),Vector2(12,91),11,Color("e4ebd6"))
		var assembly: Label=label(Parts.title(scenario.build),Vector2(12,106),9,Color("d4b886"))
		var note: Label=label(str(scenario.note),Vector2(12,277),8,Color("e4ebd6"))
		var cause: Label=label("CONTROLLED INITIAL SETUP / REAL PHYSICS / INPUTS ONLY / NO SAVE WRITES",Vector2(12,346),7,Color("bbc8cf"))
		var rows: Array[Dictionary] = []
		var max_rpm: float=0.0
		var min_rpm: float=INF
		var max_trace_age: float=0.0
		var max_traces: int=0
		var max_charge: float=0.0
		var max_maturity: float=0.0
		var max_pull: float=0.0
		var max_recovery_rate: float=0.0
		var max_drift: float=0.0
		var actual_battle_frames: int=0
		var max_spark_count: int=0
		var start_rpm: float=float(b.player_entity().rpm)
		var start_rerolls: int=run_context.reroll_charges if pickup_mode else 0
		var feature_frames: Dictionary={}
		for tick: int in range(roundi(float(scenario.seconds)*60.0)):
			var c: Dictionary=pickup_controls(b,pickup_layer,tick+int(scenario.warmup)) if pickup_mode else controls(b,str(scenario.policy),tick)
			b.test_step(Physics.FIXED_DT,c.direction,c.burst,c.brake)
			if pickup_mode: pickup_layer.update_simulation()
			var p: Dictionary=b.player_entity()
			max_rpm=maxf(max_rpm,float(p.rpm)); min_rpm=minf(min_rpm,float(p.rpm))
			max_drift=maxf(max_drift,float(p.get("drift_intensity",0.0)))
			max_charge=maxf(max_charge,float(p.get("anchor_charge",0.0)))
			max_maturity=maxf(max_maturity,float(p.get("anchor_maturity",0.0)))
			max_pull=maxf(max_pull,float(p.get("anchor_pull_strength",0.0)))
			max_recovery_rate=maxf(max_recovery_rate,float(p.get("anchor_recovery_rate",0.0)))
			max_traces=maxi(max_traces,b.powers.traces.size())
			for trace: Dictionary in b.powers.traces: max_trace_age=maxf(max_trace_age,b.powers.time-float(trace.created_at))
			var live_sparks: int=0
			for particle: Dictionary in b._particles:
				if particle.get("kind","")=="drift": live_sparks+=1
			max_spark_count=maxi(max_spark_count,live_sparks)
			if b.battle_status=="battle": actual_battle_frames+=1
			if tick%15==0:
				var rivals: Array[Dictionary]=[]
				for f: Dictionary in b.fighters:
					if f.team_id=="hostile": rivals.append({"id":f.entity_id,"position":point(f.pos),"velocity":point(f.vel),"rpm":f.rpm,"outcome":f.outcome})
				rows.append({"tick":tick,"simulation_time":b.elapsed,"rpm":p.rpm,"speed":Vector2(p.vel).length(),"position":point(p.pos),"hits":b.hits,"status":b.battle_status,"drift":p.get("drift_intensity",0.0),"anchor_charge":p.anchor_charge,"anchor_maturity":p.get("anchor_maturity",0.0),"anchor_recovery_rate":p.get("anchor_recovery_rate",0.0),"anchor_recovery_remaining":p.get("anchor_recovery_remaining",0.0),"pull_strength":p.get("anchor_pull_strength",0.0),"traces":b.powers.traces.size(),"rivals":rivals})
			if not diagnostic:
				b.queue_redraw()
				await process_frame
				var feature: String=""
				if index==0 and live_sparks>=3 and tick>=59: feature="drift"
				if index==1 and float(p.rpm)>1.02: feature="overdrive"
				if index==2 and max_trace_age>3.5: feature="long-route"
				if index==3 and float(p.get("anchor_maturity",0.0))>0.95: feature="anchor"
				if index in [4,5]:
					for wave: Dictionary in b._blast_waves:
						if wave.tag=="impact_extreme" and float(wave.age)>=0.16 and float(wave.age)<0.30: feature="blast"
				if pickup_mode and not pickup_layer.items.is_empty(): feature="chip"
				if pickup_mode and run_context.reroll_charges>start_rerolls and menu._hud.rerolls.text=="REROLLS  %d"%run_context.reroll_charges: feature="collected"
				var new_feature: bool=not feature.is_empty() and not feature_frames.has(feature)
				if not frame_dir.is_empty() and (tick in [59,179,299,roundi(float(scenario.seconds)*60.0)-1] or new_feature):
					await RenderingServer.frame_post_draw
					var capture: Image=root.get_texture().get_image()
					capture.resize(640,360,Image.INTERPOLATE_NEAREST)
					var filename: String="%02d-%s.png"%[index,feature] if new_feature else "%02d-%03d.png"%[index,tick]
					capture.save_png(frame_dir.path_join(filename))
					if new_feature: feature_frames[feature]={"tick":tick,"rpm":p.rpm,"path":frame_dir.path_join(filename)}
		var after_gains: Dictionary=b.recorded_gains.duplicate(true)
		var recorded_gains: Dictionary={}
		for source: String in after_gains: recorded_gains[source]=float(after_gains[source])-float(before_gains.get(source,0.0))
		var draws: Array=b.draw_samples.duplicate()
		draws.sort()
		runs.append({"scenario":scenario,"launch_ticks":launch_ticks,"warmup_ticks":scenario.warmup,"capture_frames":roundi(float(scenario.seconds)*60.0),"actual_battle_frames":actual_battle_frames,"duration_seconds":scenario.seconds,"start_rpm":start_rpm,"end_rpm":b.player_entity().rpm,"max_rpm":max_rpm,"min_rpm":min_rpm,"actual_contacts":b.hits-contact_start,"blast_emissions":b.blast_count-blast_start,"blast_tags":b.blast_tags,"drift_sparks_emitted":b.drift_sparks_emitted-spark_start,"max_live_drift_sparks":max_spark_count,"max_drift_intensity":max_drift,"max_trace_age":max_trace_age,"max_live_traces":max_traces,"max_anchor_charge":max_charge,"max_anchor_maturity":max_maturity,"max_pull_strength":max_pull,"max_anchor_recovery_rate":max_recovery_rate,"actual_gains":recorded_gains,"power_diagnostics":b.powers.diagnostics(b.player_entity()),"gain_events":b.gain_events,"power_events":b.powers.events,"rows":rows,"draw_samples":draws.size(),"draw_submit_p95_ms":draws[int((draws.size()-1)*0.95)] if not draws.is_empty() else 0.0,"result":b.last_result.duplicate(true)})
		runs[-1].feature_frames=feature_frames
		if pickup_mode: runs[-1].pickups={"created":pickup_layer._sequence,"collected":run_context.rerolls_collected,"start_charges":start_rerolls,"end_charges":run_context.reroll_charges,"remaining":pickup_layer.items.duplicate(true)}
		print("FEEDBACK_CAPTURE ",scenario.name," actual_contacts=",runs[-1].actual_contacts," rpm_max=",max_rpm," sparks=",runs[-1].drift_sparks_emitted," blasts=",runs[-1].blast_emissions," anchor_maturity=",max_maturity," actual_gains=",recorded_gains)
		for item: Label in [title,assembly,note,cause]: item.free()
		if not pickup_mode: pickup_layer.free()
		menu.free(); b.free()
	var file: FileAccess=FileAccess.open(manifest_path,FileAccess.WRITE)
	assert(file!=null)
	file.store_string(JSON.stringify({"authenticity":"Controlled legal assemblies/powers and optional second rival before ordinary countdown. Warmup is real omitted steering/burst/brake time. All shown physics, RPM, contacts, effects, target reactions and outcomes come from normal test_step. No state injection after launch. Menus HUD receives actual Battle statistics. No saves/preferences opened.","native_view":[640,360],"nearest_output":[1280,720],"fps":60,"diagnostic":diagnostic,"runs":runs},"\t"))
	file.close()
	print("FEEDBACK_CAPTURE_PASS runs=",runs.size())
	quit(0)
