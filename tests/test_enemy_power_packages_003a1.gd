extends "res://tests/test_continuous_run.gd"
const Packages = preload("res://scripts/enemy_power_packages.gd")
const Roles = preload("res://scripts/enemy_roles.gd")
const Catalog = preload("res://scripts/run_powers.gd")
func _run() -> void:
	for identity: String in Packages.PACKAGES:
		for tier: int in range(7):
			var kind: String = "boss" if identity in ["anvil","reaper"] else ("elite" if identity in ["ballast","hotwire"] else "rival")
			var event: Dictionary = {"key":identity,"role":"hunter","kind":kind,"tier_at_entry":tier}
			var package: Dictionary = Packages.for_event(event)
			check(package == Packages.for_event(event),"Authored packages are deterministic")
			check(package.ids.size() <= Catalog.FAMILY_CAP,"Package respects normal family limit")
			if kind == "rival": check(package.ids.size() == (0 if tier == 0 else (1 if tier == 1 else 2)),"Ordinary maturity uses zero / one / two coherent powers")
			for id: String in package.ids:
				check(id in Catalog.ACTIVE_IDS and int(package.ranks[id]) <= Catalog.max_rank(id),"Enemy ownership uses actual implemented ranks")
				if int(package.ranks[id]) == 3: check(package.mutations.get(id,"") in Catalog.MUTATION_BRANCHES.get(id,[]),"Signature mutation uses a legal player branch")
	var game = make_game()
	var b = game.battle
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	var f: Dictionary = b.entity(2)
	check(f.powers.is_empty(),"Opening rival has no hidden power package")
	check(b.powers._modern(f),"Live enemy uses accepted modern power contracts")
	var economy = b.continuous.economy
	var p_before: float = p.rpm
	f.stats = p.stats.duplicate(true); f.handling = p.handling.duplicate(true); f.wobble = p.wobble
	economy.running_costs(p,91.0,Vector2(0.6,0.3),true,1.0,0.5)
	economy.running_costs(f,91.0,Vector2(0.6,0.3),true,1.0,0.5)
	check(is_equal_approx(p.rpm,f.rpm),"Equal actual stats, movement and controls pay exactly equal Run costs")
	var player_ledger: Dictionary = economy.snapshot()
	f.rpm = 0.2
	var gain: float = b.gain_rpm(f,1.0,"dead_centre")
	check(is_equal_approx(gain,economy.TUNING.bucket_capacity),"Enemy earned power recovery obeys the same finite bucket")
	check(is_zero_approx(b.gain_rpm(f,1.0,"dead_centre")),"Repeated same-tick power recovery cannot farm reserve")
	check(economy.snapshot() == player_ledger,"Enemy accounting never contaminates the player ledger")
	economy.begin_tick(1.0,Vector2.ZERO)
	check(is_equal_approx(b.gain_rpm(f,1.0,"impact_sink"),economy.TUNING.bucket_rate),"Enemy power recovery refill uses the player rate")
	f.outcome = "ring_out"
	check(is_zero_approx(b.gain_rpm(f,1.0,"dead_centre")),"Eliminated enemy cannot gain reserve")
	f.outcome = ""
	var event: Dictionary = {"key":"hotwire","role":"hunter","kind":"elite","tier_at_entry":3,"serial":55,"cost":4.5,"name":"HOTWIRE"}
	Packages.apply(f,event)
	f.rpm = 0.7; f.cooldown = 0.0; f.burst_time = 0.0
	var reserve: float = f.rpm
	b._attempt_burst(f,Vector2.LEFT)
	check(b.powers.redline_active(f) and b.powers.active_redline_mutation(f) == "breakneck","An actual enemy Burst arms its legal modern Redline mutation")
	check(is_equal_approx(reserve-f.rpm,0.013+0.045),"Enemy Burst and Redline charge the same player costs")
	check(f.cooldown == b.BURST_COOLDOWN,"Enemy Burst uses the player physical cooldown")
	var capped: float = float(f.rpm)
	b._attempt_burst(f,Vector2.RIGHT)
	check(f.rpm == capped,"Enemy cannot bypass the shared Burst cooldown")
	economy.retire(2)
	check(not economy.enemy_buckets.has(2),"Retirement prunes bounded enemy recovery state")
	check(p.rpm < p_before,"Player costs were actually charged without a test rebate")
	game.free()
	print("ENEMY_POWER_PACKAGES_003A1_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
