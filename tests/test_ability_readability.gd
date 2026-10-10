extends "res://tests/test_ability_rebalance.gd"
## Actual runtime description proofs and native pixel-font layout. Opens no save.
const Inspector = preload("res://scripts/ability_inspection.gd")
const Catalog = preload("res://scripts/run_powers.gd")
const Roster = preload("res://scripts/roster_runtime.gd")

func _run() -> void:
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	await _native_copy()
	_orbit_accuracy()
	_sink_accuracy()
	await _live_state_accuracy()
	print("ABILITY_READABILITY_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify({"checks":checks, "failures":failures, "measurements":measurements}, "\t"))
	quit(0 if failures.is_empty() else 1)

func _native_copy() -> void:
	for id: String in Catalog.ACTIVE_IDS:
		for level: int in range(Catalog.max_rank(id) + 1):
			await _fit(id, level)
		for branch: String in Catalog.mutation_choices(id):
			await _fit(id, 3, branch)
			await _fit(id, 2, branch, true)
	check(Inspector.describe("bogus", 1).is_empty(), "Unknown power has no invented explanation")
	check(Inspector.describe("redline", 1, "runaway").mutations == "", "Rank I cannot imply ownership of a locked branch")

func _fit(id: String, level: int, branch: String = "", preview: bool = false, state: Dictionary = {}) -> void:
	var panel: Control = Inspector.new()
	panel.position = Vector2(430, 65)
	panel.size = Vector2(188, 242)
	root.add_child(panel)
	panel.inspect(id, level, branch, preview, state)
	await process_frame
	await process_frame
	var reading: Dictionary = panel.breakdown
	for field: String in ["what", "trigger", "notice", "limit", "next"]:
		check(not str(reading[field]).is_empty(), id + " answers " + field + " at actual rank " + str(level))
	for child: Node in panel._body.get_children():
		if not child is Label: continue
		var label: Label = child
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		check(font_size == 10, id + " retains the native readable 10px type")
		check(label.get_line_count() * font.get_height(font_size) <= label.size.y + 0.1, id + " rank " + str(level) + " has no clipped text: " + label.text)
		check(label.position.y + label.size.y <= panel.size.y - 7, id + " text stays inside the native inspection frame")
	panel.free()

func _orbit_accuracy() -> void:
	var observations: Array[Dictionary] = []
	for level: int in [1, 2]:
		var h: Host = host("orbit_drive", level)
		var p: Dictionary = h.entity(1)
		var roster: RefCounted = Roster.new()
		roster.setup(h)
		var m: Dictionary = {}
		for tick: int in range(70):
			var before: Vector2 = Vector2.RIGHT.rotated(float(tick) / 60.0) * 180.0
			p.vel = before
			var direction: Vector2 = before.normalized().rotated(0.5)
			m = roster.movement(p, {"direction":direction, "braking":true, "acceleration":1.0, "speed":1.0, "drag":0.0, "drain":1.0}, 1.0 / 60.0)
			roster.velocity(p, before, before.rotated(1.0 / 60.0), 1.0 / 60.0)
		observations.append({"drive":p.orbit_charge, "speed":m.speed, "drain":m.drain})
	check(is_equal_approx(observations[0].drive, observations[1].drive), "Orbit II copy does not promise invented faster DRIVE growth")
	check(observations[1].speed > observations[0].speed and observations[1].drain < observations[0].drain, "Orbit II stronger speed and efficiency are actual runtime modifiers")
	check("same rate" in str(Catalog.get_owned_power("orbit_drive", 2).description), "Orbit II catalogue states unchanged charge rate")
	measurements.orbit_ranks = observations

func _sink_accuracy() -> void:
	var h: Host = host("impact_sink", 3, "return_spring")
	var p: Dictionary = h.entity(1)
	p.rpm = 0.45
	p.wobble = 0.60
	h.runtime.defence.state(p).sink = 90.0
	step(h, Vector2.ZERO, true)
	h.runtime.flush_contact_powers()
	check(not h.impulses.is_empty() and p.rpm < 0.45 and p.wobble == 0.60, "Return Spring text correctly describes offensive pulse rather than recovery")
	check("replaces recovery" in str(Catalog.get_mutation("return_spring").description), "Return Spring catalogue makes the changed vent purpose explicit")

func _live_state_accuracy() -> void:
	var h: Host = host("dead_centre", 2)
	var p: Dictionary = h.entity(1)
	p.powers = ["dead_centre", "orbit_drive", "impact_sink", "redline"]
	p.power_ranks = {"dead_centre":2, "orbit_drive":2, "impact_sink":2, "redline":2}
	p.anchor_charge = 0.8
	p.anchor_stress = 0.6
	p.orbit_charge = 0.7
	p.drift_active = true
	h.runtime.defence.state(p).sink = 75.0
	p.sink_charge = 75.0
	p.sink_capacity = 150.0
	h.runtime.burst_started(p, Vector2.RIGHT, p.rpm)
	p.anchor_charge = 0.8
	p.anchor_stress = 0.6
	p.redline_heat = 0.4
	var state: Dictionary = h.runtime.public_state(p)
	check("STRESS 60%" in Inspector.describe("dead_centre", 2, "", false, state).state, "Inspection reads actual public Stress snapshot")
	check("DRIVE 70%" in Inspector.describe("orbit_drive", 2, "", false, state).state, "Inspection reads actual public DRIVE snapshot")
	check("FORCE 50%" in Inspector.describe("impact_sink", 2, "", false, state).state, "Inspection reads actual public force capacity ratio")
	check("HEAT 40%" in Inspector.describe("redline", 2, "", false, state).state, "Inspection reads actual active overclock heat")
	check(Inspector.describe("dead_centre", 0, "", false, state).state.is_empty(), "An unowned offer never invents a current owned state")
	for id: String in ["dead_centre", "orbit_drive", "impact_sink", "redline"]: await _fit(id, 2, "", false, state)
	var panel: Control = Inspector.new()
	panel.size = Vector2(188, 242)
	root.add_child(panel)
	panel.inspect("orbit_drive", 2, "", false, state)
	panel.visible = false
	var hidden_body: Control = panel._body
	var latest: Dictionary = state.duplicate(true)
	latest.orbit.drive = 0.2
	panel.set_runtime_state(latest)
	check(not panel.visible and panel._body == hidden_body, "Hidden live refresh stays hidden without rebuilding the inspection panel")
	panel.inspect("orbit_drive", 2)
	check(panel.visible and "DRIVE 20%" in panel.breakdown.state, "Next explicit inspection opens with the latest hidden runtime snapshot")
	panel.set_runtime_state(state)
	check(panel.visible and "DRIVE 70%" in panel.breakdown.state, "Visible live refresh stays open and updates the actual runtime state")
	panel.free()
