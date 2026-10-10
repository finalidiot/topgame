extends "res://tests/test_ability_rebalance.gd"
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")

func _run() -> void:
	var report: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
	if not report.is_absolute_path() or FileAccess.file_exists(report): quit(2); return
	for level: int in [1,2]:
		var h: Host=host("chain_impact",level)
		h.fighters.append(fighter(3,"",1,"",Vector2(30,0))); h.entity(3).combatant_type="small_top"
		h.fighters.append(fighter(4,"",1,"",Vector2(15,0))); h.entity(4).team_id="player"
		h.fighters.append(fighter(5,"",1,"",Vector2(100,0)))
		h.runtime.begin_tick(1.0/60.0)
		contact(h,Runtime.CHAIN_HARD_SEVERITY-0.00001)
		check(h.runtime._next_tick_pulses.is_empty() and int(h.runtime.counters.get("chain_prime",0))==0,"Just-below-hard contact never primes or pulses")
		contact(h,Runtime.CHAIN_HARD_SEVERITY)
		check(h.runtime._next_tick_pulses.size()==1 and int(h.runtime.counters.get("chain_prime",0))==1,"The exact canonical hard tier primes one next-tick physical pulse")
		var cause: Dictionary=h.runtime._next_tick_pulses[0].cause
		check(int(cause.owner_entity_id)==1 and int(cause.root_event_id)>0 and int(cause.generation)==1,"Pulse retains the accepted contact owner/root with bounded generation")
		check(h.impulses.is_empty(),"Hard-hit pulse waits for the next fixed tick")
		contact(h,0.99)
		check(h.runtime._next_tick_pulses.size()==1,"Same-tick hard contacts cannot spam the owner presentation")
		h.runtime.begin_tick(1.0/60.0)
		check(int(h.runtime.counters.get("chain_impact",0))==1 and h.impulses.size()==2,"One physical pulse reaches the nearby full and small hostile bodies")
		check(is_equal_approx(Vector2(h.entity(2).vel).length(),24.0 if level==2 else 15.0),"Full-top pulse keeps its existing bounded physical impulse")
		check(is_equal_approx(Vector2(h.entity(3).vel).length(),82.0 if level==2 else 65.0),"Small-top pulse keeps its existing bounded physical impulse")
		check(Vector2(h.entity(1).vel)==Vector2.ZERO and Vector2(h.entity(4).vel)==Vector2.ZERO and Vector2(h.entity(5).vel)==Vector2.ZERO,"Owner, friendly and distant bodies receive no pulse")
		h.entity(3).outcome="spin_out"
		h.runtime.eliminated(h.entity(3),"spin_out"); h.runtime.end_tick(false)
		check(h.runtime._eliminations.is_empty() and h.runtime._next_tick_pulses.is_empty(),"A credited knockout no longer activates or recursively farms Chain")
		h.runtime.burst_started(h.entity(1),Vector2.RIGHT,1.0)
		h.runtime.flush_contact_powers()
		check(int(h.runtime.counters.get("chain_burst",0))==1,"The genuine hard-hit prime retains its ordinary Burst follow-up")
		h.runtime.burst_started(h.entity(1),Vector2.RIGHT,1.0); h.runtime.flush_contact_powers()
		check(int(h.runtime.counters.get("chain_burst",0))==1,"Follow-up consumes the prime once")
		var ready: float=float(h.runtime._state(h.entity(1)).chain_ready)
		while h.runtime.time < ready-0.02: h.runtime.begin_tick(1.0/60.0)
		contact(h,0.99)
		check(h.runtime._next_tick_pulses.is_empty(),"An enormous contact before cooldown cannot retrigger")
		while h.runtime.time < ready: h.runtime.begin_tick(1.0/60.0)
		contact(h,Runtime.CHAIN_HARD_SEVERITY+0.00001)
		check(h.runtime._next_tick_pulses.size()==1,"Just-above-hard contact qualifies after cooldown")
		measurements["rank_%d"%level]={"hard_threshold":Runtime.CHAIN_HARD_SEVERITY,"cooldown":2.0 if level==1 else 1.65,"counters":h.runtime.counters.duplicate()}
	var npc: Host=host("")
	npc.entity(2).powers=["chain_impact"]; npc.entity(2).power_ranks={"chain_impact":2}
	contact(npc,0.90)
	check(npc.runtime._next_tick_pulses.size()==1 and int(npc.runtime._next_tick_pulses[0].cause.owner_entity_id)==2,"Enemy-owned Chain uses the same real-contact trigger and its own cause")
	await real_collision()
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,
		"scope":"Threshold/cooldown/provenance semantic host plus actual canonical Battle solver. The solver fixture declares only initial powers/pose/velocity; no reserve, severity, outcome or reward is forced."},"\t"));file.close()
	print("CHAIN_HARD_HITS_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func real_collision() -> void:
	var b: Node2D=Battle.new();root.add_child(b);b.set_physics_process(false);b.particles_enabled=false
	var descriptor: Dictionary=Encounters.for_run_event(1,421)
	descriptor.player_power_ids=["chain_impact"];descriptor.player_power_ranks={"chain_impact":1}
	b.begin_run({"blade":"smash","ratchet":"high","bit":"flat"},descriptor,421)
	for tick: int in range(400):
		b.test_step(Battle.FIXED_DT,Vector2.ZERO,false,false)
		if b.battle_status=="battle" and b.fighters.size()>=2:break
	check(b.battle_status=="battle" and b.fighters.size()>=2,"The solver fixture reaches actual admitted combat")
	if b.fighters.size()<2:b.free();return
	b.continuous.director.next_decision=1000000.0
	var p: Dictionary=b.player_entity();var enemy: Dictionary=b.fighters[1]
	p.pos=Vector2(-14,0);enemy.pos=Vector2(14,0);p.vel=Vector2(600,0);enemy.vel=Vector2(-600,0)
	var collisions: Array=[]
	b.full_top_impact_accepted.connect(func(row: Dictionary) -> void: collisions.append(row.duplicate(true)))
	for tick: int in range(10):b.test_step(Battle.FIXED_DT,Vector2.ZERO,false,false)
	check(not collisions.is_empty() and float(collisions[0].severity)>=Runtime.CHAIN_HARD_SEVERITY,"Actual solver creates a qualifying physical hard hit")
	check(int(b.powers.counters.get("chain_prime",0))>=1 and int(b.powers.counters.get("chain_impact",0))>=1,"Actual qualifying collision primes and presents Chain without a knockout")
	check(str(enemy.outcome).is_empty(),"The genuine Chain event occurs while the struck top remains alive")
	measurements["actual_solver"]={"collisions":collisions,"powers":b.powers.counters.duplicate(),"enemy_alive":str(enemy.outcome).is_empty(),"rpm":p.rpm,"economy":b.continuous.economy.snapshot()}
	b.free()
