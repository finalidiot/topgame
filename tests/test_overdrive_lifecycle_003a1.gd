extends "res://tests/test_input_acceptance_003a1.gd"
## Ordinary Main and keyboard UI. Only a wallet/assembly and earned-XP events
## are labelled fixtures. The seed is searched for real legal Redline offers.
const Run = preload("res://scripts/run_context.gd")
var legacy: bool = false
var redline_rows: Array = []
var next_fixture_id: int = 60000
var expected_runtime_id: int = 0
var baseline_active: Dictionary = {}
var last_emitted_hud: Dictionary = {}

func redline_state() -> Dictionary:
	var player: Dictionary = game.battle.player_entity()
	if player.is_empty(): return {}
	return {"owned":game.battle.powers.rank(player,"redline") > 0,"active":game.battle.powers.redline_active(player),
		"remaining":float(player.get("redline_time",0.0)),"heat":float(player.get("redline_heat",0.0)),"rpm":float(player.rpm),
		"runtime_time":game.battle.powers.time,"active_rank":game.battle.powers.active_redline_rank(player),
		"owned_rank":game.battle.powers.rank(player,"redline"),"runtime_id":game.battle.powers.get_instance_id()}
func sample(label: String) -> void:
	var state: Dictionary = redline_state()
	var row: Dictionary = {"frame":frame(),"phase":phase,"label":label,"screen":game.screen,"menu":game.menus.screen,"redline":state,
		"suspended":game.get("_application_suspended"),"battle_phase":game.battle.battle_status,"elapsed":game.battle.elapsed,"paused":game.battle.paused}
	if game.menus.screen == "hud":
		row["rpm_text"] = str(game.menus._hud.player_rpm.text)
		row["active_badge"] = row.rpm_text.contains("OVERDRIVE")
		var display_active: bool = bool(last_emitted_hud.get("redline_active",false)) or float(last_emitted_hud.get("player_rpm",0.0)) > 1.0
		row["expected_display_active"] = display_active
		row["hud_snapshot_age_seconds"] = float(state.get("runtime_time",0.0)) - float(last_emitted_hud.get("lifecycle_runtime_time",state.get("runtime_time",0.0)))
		if not state.is_empty():
			check(bool(row.active_badge) == display_active,"Actual OVERDRIVE badge follows the authoritative emitted active/excess state")
			check(float(row.hud_snapshot_age_seconds) <= 0.067,"The normal HUD refresh stays within its three-to-four fixed-tick cadence")
		if game.menus._hud.has("state_meters"):
			var snapshot: Dictionary = game.menus._hud.state_meters.diagnostic_snapshot()
			var display: Array = snapshot.rows.right.filter(func(item: Dictionary) -> bool: return item.id == "redline")
			row["persistent_redline_rows"] = display
			if not state.is_empty():
				check(not display.is_empty() if state.owned else display.is_empty(),"Owned REDLINE / HEAT row survives every HUD rebuild and real expiry")
				if not display.is_empty(): check(bool(display[0].active) == display_active,"State-meter active badge agrees with actual emitted runtime")
		elif not legacy: check(false,"Candidate HUD contains its new persistent state display")
	redline_rows.append(row)
func fixture_event(run: RefCounted, id: int) -> Dictionary:
	return {"kind":"elimination","encounter_id":str(run.current_encounter().id),"time":1.0,
		"entity_id":id,"combatant_type":"full_top","reason":"spin_out","player_attributed":true}
func candidate_seed() -> int:
	for candidate: int in range(1,4001):
		var rng := RandomNumberGenerator.new(); rng.seed = candidate
		var run := Run.new(); run.start(game.collection.equipped_build(),rng.randi(),"bastion")
		if not "redline" in run.pending_offer: continue
		run.choose_power(run.pending_draft_id,"redline")
		run.award_xp(fixture_event(run,1))
		if not "redline" in run.pending_offer: continue
		run.choose_power(run.pending_draft_id,"redline")
		for id: int in range(2,5):
			run.award_xp(fixture_event(run,id))
			if not run.pending_offer.is_empty(): break
		if "redline" in run.pending_offer: return candidate
	return 0
func live_draft() -> void:
	for index: int in range(8):
		var event: Dictionary = fixture_event(game.run_context,next_fixture_id)
		next_fixture_id += 1; event.time = game.battle.elapsed
		events.append({"frame":frame(),"type":"earned_xp_fixture","event":event})
		game._progression_events([event])
		if game.screen == "level_up": break
	check(game.screen == "level_up","Labelled earned-XP event enters the actual level-up flow")
	await wait_for("reward")
func owned_button(id: String) -> Control:
	for node: Node in descendants(game.menus):
		if node is Button and str(node.get_meta("power_id","")) == id and str(node.get_meta("intent","")) == "choose_power": return node
	return null
func frozen(label: String, expected: Dictionary) -> void:
	var now: Dictionary = redline_state()
	check(is_equal_approx(float(now.runtime_time),float(expected.runtime_time)) and is_equal_approx(float(now.remaining),float(expected.remaining)),label + " preserves the real paid activation timer")
	check(now.runtime_id == expected.runtime_id and bool(now.active) == bool(expected.active),label + " keeps the same live runtime and paid active state")
	sample(label)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg.begins_with("--profiles="): profiles_path = arg.trim_prefix("--profiles=")
		if arg == "--legacy": legacy = true
		if unsafe_main_argument(arg): refuse_arguments("Unsafe Main boot override refused before opening any profile."); return
	if not guard_fixture_paths(): return
	DirAccess.make_dir_recursive_absolute(profiles_path)
	root.size = Vector2i(640,360); root.content_scale_size = Vector2i(640,360)
	Input.use_accumulated_input = false; start_frame = Engine.get_process_frames(); capture_group = "overdrive"
	await boot("keyboard")
	game.battle.hud_updated.connect(func(stats: Dictionary) -> void:
		if game.screen == "battle" and game.menus.screen == "hud":
			last_emitted_hud = stats.duplicate(true)
			last_emitted_hud["lifecycle_runtime_time"] = game.battle.powers.time)
	var initial_rng_seed: int = candidate_seed()
	check(initial_rng_seed > 0,"Found actual deterministic Redline start/rank/mutation offers")
	game.rng.seed = initial_rng_seed
	await intent("start_run")
	check("redline" in game.run_context.pending_offer,"Real starting offer contains Redline")
	await activate(owned_button("redline"))
	await wait_for("battle","battle")
	await tap_key(KEY_SPACE)
	baseline_active = redline_state()
	expected_runtime_id = int(baseline_active.runtime_id)
	check(baseline_active.active and baseline_active.remaining > 2.8,"An actual reserve-paid Burst activates Redline")
	phase = "paid_redline"; sample("paid_redline")
	await live_draft()
	var paused: Dictionary = redline_state()
	await wait_frames(20); frozen("rank_draft",paused)
	await activate(owned_button("redline"))
	check(game.screen == "acquisition" and game.run_context.power_ranks.redline == 2,"Real rank selection acquires Redline II")
	frozen("rank_acquisition",paused)
	await wait_for("battle","reentry"); frozen("rank_ready",paused)
	await wait_for("battle","battle"); frozen("rank_go",paused)
	check(game.battle.powers.active_redline_rank(game.battle.player_entity()) == 1,"A paid Rank I activation retains its paid profile through the investment")
	await live_draft(); paused = redline_state()
	await activate(owned_button("redline"))
	check(game.screen == "mutation","The actual next-rank choice enters mutation selection")
	await wait_frames(20); frozen("mutation_draft",paused)
	await intent("choose_mutation")
	check(game.screen == "acquisition" and game.run_context.power_ranks.redline == 3,"Actual mutation selection claims Rank III")
	frozen("mutation_acquisition",paused)
	await wait_for("battle","reentry"); frozen("mutation_ready",paused)
	await wait_for("battle","battle"); frozen("mutation_go",paused)
	await live_draft(); paused = redline_state()
	await intent("choose_power")
	check(game.run_context.owned_power_ids.size() == 2,"Actual additional card adds another power to the same runtime")
	await wait_for("battle","reentry"); frozen("other_power_ready",paused)
	await wait_for("battle","battle"); frozen("other_power_go",paused)
	await tap_key(KEY_ESCAPE)
	paused = redline_state(); await wait_frames(20); frozen("pause",paused)
	await intent("settings"); await wait_frames(20); frozen("pause_settings",paused)
	await intent("back_settings"); await intent("resume")
	await wait_for("battle","reentry"); frozen("pause_ready",paused)
	await wait_for("battle","battle"); frozen("pause_go",paused)
	phase = "actual_expiry"
	for index: int in range(400):
		if not game.battle.powers.redline_active(game.battle.player_entity()): break
		await wait_frames(1)
	await wait_frames(4)
	check(not game.battle.powers.redline_active(game.battle.player_entity()),"The actual activation eventually expires in live gameplay")
	sample("expired_owned_redline")
	phase = "threat_transition"
	var threat_before: int = game.run_context.slot
	for index: int in range(4000):
		if game.screen == "reward": await intent("choose_power")
		elif game.screen == "mutation": await intent("choose_mutation")
		if game.run_context.slot > threat_before and game.screen == "battle": break
		await wait_frames(1)
	check(game.run_context.slot > threat_before,"The natural Director starts a later threat during the lifecycle observation")
	await wait_frames(4); sample("next_threat")
	check(game.battle.powers.get_instance_id() == expected_runtime_id,"Threat entry preserves the same authoritative runtime")
	await tap_key(KEY_SPACE)
	check(game.battle.powers.redline_active(game.battle.player_entity()),"A fresh real Burst uses the invested Redline profile before the death fixture")
	var player: Dictionary = game.battle.player_entity()
	events.append({"frame":frame(),"type":"ring_out_position_fixture","position":[180,-180],"velocity":[50,-50],"scope":"Accepted terminal/HUD lifecycle only; no survival or balance claim"})
	player.pos = Vector2(180,-180); player.vel = Vector2(50,-50)
	await wait_frames(4)
	check(game.battle.battle_status == "finished" and not game.battle.powers.redline_active(player),"Actual ring-out evaluation ends the paid activation on death")
	sample("actual_terminal_after_ring_out_fixture")
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures == 0,"legacy":legacy,"initial_rng_seed":initial_rng_seed,
		"scope":"Normal Main, actual keyboard UI/paid Burst/acquisition/READY timers; assembly/wallet, elimination-XP events, and one final ring-out position are explicit QA fixtures. Real legal offers found by deterministic seed search. No forced activation timers/ranks, no mouse input, no fabricated survival or physical acceptance.",
		"rows":redline_rows,"input_events":events,"old_active_disappearance_reproduced":redline_rows.any(func(row: Dictionary) -> bool: return row.has("active_badge") and bool(row.get("expected_display_active",false)) and not bool(row.active_badge)),
		"old_owned_state_after_expiry_hidden":legacy and redline_rows.any(func(row: Dictionary) -> bool: return row.label == "expired_owned_redline" and bool(row.redline.owned) and not bool(row.active_badge))},"\t")); file.close()
	print("OVERDRIVE_LIFECYCLE_%s checks=%d failures=%d report=%s" % ["PASS" if failures == 0 else "FAIL",checks,failures,report_path])
	game.sounds.muted = true
	for channel: AudioStreamPlayer in game.sounds.channels: channel.stop()
	game.queue_free(); await wait_frames(8); OS.delay_msec(150)
	quit(1 if failures else 0)
