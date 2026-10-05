extends RefCounted
class_name RunPowerCatalog

const IdentityArt = preload("res://scripts/power_identity.gd")

## Catalogue identity stays stable as the implemented draft pool grows.
## Physical Blade / Ratchet / Bit ratings remain exclusively in parts.gd.
const IDS: Array[String] = [
	"impact_wake", "second_wind", "redline", "iron_comet", "dead_centre", "afterimage",
	"reversal", "chain_impact", "slip_gear", "rim_runner", "flywheel_cache", "crosscut",
	"clutch", "high_gear", "orbit_drive", "crash_guard", "momentum_bank", "predator_line"
]
const ACTIVE_IDS: Array[String] = ["impact_wake", "redline", "iron_comet", "dead_centre", "afterimage", "chain_impact", "clutch", "high_gear", "orbit_drive", "crash_guard", "momentum_bank", "predator_line", "crosscut"]
const VERTICAL_IDS: Array[String] = ["redline", "dead_centre", "afterimage", "high_gear"]
const FAMILY_CAP: int = 7
# Retired IDs remain readable for historical fixtures; normal drafts use ACTIVE_IDS.
const LEGACY_OWNED_IDS: Array[String] = ["second_wind"]
const ROSTER_ART_IDS: Array[String] = ["clutch","high_gear","orbit_drive","crash_guard","momentum_bank","predator_line","crosscut","clutch_ii","high_gear_ii","orbit_drive_ii","crash_guard_ii","momentum_bank_ii","predator_line_ii","crosscut_ii","terminal_velocity","flow_state","iron_comet","iron_comet_ii"]
const ROSTER_ICON_SHEET: String = "res://assets/powers/roster_icons.png"
const ROSTER_CARD_SHEET: String = "res://assets/powers/roster_cards.png"
const ART_ALIASES: Dictionary = {"impact_wake_ii":"impact_wake","chain_impact_ii":"chain_impact"}
# Existing production atlas indexes remain stable as the active pool grows.
const LEGACY_ART_IDS: Array[String] = ["impact_wake", "second_wind", "redline", "iron_comet", "afterimage", "chain_impact"]
const ESCALATION_ART_IDS: Array[String] = ["dead_centre", "redline_ii", "dead_centre_ii", "afterimage_ii", "runaway", "breakneck", "bulwark", "counterweight", "ghost_circuit", "slipstream"]
const ICON_SHEET: String = "res://assets/powers/icons.png"
const CARD_SHEET: String = "res://assets/powers/cards.png"
const ESCALATION_ICON_SHEET: String = "res://assets/powers/escalation_icons.png"
const ESCALATION_CARD_SHEET: String = "res://assets/powers/escalation_cards.png"
const MUTATION_BRANCHES: Dictionary = {
	"redline":["runaway", "breakneck"],
	"dead_centre":["bulwark", "counterweight"],
	"afterimage":["ghost_circuit", "slipstream"],
	"high_gear":["terminal_velocity", "flow_state"]
}
# Native 64px, six discrete poses per row. Presentation reads source timing.
const CARD_DURATIONS_MS: Array[int] = [110, 90, 75, 75, 100, 170]
const CARD_STATIC_FRAMES: Dictionary = {"impact_wake":2, "second_wind":3, "redline":2, "iron_comet":4, "afterimage":3, "chain_impact":4}
const CARD_COPY: Dictionary = {
	"impact_wake": {"category":"IMPACT", "copy":"Heavy hits blast nearby tops away."},
	"second_wind": {"category":"RECOVERY", "copy":"Once per launch, recover from near spin-out."},
	"redline": {"category":"OVERCLOCK", "copy":"Burst. Move hard. Hit to climb beyond safe RPM."},
	"iron_comet": {"category":"RICOCHET", "copy":"Hard wall rebounds charge your next hit."},
	"dead_centre": {"category":"ANCHOR", "copy":"Hold the middle. Brace harder. Rebuild spin and pull rivals inward."},
	"afterimage": {"category":"MOBILITY", "copy":"High speed leaves a lasting physical pressure route."},
	"chain_impact": {"category":"CHAIN", "copy":"Knockouts chain blasts. Heavy hit primes Burst."},
	"clutch": {"category":"COMEBACK", "copy":"Low spin? Land a hit to catch the machine."},
	"high_gear": {"category":"SPEED", "copy":"Faster thrust and ceiling. Keep your line."},
	"orbit_drive": {"category":"DRIFT", "copy":"Brake + turn into a drift. Keep the arc."},
	"crash_guard": {"category":"BRAWL", "copy":"Heavy hits engage a short collision damper."},
	"momentum_bank": {"category":"BRAKE", "copy":"Brake to bank motion. Burst to release it."},
	"predator_line": {"category":"PRESSURE", "copy":"Keep hitting one rival. Build pursuit pressure."},
	"crosscut": {"category":"SHEAR", "copy":"Steer through glancing hits to cut sideways."}
}
const CONDITIONS: Dictionary = {
	"impact_wake":"Heavy contact / 1.25 s cooldown",
	"second_wind":"Low spin or severe wobble / once per launch",
	"redline":"Burst at 13%+ RPM / active high-speed movement and impacts create overcap",
	"iron_comet":"Hard wall rebound / spend within 2 s",
	"dead_centre":"Controlled centre position / settled hold recovers bounded RPM / a deliberate outside rotation reloads recovery / aggression or extreme force breaks Anchor",
	"afterimage":"High speed / each trace spends spin",
	"chain_impact":"Credited eliminations / heavy hit then Burst",
	"clutch":"Dangerous RPM / controlled movement conserves; meaningful impacts reclaim",
	"high_gear":"Movement / hard steering and braking still cost spin",
	"orbit_drive":"Brake + turn to drift / sustained arcs keep flow; reversals break it",
	"crash_guard":"Heavy incoming contact / short guarded recovery window",
	"momentum_bank":"Controlled braking / next Burst spends stored motion",
	"predator_line":"Repeated meaningful contacts with the same full rival",
	"crosscut":"Glancing contact while steering / spin-powered lateral shear"
}
const DEFINITIONS: Dictionary = {
	"impact_wake": {"id":"impact_wake", "name":"Impact Wake", "description":"Heavy contacts send a pressure ring through nearby tops.", "short_label":"WAKE", "tags":["impact"], "icon":"", "active":true},
	"second_wind": {"id":"second_wind", "name":"Second Wind", "description":"Once each launch, near spin-out triggers a dramatic recovery.", "short_label":"WIND", "tags":["recovery"], "icon":"", "active":true},
	"redline": {"id":"redline", "name":"Redline", "description":"Burst engages an unsafe overclock; active high-speed movement and successful impacts create excess RPM and worsening control.", "short_label":"RED", "tags":["burst", "risk"], "icon":"", "active":true},
	"iron_comet": {"id":"iron_comet", "name":"Iron Comet", "description":"A hard wall rebound charges your next real hit.", "short_label":"COMET", "tags":["wall", "impact"], "icon":"", "active":true},
	"dead_centre": {"id":"dead_centre", "name":"Dead Centre", "description":"Hold the middle to brace, rebuild a limited spin reserve and pull rivals inward. Move and steer outside the centre to reload recovery. Aggression or extreme force breaks the lock.", "short_label":"CENTRE", "tags":["position", "defence"], "icon":"", "active":true},
	"afterimage": {"id":"afterimage", "name":"Afterimage", "description":"Fast movement leaves physical pressure routes that linger for several seconds.", "short_label":"ECHO", "tags":["mobility"], "icon":"", "active":true},
	"reversal": {"id":"reversal", "name":"Reversal", "description":"Brake after a hard unstable hit to turn recoil into recovery.", "short_label":"REV", "tags":["brake", "recovery"], "icon":"", "active":false},
	"chain_impact": {"id":"chain_impact", "name":"Chain Impact", "description":"Thrown tops chain pressure pulses; heavy duel hits prime a Burst follow-through.", "short_label":"CHAIN", "tags":["impact", "burst"], "icon":"", "active":true},
	"slip_gear": {"id":"slip_gear", "name":"Slip Gear", "description":"Brake, turn, then Burst to release stored momentum.", "short_label":"SLIP", "tags":["brake", "mobility"], "icon":"", "active":false},
	"rim_runner": {"id":"rim_runner", "name":"Rim Runner", "description":"Brake along a solid wall to ride its edge and choose your exit.", "short_label":"RIM", "tags":["brake", "wall"], "icon":"", "active":false},
	"flywheel_cache": {"id":"flywheel_cache", "name":"Flywheel Cache", "description":"Bank a little early spin and release it when reserve gets low.", "short_label":"CACHE", "tags":["reserve", "recovery"], "icon":"", "active":false},
	"crosscut": {"id":"crosscut", "name":"Crosscut", "description":"Steering through a glancing hit spends spin for a sideways shear.", "short_label":"CUT", "tags":["impact", "mobility"], "icon":"", "active":true},
	"clutch": {"id":"clutch", "name":"Clutch", "description":"In low-spin danger, controlled movement conserves RPM and meaningful impacts earn a catch for the same unstable machine.", "short_label":"CLUTCH", "tags":["recovery", "defence"], "icon":"", "active":true},
	"high_gear": {"id":"high_gear", "name":"High Gear", "description":"Stronger acceleration and a higher physical speed ceiling make the top immediately fast.", "short_label":"GEAR", "tags":["mobility", "speed"], "icon":"", "active":true},
	"orbit_drive": {"id":"orbit_drive", "name":"Orbit Drive", "description":"Brake and turn into a deliberate drift; sustained curved motion builds efficient momentum and sharp reversals break the orbit.", "short_label":"ORBIT", "tags":["mobility", "efficiency"], "icon":"", "active":true},
	"crash_guard": {"id":"crash_guard", "name":"Crash Guard", "description":"A heavy incoming hit engages a temporary collision damper, inviting another close exchange.", "short_label":"GUARD", "tags":["defence", "impact"], "icon":"", "active":true},
	"momentum_bank": {"id":"momentum_bank", "name":"Momentum Bank", "description":"Controlled braking stores capped lost motion; the next Burst releases it along your chosen line.", "short_label":"BANK", "tags":["brake", "burst"], "icon":"", "active":true},
	"predator_line": {"id":"predator_line", "name":"Predator Line", "description":"Repeated meaningful contacts with one full rival build pursuit pressure; switching or disengaging loses it.", "short_label":"HUNT", "tags":["impact", "pressure"], "icon":"", "active":true}
}

const RANK_II: Dictionary = {
	"redline": {"name":"Redline II", "description":"A hotter overdrive: stronger acceleration and impacts, with sharper spin and wobble risk.", "card_copy":"Hotter Burst. Brutal hits. More spin and control risk.", "category":"HOT OVERDRIVE", "short_label":"RED II", "art_id":"redline_ii"},
	"dead_centre": {"name":"Dead Centre II", "description":"A deeper Anchor: deploy stronger floor braces, settle collision shock and recover more spin during a sustained central hold.", "card_copy":"Brace into the floor. Resist hits. Rebuild more spin.", "category":"GROUND LOCK", "short_label":"CENTRE II", "art_id":"dead_centre_ii"},
	"afterimage": {"name":"Afterimage II", "description":"Longer routes push enemies harder; crossing your own aged trace grants a small momentum surge.", "card_copy":"Longer routes. Stronger crossings. Reuse your path.", "category":"LIVE ROUTE", "short_label":"ECHO II", "art_id":"afterimage_ii"},
	"impact_wake": {"name":"Impact Wake II", "description":"A deeper mechanical pressure wake reaches farther and throws nearby machines harder.", "card_copy":"Broader pressure wakes. Push clustered machines apart.", "category":"IMPACT", "short_label":"WAKE II", "art_id":"impact_wake_ii"},
	"iron_comet": {"name":"Iron Comet II", "description":"A stronger rebound stores a longer-lived committed strike with a heavier mechanical release.", "card_copy":"Hold rebound charge longer. Commit a heavier strike.", "category":"REBOUND STRIKE", "short_label":"COMET II", "art_id":"iron_comet_ii"},
	"chain_impact": {"name":"Chain Impact II", "description":"A stronger credited chain transmits pressure farther and primes a deeper Burst follow-through.", "card_copy":"Extend the collision chain. Follow through with Burst.", "category":"CHAIN", "short_label":"CHAIN II", "art_id":"chain_impact_ii"},
	"clutch": {"name":"Clutch II", "description":"The low-spin catch window is more efficient, with stronger earned reclamation and stabilisation while danger remains.", "card_copy":"Catch low spin through useful play. No relaunch.", "category":"COMEBACK", "short_label":"CLUTCH II", "art_id":"clutch_ii"},
	"high_gear": {"name":"High Gear II", "description":"A higher speed ceiling and stronger acceleration deepen the machine's movement specialisation.", "card_copy":"More thrust. A visibly faster developed machine.", "category":"HIGH SPEED", "short_label":"GEAR II", "art_id":"high_gear_ii"},
	"orbit_drive": {"name":"Orbit Drive II", "description":"Brake-turn drifts build flow faster and retain stronger efficient motion through sustained arcs.", "card_copy":"Brake + turn. Hold a stronger efficient drift.", "category":"DRIFT FLOW", "short_label":"ORBIT II", "art_id":"orbit_drive_ii"},
	"crash_guard": {"name":"Crash Guard II", "description":"Heavy impacts engage a deeper short-lived damper, reducing the cost of continuing the brawl.", "card_copy":"A deeper short damper. Keep fighting after the hit.", "category":"BRAWL DEFENCE", "short_label":"GUARD II", "art_id":"crash_guard_ii"},
	"momentum_bank": {"name":"Momentum Bank II", "description":"Controlled brakes bank more capped motion for a stronger purposeful Burst release.", "card_copy":"Bank a deeper brake. Release a stronger chosen line.", "category":"BRAKE STORAGE", "short_label":"BANK II", "art_id":"momentum_bank_ii"},
	"predator_line": {"name":"Predator Line II", "description":"Consecutive meaningful contacts build a deeper hunt with more persistent pursuit pressure.", "card_copy":"Stay on one rival. Build a deeper pressure chain.", "category":"PURSUIT", "short_label":"HUNT II", "art_id":"predator_line_ii"},
	"crosscut": {"name":"Crosscut II", "description":"Committed steering through a glance spends spin for a stronger lateral shear and physical disruption.", "card_copy":"Cut harder through a glance. Spin pays for shear.", "category":"SHEAR", "short_label":"CUT II", "art_id":"crosscut_ii"}
}
const MUTATIONS: Dictionary = {
	"runaway": {"id":"runaway", "power_id":"redline", "name":"Runaway", "description":"Heavy hits sustain Redline and build a wilder overload. Keep hitting or lose the engine.", "card_copy":"Heavy hits sustain overload. Keep attacking to stay alive.", "category":"SUSTAINED OVERLOAD", "short_label":"RUNAWAY", "condition":"Heavy contacts during Redline / misses end the chain"},
	"breakneck": {"id":"breakneck", "power_id":"redline", "name":"Breakneck", "description":"Build Redline heat or excess RPM, then Burst again to commit that overclock to one violent strike with recoil and recovery.", "card_copy":"Build heat. Burst again. Commit to a brutal strike.", "category":"CATASTROPHIC CHARGE", "short_label":"BREAKNECK", "condition":"Overclock first / Burst again at 32% heat or 2.5% excess RPM"},
	"bulwark": {"id":"bulwark", "power_id":"dead_centre", "name":"Bulwark", "description":"At full Anchor, become extraordinarily hard to move. Heavy attackers recoil from your planted machine.", "card_copy":"Plant fully. Refuse displacement. Throw attackers back.", "category":"IMMOVABLE DEFENCE", "short_label":"BULWARK", "condition":"Full Anchor / heavy incoming contacts"},
	"counterweight": {"id":"counterweight", "power_id":"dead_centre", "name":"Counterweight", "description":"Capture incoming force while Anchored, then Burst to release that stored force as retaliation.", "card_copy":"Anchor. Store incoming force. Burst to release it.", "category":"STORED RETALIATION", "short_label":"COUNTER", "condition":"Incoming force while Anchored / Burst releases storage"},
	"ghost_circuit": {"id":"ghost_circuit", "power_id":"afterimage", "name":"Ghost Circuit", "description":"Close a live route into a loop to energise the circuit and pressure the enclosed arena.", "card_copy":"Draw a fast loop. Close the circuit. Crush its interior.", "category":"CIRCUIT CLOSURE", "short_label":"CIRCUIT", "condition":"Close a live Afterimage loop / forgiving route closure"},
	"slipstream": {"id":"slipstream", "power_id":"afterimage", "name":"Slipstream", "description":"Re-enter your own live route to recover momentum and handling. Reuse crossings to power your movement.", "card_copy":"Cross your old route. Recover momentum. Go again.", "category":"ROUTE ENGINE", "short_label":"STREAM", "condition":"Re-enter or cross your own active Afterimage path"},
	"terminal_velocity": {"id":"terminal_velocity", "power_id":"high_gear", "name":"Terminal Velocity", "description":"Commit to extreme raw speed; hard steering and braking burn more RPM and correction is harder.", "card_copy":"Extreme velocity. Expensive corrections. Hold your nerve.", "category":"RAW SPEED", "short_label":"TERMINAL", "condition":"High-speed movement / steering and brake expenditure"},
	"flow_state": {"id":"flow_state", "power_id":"high_gear", "name":"Flow State", "description":"Trade the extreme raw ceiling for smoother turning, better retained velocity and efficient sustained movement.", "card_copy":"Keep your velocity through turns. Maintain the flow.", "category":"MAINTAINED SPEED", "short_label":"FLOW", "condition":"Sustained movement / smooth velocity retention"}
}

static func get_power(power_id: String) -> Dictionary:
	var power: Dictionary = DEFINITIONS.get(power_id, {}).duplicate(true)
	if power.is_empty(): return power
	power.active = power_id in ACTIVE_IDS
	power["max_rank"] = max_rank(power_id)
	power["power_id"] = power_id
	power["rank"] = 1
	power["mutation"] = ""
	power["icon_frame"] = -1
	power["condition"] = CONDITIONS.get(power_id, "")
	if power.active or power_id in LEGACY_OWNED_IDS:
		_apply_art(power, power_id)
		power["category"] = CARD_COPY[power_id].category
		power["card_copy"] = CARD_COPY[power_id].copy
	return power

static func max_rank(power_id: String) -> int:
	return 3 if power_id in VERTICAL_IDS else (2 if power_id in ACTIVE_IDS else (1 if power_id in LEGACY_OWNED_IDS else 0))

static func investment_capacity() -> int:
	var capacity: int = 0
	for power_id: String in ACTIVE_IDS: capacity += max_rank(power_id)
	return capacity

static func run_investment_capacity() -> int:
	# Content capacity and a single machine's investment ceiling are distinct.
	var ranks: Array[int] = []
	for power_id: String in ACTIVE_IDS: ranks.append(max_rank(power_id))
	ranks.sort()
	ranks.reverse()
	var capacity: int = 0
	for index: int in range(mini(FAMILY_CAP,ranks.size())): capacity += ranks[index]
	return capacity

static func can_progress(power_id: String, rank: int = 0, mutation: String = "") -> bool:
	return power_id in ACTIVE_IDS and rank >= 0 and rank < max_rank(power_id) and mutation.is_empty()

static func mutation_choices(power_id: String) -> Array[String]:
	var choices: Array[String] = []
	for branch_id: String in MUTATION_BRANCHES.get(power_id, []): choices.append(branch_id)
	return choices

## A normal offer always identifies its original power. Rank II ownership
## opens a separate branch event; it never grants a third rank by itself.
static func get_offer(power_id: String, rank: int = 0, mutation: String = "") -> Dictionary:
	if not can_progress(power_id, rank, mutation): return {}
	var power: Dictionary = get_power(power_id)
	power["owned_rank"] = rank
	power["rank"] = rank + 1
	power["offer_kind"] = "acquire" if rank == 0 else ("tune" if rank == 1 else "mutation")
	power["offer_label"] = ["NEW POWER / I", "UPGRADE / II", "MUTATION / III"][rank]
	power["rank_label"] = ["RANK I / ACQUIRE", "RANK II / TUNE", "RANK III / MUTATE"][rank]
	if rank > 0:
		power.merge(RANK_II[power_id].duplicate(true), true)
		_apply_art(power, str(power.art_id))
	if rank == 2:
		power.name = str(DEFINITIONS[power_id].name) + " III"
		power.category = "MUTATION AVAILABLE"
		var branches: Array[String] = mutation_choices(power_id)
		power.description = "Choose %s or %s to transform this power." % [MUTATIONS[branches[0]].name, MUTATIONS[branches[1]].name]
		power.card_copy = "Choose a new behaviour: %s or %s." % [MUTATIONS[branches[0]].name, MUTATIONS[branches[1]].name]
	return power

static func get_mutation(branch_id: String) -> Dictionary:
	var branch: Dictionary = MUTATIONS.get(branch_id, {}).duplicate(true)
	if branch.is_empty(): return branch
	branch["active"] = true
	branch["rank"] = 3
	branch["max_rank"] = 3
	branch["mutation"] = branch_id
	branch["offer_kind"] = "mutation"
	branch["offer_label"] = "MUTATION / III"
	branch["rank_label"] = "RANK III / MUTATION"
	_apply_art(branch, branch_id)
	return branch

## Current ownership metadata is distinct from the next investment offer.
static func get_owned_power(power_id: String, rank: int = 1, mutation: String = "") -> Dictionary:
	if not (power_id in ACTIVE_IDS or power_id in LEGACY_OWNED_IDS) or rank < 1 or rank > max_rank(power_id): return {}
	if rank == 3:
		return get_mutation(mutation) if mutation in mutation_choices(power_id) else {}
	var power: Dictionary = get_power(power_id)
	if rank == 2:
		power.merge(RANK_II[power_id].duplicate(true), true)
		_apply_art(power, str(power.art_id))
	power.rank = rank
	return power

static func _apply_art(power: Dictionary, art_id: String) -> void:
	var authored: Dictionary = IdentityArt.art(art_id)
	if not authored.is_empty():
		power.merge(authored, true)
		return
	var source_id: String = str(ART_ALIASES.get(art_id, art_id))
	var escalation: bool = source_id in ESCALATION_ART_IDS
	var roster: bool = source_id in ROSTER_ART_IDS
	power["art_id"] = art_id
	power["source_tag"] = source_id
	power["icon"] = ROSTER_ICON_SHEET if roster else (ESCALATION_ICON_SHEET if escalation else ICON_SHEET)
	power["icon_frame"] = ROSTER_ART_IDS.find(source_id) if roster else (ESCALATION_ART_IDS.find(source_id) if escalation else LEGACY_ART_IDS.find(source_id))
	power["card_texture"] = ROSTER_CARD_SHEET if roster else (ESCALATION_CARD_SHEET if escalation else CARD_SHEET)
	power["card_row"] = power.icon_frame
	power["card_frames"] = 6
	power["card_cell"] = 64
	power["card_static_frame"] = int(CARD_STATIC_FRAMES.get(art_id, 3))
	power["card_durations_ms"] = CARD_DURATIONS_MS.duplicate()

static func display_names(power_ids: Array) -> Array[String]:
	var names: Array[String] = []
	for power_id: String in power_ids:
		if DEFINITIONS.has(power_id): names.append(str(DEFINITIONS[power_id].name))
	return names
