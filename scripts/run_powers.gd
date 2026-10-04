extends RefCounted
class_name RunPowerCatalog

## Catalogue identity stays stable as the implemented draft pool grows.
## Physical Blade / Ratchet / Bit ratings remain exclusively in parts.gd.
const IDS: Array[String] = [
	"impact_wake", "second_wind", "redline", "iron_comet", "dead_centre", "afterimage",
	"reversal", "chain_impact", "slip_gear", "rim_runner", "flywheel_cache", "crosscut"
]
const ACTIVE_IDS: Array[String] = ["impact_wake", "second_wind", "redline", "iron_comet", "dead_centre", "afterimage", "chain_impact"]
const VERTICAL_IDS: Array[String] = ["redline", "dead_centre", "afterimage"]
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
	"afterimage":["ghost_circuit", "slipstream"]
}
# Native 64px, six discrete poses per row. Presentation reads source timing.
const CARD_DURATIONS_MS: Array[int] = [110, 90, 75, 75, 100, 170]
const CARD_STATIC_FRAMES: Dictionary = {"impact_wake":2, "second_wind":3, "redline":2, "iron_comet":4, "afterimage":3, "chain_impact":4}
const CARD_COPY: Dictionary = {
	"impact_wake": {"category":"IMPACT", "copy":"Heavy hits blast nearby tops away."},
	"second_wind": {"category":"RECOVERY", "copy":"Once per launch, recover from near spin-out."},
	"redline": {"category":"OVERDRIVE", "copy":"Burst beyond safe RPM. Hit hard. Burn spin."},
	"iron_comet": {"category":"RICOCHET", "copy":"Hard wall rebounds charge your next hit."},
	"dead_centre": {"category":"ANCHOR", "copy":"Hold the centre. Plant yourself. Resist heavy hits."},
	"afterimage": {"category":"MOBILITY", "copy":"High speed leaves dangerous pressure traces."},
	"chain_impact": {"category":"CHAIN", "copy":"Knockouts chain blasts. Heavy hit primes Burst."}
}
const CONDITIONS: Dictionary = {
	"impact_wake":"Heavy contact / 1.25 s cooldown",
	"second_wind":"Low spin or severe wobble / once per launch",
	"redline":"Burst at 35%+ spin / extra spin cost",
	"iron_comet":"Hard wall rebound / spend within 2 s",
	"dead_centre":"Controlled centre position / aggression or extreme force breaks Anchor",
	"afterimage":"High speed / each trace spends spin",
	"chain_impact":"Credited eliminations / heavy hit then Burst"
}
const DEFINITIONS: Dictionary = {
	"impact_wake": {"id":"impact_wake", "name":"Impact Wake", "description":"Heavy contacts send a pressure ring through nearby tops.", "short_label":"WAKE", "tags":["impact"], "icon":"", "active":true},
	"second_wind": {"id":"second_wind", "name":"Second Wind", "description":"Once each launch, near spin-out triggers a dramatic recovery.", "short_label":"WIND", "tags":["recovery"], "icon":"", "active":true},
	"redline": {"id":"redline", "name":"Redline", "description":"Burst drives beyond safe spin, then leaves you unstable.", "short_label":"RED", "tags":["burst", "risk"], "icon":"", "active":true},
	"iron_comet": {"id":"iron_comet", "name":"Iron Comet", "description":"A hard wall rebound charges your next real hit.", "short_label":"COMET", "tags":["wall", "impact"], "icon":"", "active":true},
	"dead_centre": {"id":"dead_centre", "name":"Dead Centre", "description":"Holding the centre builds an anchor that heavy hits can break.", "short_label":"CENTRE", "tags":["position", "defence"], "icon":"", "active":true},
	"afterimage": {"id":"afterimage", "name":"Afterimage", "description":"Fast movement leaves brief physical pressure traces.", "short_label":"ECHO", "tags":["mobility"], "icon":"", "active":true},
	"reversal": {"id":"reversal", "name":"Reversal", "description":"Brake after a hard unstable hit to turn recoil into recovery.", "short_label":"REV", "tags":["brake", "recovery"], "icon":"", "active":false},
	"chain_impact": {"id":"chain_impact", "name":"Chain Impact", "description":"Thrown tops chain pressure pulses; heavy duel hits prime a Burst follow-through.", "short_label":"CHAIN", "tags":["impact", "burst"], "icon":"", "active":true},
	"slip_gear": {"id":"slip_gear", "name":"Slip Gear", "description":"Brake, turn, then Burst to release stored momentum.", "short_label":"SLIP", "tags":["brake", "mobility"], "icon":"", "active":false},
	"rim_runner": {"id":"rim_runner", "name":"Rim Runner", "description":"Brake along a solid wall to ride its edge and choose your exit.", "short_label":"RIM", "tags":["brake", "wall"], "icon":"", "active":false},
	"flywheel_cache": {"id":"flywheel_cache", "name":"Flywheel Cache", "description":"Bank a little early spin and release it when reserve gets low.", "short_label":"CACHE", "tags":["reserve", "recovery"], "icon":"", "active":false},
	"crosscut": {"id":"crosscut", "name":"Crosscut", "description":"Steering through a glancing hit spends spin for a sideways shear.", "short_label":"CUT", "tags":["impact", "mobility"], "icon":"", "active":false}
}

const RANK_II: Dictionary = {
	"redline": {"name":"Redline II", "description":"A hotter overdrive: stronger acceleration and impacts, with sharper spin and wobble risk.", "card_copy":"Hotter Burst. Brutal hits. More spin and control risk.", "category":"HOT OVERDRIVE", "short_label":"RED II", "art_id":"redline_ii"},
	"dead_centre": {"name":"Dead Centre II", "description":"A deeper Anchor: plant harder, absorb recoil and make attackers feel the ground lock.", "card_copy":"Lock into the floor. Absorb recoil. Punish impacts.", "category":"GROUND LOCK", "short_label":"CENTRE II", "art_id":"dead_centre_ii"},
	"afterimage": {"name":"Afterimage II", "description":"Your route lasts longer and pushes crossing enemies harder, turning movement into arena control.", "card_copy":"Longer live routes. Stronger pressure on crossings.", "category":"LIVE ROUTE", "short_label":"ECHO II", "art_id":"afterimage_ii"}
}
const MUTATIONS: Dictionary = {
	"runaway": {"id":"runaway", "power_id":"redline", "name":"Runaway", "description":"Heavy hits sustain Redline and build a wilder overload. Keep hitting or lose the engine.", "card_copy":"Heavy hits sustain overload. Keep attacking to stay alive.", "category":"SUSTAINED OVERLOAD", "short_label":"RUNAWAY", "condition":"Heavy contacts during Redline / misses end the chain"},
	"breakneck": {"id":"breakneck", "power_id":"redline", "name":"Breakneck", "description":"Compress Redline into a short, violent charge with weak steering and a hard instability crash.", "card_copy":"Aim. Commit to a catastrophic charge. Recover the crash.", "category":"CATASTROPHIC CHARGE", "short_label":"BREAKNECK", "condition":"Burst at 35%+ spin / committed direction, then instability"},
	"bulwark": {"id":"bulwark", "power_id":"dead_centre", "name":"Bulwark", "description":"At full Anchor, become extraordinarily hard to move. Heavy attackers recoil from your planted machine.", "card_copy":"Plant fully. Refuse displacement. Throw attackers back.", "category":"IMMOVABLE DEFENCE", "short_label":"BULWARK", "condition":"Full Anchor / heavy incoming contacts"},
	"counterweight": {"id":"counterweight", "power_id":"dead_centre", "name":"Counterweight", "description":"Capture incoming force while Anchored, then Burst to release that stored force as retaliation.", "card_copy":"Anchor. Store incoming force. Burst to release it.", "category":"STORED RETALIATION", "short_label":"COUNTER", "condition":"Incoming force while Anchored / Burst releases storage"},
	"ghost_circuit": {"id":"ghost_circuit", "power_id":"afterimage", "name":"Ghost Circuit", "description":"Close a live route into a loop to energise the circuit and pressure the enclosed arena.", "card_copy":"Draw a fast loop. Close the circuit. Crush its interior.", "category":"CIRCUIT CLOSURE", "short_label":"CIRCUIT", "condition":"Close a live Afterimage loop / forgiving route closure"},
	"slipstream": {"id":"slipstream", "power_id":"afterimage", "name":"Slipstream", "description":"Re-enter your own live route to recover momentum and handling. Reuse crossings to power your movement.", "card_copy":"Cross your old route. Recover momentum. Go again.", "category":"ROUTE ENGINE", "short_label":"STREAM", "condition":"Re-enter or cross your own active Afterimage path"}
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
	if power.active:
		_apply_art(power, power_id)
		power["category"] = CARD_COPY[power_id].category
		power["card_copy"] = CARD_COPY[power_id].copy
	return power

static func max_rank(power_id: String) -> int:
	return 3 if power_id in VERTICAL_IDS else (1 if power_id in ACTIVE_IDS else 0)

static func investment_capacity() -> int:
	var capacity: int = 0
	for power_id: String in ACTIVE_IDS: capacity += max_rank(power_id)
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
	if not power_id in ACTIVE_IDS or rank < 1 or rank > max_rank(power_id): return {}
	if rank == 3:
		return get_mutation(mutation) if mutation in mutation_choices(power_id) else {}
	var power: Dictionary = get_power(power_id)
	if rank == 2:
		power.merge(RANK_II[power_id].duplicate(true), true)
		_apply_art(power, str(power.art_id))
	power.rank = rank
	return power

static func _apply_art(power: Dictionary, art_id: String) -> void:
	var escalation: bool = art_id in ESCALATION_ART_IDS
	power["art_id"] = art_id
	power["source_tag"] = art_id
	power["icon"] = ESCALATION_ICON_SHEET if escalation else ICON_SHEET
	power["icon_frame"] = ESCALATION_ART_IDS.find(art_id) if escalation else LEGACY_ART_IDS.find(art_id)
	power["card_texture"] = ESCALATION_CARD_SHEET if escalation else CARD_SHEET
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
