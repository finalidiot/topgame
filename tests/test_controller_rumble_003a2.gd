extends SceneTree
## Mock requests are inspectable output, never physical motor confirmation.
## Persistence uses only the explicit external QA --out directory.
const Rumble = preload("res://scripts/controller_rumble.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
const Feedback = preload("res://scripts/combat_impact_feedback.gd")
const Battle = preload("res://scripts/battle.gd")
const Main = preload("res://scripts/main.gd")
const Encounters = preload("res://scripts/encounters.gd")
var checks: int = 0
var failures: Array[String] = []
var report: Dictionary = {}
var out: String = ""
var source_before: Dictionary = {}
const SOURCE_FILES: Array[String] = ["controller_rumble","controller_bindings","combat_impact_feedback","battle","main","base_power_runtime","power_runtime","run_powers","defence_runtime","roster_runtime","continuous_run","spin_economy","encounters","seed_utils","parts"]

class MockOutput extends RefCounted:
	var devices: Dictionary = {0:true,3:true,7:false}
	var calls: Array[Dictionary] = []
	func connected(device: int) -> bool: return devices.has(device)
	func supported(device: int) -> bool: return bool(devices.get(device,false))
	func start(device: int,weak: float,strong: float,duration: float) -> void:
		calls.append({"device":device,"weak":weak,"strong":strong,"duration":duration})
	func stop(device: int) -> void: calls.append({"stop":device})
	func starts() -> Array:
		return calls.filter(func(row: Dictionary) -> bool: return row.has("duration"))

func _initialize() -> void:
	for file: String in SOURCE_FILES: source_before[file] = FileAccess.get_sha256("res://scripts/"+file+".gd")
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func make(active: bool = true) -> Node:
	var r: Node = Rumble.new()
	r.output = MockOutput.new()
	r.configure({"controller_rumble":true,"rumble_intensity":1.0})
	r.set_active_device(3)
	r.set_gameplay_active(active)
	return r
func event(id: int,severity: float = 0.5) -> Dictionary:
	return {"collision_id":id,"severity":severity,"closing":severity*220.0,"impulse":500.0,
		"first_entity_id":1,"second_entity_id":2,"first_player":true,"second_player":false,
		"first_normal_speed":160.0,"second_normal_speed":40.0,"first_effective_mass":10.0,"second_effective_mass":10.0,
		"position":Vector2.ZERO}
func pulses(r: Node) -> Array:
	return r.snapshot().history.filter(func(row: Dictionary) -> bool: return row.has("profile"))
func latest(r: Node) -> String:
	var rows: Array = pulses(r)
	return "" if rows.is_empty() else str(rows[-1].profile)
func isolated_path(name: String) -> String:
	var task_root: String = out.get_base_dir()
	if task_root.get_file() == "manifests": task_root = task_root.get_base_dir()
	var folder: String = task_root.path_join("temp/rumble")
	DirAccess.make_dir_recursive_absolute(folder)
	return folder.path_join(out.get_file().get_basename()+"_"+name)

func routing_and_profiles() -> void:
	Bindings.configure("auto")
	var r: Node = make()
	check(r.accept_impact(event(1)),"Supported nonzero active slot accepts normal contact")
	check(r.output.starts().size() == 1 and r.output.starts()[0].device == 3,"Only active slot 3 receives output; connected slot 0 stays silent")
	var before: int = pulses(r).size()
	check(not r.accept_impact(event(1)) and pulses(r).size() == before,"Accepted collision identity deduplicates")
	r.update(0.4)
	var unrelated: Dictionary = event(2); unrelated.first_player = false
	check(not r.accept_impact(unrelated),"Unrelated enemy contact produces no controller pulse")
	var pad := InputEventJoypadMotion.new(); pad.device = 0; pad.axis = JOY_AXIS_LEFT_X; pad.axis_value = 0.5
	r._input(pad)
	check(r.active_device == 0 and not r.snapshot().output_live,"Meaningful controller input changes ownership and clears output")
	pad.device = 3; pad.axis_value = 0.10; r._input(pad)
	check(r.active_device == 0,"Neutral stick noise cannot steal active ownership")
	pad.axis_value = 0.6; r._input(pad)
	check(r.active_device == 3,"Nonzero slot can reclaim control")
	var key := InputEventKey.new(); key.physical_keycode = KEY_SPACE; key.pressed = true; r._input(key)
	check(r.active_device == -1 and not r.accept_impact(event(3)),"Keyboard action retires rumble ownership")
	r._input(pad)
	var finger := InputEventScreenTouch.new(); finger.pressed = true; r._input(finger)
	check(r.active_device == -1,"Touch intent retires rumble ownership without phone vibration")
	r.set_active_device(7)
	var count: int = r.output.starts().size()
	check(not r.accept_impact(event(4)) and r.output.starts().size() == count,"Connected unsupported driver silently falls back")
	check(r.test_pulse() == "This connection reports no rumble support.","Explicit test reports support fallback without hardware claims")
	r.set_active_device(3); r.accept_impact(event(5)); r.output.devices.erase(3); r.connection_changed(3,false)
	check(r.active_device == -1 and not r.snapshot().output_live,"Disconnect stops and retires current ownership")
	r.output.devices[3] = true; r.connection_changed(3,true)
	check(r.active_device == -1,"Reconnect never restores stale ownership")
	r._input(pad); check(r.active_device == 3,"Fresh controller input reclaims reconnected slot")
	r.set_focus(false); pad.device = 0; r._input(pad)
	check(r.active_device == 0 and not r.snapshot().output_live,"Desktop focus re-engagement observes the new owner before output can resume")
	r._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	pad.device = 3; r._input(pad); r._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(r.active_device == 0 and not r.snapshot().focused,"Android background remains stopped despite focus/input until OS resume")
	r._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(r.snapshot().focused,"Actual application resume permits fresh feedback")
	r.free()
	var rows: Array = []
	for name: String in ["light","normal","hard_delivered","hard_received","brace","extreme"]:
		r = make()
		var e: Dictionary = event(1,0.08 if name == "light" else (0.5 if name == "normal" else 0.95))
		if name == "hard_received": e.first_normal_speed = 20.0; e.second_normal_speed = 180.0
		if name == "brace": e.first_absorption = 0.2
		if name == "extreme": e.closing = 250.0; e.impulse = 4000.0
		var unchanged: Dictionary = e.duplicate(true)
		check(r.accept_impact(e) and latest(r) == name,"Actual severity and attribution select "+name)
		check(e == unchanged,"Feedback does not edit accepted solver event")
		rows.append(pulses(r)[0])
		for tick: int in range(40): r.update(0.01)
		check(not r.snapshot().output_live and r.snapshot().pulse.is_empty(),"Finite envelope completes: "+name)
		for request: Dictionary in r.output.starts():
			check(request.device == 3 and request.duration > 0.0 and request.duration <= Rumble.SEGMENT and request.weak <= 1.0 and request.strong <= 1.0,"Finite clamped request at output boundary")
		r.free()
	check(maxf(rows[0].weak,rows[0].strong) < maxf(rows[1].weak,rows[1].strong) and maxf(rows[1].weak,rows[1].strong) < maxf(rows[2].weak,rows[2].strong) and maxf(rows[3].weak,rows[3].strong) < maxf(rows[5].weak,rows[5].strong),"Light, normal, hard and extreme have an increasing intensity hierarchy")
	check(rows[2].strong < rows[3].strong and rows[2].duration < rows[3].duration,"Delivered hit is concise; received hit has heavier body")
	report.event_profiles = rows

func mixing_and_lifecycle() -> void:
	var r: Node = make()
	r.accept_impact(event(1)); r.update(0.10)
	check(not r.accept_impact(event(2)),"Ordinary impacts leave a quiet gap instead of joining into a continuous buzz")
	r.update(0.06)
	check(r.accept_impact(event(3)),"A fresh accepted contact can pulse after the quiet gap")
	r.free(); r = make()
	r.accept_impact(event(1))
	var hard: Dictionary = event(2,0.9); hard.second_normal_speed = 180.0; hard.first_normal_speed = 20.0
	check(r.accept_impact(hard) and latest(r) == "hard_received","Higher-priority impact preempts a normal pulse")
	var original_start: float = r.snapshot().pulse.started
	for id: int in range(3,200): r.accept_impact(event(id,0.5))
	check(pulses(r).size() == 2 and float(r.snapshot().pulse.started) == original_start and r.snapshot().queue_size == 0,"Collision chatter neither stacks nor restarts strong output; no backlog")
	r.update(0.4)
	check(r.snapshot().pulse.is_empty() and not r.snapshot().output_live,"Chatter cannot extend a completed pulse")
	for index: int in range(200,600):
		r.accept_impact(event(index,0.95)); r.update(0.01)
	check(pulses(r).size() < 25 and r.snapshot().work_credit >= 0.0,"Per-source cooldown, priority and magnitude-time credit bound impact workload")
	check(r.snapshot().history.size() <= Rumble.MAX_HISTORY,"Telemetry history stays bounded")
	r.free()
	for reason: String in ["pause","draft","menu","background","ownership","disconnect","run_reset","teardown","quit"]:
		r = make(); r.accept_impact(event(1))
		match reason:
			"background": r.set_focus(false)
			"ownership": r.set_active_device(0)
			"disconnect": r.connection_changed(3,false)
			"run_reset": r.reset()
			_: r.clear(reason)
		check(not r.snapshot().output_live and r.snapshot().pulse.is_empty() and r.snapshot().grind_level == 0.0,"Lifecycle clears active feedback immediately: "+reason)
		r.set_gameplay_active(true); r.set_focus(true); r.update(0.3)
		check(not r.snapshot().output_live and r.snapshot().queue_size == 0,"Resume never replays prior events: "+reason)
		r.free()
	r = make(); r.configure({"controller_rumble":false,"rumble_intensity":1.0})
	check(r.test_pulse() == "Rumble is Off." and r.output.starts().is_empty(),"Test button cannot bypass Off")
	r.configure({"controller_rumble":true,"rumble_intensity":0.55}); r.set_gameplay_active(false)
	check(r.test_pulse().begins_with("Short rumble requested") and latest(r) == "test","Explicit test works in a menu and describes a request only")
	r.configure({"controller_rumble":false,"rumble_intensity":0.55})
	check(not r.snapshot().output_live,"Disabling stops an explicit test immediately")
	r.free()
	report.routing_and_lifecycle = {"active_nonzero_slot":3,"unsupported_slot":7,"lifecycle_reasons":["pause","draft","menu","background","ownership","disconnect","run_reset","teardown","quit"],"queue_capacity":0,"history_capacity":Rumble.MAX_HISTORY}

func grind_and_actions() -> void:
	var f: RefCounted = Feedback.new()
	var player: Dictionary = {"entity_id":1,"combatant_type":"full_top","outcome":"","rpm":1.0,"pos":Vector2(-12,0),"vel":Vector2(0,100),"radius":12.0,"height":0.0}
	var enemy: Dictionary = player.duplicate(true); enemy.entity_id = 2; enemy.pos = Vector2(12,0); enemy.vel = Vector2.ZERO
	for tick: int in range(12): f.observe_grinding([player,enemy],1.0/60.0)
	check(f.grind_snapshot_for(1).active,"Player's genuine sustained tangential contact produces grind")
	check(not f.grind_snapshot_for(7).active,"Enemy-only grind is excluded from active-player feedback")
	var r: Node = make()
	for tick: int in range(6): r.observe_grind(f.grind_snapshot_for(1)); r.update(0.02)
	check(r.snapshot().output_live and r.output.starts().size() > 0,"Quiet grind attacks smoothly through finite renewed segments")
	for request: Dictionary in r.output.starts(): check(maxf(request.weak,request.strong) <= 0.11,"Grind stays below light/normal impacts")
	var e: Dictionary = event(1,0.9); e.second_normal_speed = 180.0; e.first_normal_speed = 20.0
	r.accept_impact(e)
	check(latest(r) == "hard_received" and r.output.starts()[-1].strong == 0.8,"Major impact suppresses the low-priority grind mix")
	r.clear("fixture_reset")
	for tick: int in range(6): r.observe_grind({"active":true,"strength":1.0}); r.update(0.02)
	r.observe_grind({"active":false,"strength":0.0}); r.update(0.08)
	check(not r.snapshot().output_live and r.snapshot().grind_level == 0.0,"Contact ending releases and stops grind promptly")
	r.observe_grind({"active":true,"strength":1.0}); r.update(0.04); r.update(0.16)
	check(not r.snapshot().output_live,"Missing contact refresh fails safe instead of maintaining motors")
	r.free()
	var b: Node2D = Battle.new(); root.add_child(b); b.visible = false; b.set_physics_process(false)
	b.begin({"blade":"lopsider","ratchet":"flywheel","bit":"needle"},{"blade":"guard","ratchet":"low","bit":"ball"},1,421)
	b.battle_status = "battle"
	r = make()
	b.controller_feedback.connect(r.accept_event)
	b.full_top_impact_accepted.connect(r.accept_impact)
	b.feedback_lifecycle.connect(func(_reason: String) -> void: r.clear(_reason))
	b._attempt_burst(b.player_entity(),Vector2.RIGHT)
	check(latest(r) == "burst" and pulses(r).size() == 1,"Only the production accepted player Burst emits a thrust pulse")
	b._attempt_burst(b.player_entity(),Vector2.RIGHT)
	b._attempt_burst(b.entity(2),Vector2.LEFT)
	check(pulses(r).size() == 1,"Cooldown rejection and NPC Burst emit no player rumble")
	b.set_paused(true)
	check(not r.snapshot().output_live,"Production Pause signal clears feedback immediately")
	b.begin({"blade":"balance","ratchet":"mid","bit":"ball"},{"blade":"guard","ratchet":"low","bit":"ball"},1,421)
	check(not r.snapshot().output_live,"Production encounter reset clears feedback")
	var emitted: Array[Dictionary] = []
	b.controller_feedback.connect(func(value: Dictionary) -> void: emitted.append(value.duplicate(true)))
	for power_id: String in ["impact_sink","anchor_exchange"]:
		b.begin_encounter({"blade":"balance","ratchet":"mid","bit":"ball"},{"opponent_build":{"blade":"guard","ratchet":"low","bit":"ball"},"seed":421,"ability_rebalance":true,"player_power_ids":[power_id],"player_power_ranks":{power_id:2}})
		b.battle_status = "battle"
		var p: Dictionary = b.player_entity(); var opponent: Dictionary = b.entity(2)
		p.pos = Vector2(-10,0); p.vel = Vector2.ZERO
		opponent.pos = Vector2(10,0); opponent.vel = Vector2(-180,0)
		if power_id == "anchor_exchange": b.powers.defence.state(p).brace = 0.8
		r.reset(); r.set_gameplay_active(true)
		b.resolve_pair(1,2)
		check(b.hits == 1 and latest(r) == "brace","Production heavy hit reports actual accepted absorption: "+power_id)
		var contact_pulses: int = pulses(r).size()
		b.resolve_pair(1,2)
		check(pulses(r).size() == contact_pulses,"Suppressed physical contact cannot duplicate a controller pulse")
		# The physical pose/brace is an explicit fixture. The attribution below
		# is the production accepted contact cause, rather than an injected owner.
		opponent.outcome = "ring_out"
		b._present_elimination(opponent)
		check(emitted[-1].kind == "takedown" and emitted[-1].player_attributed and latest(r) == "takedown","Production accepted player contact attributes the enemy finishing beat")
		var finish_pulses: int = pulses(r).size(); b._present_elimination(opponent)
		check(pulses(r).size() == finish_pulses,"Production elimination renderer deduplicates finishing output")
		var other: Dictionary = opponent.duplicate(true); other.entity_id = 99; other.erase("player_cause")
		b._present_elimination(other)
		check(not emitted[-1].player_attributed and pulses(r).size() == finish_pulses,"Production unrelated enemy elimination stays silent")
		other.entity_id = 100
		b._progression_contacted[100] = true
		b._feedback_credits[100] = b.elapsed-Battle.FEEDBACK_CREDIT_SECONDS-0.1
		b._present_elimination(other)
		check(not emitted[-1].player_attributed and pulses(r).size() == finish_pulses,"Expired presentation credit stays silent even if historical XP assist membership remains")
	b.free(); r.free()
	for enemy_kind: String in ["rival","elite","boss"]:
		r = make()
		var action: Dictionary = {"kind":"takedown","entity_id":9,"enemy_kind":enemy_kind,"player_attributed":false}
		check(not r.accept_event(action),"Unrelated arena elimination remains silent")
		action.player_attributed = true
		check(r.accept_event(action) and latest(r) == ("takedown" if enemy_kind == "rival" else enemy_kind+"_takedown"),"Attributed finisher selects "+enemy_kind)
		var finisher_duration: float = r.snapshot().pulse.duration
		check(r.output.starts()[0].duration <= finisher_duration*0.25,"Finishing first beat expires before the quiet gap, even across a slow frame")
		r.update(finisher_duration*0.30)
		check(not r.snapshot().output_live,"Finishing beat includes its authored quiet interval")
		r.update(0.05)
		check(r.snapshot().output_live and r.output.starts().size() == 2,"Finishing beat resumes once after its quiet interval")
		check(not r.accept_event(action) and pulses(r).size() == 1,"One attributed elimination has one authored finishing envelope")
		r.free()
	report.grind = {"existing_geometry_reused":true,"player_only":true,"attack_seconds":0.125,"maximum_release_seconds":0.08,"stale_contact_failsafe_seconds":0.10,"strong_impacts_suppress":true}

func persistence() -> void:
	check(not out.is_empty() and out.is_absolute_path(),"Persistence test requires an explicit external QA output path")
	if out.is_empty() or not out.is_absolute_path(): return
	var m: Node2D = Main.new()
	m.preferences_path = isolated_path("preferences.cfg")
	m.settings = m._validated_settings({"controller_rumble":false,"rumble_intensity":0.35,"volume":0.2})
	m._save_preferences()
	m.settings = m._validated_settings({})
	m._load_preferences()
	check(not m.settings.controller_rumble and is_equal_approx(float(m.settings.rumble_intensity),0.35),"Rumble On/Off and intensity round-trip through existing preference storage")
	var sanitized: Dictionary = m._validated_settings({"controller_rumble":"false","rumble_intensity":NAN})
	check(sanitized.controller_rumble and float(sanitized.rumble_intensity) == 0.55,"Malformed settings fall back safely to moderate defaults")
	sanitized = m._validated_settings({"rumble_intensity":2.0})
	check(float(sanitized.rumble_intensity) == 1.0,"Persisted intensity is bounded")
	m.rumble.free(); m.free()
	report.settings = {"default_enabled":true,"default_intensity":0.55,"persisted_test_intensity":0.35,"isolated_path":isolated_path("preferences.cfg"),"independent_of_audio_and_visuals":true}

func main_routes() -> void:
	if out.is_empty() or not out.is_absolute_path(): return
	var m: Node2D = Main.new()
	m.collection_path = isolated_path("collection.json")
	m.preferences_path = isolated_path("main.cfg")
	root.add_child(m)
	m.set_process(false)
	m.battle.set_physics_process(false)
	m.rumble.set_process(false)
	m.rumble.output = MockOutput.new()
	m.rumble.set_active_device(3)
	m.rumble.configure({"controller_rumble":true,"rumble_intensity":0.55})
	m._start_battle("duel")
	m._show_settings()
	Input.use_accumulated_input = false
	m.rumble.set_active_device(0)
	var native_pad := InputEventJoypadButton.new(); native_pad.device = 3; native_pad.button_index = JOY_BUTTON_DPAD_DOWN; native_pad.pressed = true
	Input.parse_input_event(native_pad); Input.flush_buffered_events()
	check(m.rumble.active_device == 3,"Actual native Node dispatch observes nonzero active ownership before menu handling")
	var native_release: InputEventJoypadButton = native_pad.duplicate()
	native_release.pressed = false; Input.parse_input_event(native_release); Input.flush_buffered_events()
	m.screen = "battle"; m.battle.battle_status = "battle"; m.battle.paused = false
	m._rumble_impact(event(1))
	check(m.rumble.snapshot().output_live,"Main routes accepted player collision into the central service")
	m._pause()
	check(m.screen == "pause" and not m.rumble.snapshot().output_live,"Actual large Pause route immediately stops output")
	m._resume()
	check(m.battle.battle_status == "reentry" and not m.rumble.snapshot().output_live,"Actual resume/re-entry has no delayed impact replay")
	m.battle.battle_status = "battle"; m.battle.paused = false
	m._rumble_impact(event(2))
	m._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(m._application_suspended and not m.rumble.snapshot().output_live,"Main focus-loss path clears output before suspending combat")
	m._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	m.battle.battle_status = "battle"; m.battle.paused = false
	m.rumble.update(0.5); m._rumble_impact(event(3))
	m.screen = "reward"
	check(not m.rumble.snapshot().output_live,"Entering a blocking draft clears output synchronously")
	m.screen = "settings"
	m._action("test_rumble")
	check(latest(m.rumble) == "test" and m.rumble.snapshot().output_live,"Actual Settings TEST RUMBLE route issues the authored short test")
	m._action("settings_changed",{"controller_rumble":false,"rumble_intensity":0.35})
	check(not m.rumble.snapshot().output_live and not m.settings.controller_rumble,"Actual Settings Off route persists and stops current output immediately")
	m._action("test_rumble")
	check(not m.rumble.snapshot().output_live,"Actual UI test action respects persisted Off")
	m.screen = "battle"; m.battle.battle_status = "battle"; m.battle.paused = false
	m.settings.controller_rumble = true; m._apply_settings(); m.rumble.reset(); m.rumble.set_active_device(3)
	m._rumble_impact(event(4))
	m._clear_run()
	check(not m.rumble.snapshot().output_live,"Actual Run reset immediately retires output")
	m.free()
	report.main_routes = {"pause":true,"draft":true,"reentry":true,"focus_loss":true,"settings_test":true,"settings_disable":true,"run_reset":true,"isolated_collection":isolated_path("collection.json")}

func physical(b: Node2D) -> Dictionary:
	var ai: Dictionary = {}
	for id: int in b._ai_rngs: ai[id] = b._ai_rngs[id].state
	var prism: Dictionary = {}
	for id: int in b.powers.base_powers.states:
		var s: Dictionary = b.powers.base_powers.states[id]
		prism[id] = {"rng":s.rng.state,"emphasis":s.emphasis,"next":s.next,"changes":s.changes}
	return {"actors":b.fighters.duplicate(true),"elapsed":b.elapsed,"status":b.battle_status,"hits":b.hits,"result":b.last_result.duplicate(true),
		"pairs":b._pair_cooldowns.duplicate(true),"powers":b.powers._states.duplicate(true),"power_events":b.powers.events.duplicate(true),
		"defence":b.powers.defence.states.duplicate(true),"roster":b.roster.states.duplicate(true),"economy":b.continuous.economy.snapshot(),
		"director":b.continuous.director.history.duplicate(true),"ai_rng":ai,"simulation_rng":b._simulation_rng.state,"cosmetic_rng":b._cosmetic_rng.state,"prismatic_rng":prism}

func deterministic_runs() -> void:
	var rows: Array = []
	for seed_value: int in [421,7341,2026]:
		for invested: bool in [false,true]:
			var pair: Array[Node2D] = []
			var services: Array[Node] = []
			for active: bool in [false,true]:
				var b: Node2D = Battle.new(); root.add_child(b); b.visible = false; b.set_physics_process(false)
				var d: Dictionary = Encounters.for_run_event(1,seed_value)
				if invested:
					d.player_power_ids = ["crash_guard","impact_sink","dead_centre","crimson_impact","azure_stability","emerald_endurance","prismatic_current"]
					d.player_power_ranks = {}
					for id: String in d.player_power_ids: d.player_power_ranks[id] = 2
				b.begin_run({"blade":"lopsider","ratchet":"flywheel","bit":"needle"},d,seed_value)
				var r: Node = make(); r.configure({"controller_rumble":active,"rumble_intensity":0.55})
				b.full_top_impact_accepted.connect(r.accept_impact)
				b.controller_feedback.connect(r.accept_event)
				pair.append(b); services.append(r)
			var ticks: int = 0
			for tick: int in range(1500):
				var direction: Vector2 = Vector2(cos(float(tick)*0.013),sin(float(tick)*0.013))*0.7
				for index: int in range(2):
					var b: Node2D = pair[index]
					services[index].set_gameplay_active(b.battle_status == "battle")
					b.test_step(Battle.FIXED_DT,direction,tick%150 == 10,tick%210 >= 180)
					services[index].observe_grind(b.player_grind_snapshot()); services[index].update(Battle.FIXED_DT)
				check(physical(pair[0]) == physical(pair[1]),"Rumble enabled/disabled preserves every actor, outcome, accepted resource ledger and gameplay RNG at the fixed-tick boundary")
				ticks = tick+1
			rows.append({"seed":seed_value,"assembly":"Lopsider / Flywheel / Needle","rank_ii_defence_auras_prism":invested,"fixed_step_calls":ticks,"elapsed":pair[0].elapsed,"accepted_contacts":pair[0].hits,"enabled_output_requests":services[1].output.starts().size(),"disabled_output_requests":services[0].output.starts().size(),"exact":physical(pair[0]) == physical(pair[1]),"input":"25s horizon including natural launch; same 0.7 rotating input, Burst every 150 ticks, Brake final 30/210 ticks"})
			check(services[0].output.starts().is_empty(),"Disabled production observer makes no vibration requests")
			for b: Node2D in pair: b.free()
			for r: Node in services: r.free()
	report.determinism = rows

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if not out.is_empty(): DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	routing_and_profiles()
	mixing_and_lifecycle()
	grind_and_actions()
	persistence()
	main_routes()
	deterministic_runs()
	var source_after: Dictionary = {}
	for file: String in SOURCE_FILES: source_after[file] = FileAccess.get_sha256("res://scripts/"+file+".gd")
	check(source_before == source_after,"All compared gameplay and rumble source files remain unchanged during execution")
	report.merge({"ok":failures.is_empty(),"checks":checks,"failures":failures,"engine":Engine.get_version_info(),
		"source_unchanged":source_before == source_after,"source_before":source_before,"source_after":source_after,
		"api":{"start":Input.has_method("start_joy_vibration"),"stop":Input.has_method("stop_joy_vibration"),"capability_query":Input.has_method("has_joy_vibration"),"official_reference":"https://docs.godotengine.org/en/4.7/classes/class_input.html"},
		"physical_devices":{"tested":[],"connected_at_execution":Input.get_connected_joypads(),"status":"Pending physical testing on exact Windows/Android candidates; mock requests do not prove motor response."},
		"source":{"rumble_sha256":FileAccess.get_sha256("res://scripts/controller_rumble.gd"),"bindings_sha256":FileAccess.get_sha256("res://scripts/controller_bindings.gd"),"battle_sha256":FileAccess.get_sha256("res://scripts/battle.gd"),"main_sha256":FileAccess.get_sha256("res://scripts/main.gd"),"test_sha256":FileAccess.get_sha256("res://tests/test_controller_rumble_003a2.gd")}})
	if not out.is_empty():
		var file: FileAccess = FileAccess.open(out,FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report,"\t")+"\n")
	print("CONTROLLER_RUMBLE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
