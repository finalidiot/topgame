extends Control
## A fixed, focus-accessible reading panel; catalogue/rank identity remains authoritative.
const Powers = preload("res://scripts/run_powers.gd")
const FrontEnd = preload("res://scripts/front_end.gd")
const GUIDES: Dictionary = {
	"gyro_lock":["Smooth steering builds moving ballast.", "Hold a smooth heading while moving.", "Idle, sharp turns and Burst break lock.", "A stronger lock with longer retention."],
	"impact_sink":["Absorb recoil into a finite reservoir.", "Take force; tap Brake at lower speed.", "A full sink cannot absorb more force.", "Store and vent more impact energy."],
	"anchor_exchange":["Brake trades mobility for paid ballast.", "Hold Brake below 78 speed; release to move.", "Bracing spends RPM every second.", "Deeper portable mass and stability."],
	"impact_wake":["Heavy impacts push nearby tops away.", "Commit to a substantial collision.", "Small taps do not trigger a wake.", "A broader, stronger pressure wake."],
	"second_wind":["Recover from near spin-out once.", "Reach dangerous spin or severe wobble.", "One rescue per launch.", "Fully developed for this Run."],
	"redline":["Burst and hard hits build overdrive.", "Burst, keep moving, then land hits.", "Overdrive spends spin and risks control.", "Hotter thrust and harder impacts."],
	"iron_comet":["Wall rebounds store a heavier next hit.", "Rebound hard, then strike a rival.", "Stored charge fades if unused.", "Hold a stronger rebound strike."],
	"dead_centre":["Plant centrally to brace and recover.", "Control the centre and settle your top.", "Aggression or extreme force breaks hold.", "Deeper braces and stronger recovery."],
	"afterimage":["Fast motion leaves pressure routes.", "Keep speed and lay a useful path.", "Every trace spends your spin reserve.", "Longer routes; reuse your crossings."],
	"chain_impact":["Knockouts chain pulses through rivals.", "Earn a knockout; hit hard, then Burst.", "Needs credited hits and eliminations.", "Farther chains and deeper follow-through."],
	"clutch":["Useful play catches dangerous low spin.", "Control movement and land meaningful hits.", "It helps the same top; no relaunch.", "Stronger earned catch and stabilisation."],
	"high_gear":["More thrust and a higher speed ceiling.", "Commit to a line and keep moving.", "Hard correction and braking cost spin.", "More acceleration and developed speed."],
	"orbit_drive":["Brake-turn arcs build efficient motion.", "Brake and turn; sustain a curved drift.", "Sharp reversals break the flow.", "Build and retain a stronger drift."],
	"crash_guard":["Heavy incoming hits engage a damper.", "Take a heavy hit and keep exchanging.", "A brief window, not permanent armour.", "A deeper short collision damper."],
	"momentum_bank":["Brake to bank motion; Burst releases it.", "Brake deliberately, then choose a line.", "Storage is capped and Burst spends it.", "Bank more; release a stronger line."],
	"predator_line":["Repeated hits on one rival build pressure.", "Keep contacting the same full rival.", "Switching or disengaging loses pursuit.", "A deeper, more persistent hunt."],
	"crosscut":["Steered glances create a sideways cut.", "Steer through a glancing collision.", "The shear spends your own spin.", "A stronger spin-powered lateral shear."]
}
const MUTATION_GUIDES: Dictionary = {
	"keel":["Deep ballast rewards a steady line.", "Maintain a very smooth moving heading.", "Sharp correction breaks the deep lock."],
	"flywheel":["Carry a lighter lock through wider arcs.", "Steer smoothly through sustained motion.", "Burst and idle still clear the lock."],
	"shock_bleed":["Stored force vents into RPM recovery.", "Tap Brake after real incoming recoil.", "Recovery shares the Run budget."],
	"return_spring":["Venting steadies wobble and returns motion.", "Tap Brake with a charged impact sink.", "Only previously stored force returns."],
	"deep_footing":["Very slow braking plants extreme ballast.", "Hold Brake below 34 speed.", "Higher RPM cost and reduced mobility."],
	"slip_anchor":["Released ballast briefly carries into motion.", "Brace, release Brake and choose a line.", "The carried brace decays in 0.35 seconds."],
	"runaway":["Heavy hits sustain a wild overload.", "Keep landing heavy Redline contacts.", "Misses end the sustaining chain."],
	"breakneck":["Commit overclock to one violent strike.", "Build heat, then Burst again.", "The strike brings recoil and recovery."],
	"bulwark":["A planted top throws attackers back.", "Fully Anchor, then receive heavy hits.", "Requires a committed central hold."],
	"counterweight":["Store incoming force for retaliation.", "Anchor, take force, then Burst.", "Burst spends your stored force."],
	"ghost_circuit":["Closed routes pressure their interior.", "Draw a fast live loop and close it.", "An open route is not a circuit."],
	"slipstream":["Your own route restores momentum.", "Re-enter or cross a live old trace.", "Requires your existing paid route."],
	"terminal_velocity":["Trade control for extreme raw speed.", "Commit to high-speed movement.", "Corrections and braking cost more RPM."],
	"flow_state":["Smooth turns retain efficient motion.", "Keep moving through controlled turns.", "Trades away the extreme speed ceiling."]
}
var power_id: String = ""
var current_rank: int = 0
var mutation_id: String = ""
var breakdown: Dictionary = {}
var _body: Control

static func describe(id: String, rank: int, mutation: String = "", branch_preview: bool = false) -> Dictionary:
	if not id in Powers.IDS or Powers.max_rank(id) == 0: return {}
	rank = clampi(rank, 0, Powers.max_rank(id))
	if mutation not in Powers.mutation_choices(id) or (not branch_preview and rank != 3): mutation = ""
	var power: Dictionary = Powers.get_owned_power(id, maxi(1, rank), mutation)
	if power.is_empty(): power = Powers.get_power(id)
	var guide: Array = GUIDES.get(id, [str(power.get("card_copy", power.get("description", ""))), str(power.get("condition", "")), "Use the mechanism deliberately.", "Fully developed for this Run."])
	var what: String = guide[0]
	var trigger: String = guide[1]
	var limit: String = guide[2]
	if mutation in MUTATION_GUIDES:
		what = MUTATION_GUIDES[mutation][0]
		trigger = MUTATION_GUIDES[mutation][1]
		limit = MUTATION_GUIDES[mutation][2]
		power = Powers.get_mutation(mutation)
	var next: String = "First investment grants Rank I." if rank == 0 else (guide[3] if rank == 1 and Powers.max_rank(id) > 1 else "Fully developed for this Run.")
	var mutations: String = ""
	if rank == 2 and Powers.max_rank(id) == 3 and mutation.is_empty():
		next = "Next investment chooses a mutation."
		var names: Array[String] = []
		for branch: String in Powers.mutation_choices(id): names.append(str(Powers.get_mutation(branch).name))
		mutations = " / ".join(names)
	elif not mutation.is_empty():
		mutations = str(Powers.get_mutation(mutation).get("name", ""))
		if branch_preview: next = "Confirm commits this branch for the Run."
	return {"power_id":id, "name":str(power.get("name", id)), "rank":rank, "branch_preview":branch_preview,
		"type":str(power.get("category", Powers.get_power(id).get("category", "MECHANISM"))),
		"what":what, "trigger":trigger, "limit":limit, "next":next, "mutations":mutations}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_render()

func inspect(id: String, rank: int = 0, mutation: String = "", branch_preview: bool = false) -> void:
	power_id = id
	current_rank = rank
	mutation_id = mutation
	breakdown = describe(id, rank, mutation, branch_preview)
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
	_line("TYPE: " + str(breakdown.type), Rect2(12, 32, width, 14), FrontEnd.MUTED)
	var y: float = 50
	for field: String in ["what", "trigger", "limit", "next"]:
		var heading: String = {"what":"WHAT IT DOES", "trigger":"TRIGGER / USE", "limit":"TRADE-OFF / LIMIT", "next":"NEXT RANK"}[field]
		_line(heading, Rect2(12, y, width, 11), FrontEnd.BLUE)
		_line(str(breakdown[field]), Rect2(12, y + 11, width, 22), FrontEnd.TEXT)
		y += 37
	if not str(breakdown.mutations).is_empty():
		_line("MUTATIONS", Rect2(12, y, width, 11), FrontEnd.ORANGE)
		_line(str(breakdown.mutations), Rect2(12, y + 11, width, 23), FrontEnd.TEXT)

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
