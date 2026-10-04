extends RefCounted
## Explicit outcome fixtures for UI/ownership regression only, never pacing proof.
static func resolve_threat(game: Node) -> void:
	var b: Node2D = game.battle
	b.battle_status = "battle"
	b._progression_contacted.clear()
	for f: Dictionary in b.fighters:
		if f.team_id != "hostile": continue
		f.player_cause = {}
		f.outcome = "natural_retirement" if f.combatant_type == "small_top" else "spin_out"
	if b.swarm.enabled:
		for entry: Dictionary in b.swarm.schedule:
			if entry.state != "spawned" and entry.state != "cancelled":
				entry.state = "cancelled"
				b.swarm.cancelled += 1
		b.swarm.wave = b.swarm.total_waves
	b._check_result()
	b._collect_progression_outcomes()
	b.continuous.after_tick(0.0)

static func next_threat(game: Node) -> void:
	resolve_threat(game)
	# Skip only the breath for screen fixtures; runtime tests exercise its clock.
	game.battle.continuous._spawn_next()

static func defeat_player(game: Node, reason: String = "spin_out") -> void:
	game.battle.battle_status = "battle"
	game.battle.player_entity().outcome = reason
	game.battle._check_result()
	game.battle._finish_timer = 0.0
	game.battle._update_finish(0.0)
