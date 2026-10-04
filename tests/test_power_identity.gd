extends SceneTree
## Active C5 art contracts, native file evidence and actual draw isolation.
## Explicit held visual fixtures are not gameplay or balance evidence.
const I = preload("res://scripts/power_identity.gd")
const C = preload("res://scripts/run_powers.gd")
const Contract = preload("res://tests/power_identity_contract.gd")
const B = preload("res://scripts/battle.gd")
const E = preload("res://scripts/encounters.gd")
const S = preload("res://scripts/starters.gd")
const P = preload("res://scripts/power_visuals.gd")
const Route = preload("res://tests/roster_route_bot.gd")
const Runtime = preload("res://scripts/power_runtime.gd")
const FAMILIES: Array[String] = ["impact_wake", "redline", "iron_comet", "dead_centre", "afterimage", "chain_impact", "clutch", "high_gear", "orbit_drive", "crash_guard", "momentum_bank", "predator_line", "crosscut"]
const HEADINGS: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const DIRECTIONAL: Dictionary = {
	"iron_comet": ["comet_charge", "comet_flight", "comet_impact", "comet_scrape"],
	"high_gear": ["speed", "terminal_velocity", "flow_state"],
	"orbit_drive": ["orbit_drift"],
	"momentum_bank": ["bank_stored", "bank_load", "bank_release"],
	"predator_line": ["predator_pressure", "predator_tracking"],
	"crosscut": ["shear_slice"],
	"crash_guard": ["damper_contact"]
}
var checks: int = 0
var failures: int = 0
var draw_states: int = 0
var paid_preview_draws: int = 0

class DrawBattle extends B:
	var draw_calls: int = 0
	func _draw() -> void:
		draw_calls += 1
		super._draw()

class RequestRecorder extends Runtime:
	var submitted: Array[int] = []
	func _request(target: Dictionary, velocity: Vector2, cause: Dictionary) -> void:
		submitted.append(int(target.entity_id))
		super._request(target, velocity, cause)

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func read_string(bytes: PackedByteArray, at: int) -> Dictionary:
	if at < 0 or at + 2 > bytes.size(): return {}
	var count: int = bytes.decode_u16(at)
	if at + 2 + count > bytes.size(): return {}
	return {"value": bytes.slice(at + 2, at + 2 + count).get_string_from_utf8(), "next": at + 2 + count}

func integer_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values: result.append(int(value))
	return result

func same_tags(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size(): return false
	for tag: String in actual:
		if not expected.has(tag) or int(actual[tag].from) != int(expected[tag].from) or int(actual[tag].to) != int(expected[tag].to): return false
	return true

func native_meta(path: String) -> Dictionary:
	# Read the actual ASE frame/chunk structure, rather than trusting sidecar JSON.
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://" + path)
	if bytes.size() < 128 or bytes.decode_u32(0) != bytes.size() or bytes.decode_u16(4) != 0xA5E0: return {}
	var result: Dictionary = {"cell": [bytes.decode_u16(8), bytes.decode_u16(10)], "depth": bytes.decode_u16(12), "frames": bytes.decode_u16(6), "layers": [], "tags": {}, "durations": [], "pivot": [], "cels": 0, "normal_layers": true}
	var offset: int = 128
	for frame: int in range(int(result.frames)):
		if offset + 16 > bytes.size() or bytes.decode_u16(offset + 4) != 0xF1FA: return {}
		var length: int = bytes.decode_u32(offset)
		if length < 16 or offset + length > bytes.size(): return {}
		result.durations.append(bytes.decode_u16(offset + 8))
		var chunk_count: int = bytes.decode_u32(offset + 12)
		if chunk_count == 0: chunk_count = bytes.decode_u16(offset + 6)
		var at: int = offset + 16
		for chunk: int in range(chunk_count):
			if at + 6 > offset + length: return {}
			var size: int = bytes.decode_u32(at)
			if size < 6 or at + size > offset + length: return {}
			var payload: PackedByteArray = bytes.slice(at + 6, at + size)
			match bytes.decode_u16(at + 4):
				0x2004:
					var name: Dictionary = read_string(payload, 16)
					if name.is_empty(): return {}
					result.layers.append(name.value)
					result.normal_layers = result.normal_layers and payload.decode_u16(2) == 0 and payload.decode_u16(10) == 0 and (payload.decode_u16(0) & 1) != 0
				0x2005:
					if payload.size() < 16: return {}
					result.cels += 1
					if payload.decode_u16(0) >= result.layers.size(): return {}
				0x2018:
					if payload.size() < 10: return {}
					var cursor: int = 10
					for tag: int in range(payload.decode_u16(0)):
						var name: Dictionary = read_string(payload, cursor + 17)
						if name.is_empty() or result.tags.has(name.value) or payload[cursor + 4] != 0: return {}
						result.tags[name.value] = {"from": payload.decode_u16(cursor), "to": payload.decode_u16(cursor + 2)}
						cursor = int(name.next)
				0x2022:
					var name: Dictionary = read_string(payload, 12)
					if name.is_empty(): return {}
					var flags: int = payload.decode_u32(4)
					var pivot_at: int = int(name.next) + 20 + (16 if flags & 1 else 0)
					if name.value == "contact_pivot" and payload.decode_u32(0) > 0 and flags & 2:
						if pivot_at + 8 > payload.size(): return {}
						result.pivot = [payload.decode_s32(pivot_at), payload.decode_s32(pivot_at + 4)]
			at += size
		if at != offset + length: return {}
		offset += length
	return result if offset == bytes.size() else {}

func test_sources(family: String, info: Dictionary) -> void:
	for group: String in ["cards", "icons", "fx"]:
		var exported: Dictionary = info[group]
		var native: Dictionary = native_meta(str(exported.source))
		var label: String = family + "/" + group
		check(not native.is_empty(), label + " is a complete real ASE file")
		if native.is_empty(): continue
		check(native.depth == 32 and integer_array(native.cell) == integer_array(exported.cell) and native.frames == int(exported.frame_count), label + " native RGBA header agrees with export")
		check(native.layers == exported.layers and native.layers.size() >= 2 and native.normal_layers, label + " named visible normal layers survive export")
		check(same_tags(native.tags, exported.tags), label + " real ASE tags agree exactly with manifest")
		check(integer_array(native.pivot) == integer_array(exported.pivot) and integer_array(native.pivot) == integer_array([48, 48] if group == "fx" else ([32, 32] if group == "cards" else [8, 8])), label + " true native contact-pivot slice retained")
		check(integer_array(native.durations) == integer_array(exported.durations_ms) and native.durations.size() == int(native.frames), label + " real frame durations survive export")
		check(native.cels >= native.frames, label + " contains authored native cels")
		var tex: Texture2D = I.texture(str(exported.texture))
		check(tex != null and tex.get_size() == Vector2(int(exported.columns) * int(exported.cell[0]), ceili(float(exported.frame_count) / float(exported.columns)) * int(exported.cell[1])), label + " atlas is exported at native scale")
		for tag: String in exported.tags:
			var span: Dictionary = exported.tags[tag]
			check(int(span.from) >= 0 and int(span.to) < int(exported.frame_count) and int(span.to) - int(span.from) == (11 if group == "cards" else (0 if group == "icons" else 7)), label + ":" + tag + " finite native tag span")
			if group == "fx":
				check(I.frame(family, tag, -2.0) == int(span.from) and I.frame(family, tag, 99.0) == int(span.to), label + ":" + tag + " bounded start and terminal pose")
				var boundary: float = float(exported.durations_ms[int(span.from)]) * 0.001
				check(I.frame(family, tag, boundary * 0.5) == int(span.from) and I.frame(family, tag, boundary + 0.0001) == int(span.from) + 1, label + ":" + tag + " uses authored timing")
				check(I.frame(family, tag, 99.0, true) >= int(span.from) and I.frame(family, tag, 99.0, true) <= int(span.to), label + ":" + tag + " looping remains inside its own tag")
	for key: String in ["silhouette", "motion", "location", "persistence", "palette", "feature"]:
		check(not str(info.grammar.get(key, "")).is_empty(), family + " documented physical grammar: " + key)
	check(FileAccess.file_exists("res://" + str(info.design)), family + " editable design notes supplied")

func test_card(art_id: String) -> void:
	Contract.catalog_art(check, art_id)
	var art: Dictionary = I.art(art_id)
	if art.is_empty(): return
	var info: Dictionary = I.family_info(str(art.family))
	check(info.cards.tags.has(art_id) and info.icons.tags.has(art_id), art_id + " has its own native card and icon tag")
	check(int(info.cards.tags[art_id].from) == int(art.card_row) * 12 and int(info.icons.tags[art_id].from) == int(art.icon_frame), art_id + " mappings address the correct native tag")
	var card_image: Image = I.texture(str(art.card_texture)).get_image()
	var poses: Dictionary = {}
	var times: Dictionary = {}
	for index: int in range(12):
		var region: Image = card_image.get_region(Rect2i(index * 64, int(art.card_row) * 64, 64, 64))
		poses[region.get_data().hex_encode()] = true
		times[int(art.card_durations_ms[index])] = true
		check(int(art.card_durations_ms[index]) >= 25 and int(art.card_durations_ms[index]) <= 250, art_id + " finite authored pose duration " + str(index))
	check(poses.size() >= 4 and times.size() >= 3, art_id + " authored movement and rhythm are not twelve duplicated cels")
	var icon: Image = I.texture(str(art.icon)).get_image().get_region(Rect2i(int(art.icon_frame) * 16, 0, 16, 16))
	check(not icon.is_invisible() and str(info.icons.source) != str(info.cards.source), art_id + " nonempty native icon has its own editable master")

func test_directions(family: String, info: Dictionary) -> void:
	var bases: Dictionary = {}
	for kind: String in info.event_tags:
		check(I.event_family(kind) == family, family + " runtime event resolves " + kind)
		bases[str(info.event_tags[kind])] = true
	for semantic: String in info.active_tags: bases[str(info.active_tags[semantic])] = true
	for base: String in bases:
		for rank: int in [1, 2]:
			for heading_index: int in range(8):
				var angle: float = TAU * heading_index / 8.0
				var screen: Vector2 = Vector2.from_angle(angle)
				var world: Vector2 = Vector2(screen.y + screen.x * 0.5, screen.y - screen.x * 0.5)
				check(I.heading(world) == HEADINGS[heading_index], "World direction projects to authored heading " + HEADINGS[heading_index])
				var variant: String = I.variant(family, base, rank, world)
				if family == "impact_wake" and base == "wake" and rank == 1:
					# The accepted Rank I pressure animation is intentionally retained.
					check(variant.is_empty() and P._meta("effects").tags.has("pressure"), "Wake I explicitly falls back to the retained authored pressure sequence")
				else:
					check(not variant.is_empty() and info.fx.tags.has(variant), family + ":" + base + " supported live rank and heading")
				if base in DIRECTIONAL.get(family, []):
					check(variant.ends_with("_" + HEADINGS[heading_index]), family + ":" + base + " uses the true upright " + HEADINGS[heading_index] + " heading")

func fixture(b: Node2D, family: String, rank: int, branch: String) -> void:
	# These explicit state poses exercise drawing only. Simulation stays disabled.
	var p: Dictionary = b.player_entity()
	p.vel = Vector2(155, -85); p.height = 0.0
	p.anchor_charge = 0.9; p.stored_force = 110.0
	p.redline_time = 0.8; p.redline_active_rank = rank; p.redline_active_mutation = branch
	p.redline_heading = p.vel.normalized(); p.redline_heat = 0.82; p.runaway_heat = 0.82
	p.iron_comet_time = 1.9; p.drift_active = true; p.orbit_charge = 0.8
	p.clutch_active = true; p.clutch_time = 3.0; p.clutch_recovery_time = 0.2
	p.guard_time = 0.9; p.slipstream_time = 0.35
	p.momentum_charge = 85.0; p.hunt_stacks = 3; p.hunt_target = 2
	p.ghost_preview = {"a": Vector2(-25, 0), "b": Vector2(20, 15), "strength": 0.8}
	b.entity(2).pos = Vector2(p.pos) + Vector2(65, -25)
	var info: Dictionary = I.family_info(family)
	for kind: String in info.event_tags:
		var provenance: Dictionary = {"owner_entity_id": int(p.entity_id), "receiver_entity_ids": [2]} if family == "chain_impact" else {}
		b.add_power_fx(kind, p.pos, Vector2(1, -0.5), 1.0, provenance)
		b._power_fx[-1].age = 0.10
		b._power_fx[-1].rank = rank

func sim_state(b: Node2D) -> Dictionary:
	var ai: Dictionary = {}
	for id: Variant in b._ai_rngs: ai[id] = b._ai_rngs[id].state
	return {"battle": b.snapshot(), "core": b.powers._states.duplicate(true), "core_events": b.powers.events.duplicate(true), "core_counters": b.powers.counters.duplicate(true), "roster": b.roster.states.duplicate(true), "roster_counters": b.roster.counters.duplicate(true), "traces": b.powers.traces.duplicate(true), "core_time": b.powers.time, "roster_time": b.roster.time, "director": b.continuous.snapshot(), "economy": b.continuous.economy.snapshot(), "director_rng": b.continuous.director.rng.state, "simulation_rng": b._simulation_rng.state, "cosmetic_rng": b._cosmetic_rng.state, "ai_rngs": ai, "effects": b._power_fx.duplicate(true)}

func test_draw(family: String, rank: int, branch: String = "") -> void:
	var b = DrawBattle.new(); root.add_child(b)
	b.set_physics_process(false); b.set_process(false)
	var descriptor: Dictionary = E.for_run_event(1, 421)
	descriptor.player_power_ids = [family]; descriptor.player_power_ranks = {family: rank}
	descriptor.player_power_mutations = {family: branch} if not branch.is_empty() else {}
	descriptor.ability_rebalance = true
	b.begin_run(S.build_for("vane"), descriptor, 421); b.battle_status = "battle"
	fixture(b, family, rank, branch)
	var before: Dictionary = sim_state(b)
	var draws_before: int = b.draw_calls
	b.queue_redraw(); await process_frame; await process_frame
	check(b.draw_calls > draws_before, "Actual canvas draw executed for " + family + "/" + str(rank) + branch)
	check(before == sim_state(b), "Drawing changes no fighter, timers, power counters, trace, ledger or RNG: " + family + "/" + str(rank) + branch)
	draw_states += 1
	b.free()

func test_modern_activation_alias(rank: int, branch: String, kind: String) -> void:
	# A full-reserve modern fighter earns the effect through an ordinary Burst.
	# Enumerating manifest keys alone cannot detect an emitted alias left unmapped.
	var b = B.new(); root.add_child(b); b.set_physics_process(false); b.set_process(false)
	var descriptor: Dictionary = E.for_run_event(1, 421)
	descriptor.player_power_ids = ["redline"]; descriptor.player_power_ranks = {"redline": rank}
	descriptor.player_power_mutations = {"redline": branch} if not branch.is_empty() else {}
	descriptor.ability_rebalance = true
	b.begin_run(S.build_for("vane"), descriptor, 421); b.battle_status = "battle"
	b.test_step(B.FIXED_DT, Vector2.RIGHT, true, false)
	var emitted: Dictionary = {}
	for effect: Dictionary in b._power_fx:
		if str(effect.kind) == kind: emitted = effect; break
	check(not emitted.is_empty(), "Ordinary modern Burst emits " + kind)
	check(I.event_family(kind) == "redline", "Actual emitted alias " + kind + " resolves to authored Redline art")
	if not emitted.is_empty():
		check(int(emitted.get("rank", -1)) == rank and emitted.get("art_family", "") == "redline", kind + " effect carries correct presentation rank provenance")
		var info: Dictionary = I.family_info("redline")
		var base: String = str(info.event_tags.get(kind, ""))
		check(not base.is_empty() and not I.variant("redline", base, rank, emitted.direction).is_empty(), kind + " actual effect selects a real native tag")
		for art_rank: int in [1, 2, 3]:
			var variant: String = I.variant("redline", base, art_rank, emitted.direction)
			check(info.fx.tags.has(variant) and not variant.contains("_ii_ii"), kind + " alias with developed base resolves without a doubled rank suffix at " + str(art_rank))
	b.free()

func test_paid_preview() -> void:
	var b = DrawBattle.new(); root.add_child(b); b.set_physics_process(false); b.set_process(false)
	var descriptor: Dictionary = E.for_run_event(1, 421)
	descriptor.player_power_ids = ["afterimage"]; descriptor.player_power_ranks = {"afterimage": 3}
	descriptor.player_power_mutations = {"afterimage": "ghost_circuit"}; descriptor.ability_rebalance = true
	b.begin_run(S.build_for("vane"), descriptor, 421); b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	var paid_preview: bool = false
	for tick: int in range(900):
		var before_traces: int = int(b.powers.counters.get("afterimage", 0))
		var controls: Dictionary = Route.input(b, tick, false, 98.0, 155.0)
		b.test_step(B.FIXED_DT, controls.direction, false, false)
		if not Dictionary(p.get("ghost_preview", {})).is_empty() and int(b.powers.counters.get("afterimage", 0)) > before_traces:
			paid_preview = true; break
		if b.battle_status == "finished": break
	check(paid_preview, "Ordinary full-reserve route inputs produce a real Ghost preview on a paid trace emission")
	if not paid_preview:
		b.free(); return
	var preview: Dictionary = p.ghost_preview
	var socket_paid: bool = false
	var end_paid: bool = false
	for trace: Dictionary in b.powers.traces:
		if int(trace.owner_entity_id) != int(p.entity_id): continue
		for point: Vector2 in trace.points:
			if point.is_equal_approx(preview.a): socket_paid = true
			if point.is_equal_approx(preview.b): end_paid = true
	check(socket_paid and end_paid, "Both observed preview sockets belong to the actual paid chronological route")
	var expected: PackedVector2Array = PackedVector2Array([b.project(preview.a), b.project(preview.b)])
	var before: Dictionary = sim_state(b)
	var points: PackedVector2Array = I.ghost_preview_points(p, b.project(p.pos))
	check(points.size() == 2 and points[0].is_equal_approx(expected[0]) and points[1].is_equal_approx(expected[1]), "Native latch positions follow the actual paid world a/b sockets")
	check(before == sim_state(b), "Preview placement changes no route, preview, timer, ledger or RNG")
	var translated: Dictionary = p.duplicate(true)
	translated.pos = Vector2(p.pos) + Vector2(81, -37)
	translated.height = float(p.height) + 17.0
	var translated_before: Dictionary = translated.duplicate(true)
	var moved: PackedVector2Array = I.ghost_preview_points(translated, b.project(translated.pos))
	check(moved.size() == 2 and moved[0].is_equal_approx(expected[0]) and moved[1].is_equal_approx(expected[1]), "Moving the live fighter cannot reanchor paid endpoints to a new local origin")
	check(translated == translated_before, "Translated preview placement is read only")
	check(I.ghost_preview_points({"pos": Vector2(50, 80)}, Vector2(20, 30)).is_empty(), "Missing paid sockets cannot fabricate a preview")
	check(I.has_active("afterimage", "ghost_preview") and not I.variant("afterimage", str(I.family_info("afterimage").active_tags.ghost_preview), 1, Vector2(preview.b) - Vector2(preview.a)).is_empty(), "Real paid preview resolves the new authored latch-endpoint tag")
	var draws_before: int = b.draw_calls
	b.queue_redraw(); await process_frame; await process_frame
	check(b.draw_calls > draws_before and before == sim_state(b), "Actual native preview draw preserves the paid route and every gameplay/random field")
	paid_preview_draws += 1
	b.free()

func chain_battle() -> Node2D:
	# Explicit semantic contact fixtures; no capture or natural-play claim.
	var b = B.new(); root.add_child(b); b.set_physics_process(false); b.set_process(false)
	var descriptor: Dictionary = E.for_run_event(1, 421)
	descriptor.player_power_ids = ["chain_impact"]; descriptor.player_power_ranks = {"chain_impact": 2}
	descriptor.ability_rebalance = true
	b.begin_run(S.build_for("breaker"), descriptor, 421); b.battle_status = "battle"
	b.test_set_entity_state(1, {"pos": Vector2.ZERO, "vel": Vector2.ZERO})
	b.test_set_entity_state(2, {"pos": Vector2(30, 0), "vel": Vector2.ZERO})
	for id: int in [3, 4, 5, 6, 7, 8, 9]:
		var positions: Dictionary = {3: Vector2(10, 25), 4: Vector2(-20, 10), 5: Vector2(30, -25), 6: Vector2.ZERO, 7: Vector2(5, 15), 8: Vector2(-10, 5), 9: Vector2(75, 0)}
		check(b.add_full_top(S.build_for("breaker"), id, "player" if id == 7 else ("neutral" if id == 8 else "hostile"), "semantic_%d" % id, positions[id]), "Chain provenance fixture admits entity " + str(id))
	b.entity(3).combatant_type = "small_top"
	b.entity(6).combatant_type = "small_top"
	# A nearby other owner must not steal the actual emitter's Rank II art.
	b.entity(7).powers = ["chain_impact"]; b.entity(7).power_ranks = {"chain_impact": 1}
	var recording = RequestRecorder.new(); recording.setup(b); b.powers = recording
	return b

func last_chain_fx(b: Node2D) -> Dictionary:
	for index: int in range(b._power_fx.size() - 1, -1, -1):
		if b._power_fx[index].kind == "chain_impact": return b._power_fx[index]
	return {}

func test_chain_provenance() -> void:
	var burst = chain_battle()
	var owner: Dictionary = burst.player_entity()
	var target: Dictionary = burst.entity(2)
	burst.powers.accepted_contact(owner, target, 0.7, Vector2.RIGHT, Vector2(15, 0), Vector2(-100, 0), Vector2(100, 0))
	check(int(burst.powers._state(owner).chain_target) == 2, "Meaningful contact primes its real single full-top Chain target")
	burst.powers.submitted.clear()
	burst._attempt_burst(owner, Vector2.RIGHT)
	var burst_fx: Dictionary = last_chain_fx(burst)
	check(burst.powers.submitted == [2], "Actual primed Burst submits only its stored target despite nearby rivals")
	check(not burst_fx.is_empty() and burst_fx.get("receiver_entity_ids", []) == [2], "Burst artwork links only the actual submitted target")
	check(int(burst_fx.get("owner_entity_id", 0)) == 1 and int(burst_fx.get("rank", 0)) == 2, "Burst art provenance uses its real Rank II owner rather than a nearby Rank I holder")
	check(burst_fx.get("receivers", []) == [Vector2(target.pos)], "Burst recipient position is an immutable contact-time snapshot")
	burst.powers.flush_contact_powers()
	check(Vector2(target.vel).length() > 0.0 and Vector2(burst.entity(3).vel) == Vector2.ZERO and Vector2(burst.entity(4).vel) == Vector2.ZERO, "Receiver metadata cannot add impulses to nearby unhit bodies")
	burst.free()
	var pulse = chain_battle()
	var p: Dictionary = pulse.player_entity()
	p.pos = Vector2(80, 20)
	var source: Dictionary = pulse.entity(6)
	var cause: Dictionary = pulse.powers._owned_effect_cause(p, "contact")
	pulse.powers._tag(source, cause); source.outcome = "impact"
	pulse.powers.eliminated(source, "impact"); pulse.powers.end_tick(false)
	pulse.powers.begin_tick(B.FIXED_DT)
	var pulse_fx: Dictionary = last_chain_fx(pulse)
	check(pulse.powers.submitted == [2, 3, 4, 5], "Actual elimination pulse submits all live hostile full/small recipients and excludes ally/neutral/retired/far bodies")
	check(not pulse_fx.is_empty() and pulse_fx.get("receiver_entity_ids", []) == [2, 3, 4], "Pulse artwork shows a bounded subset of its actual requested recipients")
	check(int(pulse_fx.get("owner_entity_id", 0)) == 1 and int(pulse_fx.get("rank", 0)) == 2, "Pulse retains actual emitter provenance even away from its elimination origin")
	var positions: Array[Vector2] = [Vector2(pulse.entity(2).pos), Vector2(pulse.entity(3).pos), Vector2(pulse.entity(4).pos)]
	check(pulse_fx.get("receivers", []) == positions, "Bounded pulse links snapshot the same actual recipients")
	var old_position: Vector2 = pulse.entity(2).pos
	pulse.entity(2).pos = old_position + Vector2(50, 20)
	check(pulse_fx.get("receivers", []) == positions, "Later target movement cannot rewrite a finished pulse's visual snapshot")
	pulse.entity(2).pos = old_position
	pulse.powers.flush_contact_powers()
	check(Vector2(pulse.entity(5).vel).length() > 0.0 and Vector2(pulse.entity(7).vel) == Vector2.ZERO and Vector2(pulse.entity(8).vel) == Vector2.ZERO, "Three-link display cap preserves every real pulse impulse and opposition rule")
	pulse._power_fx.clear(); pulse.add_power_fx("chain_impact", Vector2.ZERO)
	check(last_chain_fx(pulse).get("receivers", []).is_empty(), "Legacy four-argument FX calls never fabricate nearby Chain recipients")
	pulse.free()

func test_guard_contact_direction() -> void:
	for index: int in range(8):
		var angle: float = TAU * index / 8.0
		var screen_direction: Vector2 = Vector2.from_angle(angle)
		var toward_rival: Vector2 = Vector2(screen_direction.y + screen_direction.x * 0.5, screen_direction.y - screen_direction.x * 0.5).normalized()
		var b = B.new(); root.add_child(b); b.set_physics_process(false); b.set_process(false)
		var descriptor: Dictionary = E.for_run_event(1, 421)
		descriptor.player_power_ids = ["crash_guard"]; descriptor.player_power_ranks = {"crash_guard": 2}; descriptor.ability_rebalance = true
		b.begin_run(S.build_for("bastion"), descriptor, 421); b.battle_status = "battle"
		b.test_set_entity_state(1, {"pos": Vector2.ZERO, "vel": toward_rival * 120.0})
		b.test_set_entity_state(2, {"pos": toward_rival * 20.0, "vel": -toward_rival * 60.0})
		b.resolve_pair(1, 2)
		var effect: Dictionary = {}
		for candidate: Dictionary in b._power_fx:
			if candidate.kind == "crash_guard": effect = candidate; break
		check(not effect.is_empty(), "Actual meaningful contact emits Guard at projected heading " + HEADINGS[index])
		if not effect.is_empty():
			var before: Dictionary = sim_state(b)
			var force: Vector2 = effect.direction
			var face: Vector2 = I.contact_art_direction("crash_guard", force)
			check(force.dot(toward_rival) < -0.99 and face.dot(toward_rival) > 0.99, "Guard's emitted incoming force places its damper on the actual rival side " + HEADINGS[index])
			var tag: String = I.variant("crash_guard", "damper_contact", int(effect.rank), face)
			check(tag == "damper_contact_ii_" + HEADINGS[index], "Actual Guard contact selects correct upright native heading " + HEADINGS[index])
			check(I.contact_art_direction("crosscut", force) == force and I.contact_art_direction("momentum_release", force) == force, "Shear/release art keeps its emitted force direction")
			check(before == sim_state(b), "Contact art direction and native tag selection never mutate gameplay")
		b.free()

func run() -> void:
	check(I.meta().families.size() == 13 and I.meta().art.size() == 34, "All thirteen families and thirty-four developed states have active identity assets")
	var retained: Dictionary = native_meta("assets/source-art/power_fx_002b.aseprite")
	var retained_meta: Dictionary = P._meta("effects")
	check(not retained.is_empty() and retained.depth == 32 and retained.tags.has("pressure"), "Retained Wake I is backed by the real native pressure source")
	check(same_tags(retained.tags, retained_meta.tags) and integer_array(retained.pivot) == [64, 64], "Retained Wake I source tags and contact pivot remain intact")
	check(int(retained.tags.pressure.to) - int(retained.tags.pressure.from) == 7 and P._frame("effects", "pressure", 0.0) == int(retained.tags.pressure.from) and P._frame("effects", "pressure", 99.0) == int(retained.tags.pressure.to), "Retained Wake I has eight finite authored pressure poses")
	var expected: Array[String] = []
	for family: String in FAMILIES:
		expected.append(family); expected.append(family + "_ii")
		for branch: String in C.MUTATION_BRANCHES.get(family, []): expected.append(branch)
	check(expected.size() == 34 and not I.art("second_wind").size(), "Complete current roster owns new art while Second Wind is explicitly historical")
	check(not I.has_active("crash_guard", "guarded") and I.family_info("crash_guard").event_tags.get("crash_guard", "") == "damper_contact", "Crash Guard art is a contact response without a persistent orbiting shield")
	for family: String in FAMILIES:
		var info: Dictionary = I.family_info(family)
		check(not info.is_empty(), family + " active family manifest")
		if info.is_empty(): continue
		test_sources(family, info)
		test_directions(family, info)
	for art_id: String in expected: test_card(art_id)
	test_modern_activation_alias(2, "", "redline_ii")
	test_modern_activation_alias(3, "runaway", "runaway")
	await test_paid_preview()
	test_chain_provenance()
	test_guard_contact_direction()
	# Each state is drawn with the real battle renderer and native imports.
	for family: String in FAMILIES:
		await test_draw(family, 1); await test_draw(family, 2)
		for branch: String in C.MUTATION_BRANCHES.get(family, []): await test_draw(family, 3, branch)
	check(draw_states == 34, "Every card state reached an actual draw-isolation fixture")
	check(paid_preview_draws == 1, "Production-paid Ghost endpoints reached an actual native preview draw")
	print("POWER_IDENTITY_TEST_%s checks=%d failures=%d states=34 draw_states=%d paid_preview_draws=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures, draw_states, paid_preview_draws])
	quit(1 if failures else 0)
