extends Control
## A fixed, focus-accessible reading panel; catalogue/rank identity remains authoritative.
const Powers = preload("res://scripts/run_powers.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const GUIDES: Dictionary = {
	"impact_wake":["Heavy hits shove nearby rivals.", "Hit hard, especially near a crowd.", "A ring pushes tops apart.", "Small taps do nothing; brief cooldown.", "Wider, stronger wakes; shorter cooldown."],
	"second_wind":["Rescue the same top from spin-out.", "Triggers at low RPM or severe wobble.", "A recovery flash steadies your top.", "One rescue per launch.", "Fully developed for this Run."],
	"redline":["Burst opens an unsafe RPM overclock.", "Burst; move fast and land hard hits.", "Watch heat and OVERDRIVE above 100%.", "Costs RPM; heat weakens control.", "More thrust and hit power; higher cost."],
	"iron_comet":["Wall rebounds charge your next hit.", "Rebound hard, then hit a rival.", "A charged hit releases a hard shove.", "Use it quickly or the charge fades.", "Stronger strike; charge lasts longer."],
	"dead_centre":["Hold centre to brace and recover RPM.", "Settle centrally; steer away to vent.", "Hard hits build Anchor Stress.", "High Stress weakens hold and recovery.", "Stronger brace; more recovery reserve."],
	"afterimage":["Fast travel lays routes that shove.", "Move fast; draw paths through rivals.", "Live trails push tops crossing them.", "Each trail costs RPM and expires.", "Longer trails; cross yours for speed."],
	"chain_impact":["Your knockouts chain nearby shoves.", "Hit hard, then Burst into that rival.", "Thrown rivals send more rings.", "Needs credited kills or heavy hits.", "Wider chains; stronger Burst follow-up."],
	"clutch":["Low RPM opens a recovery chance.", "Steer gently; land hits during Clutch.", "CLUTCH signals the low-spin window.", "Finite recovery; no revive after loss.", "Longer window; more earned recovery."],
	"high_gear":["Accelerate harder and travel faster.", "Steer a line and keep moving.", "Your top reaches a higher speed.", "Hard turns and Brake still cost RPM.", "More thrust, speed and retained motion."],
	"orbit_drive":["Curved travel builds efficient DRIVE.", "Brake + turn to drift; keep the arc.", "DRIVE grows; your top carves faster.", "Straighten, slow or reverse to lose it.", "Stronger carving, speed and efficiency."],
	"crash_guard":["Heavy hits trigger a brief damper.", "Take a hit; use the guarded window.", "A guard flash signals reduced loss.", "Brief protection, then a cooldown.", "Deeper damper; a longer guard window."],
	"momentum_bank":["Brake stores motion for your Burst.", "Steer + Brake, then Burst a line.", "Stored motion becomes a surge.", "Charge leaks; release costs extra RPM.", "Bank more motion; stronger release."],
	"predator_line":["Repeated hits strengthen pursuit.", "Keep hitting the same full-size rival.", "Pursuit marks build up to three times.", "Switch or wait to lose pursuit.", "Stronger hits; pursuit lasts longer."],
	"crosscut":["Glancing hits shove rivals sideways.", "Steer across a moving rival on contact.", "A sideways cut deflects the rival.", "Each cut spends RPM and recoils on you.", "Stronger cuts; shorter cooldown."],
	"gyro_lock":["Smooth travel builds a moving brace.", "Steer smoothly; move off Brake.", "A lock forms; shoves move you less.", "Idle, hard turns or Burst break lock.", "Build a heavier lock sooner."],
	"impact_sink":["Store part of incoming recoil.", "Take hits; tap Brake at low speed.", "STORED FORCE fills, then vents.", "Finite store; unused force leaks away.", "Catch more recoil; hold more force."],
	"anchor_exchange":["Brake buys heavy portable footing.", "Hold Brake near rest; release to move.", "Braces plant; shoves move you less.", "Brace costs RPM and slows travel.", "Build heavier footing sooner."]
}
const MUTATION_GUIDES: Dictionary = {
	"keel":["A steady line builds extreme ballast.", "Move with very smooth steering.", "A heavy lock steadies your line.", "Less speed; tight turns break lock."],
	"flywheel":["Carry ballast through wider curves.", "Steer smoothly while moving.", "Lock survives faster, wider turns.", "Idle, Brake or Burst still lose lock."],
	"shock_bleed":["Stored force buys stronger recovery.", "Take recoil, then tap Brake slowly.", "The vent restores RPM and steadies you.", "Stored force pays; recovery capped."],
	"return_spring":["Stored force powers a nearby shove.", "Charge the sink; tap Brake slowly.", "A pulse pushes nearby rivals.", "Costs store and RPM; no recovery vent."],
	"deep_footing":["Brake plants extreme footing.", "Almost stop, then hold Brake.", "Deeper braces resist huge shoves.", "Higher RPM cost; reduced movement."],
	"slip_anchor":["Carry some brace into repositioning.", "Brace; release Brake and pick a line.", "Footing follows the first escape step.", "Fades in 0.35s; Burst clears it."],
	"runaway":["Hard hits sustain a hotter overclock.", "Burst; keep moving and hitting hard.", "Heat climbs as overload lasts longer.", "More control risk; misses end it."],
	"breakneck":["Spend overclock on one huge strike.", "Build heat, then Burst again at a rival.", "Your top commits to a brutal charge.", "RPM and recoil cost; misses cost more."],
	"bulwark":["Full Anchor throws attackers back.", "Plant centrally; receive hard hits.", "Attackers recoil off your hold.", "Counterforce adds Anchor Stress."],
	"counterweight":["Store anchored hits for a counter.", "Anchor; take force, then aim a Burst.", "Burst releases the stored force.", "Burst spends force and breaks hold."],
	"ghost_circuit":["Closed routes shove rivals inside.", "Draw a fast live loop and close it.", "A closed circuit pushes rivals.", "Must close a paid live route; RPM cost."],
	"slipstream":["Your own old trail boosts motion.", "Cross a live trail you already laid.", "A speed surge carries you onward.", "Needs your paid route; limited repeats."],
	"terminal_velocity":["Extreme speed trades away control.", "Commit to a fast line; plan turns.", "Huge thrust and a higher speed limit.", "Hard turns and Brake cost extra RPM."],
	"flow_state":["Smooth travel keeps speed efficiently.", "Move through controlled turns.", "Turns carry your momentum onward.", "Less thrust than Terminal Velocity."]
}
const BRANCH_NEXT: Dictionary = {
	"redline":"Choose sustained heat or one huge hit.",
	"dead_centre":"Choose recoil or stored retaliation.",
	"afterimage":"Choose loop pressure or trail speed.",
	"high_gear":"Choose raw speed or smoother flow.",
	"gyro_lock":"Choose heavy footing or wider curves.",
	"impact_sink":"Choose recovery or a counter pulse.",
	"anchor_exchange":"Choose deeper brace or brief carry."
}
const SYNERGIES: Dictionary = {
	"dead_centre":"Sink / Exchange: paid vents ease Stress.",
	"redline":"Dead Centre: hard hits add more Stress.",
	"impact_sink":"Dead Centre: a paid vent eases Stress.",
	"anchor_exchange":"Dead Centre: steer on release to vent.",
	"gyro_lock":"Dead Centre: brace while repositioning.",
	"momentum_bank":"Counterweight: Burst spends both stores."
}
var power_id: String = ""
var current_rank: int = 0
var mutation_id: String = ""
var breakdown: Dictionary = {}
var runtime_state: Dictionary = {}
var _body: Control

static func describe(id: String, rank: int, mutation: String = "", branch_preview: bool = false, state: Dictionary = {}) -> Dictionary:
	if not id in Powers.IDS or Powers.max_rank(id) == 0: return {}
	rank = clampi(rank, 0, Powers.max_rank(id))
	if mutation not in Powers.mutation_choices(id) or (not branch_preview and rank != 3): mutation = ""
	var power: Dictionary = Powers.get_owned_power(id, maxi(1, rank), mutation)
	if power.is_empty(): power = Powers.get_power(id)
	var guide: Array = GUIDES[id]
	var what: String = guide[0]
	var trigger: String = guide[1]
	var notice: String = guide[2]
	var limit: String = guide[3]
	if mutation in MUTATION_GUIDES:
		what = MUTATION_GUIDES[mutation][0]
		trigger = MUTATION_GUIDES[mutation][1]
		notice = MUTATION_GUIDES[mutation][2]
		limit = MUTATION_GUIDES[mutation][3]
		power = Powers.get_mutation(mutation)
	var next: String = "First investment grants Rank I." if rank == 0 else (guide[4] if rank == 1 and Powers.max_rank(id) > 1 else "Fully developed for this Run.")
	var mutations: String = ""
	if rank == 2 and Powers.max_rank(id) == 3 and mutation.is_empty():
		next = BRANCH_NEXT[id]
		var names: Array[String] = []
		for branch: String in Powers.mutation_choices(id): names.append(str(Powers.get_mutation(branch).name))
		mutations = " / ".join(names)
	elif not mutation.is_empty():
		mutations = str(Powers.get_mutation(mutation).get("name", ""))
		if branch_preview: next = "Confirm commits this branch for the Run."
	return {"power_id":id, "name":str(power.get("name", id)), "rank":rank, "branch_preview":branch_preview,
		"type":str(power.get("category", Powers.get_power(id).get("category", "MECHANISM"))),
		"what":what, "trigger":trigger, "notice":notice, "state":current_state(id, state) if rank > 0 and not branch_preview else "",
		"limit":limit, "next":next, "mutations":mutations, "synergy":str(SYNERGIES.get(id, ""))}

static func current_state(id: String, state: Dictionary) -> String:
	# Snapshot from PowerRuntime.public_state(); never invented gameplay values.
	var key: String = {"dead_centre":"anchor", "orbit_drive":"orbit", "impact_sink":"sink", "redline":"redline"}.get(id, "")
	if key.is_empty() or not state.has(key) or not bool(state[key].get("owned", false)): return ""
	var live: Dictionary = state[key]
	match key:
		"anchor": return "ANCHOR %d%% / STRESS %d%%\n%s" % [roundi(float(live.get("charge", 0.0)) * 100.0), roundi(float(live.get("stress", 0.0)) * 100.0), "Venting Stress" if bool(live.get("venting", false)) else "Steer away to vent"]
		"orbit": return "DRIVE %d%% / %s" % [roundi(float(live.get("drive", 0.0)) * 100.0), "DRIFTING" if bool(live.get("drifting", false)) else "Keep a curved line"]
		"sink": return "STORED FORCE %d%%\nTap Brake slowly to vent" % roundi(float(live.get("ratio", 0.0)) * 100.0)
		"redline": return "%s / HEAT %d%%\nEXCESS RPM +%d%%" % ["OVERCLOCK" if bool(live.get("active", false)) else "READY", roundi(float(live.get("heat", 0.0)) * 100.0), roundi(float(live.get("excess", 0.0)) * 100.0)]
	return ""

func set_runtime_state(state: Dictionary) -> void:
	runtime_state = state.duplicate(true)
	if not power_id.is_empty() and visible: inspect(power_id, current_rank, mutation_id, bool(breakdown.get("branch_preview", false)))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_render()

func inspect(id: String, rank: int = 0, mutation: String = "", branch_preview: bool = false, state: Dictionary = {}) -> void:
	if not state.is_empty(): runtime_state = state.duplicate(true)
	power_id = id
	current_rank = rank
	mutation_id = mutation
	breakdown = describe(id, rank, mutation, branch_preview, runtime_state)
	current_rank = int(breakdown.get("rank", 0))
	visible = not breakdown.is_empty()
	if is_node_ready(): _render()

func _render() -> void:
	if is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	var panel: Panel = Panel.new()
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBox = FrontEnd.plate(FrontEnd.PANEL, FrontEnd.BLUE)
	var path: String = "res://assets/ui/human_feedback003a/inspection_frame.png"
	if ResourceLoader.exists(path):
		var authored: StyleBoxTexture = StyleBoxTexture.new()
		authored.texture = load(path)
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: authored.set_texture_margin(side, 8)
		style = authored
	panel.add_theme_stylebox_override("panel", style)
	_body.add_child(panel)
	if breakdown.is_empty(): return
	var width: float = size.x - 24
	var rank_label: String = "NEW" if current_rank == 0 else "RANK %s" % ["I", "II", "III"][clampi(current_rank - 1, 0, 2)]
	if bool(breakdown.branch_preview): rank_label = "BRANCH III"
	_line(str(breakdown.name).to_upper() + " / " + rank_label, Rect2(12, 9, width, 22), FrontEnd.TEXT)
	var stateful: bool = not str(breakdown.state).is_empty()
	var fields: Array[String] = ["what", "trigger", "state" if stateful else "notice", "limit", "next"]
	if not str(breakdown.synergy).is_empty(): fields.append("synergy")
	var y: float = 36
	for field: String in fields:
		var heading: String = {"what":"WHAT IT DOES", "trigger":"HOW TO USE", "notice":"WHAT TO NOTICE", "state":"CURRENT STATE", "limit":"TRADE-OFF", "next":"NEXT RANK", "synergy":"SYNERGY"}[field]
		_line(heading, Rect2(12, y, width, 10), FrontEnd.ORANGE if field == "synergy" else FrontEnd.BLUE)
		_line(str(breakdown[field]), Rect2(12, y + 10, width, 21), FrontEnd.TEXT)
		y += 33

func _line(value: String, area: Rect2, color: Color) -> void:
	var node: Label = Label.new()
	node.text = value
	node.add_theme_font_override("font", FrontEnd.pixel_font())
	node.add_theme_font_size_override("font_size", 10)
	node.add_theme_constant_override("line_spacing", 0)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.clip_text = true
	node.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(node)
	node.position = area.position
	node.size = area.size
