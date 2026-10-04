extends Node2D
class_name PrototypeBattle

## Contact coordinates live in world u/v. The fixed raster camera is only
## a projection; it never rotates either the arena or an assembled sprite.
signal round_finished(result: Dictionary)
signal hud_updated(stats: Dictionary)
signal event_sfx(kind: String)
signal contact_accepted(first_entity_id: int, second_entity_id: int)
signal progression_events(events: Array)
signal threat_cleared(summary: Dictionary)
signal threat_started(summary: Dictionary)

const Catalog = preload("res://scripts/parts.gd")
const Seeds = preload("res://scripts/seed_utils.gd")
const PowerRuntime = preload("res://scripts/power_runtime.gd")
const RosterRuntime = preload("res://scripts/roster_runtime.gd")
const SwarmRuntime = preload("res://scripts/swarm_runtime.gd")
const SignatureVisuals = preload("res://scripts/signature_visuals.gd")
const PowerVisuals = preload("res://scripts/power_visuals.gd")
const Progression = preload("res://scripts/run_progression.gd")
const Starters = preload("res://scripts/starters.gd")
const EnemyRoles = preload("res://scripts/enemy_roles.gd")
const ContinuousRun = preload("res://scripts/continuous_run.gd")
const RunPowers = preload("res://scripts/run_powers.gd")
const PLAYER_TEAM: String = "player"
const HOSTILE_TEAM: String = "hostile"
const NEUTRAL_TEAM: String = "neutral"
const PLAYER_OWNER: String = "player"
const FIXED_DT: float = 1.0 / 60.0
const GATE_LIMIT: float = 264.0
const GATE_MOUTH_HALF_SUM: float = 36.0
const WALL_AXIS: float = 166.0
const WALL_SUM: float = 270.0
const ROUND_LIMIT: float = 60.0
const BURST_COOLDOWN: float = 4.0
const PLAYER_COLOR: Color = Color("69c7e3")
const ENEMY_COLOR: Color = Color("f0a468")

var continuous = null
var powers = PowerRuntime.new()
var roster = RosterRuntime.new()
# QA descriptors may opt into continuous power semantics without a director.
var ability_rebalance: bool = false
var swarm = SwarmRuntime.new()
var _power_fx: Array[Dictionary] = []
var fighters: Array[Dictionary] = []
var battle_status: String = "idle"
var elapsed: float = 0.0
var paused: bool = false
var last_result: Dictionary = {}
var difficulty: int = 1
var seed_value: int = 0
var hits: int = 0
var screen_shake_enabled: bool = true
var particles_enabled: bool = true
var encounter: Dictionary = {}
var live_time_limit: float = ROUND_LIMIT
var player_entity_id: int = 1

# No full-top equation currently needs a simulation random draw. Keep its
# stream independent for future mechanics; never spend it on visual variation.
var _simulation_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _cosmetic_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _ai_rngs: Dictionary = {}
var _textures: Dictionary = {}
var _assets_loaded: bool = false
var _accumulator: float = 0.0
var _countdown: float = 2.6
var _launch_time: float = 0.0
var _finish_timer: float = 0.0
var _result_emitted: bool = false
var _hit_stop: float = 0.0
var _pair_cooldowns: Dictionary = {}
var _contact_fx_cooldown: float = 0.0
var _shake_strength: float = 2.0
var _signature_ready: float = 0.0
var _presentation_full_contact: bool = false
var _reclaim_ready: float = 0.0
var _low_rpm_ready: float = 0.0
var _shake_time: float = 0.0
var _shake_phase: float = 0.0
var _visual_time: float = 0.0
var _hud_clock: float = 0.0
var _burst_was_down: bool = false
var _burst_buffer: float = 0.0
var _buffered_burst_direction: Vector2 = Vector2.ZERO
var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _progression_queue: Array[Dictionary] = []
var _progression_sequence: int = 0
var _progression_eliminated: Dictionary = {}
var _progression_contacted: Dictionary = {}
var _progression_waves: Dictionary = {}
var _combat_needs_release: bool = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_assets()
	queue_redraw()

func _load_assets() -> void:
	if _assets_loaded:
		return
	_assets_loaded = true
	for layer: String in ["backdrop", "structure", "surface", "markings", "rear_rim", "front_rim"]:
		_cache_texture("arena/" + layer, "res://assets/arena/%s.png" % layer)
	for blade: String in Catalog.BLADE_IDS:
		_cache_texture("blade/" + blade, "res://assets/top/parts/blades/%s_spin.png" % blade)
	for ratchet: String in Catalog.RATCHET_IDS:
		_cache_texture("ratchet/" + ratchet, Catalog.texture_path("ratchet", ratchet))
	for bit: String in Catalog.BIT_IDS:
		_cache_texture("bit/" + bit, Catalog.texture_path("bit", bit))
	for starter_id: String in ["breaker", "bastion", "vane"]:
		_cache_texture("identity/" + starter_id, "res://assets/top/starters/%s_spin.png" % starter_id)
	_cache_texture("rival/smash", "res://assets/top/rivals/smash_blade_warm_spin.png")
	_cache_texture("rival/low", "res://assets/top/rivals/smash_low_flat_warm_ratchet.png")
	_cache_texture("rival/flat", "res://assets/top/rivals/smash_low_flat_warm_bit.png")
	_cache_texture("fx", "res://assets/top/sheets/starter_fx.png")
	_cache_texture("shadow", "res://assets/top/sheets/starter_shadow.png")
	for layer: String in ["bit", "ratchet", "blade"]:
		_cache_texture("starter/" + layer, "res://assets/top/sheets/starter_%s.png" % layer)

func _cache_texture(key: String, path: String) -> void:
	if ResourceLoader.exists(path):
		var resource: Resource = load(path)
		if resource is Texture2D:
			_textures[key] = resource

func begin(player_build: Dictionary, enemy_build: Dictionary, level: int = 1, requested_seed: int = 0) -> void:
	begin_encounter(player_build, {"opponent_build": enemy_build, "difficulty": level, "seed": requested_seed, "live_time_limit": ROUND_LIMIT})

func begin_encounter(player_build: Dictionary, descriptor: Dictionary) -> void:
	continuous = null
	ability_rebalance = bool(descriptor.get("ability_rebalance",false))
	_load_assets()
	encounter = descriptor.duplicate(true)
	_progression_queue.clear()
	_progression_sequence = 0
	_progression_eliminated.clear()
	_progression_contacted.clear()
	_progression_waves.clear()
	difficulty = clampi(int(descriptor.get("difficulty", 1)), 1, 5)
	live_time_limit = maxf(FIXED_DT, float(descriptor.get("live_time_limit", ROUND_LIMIT)))
	# Zero is a valid replay seed. Seed creation belongs to the caller; opening
	# a descriptor at a different wall-clock time must never change combat.
	seed_value = int(descriptor.get("seed", 0))
	_simulation_rng.seed = Seeds.derive(seed_value, "simulation")
	_cosmetic_rng.seed = Seeds.derive(seed_value, "cosmetic")
	_ai_rngs.clear()
	fighters.clear()
	player_entity_id = 1
	add_full_top(player_build, player_entity_id, PLAYER_TEAM, PLAYER_OWNER, Vector2(-59.0, 19.0), Vector2(64.0, -26.0))
	swarm.setup(self, descriptor)
	player_entity()["powers"] = descriptor.get("player_power_ids", []).duplicate()
	player_entity()["power_ranks"] = descriptor.get("player_power_ranks", {}).duplicate(true)
	player_entity()["power_mutations"] = descriptor.get("player_power_mutations", {}).duplicate(true)
	player_entity()["starter_id"] = str(descriptor.get("starter_id", "custom")) if int(descriptor.get("slot",0)) > 0 else "custom"
	var handling: Dictionary = Starters.HANDLING.get(player_entity()["starter_id"], {}).duplicate(true)
	player_entity()["handling"] = handling
	player_entity()["mass"] = float(player_entity()["mass"]) * float(handling.get("mass", 1.0))
	if not swarm.enabled:
		add_full_top(descriptor.get("opponent_build", {}), 2, HOSTILE_TEAM, "rival_1", Vector2(59.0, -19.0), Vector2(-64.0, 26.0))
		entity(2)["powers"] = descriptor.get("opponent_power_ids", []).duplicate()
		entity(2)["power_ranks"] = descriptor.get("opponent_power_ranks", {}).duplicate(true)
		entity(2)["power_mutations"] = descriptor.get("opponent_power_mutations", {}).duplicate(true)
	powers.setup(self)
	roster.setup(self)
	_power_fx.clear()
	battle_status = "countdown"
	elapsed = 0.0
	paused = false
	hits = 0
	last_result = {}
	_countdown = 2.6
	_launch_time = 0.0
	_finish_timer = 0.0
	_result_emitted = false
	_hit_stop = 0.0
	_pair_cooldowns.clear()
	_contact_fx_cooldown = 0.0
	_shake_time = 0.0
	_shake_strength = 2.0
	_signature_ready = 0.0
	_presentation_full_contact = false
	_reclaim_ready = 0.0
	_low_rpm_ready = 0.0
	_visual_time = 0.0
	_hud_clock = 0.0
	_accumulator = 0.0
	_burst_buffer = 0.0
	_buffered_burst_direction = Vector2.ZERO
	_particles.clear()
	_rings.clear()
	_burst_was_down = Input.is_action_pressed("burst")
	_combat_needs_release = not combat_input_neutral()
	_emit_hud()
	queue_redraw()

## One initialization per Run. Threat transitions never call begin_encounter.
func begin_run(player_build: Dictionary, descriptor: Dictionary, run_seed: int) -> void:
	begin_encounter(player_build, descriptor)
	continuous = ContinuousRun.new()
	continuous.setup(self, run_seed)
	_emit_hud()

func threat_elapsed() -> float:
	return continuous.threat_elapsed() if continuous != null else elapsed

## Replace only threat-owned state; player dictionary and semantic runtime stay live.
func enter_threat(descriptor: Dictionary, entry_position: Vector2) -> void:
	encounter = descriptor.duplicate(true)
	var player: Dictionary = player_entity()
	encounter["player_power_ids"] = player.powers.duplicate()
	encounter["player_power_ranks"] = player.power_ranks.duplicate(true)
	encounter["player_power_mutations"] = player.power_mutations.duplicate(true)
	encounter["starter_id"] = player.starter_id
	if descriptor.fixture_type == "swarm":
		_progression_waves.clear()
		swarm.setup(self, descriptor)
	else:
		var id: int = int(descriptor.first_entity_id)
		add_full_top(descriptor.opponent_build, id, HOSTILE_TEAM, "rival_%d" % id, entry_position)
		var rival: Dictionary = entity(id)
		EnemyRoles.configure(rival,descriptor.director_event)
		rival.vel = -entry_position.normalized() * 64.0
		rival.powers = descriptor.get("opponent_power_ids", []).duplicate()
		rival.power_ranks = descriptor.get("opponent_power_ranks", {}).duplicate(true)
		rival.power_mutations = descriptor.get("opponent_power_mutations", {}).duplicate(true)
		_spawn_ring(project(entry_position), ENEMY_COLOR, 0.5)
		event_sfx.emit("land")

func remove_retired_enemy(id: int) -> void:
	var retired: Dictionary = entity(id)
	if retired.is_empty() or id == player_entity_id or _is_live(retired): return
	for index: int in range(fighters.size() - 1, -1, -1):
		if int(fighters[index].entity_id) == id: fighters.remove_at(index)
	if continuous != null: continuous.economy.retire(id)
	_ai_rngs.erase(id)
	_progression_eliminated.erase(id)
	_progression_contacted.erase(id)
	for key: String in _pair_cooldowns.keys():
		if str(id) in key.split(":"): _pair_cooldowns.erase(key)

func add_full_top(build: Dictionary, entity_id: int, team_id: String, owner_id: String, start: Vector2, launch_velocity: Vector2 = Vector2.ZERO) -> bool:
	if entity_id <= 0 or not entity(entity_id).is_empty():
		return false
	var ai_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	ai_rng.seed = Seeds.derive(seed_value, "ai:%d" % entity_id)
	_ai_rngs[entity_id] = ai_rng
	fighters.append(_make_fighter(build, entity_id, team_id, owner_id, start, launch_velocity, ai_rng))
	return true

func _make_fighter(build: Dictionary, entity_id: int, team_id: String, owner_id: String, start: Vector2, launch_velocity: Vector2, ai_rng: RandomNumberGenerator) -> Dictionary:
	var clean: Dictionary = Catalog.validate_build(build)
	var stats: Dictionary = Catalog.derive(clean)
	var radius: float = {"balance": 12.2, "smash": 13.1, "guard": 13.5, "hook": 12.5}[clean["blade"]]
	return {
		"build": clean, "stats": stats, "pos": start,
		"entity_id": entity_id, "team_id": team_id, "owner_id": owner_id,
		"combatant_type": "full_top", "launch_velocity": launch_velocity, "powers": [], "impulse_time": 0.0,
		"power_ranks": {}, "power_mutations": {}, "anchor_charge": 0.0, "stored_force": 0.0,
		"runaway_heat": 0.0, "slipstream_time": 0.0, "redline_heading": Vector2.ZERO,
		"ai_clock": 0.0, "ai_direction": Vector2.ZERO,
		"ai_burst_delay": 2.5 + ai_rng.randf_range(0.0, 1.1),
		"vel": Vector2.ZERO, "rpm": 1.0, "energy": 1.0, "wobble": 0.0,
		"mass": 3.8 + float(stats["mass"]) * 0.56, "radius": radius,
		"cooldown": 0.0, "burst_time": 0.0, "height": 0.0,
		"height_vel": 0.0, "phase": _cosmetic_rng.randf_range(0.0, 8.0),
		"impact_time": 0.0, "impact_strength": 0.0, "outcome": "",
		"out_time": 0.0, "trail": [], "scrape_clock": 0.0,
		"name": str(clean["blade"]).to_upper()
	}

func entity(entity_id: int) -> Dictionary:
	for fighter: Dictionary in fighters:
		if int(fighter["entity_id"]) == entity_id:
			return fighter
	return {}

func player_entity() -> Dictionary:
	return entity(player_entity_id)

func _ordered_fighters() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = fighters.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["entity_id"]) < int(b["entity_id"]))
	return ordered

func _is_live(fighter: Dictionary) -> bool:
	return str(fighter["outcome"]).is_empty() and str(fighter["combatant_type"]) in ["full_top", "small_top"]

func _opposes(first: Dictionary, second: Dictionary) -> bool:
	return str(first["team_id"]) != str(second["team_id"]) and str(first["team_id"]) != NEUTRAL_TEAM and str(second["team_id"]) != NEUTRAL_TEAM

func _target_for(fighter: Dictionary) -> Dictionary:
	var target: Dictionary = {}
	var nearest: float = INF
	for candidate: Dictionary in _ordered_fighters():
		if not _is_live(candidate) or not _opposes(fighter, candidate):
			continue
		var distance: float = Vector2(fighter["pos"]).distance_squared_to(candidate["pos"])
		if distance < nearest:
			nearest = distance
			target = candidate
	return target

func _team_color(fighter: Dictionary) -> Color:
	if fighter.get("enemy_kind","") == "boss": return Color("ff6278")
	if fighter.get("enemy_kind","") == "elite": return Color("f5dc68")
	if str(fighter["team_id"]) == PLAYER_TEAM:
		return {"breaker":Color("ef7052"), "bastion":Color("69bafa"), "vane":Color("82d978")}.get(str(fighter.get("starter_id", "custom")), PLAYER_COLOR)
	return Color("b8c2c8") if str(fighter["team_id"]) == NEUTRAL_TEAM else ENEMY_COLOR

func set_paused(value: bool) -> void:
	paused = value
	# The same face button confirms menus and bursts. A held confirmation must
	# be released before it can become a new combat press after launch/resume.
	_burst_was_down = Input.is_action_pressed("burst")
	if not value:
		_combat_needs_release = not combat_input_neutral()
		_burst_buffer = 0.0
		_buffered_burst_direction = Vector2.ZERO
	_emit_hud()
	queue_redraw()

func combat_input_neutral() -> bool:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down").length() <= 0.05 and not Input.is_action_pressed("burst") and not Input.is_action_pressed("brake")

func acquire_run_power(power_id: String, rank_value: int = 1, mutation_value: String = "") -> bool:
	# Preserve the live PowerRuntime and every existing cooldown/cause/trace.
	# Its semantic hooks read this list, so a newly owned power is live next tick.
	var player: Dictionary = player_entity()
	if player.is_empty() or rank_value < 1 or rank_value > RunPowers.max_rank(power_id): return false
	var old_rank: int = powers.rank(player, power_id)
	if rank_value != old_rank + 1: return false
	if rank_value == 3:
		if mutation_value not in PowerRuntime.MUTATIONS.get(power_id, []) or not str(player["power_mutations"].get(power_id, "")).is_empty(): return false
	elif not mutation_value.is_empty(): return false
	if old_rank == 0: player["powers"].append(power_id)
	player["power_ranks"][power_id] = rank_value
	if rank_value == 3: player["power_mutations"][power_id] = mutation_value
	encounter["player_power_ids"] = player["powers"].duplicate()
	encounter["player_power_ranks"] = player["power_ranks"].duplicate(true)
	encounter["player_power_mutations"] = player["power_mutations"].duplicate(true)
	# Cosmetic previews change no reserve, force, cooldown or semantic runtime.
	if rank_value >= 2:
		var preview: String = {"redline": "redline_ii", "dead_centre": "anchor", "afterimage": "afterimage_ii"}.get(power_id, "")
		if rank_value == 3:
			preview = {"runaway": "runaway", "breakneck": "breakneck_charge", "bulwark": "bulwark_impact", "counterweight": "counterweight_store", "ghost_circuit": "ghost_closure", "slipstream": "slipstream_cross"}.get(mutation_value, preview)
		add_power_fx(preview, player["pos"], Vector2(player["vel"]).normalized(), float(rank_value))
	return true

func _physics_process(delta: float) -> void:
	if paused or battle_status == "idle":
		return
	# InputMap merges keyboard and Godot-mapped gamepads. get_vector applies a
	# circular deadzone while retaining analogue direction and magnitude.
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var burst_down: bool = Input.is_action_pressed("burst")
	var trigger_burst: bool = burst_down and not _burst_was_down
	_burst_was_down = burst_down
	var brake: bool = Input.is_action_pressed("brake")
	if _combat_needs_release:
		if combat_input_neutral(): _combat_needs_release = false
		direction = Vector2.ZERO
		trigger_burst = false
		brake = false
	test_step(delta, direction, trigger_burst, brake)

## Deterministic QA and interactive play use exactly the same 60 Hz simulation.
func test_step(dt: float, input_direction: Vector2 = Vector2.ZERO, burst: bool = false, brake: bool = false) -> void:
	if paused or battle_status == "idle":
		return
	if burst:
		# A press during the brief impact hold survives until the next live tick.
		_burst_buffer = 0.12
		_buffered_burst_direction = input_direction.limit_length(1.0)
	_accumulator += clampf(dt, 0.0, 0.25)
	while not paused and _accumulator + 0.000001 >= FIXED_DT:
		_accumulator -= FIXED_DT
		_step(FIXED_DT, input_direction.limit_length(1.0), brake)
	queue_redraw()

func _step(dt: float, screen_direction: Vector2, brake: bool) -> void:
	_visual_time += dt
	_burst_buffer = maxf(0.0, _burst_buffer - dt)
	_update_effects(dt)
	_hud_clock -= dt
	if battle_status == "finished":
		_update_finish(dt)
		if _hud_clock <= 0.0:
			_emit_hud()
		return
	if battle_status == "countdown":
		var old_count: int = ceili(_countdown)
		_countdown = maxf(0.0, _countdown - dt)
		if ceili(_countdown) != old_count:
			event_sfx.emit("countdown")
		if _countdown <= 0.0:
			battle_status = "launch"
			_launch_time = 0.0
			for fighter: Dictionary in fighters:
				fighter["height"] = 20.0
				fighter["height_vel"] = -12.0
			event_sfx.emit("launch")
		if _hud_clock <= 0.0:
			_emit_hud()
		return
	if battle_status == "launch":
		_launch_time += dt
		for fighter: Dictionary in fighters:
			fighter["phase"] = fmod(float(fighter["phase"]) + dt * 19.0, 8.0)
			fighter["height"] = maxf(0.0, 20.0 * (1.0 - _launch_time / 0.45))
		if _launch_time >= 0.45:
			battle_status = "battle"
			for fighter: Dictionary in fighters:
				fighter["vel"] = fighter["launch_velocity"]
				_spawn_ring(project(fighter["pos"]), _team_color(fighter), 0.35)
			event_sfx.emit("land")
		if _hud_clock <= 0.0:
			_emit_hud()
		return
	if _hit_stop > 0.0:
		_hit_stop = maxf(0.0, _hit_stop - dt)
		return
	elapsed += dt
	if continuous != null: continuous.economy.begin_tick(dt, screen_direction)
	powers.begin_tick(dt)
	roster.begin_tick(dt)
	swarm.begin_tick(dt)
	for pair_key: String in _pair_cooldowns.keys():
		_pair_cooldowns[pair_key] = maxf(0.0, float(_pair_cooldowns[pair_key]) - dt)
		if float(_pair_cooldowns[pair_key]) <= 0.0:
			_pair_cooldowns.erase(pair_key)
	_contact_fx_cooldown = maxf(0.0, _contact_fx_cooldown - dt)
	var player_world_direction: Vector2 = unproject_direction(screen_direction)
	var ordered: Array[Dictionary] = _ordered_fighters()
	# Decide all controls before integrating any entity, so array order cannot
	# make an AI read a target one simulation tick ahead of another AI.
	for fighter: Dictionary in ordered:
		if _is_live(fighter) and str(fighter["combatant_type"]) == "small_top":
			swarm.decide(fighter, dt)
		elif _is_live(fighter) and str(fighter["owner_id"]) != PLAYER_OWNER:
			fighter["ai_burst_delay"] = float(fighter["ai_burst_delay"]) - dt
			_update_ai(fighter, dt)
	var player: Dictionary = player_entity()
	if not player.is_empty() and _is_live(player) and _burst_buffer > 0.0 and float(player["cooldown"]) <= 0.0:
		_attempt_burst(player, unproject_direction(_buffered_burst_direction))
		_burst_buffer = 0.0
	for fighter: Dictionary in ordered:
		if not _is_live(fighter) or str(fighter["owner_id"]) == PLAYER_OWNER or str(fighter["combatant_type"]) == "small_top":
			continue
		var target: Dictionary = _target_for(fighter)
		if not target.is_empty() and float(fighter["ai_burst_delay"]) <= 0.0 and float(fighter["cooldown"]) <= 0.0:
			var ai_pos: Vector2 = fighter["pos"]
			if (EnemyRoles.wants_burst(fighter,target,elapsed) if fighter.has("role") else ai_pos.distance_to(target["pos"]) < 105.0 and absf(ai_pos.x - ai_pos.y) < 195.0):
				_attempt_burst(fighter, fighter["ai_direction"])
				var ai_rng: RandomNumberGenerator = _ai_rngs[int(fighter["entity_id"])]
				fighter["ai_burst_delay"] = ai_rng.randf_range(2.0, 3.8)
	var starts: Dictionary = {}
	var has_small: bool = swarm.active_count() > 0
	for fighter: Dictionary in ordered:
		if not _is_live(fighter): continue
		starts[int(fighter.entity_id)] = fighter.pos
		if fighter.combatant_type == "small_top":
			swarm.move(fighter, dt)
		else:
			var controlled: bool = str(fighter["owner_id"]) == PLAYER_OWNER
			_update_fighter(fighter, player_world_direction if controlled else Vector2(fighter["ai_direction"]), brake if controlled else _ai_should_brake(fighter), dt)
	if has_small:
		# Four bounded motion slices: even opposing 400-unit/s bodies move less
		# than their combined radius per slice. Full-top no-swarm path is unchanged.
		for fighter: Dictionary in ordered:
			if starts.has(int(fighter.entity_id)): fighter.pos = starts[int(fighter.entity_id)]
		for slice: int in range(4):
			for fighter: Dictionary in ordered:
				if _is_live(fighter): fighter.pos = Vector2(fighter.pos) + Vector2(fighter.vel) * dt * 0.25
			_resolve_contact()
			powers.flush_contact_powers()
			for fighter: Dictionary in ordered:
				if _is_live(fighter): _resolve_boundary(fighter)
	else:
		_resolve_contact()
		powers.flush_contact_powers()
		for fighter: Dictionary in ordered:
			if _is_live(fighter): _resolve_boundary(fighter)
	powers.after_movement()
	powers.flush_contact_powers()
	if continuous != null: continuous.economy.outcomes()
	powers.recover()
	swarm.account_outcomes()
	_check_result()
	powers.end_tick(battle_status == "finished")
	if continuous != null: continuous.economy.end_tick(dt)
	_collect_progression_outcomes()
	if not _progression_queue.is_empty():
		var earned: Array[Dictionary] = _progression_queue.duplicate(true)
		_progression_queue.clear()
		# Only publish at the fixed-tick boundary. Menu pause cannot bisect
		# contact resolution, chain propagation, recovery or swarm scheduling.
		progression_events.emit(earned)
	if continuous != null: continuous.after_tick(dt)
	if _hud_clock <= 0.0:
		_emit_hud()

func _queue_progression(data: Dictionary) -> void:
	if int(encounter.get("slot", 0)) <= 0: return
	_progression_sequence += 1
	data["event_id"] = _progression_sequence
	data["encounter_id"] = str(encounter.get("id", ""))
	if continuous != null: data["scope_id"] = "continuous/%d" % continuous.run_seed
	data["time"] = elapsed
	_progression_queue.append(data)

func _progression_contact(first: Dictionary, second: Dictionary, severity: float) -> void:
	if continuous != null and (not is_same(entity(int(first.entity_id)), first) or not is_same(entity(int(second.entity_id)), second)): return
	if int(encounter.get("slot", 0)) <= 0 or not _opposes(first, second): return
	if int(first.entity_id) != player_entity_id and int(second.entity_id) != player_entity_id: return
	var hostile: Dictionary = second if int(first.entity_id) == player_entity_id else first
	if severity >= float(Progression.TUNING.collision_min_severity):
		_progression_contacted[int(hostile.entity_id)] = true
	_queue_progression({"kind":"collision", "first_entity_id":int(first.entity_id), "second_entity_id":int(second.entity_id), "severity":severity, "player_attributed":true})

func _collect_progression_outcomes() -> void:
	if int(encounter.get("slot", 0)) <= 0: return
	for fighter: Dictionary in _ordered_fighters():
		var id: int = int(fighter.entity_id)
		if str(fighter.outcome).is_empty() or fighter.team_id != HOSTILE_TEAM or _progression_eliminated.has(id): continue
		_progression_eliminated[id] = true
		# Timeout presentation sets a defeated full top's visual outcome to
		# spin_out. It is not a physical knockout and must not generate XP.
		if fighter.combatant_type == "full_top" and battle_status == "finished" and str(last_result.get("reason", "")) in ["timeout", "draw"]: continue
		var cause: Dictionary = powers.cause_for(fighter)
		var credited: bool = str(cause.get("owner_id", "")) == PLAYER_OWNER if fighter.combatant_type == "small_top" else _progression_contacted.has(id)
		if credited and fighter.outcome in ["impact", "ring_out", "spin_out"]:
			_queue_progression({"kind":"elimination", "entity_id":id, "combatant_type":str(fighter.combatant_type), "enemy_kind":str(fighter.get("enemy_kind","")), "reason":str(fighter.outcome), "wave":int(fighter.get("wave",0)), "player_attributed":true})
			if fighter.combatant_type == "small_top": _progression_waves["credit_%d" % int(fighter.wave)] = true
	if not swarm.enabled: return
	for wave_id: int in range(1, swarm.total_waves + 1):
		if _progression_waves.has(wave_id): continue
		var resolved: bool = true
		for entry: Dictionary in swarm.schedule:
			if int(entry.wave) != wave_id: continue
			if entry.state not in ["spawned", "cancelled"]: resolved = false; break
			var body: Dictionary = entity(int(entry.id))
			if not body.is_empty() and str(body.outcome).is_empty(): resolved = false; break
		if resolved:
			_progression_waves[wave_id] = true
			if _progression_waves.has("credit_%d" % wave_id):
				_queue_progression({"kind":"wave_complete", "wave":wave_id+swarm.event_serial*10, "player_attributed":true})

static func project(world_position: Vector2, height: float = 0.0) -> Vector2:
	return Vector2(320.0 + world_position.x - world_position.y, 165.0 + (world_position.x + world_position.y) * 0.5 - height)

static func unproject_direction(screen_direction: Vector2) -> Vector2:
	if screen_direction.length_squared() < 0.0001:
		return Vector2.ZERO
	var world: Vector2 = Vector2(screen_direction.y + screen_direction.x * 0.5, screen_direction.y - screen_direction.x * 0.5)
	return world.normalized() * minf(1.0, screen_direction.length())

func _update_ai(rival: Dictionary, dt: float) -> void:
	if rival.has("role"):
		rival.ai_clock -= dt
		if float(rival.ai_clock) <= 0.0:
			rival.ai_clock = 0.22
			var target: Dictionary = _target_for(rival)
			rival.ai_direction = EnemyRoles.direction(rival,target,elapsed) if not target.is_empty() else Vector2.ZERO
		return
	rival["ai_clock"] = float(rival["ai_clock"]) - dt
	if float(rival["ai_clock"]) > 0.0:
		return
	var ai_rng: RandomNumberGenerator = _ai_rngs[int(rival["entity_id"])]
	rival["ai_clock"] = 0.16 + ai_rng.randf_range(0.01, 0.08)
	var player: Dictionary = _target_for(rival)
	if player.is_empty():
		rival["ai_direction"] = Vector2.ZERO
		return
	var own_position: Vector2 = rival["pos"]
	var player_position: Vector2 = player["pos"]
	var player_velocity: Vector2 = player["vel"]
	var delta_position: Vector2 = player_position - own_position
	var distance: float = delta_position.length()
	var aim: Vector2 = delta_position + player_velocity * (0.12 + float(difficulty) * 0.018)
	var approach: Vector2 = aim.normalized()
	var orbit: Vector2 = Vector2(-approach.y, approach.x)
	var orbit_strength: float = 0.23 if distance < 82.0 else 0.08
	var pulse: float = sin(elapsed * 0.8 + float(seed_value % 17))
	var desired: Vector2 = approach * (0.83 + 0.035 * float(difficulty)) + orbit * pulse * orbit_strength
	var near_gate: float = absf(own_position.x - own_position.y)
	if near_gate > 185.0 or own_position.length() > 159.0:
		var avoidance: float = clampf((maxf(near_gate * 0.7, own_position.length()) - 140.0) / 40.0, 0.0, 1.0)
		desired = desired.lerp(-own_position.normalized(), avoidance * 0.87)
	if float(rival["rpm"]) < 0.22 and float(player["rpm"]) > 0.30:
		# A tiring opponent can be chased: it circles, but never reads future input.
		desired = (-approach * 0.30 + orbit * 0.80 - own_position.normalized() * 0.30).normalized()
	rival["ai_direction"] = desired.limit_length(0.91 + minf(float(difficulty - 1) * 0.02, 0.08))

func _ai_should_brake(rival: Dictionary) -> bool:
	var own_position: Vector2 = rival["pos"]
	var own_velocity: Vector2 = rival["vel"]
	return absf(own_position.x - own_position.y) > 212.0 and own_position.dot(own_velocity) > 0.0

## Source-aware writes. Standalone modes retain their exact previous arithmetic.
func spend_rpm(fighter: Dictionary, amount: float, source: String) -> void:
	if continuous != null:
		continuous.economy.spend(fighter,amount,source)
	else:
		fighter.rpm = maxf(0.0,float(fighter.rpm)-amount)
		fighter.energy = fighter.rpm

func gain_rpm(fighter: Dictionary, amount: float, source: String, small: bool = false) -> float:
	if continuous != null and int(fighter.entity_id) == player_entity_id:
		return continuous.economy.gain(fighter,amount,source,small)
	else:
		var before: float = fighter.rpm
		fighter.rpm = minf(powers.rpm_cap(fighter),float(fighter.rpm)+amount)
		fighter.energy = fighter.rpm
		return float(fighter.rpm)-before

func _attempt_burst(fighter: Dictionary, direction: Vector2) -> void:
	if float(fighter["cooldown"]) > 0.0 or float(fighter["rpm"]) < 0.13:
		return
	var position_world: Vector2 = fighter["pos"]
	var velocity_world: Vector2 = fighter["vel"]
	var heading: Vector2 = direction
	if heading.length_squared() < 0.01:
		var other: Dictionary = _target_for(fighter)
		if not other.is_empty():
			heading = (Vector2(other["pos"]) - position_world).normalized()
	if heading.length_squared() < 0.01:
		heading = velocity_world.normalized()
	var pre_cost_rpm: float = float(fighter["rpm"])
	var stats: Dictionary = fighter["stats"]
	var push: float = 67.0 + float(stats["grip"]) * 3.0
	fighter["vel"] = velocity_world + heading.normalized() * push
	fighter["cooldown"] = BURST_COOLDOWN
	fighter["burst_time"] = 0.42
	spend_rpm(fighter,0.013,"burst")
	fighter["energy"] = fighter["rpm"]
	_spawn_ring(project(position_world), _team_color(fighter), 0.30)
	powers.burst_started(fighter, heading.normalized(), pre_cost_rpm)
	roster.burst(fighter,heading.normalized())
	event_sfx.emit("burst")

func _update_fighter(fighter: Dictionary, direction: Vector2, braking: bool, dt: float) -> void:
	var modifiers: Dictionary = powers.movement_control(fighter, direction, braking, dt)
	modifiers = roster.movement(fighter,modifiers,dt)
	direction = modifiers["direction"]
	braking = bool(modifiers["braking"])
	var stats: Dictionary = fighter["stats"]
	var position_world: Vector2 = fighter["pos"]
	var velocity_world: Vector2 = fighter["vel"]
	var rpm: float = float(fighter["rpm"])
	var grip: float = float(stats["grip"])
	var stability: float = float(stats["stability"])
	var stamina: float = float(stats["stamina"])
	var alive_factor: float = clampf(rpm * 2.3 + 0.20, 0.18, 1.0)
	var acceleration: float = (123.0 + grip * 17.0) * alive_factor
	var top_speed: float = (110.0 + float(stats["speed"]) * 13.0) * (0.64 + alive_factor * 0.36)
	var handling: Dictionary = fighter.get("handling", {})
	acceleration *= float(handling.get("acceleration", 1.0))
	top_speed *= float(handling.get("speed", 1.0))
	acceleration *= float(modifiers["acceleration"])
	top_speed *= float(modifiers["speed"])
	var burst_time: float = maxf(0.0, float(fighter["burst_time"]) - dt)
	if burst_time > 0.0 or powers.redline_active(fighter):
		acceleration *= 1.65
		top_speed *= 1.46
	if braking:
		acceleration *= 0.5
	var acceleration_world: Vector2 = direction * acceleration
	# A shallow dish gently returns roaming tops. The bank is steeper, but
	# collision momentum still carries a top through either unguarded gate.
	var radial_distance: float = position_world.length()
	if radial_distance > 2.0:
		var bank: float = maxf(0.0, radial_distance - 105.0) * 0.83
		acceleration_world -= position_world.normalized() * (9.0 + bank) * float(handling.get("bank", 1.0))
		var tangent: Vector2 = Vector2(-position_world.y, position_world.x).normalized()
		acceleration_world += tangent * (6.0 + rpm * 8.0) * float(handling.get("orbit", 1.0))
	velocity_world += acceleration_world.limit_length(float(modifiers["acceleration_limit"])) * dt
	var drag: float = 0.54 + grip * 0.030
	drag += float(modifiers["drag"])
	if braking:
		drag += (3.8 + grip * 0.20)*float(modifiers.get("brake_drag_scale",1.0))*float(modifiers.get("braking_efficiency",1.0))
	velocity_world *= exp(-drag * dt)
	if float(fighter.get("impulse_time",0.0)) > 0.0:
		top_speed = maxf(top_speed, 340.0)
		fighter["impulse_time"] = maxf(0.0, float(fighter.impulse_time)-dt)
	velocity_world = roster.velocity(fighter,Vector2(fighter.vel),velocity_world.limit_length(top_speed),dt)
	# Expanded movement combinations and overclock share a finite safety ceiling.
	if continuous != null or ability_rebalance: velocity_world = velocity_world.limit_length(RosterRuntime.SPEED_CLAMP)
	position_world += velocity_world * dt
	# Low spin loses both control and stability. Braking buys position at a
	# measurable spin cost; attack bits naturally spend more reserve.
	var natural_loss: float = 0.025 - stamina * 0.00155
	var moving_loss: float = velocity_world.length() / 230.0 * 0.0014
	var brake_loss: float = 0.0055 if braking else 0.0
	var wobble_loss: float = float(fighter["wobble"]) * 0.0048
	if continuous != null and int(fighter.entity_id) == player_entity_id:
		continuous.economy.running_costs(fighter,velocity_world.length(),direction,braking,float(modifiers.drain),dt)
		rpm = fighter.rpm
	else:
		rpm = maxf(0.0, rpm - (natural_loss + moving_loss + brake_loss + wobble_loss) * dt * float(handling.get("spin_drain", 1.0)) * float(modifiers["drain"]))
	var low_spin_wobble: float = clampf((0.32 - rpm) * 2.5, 0.0, 0.80)
	var current_wobble: float = float(fighter["wobble"])
	current_wobble = maxf(low_spin_wobble, current_wobble - (0.040 + stability * 0.007) * dt * float(handling.get("recovery", 1.0))*float(modifiers.get("recovery",1.0)))
	fighter["pos"] = position_world
	fighter["vel"] = velocity_world
	fighter["rpm"] = rpm
	fighter["energy"] = rpm
	fighter["wobble"] = clampf(current_wobble, 0.0, 1.0)
	fighter["cooldown"] = maxf(0.0, float(fighter["cooldown"]) - dt)
	fighter["burst_time"] = burst_time
	fighter["impact_time"] = maxf(0.0, float(fighter["impact_time"]) - dt)
	fighter["phase"] = fmod(float(fighter["phase"]) + dt * (3.2 + powers.effective_rpm(fighter) * 13.5), 8.0)
	fighter["height_vel"] = float(fighter["height_vel"]) - 140.0 * dt
	fighter["height"] = maxf(0.0, float(fighter["height"]) + float(fighter["height_vel"]) * dt)
	if float(fighter["height"]) <= 0.0:
		fighter["height_vel"] = 0.0
	var trail: Array = fighter["trail"]
	trail.append(project(position_world))
	if trail.size() > 5:
		trail.pop_front()
	fighter["scrape_clock"] = float(fighter["scrape_clock"]) - dt
	if current_wobble > 0.63 and float(fighter["scrape_clock"]) <= 0.0:
		_spawn_sparks(project(position_world), velocity_world.normalized(), 3, 0.35)
		fighter["scrape_clock"] = 0.24

func _resolve_contact() -> void:
	var ordered: Array[Dictionary] = []
	for fighter: Dictionary in _ordered_fighters():
		if _is_live(fighter): ordered.append(fighter)
	for first_index: int in range(ordered.size()):
		for second_index: int in range(first_index + 1, ordered.size()):
			_resolve_pair_records(ordered[first_index], ordered[second_index])

## Canonical ID ordering gives exact overlaps the same normal and resolves
## simultaneous pairs in the same order even if the backing array is reversed.
func resolve_pair(first_entity_id: int, second_entity_id: int) -> void:
	if battle_status != "battle" or first_entity_id == second_entity_id:
		return
	var first: Dictionary = entity(mini(first_entity_id, second_entity_id))
	var second: Dictionary = entity(maxi(first_entity_id, second_entity_id))
	_resolve_pair_records(first, second)

func _resolve_pair_records(first: Dictionary, second: Dictionary) -> void:
	if battle_status != "battle": return
	if first.is_empty() or second.is_empty() or not _is_live(first) or not _is_live(second):
		return
	if first.combatant_type == "small_top" or second.combatant_type == "small_top":
		_resolve_small_pair(first, second)
		return
	var pair_key: String = "%d:%d" % [int(first["entity_id"]), int(second["entity_id"])]
	var a: Vector2 = first["pos"]
	var b: Vector2 = second["pos"]
	var difference: Vector2 = b - a
	var distance: float = difference.length()
	var min_distance: float = float(first["radius"]) + float(second["radius"])
	if distance >= min_distance:
		return
	var normal: Vector2 = difference / distance if distance > 0.001 else Vector2.RIGHT
	var inv_a: float = powers.inverse_mass(first)
	var inv_b: float = powers.inverse_mass(second)
	var inv_sum: float = inv_a + inv_b
	var separation: float = (min_distance - distance) + 0.05
	first["pos"] = a - normal * separation * inv_a / inv_sum
	second["pos"] = b + normal * separation * inv_b / inv_sum
	var va: Vector2 = first["vel"]
	var vb: Vector2 = second["vel"]
	var closing: float = (va - vb).dot(normal)
	if closing <= 0.0:
		return
	var a_stats: Dictionary = first["stats"]
	var b_stats: Dictionary = second["stats"]
	var a_burst: float = 1.43 if float(first["burst_time"]) > 0.0 else 1.0
	var b_burst: float = 1.43 if float(second["burst_time"]) > 0.0 else 1.0
	var a_attack: float = (0.66 + float(a_stats["power"]) * 0.073) * a_burst * (0.45 + powers.effective_rpm(first) * 0.55)
	var b_attack: float = (0.66 + float(b_stats["power"]) * 0.073) * b_burst * (0.45 + powers.effective_rpm(second) * 0.55)
	a_attack *= float(first.get("handling", {}).get("impact", 1.0))
	b_attack *= float(second.get("handling", {}).get("impact", 1.0))
	a_attack *= powers.attack_multiplier(first)
	b_attack *= powers.attack_multiplier(second)
	a_attack *= roster.attack_multiplier(first,second)
	b_attack *= roster.attack_multiplier(second,first)
	var impulse: float = (1.70 * closing + 19.0) / inv_sum
	var attack_bias: float = clampf((a_attack - b_attack) * 0.19, -0.25, 0.25)
	first["vel"] = va - normal * impulse * inv_a * (1.0 - attack_bias)
	second["vel"] = vb + normal * impulse * inv_b * (1.0 + attack_bias)
	# The glancing edge on Hook redirects a little impulse across the face.
	var tangent: Vector2 = Vector2(-normal.y, normal.x)
	if str(first["build"]["blade"]) == "hook":
		second["vel"] = Vector2(second["vel"]) + tangent * closing * 0.12
	if str(second["build"]["blade"]) == "hook":
		first["vel"] = Vector2(first["vel"]) - tangent * closing * 0.12
	if continuous != null or ability_rebalance:
		first.vel = Vector2(first.vel).limit_length(RosterRuntime.SPEED_CLAMP)
		second.vel = Vector2(second.vel).limit_length(RosterRuntime.SPEED_CLAMP)
	if float(_pair_cooldowns.get(pair_key, 0.0)) > 0.0:
		return
	_pair_cooldowns[pair_key] = 0.24
	hits += 1
	var severity: float = clampf(closing / 220.0, 0.08, 1.30)
	var a_defense: float = 0.76 + float(a_stats["stability"]) * 0.055 + float(a_stats["mass"]) * 0.016
	var b_defense: float = 0.76 + float(b_stats["stability"]) * 0.055 + float(b_stats["mass"]) * 0.016
	var loss_a: float = (0.004 + severity * 0.012) * b_attack / a_defense * roster.collision_cost(first)
	var loss_b: float = (0.004 + severity * 0.012) * a_attack / b_defense * roster.collision_cost(second)
	var actual_a: float = minf(float(first.rpm),loss_a)
	var actual_b: float = minf(float(second.rpm),loss_b)
	spend_rpm(first,loss_a,"collisions")
	spend_rpm(second,loss_b,"collisions")
	first["energy"] = first["rpm"]
	second["energy"] = second["rpm"]
	first["wobble"] = minf(1.0, float(first["wobble"]) + loss_a * 3.1)
	second["wobble"] = minf(1.0, float(second["wobble"]) + loss_b * 3.1)
	for fighter: Dictionary in [first, second]:
		fighter["impact_time"] = 0.30 if severity > 0.5 else 0.18
		fighter["impact_strength"] = severity
		if severity > 0.75:
			fighter["height_vel"] = 27.0
	if continuous != null:
		if int(first.entity_id) == player_entity_id: continuous.economy.contact(second,severity,actual_b,va.dot(normal),va.length())
		elif int(second.entity_id) == player_entity_id: continuous.economy.contact(first,severity,actual_a,-vb.dot(normal),vb.length())
	_presentation_full_contact = true
	powers.accepted_contact(first, second, severity, normal, a + normal * float(first.radius), Vector2(first.vel)-va, Vector2(second.vel)-vb, impulse / float(first.mass) * (1.0 - attack_bias), impulse / float(second.mass) * (1.0 + attack_bias))
	_presentation_full_contact = false
	roster.contact(first,second,severity,normal,va,vb)
	_progression_contact(first, second, severity)
	contact_accepted.emit(int(first["entity_id"]), int(second["entity_id"]))
	# The authored impact hold remains gameplay timing and is independent of
	# particle/audio throttling. Another valid pair still receives its damage.
	if continuous == null and severity > 0.50:
		_hit_stop = FIXED_DT * 2.0
	elif continuous != null and _contact_fx_cooldown <= 0.0:
		_hit_stop = maxf(_hit_stop,SignatureVisuals.impact_hold(SignatureVisuals.impact_tier(severity)))
	if _contact_fx_cooldown > 0.0:
		return
	_contact_fx_cooldown = 0.24
	var tier: String = SignatureVisuals.impact_tier(severity)
	add_power_fx("contact_"+tier,(a+b)*0.5,normal,severity)
	var impact: Vector2 = project((a + b) * 0.5)
	_spawn_sparks(impact - Vector2(0.0, 13.0), normal, 6 + int(severity * 8.0), severity)
	_spawn_ring(impact - Vector2(0.0, 12.0), Color("f3c36a"), 0.22)
	if severity > 0.50:
		_shake_time = 0.11
		_shake_strength = maxf(_shake_strength,SignatureVisuals.impact_shake(tier))
		event_sfx.emit("heavy_impact")
	else:
		event_sfx.emit("hit")

func apply_power_impulse(target: Dictionary, delta_velocity: Vector2, _cause: Dictionary) -> void:
	if continuous != null and not is_same(entity(int(target.entity_id)), target): return
	if not _is_live(target): return
	# Attribution is an observer only. Full tops do not use the small-body
	# propagation tag, but a live player-owned pressure effect still earns
	# credit if its physical impulse knocks a rival out before direct contact.
	if target.combatant_type == "full_top" and target.team_id == HOSTILE_TEAM and str(_cause.get("owner_id", "")) == PLAYER_OWNER and int(_cause.get("owner_entity_id", -1)) == player_entity_id and float(_cause.get("expires_at", -1.0)) >= powers.time and delta_velocity.length_squared() > 0.0001:
		_progression_contacted[int(target.entity_id)] = true
		if continuous != null: continuous.economy.credit(target)
	var cap: float = 400.0 if target.combatant_type == "small_top" else 340.0
	var braced_velocity: Vector2 = delta_velocity.limit_length(100.0)
	powers.incoming_power_impulse(target, braced_velocity, _cause)
	if float(target.get("anchor_charge", 0.0)) > 0.0:
		braced_velocity *= powers.inverse_mass(target) * float(target.mass)
	target.vel = (Vector2(target.vel) + braced_velocity).limit_length(cap)
	target.impulse_time = maxf(float(target.get("impulse_time",0.0)),0.35)

func present_reclaim(amount: float, source: String) -> void:
	if source == "second_wind" or amount < 0.02 or elapsed < _reclaim_ready or paused or battle_status != "battle": return
	_reclaim_ready = elapsed+0.45
	add_power_fx("rpm_reclaim",player_entity().pos,Vector2.ZERO,amount)

func add_power_fx(kind: String, pos: Vector2, direction: Vector2 = Vector2.ZERO, strength: float = 1.0) -> void:
	var durations: Dictionary = {"impact_wake":0.40,"second_wind":0.64,"redline":0.28,"redline_release":0.32,"comet_charge":0.22,"comet_release":0.28,"afterimage":0.24,"chain_impact":0.38,
		"redline_ii":0.40,"runaway":0.44,"runaway_hit":0.30,"breakneck_charge":0.36,"breakneck_impact":0.45,"anchor":0.42,"anchor_break":0.30,"bulwark_impact":0.48,"counterweight_store":0.36,"counterweight_release":0.45,"afterimage_ii":0.24,"ghost_closure":0.48,"ghost_activation":0.60,"slipstream_cross":0.42}
	if kind in ["boss_entry","boss_defeat"]: durations[kind] = 0.75
	if kind == "breakneck_recovery": durations[kind] = 0.48
	if kind == "comet_release": durations[kind] = 0.40
	if kind == "clutch_recover": durations[kind] = 0.45
	if kind == "redline_overcap": durations[kind] = 0.25
	if kind == "ghost_preview": durations[kind] = 0.22
	if _presentation_full_contact and kind in ["breakneck_impact","bulwark_impact"] and continuous != null and battle_status == "battle" and elapsed >= _signature_ready:
		_signature_ready = elapsed+0.35
		_hit_stop = maxf(_hit_stop,SignatureVisuals.impact_hold("signature"))
		_shake_strength = SignatureVisuals.impact_shake("signature")
		_shake_time = 0.13
	if _power_fx.size() >= 32:
		var discard: int = 0
		for index: int in range(_power_fx.size()):
			if str(_power_fx[index].kind) != "second_wind":
				discard = index
				break
		_power_fx.remove_at(discard)
	var effect: Dictionary = {"kind":kind,"pos":pos,"dir":direction,"direction":direction,"strength":strength,"age":0.0,"duration":durations.get(kind,0.4)}
	if kind == "second_wind":
		for fighter: Dictionary in _ordered_fighters():
			if Vector2(fighter.pos).is_equal_approx(pos):
				effect["owner_entity_id"] = fighter.entity_id
				effect["phase"] = fighter.phase
				break
	_power_fx.append(effect)
	# Contact atlas accompanies the already throttled collision sound.
	if not kind.begins_with("contact_"): event_sfx.emit(kind)

func _resolve_small_pair(first: Dictionary, second: Dictionary) -> void:
	var a: Vector2 = first.pos
	var b: Vector2 = second.pos
	var difference: Vector2 = b-a
	var distance: float = difference.length()
	var reach: float = float(first.radius)+float(second.radius)
	if distance >= reach: return
	var normal: Vector2 = difference/distance if distance > 0.001 else Vector2.RIGHT
	var inv_a: float = powers.inverse_mass(first)
	var inv_b: float = powers.inverse_mass(second)
	var inv_sum: float = inv_a+inv_b
	first.pos = a-normal*(reach-distance+0.05)*inv_a/inv_sum
	second.pos = b+normal*(reach-distance+0.05)*inv_b/inv_sum
	var va: Vector2 = first.vel
	var vb: Vector2 = second.vel
	var closing: float = (va-vb).dot(normal)
	if closing <= 0.0: return
	var impulse: float = (1.65*closing+7.0)/inv_sum
	first.vel = (va-normal*impulse*inv_a).limit_length(400.0)
	second.vel = (vb+normal*impulse*inv_b).limit_length(400.0)
	for f: Dictionary in [first,second]:
		if f.combatant_type == "small_top": f.impulse_time = 0.4
	var key: String = "%d:%d" % [int(first.entity_id),int(second.entity_id)]
	if float(_pair_cooldowns.get(key,0.0)) > 0.0: return
	_pair_cooldowns[key] = 0.24
	var severity: float = clampf(closing/220.0,0.08,1.3)
	var attack_outputs: Dictionary = {
		int(first.entity_id): powers.attack_multiplier(first) * (1.43 if float(first.get("burst_time", 0.0)) > 0.0 else 1.0),
		int(second.entity_id): powers.attack_multiplier(second) * (1.43 if float(second.get("burst_time", 0.0)) > 0.0 else 1.0)}
	var rpm_outputs: Dictionary = {int(first.entity_id): powers.effective_rpm(first), int(second.entity_id): powers.effective_rpm(second)}
	powers.accepted_contact(first,second,severity,normal,a+normal*float(first.radius),Vector2(first.vel)-va,Vector2(second.vel)-vb,impulse/float(first.mass),impulse/float(second.mass))
	_progression_contact(first, second, severity)
	for pair: Array in [[first,second],[second,first]]:
		var target: Dictionary = pair[0]
		var source: Dictionary = pair[1]
		var loss: float = 0.0
		if target.combatant_type == "full_top":
			loss = minf(swarm.contact_budget,(0.004+severity*0.012)*0.20)
			swarm.contact_budget = maxf(0.0,swarm.contact_budget-loss)
			target.wobble = minf(1.0,float(target.wobble)+loss*3.1)
		elif source.combatant_type == "full_top":
			var attack: float = (0.66+float(source.stats.power)*0.073)*(0.45+float(rpm_outputs[int(source.entity_id)])*0.55)
			attack *= float(source.get("handling", {}).get("impact", 1.0))
			attack *= float(attack_outputs[int(source.entity_id)])
			loss = (0.045+severity*0.12)*attack
		elif not powers.cause_for(source).is_empty():
			loss = 0.01+severity*0.075
		else: loss = severity*0.004
		spend_rpm(target,loss,"collisions")
		target.energy = target.rpm
		target.impact_time = 0.12
		target.impact_strength = severity
	hits += 1
	contact_accepted.emit(int(first.entity_id),int(second.entity_id))
	# Swarm contacts never freeze the simulation; only important player contacts sound.
	if (first.owner_id == PLAYER_OWNER or second.owner_id == PLAYER_OWNER) and _contact_fx_cooldown <= 0.0:
		_contact_fx_cooldown = 0.12
		_spawn_sparks(project(a+normal*float(first.radius)),normal,4,severity*0.6)
		event_sfx.emit("small_hit")

func _resolve_boundary(fighter: Dictionary) -> void:
	var position_world: Vector2 = fighter["pos"]
	var in_gate_mouth: bool = absf(position_world.x + position_world.y) <= GATE_MOUTH_HALF_SUM
	if absf(position_world.x - position_world.y) > GATE_LIMIT and in_gate_mouth:
		fighter["outcome"] = "ring_out"
		return
	var velocity_world: Vector2 = fighter["vel"]
	var radius: float = float(fighter["radius"]) * 0.64
	var axis_limit: float = WALL_AXIS - radius
	var normals: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, Vector2(1.0, 1.0).normalized(), Vector2(-1.0, -1.0).normalized()]
	var distances: Array[float] = [axis_limit, axis_limit, axis_limit, axis_limit, (WALL_SUM - radius * 1.4) / sqrt(2.0), (WALL_SUM - radius * 1.4) / sqrt(2.0)]
	if not in_gate_mouth:
		normals.append(Vector2(1.0, -1.0).normalized())
		normals.append(Vector2(-1.0, 1.0).normalized())
		distances.append((GATE_LIMIT - radius * 1.4) / sqrt(2.0))
		distances.append((GATE_LIMIT - radius * 1.4) / sqrt(2.0))
	for index: int in range(normals.size()):
		var normal: Vector2 = normals[index]
		var overshoot: float = position_world.dot(normal) - distances[index]
		if overshoot <= 0.0:
			continue
		position_world -= normal * overshoot
		var outward: float = velocity_world.dot(normal)
		if outward > 0.0:
			velocity_world -= normal * outward * 1.66
			velocity_world *= 0.91
			spend_rpm(fighter,minf(0.019, outward * 0.000055),"walls")
			fighter["wobble"] = minf(1.0, float(fighter["wobble"]) + minf(0.16, outward * 0.00055))
			fighter["impact_time"] = 0.12
			fighter["impact_strength"] = 0.3
			powers.wall_rebound(fighter, outward, normal, position_world)
			if outward > 70.0 and fighter.combatant_type == "full_top":
				_spawn_sparks(project(position_world), -normal, 4, 0.6)
				event_sfx.emit("wall")
	fighter["pos"] = position_world
	fighter["vel"] = velocity_world
	fighter["energy"] = fighter["rpm"]

# Full-top objectives use team elimination. For a timeout (or simultaneous
# elimination), the highest remaining RPM wins; ties favor the lowest stable ID.
func _check_result() -> void:
	if continuous != null:
		if battle_status == "finished": return
		for f: Dictionary in fighters:
			if f.combatant_type == "full_top" and float(f.rpm) <= 0.045 and str(f.outcome).is_empty(): f.outcome = "spin_out"
		continuous.observe_outcomes()
		var player: Dictionary = player_entity()
		if not _is_live(player):
			powers.eliminated(player,str(player.outcome))
			_finish(0, str(player.outcome))
		return
	if battle_status == "finished":
		return
	if swarm.enabled:
		var player: Dictionary = player_entity()
		if float(player.rpm) <= 0.045 and str(player.outcome).is_empty(): player.outcome = "spin_out"
		if not str(player.outcome).is_empty():
			_finish(0,str(player.outcome))
		elif swarm.clear():
			_finish(player_entity_id,"swarm_clear")
		return
	var live_teams: Dictionary = {}
	var competitors: Array[Dictionary] = []
	for fighter: Dictionary in _ordered_fighters():
		if str(fighter["combatant_type"]) != "full_top" or str(fighter["team_id"]) == NEUTRAL_TEAM:
			continue
		competitors.append(fighter)
		if float(fighter["rpm"]) <= 0.045 and str(fighter["outcome"]).is_empty():
			fighter["outcome"] = "spin_out"
		if _is_live(fighter):
			live_teams[str(fighter["team_id"])] = true
	if competitors.is_empty():
		return
	# Runs prioritize confirmed player elimination. Quick Duel keeps its
	# historical simultaneous-elimination and stable-ID timeout tie behavior.
	if int(encounter.get("slot", 0)) > 0:
		var run_player: Dictionary = player_entity()
		var run_enemy: Dictionary = _hud_enemy()
		if not run_enemy.is_empty():
			if not _is_live(run_player):
				_finish(int(run_enemy.entity_id), str(run_player.outcome))
				return
			if elapsed >= live_time_limit and _is_live(run_enemy) and absf(float(run_player.rpm)-float(run_enemy.rpm)) <= 0.000001:
				_finish(int(run_enemy.entity_id), "draw")
				return
	var winner: Dictionary = {}
	if live_teams.size() <= 1 or elapsed >= live_time_limit:
		for fighter: Dictionary in competitors:
			if not live_teams.is_empty() and not _is_live(fighter):
				continue
			if winner.is_empty() or float(fighter["rpm"]) > float(winner["rpm"]):
				winner = fighter
		var reason: String = "timeout"
		if live_teams.size() <= 1:
			for loser: Dictionary in competitors:
				if str(loser["team_id"]) != str(winner["team_id"]) and not str(loser["outcome"]).is_empty():
					reason = str(loser["outcome"])
					break
		_finish(int(winner["entity_id"]), reason)

func _hud_enemy() -> Dictionary:
	if continuous != null:
		var rival: Dictionary = {}
		for f: Dictionary in fighters:
			if f.team_id != HOSTILE_TEAM or not _is_live(f) or f.combatant_type != "full_top": continue
			if f.get("enemy_kind","") == "boss": return f
			if rival.is_empty(): rival = f
		if not rival.is_empty(): return rival
	var player: Dictionary = player_entity()
	if player.is_empty():
		return {}
	var fallback: Dictionary = {}
	for candidate: Dictionary in _ordered_fighters():
		if not _opposes(player, candidate):
			continue
		if _is_live(candidate):
			return candidate
		if fallback.is_empty():
			fallback = candidate
	return fallback

func _finish(winner_entity_id: int, reason: String) -> void:
	if continuous != null and _is_live(player_entity()): return
	if battle_status == "finished":
		return
	var winner: Dictionary = entity(winner_entity_id)
	if winner.is_empty():
		if (swarm.enabled or continuous != null) and winner_entity_id == 0: winner = {"team_id":HOSTILE_TEAM}
		else: return
	battle_status = "finished"
	powers.finish()
	_finish_timer = 1.35 if reason == "ring_out" else 2.38
	for loser: Dictionary in _ordered_fighters():
		if loser.combatant_type == "small_top" and not str(loser.outcome).is_empty(): continue
		if not _opposes(winner, loser):
			continue
		loser["out_time"] = 0.0
		if str(loser["outcome"]) == "ring_out":
			loser["height_vel"] = 98.0
			_spawn_sparks(project(loser["pos"]), Vector2(loser["vel"]).normalized(), 12, 1.1)
		else:
			loser["outcome"] = "spin_out"
	event_sfx.emit("ring_out" if reason == "ring_out" else "spin_out")
	var player: Dictionary = player_entity()
	var enemy: Dictionary = _hud_enemy()
	var won: bool = str(winner["team_id"]) == PLAYER_TEAM
	# Legacy winner 0/1 is a team result for Quick Duel consumers, never an index.
	last_result = {"won": won, "winner": 0 if won else 1,
		"winner_entity_id": winner_entity_id, "winner_team_id": str(winner["team_id"]),
		"reason": reason, "player_remaining": float(player.get("rpm", 0.0)),
		"enemy_remaining": float(enemy.get("rpm", 0.0)), "duration": elapsed,
		"hits": hits, "seed": seed_value, "encounter_id": str(encounter.get("id", "")), "swarm":swarm.telemetry()}
	if continuous != null:
		last_result.merge(continuous.snapshot(), true)
		last_result["continuous_run"] = true
	_emit_hud()

func _update_finish(dt: float) -> void:
	_finish_timer -= dt
	for fighter: Dictionary in fighters:
		fighter["out_time"] = float(fighter["out_time"]) + dt
		var position_world: Vector2 = fighter["pos"]
		var velocity_world: Vector2 = fighter["vel"]
		if str(fighter["outcome"]) == "ring_out":
			position_world += velocity_world * dt * 0.68
			fighter["height_vel"] = float(fighter["height_vel"]) - 138.0 * dt
			fighter["height"] = float(fighter["height"]) + float(fighter["height_vel"]) * dt
		else:
			position_world += velocity_world * dt
			velocity_world *= exp(-3.5 * dt)
		fighter["pos"] = position_world
		fighter["vel"] = velocity_world
		var dying: bool = str(fighter["outcome"]) == "spin_out"
		var spin_speed: float = maxf(0.0, 9.0 - float(fighter["out_time"]) * 8.0) if dying else 9.0
		fighter["phase"] = fmod(float(fighter["phase"]) + dt * spin_speed, 8.0)
		if dying:
			fighter["wobble"] = maxf(0.0, 0.90 - float(fighter["out_time"]) * 0.5)
	if _finish_timer <= 0.0 and not _result_emitted:
		_result_emitted = true
		round_finished.emit(last_result.duplicate(true))

func _emit_hud() -> void:
	_hud_clock = 0.05
	var player: Dictionary = player_entity()
	var enemy: Dictionary = _hud_enemy()
	if player.is_empty(): return
	if enemy.is_empty(): enemy = {"rpm":0.0,"wobble":0.0,"name":"AMMUNITION WAVES","entity_id":0}
	var player_rpm: float = float(player["rpm"])
	var enemy_rpm: float = float(enemy["rpm"])
	var stats: Dictionary = {
		"rpm_recovery": continuous.economy.pulse_amount if continuous != null and elapsed < continuous.economy.pulse_until else 0.0,
		"rpm_recovery_source": continuous.economy.pulse_source if continuous != null else "",
		"player_rpm": player_rpm, "enemy_rpm": enemy_rpm,
		"player_stamina": player_rpm, "enemy_stamina": enemy_rpm,
		"player_rpm_value": int(player_rpm * 9000.0), "enemy_rpm_value": int(enemy_rpm * 9000.0),
		"burst_ready": float(player["cooldown"]) <= 0.0 and player_rpm >= 0.13,
		"burst_cooldown": float(player["cooldown"]), "burst_cooldown_max": BURST_COOLDOWN,
		"elapsed": elapsed, "time": elapsed, "time_left": maxf(0.0, live_time_limit - elapsed),
		"status": battle_status, "countdown": ceili(_countdown),
		"player_name": str(player["name"]), "enemy_name": str(enemy["name"]),
		"player_wobble": float(player["wobble"]), "enemy_wobble": float(enemy["wobble"]),
		"hits": hits, "paused": paused, "player_entity_id": int(player["entity_id"]),
		"enemy_entity_id": int(enemy["entity_id"]), "entity_count": fighters.size()
	}
	stats["is_swarm"] = swarm.enabled
	stats["swarm_wave"] = swarm.wave
	stats["swarm_total_waves"] = swarm.total_waves
	stats["swarm_active"] = swarm.active_count()
	stats["swarm_remaining"] = swarm.schedule.size()-swarm.spawned-swarm.cancelled
	if continuous != null:
		stats["continuous_run"] = true
		stats["run_state"] = continuous.snapshot()
	hud_updated.emit(stats)

func snapshot() -> Dictionary:
	var entities: Dictionary = {}
	for fighter: Dictionary in _ordered_fighters():
		entities[int(fighter["entity_id"])] = fighter.duplicate(true)
	return {"player": player_entity().duplicate(true), "enemy": _hud_enemy().duplicate(true),
		"entities": entities, "elapsed": elapsed, "status": battle_status,
		"active": battle_status == "battle", "paused": paused,
		"winner": last_result.get("winner", -1), "reason": last_result.get("reason", ""),
		"hits": hits, "result": last_result.duplicate(true), "swarm":swarm.telemetry()}

## Positional seam retained only for the Task 001 regression fixtures.
## New callers should use explicit entity IDs through test_set_entity_state.
func test_set_state(side: int, overrides: Dictionary) -> void:
	if side < 0 or side >= fighters.size():
		return
	test_set_entity_state(int(fighters[side]["entity_id"]), overrides)

func test_set_entity_state(entity_id: int, overrides: Dictionary) -> void:
	var fighter: Dictionary = entity(entity_id)
	if fighter.is_empty():
		return
	for key: Variant in overrides:
		if key not in ["entity_id", "team_id", "owner_id", "combatant_type"]:
			fighter[key] = overrides[key]
	if overrides.has("rpm"):
		fighter["energy"] = float(overrides["rpm"])
	queue_redraw()

func _spawn_sparks(screen_position: Vector2, world_normal: Vector2, count: int, strength: float) -> void:
	if not particles_enabled:
		return
	var direction: Vector2 = Vector2(world_normal.x - world_normal.y, (world_normal.x + world_normal.y) * 0.5).normalized()
	for index: int in range(count):
		var angle: float = _cosmetic_rng.randf_range(-PI, PI)
		var radial: Vector2 = Vector2(cos(angle), sin(angle))
		var velocity: Vector2 = radial * _cosmetic_rng.randf_range(22.0, 56.0 + strength * 27.0) + direction * _cosmetic_rng.randf_range(-15.0, 15.0)
		var life: float = _cosmetic_rng.randf_range(0.14, 0.34)
		_particles.append({"pos": screen_position, "vel": velocity, "life": life, "max_life": life, "color": Color("f3c36a") if index % 3 != 0 else Color("e3e8dc")})
	while _particles.size() > 120:
		_particles.pop_front()

func _spawn_ring(screen_position: Vector2, color: Color, duration: float) -> void:
	if _rings.size() >= 32: _rings.pop_front()
	_rings.append({"pos": screen_position, "life": duration, "max_life": duration, "color": color})

func _update_effects(dt: float) -> void:
	for index: int in range(_power_fx.size()-1,-1,-1):
		_power_fx[index].age += dt
		if float(_power_fx[index].age) >= float(_power_fx[index].duration): _power_fx.remove_at(index)
	for trace: Dictionary in powers.traces:
		if trace.has("presentation_circuit_age"): trace.presentation_circuit_age += dt
	if continuous != null and battle_status == "battle" and not paused and elapsed >= _low_rpm_ready:
		var player: Dictionary = player_entity()
		if not player.is_empty() and str(player.outcome).is_empty() and float(player.rpm) < 0.25:
			_low_rpm_ready = elapsed+4.0
			event_sfx.emit("low_rpm")
	_shake_time = maxf(0.0, _shake_time - dt)
	if _shake_time <= 0.0: _shake_strength = 0.0
	_shake_phase += dt * 81.0
	for index: int in range(_particles.size() - 1, -1, -1):
		var particle: Dictionary = _particles[index]
		particle["life"] = float(particle["life"]) - dt
		if float(particle["life"]) <= 0.0:
			_particles.remove_at(index)
			continue
		var velocity: Vector2 = particle["vel"]
		particle["pos"] = Vector2(particle["pos"]) + velocity * dt
		particle["vel"] = velocity + Vector2(0.0, 63.0) * dt
	for index: int in range(_rings.size() - 1, -1, -1):
		_rings[index]["life"] = float(_rings[index]["life"]) - dt
		if float(_rings[index]["life"]) <= 0.0:
			_rings.remove_at(index)

func _draw() -> void:
	var shake: Vector2 = Vector2.ZERO
	if screen_shake_enabled and _shake_time > 0.0:
		shake = Vector2(roundf(sin(_shake_phase) * _shake_strength), roundf(cos(_shake_phase * 1.31) * _shake_strength * 0.5))
	draw_set_transform(shake)
	for layer: String in ["backdrop", "structure", "surface", "markings", "rear_rim"]:
		var texture: Texture2D = _textures.get("arena/" + layer)
		if texture != null:
			draw_texture(texture, Vector2.ZERO)
	for entry: Dictionary in swarm.schedule:
		if entry.state == "telegraph":
			PowerVisuals.draw_spawn(self, project(swarm.PORTS[int(entry.port)]), clampf(1.0-(float(entry.ready)-swarm.local_time())/swarm.TELEGRAPH,0.0,1.0))
	if continuous != null and not continuous.pending.is_empty() and continuous.pending.kind != "swarm" and Vector2(continuous.pending.position).is_finite():
		var at: Vector2 = project(continuous.pending.position)
		SignatureVisuals.entry(self,at,continuous.pending.kind,float(continuous.pending.ready_at)-elapsed)
	for trace: Dictionary in powers.traces:
		var path: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in trace.get("points",[trace.a,trace.b]): path.append(project(point))
		PowerVisuals.draw_trace_path(self, trace, path)
		var circuit_path: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in trace.get("circuit_points", []): circuit_path.append(project(point))
		if circuit_path.size() >= 4: PowerVisuals.draw_circuit_field(self, trace, circuit_path)
	for fx: Dictionary in _power_fx:
		if not str(fx.kind) in SignatureVisuals.FOREGROUND: PowerVisuals.draw_effect(self, fx, project(fx.pos))
	# Every complete rig sorts by ground contact Y, with stable ID ties.
	var order: Array[Dictionary] = _ordered_fighters()
	for fighter: Dictionary in order:
		_draw_shadow(fighter)
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var depth_a: float = Vector2(a["pos"]).x + Vector2(a["pos"]).y
		var depth_b: float = Vector2(b["pos"]).x + Vector2(b["pos"]).y
		return int(a["entity_id"]) < int(b["entity_id"]) if depth_a == depth_b else depth_a < depth_b)
	for fighter: Dictionary in order:
		if float(fighter["height"]) < 23.0 or str(fighter["outcome"]) != "ring_out":
			_draw_fighter(fighter)
	for fx: Dictionary in _power_fx:
		if str(fx.kind) in SignatureVisuals.FOREGROUND: PowerVisuals.draw_effect(self,fx,project(fx.pos))
	_draw_particles()
	var foreground: Texture2D = _textures.get("arena/front_rim")
	if foreground != null:
		draw_texture(foreground, Vector2.ZERO)
	for fighter: Dictionary in fighters:
		if float(fighter["height"]) >= 23.0 and str(fighter["outcome"]) == "ring_out":
			_draw_fighter(fighter)
	draw_set_transform(Vector2.ZERO)

func _draw_shadow(fighter: Dictionary) -> void:
	if fighter.combatant_type == "small_top": return
	var grounded: Vector2 = project(fighter["pos"]).round()
	var height: float = float(fighter["height"])
	var shadow_scale: float = clampf(1.0 - maxf(0.0, height) / 70.0, 0.30, 1.0)
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(16):
		var angle: float = float(index) / 16.0 * TAU
		points.append((grounded + Vector2(cos(angle) * 15.0 * shadow_scale, sin(angle) * 6.0 * shadow_scale)).round())
	draw_colored_polygon(points, Color(0.04, 0.07, 0.10, 0.44 * shadow_scale))
	var side_color: Color = _team_color(fighter)
	side_color.a = 0.73
	var selected: PackedVector2Array = PackedVector2Array()
	for index: int in range(17):
		var angle: float = float(index) / 16.0 * TAU
		selected.append((grounded + Vector2(cos(angle) * 18.0, sin(angle) * 8.0)).round())
	draw_polyline(selected, side_color, 1.0)
	SignatureVisuals.marker(self,fighter,grounded,_visual_time)
	if fighter.get("enemy_kind","") in ["elite","boss"]:
		draw_arc(grounded-Vector2(0,15),23.0 if fighter.enemy_kind == "boss" else 19.0,PI,TAU,24,side_color,2.0)
		for index: int in range(3 if fighter.enemy_kind == "boss" else 1):
			draw_rect(Rect2(grounded+Vector2(-5+index*4,-42),Vector2(3,4)),side_color)


func _draw_fighter(fighter: Dictionary) -> void:
	if fighter.combatant_type == "small_top":
		PowerVisuals.draw_small(self, fighter, project(fighter.pos,fighter.height), _visual_time)
		return
	PowerVisuals.draw_aura(self, fighter, project(fighter.pos,fighter.height), _visual_time)
	var position_world: Vector2 = fighter["pos"]
	var height: float = float(fighter["height"])
	var contact: Vector2 = project(position_world, height).round()
	if contact.x < -55.0 or contact.x > 695.0 or contact.y < -55.0 or contact.y > 410.0:
		return
	var velocity_world: Vector2 = fighter["vel"]
	var velocity_screen: Vector2 = Vector2(velocity_world.x - velocity_world.y, (velocity_world.x + velocity_world.y) * 0.5)
	var lean: Vector2 = (velocity_screen / 78.0).limit_length(3.0)
	var wobble: float = float(fighter["wobble"])
	lean += Vector2(sin(_visual_time * 15.5 + float(int(fighter["entity_id"]) - 1) * 2.0), cos(_visual_time * 13.0)) * wobble * 4.5
	# Cosmetic body-only rhythms: contact pivot and collision geometry stay fixed.
	var identity: String = str(fighter.get("starter_id",""))
	if identity == "breaker": lean += velocity_screen.normalized() * (1.5 if float(fighter.burst_time)>0.0 else 0.5)
	elif identity == "bastion": lean *= 0.65
	elif identity == "vane": lean += velocity_screen.normalized().orthogonal()*sin(_visual_time*8.0)*0.7
	if float(fighter.rpm)<0.25: lean += Vector2(sin(_visual_time*19.0)*1.5,cos(_visual_time*11.0))
	lean = lean.limit_length(5.0).round()
	var build: Dictionary = fighter["build"]
	var stance: float = {"low": 3.0, "mid": 0.0, "high": -3.0}[build["ratchet"]]
	var phase: int = int(fighter["phase"]) % 8
	var pose: Dictionary = PowerVisuals.recovery_pose(fighter, _power_fx)
	if not pose.is_empty():
		phase = int(pose.phase)
		lean = pose.lean
		stance += float(pose.stance)
	var body_origin: Vector2 = contact - Vector2(24.0, 40.0)
	var player: bool = str(fighter["team_id"]) == PLAYER_TEAM
	var tint: Color = Color.WHITE if player else Color(1.0, 0.88, 0.72)
	if str(fighter["outcome"]) == "spin_out" and str(build["blade"]) == "balance" and str(build["ratchet"]) == "mid" and str(build["bit"]) == "ball":
		_draw_authored_spin_out(body_origin, float(fighter["out_time"]), tint)
		return
	var trail: Array = fighter["trail"]
	if float(fighter["burst_time"]) > 0.0 and trail.size() >= 2:
		var color: Color = _team_color(fighter)
		for index: int in range(trail.size() - 1):
			color.a = float(index + 1) / float(trail.size()) * 0.47
			draw_line(Vector2(trail[index]).round() - Vector2(0.0, 13.0), Vector2(trail[index + 1]).round() - Vector2(0.0, 13.0), color, 2.0)
	var bit_texture: Texture2D = _textures.get("bit/" + str(build["bit"]))
	var ratchet_texture: Texture2D = _textures.get("ratchet/" + str(build["ratchet"]))
	var blade_texture: Texture2D = _textures.get("blade/" + str(build["blade"]))
	if player:
		blade_texture = _textures.get("identity/" + str(fighter.get("starter_id", "custom")), blade_texture)
	if not player and str(build["blade"]) == "smash":
		blade_texture = _textures.get("rival/smash", blade_texture)
		if str(build["ratchet"]) == "low":
			ratchet_texture = _textures.get("rival/low", ratchet_texture)
		if str(build["bit"]) == "flat":
			bit_texture = _textures.get("rival/flat", bit_texture)
	if bit_texture != null:
		draw_texture(bit_texture, body_origin, tint)
	if ratchet_texture != null:
		draw_texture(ratchet_texture, body_origin + (lean * 0.55).round(), tint)
	if blade_texture != null:
		var blade_origin: Vector2 = body_origin + lean + Vector2(0.0, stance)
		var source: Rect2 = Rect2(float(phase) * 48.0, 0.0, 48.0, 48.0)
		draw_texture_rect_region(blade_texture, Rect2(blade_origin, Vector2(48.0, 48.0)), source, tint)
		if float(fighter["burst_time"]) > 0.0:
			var smear_tint: Color = _team_color(fighter)
			smear_tint.a = 0.17
			var smear_source: Rect2 = Rect2(float((phase + 7) % 8) * 48.0, 0.0, 48.0, 48.0)
			draw_texture_rect_region(blade_texture, Rect2(blade_origin - velocity_screen.normalized().round() * 2.0, Vector2(48.0, 48.0)), smear_source, smear_tint)
	if float(fighter["impact_time"]) > 0.0:
		var heavy: bool = float(fighter["impact_strength"]) > 0.50
		var duration: float = 0.30 if heavy else 0.18
		var impact_progress: float = clampf((duration - float(fighter["impact_time"])) / duration, 0.0, 0.999)
		var frame: int = (75 + int(impact_progress * 7.0)) if heavy else (70 + int(impact_progress * 5.0))
		_draw_sheet_fx(body_origin + lean, frame)
	elif float(fighter["burst_time"]) > 0.0:
		_draw_sheet_fx(body_origin + lean, 30 + phase)
	elif wobble > 0.65:
		_draw_sheet_fx(body_origin + lean, 90 + phase)
	# A tiny owner marker stays readable without enlarging the canonical rig.
	if str(fighter["outcome"]).is_empty():
		var color: Color = _team_color(fighter)
		draw_rect(Rect2(contact + Vector2(-2.0, -35.0 - maxf(0.0, -stance)), Vector2(5.0, 2.0)), color)

func _draw_sheet_fx(origin: Vector2, frame: int) -> void:
	var texture: Texture2D = _textures.get("fx")
	if texture == null:
		return
	var source: Rect2 = Rect2(float(frame % 12) * 48.0, floorf(float(frame) / 12.0) * 48.0, 48.0, 48.0)
	draw_texture_rect_region(texture, Rect2(origin.round(), Vector2(48.0, 48.0)), source)

func _draw_authored_spin_out(origin: Vector2, animation_time: float, tint: Color) -> void:
	var durations: Array[float] = [0.130, 0.150, 0.180, 0.210, 0.260, 0.330, 0.420, 0.650]
	var frame: int = 113
	var frame_time: float = 0.0
	for index: int in range(durations.size()):
		frame_time += durations[index]
		if animation_time < frame_time:
			frame = 106 + index
			break
	var source: Rect2 = Rect2(float(frame % 12) * 48.0, floorf(float(frame) / 12.0) * 48.0, 48.0, 48.0)
	for layer: String in ["bit", "ratchet", "blade"]:
		var texture: Texture2D = _textures.get("starter/" + layer)
		if texture != null:
			draw_texture_rect_region(texture, Rect2(origin, Vector2(48.0, 48.0)), source, tint)
	_draw_sheet_fx(origin, frame)

func _draw_particles() -> void:
	for ring: Dictionary in _rings:
		var t: float = 1.0 - float(ring["life"]) / float(ring["max_life"])
		var color: Color = ring["color"]
		color.a = (1.0 - t) * 0.85
		var points: PackedVector2Array = PackedVector2Array()
		var center: Vector2 = ring["pos"]
		var radius: float = 5.0 + t * 18.0
		for index: int in range(17):
			var angle: float = float(index) / 16.0 * TAU
			points.append((center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.5)).round())
		draw_polyline(points, color, 1.0)
	for particle: Dictionary in _particles:
		var color: Color = particle["color"]
		color.a = clampf(float(particle["life"]) / float(particle["max_life"]) * 1.3, 0.0, 1.0)
		var point: Vector2 = Vector2(particle["pos"]).round()
		var velocity: Vector2 = particle["vel"]
		draw_line(point, (point - velocity * 0.025).round(), color, 1.0)
