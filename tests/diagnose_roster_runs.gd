extends "res://tests/test_rpm_playthrough.gd"
## Natural draft preferences only. This controller never equips missing powers,
## edits reserve, removes enemies, blocks losses or overrides director admission.
const PROFILES: Dictionary = {
	"overclock":{"style":"aggressive","powers":["redline","high_gear","predator_line","impact_wake","clutch"],"mutation":"runaway"},
	"speed":{"style":"aggressive","powers":["high_gear","orbit_drive","afterimage","iron_comet","clutch"],"mutation":"terminal_velocity"},
	"defence":{"style":"defensive","powers":["dead_centre","crash_guard","clutch","momentum_bank","impact_wake"],"mutation":"counterweight"},
	"route":{"style":"hybrid","powers":["afterimage","high_gear","orbit_drive","clutch","crash_guard"],"mutation":"ghost_circuit"},
	"impact":{"style":"aggressive","powers":["iron_comet","impact_wake","chain_impact","momentum_bank","predator_line"],"mutation":"breakneck"},
	"comeback":{"style":"hybrid","powers":["clutch","crash_guard","dead_centre","impact_wake","crosscut"],"mutation":"bulwark"},
	"hybrid":{"style":"hybrid","powers":["orbit_drive","momentum_bank","high_gear","dead_centre","crosscut"],"mutation":"flow_state"}
}
var profile: String = "overclock"
const RouteBot = preload("res://tests/roster_route_bot.gd")
var draft_log: Array[Dictionary] = []
func controls(b: Node2D, playstyle: String, tick: int) -> Dictionary:
	if profile == "route": return RouteBot.input(b,tick)
	if profile not in ["route","speed","hybrid"]: return Bot.input(b,playstyle,tick)
	# Mobility still has to fight. Alternate pursuit with deliberate curved
	# brake-and-turn play instead of endlessly circling away from opponents.
	if profile in ["speed","hybrid"] and tick % 480 < 360:
		return Bot.input(b,playstyle,tick)
	var p: Dictionary = b.player_entity()
	var pos: Vector2 = p.pos
	var radial: Vector2 = pos.normalized() if pos.length() > 1.0 else Vector2.RIGHT
	var tangent: Vector2 = Vector2(-radial.y,radial.x)
	var pace: float = 145.0 if profile == "route" else 175.0
	var radius: float = 108.0
	var route: Vector2 = tangent*pace+radial*(radius-pos.length())*2.0
	var thrust: Vector2 = (route-Vector2(p.vel))*4.0+route*0.75-radial*(pace*pace/radius)
	var available: float = (123.0+float(p.stats.grip)*17.0)*float(p.handling.get("acceleration",1.0))
	var world: Vector2 = thrust.limit_length(available)/available
	var brake: bool = profile in ["speed","hybrid"] and "orbit_drive" in p.powers and tick%240 > 165 and tick%240 < 205
	var burst: bool = profile != "route" and float(p.cooldown) <= 0.0 and pos.length() < 145.0
	return {"direction":Vector2(world.x-world.y,(world.x+world.y)*0.5).normalized()*world.length(),"brake":brake,"burst":burst and not brake}
func choose(game: QuietMain) -> void:
	var preferences: Array = PROFILES[profile].powers
	var offers: Array = game.run_context.pending_offer
	var choice: String = str(offers[0])
	var best: float = -INF
	for id: String in offers:
		var index: int = preferences.find(id)
		var score: float = 10.0-float(index) if index >= 0 else 0.0
		var rank: int = int(game.run_context.power_ranks.get(id,0))
		if rank > 0 and index >= 0: score += 8.0+float(rank)*2.0
		if score > best: best = score; choice = id
	var rank: int = int(game.run_context.power_ranks.get(choice,0))
	var claim: String = game.run_context.pending_draft_id
	var branch: String = ""
	game._action("choose_power",{"encounter_id":claim,"power_id":choice,"run_seed":game.run_context.run_seed})
	if game.screen == "mutation":
		branch = str(PROFILES[profile].mutation)
		if branch not in game.run_context.pending_mutation_offer: branch = str(game.run_context.pending_mutation_offer[0])
		game._action("choose_mutation",{"encounter_id":claim,"branch_id":branch,"run_seed":game.run_context.run_seed})
	draft_log.append({"id":claim,"time":game.battle.elapsed if is_instance_valid(game.battle) else 0.0,"power":choice,"rank":rank+1,"mutation":branch,"offers":offers})
	game._process(1.1)
func _run() -> void:
	var wanted: Array = PROFILES.keys()
	var seeds: Array = [421,7341]
	var starters: Array = Starters.IDS
	var output: String = "user://task002c5-natural.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--profiles="): wanted = Array(arg.trim_prefix("--profiles=").split(","))
		if arg == "--quick": seeds = [421]
		if arg.begins_with("--seed="): seeds = [int(arg.trim_prefix("--seed="))]
		if arg.begins_with("--starters="): starters = Array(arg.trim_prefix("--starters=").split(","))
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
		if arg.begins_with("--ceiling="): sample_limit = clampf(float(arg.trim_prefix("--ceiling=")),60.0,LIMIT)
	report["diagnostic_ceiling_seconds"] = sample_limit
	for name: String in wanted:
		profile = name; style = str(PROFILES[name].style); override_power = str(PROFILES[name].powers[0])
		for starter: String in starters:
			for seed_id: int in seeds:
				draft_log.clear()
				var row: Dictionary = play(starter,seed_id)
				row["profile"] = name; row["drafts"] = draft_log.duplicate(true)
				report.runs.append(row)
				var file = FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify(report)); file.close()
				print("ROSTER_NATURAL %s %s seed=%d seconds=%.2f level=%d families=%d mutations=%d death=%s overcap=%.2fs peak=%.3f clutch=%d" % [name,starter,seed_id,row.survival_time,row.level,row.powers.size(),row.mutations.size(),row.reason,float(row.redline.get("overcap_seconds",0.0)),float(row.redline.get("max_overcap",0.0)),int(row.power_procs.get("clutch_recover",0))])
	print("ROSTER_NATURAL_DONE samples=",report.runs.size())
	quit()
