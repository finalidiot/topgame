extends "res://tests/test_ability_rebalance.gd"
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
class GatedHost extends Host:
	var paused: bool=false
	var battle_status: String="battle"

func gate_host(level: int, owner: int = 1) -> GatedHost:
	var h:=GatedHost.new()
	h.fighters=[fighter(1),fighter(2)]
	var p: Dictionary=h.entity(owner)
	p.powers=["orbit_drive"];p.power_ranks={"orbit_drive":level};p.rpm=0.50;p.energy=p.rpm
	p.vel=Vector2(130,0);p.orbit_charge=1.0
	h.runtime=Runtime.new();h.runtime.setup(h);h.runtime.begin_tick(1.0/60.0)
	h.runtime._state(p).motion_input=0.7
	return h

func _run() -> void:
	var report: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
	if not report.is_absolute_path() or FileAccess.file_exists(report):quit(2);return
	for level: int in [1,2]:
		var h:GatedHost=gate_host(level)
		var p:Dictionary=h.entity(1)
		p.orbit_charge=0.99999;h.runtime.after_movement()
		check(h.gains==0.0,"Just-below100% CARVE does not recover RPM")
		p.orbit_charge=1.0;h.runtime.after_movement()
		check(is_equal_approx(h.gains,(0.009 if level==1 else 0.012)/60.0),"Full moving controlled CARVE uses the bounded rank rate")
		check(is_equal_approx(p.energy,p.rpm),"Recovered reserve and displayed energy remain the same canonical value")
		var gained:float=h.gains
		h.paused=true;h.runtime.after_movement();check(h.gains==gained,"Pause cannot recover full-CARVE RPM")
		h.paused=false;h.battle_status="reentry";h.runtime.after_movement();check(h.gains==gained,"READY cannot recover full-CARVE RPM")
		h.battle_status="battle";h.runtime._state(p).motion_input=0.0;h.runtime.after_movement();check(h.gains==gained,"Idle cannot recover even with an artificial full-charge gate fixture")
		h.runtime._state(p).motion_input=0.7;p.vel=Vector2(80,0);h.runtime.after_movement();check(h.gains==gained,"The speed boundary requires actual movement above80")
		p.vel=Vector2(130,0);p.outcome="spin_out";h.runtime.after_movement();check(h.gains==gained,"A dead top cannot recover")
		p.outcome="";p.orbit_charge=0.98;h.runtime.after_movement();check(h.gains==gained,"Loss of charge stops recovery immediately")
		p.orbit_charge=1.0;p.rpm=0.99999;h.runtime.after_movement();check(p.rpm<=1.0,"Ordinary Orbit never raises the reserve ceiling")
		h.runtime.finish();h.runtime.after_movement();check(p.rpm<=1.0,"Terminal presentation cannot resume recovery")
		var npc:GatedHost=gate_host(level,2);var before:float=npc.entity(2).rpm;npc.runtime.after_movement()
		check(is_equal_approx(float(npc.entity(2).rpm)-before,(0.009 if level==1 else 0.012)/60.0),"NPC full CARVE uses the identical rate and motion gates")
		await actual_arc(level)
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,
		"scope":"Semantic boundary fixtures plus an actual solo canonical Run solver. Solo admissions and initial legal assembly/pose/velocity are disclosed fixtures; subsequent charge, speed, reserve, losses and gains come from real controls/physics. No charge/reserve is held or injected into the actual arc."},"\t"));file.close()
	print("ORBIT_FULL_CARVE_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func actual_arc(level: int) -> void:
	var b:Node2D=Battle.new();root.add_child(b);b.set_physics_process(false);b.particles_enabled=false
	var descriptor:Dictionary=Encounters.for_run_event(1,7341)
	descriptor.starter_id="vane";descriptor.player_power_ids=["orbit_drive"];descriptor.player_power_ranks={"orbit_drive":level}
	b.begin_run(Starters.build_for("vane"),descriptor,7341)
	var p:Dictionary=b.player_entity()
	# A solo mechanical fixture isolates carving from contact rewards/AI.
	b.fighters.assign([p]);b.continuous.events.clear();b.continuous.pending.clear()
	b.continuous.director.next_decision=1000000.0
	for tick:int in range(300):
		b.test_step(Battle.FIXED_DT)
		if b.battle_status=="battle":break
	p.pos=Vector2(90,0);p.vel=Vector2(0,105)
	var started:float=b.elapsed
	var first_full:float=-1.0;var full_start_rpm:float=0.0;var highest_full_rpm:float=0.0;var full_ticks:int=0
	var rows:Array=[]
	for tick:int in range(1080):
		var angle:float=PI*0.5+(b.elapsed-started)*1.1
		var world_input:Vector2=Vector2.from_angle(angle)*0.31
		var screen_input:Vector2=Vector2(world_input.x-world_input.y,(world_input.x+world_input.y)*0.5).normalized()*world_input.length()
		b.test_step(Battle.FIXED_DT,screen_input,false,false)
		if float(p.get("orbit_charge",0.0))>=1.0:
			full_ticks+=1
			if first_full<0:first_full=b.elapsed;full_start_rpm=p.rpm
			highest_full_rpm=maxf(highest_full_rpm,float(p.rpm))
		if tick%60==0:rows.append({"time":b.elapsed,"rpm":p.rpm,"carve":p.get("orbit_charge",0.0),"speed":Vector2(p.vel).length(),"position":p.pos,"gains":b.continuous.economy.gains.duplicate(),"losses":b.continuous.economy.losses.duplicate()})
		if b.battle_status=="finished":break
	check(first_full>=0 and full_ticks>=120,"Real paid steering earns and holds full CARVE for at least two seconds")
	check(highest_full_rpm>full_start_rpm+0.0001,"Sustained actual full CARVE raises NET RPM after the normal costs")
	var economy:Dictionary=b.continuous.economy.snapshot()
	check(float(economy.gains.get("orbit_drive",0.0))>0.0,"Actual shared SpinEconomy accounts earned Orbit recovery")
	check(float(economy.losses.passive)>0 and float(economy.losses.movement)>0,"Natural attrition and movement costs remain paid")
	check(str(p.outcome).is_empty() and float(p.rpm)<=1.0,"The controlled carve stays alive under the ordinary reserve cap")
	var before_idle:float=float(economy.gains.get("orbit_drive",0.0))
	for tick:int in range(30):b.test_step(Battle.FIXED_DT,Vector2.ZERO,false,false)
	check(float(b.continuous.economy.gains.get("orbit_drive",0.0))==before_idle and float(p.orbit_charge)<1.0,"Actual input release immediately stops recovery and decays charge")
	check(absf(1.0-sum_values(b.continuous.economy.losses)+sum_values(b.continuous.economy.gains)-float(p.rpm))<0.000001,"The entire actual arc closes the canonical RPM ledger")
	measurements["actual_rank_%d"%level]={"first_full_time":first_full,"full_ticks":full_ticks,"rpm_at_full":full_start_rpm,"highest_full_rpm":highest_full_rpm,"trace":rows,"final_economy":b.continuous.economy.snapshot(),"final_rpm":p.rpm}
	b.free()

func sum_values(values: Dictionary) -> float:
	var result:float=0
	for value:Variant in values.values():result+=float(value)
	return result
