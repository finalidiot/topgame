extends SceneTree
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: "+label)

func make_battle(power_ids: Array = []) -> Node2D:
	var b: Node2D = Battle.new()
	root.add_child(b)
	b.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_slot(3,421)
	descriptor.player_power_ids = power_ids
	b.begin_encounter({"blade":"smash","ratchet":"low","bit":"flat"},descriptor)
	b.battle_status = "battle"
	return b

func physical(b: Node2D) -> Dictionary:
	var state: Dictionary = b.snapshot()
	for f: Dictionary in state.entities.values(): f.erase("phase")
	state.erase("player")
	state.erase("enemy")
	state["power_events"] = b.powers.events.duplicate(true)
	state["traces"] = b.powers.traces.duplicate(true)
	return state

func _run() -> void:
	test_schedule()
	test_contact_and_retirement()
	test_safe_entry_and_ceiling()
	test_replay()
	test_tunnelling_and_budget()
	test_run_result_priority()
	test_blocked_admission()
	print("SWARM_TEST_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_schedule() -> void:
	var b: Node2D = make_battle()
	check(b.fighters.size()==1,"Swarm launches no full rival")
	check(b.swarm.schedule.size()==24,"24 scheduled entries")
	var minimum_gap_safe: bool = true
	var previous_spawned: int = 0
	for tick: int in range(2100):
		# Schedule fixture keeps the player healthy; it does not assert combat balance.
		b.player_entity().rpm = 1.0
		b.player_entity().pos = Vector2.ZERO
		b.player_entity().vel = Vector2.ZERO
		b.test_step(Battle.FIXED_DT,Vector2.ZERO,false,true)
		if b.swarm.spawned > previous_spawned:
			for f: Dictionary in b.fighters:
				if f.combatant_type=="small_top" and float(f.age)<0.025:
					minimum_gap_safe = minimum_gap_safe and Vector2(f.pos).distance_to(b.player_entity().pos)>40.0
		previous_spawned = b.swarm.spawned
		if b.battle_status=="finished": break
	check(b.last_result.get("won",false) and b.last_result.reason=="swarm_clear","Schedule completes only after all waves")
	check(b.swarm.spawned==24 and b.swarm.cancelled==0,"Ordinary safe run admits all24")
	check(b.swarm.peak_active<=12 and b.swarm.active_count()==0,"Population cap and cleanup")
	check(b.swarm.wave==3 and b.elapsed>=18.0,"Empty gap cannot end earlier wave")
	check(minimum_gap_safe,"Telegraphed spawns clear player")
	check(b.swarm.retired+b.swarm.eliminated==24,"Every body accounted for")
	check(not b.swarm.cleanup_used,"Normal schedule clears without emergency ceiling")
	print("SCHEDULE ",b.swarm.telemetry()," duration=",b.elapsed)
	b.free()

func test_contact_and_retirement() -> void:
	var b: Node2D = make_battle(["impact_wake","chain_impact"])
	var small: Dictionary = b.swarm.add_small(40,Vector2(14,0))
	var neighbor: Dictionary = b.swarm.add_small(41,Vector2(36,0))
	b.player_entity().pos = Vector2.ZERO
	b.player_entity().vel = Vector2(260,0)
	b.resolve_pair(1,40)
	b.powers.flush_contact_powers()
	check(not small.has("build") and not small.has("stats"),"Small records have no parts or six-stat build")
	check(Vector2(small.vel).length()>118.0,"Clean hit throws small faster than chase")
	check(not b.powers.cause_for(small).is_empty(),"Player physical contact attributes thrown body")
	check(Vector2(neighbor.vel).length()>0.0 and b.powers.counters.get("impact_wake",0)==1,"Wake scatters nearby small body")
	b.swarm.account_outcomes()
	b.powers.end_tick(false)
	b.powers.begin_tick(Battle.FIXED_DT)
	check(b.powers.counters.get("chain_impact",0)>=1,"Player knockout naturally queues next-tick Chain")
	var retired: Dictionary = b.swarm.add_small(42,Vector2(-50,20))
	retired.player_cause = b.powers.cause_for(small)
	var prior: int = b.powers.counters.get("chain_impact",0)
	b.swarm.retire(retired,"natural_retirement")
	b.powers.end_tick(false)
	b.powers.begin_tick(Battle.FIXED_DT)
	check(b.powers.counters.get("chain_impact",0)==prior,"Natural expiry never earns Chain credit")
	b.free()

func test_safe_entry_and_ceiling() -> void:
	var b: Node2D = make_battle(["second_wind"])
	var entry: Dictionary = b.swarm.schedule[0]
	var chosen: int = b.swarm.safe_port(entry)
	b.player_entity().pos = b.swarm.PORTS[chosen]
	check(not b.swarm.port_safe(chosen,int(entry.id)),"Player-blocked port rejected")
	check(b.swarm.safe_port(entry)!=chosen,"Fallback is deterministic and safe")
	for i: int in range(12): b.swarm.add_small(50+i,Vector2(i*12-65,60))
	check(b.swarm.add_small(99,Vector2.ZERO).is_empty(),"Cannot exceed12 even at API boundary")
	b.elapsed = 32.0
	b.swarm.begin_tick(Battle.FIXED_DT)
	b._check_result()
	check(b.swarm.cleanup_used and b.swarm.clear(),"Cleanup accounts pending entries and retirees")
	check(b.last_result.get("won",false),"Cleanup survival clears")
	b.free()
	b = make_battle(["second_wind"])
	b.player_entity().pos = Vector2(145,-145)
	b.player_entity().rpm = 0.1
	b._resolve_boundary(b.player_entity())
	b.powers.recover()
	b.elapsed = 32.0
	b.swarm.begin_tick(Battle.FIXED_DT)
	b._check_result()
	check(not b.last_result.won and b.last_result.reason=="ring_out","Player ring-out wins priority over cleanup and recovery")
	b.free()

func test_replay() -> void:
	var a: Node2D = make_battle(["redline","afterimage","impact_wake","chain_impact","iron_comet","second_wind"])
	var b: Node2D = make_battle(["redline","afterimage","impact_wake","chain_impact","iron_comet","second_wind"])
	b.particles_enabled = false
	b.screen_shake_enabled = false
	b._cosmetic_rng.seed = 812345
	var matches: bool = true
	var samples: Array[float] = []
	for tick: int in range(1900):
		var direction: Vector2 = Vector2(sin(tick*0.023),cos(tick*0.019))
		var before: int = Time.get_ticks_usec()
		a.test_step(Battle.FIXED_DT,direction,tick%250==0,tick%130>115)
		samples.append(float(Time.get_ticks_usec()-before)/1000.0)
		b.fighters.reverse()
		b.test_step(Battle.FIXED_DT,direction,tick%250==0,tick%130>115)
		if physical(a)!=physical(b):
			matches = false
			break
		if a.battle_status=="finished": break
	check(matches,"Seed+recorded input reproduces swarm, powers, results with different cosmetics/order")
	samples.sort()
	print("REPLAY simulation_ms_median=",samples[samples.size()/2]," p95=",samples[int(samples.size()*0.95)]," max=",samples.back()," power_counters=",a.powers.counters)
	a.free()
	b.free()

func test_tunnelling_and_budget() -> void:
	var b: Node2D = make_battle()
	var a: Dictionary = b.swarm.add_small(80,Vector2(-7,60))
	var c: Dictionary = b.swarm.add_small(81,Vector2(7,60))
	a.vel = Vector2(400,0)
	c.vel = Vector2(-400,0)
	a.impulse_time = 0.5
	c.impulse_time = 0.5
	b.test_step(Battle.FIXED_DT)
	check(float(a.vel.x)<0 and float(c.vel.x)>0,"Opposing400 speed bodies collide instead of tunnel")
	b.free()

	b = make_battle()
	var player: Dictionary = b.player_entity()
	player.rpm = 1.0
	for index: int in range(12):
		var small: Dictionary = b.swarm.add_small(90+index,Vector2(14,0))
		player.pos = Vector2.ZERO
		player.vel = Vector2(250,0)
		small.vel = Vector2(-250,0)
		b.resolve_pair(1,int(small.entity_id))
	check(float(player.rpm)>=0.985-0.000001,"12 overlapping contacts obey aggregate .015 reserve cap")
	check(b._hit_stop==0.0,"Small contacts never impose global hit-stop")
	b.free()

func test_run_result_priority() -> void:
	for scenario: String in ["simultaneous", "timeout_tie"]:
		var b: Node2D = Battle.new()
		root.add_child(b)
		b.set_physics_process(false)
		b.begin_encounter({"blade":"balance","ratchet":"mid","bit":"ball"},Encounters.for_slot(1,1))
		b.battle_status = "battle"
		if scenario == "simultaneous":
			b.player_entity().outcome = "ring_out"
			b.player_entity().rpm = 0.9
			b.entity(2).outcome = "ring_out"
			b.entity(2).rpm = 0.1
		else:
			b.elapsed = 60.0
			b.player_entity().rpm = 0.5
			b.entity(2).rpm = 0.5
		b._check_result()
		check(not b.last_result.won,"Run fails without reward on "+scenario)
		b.free()

func test_blocked_admission() -> void:
	var b: Node2D = make_battle()
	b.swarm.begin_tick(Battle.FIXED_DT)
	var entry: Dictionary = b.swarm.schedule[0]
	check(entry.state=="telegraph","Entry advertises before spawning")
	b.player_entity().pos = b.swarm.PORTS[int(entry.port)]
	b.elapsed = float(entry.ready)+0.01
	b.swarm.begin_tick(Battle.FIXED_DT)
	check(b.entity(int(entry.id)).is_empty(),"Moving into mature telegraph defers entry")
	check(entry.state=="waiting","A relocated entry must telegraph again")
	b.free()
	b = make_battle(["chain_impact"])
	for i: int in range(b.swarm.PORTS.size()):
		b.add_full_top({"blade":"guard","ratchet":"low","bit":"needle"},100+i,"neutral","blocker",b.swarm.PORTS[i])
	for tick: int in range(1500):
		b.elapsed += Battle.FIXED_DT
		b.swarm.begin_tick(Battle.FIXED_DT)
	check(b.swarm.cancelled==24 and b.swarm.spawned==0 and b.swarm.clear(),"All ports blocked eventually cancel/account every entry")
	b.free()
	b = make_battle(["chain_impact"])
	var small: Dictionary = b.swarm.add_small(60,Vector2(140,-140))
	small.vel = Vector2(200,-200)
	b._resolve_boundary(small)
	b.swarm.account_outcomes()
	b.swarm.account_outcomes()
	check(b.swarm.eliminated==1,"Repeated outcome scans count ring-out once")
	var old_position: Vector2 = small.pos
	b.swarm.begin_tick(Battle.FIXED_DT)
	check(Vector2(small.pos).distance_to(old_position)>0.0,"Lethal launch retains visual retirement momentum")
	b.free()
