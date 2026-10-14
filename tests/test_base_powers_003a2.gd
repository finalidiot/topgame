extends SceneTree
const Base = preload("res://scripts/base_power_runtime.gd")
const Art = preload("res://scripts/base_power_art.gd")
const Catalog = preload("res://scripts/run_powers.gd")
const Context = preload("res://scripts/run_context.gd")
const Parts = preload("res://scripts/parts.gd")
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
var checks: int = 0
var failures: Array[String] = []
var output: String = ""
var observations: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func fighter(ids: Array[String], rank_value: int = 1, owner: int = 1) -> Dictionary:
	var ranks: Dictionary = {}
	for id: String in ids: ranks[id] = rank_value
	return {"entity_id":owner, "owner_id":"qa", "team_id":"player" if owner == 1 else "hostile", "powers":ids.duplicate(), "power_ranks":ranks, "power_mutations":{}, "rpm":0.8, "energy":0.8, "wobble":0.4, "outcome":""}

func fresh_modifiers() -> Dictionary:
	return {"drain":1.0, "recovery":1.0, "speed":1.0}

func make_battle(ids: Array[String], rank_value: int = 1) -> Node2D:
	var b := Battle.new()
	root.add_child(b); b.set_physics_process(false)
	var descriptor: Dictionary = Encounters.for_run_event(1, 421)
	descriptor.starter_id = "custom"
	descriptor.player_power_ids = ids.duplicate()
	descriptor.player_power_ranks = {}
	for id: String in ids: descriptor.player_power_ranks[id] = rank_value
	b.begin_run({"blade":"lopsider", "ratchet":"flywheel", "bit":"needle"}, descriptor, 421)
	b.battle_status = "battle"
	return b

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	if not output.is_absolute_path() or FileAccess.file_exists(output): push_error("Fresh external report required"); quit(2); return
	check(Catalog.ACTIVE_IDS.size() == 22 and Catalog.FAMILY_CAP == 7, "Six additional families preserve seven slots")
	check(Catalog.VERTICAL_IDS.size() == 7 and Catalog.MUTATIONS.size() == 14, "All seven accepted mutation pairs remain live")
	for branch: String in Catalog.Retired.MUTATIONS:
		var metadata: Dictionary = Catalog.get_mutation(branch)
		check(not metadata.active and metadata.archived and not metadata.has("card_texture"), "Retired branch remains descriptive only: " + branch)
		var parent: String = metadata.power_id
		check(Catalog.max_rank(parent) == 2 and Catalog.mutation_choices(parent).is_empty(), "Retired parent terminates at II: " + parent)
		var old: Dictionary = fighter([parent], 3)
		old.power_mutations[parent] = branch
		check(Catalog.normalize_retired_ownership(old).size() == 1 and old.power_ranks[parent] == 2 and old.power_mutations.is_empty(), "Deterministic matching-parent downgrade: " + branch)
		check(Catalog.get_owned_power(parent, 3, branch).rank == 2, "Historical ownership displays parent II without random substitution")
	for id: String in Base.IDS:
		check(Catalog.get_offer(id).rank == 1 and Catalog.get_offer(id, 1).rank == 2 and Catalog.get_offer(id, 2).is_empty(), "Legal I -> II completion: " + id)
		check(Catalog.get_owned_power(id, 2).card_badge == "RANK II" and not Art.art(id + "_ii").is_empty(), "New identity and rank badge: " + id)
		check(Catalog.mutation_choices(id).is_empty(), "No new mutation branches: " + id)
	var runtime := Base.new(); runtime.setup(7341)
	var f: Dictionary = fighter(["crimson_impact", "azure_stability", "emerald_endurance", "true_bearing", "last_stand"], 1)
	check(is_equal_approx(runtime.attack(f), 1.08) and is_equal_approx(runtime.wobble(f), 0.90) and is_equal_approx(runtime.displacement(f), 0.94), "Rank I impact and resistance values")
	for read: int in range(120):
		var m: Dictionary = fresh_modifiers(); runtime.movement(f, m)
		check(is_equal_approx(m.drain, 0.94) and is_equal_approx(m.recovery, 1.16) and f.rpm == 0.8, "Repeated fresh modifier refresh cannot stack or regenerate")
	f.power_ranks = {"crimson_impact":2, "azure_stability":2, "emerald_endurance":2, "true_bearing":2, "last_stand":2}
	var m: Dictionary = fresh_modifiers(); runtime.movement(f, m)
	check(is_equal_approx(runtime.attack(f), 1.14) and is_equal_approx(m.drain, 0.90) and is_equal_approx(m.recovery, 1.28), "Rank II replaces I immediately")
	f.rpm = 0.349
	check(is_equal_approx(runtime.wobble(f), 0.82 * 0.76), "Last Stand multiplies incoming wobble only below threshold")
	f.rpm = 0.35
	check(is_equal_approx(runtime.wobble(f), 0.82), "Threshold is explicit and cannot refill RPM")
	var prism: Dictionary = fighter(["prismatic_current"], 1)
	runtime.register(prism)
	var mirror := Base.new(); mirror.setup(7341)
	var copy: Dictionary = fighter(["prismatic_current"], 1); mirror.register(copy)
	var npc: Dictionary = fighter(["prismatic_current"], 2, 9); runtime.register(npc)
	var expected: int = runtime.emphasis(prism)
	var sequence: Array[int] = [expected]
	for tick: int in range(2400):
		runtime.begin_tick([prism, npc], 1.0 / 60.0); mirror.begin_tick([copy], 1.0 / 60.0)
		check(runtime.emphasis(prism) == mirror.emphasis(copy), "Owner-isolated seeded RNG reproduces without consuming another stream")
		if tick % 480 == 479:
			check(runtime.emphasis(prism) != expected, "Prismatic changes every 8s without immediate repeat")
			expected = runtime.emphasis(prism); sequence.append(expected)
	var saved_state: int = runtime.states[1].rng.state
	for read: int in range(100): runtime.snapshot(prism); runtime.attack(prism); runtime.wobble(prism)
	check(runtime.states[1].rng.state == saved_state and runtime.states[1].changes == 5, "Public/stat reads do not advance randomness or clocks")
	check(runtime.states.size() == 2 and prism.rpm == 0.8 and npc.rpm == 0.8, "Owner state is bounded and NPC never feeds player resource")
	runtime.begin_tick([prism], 1.0 / 60.0)
	check(runtime.states.size() == 1, "Retirement removes owner RNG state")
	runtime.finish([prism, npc])
	check(runtime.states.is_empty() and not prism.has("prismatic_state") and runtime.attack(prism) == 1.0, "Run end clears state and modifiers")
	var before_parts: Dictionary = Parts.derive({"blade":"lopsider", "ratchet":"flywheel", "bit":"needle"})
	var b: Node2D = make_battle(["emerald_endurance", "true_bearing"])
	var player: Dictionary = b.player_entity()
	check(b.entity(2).powers.is_empty(), "Ordinary opening rival does not automatically inherit new powers")
	var reserve: float = player.rpm
	for tick: int in range(240): b.test_step(Battle.FIXED_DT, Vector2.ZERO, false, false)
	check(player.rpm < reserve and b.continuous.economy.snapshot().total_recovered == 0.0, "Efficiency still drains reserve without recovery at rest")
	check(player.stats == before_parts and Parts.derive(player.build) == before_parts, "Runtime modifiers never change assembly ratings")
	b.set_paused(true)
	check(b.acquire_run_power("prismatic_current", 1), "Prismatic acquisition uses production path")
	var public_before: Dictionary = b.powers.public_state(player)
	var rng_before: int = b.powers.base_powers.states[1].rng.state
	for read: int in range(100): b.powers.public_state(player)
	check(b.powers.base_powers.states[1].rng.state == rng_before and b.powers.public_state(player) == public_before, "Paused acquisition initialized once; inspection is pure")
	observations.append({"prismatic_seed":7341, "sequence":sequence, "assembly":player.build, "ratings":before_parts, "economy":b.continuous.economy.snapshot()})
	b.free()
	for azure_rank: int in [1,2]:
		var azure_battle: Node2D = make_battle(["azure_stability"], azure_rank)
		var azure_player: Dictionary = azure_battle.player_entity()
		var velocity_before: Vector2 = azure_player.vel
		azure_battle.apply_power_impulse(azure_player, Vector2(70,0), {"owner_id":"hostile", "owner_entity_id":2, "expires_at":10.0})
		check((Vector2(azure_player.vel)-velocity_before).is_equal_approx(Vector2(70,0)*(0.94 if azure_rank == 1 else 0.89)), "Azure alone resists accepted secondary power shoves through the existing solver boundary")
		azure_battle.free()
	# Natural legal drafts, including rerolls, never strand the choice screen.
	for seed: int in range(30):
		var context := Context.new(); context.start({"blade":"lopsider", "ratchet":"flywheel", "bit":"needle"}, seed)
		check(not context.pending_offer.is_empty(), "Broader pool always offers starting choices")
		for id: String in context.pending_offer: check(id in Catalog.ACTIVE_IDS, "Starting offer is live content")
		if context.can_reroll():
			check(context.reroll_offer(context.pending_draft_id, int(context.reroll_snapshot().revision)), "Reroll remains legal")
			check(not context.pending_offer.is_empty(), "Reroll cannot strand draft")
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures, "observations":observations, "scope":"Production modifier/acquisition seams plus fixed seeded RNG; isolated initial ownership fixtures are disclosed; no physical feel acceptance."}, "\t"))
	print("BASE_POWERS_003A2_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
