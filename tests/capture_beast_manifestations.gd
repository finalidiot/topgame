extends SceneTree
## Review capture: legal initial equipment/powers, ordinary countdown and inputs.
## No state, contacts, outcomes or presentation events are injected after launch.
const Battle = preload("res://scripts/battle.gd")
const Parts = preload("res://scripts/parts.gd")
const Menus = preload("res://scripts/menus.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Bot = preload("res://tests/rpm_bot.gd")

const SCENARIOS: Array[Dictionary] = [
	{"identity":"black_arrow","name":"BLACK ARROW / WALL CHARGE TO CONTACT","build":{"blade":"smash","ratchet":"offset","bit":"claw"},"powers":["iron_comet"],"ranks":{"iron_comet":2},"mutations":{},"policy":"comet","seed":421,"seconds":9,"warmup":0,"note":"Real wall rebound charges Iron Comet; a real contact releases it"},
	{"identity":"iron_bull","name":"IRON BULL / HEAVY CONTACT","build":{"blade":"hammerfall","ratchet":"kickback","bit":"flat"},"powers":["impact_wake"],"ranks":{"impact_wake":2},"mutations":{},"policy":"aggressive","seed":421,"seconds":9,"warmup":0,"note":"A heavy physical hit triggers Impact Wake and its brief beast strike"},
	{"identity":"stone_tortoise","name":"STONE TORTOISE / MATURE CENTRE HOLD","build":{"blade":"guard","ratchet":"ballast","bit":"tripod"},"powers":["dead_centre"],"ranks":{"dead_centre":2},"mutations":{},"policy":"anchor","seed":421,"seconds":10,"warmup":0,"note":"Six real seconds of a settled central hold earn a brief guarding avatar"},
	{"identity":"coil_dragon","name":"COIL DRAGON / PAID BREAKNECK COMMIT","build":{"blade":"balance","ratchet":"mid","bit":"flat"},"powers":["redline"],"ranks":{"redline":3},"mutations":{"redline":"breakneck"},"policy":"breakneck_late","seed":421,"seconds":10,"warmup":0,"note":"Build real overclock, Burst again to commit; misses recover without a fake hit"}
]

static func screen_input(world: Vector2, intensity: float = 1.0) -> Vector2:
	return Vector2(world.x-world.y,(world.x+world.y)*0.5).normalized()*intensity

static func controls(b: Node2D, policy: String, tick: int) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var pos: Vector2 = p.pos
	var velocity: Vector2 = p.vel
	if policy == "anchor":
		if pos.length() > 28.0 or velocity.length() > 25.0:
			return {"direction":screen_input(-pos*2.0-velocity*0.65,clampf(pos.length()/55.0,0.18,0.75)),"burst":false,"brake":pos.length()<46.0 or velocity.length()>80.0}
		return {"direction":Vector2.ZERO,"burst":false,"brake":true}
	if policy == "comet":
		if float(p.get("iron_comet_time",0.0)) > 0.0:
			return Bot.input(b,"aggressive",tick)
		# The solid +Y wall is outside the two diagonal gate mouths.
		var outward: Vector2 = Vector2(0.0,145.0)-pos
		return {"direction":screen_input(outward,0.95),"burst":float(p.cooldown)<=0.0 and pos.y<115.0,"brake":false}
	if policy.begins_with("breakneck"):
		var active: bool = b.powers.redline_active(p)
		var ready_commit: bool = active and float(p.cooldown)<=0.0 and (float(p.get("redline_heat",0.0))>=0.32 or float(p.rpm)>=1.025)
		if policy=="breakneck_late": ready_commit=ready_commit and float(p.get("redline_time",0.0))<=0.35
		if ready_commit or float(p.get("redline_commit_time",0.0))>0.0:
			var c: Dictionary = Bot.input(b,"aggressive",tick)
			c.burst=ready_commit
			c.brake=false
			if policy == "breakneck_miss": c.direction=screen_input(-pos if pos.length()>25.0 else Vector2.DOWN)
			return c
		var radial: Vector2 = pos.normalized() if pos.length()>1.0 else Vector2.RIGHT
		var desired: Vector2 = radial.orthogonal()*165.0+radial*(72.0-pos.length())*2.3
		return {"direction":screen_input(desired-velocity,0.78),"burst":not active and float(p.cooldown)<=0.0,"brake":pos.length()>149.0}
	return Bot.input(b,policy,tick)

static func descriptor(scenario: Dictionary) -> Dictionary:
	var result: Dictionary = Encounters.for_run_event(1,int(scenario.seed))
	result.ability_rebalance=true
	result.player_power_ids=scenario.powers.duplicate()
	result.player_power_ranks=scenario.ranks.duplicate(true)
	result.player_power_mutations=scenario.mutations.duplicate(true)
	result.starter_id="bastion" if scenario.policy=="anchor" else "custom"
	result.opponent_build={"blade":"guard","ratchet":"mid","bit":"ball"}
	return result

static func point(value: Vector2) -> Array[float]: return [value.x,value.y]

static func portable(value: Variant) -> Variant:
	if value is Vector2: return point(value)
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value: result[str(key)]=portable(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(portable(item))
		return result
	return value

func caption(text: String, at: Vector2, size: int) -> Label:
	var result := Label.new()
	result.text=text
	result.position=at
	result.add_theme_font_size_override("font_size",size)
	result.add_theme_color_override("font_color",Color("e4ebd6"))
	root.add_child(result)
	return result

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var output: String=""
	var frames: String=""
	var diagnostic: bool=false
	var selection: int=-1
	var seed_override: int=-1
	var warmup_override: int=-1
	var policy_override: String=""
	var seconds_override: float=-1.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--frames="): frames=arg.trim_prefix("--frames=")
		if arg.begins_with("--scenario="): selection=int(arg.trim_prefix("--scenario="))
		if arg.begins_with("--seed="): seed_override=int(arg.trim_prefix("--seed="))
		if arg.begins_with("--warmup="): warmup_override=int(arg.trim_prefix("--warmup="))
		if arg.begins_with("--policy="): policy_override=arg.trim_prefix("--policy=")
		if arg.begins_with("--seconds="): seconds_override=float(arg.trim_prefix("--seconds="))
		if arg=="--diagnostic": diagnostic=true
	if output.is_empty():
		push_error("Supply external --manifest output; the capture never opens profile files")
		quit(2); return
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(640,360)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frames.is_empty(): DirAccess.make_dir_recursive_absolute(frames)
	var runs: Array[Dictionary]=[]
	for index: int in range(SCENARIOS.size()):
		if selection>=0 and selection!=index: continue
		var s: Dictionary=SCENARIOS[index].duplicate(true)
		if seed_override>=0: s.seed=seed_override
		if warmup_override>=0: s.warmup=warmup_override
		if seconds_override>0.0: s.seconds=seconds_override
		if not policy_override.is_empty(): s.policy=policy_override
		assert(Parts.validate_build(s.build)==s.build)
		var b: Node2D=Battle.new()
		root.add_child(b)
		b.set_physics_process(false); b.set_process(false)
		var menu: Control=Menus.new()
		root.add_child(menu)
		b.hud_updated.connect(func(stats: Dictionary) -> void:
			var enriched: Dictionary=stats.duplicate(true)
			var p: Dictionary=b.player_entity()
			enriched.owned_power_ids=p.powers.duplicate()
			enriched.power_ranks=p.power_ranks.duplicate(true)
			enriched.power_mutations=p.power_mutations.duplicate(true)
			enriched.starter_id=p.starter_id
			menu.show_hud(enriched))
		b.begin_run(s.build,descriptor(s),int(s.seed))
		var launch: int=0
		while b.battle_status!="battle" and launch<300:
			b.test_step(Battle.FIXED_DT); launch+=1
		assert(b.battle_status=="battle")
		for tick: int in range(int(s.warmup)):
			var c: Dictionary=controls(b,str(s.policy),tick)
			b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		var labels: Array[Label]=[
			caption("002C.5.2 BEASTS / "+str(s.name),Vector2(12,91),10),
			caption(Parts.title(s.build),Vector2(12,106),8),
			caption(str(s.note),Vector2(12,277),8),
			caption("LEGAL INITIAL SETUP / REAL PHYSICS / INPUTS ONLY / NO SAVE WRITES",Vector2(12,346),7)]
		var rows: Array[Dictionary]=[]
		var features: Dictionary={}
		var phases: Dictionary={}
		var live_frames: int=0
		var beast_frames: int=0
		var contact_start: int=b.hits
		var min_rpm: float=INF
		var max_rpm: float=0.0
		var max_hold: float=0.0
		var starting: Dictionary=b.beast_presentation_snapshot()
		for tick: int in range(roundi(float(s.seconds)*60.0)):
			var c: Dictionary=controls(b,str(s.policy),tick+int(s.warmup))
			b.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
			var p: Dictionary=b.player_entity()
			var state: Dictionary=b.beast_presentation_snapshot()
			if b.battle_status=="battle": live_frames+=1
			min_rpm=minf(min_rpm,float(p.rpm)); max_rpm=maxf(max_rpm,float(p.rpm))
			max_hold=maxf(max_hold,float(p.get("anchor_hold_seconds",0.0)))
			if int(state.count)>0: beast_frames+=1
			var full: Dictionary={}
			for instance: Dictionary in state.active:
				var key: String=str(instance.beast)+"/"+str(instance.phase)
				phases[key]=int(phases.get(key,0))+1
				# Retain a developed authored key, after the start of its phase.
				if instance.beast==s.identity and float(instance.phase_age)>=minf(0.12,float(instance.phase_duration)*0.4) and instance.phase in ["travel","strike","guard"]: full=instance
			if tick%15==0:
				rows.append({"tick":tick,"time":b.elapsed,"hits":b.hits,"rpm":p.rpm,"position":point(p.pos),"velocity":point(p.vel),"hold":p.get("anchor_hold_seconds",0.0),"status":b.battle_status,"beasts":portable(state.active)})
			if not diagnostic:
				b.queue_redraw(); await process_frame
				var phase: String=str(full.get("phase",""))
				var feature: bool=not full.is_empty() and not features.has(phase)
				if not frames.is_empty() and (feature or tick in [59,179,299,roundi(float(s.seconds)*60.0)-1]):
					await RenderingServer.frame_post_draw
					var capture: Image=root.get_texture().get_image()
					capture.resize(640,360,Image.INTERPOLATE_NEAREST)
					var filename: String="%02d-%s-%s.png"%[index,s.identity,phase] if feature else "%02d-%03d.png"%[index,tick]
					assert(capture.save_png(frames.path_join(filename))==OK)
					if feature: features[phase]={"tick":tick,"path":frames.path_join(filename),"instance":portable(full),"actual_contacts":b.hits-contact_start}
		var state: Dictionary=b.beast_presentation_snapshot()
		var summary: Dictionary={"scenario":s,"launch_ticks":launch,"capture_frames":roundi(float(s.seconds)*60.0),"actual_battle_frames":live_frames,"beast_visible_frames":beast_frames,"actual_contacts":b.hits-contact_start,"min_rpm":min_rpm,"max_rpm":max_rpm,"max_hold_seconds":max_hold,"presentation_start":portable(starting),"presentation_end":portable(state),"phase_frames":phases,"feature_frames":features,"power_events":b.powers.events.duplicate(true),"power_diagnostics":b.powers.diagnostics(b.player_entity()),"rpm_ledger":b.continuous.economy.snapshot(),"director_history":b.continuous.director.history.duplicate(true),"rows":rows,"result":b.last_result.duplicate(true)}
		runs.append(summary)
		print("BEAST_CAPTURE ",s.identity," contacts=",summary.actual_contacts," beast_frames=",beast_frames," spawned=",state.spawned," phases=",phases," hold=",max_hold)
		for item: Label in labels: item.free()
		menu.free(); b.free()
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	assert(file!=null)
	file.store_string(JSON.stringify({"authenticity":"Legal initial assemblies/powers before ordinary countdown; all shown movement, charge, paid commitment, mature hold, contacts, RPM and avatars come from normal fixed-step steering/Burst/brake inputs. No state/contact/effect injection after launch; production Menus HUD; no collection/preferences opened.","native_view":[640,360],"nearest_output":[1280,720],"fps":60,"diagnostic":diagnostic,"runs":portable(runs)},"\t"))
	file.close()
	print("BEAST_CAPTURE_PASS runs=",runs.size())
	quit(0)
