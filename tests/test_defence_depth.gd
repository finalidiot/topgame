extends "res://tests/test_powers.gd"
## Actual semantic hooks plus continuous Battle ledger/freeze integration.
const Catalog = preload("res://scripts/run_powers.gd")
const Art = preload("res://scripts/defence_art.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")

func fixture(id: String, level: int = 2, mutation: String = "") -> Dictionary:
	var host: Host = _host([id] if not id.is_empty() else [])
	for f: Dictionary in host.fighters:
		f["mass"] = 2.0
		f["burst_time"] = 0.0
		f["power_ranks"] = {id:level} if int(f.entity_id) == 1 else {}
		f["power_mutations"] = {id:mutation} if int(f.entity_id) == 1 else {}
	return {"host":host,"runtime":_runtime(host),"player":host.entity(1)}

func step(entry: Dictionary, input: Vector2, braking: bool = false, count: int = 1) -> Dictionary:
	var modifiers: Dictionary = {}
	for tick: int in range(count):
		entry.runtime.begin_tick(Battle.FIXED_DT)
		modifiers = entry.runtime.movement_control(entry.player, input, braking, Battle.FIXED_DT)
	return modifiers

func hit(entry: Dictionary, amount: float = 100.0, severity: float = 0.7) -> void:
	var p: Dictionary = entry.player
	p.vel = Vector2(-amount, 0)
	entry.runtime.accepted_contact(p, entry.host.entity(2), severity, Vector2.RIGHT, Vector2(10, 0), Vector2(-amount, 0), Vector2.ZERO, amount, 0.0)

func _run() -> void:
	_catalogue()
	_gyro()
	_sink()
	_exchange()
	_retirement_and_terminal()
	_battle()
	print("DEFENCE_DEPTH_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _catalogue() -> void:
	_check(Catalog.ACTIVE_IDS.size() == 16 and Catalog.investment_capacity() == 39 and Catalog.run_investment_capacity() == 21 and Catalog.FAMILY_CAP == 7, "Three meaningful families add development while keeping seven slots")
	for id: String in ["gyro_lock", "impact_sink", "anchor_exchange"]:
		_check(Catalog.get_offer(id).offer_kind == "acquire" and Catalog.get_offer(id, 1).offer_kind == "tune" and Catalog.get_offer(id, 2).offer_kind == "mutation", id + " real acquisition/tune/mutation progression")
		_check(Catalog.mutation_choices(id).size() == 2 and Catalog.max_rank(id) == 3, id + " two valid specialization decisions")
		_check(Catalog.get_owned_power(id, 3, "bogus").is_empty(), id + " rejects malformed branch ownership")
		for art_id: String in [id, id + "_ii"] + Catalog.mutation_choices(id):
			var art: Dictionary = Art.art(art_id)
			_check(not art.is_empty(), art_id + " saved native art")
			_check(art.card_cell == 64 and art.card_frames == 12 and art.card_durations_ms.size() == 12 and art.icon_frame >= 0, art_id + " authored card timing and independent icon")
			_check(FileAccess.file_exists(art.card_texture) and FileAccess.file_exists(art.icon), art_id + " runtime assets exist")
	for family: String in Art.meta().families:
		for group: String in ["cards", "icons", "fx"]:
			var m: Dictionary = Art.meta().families[family][group]
			_check(m.layers.size() >= 3 and FileAccess.file_exists("res://" + str(m.source)), family + group + " layered editable native master")
			for span: Dictionary in m.tags.values():
				_check(int(span.to) >= int(span.from) and int(span.to) < int(m.frame_count), family + group + " bounded native tags")

func _gyro() -> void:
	var entry: Dictionary = fixture("gyro_lock")
	var p: Dictionary = entry.player
	p.vel = Vector2(65, 0)
	step(entry, Vector2.ZERO, false, 600)
	_check(float(p.gyro_charge) == 0.0 and is_equal_approx(entry.runtime.inverse_mass(p), 0.5), "Zero steering never winds Gyro Lock despite moving")
	step(entry, Vector2.RIGHT * 0.50, false, 120)
	_check(float(p.gyro_charge) > 0.99 and entry.runtime.inverse_mass(p) < 0.12, "Smooth deliberate movement builds real displacement mass")
	_check(float(p.rpm) == 1.0 and float(p.mass) == 2.0 and float(p.radius) == 12.0, "Gyro does not invent reserve or alter original part/body data")
	step(entry, Vector2.LEFT * 0.50)
	_check(float(p.gyro_charge) == 0.0, "Sharp reversal releases the lock immediately")
	step(entry, Vector2.RIGHT, false, 120)
	_check(float(p.gyro_charge) > 0.99, "Keyboard-strength steady steering can earn Gyro Lock")
	step(entry, Vector2.ZERO, false, 60)
	_check(float(p.gyro_charge) == 0.0, "Parking loses active moving defence")
	step(entry, Vector2.RIGHT * 0.5, false, 120)
	entry.runtime.burst_started(p, Vector2.RIGHT, 1.0)
	_check(float(p.gyro_charge) == 0.0, "Accepted Burst clears a Gyro lock and delays reacquisition")
	step(entry, Vector2.RIGHT * 0.50, false, 30)
	_check(float(p.gyro_charge) == 0.0, "Burst lockout prevents instant defence reacquisition")
	var keel: Dictionary = fixture("gyro_lock", 3, "keel")
	keel.player.vel = Vector2(65, 0)
	var m: Dictionary = step(keel, Vector2.RIGHT * 0.5, false, 120)
	_check(keel.runtime.inverse_mass(keel.player) < 0.08 and float(m.speed) < 0.80, "Keel trades mobility for heavier moving footing")
	var flywheel: Dictionary = fixture("gyro_lock", 3, "flywheel")
	flywheel.player.vel = Vector2(240, 0)
	for tick: int in range(240): step(flywheel, Vector2.RIGHT.rotated(float(tick) * Battle.FIXED_DT * 2.0) * 0.5)
	_check(float(flywheel.player.gyro_charge) > 0.99, "Flywheel permits faster controlled curves without static immunity")

func _sink() -> void:
	var entry: Dictionary = fixture("impact_sink", 1)
	var p: Dictionary = entry.player
	p.rpm = 0.45; p.wobble = 0.60
	hit(entry, 50.0)
	_check(float(p.get("sink_charge", 0.0)) == 0.0 and p.vel == Vector2(-50, 0), "Small taps cannot generate stored shock")
	hit(entry)
	_check(is_equal_approx(float(p.sink_charge), 24.0) and is_equal_approx(Vector2(p.vel).x, -76.0), "Sink cushions only a bounded portion of actual incoming recoil")
	_check(float(p.rpm) == 0.45 and float(p.wobble) == 0.60, "Impact storage itself does not heal or erase collision cost")
	hit(entry)
	_check(float(p.sink_charge) == 24.0, "Same-tick contact spam cannot repeatedly absorb")
	for repeat: int in range(4):
		entry.runtime.begin_tick(0.30)
		hit(entry)
	_check(is_equal_approx(float(p.sink_charge), 90.0), "Rank I reservoir fills at exactly finite capacity")
	entry.runtime.begin_tick(0.30)
	hit(entry)
	_check(p.vel == Vector2(-100, 0) and is_equal_approx(float(p.sink_charge), 90.0), "A full sink cannot keep cushioning force")
	var before: float = p.rpm
	step(entry, Vector2.ZERO, true)
	_check(float(p.sink_charge) == 0.0 and p.rpm > before and p.rpm <= before + 0.028001 and p.wobble < 0.60, "A fresh Brake converts accepted stored shock to bounded spin/wobble recovery")
	var after: float = p.rpm
	step(entry, Vector2.ZERO, true, 240)
	_check(p.rpm == after and int(entry.runtime.defence.state(p).vents) == 1, "Held or empty Brake cannot create another recovery")
	entry.runtime.defence.state(p).sink = 90.0
	entry.runtime.begin_tick(11.0)
	_check(float(p.sink_charge) == 0.0 and p.rpm == after, "Ignored stored shock leaks as heat and grants no passive reserve")
	var spring: Dictionary = fixture("impact_sink", 3, "return_spring")
	for id: int in range(3, 23): spring.host.fighters.append(_fighter(id, Vector2(20, id)))
	spring.runtime.defence.state(spring.player).sink = 150.0
	step(spring, Vector2.ZERO, true)
	spring.runtime.flush_contact_powers()
	_check(spring.host.impulses.size() == 6 and float(spring.player.rpm) < 1.0 and float(spring.player.sink_charge) == 0.0, "Return Spring spends its reservoir and spin on six real nearby targets maximum")
	for impulse: Dictionary in spring.host.impulses:
		_check(float(Vector2(impulse.velocity).length()) <= 95.001 and impulse.cause.kind == "return_spring", "Counter pulse uses bounded physical attributed requests")
	var bleed: Dictionary = fixture("impact_sink", 3, "shock_bleed")
	bleed.player.rpm = 0.40; bleed.player.wobble = 0.70
	bleed.runtime.defence.state(bleed.player).sink = 150.0
	step(bleed, Vector2.ZERO, true)
	_check(is_equal_approx(float(bleed.player.rpm), 0.445) and float(bleed.player.wobble) < 0.5, "Shock Bleed specializes the real stored-force recovery")

func _exchange() -> void:
	var entry: Dictionary = fixture("anchor_exchange")
	var p: Dictionary = entry.player
	p.vel = Vector2.ZERO; p.pos = Vector2(130, 0)
	var start: float = p.rpm
	step(entry, Vector2.ZERO, false, 180)
	_check(float(p.exchange_charge) == 0.0 and p.rpm == start, "Merely stopping outside centre does not gain a portable brace")
	var m: Dictionary = step(entry, Vector2.RIGHT * 0.5, true, 60)
	_check(float(p.exchange_charge) > 0.99 and entry.runtime.inverse_mass(p) < 0.05, "Held Brake grants heavy real mass away from the central socket")
	_check(p.rpm < start and float(m.speed) < 0.5 and float(m.acceleration) < 0.3, "Brace pays spin and limits purposeful movement")
	step(entry, Vector2.RIGHT * 0.5, false)
	_check(float(p.exchange_charge) == 0.0 and is_equal_approx(entry.runtime.inverse_mass(p), 0.5), "Release returns normal mass and mobility immediately")
	var deep: Dictionary = fixture("anchor_exchange", 3, "deep_footing")
	step(deep, Vector2.ZERO, true, 60)
	_check(deep.runtime.inverse_mass(deep.player) < 0.025 and deep.player.rpm < p.rpm, "Deep Footing buys extreme stationary bracing with higher reserve cost")
	deep.player.vel = Vector2(50, 0)
	step(deep, Vector2.ZERO, true, 60)
	_check(float(deep.player.exchange_charge) == 0.0, "Deep Footing requires near rest instead of delivering fast heavy movement")
	var slip: Dictionary = fixture("anchor_exchange", 3, "slip_anchor")
	step(slip, Vector2.ZERO, true, 60)
	step(slip, Vector2.RIGHT * 0.5, false)
	_check(float(slip.player.exchange_charge) == 0.0 and slip.runtime.inverse_mass(slip.player) < 0.1, "Slip Anchor carries part of paid footing into actual release")
	step(slip, Vector2.RIGHT * 0.5, false, 43)
	_check(is_equal_approx(slip.runtime.inverse_mass(slip.player), 0.5), "Carried brace expires completely after 0.35 seconds")

func _retirement_and_terminal() -> void:
	var entry: Dictionary = fixture("gyro_lock")
	entry.player.vel = Vector2(60, 0)
	step(entry, Vector2.RIGHT * 0.5, false, 120)
	_check(entry.runtime.defence.states.size() == 1, "Only owners of relevant tools allocate state")
	entry.player.outcome = "ring_out"
	entry.runtime.begin_tick(Battle.FIXED_DT)
	_check(entry.runtime.defence.states.is_empty() and is_equal_approx(entry.runtime.inverse_mass(entry.player), 0.5), "Retired owners cannot retain immunity or leak storage")
	entry.player.outcome = ""; entry.runtime.setup(entry.host)
	_check(entry.runtime.defence.states.is_empty() and float(entry.player.gyro_charge) == 0.0 and float(entry.player.exchange_carry) == 0.0, "Setup resets this launch's defence state and presentation marks")
	entry.runtime.finish()
	step(entry, Vector2.RIGHT * 0.5, true, 120)
	_check(entry.runtime.defence.states.is_empty(), "Finished combat rejects later movement/force state")
	var old: Dictionary = fixture("")
	old.player.vel = Vector2(60, 0)
	var before: Dictionary = old.player.duplicate(true)
	for tick: int in range(300):
		var m: Dictionary = old.runtime.movement_control(old.player, Vector2.RIGHT * 0.5, false, Battle.FIXED_DT)
		_check(float(m.speed) == 1.0 and float(m.acceleration) == 1.0 and float(m.drag) == 0.0 and is_equal_approx(old.runtime.inverse_mass(old.player), 0.5), "Non-owner neutral physics")
	_check(old.player == before and old.runtime.defence.states.is_empty(), "Existing owners receive no defence fields or changed simulation state")

func _battle() -> void:
	var b: Node2D = Battle.new()
	root.add_child(b); b.set_physics_process(false)
	var d: Dictionary = Encounters.for_run_event(1, 421)
	d.player_power_ids = ["impact_sink", "anchor_exchange"]
	d.player_power_ranks = {"impact_sink":3,"anchor_exchange":2}
	d.player_power_mutations = {"impact_sink":"shock_bleed"}
	b.begin_run(Starters.build_for("bastion"), d, 421); b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	p.rpm = 0.50
	b.powers.defence.state(p).sink = 150.0
	b.powers.movement_control(p, Vector2.ZERO, true, Battle.FIXED_DT)
	_check(float(b.continuous.economy.gains.get("impact_sink", 0.0)) > 0.0 and p.rpm <= 0.545001, "Sink recovery passes through production Run accounting and shared gain budget")
	var time: float = b.powers.defence.time
	var state_before: Dictionary = b.powers.defence.states.duplicate(true)
	var ledger: Dictionary = b.continuous.economy.snapshot()
	b.set_paused(true)
	for tick: int in range(120): b.test_step(Battle.FIXED_DT, Vector2.RIGHT, true, true)
	_check(b.powers.defence.time == time and b.powers.defence.states == state_before and b.continuous.economy.snapshot() == ledger, "Pause freezes new tool clocks, state and ledger")
	_check(is_same(p, b.player_entity()), "Defensive choices preserve the same launched top")
	b.free()
