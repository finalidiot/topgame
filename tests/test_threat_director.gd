extends "res://tests/test_continuous_run.gd"
## Policy load model is explicitly synthetic; real combat has a separate diagnostic.
const Director = preload("res://scripts/threat_director.gd")
const Roles = preload("res://scripts/enemy_roles.gd")
const Seeds = preload("res://scripts/seed_utils.gd")
var diagnostics: Array[Dictionary] = []

func _run() -> void:
	var sequences: Dictionary = {}
	for seed_value: int in [421,7341,11,81,2026,99,123,77]:
		var sample: Dictionary = simulate(seed_value)
		diagnostics.append(sample)
		sequences[str(sample.sequence)] = true
		check(sample.bosses > 0 and sample.elites > 0 and sample.swarms > 0,"Long policy sample exercises all event classes")
		check(sample.first_boss >= float(Director.TUNING.tier_seconds[2]) and sample.longest_empty < 8.0,"Boss eligibility follows the authored tier; empty-gap bounds remain")
		check(sample.max_tier > 4 and sample.events > 30,"Policy continues beyond authored tiers")
	check(sequences.size() == 8,"Different seeds produce different compositions/timing")
	check(simulate(421) == diagnostics[0],"Identical seed and census reproduce every decision and pacing statistic")
	_test_overlap_and_boss()
	_test_roles()
	_test_policy_edges()
	_test_bounded_lull()
	_test_earlier_questions()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--report="),FileAccess.WRITE)
			file.store_string(JSON.stringify({"scope":"900-second synthetic occupancy model. Tests policy, caps and pacing; does not claim combat survival.","samples":diagnostics},"\t"))
	print("THREAT_DIRECTOR_%s checks=%d failures=%d samples=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures,diagnostics.size()])
	quit(1 if failures else 0)

func simulate(seed_value: int) -> Dictionary:
	var director = Director.new()
	director.setup(seed_value)
	var live: Array[Dictionary] = [{"serial":1,"kind":"rival","key":"hunter","cost":2.6,"expires":27.0}]
	var report: Dictionary = {"seed":seed_value,"sequence":[],"events":1,"bosses":0,"elites":0,"swarms":0,"first_boss":-1.0,"first_elite":-1.0,"first_swarm":-1.0,"first_specialist":-1.0,"first_overlap":-1.0,"max_full":1,"max_entities":2,"max_tier":0,"longest_empty":0.0,"calm_seconds":0.0}
	var pressures: Array[float] = []
	var empty_gap: float = 0.0
	var previous_boss: Dictionary = {}
	var caps_ok: bool = true
	var history_ok: bool = true
	for tick: int in range(3600):
		var time: float = tick*0.25
		for index: int in range(live.size()-1,-1,-1):
			if time >= float(live[index].expires):
				var ended: Dictionary = live[index]
				live.remove_at(index)
				director.cleared(int(ended.serial),time,live.is_empty())
		var c: Dictionary = {"pressure":0.0,"full":0,"small":0,"elites":0,"bosses":0,"total":1,"swarm":false}
		for e: Dictionary in live:
			c.pressure += float(e.cost)
			if e.kind == "swarm": c.swarm = true; c.small += int(e.small_cap)
			else: c.full += 1
			if e.kind == "elite": c.elites += 1
			if e.kind == "boss": c.bosses += 1
		c.total += int(c.small)+int(c.full)
		var limit: Dictionary = Director.limits(time,mini(13,1+int(time/25.0)))
		caps_ok = caps_ok and c.pressure <= limit.budget+0.00001 and c.full <= limit.full and c.total <= limit.total and c.small <= limit.small and c.elites <= limit.elites and c.bosses <= limit.bosses
		report.max_full = maxi(report.max_full,c.full)
		report.max_entities = maxi(report.max_entities,c.total)
		report.max_tier = limit.tier
		if c.pressure == 0.0: empty_gap += 0.25
		else: empty_gap = 0.0
		report.longest_empty = maxf(report.longest_empty,empty_gap)
		if c.full+int(c.swarm) > 1 and report.first_overlap < 0.0: report.first_overlap = time
		if director.draining or time < director.calm_until: report.calm_seconds += 0.25
		if tick%4 == 0: pressures.append(c.pressure)
		var event: Dictionary = director.decide(time,c,mini(13,1+int(time/25.0)))
		if event.is_empty(): continue
		var random_life: RandomNumberGenerator = RandomNumberGenerator.new()
		random_life.seed = Seeds.derive(seed_value,"test_lifetime/%d" % event.serial)
		event["expires"] = time+random_life.randf_range(21,40)+(30.0 if event.kind == "boss" else (10.0 if event.kind == "elite" else 0.0))
		if event.kind == "swarm": event.expires = time+30.0
		live.append(event)
		report.events += 1
		report.sequence.append({"key":event.key,"time":time,"tier":limit.tier})
		for kind: String in ["boss","elite","swarm","specialist"]:
			if event.kind == kind and float(report["first_"+kind]) < 0.0: report["first_"+kind] = time
		if event.kind == "boss":
			report.bosses += 1
			if previous_boss.has(event.key): history_ok = history_ok and time-float(previous_boss[event.key]) >= float(Director.TUNING.same_boss_cooldown)
			previous_boss[event.key] = time
		if event.kind == "elite": report.elites += 1
		if event.kind == "swarm": report.swarms += 1
		var n: int = report.sequence.size()
		if n >= 3: history_ok = history_ok and not (report.sequence[n-1].key == report.sequence[n-2].key and report.sequence[n-2].key == report.sequence[n-3].key)
	check(caps_ok,"Every policy sample respects reserved pressure and every population cap")
	check(history_ok,"No three consecutive identical roles or immediate repeated boss")
	check(director.active.size() <= 6 and director.history.size() <= 128 and director.recent.size() <= 6,"Director records remain bounded")
	var sum: float = 0.0
	for pressure: float in pressures: sum += pressure
	pressures.sort()
	report["average_pressure"] = sum/pressures.size()
	report["median_pressure"] = pressures[pressures.size()/2]
	return report

func force_event(b: Node, key: String) -> void:
	var runtime = b.continuous
	var event: Dictionary = {}
	for definition: Dictionary in Director.EVENTS:
		if definition.key == key: event = definition.duplicate(true)
	event["serial"] = runtime.threat_number+1
	event["tier_at_entry"] = Director.tier_at(b.elapsed)
	event["small_cap"] = 10
	event["ready_at"] = b.elapsed
	event["position"] = runtime._safe_entry()
	runtime.director.serial = int(event.serial)
	runtime.director.active[int(event.serial)] = {"kind":event.kind,"time":b.elapsed}
	runtime.pending = event
	check(runtime._admit_pending(),"Controlled admission uses normal safe admission path")

func _test_overlap_and_boss() -> void:
	var game: QuietMain = make_game()
	var b: Node2D = game.battle
	b.battle_status = "battle"
	b.elapsed = 210.0
	b.powers.time = 210.0
	var p: Dictionary = b.player_entity()
	p.rpm = 0.62; p.cooldown = 1.3; p.vel = Vector2(7,12); p.wobble = 0.31
	var before: Dictionary = p.duplicate(true)
	var enemy: Dictionary = b.entity(2)
	force_event(b,"anvil")
	check(p == before and is_same(p,b.player_entity()) and is_same(enemy,b.entity(2)),"Boss joins existing combat without changing player or rival")
	var boss: Dictionary = b.entity(b.continuous.next_entity_id-1)
	force_event(b,"ammunition")
	var schedule: Array = b.swarm.schedule.duplicate(true)
	var clock: float = b.swarm.started_at
	# Rival admissions cannot erase a live swarm. Fixture raises time only for eligibility.
	b.elapsed = 500.0
	force_event(b,"harasser")
	check(b.swarm.schedule == schedule and b.swarm.started_at == clock,"Adding a rival cannot restart or overwrite a swarm")
	check(b.continuous.events.size() == 4 and b.fighters.size() == 4,"Overlapping events keep all full-size enemies")
	b._progression_contacted[int(boss.entity_id)] = true
	boss.outcome = "spin_out"
	b._collect_progression_outcomes()
	var earned: Array = b._progression_queue.duplicate(true)
	b._progression_queue.clear()
	game._progression_events(earned)
	settle_drafts(game)
	b.continuous.after_tick(0.0)
	check(game.run_context.level >= 2 and game.run_context.owned_power_ids.size() >= 1,"Boss XP uses live earned investment path")
	check(b.battle_status == "battle" and game.screen == "battle" and b.continuous.bosses_defeated == 1,"Boss defeat cannot terminate a Run")
	check(is_same(p,b.player_entity()) and p.rpm == before.rpm and p.vel == before.vel,"Post-boss draft and continuation retain exact physical state")
	var retired_runtime = b.continuous
	var clear_count: int = retired_runtime.threats_cleared
	check(not retired_runtime.director.cleared(int(boss.event_serial),b.elapsed,false),"Duplicate director clear is rejected")
	Fixtures.defeat_player(game)
	game._action("restart_run")
	claim(game)
	retired_runtime.after_tick(10.0)
	check(retired_runtime.threats_cleared == clear_count and game.battle.continuous != retired_runtime,"Discarded runtime cannot admit or clear events in a new Run")
	game.free()

func _test_roles() -> void:
	var player: Dictionary = {"pos":Vector2.ZERO,"vel":Vector2(10,0)}
	var vectors: Dictionary = {}
	for role: String in Roles.BUILDS:
		var f: Dictionary = {"pos":Vector2(65,0),"entity_id":2,"role":role,"archetype":role,"role_phase":0.0}
		var direction: Vector2 = Roles.direction(f,player,2.5)
		vectors[str(direction)] = true
		check(direction.is_finite() and direction.length() <= 0.951,"Movement policy has finite bounded steering")
	check(vectors.size() == 4,"Identical arena state produces four distinct movement intents")
	check(Director.limits(100000.0).budget > Director.limits(900.0).budget and Director.limits(100000.0).total == 16,"Endless pressure scales without unbounded population")
	var hunter: Vector2 = Roles.direction({"pos":Vector2(65,0),"entity_id":2,"role":"hunter","archetype":"hunter","role_phase":0.0},player,2.5)
	var harasser: Vector2 = Roles.direction({"pos":Vector2(65,0),"entity_id":2,"role":"harasser","archetype":"harasser","role_phase":0.0},player,2.5)
	check(hunter.x < -0.8 and harasser.x > 0.3,"Hunter commits while harasser retreats tangentially between contacts")
	check(Roles.ELITES.ballast.mass > 1.4 and Roles.ELITES.ballast.speed < 1.0 and Roles.ELITES.hotwire.recovery < 1.0,"Elites carry real movement/mass tradeoffs")
	check(Roles.BOSSES.anvil.mass > Roles.BOSSES.reaper.mass and Roles.BOSSES.anvil.speed < Roles.BOSSES.reaper.speed,"Bosses have contrasting physical identity")

func _test_policy_edges() -> void:
	var director = Director.new()
	director.setup(421)
	var c: Dictionary = {"pressure":7.0,"full":1,"small":0,"total":2,"elites":0,"bosses":1,"swarm":false}
	var early: Array[Dictionary] = director.candidates(150.0,c,13)
	var late: Array[Dictionary] = director.candidates(600.0,c,13)
	var early_boss: bool = false
	var late_boss: bool = false
	for e: Dictionary in early: early_boss = early_boss or e.kind == "boss"
	for e: Dictionary in late: late_boss = late_boss or e.kind == "boss"
	check(not early_boss and late_boss,"One early boss maximum, two late bosses possible within the budget")
	c.pressure = 100.0
	check(director.candidates(600.0,c,13).is_empty(),"No candidate can overspend committed pressure")
	for serial: int in range(10,15):
		director.active[serial] = {"time":0.0,"kind":"rival"}
		director.cleared(serial,5.0,false)
	check(director.fast_clears == 4,"Fast-clear adaptation is capped at four increments / 20 percent")
	check(not director.cleared(999,6.0,true),"Unknown director outcomes cannot grant recovery or mutate history")
	var game: QuietMain = make_game()
	var b: Node2D = game.battle
	b.battle_status = "battle"
	b.continuous.pending = {"kind":"boss","cost":7.0,"serial":2,"position":Vector2(115,30),"ready_at":3.0}
	var pending: Dictionary = b.continuous.pending.duplicate(true)
	var rng_state: int = b.continuous.director.rng.state
	b.set_paused(true)
	for tick: int in range(600): b.test_step(b.FIXED_DT)
	check(b.elapsed == 0.0 and b.continuous.pending == pending and b.continuous.director.rng.state == rng_state,"Pause freezes boss warning, admission and director randomness")
	for tick: int in range(100): b._cosmetic_rng.randf(); b._simulation_rng.randf()
	check(b.continuous.director.rng.state == rng_state,"Director stream is isolated from cosmetics and combat RNG")
	game.free()
	game = make_game()
	b = game.battle
	b.battle_status = "battle"
	b.elapsed = 600.0
	force_event(b,"anvil")
	force_event(b,"reaper")
	var mixed: Dictionary = b.continuous.census()
	check(mixed.bosses == 2 and mixed.pressure <= Director.limits(600.0).budget,"Two distinct late bosses coexist within a legal pressure reservation")
	var anvil: Dictionary = b.entity(3)
	var reaper: Dictionary = b.entity(4)
	anvil.outcome = "spin_out"
	b.continuous.after_tick(0.0)
	check(is_same(reaper,b.entity(4)) and reaper.outcome == "" and game.screen == "battle","One boss clear leaves the other boss and Run alive")
	game.free()

func _test_bounded_lull() -> void:
	var director = Director.new()
	director.setup(421)
	director.next_decision = 55.0
	var census: Dictionary = {"pressure":2.8,"full":1,"small":0,"total":2,"elites":0,"bosses":0,"swarm":false}
	check(director.decide(55.0,census,4).is_empty() and director.draining,"A busy schedule still offers a real admission lull")
	var initial_rng: int = director.rng.state
	for second: int in range(56,65):
		check(director.decide(float(second),census,4).is_empty() and director.draining,"Durable surviving rival keeps the bounded admission lull")
	check(director.rng.state == initial_rng,"Waiting on the bounded lull does not consume decision randomness")
	check(director.decide(65.0,census,4).is_empty() and not director.draining,"Ten-second lull releases even when one Bulwark remains above the old 45% threshold")
	check(director.calm_until >= 66.5 and director.calm_until <= 67.75,"A readable short breath follows the bounded lull")
	var choice: Dictionary = director.decide(director.calm_until + 0.01,census,4)
	check(not choice.is_empty() and census.pressure + choice.cost <= Director.limits(director.calm_until,4).budget,"Schedule returns to normal budget-guarded admissions, without killing or changing the surviving rival")
	var twin = Director.new()
	twin.setup(421)
	twin.next_decision = 55.0
	for second: int in range(55,66): twin.decide(float(second),census,4)
	var replay: Dictionary = twin.decide(twin.calm_until + 0.01,census,4)
	check(choice == replay and director.rng.state == twin.rng.state,"Identical seed/census reproduces the lull and subsequent choice exactly")

func _test_earlier_questions() -> void:
	var director = Director.new()
	director.setup(421)
	var empty: Dictionary = {"pressure":0.0,"full":0,"small":0,"total":1,"elites":0,"bosses":0,"swarm":false}
	for time: float in [0.0,19.9,27.99]:
		for event: Dictionary in director.candidates(time,empty,10):
			check(event.kind == "rival","Opening remains a single rival question before the 28-second mixed tier")
	check(Director.limits(20.0,21).full == 1 and Director.limits(20.0,21).budget == 2.8,"Even a declared strong early build cannot cause an instant opening swarm or overlap")
	var mixed: Array[String] = []
	for event: Dictionary in director.candidates(28.0,empty,4): mixed.append(str(event.kind))
	check("specialist" in mixed and "swarm" in mixed and "elite" not in mixed and "boss" not in mixed,"First mixed role questions arrive at 28 seconds, with elites/bosses deferred")
	var developed: Array[String] = []
	for event: Dictionary in director.candidates(80.0,empty,4): developed.append(str(event.kind))
	check("elite" in developed and "boss" in developed,"Developed 80-second budget admits warned elite/boss candidates")
	for index: int in range(1,5):
		var boundary: float = Director.TUNING.tier_seconds[index]
		check(Director.tier_at(boundary - 0.001) == index - 1 and Director.tier_at(boundary) == index,"Every tier switches deterministically at its authored boundary")
	check(Director.tier_at(399.999) == 4 and Director.tier_at(400.0) == 5,"Endless budget growth is measured from the new final authored tier, not the retired 360-second boundary")
	var player: Dictionary = {"pos":Vector2.ZERO,"vel":Vector2.ZERO}
	var f: Dictionary = {"pos":Vector2(65,0),"entity_id":2,"role":"hunter","archetype":"hunter","role_phase":0.0,"role_commit_cycle":-1}
	Roles.direction(f,player,27.99)
	check(not f.has("role_attack_state"),"Original opening approach remains intact before committed attacks unlock")
	Roles.direction(f,player,28.0)
	check(f.get("role_attack_state","") in ["set_up","committed","recover"],"The same telegraphed attack policy unlocks at 28 seconds")
	check(Roles.COMMIT_MATURITY_SECONDS == 325.0 and Roles.ELITES.ballast.mass == 1.55 and Roles.BOSSES.anvil.mass == 2.0,"Earlier commitments retain original maturity shape and authored enemy stat profiles")
