extends SceneTree
## Live parity uses legal initial loadouts/countdown and ordinary input. The
## explicit impact/timeline fixtures test presentation contracts, never balance
## acceptance or footage. Natural rarity is measured by observe_beast_impacts.
const Battle = preload("res://scripts/battle.gd")
const Beasts = preload("res://scripts/beast_manifestations.gd")
const Review = preload("res://tests/capture_beast_manifestations.gd")
const Parts = preload("res://scripts/parts.gd")
const Collection = preload("res://scripts/collection_save.gd")
var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func prepare(s: Dictionary, enabled: bool = true) -> Node2D:
	var b: Node2D = Battle.new()
	root.add_child(b); b.set_physics_process(false); b.set_process(false)
	b.beast_manifestations_enabled = enabled
	b.begin_run(s.build, Review.descriptor(s), int(s.seed))
	for tick: int in range(300):
		if b.battle_status == "battle": break
		b.test_step(Battle.FIXED_DT)
	check(b.battle_status == "battle", "Legal loadout passes ordinary countdown")
	return b

func rng_state(b: Node2D) -> Dictionary:
	var ai: Dictionary = {}
	for key: Variant in b._ai_rngs: ai[key] = str(b._ai_rngs[key].state)
	return {"simulation":str(b._simulation_rng.state), "cosmetic":str(b._cosmetic_rng.state), "ai":ai, "director":str(b.continuous.director.rng.state)}

static func impact(id: int = 1, score: float = Beasts.EXTREME_IMPACT_SCORE + 1.0, first: int = 1, second: int = 2) -> Dictionary:
	return {"collision_id":id, "first_entity_id":first, "second_entity_id":second,
		"impulse":score / 300.0, "closing":300.0, "severity":1.30,
		"first_normal_speed":0.0, "second_normal_speed":300.0,
		"first_effective_mass":10.0, "second_effective_mass":10.0,
		"first_velocity":Vector2.RIGHT * 80.0, "second_velocity":Vector2.LEFT * 300.0,
		"normal":Vector2.RIGHT, "position":Vector2(12.0,18.0)}

func actual_cases() -> void:
	var ownership = Collection.new(OS.get_temp_dir().path_join("beasts_unopened_collection.json"))
	var ownership_before: Dictionary = ownership.snapshot()
	for s: Dictionary in Review.SCENARIOS:
		check(Parts.validate_build(s.build) == s.build, "Review loadout is catalogue-valid")
		var shown: Node2D = prepare(s, true)
		var hidden: Node2D = prepare(s, false)
		var contacts: Dictionary = {}
		shown.full_top_impact_accepted.connect(func(event: Dictionary) -> void: contacts[int(event.collision_id)] = event.duplicate(true))
		var peak: int = 0
		for tick: int in range(roundi(float(s.seconds) * 60.0)):
			var c: Dictionary = Review.controls(shown, str(s.policy), tick)
			shown.test_step(Battle.FIXED_DT, c.direction, c.burst, c.brake)
			hidden.test_step(Battle.FIXED_DT, c.direction, c.burst, c.brake)
			check(shown.snapshot() == hidden.snapshot(), "Beasts preserve exact positions, velocity, RPM, wobble, hits and outcomes")
			check(shown.continuous.snapshot() == hidden.continuous.snapshot() and shown.continuous.economy.snapshot() == hidden.continuous.economy.snapshot(), "Beasts preserve director census and RPM ledger")
			check(shown.continuous.director.history == hidden.continuous.director.history and rng_state(shown) == rng_state(hidden), "Beasts consume no simulation, AI, director or cosmetic random stream")
			check(shown.powers.events == hidden.powers.events, "Small power events retain exact provenance")
			var snap: Dictionary = shown.beast_presentation_snapshot()
			check(int(snap.count) <= 1 and int(snap.peak_live) <= 1 and hidden.beast_presentation_snapshot().count == 0, "One giant live; disabled presentation remains empty")
			peak = maxi(peak, int(snap.count))
			for item: Dictionary in snap.active:
				check(contacts.has(int(item.collision_id)) and Beasts.qualifies_impact(contacts[int(item.collision_id)]), "Every live performance traces to one actual qualifying physical collision")
				check(item.trigger == "extreme_impact" and item.beast == Beasts.beast_for_blade(str(shown.entity(int(item.owner_entity_id)).build.blade)), "Correct owner's equipped Blade selects beast")
				check(float(item.age) < Beasts.MAX_INSTANCE_SECONDS and Vector2(item.world_pos).is_finite(), "Presentation position/lifetime remains finite")
				var geometry: Dictionary = shown.beasts.draw_geometry_for(item)
				var expected: Vector2 = shown.project(Vector2(shown.entity(int(item.owner_entity_id)).pos), float(shown.entity(int(item.owner_entity_id)).height)) if item.follow_owner else shown.project(Vector2(item.world_pos))
				check(Vector2(geometry.projected_point).distance_to(expected) < 0.000001, "Performance follows actual rig or accepted contact")
				var rect: Rect2 = geometry.rect
				check(absf(rect.position.x + 64.0 - expected.x) <= 0.501 and absf(rect.position.y + 96.0 + float(geometry.lift) - expected.y) <= 0.501, "Native mirrored/unmirrored pivot stays attached")
		measurements[str(s.identity)] = {"actual_contacts":contacts.size(), "peak_live":peak, "snapshot":Review.portable(shown.beast_presentation_snapshot()), "actual_power_events":Review.portable(shown.powers.events)}
		shown.begin_run(s.build, Review.descriptor(s), int(s.seed))
		check(shown.beast_presentation_snapshot().count == 0 and shown.beast_presentation_snapshot().spawned == 0, "New Run clears collision identities, cooldowns and performance")
		shown.free(); hidden.free()
	check(ownership.snapshot() == ownership_before and ownership.owned_count() == 0, "Presentation cases never grant collection parts")

func director_parity() -> void:
	var s: Dictionary = Review.SCENARIOS[1].duplicate(true); s.seed = 7331
	var shown: Node2D = prepare(s, true)
	var hidden: Node2D = prepare(s, false)
	for tick: int in range(2400):
		var c: Dictionary = Review.controls(shown, "defensive", tick)
		shown.test_step(Battle.FIXED_DT, c.direction, c.burst, c.brake)
		hidden.test_step(Battle.FIXED_DT, c.direction, c.burst, c.brake)
		check(shown.snapshot() == hidden.snapshot() and shown.continuous.economy.snapshot() == hidden.continuous.economy.snapshot(), "Long seeded Run retains exact combat/reserve")
		check(shown.continuous.director.history == hidden.continuous.director.history and rng_state(shown) == rng_state(hidden), "Long Run preserves actual admission decisions and RNG")
	check(shown.elapsed > 18.0 and not shown.continuous.director.history.is_empty(), "Parity includes actual later threat admission")
	measurements.director_parity = {"seconds":shown.elapsed, "history":shown.continuous.director.history.duplicate(true)}
	shown.free(); hidden.free()

func qualification_fixtures() -> void:
	check(is_finite(Beasts.EXTREME_IMPACT_SCORE) and Beasts.EXTREME_IMPACT_SCORE > 0.0, "Production fixed threshold is configured from study")
	check(not Beasts.qualifies_impact(impact(1, Beasts.EXTREME_IMPACT_SCORE - 0.001)), "Just below physical threshold cannot qualify")
	check(Beasts.qualifies_impact(impact(1, Beasts.EXTREME_IMPACT_SCORE + 0.001)), "Just above physical threshold qualifies")
	check(Beasts.qualifies_impact(impact(1, Beasts.EXTREME_IMPACT_SCORE)), "Exact threshold uses inclusive deterministic comparison")
	check(not Beasts.qualifies_impact(impact(1, 1.0)), "Routine contact never qualifies")
	for value: float in [NAN, INF, -1.0]: check(not Beasts.qualifies_impact(impact(1, value)), "Invalid/negative metric cannot qualify")
	var invalid: Dictionary = impact(); invalid.closing = 0.0
	check(not Beasts.qualifies_impact(invalid), "No closing physical contact cannot qualify")
	var b: Node2D = prepare(Review.SCENARIOS[0])
	var before: Dictionary = b.snapshot()
	var random_before: Dictionary = rng_state(b)
	for event: String in ["comet_charge", "comet_release", "breakneck_charge", "breakneck_impact", "breakneck_recovery", "impact_wake", "anchor_mature", "redline", "anchor"]:
		b.beasts.accept_event(event, Vector2.ZERO, Vector2.RIGHT, 3.0, {"owner_entity_id":1, "beast_trigger":true})
	check(b.beast_presentation_snapshot().spawned == 0, "Power activation, charge, preparation, semantic impact and recovery alone never manifest")
	b.player_entity().powers = ["dead_centre"]
	b.player_entity().anchor_hold_seconds = 9.0; b.player_entity().anchor_central_hold = true
	b.beasts.update(0.2)
	check(b.beast_presentation_snapshot().spawned == 0, "Mature six-second Dead Centre alone never manifests")
	b.beasts.reset()
	var below: Dictionary = impact(1, Beasts.EXTREME_IMPACT_SCORE - 0.001)
	check(not b.beasts.accept_impact(below) and b.beast_presentation_snapshot().count == 0, "Below-threshold accepted physical event allocates no beast")
	check(b.beasts.accept_impact(impact(2)), "Qualifying event manifests without requiring any offensive power")
	var item: Dictionary = b.beast_presentation_snapshot().active[0]
	check(item.owner_entity_id == 1 and item.collision_id == 2 and item.beast == "black_arrow", "Defensive absorption preserves player's actual Blade identity")
	var instance: int = int(item.instance_id)
	check(not b.beasts.accept_impact(impact(2)) and b.beast_presentation_snapshot().duplicates == 1, "One collision identity never spawns twice")
	check(not b.beasts.accept_impact(impact(3)) and b.beast_presentation_snapshot().active[0].instance_id == instance, "Another huge hit cannot retrigger/restart an in-progress authored movement")
	b.beasts.update(1.35)
	check(b.beast_presentation_snapshot().count == 0, "Full authored performance resolves at 1.35 seconds")
	check(not b.beasts.accept_impact(impact(4)), "Owner cooldown is secondary after completion")
	check(rng_state(b) == random_before, "Controller qualification, timeline and owner cooldown draw no RNG")
	for id: int in [3,4]: check(b.add_full_top({"blade":"hammerfall","ratchet":"mid","bit":"ball"}, id, "hostile", "beast_fixture_%d" % id, Vector2(30.0 * id, 0.0)), "Budget fixture has valid full-top owners")
	var fixture_random_before: Dictionary = rng_state(b)
	check(not b.beasts.accept_impact(impact(5, Beasts.EXTREME_IMPACT_SCORE + 1.0, 3, 4)), "Global theatre protection prevents immediately sequential owners")
	b.beasts.update(0.25)
	var third: Dictionary = impact(6, Beasts.EXTREME_IMPACT_SCORE + 1.0, 3, 4)
	third.first_normal_speed = 400.0
	check(b.beasts.accept_impact(third) and b.beast_presentation_snapshot().active[0].owner_entity_id == 3, "NPC-only collision chooses dominant incoming momentum")
	b.beasts.update(2.4)
	check(b.beasts.accept_impact(impact(7)), "Owner cooldown rearms on deterministic elapsed time")
	for id: int in range(8, 130): b.beasts.accept_impact(impact(id))
	check(b.beast_presentation_snapshot().events.size() <= Beasts.MAX_HISTORY and b.beast_presentation_snapshot().dedup_entries <= Beasts.MAX_HISTORY, "Diagnostics and deduplication memory remain bounded")
	check(not b.beasts.accept_impact(impact(2)), "Old collision cannot retrigger even after bounded dedup entry eviction")
	check(b.beast_presentation_snapshot().peak_live == 1, "No path overlaps giant silhouettes")
	check(rng_state(b) == fixture_random_before, "Qualification/cooldown/dedup draw no RNG after declared owner fixtures")
	# The above explicit fighter setup changes are test fixture-only; controller
	# calls leave all fighter dictionaries unchanged after those fixture writes.
	var frozen: Dictionary = b.snapshot()
	b.beasts.update(0.01)
	check(b.snapshot() == frozen, "Timeline/controller never writes fighter state")
	b.beasts.reset(); b.free()

func physical_power_collision_fixtures() -> void:
	# The canonical solver executes against explicit legal collision setups, with
	# legal max-speed participants. These are regressions, not natural frequency.
	for identity: int in [0, 1, 2, 3]:
		var s: Dictionary = Review.SCENARIOS[identity].duplicate(true)
		var b: Node2D = prepare(s)
		var p: Dictionary = b.player_entity(); var foe: Dictionary = b.entity(2)
		p.pos = Vector2(-5.0,0.0); foe.pos = Vector2(5.0,0.0)
		p.vel = Vector2.RIGHT * 520.0; foe.vel = Vector2.LEFT * 520.0
		if identity == 0:
			b.powers.wall_rebound(p, 150.0, Vector2.LEFT, p.pos)
			check(b.beast_presentation_snapshot().spawned == 0, "Actual Iron Comet wall charge retains small VFX without full spirit")
		if identity == 2:
			p.anchor_hold_seconds = 8.0; p.anchor_central_hold = true; p.anchor_charge = 1.0
		if identity == 3:
			p.redline_commit_time = 0.3; p.redline_time = 1.0; p.redline_active_mutation = "breakneck"
			var state: Dictionary = b.powers._state(p)
			state.redline_until = b.powers.time + 1.0; state.redline_commit_until = b.powers.time + 0.3
			state.motion_speed = 520.0; state.motion_input = 1.0; state.motion_braking = false
			state.redline_heading = Vector2.RIGHT; state.redline_hit = false
		var received: Array[Dictionary] = []
		b.full_top_impact_accepted.connect(func(event: Dictionary) -> void: received.append(event.duplicate(true)))
		b.resolve_pair(1,2)
		check(received.size() == 1 and b.hits > 0, "Actual canonical full-top solver accepts one huge collision")
		if not received.is_empty():
			check(Beasts.qualifies_impact(received[0]) and b.beast_presentation_snapshot().spawned == 1, "Actual qualifying Comet, Impact Wake, defensive brace or Breakneck hit can manifest")
			if identity in [0,3]:
				var expected_event: String = "comet_release" if identity == 0 else "breakneck_impact"
				var found: bool = false
				for power_event: Dictionary in b.powers.events:
					if str(power_event.kind) == expected_event and int(power_event.owner) == 1: found = true
				check(found, "Physical regression executes the actual Comet release or Breakneck impact power hook")
			check(b.beast_presentation_snapshot().active[0].beast == s.identity, "Actual physical collision retains all four Blade/beast identities")
			measurements["physical_fixture_" + str(s.identity)] = Review.portable(received[0])
		b.free()

func solver_score_at(speed: float) -> Dictionary:
	var b: Node2D = prepare(Review.SCENARIOS[0])
	var p: Dictionary = b.player_entity(); var foe: Dictionary = b.entity(2)
	p.pos = Vector2(-5.0,0.0); foe.pos = Vector2(5.0,0.0)
	p.vel = Vector2.RIGHT * speed; foe.vel = Vector2.LEFT * speed
	var received: Array[Dictionary] = []
	b.full_top_impact_accepted.connect(func(event: Dictionary) -> void: received.append(event.duplicate(true)))
	b.resolve_pair(1,2)
	var result: Dictionary = {"score":0.0,"spawned":int(b.beast_presentation_snapshot().spawned),"event":{}}
	if not received.is_empty(): result.score = Beasts.impact_metric(received[0]); result.event = received[0]
	b.free()
	return result

func canonical_threshold_boundaries() -> void:
	# Locate speeds against the actual solver instead of duplicating its mass,
	# component or impulse equations in the assertion. Both participants remain
	# within the legal 520 speed clamp throughout this explicit fixture.
	for ratio: float in [0.99,1.01]:
		var target: float = Beasts.EXTREME_IMPACT_SCORE * ratio
		var lower: float = 0.0; var upper: float = 520.0
		check(float(solver_score_at(upper).score) > target, "Legal max-speed actual collision bounds extreme threshold")
		for iteration: int in range(23):
			var middle: float = (lower + upper) * 0.5
			if float(solver_score_at(middle).score) < target: lower = middle
			else: upper = middle
		var result: Dictionary = solver_score_at((lower + upper) * 0.5)
		check(absf(float(result.score) - target) < Beasts.EXTREME_IMPACT_SCORE * 0.00005, "Actual canonical solver fixture reaches requested 0.99/1.01 boundary")
		check(int(result.spawned) == (1 if ratio > 1.0 else 0), "Actual just-below/above threshold collision produces correct presentation")
		measurements["solver_boundary_" + str(ratio)] = Review.portable(result)
	var slow: Dictionary = impact()
	slow.impulse = 100000.0; slow.closing = 0.01
	check(not Beasts.qualifies_impact(slow), "Huge braced impulse at tiny closing speed remains ordinary pressing contact")
	slow.closing = 0.0
	check(Beasts.impact_metric(slow) == 0.0 and not Beasts.qualifies_impact(slow), "Motionless massive press has zero work proxy and cannot manifest")

func catalogue_and_assets() -> void:
	check(Parts.BLADE_IDS.size() + Parts.RATCHET_IDS.size() + Parts.BIT_IDS.size() == 31, "Beasts preserve 31-part catalogue")
	for blade: String in Parts.BLADE_IDS: check(not Beasts.beast_for_blade(blade).is_empty(), "Every existing Blade retains an authored beast")
	check(Beasts.beast_for_blade("not_a_blade") == "", "Unknown Blade cannot invent identity")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Beasts.MANIFEST_PATH))
	check(parsed is Dictionary and parsed.get("effects", {}).size() == 4, "Exactly four native identities")
	if not parsed is Dictionary: return
	var controller = Beasts.new()
	for identity: String in ["black_arrow", "iron_bull", "stone_tortoise", "coil_dragon"]:
		var meta: Dictionary = parsed.effects[identity]
		check(meta.cell.size() == 2 and int(meta.cell[0]) == 128 and int(meta.cell[1]) == 128 and meta.pivot.size() == 2 and int(meta.pivot[0]) == 64 and int(meta.pivot[1]) == 96 and int(meta.frame_count) == 20, "Native cells, pivots and 20 authored frames preserved")
		check(meta.layers.size() == 4 and meta.tags.size() == 5, "Layer/tag structure remains editable")
		check(bool(meta.get("native_runtime_rgba_exact", false)), "Native/runtime RGBA parity metadata remains exact")
		check(bool(meta.get("colour_authored_in_native_layers", false)) and not bool(meta.get("runtime_colour_tint", true)), "Spirit colour is authored in editable native layers with no flat runtime tint")
		check(str(meta.get("colour_identity", "")).length() > 0 and meta.get("native_palette", {}).size() == 6, "Each spirit declares distinct native colour and six preserved depth swatches")
		check(str(meta.get("native_alpha_sha256", "")).length() == 64 and str(meta.get("native_shape_sha256", "")).length() == 64, "Colour export records alpha/shape preservation hashes")
		var body: Color = Color(str(meta.get("native_palette", {}).get("body", "#000000")))
		match identity:
			"black_arrow": check(maxf(body.r,maxf(body.g,body.b)) < 0.40 and absf(body.r-body.b) < 0.1, "Black Arrow remains smoky translucent charcoal")
			"iron_bull": check(body.r > body.g * 1.4 and body.r > body.b * 1.4, "Iron Bull retains restrained heated iron/rust red")
			"stone_tortoise": check(body.g > body.r * 1.4 and body.g > body.b * 1.4, "Stone Tortoise is unmistakably earthy green")
			"coil_dragon": check(body.b > body.r * 1.4 and body.g > body.r * 1.4, "Coil Dragon retains spectral blue/cyan")
		for phase: String in ["prepare", "travel", "strike", "recovery", "guard"]:
			var tag: Dictionary = meta.tags[phase]
			check(int(tag.to) - int(tag.from) == 3, "Each authored phase retains four keys")
			var total: float = 0.0
			for frame: int in range(int(tag.from), int(tag.to) + 1):
				check(float(meta.durations_ms[frame]) > 0.0, "Authored millisecond timings are positive")
				total += float(meta.durations_ms[frame]) / 1000.0
			check(controller.frame_for(identity, phase, 0.0) == int(tag.from) and controller.frame_for(identity, phase, total + 0.001) == int(tag.to), "Frame sampling respects native timing endpoints")

func run() -> void:
	catalogue_and_assets()
	qualification_fixtures()
	physical_power_collision_fixtures()
	canonical_threshold_boundaries()
	actual_cases()
	director_parity()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			assert(file != null)
			file.store_string(JSON.stringify({"checks":checks, "failures":failures, "measurements":Review.portable(measurements), "fixture_policy":"Natural live parity uses legal initial equipment/powers and ordinary countdown/controls. Threshold/controller/canonical-collision boundary cases are explicitly labelled fixtures, never natural frequency or human review footage."}, "\t")); file.close()
	print("BEAST_MANIFESTATIONS_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
