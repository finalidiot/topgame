extends SceneTree
## Native layout fixtures plus real live Battle snapshots. No player save.
const Meters = preload("res://scripts/power_state_meters.gd")
const Menus = preload("res://scripts/menus.gd")
const Battle = preload("res://scripts/battle.gd")
const Encounters = preload("res://scripts/encounters.gd")
const Starters = preload("res://scripts/starters.gd")
const Arena = preload("res://scripts/arena_presentation.gd")
const Visuals = preload("res://scripts/power_visuals.gd")
const Layout = preload("res://scripts/combat_hud_layout.gd")
var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {}
var report: String = ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	root.size = Vector2i(800,480); root.content_scale_size = Vector2i(800,480)
	var meter: Control = Meters.new(); root.add_child(meter)
	await process_frame
	for ownership: int in range(16):
		for stress: float in [0.0,0.34,0.35,0.70,1.0]:
			# Extreme endpoint layout only; does not claim these were earned.
			var state: Dictionary = {"anchor":{"owned":bool(ownership&1),"strength":1.0,"stress":stress,"venting":stress==1.0},
				"orbit":{"owned":bool(ownership&2),"drive":1.0,"drifting":true},
				"sink":{"owned":bool(ownership&4),"stored":150.0,"capacity":150.0,"ratio":1.0},
				"redline":{"owned":bool(ownership&8),"active":true,"heat":1.0,"excess":0.24}}
			if not bool(ownership&8): state.redline.active=false; state.redline.excess=0.0
			var original: Dictionary = state.duplicate(true)
			meter.update_state(state)
			check(state==original,"Presentation does not modify input state")
			var d: Dictionary = meter.diagnostic_snapshot()
			check(d.rows.left.size()<=2 and d.rows.right.size()<=2,"At most four meaningful owned-state rows")
			var font: Font = meter.get_theme_default_font()
			for side: String in ["left","right"]:
				for index: int in range(d.rows[side].size()):
					var row: Dictionary = d.rows[side][index]
					var origin: Vector2 = Meters.LEFT if side == "left" else Meters.RIGHT
					var box := Rect2(origin+Vector2(0,index*Meters.ROW_HEIGHT),Vector2(Meters.WIDTH,66))
					check((Layout.LEFT_EDGE if side == "left" else Layout.RIGHT_EDGE).encloses(box) and not box.intersects(Layout.PLAY_REGION),"Owned row stays wholly inside its actual external margin")
					var identity: String = {"anchor":"ANCHOR","sink":"FORCE","redline":"REDLINE","orbit":"DRIVE"}[row.id]
					check(font.get_string_size(identity,HORIZONTAL_ALIGNMENT_LEFT,-1,Meters.LABEL_SIZE).x<=Meters.WIDTH-24,"Visible icon-adjacent identity fits at actual authored size: "+identity)
					# row.text is the longer semantic/inspection description. The
					# compact renderer draws identity, value and state on three lines.
					var compact: Array[String] = ["100%","CARVE","DRIFT"]
					if row.id == "anchor": compact = ["STRESS100","SET","HOLD","HIGH","RECOVER","VENT"]
					elif row.id == "sink": compact = ["150 / 150","LOADED","STORE","EMPTY"]
					elif row.id == "redline": compact = ["HEAT 100%","ACTIVE","COOL"]
					for text: String in compact:
						check(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,Meters.LABEL_SIZE).x<=Meters.WIDTH-10,"Visible compact state/value fits at actual authored size: "+text)
					for bar: Dictionary in row.bars: check(float(bar.value)>=0.0 and float(bar.value)<=1.0,"Displayed reserve is bounded")
			check(d.rows.left.size()+d.rows.right.size() == int(bool(ownership&1))+int(bool(ownership&2))+int(bool(ownership&4))+int(bool(ownership&8)),"Only owned powers receive compact state rows")
			check(d.gameplay_writes==0 and not d.owns_timers and d.reduced_flashing_pulses==0,"Meters own neither combat, clock nor flashing")
	check(meter.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and meter.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Nearest pixels never steal steering or touch")
	meter.free()
	await live_hud()
	for kind: String in ["redline","redline_ii","redline_release","runaway","runaway_hit"]:
		var policy: Dictionary = Visuals.redline_presentation(kind)
		check(policy.handled and policy.ring and policy.particle_cels==0,"Native Redline ring replaces fragment soup: "+kind)
	for kind: String in ["redline_overcap","redline_heat"]:
		check(Visuals.redline_presentation(kind).handled and not Visuals.redline_presentation(kind).ring,"State announcements do not loop a surrounding particle aura")
	check(not Visuals.redline_presentation("breakneck_impact").handled,"Paid committed Breakneck impact keeps its authored reaction")
	check(Visuals._meta("effects").tags.has("corona"),"Retained ring uses the saved native atlas")
	for time: float in [0,90,210,390,540]:
		for reduced: bool in [false,true]:
			var d: Dictionary = Arena.presentation_snapshot(time,false,reduced)
			check(d.warning_bank_draw_calls==0 and not d.warning_animation and d.pressure_source=="HUD Director census","Decorative banks cannot look like active arena walls")
	print("STATE_METERS_003A1_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	if not report.is_empty():
		check(not FileAccess.file_exists(report),"Preserve prior meter evidence")
		var file := FileAccess.open(report,FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements},"\t"))
	quit(0 if failures.is_empty() else 1)

func live_hud() -> void:
	var b: Node2D = Battle.new(); root.add_child(b); b.set_physics_process(false); b.set_process(false)
	var menus: Control = Menus.new(); root.add_child(menus)
	var descriptor: Dictionary = Encounters.for_run_event(1,421)
	# Explicit legal loadout fixture. Runtime values below come from Battle.
	descriptor.player_power_ids=["dead_centre","orbit_drive","impact_sink","redline"]
	descriptor.player_power_ranks={"dead_centre":2,"orbit_drive":2,"impact_sink":2,"redline":2}
	descriptor.starter_id="bastion"; descriptor.ability_rebalance=true
	b.hud_updated.connect(func(stats: Dictionary) -> void:
		stats=stats.duplicate(true); stats.owned_power_ids=b.player_entity().powers.duplicate()
		stats.power_ranks=b.player_entity().power_ranks.duplicate(true); stats.power_mutations=b.player_entity().power_mutations.duplicate(true)
		stats.is_run=true; stats.level=8; stats.xp=3; stats.xp_threshold=10; menus.show_hud(stats))
	b.begin_run(Starters.build_for("bastion"),descriptor,421)
	for tick: int in range(180): b.test_step(1.0/60.0)
	b._emit_hud()
	await process_frame
	var p: Dictionary = b.player_entity()
	var state: Dictionary = b.powers.public_state(p)
	check(menus._hud.state_meters.diagnostic_snapshot().state==state,"HUD reads actual runtime snapshot")
	check(menus._inspection_owned_state.state==state,"Inspector receives the same authoritative state")
	check(not menus._hud.has("anchor"),"The single authoritative anchor meter has no duplicate lower status/quota label")
	check(Meters.LEFT.y+2*Meters.ROW_HEIGHT<=Layout.LEFT_EDGE.end.y and Meters.RIGHT.y+2*Meters.ROW_HEIGHT<=Layout.RIGHT_EDGE.end.y,"All four owned-state meters fit in the external side reservations")
	check(menus._hud.enemy_name.text.begins_with("PRESSURE ") and menus._hud.enemy_bar.visible,"Continuous Run pressure is explicit in upper framing")
	var census: Dictionary = b.continuous.snapshot().census
	var budget: float = float(b.continuous.snapshot().limits.budget)
	check(absf(menus._hud.enemy_bar.value-clampf(float(census.pressure)/budget,0,1))<=0.000501,"Pressure fill uses live census and budget within the native bar's 0.001 step")
	var before: Dictionary = {"fighter":p.duplicate(true),"powers":b.powers._states.duplicate(true),"time":b.powers.time,"rng":b._simulation_rng.state,"director":b.continuous.snapshot()}
	for index: int in range(5): menus.show_hud(hud_fixture(b))
	check(p==before.fighter and b.powers._states==before.powers and b.powers.time==before.time and b._simulation_rng.state==before.rng and b.continuous.snapshot()==before.director,"Repeated HUD refresh has no simulation writes")
	measurements.live_snapshot=state; measurements.pressure=census; measurements.row_layout=menus._hud.state_meters.diagnostic_snapshot()
	menus.free(); b.free()

func hud_fixture(b: Node2D) -> Dictionary:
	var p: Dictionary = b.player_entity()
	return {"player_rpm":p.rpm,"enemy_rpm":1.0,"owned_power_ids":p.powers,"power_ranks":p.power_ranks,"power_mutations":p.power_mutations,"power_state":b.powers.public_state(p),"dead_centre_owned":true,"is_run":true,"continuous_run":true,"run_state":b.continuous.snapshot(),"enemy_name":"fixture","elapsed":b.elapsed,"level":8,"xp":3,"xp_threshold":10}
