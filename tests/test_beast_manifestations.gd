extends SceneTree
## Combat cases use legal initial builds/powers, ordinary countdown and controls.
## Explicit presentation fixtures below test only controller bounds/lifecycle;
## those fixtures are never used in the review capture or gameplay evidence.
const Battle = preload("res://scripts/battle.gd")
const Beasts = preload("res://scripts/beast_manifestations.gd")
const Review = preload("res://tests/capture_beast_manifestations.gd")
const Parts = preload("res://scripts/parts.gd")
const Collection = preload("res://scripts/collection_save.gd")

var checks: int=0
var failures: Array[String]=[]
var measurements: Dictionary={}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)

func prepare(s: Dictionary, enabled: bool=true) -> Node2D:
	var b: Node2D=Battle.new()
	root.add_child(b)
	b.set_physics_process(false); b.set_process(false)
	b.beast_manifestations_enabled=enabled
	b.begin_run(s.build,Review.descriptor(s),int(s.seed))
	var launch: int=0
	while b.battle_status!="battle" and launch<300:
		b.test_step(Battle.FIXED_DT); launch+=1
	check(b.battle_status=="battle","Legal setup passes the ordinary countdown and launch")
	return b

func rng_state(b: Node2D) -> Dictionary:
	var ai: Dictionary={}
	for key: Variant in b._ai_rngs: ai[key]=str(b._ai_rngs[key].state)
	return {"simulation":str(b._simulation_rng.state),"cosmetic":str(b._cosmetic_rng.state),"ai":ai,"director":str(b.continuous.director.rng.state)}

func kinds(events: Array, owner: int=1) -> Dictionary:
	var result: Dictionary={}
	for item: Dictionary in events:
		if int(item.get("owner",owner))!=owner: continue
		result[str(item.kind)]=int(result.get(str(item.kind),0))+1
	return result

func actual_cases() -> void:
	var ownership=Collection.new(OS.get_temp_dir().path_join("beasts_unopened_collection.json"))
	var ownership_before: Dictionary=ownership.snapshot()
	for index: int in range(Review.SCENARIOS.size()):
		var s: Dictionary=Review.SCENARIOS[index].duplicate(true)
		check(Parts.validate_build(s.build)==s.build,"Review equipment is catalogue-valid")
		var shown: Node2D=prepare(s,true)
		var hidden: Node2D=prepare(s,false)
		var maximum_hold: float=0.0
		var live_peak: int=0
		var observed: Dictionary={}
		var actual_impact: bool=false
		var paused_once: bool=false
		var first_contact_id: int=-1
		var count: int=roundi(float(s.seconds)*60.0)+int(s.warmup)
		for tick: int in range(count):
			var c: Dictionary=Review.controls(shown,str(s.policy),tick)
			shown.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
			hidden.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
			check(shown.snapshot()==hidden.snapshot(),"Beasts cannot alter exact positions, velocities, RPM, wobble, hits or outcomes")
			check(shown.continuous.snapshot()==hidden.continuous.snapshot() and shown.continuous.economy.snapshot()==hidden.continuous.economy.snapshot(),"Beasts preserve director census and source-accounted RPM ledger")
			check(shown.continuous.director.history==hidden.continuous.director.history and rng_state(shown)==rng_state(hidden),"Beasts consume no simulation, AI, director or cosmetic random stream")
			check(shown.powers.events==hidden.powers.events,"Cosmetic hooks preserve all actual power event provenance")
			var snapshot: Dictionary=shown.beast_presentation_snapshot()
			check(int(snapshot.count)<=Beasts.MAX_LIVE and int(snapshot.peak_live)<=Beasts.MAX_LIVE,"Actual manifestations remain under three live avatars")
			check(hidden.beast_presentation_snapshot().count==0,"Disabled presentation remains empty during identical live gameplay")
			live_peak=maxi(live_peak,int(snapshot.count))
			maximum_hold=maxf(maximum_hold,float(shown.player_entity().get("anchor_hold_seconds",0.0)))
			for item: Dictionary in snapshot.active:
				check(int(item.owner_entity_id)>0 and item.beast==Beasts.beast_for_blade(str(shown.entity(int(item.owner_entity_id)).build.blade)),"Actual avatar identity follows its explicit owner's equipped blade")
				check(float(item.age)<Beasts.MAX_INSTANCE_SECONDS and Vector2(item.world_pos).is_finite(),"Live presentation remains finite and expires within its lifetime budget")
				if int(item.owner_entity_id)!=1: continue
				if item.phase=="guard": check(float(shown.player_entity().anchor_hold_seconds)>=6.0-0.000001 and bool(shown.player_entity().anchor_central_hold),"Guard appears only during a genuinely mature central hold")
				observed[str(item.phase)]=true
				if bool(item.impact): actual_impact=true
				if item.phase=="strike" and first_contact_id<0: first_contact_id=shown.hits
			if not paused_once and int(snapshot.count)>0:
				shown.set_paused(true); hidden.set_paused(true)
				var freeze: Dictionary=shown.beast_presentation_snapshot()
				var combat: Dictionary=shown.snapshot()
				var ledger: Dictionary=shown.continuous.economy.snapshot()
				for pause_tick: int in range(20):
					shown.test_step(Battle.FIXED_DT,Vector2.ONE,true,true)
					hidden.test_step(Battle.FIXED_DT,Vector2.ONE,true,true)
				check(shown.beast_presentation_snapshot()==freeze and shown.snapshot()==combat and shown.continuous.economy.snapshot()==ledger,"Pause freezes avatar timers together with real combat and reserve")
				shown.set_paused(false); hidden.set_paused(false); paused_once=true
		var power_counts: Dictionary=kinds(shown.powers.events)
		var final: Dictionary=shown.beast_presentation_snapshot()
		check(int(final.spawned)>0 and paused_once,"Each genuine review case produces an inspectable live avatar")
		match str(s.identity):
			"black_arrow":
				check(int(power_counts.get("comet_charge",0))>0 and int(power_counts.get("comet_release",0))>0,"Ordinary wall movement charges Iron Comet and a real contact releases it")
				check(observed.has("prepare") and observed.has("travel") and observed.has("strike") and actual_impact and first_contact_id>0,"Comet preparation, owner-following travel and contact strike are real")
			"iron_bull":
				check(int(power_counts.get("impact_wake",0))>0 and observed.has("strike") and shown.hits>0,"Actual heavy contact triggers Impact Wake and its beast strike")
			"stone_tortoise":
				check(maximum_hold>=6.0-0.000001 and observed.has("guard"),"Settled Dead Centre hold matures for six real seconds before guarding")
				check(not actual_impact,"Mature hold cannot invent a contact or strike")
			"coil_dragon":
				check(int(power_counts.get("breakneck_commit",0))>0 and observed.has("prepare"),"Run Breakneck earns heat/excess and pays for a genuine second-Burst commitment")
				check(float(shown.powers.diagnostics(shown.player_entity()).rpm_spent)>0.0,"The captured commitment retains real RPM expenditure")
				if int(power_counts.get("breakneck_miss",0))>0:
					check(observed.has("recovery") and not observed.has("strike") and not actual_impact,"An actual paid Breakneck miss shows recovery and never invents an impact")
		measurements[str(s.identity)]={"power_events":power_counts,"phases":observed,"actual_contacts":shown.hits,"peak_live":live_peak,"hold_seconds":maximum_hold,"snapshot":Review.portable(final),"rpm_ledger":shown.continuous.economy.snapshot()}
		shown.begin_run(s.build,Review.descriptor(s),int(s.seed))
		check(shown.beast_presentation_snapshot().count==0 and shown.beast_presentation_snapshot().spawned==0,"A new battle clears active avatars, cooldowns and presentation diagnostics")
		shown.free(); hidden.free()
	check(ownership.snapshot()==ownership_before and ownership.owned_count()==0,"Avatar cases never grant catalogue parts or write collection ownership")

func director_parity() -> void:
	var s: Dictionary=Review.SCENARIOS[1].duplicate(true)
	s.seed=7331
	var shown: Node2D=prepare(s,true)
	var hidden: Node2D=prepare(s,false)
	for tick: int in range(2400):
		var c: Dictionary=Review.controls(shown,"defensive",tick)
		shown.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		hidden.test_step(Battle.FIXED_DT,c.direction,c.burst,c.brake)
		check(shown.snapshot()==hidden.snapshot() and shown.continuous.economy.snapshot()==hidden.continuous.economy.snapshot(),"Long seeded Run retains exact combat and reserve with or without beasts")
		check(shown.continuous.director.history==hidden.continuous.director.history and rng_state(shown)==rng_state(hidden),"Long seeded Run preserves real director decisions and every RNG state")
	check(shown.elapsed>18.0 and not shown.continuous.director.history.is_empty(),"Parity covers a real later threat-director admission")
	measurements.director_parity={"seconds":shown.elapsed,"history":shown.continuous.director.history.duplicate(true),"census":shown.continuous.snapshot()}
	shown.free(); hidden.free()

func lifecycle_fixtures() -> void:
	# Explicitly labelled presentation-only fixtures, never review footage.
	var s: Dictionary=Review.SCENARIOS[0].duplicate(true)
	var b: Node2D=prepare(s)
	for id: int in [3,4,5]:
		check(b.add_full_top({"blade":"hammerfall","ratchet":"mid","bit":"ball"},id,"hostile","beast_bound_fixture_%d"%id,Vector2(30*id,0)),"Presentation budget fixture adds a valid full-top owner")
		b.entity(id).powers=["impact_wake"]
		b.entity(id).power_ranks={"impact_wake":1}
	b.entity(2).powers=["impact_wake"]
	var initial: Dictionary=b.snapshot()
	var random_before: Dictionary=rng_state(b)
	b.beasts.accept_event("comet_release",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":1,"beast_trigger":true})
	b.beasts.accept_event("comet_charge",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":1})
	b.beasts.accept_event("comet_charge",Vector2.ZERO,Vector2.RIGHT,1.0,{"beast_trigger":true})
	check(b.beast_presentation_snapshot().count==0,"Release-only, acquisition-style previews and missing ownership cannot create an avatar")
	for id: int in [2,3,4,5]: b.beasts.accept_event("impact_wake",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":id,"beast_trigger":true})
	check(b.beast_presentation_snapshot().count==3 and b.beast_presentation_snapshot().peak_live==3,"Four eligible owner fixtures cannot exceed the live budget of three")
	check(b.beast_presentation_snapshot().suppressed>=1,"Overflow owners are explicitly suppressed")
	b.beasts.accept_event("impact_wake",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":2,"beast_trigger":true})
	check(b.beast_presentation_snapshot().count==3,"Owner cooldown prevents a repeated fixture from allocating another slot")
	b.beasts.accept_event("comet_charge",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":1,"beast_trigger":true})
	var player_retained: bool=false
	for item: Dictionary in b.beast_presentation_snapshot().active:
		if int(item.owner_entity_id)==1: player_retained=true
	check(player_retained and b.beast_presentation_snapshot().count==3,"Player's meaningful commitment replaces an enemy slot while retaining the live budget")
	for tick: int in range(120): b.beasts.accept_event("impact_wake",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":3,"beast_trigger":true})
	check(b.beast_presentation_snapshot().events.size()<=Beasts.MAX_HISTORY,"Repeated suppressed fixtures cannot grow unbounded presentation history")
	check(b.snapshot()==initial and rng_state(b)==random_before,"Presentation stress cannot mutate a fighter, collision result or random stream")
	b.beasts.reset()
	b.player_entity().comet_time=2.0
	b.beasts.accept_event("comet_charge",b.player_entity().pos,Vector2.RIGHT,1.0,{"owner_entity_id":1,"beast_trigger":true})
	var instance: int=int(b.beast_presentation_snapshot().active[0].instance_id)
	b.beasts.update(0.2)
	b.beasts.accept_event("comet_release",Vector2(12,18),Vector2.LEFT,1.0,{"owner_entity_id":1,"beast_trigger":true})
	var resolved: Dictionary=b.beast_presentation_snapshot().active[0]
	check(resolved.instance_id==instance and resolved.phase=="strike" and resolved.world_pos==Vector2(12,18),"Real resolution updates the prepared instance at its accepted contact point")
	b.beasts.update(0.5); b.beasts.update(0.5)
	check(b.beast_presentation_snapshot().count==0,"Completed strike and recovery expire without leaving a mascot")
	var spawned: int=int(b.beast_presentation_snapshot().spawned)
	b.beasts.accept_event("comet_charge",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":1,"beast_trigger":true})
	check(b.beast_presentation_snapshot().spawned==spawned,"Resolved owners retain the four-second cooldown")
	b.beasts.update(3.1)
	b.beasts.accept_event("comet_charge",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":1,"beast_trigger":true})
	check(b.beast_presentation_snapshot().count==1,"Owner cooldown rearms after its elapsed duration")
	b.player_entity().comet_time=0.0
	b.beasts.update(0.01)
	check(b.beast_presentation_snapshot().active[0].phase=="recovery" and not b.beast_presentation_snapshot().active[0].impact,"A missed/expired charge recovers without inventing impact")
	b.beasts.update(0.6)
	check(b.beast_presentation_snapshot().count==0,"Miss recovery expires")
	b.beasts.reset(); b.player_entity().comet_time=10.0
	b.beasts.accept_event("comet_charge",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":1,"beast_trigger":true})
	b.beasts.update(Beasts.MAX_INSTANCE_SECONDS)
	check(b.beast_presentation_snapshot().count==0,"Even armed fixture timers cannot outlive the hard four-second presentation budget")
	b.beasts.reset()
	b.beasts.accept_event("comet_charge",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":1,"beast_trigger":true})
	b.player_entity().outcome="spin_out"
	b.beasts.update(0.01)
	check(b.beast_presentation_snapshot().count==0,"Retiring the owner expires its avatar immediately")
	b.beasts.reset(); b.player_entity().outcome=""
	b.beasts.accept_event("comet_charge",Vector2.ZERO,Vector2.RIGHT,1.0,{"owner_entity_id":1,"beast_trigger":true})
	b.battle_status="finished"; b.beasts.update(0.01)
	check(b.beast_presentation_snapshot().count==0,"Battle outcome expires all remaining avatars")
	b.free()

func catalogue_and_assets() -> void:
	check(Parts.BLADE_IDS.size()+Parts.RATCHET_IDS.size()+Parts.BIT_IDS.size()==31,"Avatar presentation preserves the31-part catalogue")
	for blade: String in Parts.BLADE_IDS: check(not Beasts.beast_for_blade(blade).is_empty(),"Every existing blade maps to one authored identity")
	check(Beasts.beast_for_blade("not_a_blade")=="","Unknown blades cannot invent an identity")
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(Beasts.MANIFEST_PATH))
	check(parsed is Dictionary and parsed.get("effects",{}).size()==4,"Beast manifest contains exactly four authored identities")
	if not parsed is Dictionary: return
	var controller=Beasts.new()
	for identity: String in ["black_arrow","iron_bull","stone_tortoise","coil_dragon"]:
		var meta: Dictionary=parsed.get("effects",{}).get(identity,{})
		var cell: Array=meta.get("cell",[])
		var pivot: Array=meta.get("pivot",[])
		check(cell.size()==2 and pivot.size()==2 and int(cell[0])==128 and int(cell[1])==128 and int(pivot[0])==64 and int(pivot[1])==96,"Each authored beast uses a native128px cell and stable floor pivot")
		for phase: String in ["prepare","travel","strike","recovery","guard"]:
			var tag: Dictionary=meta.get("tags",{}).get(phase,{})
			check(int(tag.get("to",-1))-int(tag.get("from",0))==3,"Each manifestation phase retains four authored frames")
			if tag.is_empty(): continue
			var total: float=0.0
			var durations: Array=meta.get("durations_ms",[])
			for frame: int in range(int(tag.from),int(tag.to)+1):
				check(frame<durations.size() and float(durations[frame])>0.0,"Authored phase timing uses valid positive milliseconds")
				if frame<durations.size(): total+=float(durations[frame])/1000.0
			check(controller.frame_for(identity,phase,0.0)==int(tag.from) and controller.frame_for(identity,phase,total+0.001)==int(tag.to),"Frame sampling respects authored phase endpoints")

func run() -> void:
	catalogue_and_assets()
	actual_cases()
	director_parity()
	lifecycle_fixtures()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess=FileAccess.open(arg.trim_prefix("--report="),FileAccess.WRITE)
			assert(file!=null)
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":Review.portable(measurements),"fixture_policy":"Combat/parity cases use legal initial setups and ordinary inputs. Controller lifecycle/budget cases are explicitly presentation-only fixtures and never used in the real review movie."},"\t")); file.close()
	print("BEAST_MANIFESTATIONS_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
